import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service to keep StayDriv active when the app is minimized or screen is locked
/// Ensures Pilots & Customers continue receiving incoming requests, live tracking, and ride status.
class WakeLockService {
  static const MethodChannel _channel = MethodChannel('com.staydriv.app/wake_lock');

  static bool _isWakeLockActive = false;

  /// Acquires Android CPU WakeLock to prevent the OS from freezing network/polling while minimized or screen locked
  static Future<void> acquireWakeLock() async {
    if (kIsWeb) return;
    try {
      if (!_isWakeLockActive) {
        await _channel.invokeMethod('acquireWakeLock');
        _isWakeLockActive = true;
        debugPrint('[WakeLockService] CPU WakeLock acquired (Background Keep-Alive Active)');
      }
    } catch (e) {
      debugPrint('[WakeLockService] Error acquiring wake lock: $e');
    }
  }

  /// Releases CPU WakeLock when the pilot goes offline or ride concludes (saves battery)
  static Future<void> releaseWakeLock() async {
    if (kIsWeb) return;
    try {
      if (_isWakeLockActive) {
        await _channel.invokeMethod('releaseWakeLock');
        _isWakeLockActive = false;
        debugPrint('[WakeLockService] CPU WakeLock released (Normal Power Mode)');
      }
    } catch (e) {
      debugPrint('[WakeLockService] Error releasing wake lock: $e');
    }
  }

  /// Turns on the screen and shows the incoming booking alert over the lock screen
  static Future<void> wakeUpScreen() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('wakeUpScreen');
      debugPrint('[WakeLockService] Screen wake-up triggered for incoming booking / alert!');
    } catch (e) {
      debugPrint('[WakeLockService] Error waking up screen: $e');
    }
  }

  /// Checks if app is whitelisted from Android battery optimizations
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (kIsWeb) return true;
    try {
      final bool isIgnored = await _channel.invokeMethod('isIgnoringBatteryOptimizations') ?? false;
      return isIgnored;
    } catch (e) {
      debugPrint('[WakeLockService] Error checking battery optimizations: $e');
      return false;
    }
  }

  /// Requests user permission to exempt StayDriv from battery saver (prevents Android OS from killing app in background)
  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (kIsWeb) return;
    try {
      final bool alreadyIgnored = await isIgnoringBatteryOptimizations();
      if (!alreadyIgnored) {
        await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
        debugPrint('[WakeLockService] Prompted user to exempt StayDriv from battery optimization');
      }
    } catch (e) {
      debugPrint('[WakeLockService] Error requesting battery exemption: $e');
    }
  }
}
