import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api_client.dart';
import 'firebase_service.dart';
import 'network_config.dart';
import 'theme.dart';

enum CallDialogStatus {
  connecting,
  ringing,
  alreadyInProgress,
  failed,
}

class CallModalData {
  final CallDialogStatus status;
  final String virtualNumber;
  final String? realNumber;
  final String? message;
  final String? errorMessage;
  final bool isFallbackAvailable;

  CallModalData({
    required this.status,
    this.virtualNumber = '8065916303',
    this.realNumber,
    this.message,
    this.errorMessage,
    this.isFallbackAvailable = false,
  });

  CallModalData copyWith({
    CallDialogStatus? status,
    String? virtualNumber,
    String? realNumber,
    String? message,
    String? errorMessage,
    bool? isFallbackAvailable,
  }) {
    return CallModalData(
      status: status ?? this.status,
      virtualNumber: virtualNumber ?? this.virtualNumber,
      realNumber: realNumber ?? this.realNumber,
      message: message ?? this.message,
      errorMessage: errorMessage ?? this.errorMessage,
      isFallbackAvailable: isFallbackAvailable ?? this.isFallbackAvailable,
    );
  }
}

class CallMaskingResult {
  final bool success;
  final String status;
  final String message;
  final String? callId;
  final String? virtualNumber;
  final String? realNumber;
  final bool isFallback;
  final int? retryAfter;

  CallMaskingResult({
    required this.success,
    required this.status,
    required this.message,
    this.callId,
    this.virtualNumber,
    this.realNumber,
    this.isFallback = false,
    this.retryAfter,
  });
}

class CallMaskingService {
  static final CallMaskingService _instance = CallMaskingService._internal();
  factory CallMaskingService() => _instance;
  CallMaskingService._internal();

  final Set<String> _pendingCalls = {};
  static const String defaultVirtualNumber = '8065916303';

  /// Masks a phone number strictly in the format 98******21 (STEP 12)
  static String maskPhone(String? phone) {
    if (phone == null || phone.trim().isEmpty) return '******';
    String digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('91')) {
      digits = digits.substring(2);
    } else if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (digits.length > 10) {
      digits = digits.substring(digits.length - 10);
    }
    if (digits.length < 4) return '******';
    final first2 = digits.substring(0, 2);
    final last2 = digits.substring(digits.length - 2);
    return '$first2******$last2';
  }

  /// Directly opens the device dialer with the StayDriv masked virtual DID (Priority 1)
  static Future<void> launchDirectDial([String? virtualNumber]) async {
    final raw = virtualNumber ?? defaultVirtualNumber;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final fullNumber = digits.length == 10 ? '+91$digits' : (digits.startsWith('91') ? '+$digits' : digits);
    final uri = Uri.parse('tel:$fullNumber');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[CallMaskingService] launchDirectDial error: $e');
    }
  }

  /// Directly opens the device dialer with real phone number (Priority 2 Fallback)
  /// Also logs the fallback call to the backend and Admin console
  static Future<void> launchDirectPhoneCall({
    required String phone,
    String? bookingId,
    String? callerRole,
    String? reason,
  }) async {
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    final fullNumber = clean.length == 10 ? '+91$clean' : (clean.startsWith('91') ? '+$clean' : clean);

    // Log fallback call to backend if bookingId provided for Admin Console auditing
    if (bookingId != null && bookingId.isNotEmpty) {
      () async {
        try {
          final url = Uri.parse('${NetworkConfig.backendUrl}/api/bookings/$bookingId/call-direct-fallback');
          await ApiClient().post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'callerRole': callerRole ?? 'unknown',
              'reason': reason ?? 'USER_FALLBACK_DIAL',
            }),
            timeout: const Duration(seconds: 4),
          );
        } catch (e) {
          debugPrint('[CallMaskingService] launchDirectPhoneCall log error: $e');
        }
      }();
    }

    final uri = Uri.parse('tel:$fullNumber');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[CallMaskingService] launchDirectPhoneCall error: $e');
    }
  }

  /// Initiates masked call from Customer to Pilot (STEP 5 & 13)
  Future<CallMaskingResult> callPilot({
    required String bookingId,
    String? pilotName,
    BuildContext? context,
  }) async {
    final lockKey = 'pilot:$bookingId';
    if (_pendingCalls.contains(lockKey)) {
      final res = CallMaskingResult(
        success: true,
        status: 'ALREADY_IN_PROGRESS',
        virtualNumber: defaultVirtualNumber,
        message: 'Connecting call...',
      );
      if (context != null && context.mounted) {
        _showSnackBar(context, 'Call already in progress. Please check your phone.', isError: false);
      }
      return res;
    }

    _pendingCalls.add(lockKey);

    final stateNotifier = ValueNotifier<CallModalData>(
      CallModalData(
        status: CallDialogStatus.connecting,
        virtualNumber: defaultVirtualNumber,
        message: 'Connecting via Tata Smartflo...',
      ),
    );

    if (context != null && context.mounted) {
      _showCallModal(
        context: context,
        title: 'Call Pilot',
        contactName: pilotName ?? 'StayDriv Pilot',
        bookingId: bookingId,
        callerRole: 'CUSTOMER',
        stateNotifier: stateNotifier,
      );
    }

    try {
      final url = Uri.parse('${NetworkConfig.backendUrl}/api/bookings/$bookingId/call-pilot');
      final response = await ApiClient().post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({}),
        timeout: const Duration(seconds: 15),
      );

      final data = jsonDecode(response.body);
      final returnedDid = (data['virtualNumber'] as String?)?.isNotEmpty == true
          ? data['virtualNumber'] as String
          : defaultVirtualNumber;
      final realPhone = data['realPhone'] as String?;
      final isFallbackMode = data['fallbackMode'] == true || data['status'] == 'FALLBACK_TO_REAL_NUMBER';

      if (response.statusCode == 200 || response.statusCode == 201) {
        final status = data['status'] ?? 'CALL_INITIATED';

        if (status == 'ALREADY_IN_PROGRESS') {
          stateNotifier.value = stateNotifier.value.copyWith(
            status: CallDialogStatus.alreadyInProgress,
            virtualNumber: returnedDid,
            realNumber: realPhone,
            isFallbackAvailable: realPhone != null,
            message: 'Call already initiated. Tata Smartflo is ringing your phone.',
          );
          return CallMaskingResult(
            success: true,
            status: 'ALREADY_IN_PROGRESS',
            message: 'Call already in progress',
            virtualNumber: returnedDid,
            realNumber: realPhone,
            callId: data['callId'],
          );
        }

        stateNotifier.value = stateNotifier.value.copyWith(
          status: CallDialogStatus.ringing,
          virtualNumber: returnedDid,
          realNumber: realPhone,
          isFallbackAvailable: realPhone != null,
          message: 'Tata Smartflo is ringing your phone right now.',
        );

        if (context != null && context.mounted) {
          _showSnackBar(context, 'Connecting call... Please answer your phone.', isError: false);
        }

        return CallMaskingResult(
          success: true,
          status: 'CALL_INITIATED',
          message: 'Call connected',
          virtualNumber: returnedDid,
          realNumber: realPhone,
          callId: data['callId'],
        );
      } else {
        final msg = data['message'] ?? 'Unable to connect automated call. You can dial directly.';
        stateNotifier.value = stateNotifier.value.copyWith(
          status: CallDialogStatus.failed,
          virtualNumber: returnedDid,
          realNumber: realPhone,
          isFallbackAvailable: realPhone != null,
          errorMessage: isFallbackMode
              ? 'Tata Smartflo call masking is temporarily unavailable. Direct real number calling is enabled below.'
              : msg,
        );
        return CallMaskingResult(
          success: false,
          status: isFallbackMode ? 'FALLBACK_TO_REAL_NUMBER' : 'FAILED',
          virtualNumber: returnedDid,
          realNumber: realPhone,
          isFallback: isFallbackMode,
          message: msg,
        );
      }
    } catch (e) {
      debugPrint('[CallMaskingService] callPilot error: $e');
      stateNotifier.value = stateNotifier.value.copyWith(
        status: CallDialogStatus.failed,
        virtualNumber: defaultVirtualNumber,
        isFallbackAvailable: true,
        errorMessage: 'Network issue connecting to carrier. Direct dial options available below.',
      );
      return CallMaskingResult(
        success: false,
        status: 'NETWORK_ERROR',
        virtualNumber: defaultVirtualNumber,
        isFallback: true,
        message: 'Unable to connect via PBX. Direct dialing available.',
      );
    } finally {
      Future.delayed(const Duration(seconds: 8), () {
        _pendingCalls.remove(lockKey);
      });
    }
  }

  /// Initiates masked call from Pilot to Customer (STEP 6 & 13)
  Future<CallMaskingResult> callCustomer({
    required String bookingId,
    String? customerName,
    BuildContext? context,
  }) async {
    final lockKey = 'customer:$bookingId';
    if (_pendingCalls.contains(lockKey)) {
      final res = CallMaskingResult(
        success: true,
        status: 'ALREADY_IN_PROGRESS',
        virtualNumber: defaultVirtualNumber,
        message: 'Connecting call...',
      );
      if (context != null && context.mounted) {
        _showSnackBar(context, 'Call already in progress. Please check your phone.', isError: false);
      }
      return res;
    }

    _pendingCalls.add(lockKey);

    final stateNotifier = ValueNotifier<CallModalData>(
      CallModalData(
        status: CallDialogStatus.connecting,
        virtualNumber: defaultVirtualNumber,
        message: 'Connecting via Tata Smartflo...',
      ),
    );

    if (context != null && context.mounted) {
      _showCallModal(
        context: context,
        title: 'Call Customer',
        contactName: customerName ?? 'Customer',
        bookingId: bookingId,
        callerRole: 'PILOT',
        stateNotifier: stateNotifier,
      );
    }

    try {
      final url = Uri.parse('${NetworkConfig.backendUrl}/api/bookings/$bookingId/call-customer');
      final response = await ApiClient().post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({}),
        timeout: const Duration(seconds: 15),
      );

      final data = jsonDecode(response.body);
      final returnedDid = (data['virtualNumber'] as String?)?.isNotEmpty == true
          ? data['virtualNumber'] as String
          : defaultVirtualNumber;
      final realPhone = data['realPhone'] as String?;
      final isFallbackMode = data['fallbackMode'] == true || data['status'] == 'FALLBACK_TO_REAL_NUMBER';

      if (response.statusCode == 200 || response.statusCode == 201) {
        final status = data['status'] ?? 'CALL_INITIATED';

        if (status == 'ALREADY_IN_PROGRESS') {
          stateNotifier.value = stateNotifier.value.copyWith(
            status: CallDialogStatus.alreadyInProgress,
            virtualNumber: returnedDid,
            realNumber: realPhone,
            isFallbackAvailable: realPhone != null,
            message: 'Call already initiated. Tata Smartflo is ringing your phone.',
          );
          return CallMaskingResult(
            success: true,
            status: 'ALREADY_IN_PROGRESS',
            message: 'Call already in progress',
            virtualNumber: returnedDid,
            realNumber: realPhone,
            callId: data['callId'],
          );
        }

        stateNotifier.value = stateNotifier.value.copyWith(
          status: CallDialogStatus.ringing,
          virtualNumber: returnedDid,
          realNumber: realPhone,
          isFallbackAvailable: realPhone != null,
          message: 'Tata Smartflo is ringing your phone right now.',
        );

        if (context != null && context.mounted) {
          _showSnackBar(context, 'Connecting call... Please answer your phone.', isError: false);
        }

        return CallMaskingResult(
          success: true,
          status: 'CALL_INITIATED',
          message: 'Call connected',
          virtualNumber: returnedDid,
          realNumber: realPhone,
          callId: data['callId'],
        );
      } else {
        final msg = data['message'] ?? 'Unable to connect automated call. You can dial directly.';
        stateNotifier.value = stateNotifier.value.copyWith(
          status: CallDialogStatus.failed,
          virtualNumber: returnedDid,
          realNumber: realPhone,
          isFallbackAvailable: realPhone != null,
          errorMessage: isFallbackMode
              ? 'Tata Smartflo call masking is temporarily unavailable. Direct real number calling is enabled below.'
              : msg,
        );
        return CallMaskingResult(
          success: false,
          status: isFallbackMode ? 'FALLBACK_TO_REAL_NUMBER' : 'FAILED',
          virtualNumber: returnedDid,
          realNumber: realPhone,
          isFallback: isFallbackMode,
          message: msg,
        );
      }
    } catch (e) {
      debugPrint('[CallMaskingService] callCustomer error: $e');
      stateNotifier.value = stateNotifier.value.copyWith(
        status: CallDialogStatus.failed,
        virtualNumber: defaultVirtualNumber,
        isFallbackAvailable: true,
        errorMessage: 'Network issue connecting to carrier. Direct dial options available below.',
      );
      return CallMaskingResult(
        success: false,
        status: 'NETWORK_ERROR',
        virtualNumber: defaultVirtualNumber,
        isFallback: true,
        message: 'Unable to connect via PBX. Direct dialing available.',
      );
    } finally {
      Future.delayed(const Duration(seconds: 8), () {
        _pendingCalls.remove(lockKey);
      });
    }
  }

  /// Checks active call session status for a booking
  Future<Map<String, dynamic>> getCallStatus(String bookingId) async {
    try {
      final url = Uri.parse('${NetworkConfig.backendUrl}/api/bookings/$bookingId/call-status');
      final response = await ApiClient().get(url, timeout: const Duration(seconds: 6));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('[CallMaskingService] getCallStatus error: $e');
    }
    return {'hasActiveCall': false};
  }

  /// Initiates masked call for Food Orders across Customer, Pilot, and Restaurant (ALL 6 FLOWS)
  Future<CallMaskingResult> callFoodOrder({
    required String orderId,
    required String callerRole, // 'customer', 'pilot', 'restaurant'
    required String targetRole, // 'customer', 'pilot', 'restaurant'
    String? contactName,
    BuildContext? context,
  }) async {
    final lockKey = 'food:$orderId:${callerRole}_to_$targetRole';
    if (_pendingCalls.contains(lockKey)) {
      final res = CallMaskingResult(
        success: true,
        status: 'ALREADY_IN_PROGRESS',
        virtualNumber: defaultVirtualNumber,
        message: 'Connecting call...',
      );
      if (context != null && context.mounted) {
        _showSnackBar(context, 'Call already in progress. Please check your phone.', isError: false);
      }
      return res;
    }

    _pendingCalls.add(lockKey);

    String displayTitle;
    if (callerRole == 'customer') {
      displayTitle = targetRole == 'pilot' ? 'Call Delivery Pilot' : 'Call Restaurant';
    } else if (callerRole == 'pilot') {
      displayTitle = targetRole == 'customer' ? 'Call Customer' : 'Call Restaurant';
    } else {
      displayTitle = targetRole == 'customer' ? 'Call Customer' : 'Call Delivery Pilot';
    }

    final stateNotifier = ValueNotifier<CallModalData>(
      CallModalData(
        status: CallDialogStatus.connecting,
        virtualNumber: defaultVirtualNumber,
        message: 'Connecting via Tata Smartflo...',
      ),
    );

    if (context != null && context.mounted) {
      _showCallModal(
        context: context,
        title: displayTitle,
        contactName: contactName ?? (targetRole == 'pilot' ? 'StayDriv Pilot' : (targetRole == 'restaurant' ? 'Restaurant' : 'Customer')),
        bookingId: orderId,
        callerRole: callerRole.toUpperCase(),
        stateNotifier: stateNotifier,
      );
    }

    try {
      final rawUid = FirebaseService().currentUid ?? '';
      final url = Uri.parse('${NetworkConfig.backendUrl}/api/food/orders/$orderId/call');
      final response = await ApiClient().post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'callerUserId': rawUid,
          'callerRole': callerRole,
          'targetRole': targetRole,
        }),
        timeout: const Duration(seconds: 15),
      );

      final data = jsonDecode(response.body);
      final returnedDid = (data['virtualNumber'] as String?)?.isNotEmpty == true
          ? data['virtualNumber'] as String
          : defaultVirtualNumber;

      if (response.statusCode == 200 || response.statusCode == 201) {
        final status = data['status'] ?? 'CALL_INITIATED';

        if (status == 'ALREADY_IN_PROGRESS') {
          stateNotifier.value = stateNotifier.value.copyWith(
            status: CallDialogStatus.alreadyInProgress,
            virtualNumber: returnedDid,
            message: 'Call already initiated. Tata Smartflo is ringing your phone.',
          );
          return CallMaskingResult(
            success: true,
            status: 'ALREADY_IN_PROGRESS',
            message: 'Call already in progress',
            virtualNumber: returnedDid,
            callId: data['callId'],
          );
        }

        stateNotifier.value = stateNotifier.value.copyWith(
          status: CallDialogStatus.ringing,
          virtualNumber: returnedDid,
          message: 'Tata Smartflo is ringing your phone right now. Answer to speak.',
        );

        if (context != null && context.mounted) {
          _showSnackBar(context, 'Connecting call... Please answer your phone.', isError: false);
        }

        return CallMaskingResult(
          success: true,
          status: 'CALL_INITIATED',
          message: 'Call connected',
          virtualNumber: returnedDid,
          callId: data['callId'],
        );
      } else {
        final msg = data['message'] ?? 'Unable to connect call via Tata Smartflo.';
        stateNotifier.value = stateNotifier.value.copyWith(
          status: CallDialogStatus.failed,
          virtualNumber: returnedDid,
          errorMessage: msg,
        );
        return CallMaskingResult(
          success: false,
          status: 'FAILED',
          virtualNumber: returnedDid,
          message: msg,
        );
      }
    } catch (e) {
      debugPrint('[CallMaskingService] callFoodOrder error: $e');
      stateNotifier.value = stateNotifier.value.copyWith(
        status: CallDialogStatus.failed,
        virtualNumber: defaultVirtualNumber,
        errorMessage: 'Network issue connecting to carrier. Please try again.',
      );
      return CallMaskingResult(
        success: false,
        status: 'NETWORK_ERROR',
        virtualNumber: defaultVirtualNumber,
        message: 'Unable to connect via PBX.',
      );
    } finally {
      Future.delayed(const Duration(seconds: 8), () {
        _pendingCalls.remove(lockKey);
      });
    }
  }

  void _showSnackBar(BuildContext context, String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.inter(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? AppTheme.errorColor : const Color(0xFF15803D),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showCallModal({
    required BuildContext context,
    required String title,
    required String contactName,
    required ValueNotifier<CallModalData> stateNotifier,
    String? bookingId,
    String? callerRole,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _CallConnectingDialog(
        title: title,
        contactName: contactName,
        stateNotifier: stateNotifier,
        bookingId: bookingId,
        callerRole: callerRole,
      ),
    );
  }
}

class _CallConnectingDialog extends StatefulWidget {
  final String title;
  final String contactName;
  final ValueNotifier<CallModalData> stateNotifier;
  final String? bookingId;
  final String? callerRole;

  const _CallConnectingDialog({
    required this.title,
    required this.contactName,
    required this.stateNotifier,
    this.bookingId,
    this.callerRole,
  });

  @override
  State<_CallConnectingDialog> createState() => _CallConnectingDialogState();
}

class _CallConnectingDialogState extends State<_CallConnectingDialog> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _formatDid(String did) {
    final clean = did.replaceAll(RegExp(r'\D'), '');
    if (clean.length == 10) {
      return '+91 ${clean.substring(0, 4)} ${clean.substring(4, 7)} ${clean.substring(7)}';
    }
    return '+91 $did';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CallModalData>(
      valueListenable: widget.stateNotifier,
      builder: (context, data, child) {
        final isFailed = data.status == CallDialogStatus.failed;
        final isRinging = data.status == CallDialogStatus.ringing || data.status == CallDialogStatus.alreadyInProgress;
        final didFormatted = _formatDid(data.virtualNumber);

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: isFailed ? Colors.redAccent.withValues(alpha: 0.3) : const Color(0xFF3B82F6).withValues(alpha: 0.25),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: isFailed ? Colors.red.withValues(alpha: 0.2) : const Color(0xFF1E3A8A).withValues(alpha: 0.4),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top header badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isFailed ? Icons.warning_amber_rounded : Icons.shield_rounded,
                      color: isFailed ? Colors.amberAccent : const Color(0xFF60A5FA),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'TATA SMARTFLO CALL MASKING',
                      style: GoogleFonts.robotoMono(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isFailed ? Colors.amberAccent : const Color(0xFF93C5FD),
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Pulsing Icon
                Stack(
                  alignment: Alignment.center,
                  children: [
                    if (!isFailed)
                      ...List.generate(2, (index) {
                        return AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            final progress = (_pulseController.value + (index / 2)) % 1.0;
                            final ringColor = isRinging ? const Color(0xFF10B981) : const Color(0xFF2563EB);
                            return Container(
                              width: 80 + (progress * 45),
                              height: 80 + (progress * 45),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: ringColor.withValues(alpha: (1.0 - progress) * 0.25),
                              ),
                            );
                          },
                        );
                      }),
                    Container(
                      width: 74,
                      height: 74,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: isFailed
                              ? [const Color(0xFFEF4444), const Color(0xFFB91C1C)]
                              : (isRinging
                                  ? [const Color(0xFF10B981), const Color(0xFF047857)]
                                  : [const Color(0xFF2563EB), const Color(0xFF1D4ED8)]),
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (isRinging ? const Color(0xFF10B981) : const Color(0xFF2563EB)).withValues(alpha: 0.35),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        isFailed ? Icons.phone_disabled_rounded : Icons.phone_in_talk_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Contact Name
                Text(
                  widget.contactName,
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),

                // Privacy badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline, size: 12, color: Color(0xFF93C5FD)),
                      const SizedBox(width: 4),
                      Text(
                        'Phone Numbers Masked & 100% Private',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF93C5FD),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Guidance Box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isFailed ? Colors.red.withValues(alpha: 0.12) : const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isFailed ? Colors.redAccent.withValues(alpha: 0.25) : Colors.white12,
                    ),
                  ),
                  child: Column(
                    children: [
                      if (isRinging) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF10B981),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'INCOMING CALL IN PROGRESS',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF34D399),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tata Smartflo will ring your phone from:',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            didFormatted,
                            style: GoogleFonts.robotoMono(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF60A5FA),
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Please ANSWER your phone when it rings to connect with your ride partner.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ] else if (isFailed) ...[
                        Text(
                          data.errorMessage ?? 'Automated callback unavailable.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFFFCA5A5),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No problem! You can call directly using our secure virtual line below:',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ] else ...[
                        Text(
                          'Connecting call via Tata Smartflo...\nYour phone will ring momentarily from our secure number.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.white70,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // 1. DIRECT DIAL VIA MASKED DID (Priority 1)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      CallMaskingService.launchDirectDial(data.virtualNumber);
                    },
                    icon: const Icon(Icons.shield_outlined, color: Colors.white, size: 19),
                    label: Text(
                      'Dial Masked Line ($didFormatted)',
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      elevation: 4,
                      shadowColor: const Color(0xFF10B981).withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),

                // 2. DIRECT REAL NUMBER CALL FALLBACK (Priority 2)
                if (data.realNumber != null && data.realNumber!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        CallMaskingService.launchDirectPhoneCall(
                          phone: data.realNumber!,
                          bookingId: widget.bookingId,
                          callerRole: widget.callerRole,
                          reason: 'MANUAL_FALLBACK_DIAL',
                        );
                      },
                      icon: const Icon(Icons.phone_forwarded_rounded, color: Colors.white, size: 19),
                      label: Text(
                        'Dial Real Number (${CallMaskingService.maskPhone(data.realNumber)})',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD97706),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        elevation: 4,
                        shadowColor: const Color(0xFFD97706).withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '⚠️ Priority 2 Fallback: If Smartflo PBX is busy, dial partner real number directly. Admin tracking enabled.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: const Color(0xFFFCD34D),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 10),

                // Dismiss Button
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.06),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      'Dismiss',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
