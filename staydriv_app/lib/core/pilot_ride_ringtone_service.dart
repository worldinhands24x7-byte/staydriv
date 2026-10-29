import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'wake_lock_service.dart';
import 'js_stub.dart' if (dart.library.js) 'dart:js' as js;

/// Dedicated High-Priority Ride Booking Ringtone Service for StayDriv Pilots.
///
/// Ensures pilots hear a clear, continuous, audible ringtone when a new customer
/// ride booking arrives via Socket.IO, polling, or background notification.
///
/// Features:
/// - Distinctive, looping, audible incoming ride alert.
/// - Loop pulse timer to ensure continuous ringing across diverse Android devices & OEM ROMs.
/// - Haptic feedback pulse on native devices for tactile awareness.
/// - Deduplication to prevent multiple/restarted ringtones on socket reconnects or periodic syncs.
/// - Immediate silencing when booking is accepted, rejected, cancelled, or expired.
/// - 35-second safety auto-stop to prevent indefinite ringing if UI is interrupted.
class PilotRideRingtoneService {
  static final PilotRideRingtoneService _instance = PilotRideRingtoneService._internal();
  factory PilotRideRingtoneService() => _instance;
  PilotRideRingtoneService._internal();

  bool _isRinging = false;
  String? _currentBookingId;
  Timer? _loopPulseTimer;
  Timer? _safetyTimeoutTimer;

  final ValueNotifier<bool> isRingingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String?> currentBookingIdNotifier = ValueNotifier<String?>(null);

  bool get isRinging => _isRinging;
  String? get currentBookingId => _currentBookingId;

  /// Starts the audible incoming ride booking alert.
  /// If already ringing for this exact [bookingId], the call is safely ignored (deduplicated).
  void startRideAlert({
    required String bookingId,
    String? title,
    String? pickup,
  }) {
    if (bookingId.isEmpty) return;

    // Deduplication check: If already ringing for this exact booking, do not re-trigger
    if (_isRinging && _currentBookingId == bookingId) {
      debugPrint('[PilotRideRingtoneService] Booking $bookingId is already actively ringing. Deduplicated.');
      return;
    }

    debugPrint('[PilotRideRingtoneService] 🔔 Starting ride booking ringtone for booking: $bookingId');

    // Cancel any previous pulse or timeout
    _loopPulseTimer?.cancel();
    _safetyTimeoutTimer?.cancel();

    _isRinging = true;
    _currentBookingId = bookingId;
    isRingingNotifier.value = true;
    currentBookingIdNotifier.value = bookingId;

    // Wake screen and bring app to front on mobile
    WakeLockService.wakeUpScreen();
    WakeLockService.bringAppToForeground();

    // Initial audio pulse
    _playAudioPulse();

    // Continuous loop pulse timer (every 2.2 seconds) to keep audio active on native streams
    _loopPulseTimer = Timer.periodic(const Duration(milliseconds: 2200), (_) {
      if (_isRinging) {
        _playAudioPulse();
      }
    });

    // 35-second safety auto-timeout: if pilot neither accepts nor declines, automatically stop
    _safetyTimeoutTimer = Timer(const Duration(seconds: 35), () {
      if (_isRinging && _currentBookingId == bookingId) {
        debugPrint('[PilotRideRingtoneService] 35s countdown expired. Auto-stopping ringtone for $bookingId.');
        stopRideAlert(bookingId: bookingId);
      }
    });
  }

  /// Silences the ringtone immediately.
  /// If [bookingId] is specified, only stops if it matches the current ringing booking.
  void stopRideAlert({String? bookingId}) {
    if (bookingId != null && _currentBookingId != null && bookingId != _currentBookingId) {
      debugPrint('[PilotRideRingtoneService] Stop request for $bookingId ignored (active is $_currentBookingId).');
      return;
    }

    if (!_isRinging && _currentBookingId == null) {
      return;
    }

    debugPrint('[PilotRideRingtoneService] 🔕 Stopping ride booking ringtone (booking: $_currentBookingId)');

    _isRinging = false;
    _currentBookingId = null;
    _loopPulseTimer?.cancel();
    _loopPulseTimer = null;
    _safetyTimeoutTimer?.cancel();
    _safetyTimeoutTimer = null;

    isRingingNotifier.value = false;
    currentBookingIdNotifier.value = null;

    _stopAudioHardware();
    WakeLockService.dismissIncomingAlert();
  }

  void _playAudioPulse() {
    if (!_isRinging) return;

    if (kIsWeb) {
      try {
        js.context.callMethod('startStayDrivRinging');
      } catch (e) {
        debugPrint('[PilotRideRingtoneService] Web audio error: $e');
      }
    } else {
      try {
        HapticFeedback.heavyImpact();
        FlutterRingtonePlayer().play(
          android: AndroidSounds.ringtone,
          ios: IosSounds.electronic,
          looping: true,
          volume: 1.0,
          asAlarm: true,
        ).catchError((e) {
          debugPrint('[PilotRideRingtoneService] Ringtone player error: $e');
        });
      } catch (e) {
        debugPrint('[PilotRideRingtoneService] Audio pulse exception: $e');
      }
    }
  }

  void _stopAudioHardware() {
    if (kIsWeb) {
      try {
        js.context.callMethod('stopStayDrivRinging');
      } catch (e) {
        debugPrint('[PilotRideRingtoneService] Web stop error: $e');
      }
    } else {
      try {
        FlutterRingtonePlayer().stop().catchError((_) {});
      } catch (e) {
        debugPrint('[PilotRideRingtoneService] Native stop error: $e');
      }
    }
  }

  /// 4-second Test Buzzer allows pilot to test and verify incoming ringtone volume anytime
  void testRingtone() {
    startRideAlert(bookingId: 'TEST_${DateTime.now().millisecondsSinceEpoch}');
    Timer(const Duration(seconds: 4), () {
      stopRideAlert();
    });
  }
}
