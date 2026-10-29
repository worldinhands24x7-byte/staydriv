import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/network_config.dart';
import '../../../core/socket_service.dart';
import '../models/in_app_notification_model.dart';

class NotificationInboxService {
  static final NotificationInboxService _instance = NotificationInboxService._internal();
  factory NotificationInboxService() => _instance;
  NotificationInboxService._internal();

  final ValueNotifier<List<InAppNotificationItem>> notificationsNotifier = ValueNotifier([]);
  final ValueNotifier<int> unreadCountNotifier = ValueNotifier(0);
  final ValueNotifier<InAppNotificationItem?> latestNotificationNotifier = ValueNotifier(null);

  String _role = 'customer';
  String? _phone;
  String? _uid;
  bool _isInitialized = false;

  Future<void> init({
    required String role,
    String? phone,
    String? uid,
  }) async {
    _role = role.toLowerCase().contains('pilot') || role.toLowerCase().contains('driver')
        ? 'partner'
        : 'customer';
    _phone = phone;
    _uid = uid;

    if (!_isInitialized) {
      SocketService().addInAppNotificationListener(_handleSocketNotification);
      _isInitialized = true;
    }

    await fetchInbox();
  }

  void _handleSocketNotification(Map<String, dynamic> data) {
    debugPrint('[NotificationInboxService] Live notification received: $data');
    try {
      final newItem = InAppNotificationItem.fromJson(data);

      // Check if already in list to avoid duplicates
      final currentList = List<InAppNotificationItem>.from(notificationsNotifier.value);
      final exists = currentList.any((n) => n.id == newItem.id);

      if (!exists) {
        currentList.insert(0, newItem);
        notificationsNotifier.value = currentList;
        unreadCountNotifier.value = currentList.where((n) => !n.isRead).length;
        latestNotificationNotifier.value = newItem;
      }
    } catch (e) {
      debugPrint('[NotificationInboxService] Error handling socket notification: $e');
    }
  }

  Future<void> fetchInbox() async {
    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/notifications/inbox').replace(
        queryParameters: {
          'role': _role,
          if (_phone != null && _phone!.isNotEmpty) 'phone': _phone!,
          if (_uid != null && _uid!.isNotEmpty) 'uid': _uid!,
          'limit': '50',
        },
      );

      final res = await http.get(uri).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['notifications'] is List) {
          final list = (data['notifications'] as List)
              .map((j) => InAppNotificationItem.fromJson(j as Map<String, dynamic>))
              .toList();

          notificationsNotifier.value = list;
          unreadCountNotifier.value = data['unreadCount'] is int
              ? data['unreadCount'] as int
              : list.where((n) => !n.isRead).length;

          if (data['latestNotification'] != null) {
            latestNotificationNotifier.value = InAppNotificationItem.fromJson(
              data['latestNotification'] as Map<String, dynamic>,
            );
          } else if (list.isNotEmpty) {
            latestNotificationNotifier.value = list.first;
          } else {
            latestNotificationNotifier.value = null;
          }
        }
      }
    } catch (e) {
      debugPrint('[NotificationInboxService] Error fetching inbox: $e');
    }
  }

  Future<void> markAsRead(String notificationId) async {
    // Optimistic UI update
    final currentList = List<InAppNotificationItem>.from(notificationsNotifier.value);
    final idx = currentList.indexWhere((n) => n.id == notificationId);
    if (idx != -1) {
      currentList[idx] = currentList[idx].copyWith(isRead: true);
      notificationsNotifier.value = currentList;
      unreadCountNotifier.value = currentList.where((n) => !n.isRead).length;

      if (latestNotificationNotifier.value?.id == notificationId) {
        latestNotificationNotifier.value = currentList[idx];
      }
    }

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/notifications/mark-read');
      await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'notificationId': notificationId,
          'phone': _phone,
          'uid': _uid,
          'role': _role,
        }),
      ).timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('[NotificationInboxService] Error marking as read: $e');
    }
  }

  Future<void> markAllAsRead() async {
    // Optimistic UI update
    final currentList = notificationsNotifier.value
        .map((n) => n.copyWith(isRead: true))
        .toList();
    notificationsNotifier.value = currentList;
    unreadCountNotifier.value = 0;
    if (latestNotificationNotifier.value != null) {
      latestNotificationNotifier.value = latestNotificationNotifier.value!.copyWith(isRead: true);
    }

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/notifications/mark-read');
      await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'markAll': true,
          'phone': _phone,
          'uid': _uid,
          'role': _role,
        }),
      ).timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('[NotificationInboxService] Error marking all as read: $e');
    }
  }
}
