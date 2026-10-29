import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Service to keep StayDriv active when the app is minimized or screen is locked
/// Ensures Pilots & Customers continue receiving incoming requests, live tracking, and ride status.
class WakeLockService {
  static const MethodChannel _channel = MethodChannel('com.staydriv.app/wake_lock');

  static bool _isWakeLockActive = false;
  static bool _isChannelHandlerSet = false;
  static void Function(String action, String? bookingId)? _bookingActionListener;
  static void Function(bool isInPip)? _pipModeListener;

  /// Registers a callback for quick actions performed on notifications (accept, view, decline)
  static void setBookingActionListener(void Function(String action, String? bookingId)? listener) {
    _bookingActionListener = listener;
    _initChannelHandler();
  }

  /// Sets a listener for Android Picture-in-Picture mode transitions
  static void setPipModeListener(void Function(bool isInPip)? listener) {
    _pipModeListener = listener;
    _initChannelHandler();
  }

  static void _initChannelHandler() {
    if (_isChannelHandlerSet || kIsWeb) return;
    _isChannelHandlerSet = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onBookingActionReceived') {
        final Map? args = call.arguments is Map ? call.arguments as Map : null;
        final action = args?['action']?.toString() ?? 'view';
        final bookingId = args?['bookingId']?.toString();
        debugPrint('[WakeLockService] Notification action received: $action (bookingId: $bookingId)');
        _bookingActionListener?.call(action, bookingId);
      } else if (call.method == 'onPipModeChanged') {
        final bool inPip = call.arguments == true;
        debugPrint('[WakeLockService] PiP mode changed: $inPip');
        _pipModeListener?.call(inPip);
      }
    });
  }

  /// Enables or disables automatic entry into Picture-in-Picture when app is minimized during active navigation
  static Future<void> enableAutoPip(bool enabled) async {
    if (kIsWeb) return;
    try {
      _initChannelHandler();
      await _channel.invokeMethod('enableAutoPip', {'enabled': enabled});
      debugPrint('[WakeLockService] Auto PiP ${enabled ? "enabled" : "disabled"}');
    } catch (e) {
      debugPrint('[WakeLockService] Error toggling auto PiP: $e');
    }
  }

  /// Programmatically triggers Android Picture-in-Picture mode
  static Future<bool> enterPipMode() async {
    if (kIsWeb) return false;
    try {
      _initChannelHandler();
      final bool success = await _channel.invokeMethod('enterPip') ?? false;
      return success;
    } catch (e) {
      debugPrint('[WakeLockService] Error entering PiP mode: $e');
      return false;
    }
  }

  /// Checks if Picture-in-Picture is supported by the current Android device
  static Future<bool> isPipSupported() async {
    if (kIsWeb) return false;
    try {
      final bool supported = await _channel.invokeMethod('isPipSupported') ?? false;
      return supported;
    } catch (e) {
      return false;
    }
  }

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

  /// Starts Android Native Foreground Service with persistent status notification
  /// Guarantees that Android OS does NOT suspend polling timers or sockets when minimized
  static Future<void> startForegroundService({required String title, required String message}) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('startForegroundService', {
        'title': title,
        'message': message,
      });
      debugPrint('[WakeLockService] Native Foreground Service started: $title');
    } catch (e) {
      debugPrint('[WakeLockService] Error starting foreground service: $e');
    }
  }

  /// Stops Android Native Foreground Service when offline or ride completes
  static Future<void> stopForegroundService() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('stopForegroundService');
      debugPrint('[WakeLockService] Native Foreground Service stopped');
    } catch (e) {
      debugPrint('[WakeLockService] Error stopping foreground service: $e');
    }
  }

  /// Displays urgent high-priority Heads-Up Notification with sound, vibration, and full-screen intent
  /// Suppressed automatically when app is already in the foreground to prevent duplicate floating banners
  static Future<void> showIncomingAlert({
    required String title,
    required String message,
    String? bookingId,
    String role = 'pilot',
    bool force = false,
  }) async {
    if (kIsWeb) return;
    try {
      final isForeground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      if (isForeground && !force) {
        debugPrint('[WakeLockService] Suppressed floating alert banner because app is in foreground: $title');
        return;
      }
      _initChannelHandler();
      await _channel.invokeMethod('showIncomingAlert', {
        'title': title,
        'message': message,
        'bookingId': bookingId,
        'role': role,
        'force': force,
      });
      debugPrint('[WakeLockService] Urgent incoming booking alert notification triggered (role: $role): $title');
    } catch (e) {
      debugPrint('[WakeLockService] Error showing incoming alert notification: $e');
    }
  }

  /// Dismisses the urgent incoming alert notification
  static Future<void> dismissIncomingAlert() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('dismissIncomingAlert');
      debugPrint('[WakeLockService] Urgent incoming alert notification dismissed');
    } catch (e) {
      debugPrint('[WakeLockService] Error dismissing incoming alert notification: $e');
    }
  }

  /// Brings the StayDriv app window to the front
  static Future<void> bringAppToForeground() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('bringAppToForeground');
    } catch (e) {
      debugPrint('[WakeLockService] Error bringing app to foreground: $e');
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
