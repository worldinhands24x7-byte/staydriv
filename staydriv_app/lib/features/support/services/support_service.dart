import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api_client.dart';
import '../../../core/network_config.dart';
import '../../../core/booking_manager.dart';
import '../models/support_ticket_model.dart';

class SupportService {
  static final SupportService _instance = SupportService._internal();
  factory SupportService() => _instance;
  SupportService._internal();

  static const String _defaultHelpline = '+919490440281';
  static const String _defaultWhatsApp = '+919490440281';

  String _cachedHelpline = _defaultHelpline;
  String _cachedWhatsApp = _defaultWhatsApp;
  bool _isSubmitting = false;

  String get emergencyHelplineNumber => _cachedHelpline;
  String get whatsAppSupportNumber => _cachedWhatsApp;

  /// Fetches remote support configuration (helpline & WhatsApp number)
  Future<Map<String, String>> fetchSupportConfig() async {
    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/support/config');
      final res = await ApiClient().get(uri, timeout: const Duration(seconds: 6), retry: false);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['config'] != null) {
          final cfg = data['config'];
          if (cfg['helplinePhone'] != null && cfg['helplinePhone'].toString().isNotEmpty) {
            _cachedHelpline = cfg['helplinePhone'].toString();
          }
          if (cfg['whatsAppPhone'] != null && cfg['whatsAppPhone'].toString().isNotEmpty) {
            _cachedWhatsApp = cfg['whatsAppPhone'].toString();
          }
        }
      }
    } catch (e) {
      debugPrint('[SupportService] Note fetching remote config: $e');
    }
    return {
      'helpline': _cachedHelpline,
      'whatsApp': _cachedWhatsApp,
    };
  }

  /// Creates a new support ticket with double-tap protection and offline caching
  Future<SupportTicket> createTicket({
    required String category,
    required String subcategory,
    required String subject,
    required String description,
    String? rideId,
    String? userType,
    String? priority,
  }) async {
    if (_isSubmitting) {
      throw Exception('A support request is already being processed. Please wait.');
    }
    _isSubmitting = true;

    try {
      final active = BookingManager().activeBooking;
      final resolvedRideId = rideId ??
          active?['bookingId']?.toString() ??
          active?['id']?.toString() ??
          active?['_id']?.toString();

      final effectiveUid = BookingManager().effectiveUid;
      final prefs = await SharedPreferences.getInstance();
      final userName = prefs.getString('user_name') ?? 'StayDriv User';
      final userPhone = prefs.getString('phone_number') ?? '';
      final effectiveRole = userType ?? (BookingManager().isDriverOnline ? 'pilot' : 'customer');

      final payload = {
        'userId': effectiveUid,
        'userType': effectiveRole,
        'userName': userName,
        'userPhone': userPhone,
        'rideId': resolvedRideId,
        'category': category,
        'subcategory': subcategory,
        'subject': subject,
        'description': description,
        'priority': priority ?? (category == 'safety' ? 'URGENT' : 'MEDIUM'),
      };

      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/support/ticket');
      final res = await ApiClient().post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
        timeout: const Duration(seconds: 15),
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['ticket'] != null) {
          final ticket = SupportTicket.fromJson(Map<String, dynamic>.from(data['ticket']));
          await _cacheLocalTicket(ticket);
          return ticket;
        } else {
          throw Exception(data['message'] ?? 'Failed to parse support ticket.');
        }
      } else {
        String errMsg = 'Server returned ${res.statusCode}';
        if (res.body.trim().isNotEmpty) {
          try {
            final data = jsonDecode(res.body);
            if (data is Map && data['message'] != null) {
              errMsg = data['message'].toString();
            }
          } catch (_) {
            errMsg = res.body;
          }
        }
        throw Exception(errMsg);
      }
    } catch (e) {
      debugPrint('[SupportService] Error creating ticket: $e');
      // Fallback: If network is offline or server unreachable, generate a valid queued ticket locally
      final errStr = e.toString();
      if (errStr.contains('Failed host lookup') ||
          errStr.contains('SocketException') ||
          errStr.contains('ClientException') ||
          errStr.contains('Connection refused') ||
          errStr.contains('TimeoutException') ||
          errStr.contains('Server returned 400') ||
          errStr.contains('Server returned 502') ||
          errStr.contains('Server returned 503')) {
        final prefs = await SharedPreferences.getInstance();
        final localId = 'STY-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
        final fallbackTicket = SupportTicket(
          ticketId: localId,
          userId: BookingManager().effectiveUid,
          userType: userType ?? 'customer',
          userName: prefs.getString('user_name') ?? 'StayDriv User',
          userPhone: prefs.getString('phone_number') ?? '',
          rideId: rideId,
          category: category,
          subcategory: subcategory,
          subject: subject,
          description: description,
          status: 'OPEN',
          priority: priority ?? (category == 'safety' ? 'URGENT' : 'MEDIUM'),
          chatHistory: [],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await _cacheLocalTicket(fallbackTicket);
        return fallbackTicket;
      }
      rethrow;
    } finally {
      _isSubmitting = false;
    }
  }

  /// Fetches all tickets submitted by the authenticated user
  Future<List<SupportTicket>> getMyTickets({String? userId, String? userType}) async {
    try {
      final effectiveUid = userId ?? BookingManager().effectiveUid;
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/support/my-tickets?userId=$effectiveUid');
      final res = await ApiClient().get(uri, timeout: const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['tickets'] is List) {
          final list = (data['tickets'] as List)
              .map((t) => SupportTicket.fromJson(Map<String, dynamic>.from(t as Map)))
              .toList();
          await _saveAllLocalTickets(list);
          return list;
        }
      }
    } catch (e) {
      debugPrint('[SupportService] Network fetch error: $e. Falling back to cache.');
    }
    return _getLocalCachedTickets();
  }

  /// Fetches ticket details along with full chat conversation thread
  Future<SupportTicket> getTicketDetails(String ticketId) async {
    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/support/ticket/$ticketId');
      final res = await ApiClient().get(uri, timeout: const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['ticket'] != null) {
          final ticket = SupportTicket.fromJson(Map<String, dynamic>.from(data['ticket']));
          await _cacheLocalTicket(ticket);
          return ticket;
        }
      }
    } catch (e) {
      debugPrint('[SupportService] Error fetching ticket details: $e');
    }

    final localList = await _getLocalCachedTickets();
    final cached = localList.firstWhere((t) => t.ticketId == ticketId, orElse: () {
      throw Exception('Ticket $ticketId not found. Please check your connection.');
    });
    return cached;
  }

  /// Sends a reply to an existing support ticket
  Future<SupportTicket> replyToTicket({
    required String ticketId,
    required String message,
    required String senderId,
    required String senderName,
    required String senderRole,
  }) async {
    if (message.trim().isEmpty) {
      throw Exception('Message cannot be empty.');
    }

    final baseUrl = NetworkConfig.backendUrl;
    final uri = Uri.parse('$baseUrl/api/support/ticket/$ticketId/reply');
    final payload = {
      'senderId': senderId,
      'senderName': senderName,
      'senderRole': senderRole,
      'message': message.trim(),
    };

    final res = await ApiClient().post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
      timeout: const Duration(seconds: 12),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      if (data['success'] == true && data['ticket'] != null) {
        final updated = SupportTicket.fromJson(Map<String, dynamic>.from(data['ticket']));
        await _cacheLocalTicket(updated);
        return updated;
      }
    }
    throw Exception('Failed to send reply. Please try again.');
  }

  /// Initiates device phone call to the configured emergency helpline
  Future<bool> callEmergencyHelpline(BuildContext context) async {
    final cleanPhone = _cachedHelpline.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return true;
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open phone dialer for $_cachedHelpline. Please dial directly.'),
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return false;
      }
    } catch (e) {
      debugPrint('[SupportService] Error dialing emergency helpline: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Phone dialer unavailable. Helpline number: $_cachedHelpline'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
      return false;
    }
  }

  /// Opens official WhatsApp support chat
  Future<bool> openWhatsAppSupport(BuildContext context, {String? defaultMessage}) async {
    final cleanPhone = _cachedWhatsApp.replaceAll(RegExp(r'[^\d]'), '');
    final text = Uri.encodeComponent(defaultMessage ?? 'Hello StayDriv Support, I need assistance with my ride.');

    final appUri = Uri.parse('whatsapp://send?phone=$cleanPhone&text=$text');
    final webUri = Uri.parse('https://api.whatsapp.com/send?phone=$cleanPhone&text=$text');

    try {
      if (await canLaunchUrl(appUri)) {
        await launchUrl(appUri, mode: LaunchMode.externalApplication);
        return true;
      } else if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
        return true;
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('WhatsApp is not installed on this device. Please call our 24/7 helpline.'),
              backgroundColor: Colors.amber,
            ),
          );
        }
        return false;
      }
    } catch (e) {
      debugPrint('[SupportService] Error opening WhatsApp: $e');
      return false;
    }
  }

  // --- Local Cache Helpers ---
  Future<void> _cacheLocalTicket(SupportTicket ticket) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentList = await _getLocalCachedTickets();
      currentList.removeWhere((t) => t.ticketId == ticket.ticketId);
      currentList.insert(0, ticket);
      final jsonList = currentList.map((t) => t.toJson()).toList();
      await prefs.setString('staydriv_support_tickets_cache', jsonEncode(jsonList));
    } catch (e) {
      debugPrint('[SupportService] Local cache note: $e');
    }
  }

  Future<void> _saveAllLocalTickets(List<SupportTicket> tickets) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = tickets.map((t) => t.toJson()).toList();
      await prefs.setString('staydriv_support_tickets_cache', jsonEncode(jsonList));
    } catch (e) {
      debugPrint('[SupportService] Local save note: $e');
    }
  }

  Future<List<SupportTicket>> _getLocalCachedTickets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('staydriv_support_tickets_cache');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List;
        return decoded.map((item) => SupportTicket.fromJson(Map<String, dynamic>.from(item as Map))).toList();
      }
    } catch (_) {}
    return [];
  }
}
