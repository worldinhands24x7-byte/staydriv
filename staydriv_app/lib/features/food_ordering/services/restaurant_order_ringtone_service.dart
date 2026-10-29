import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/js_stub.dart'
    if (dart.library.js) 'dart:js' as js;

/// Dedicated High-Volume Order Ringtone and Notification Service
/// for StayDriv Food Order Now - Restaurant Partner Console.
///
/// Features:
/// - Distinctive, loud, continuous restaurant kitchen order alert.
/// - Maximum device volume support with user preference persistence.
/// - Native Android/iOS ALARM audio stream + Web Audio API synthesizer.
/// - Deduplication and multi-order active queue management.
/// - Automatic silencing on accept/reject/cancel/expire.
/// - Web Push & Browser notification permission management.
/// - 4-second Test Ringtone capability.
class RestaurantOrderRingtoneService {
  static final RestaurantOrderRingtoneService _instance = RestaurantOrderRingtoneService._internal();
  factory RestaurantOrderRingtoneService() => _instance;
  RestaurantOrderRingtoneService._internal();

  static const String _prefSoundEnabledKey = 'staydriv_restaurant_sound_enabled';
  static const String _prefVolumeKey = 'staydriv_restaurant_sound_volume';

  bool _initialized = false;
  bool _soundEnabled = true;
  double _volume = 1.0; // 0.1 to 1.0, default 100% max volume
  bool _isRinging = false;
  bool _isTesting = false;

  final Set<String> _activeRingingOrderIds = {};

  final ValueNotifier<bool> isRingingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> soundEnabledNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<double> volumeNotifier = ValueNotifier<double>(1.0);
  final ValueNotifier<int> activeOrdersCountNotifier = ValueNotifier<int>(0);

  bool get soundEnabled => _soundEnabled;
  double get volume => _volume;
  bool get isRinging => _isRinging;
  bool get isTesting => _isTesting;
  Set<String> get activeOrderIds => Set.unmodifiable(_activeRingingOrderIds);

  Timer? _nativeLoopTimer;
  Timer? _testStopTimer;

  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _soundEnabled = prefs.getBool(_prefSoundEnabledKey) ?? true;
      _volume = prefs.getDouble(_prefVolumeKey) ?? 1.0;
      soundEnabledNotifier.value = _soundEnabled;
      volumeNotifier.value = _volume;
      _initialized = true;
      debugPrint('[OrderRingtoneService] Initialized. SoundEnabled: $_soundEnabled, Volume: ${(_volume * 100).toInt()}%');
    } catch (e) {
      debugPrint('[OrderRingtoneService] Init error: $e');
    }
  }

  Future<void> setSoundEnabled(bool enabled) async {
    _soundEnabled = enabled;
    soundEnabledNotifier.value = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefSoundEnabledKey, enabled);
    } catch (_) {}

    if (!enabled && _isRinging) {
      _stopAudioHardware();
    }
  }

  Future<void> setVolume(double newVolume) async {
    _volume = newVolume.clamp(0.1, 1.0);
    volumeNotifier.value = _volume;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefVolumeKey, _volume);
    } catch (_) {}

    // If actively ringing, re-trigger at the new volume
    if (_isRinging && !_isTesting) {
      _playAudioHardware();
    }
  }

  void startOrderAlert(String orderId, {String? summary}) {
    if (orderId.isNotEmpty) {
      _activeRingingOrderIds.add(orderId);
      activeOrdersCountNotifier.value = _activeRingingOrderIds.length;
    }

    if (!_soundEnabled) {
      debugPrint('[OrderRingtoneService] Sound disabled in settings. Skipping ringtone for $orderId.');
      return;
    }

    if (_isRinging && !_isTesting) {
      debugPrint('[OrderRingtoneService] Already ringing. Added $orderId to active ringing orders (${_activeRingingOrderIds.length}).');
      return;
    }

    _isTesting = false;
    _isRinging = true;
    isRingingNotifier.value = true;
    debugPrint('[OrderRingtoneService] STARTING HIGH-VOLUME RINGTONE for order $orderId (Active queue: ${_activeRingingOrderIds.length}, Vol: ${(_volume * 100).toInt()}%)');

    _playAudioHardware(orderId: orderId, summary: summary);
  }

  void stopOrderAlert({String? orderId, bool forceAll = false}) {
    if (orderId != null && orderId.isNotEmpty) {
      _activeRingingOrderIds.remove(orderId);
      activeOrdersCountNotifier.value = _activeRingingOrderIds.length;
    }

    if (forceAll || _activeRingingOrderIds.isEmpty) {
      if (forceAll) {
        _activeRingingOrderIds.clear();
        activeOrdersCountNotifier.value = 0;
      }
      _stopAudioHardware();
    } else {
      debugPrint('[OrderRingtoneService] Order $orderId acknowledged, but ${_activeRingingOrderIds.length} order(s) remain unacknowledged. Continuing alert.');
    }
  }

  void testRingtone() {
    if (_isTesting) {
      _stopAudioHardware();
      return;
    }

    _isTesting = true;
    _isRinging = true;
    isRingingNotifier.value = true;
    debugPrint('[OrderRingtoneService] Playing 4-second test restaurant ringtone at volume ${(_volume * 100).toInt()}%');

    if (kIsWeb) {
      try {
        js.context.callMethod('playStayDrivTestChime', [_volume]);
      } catch (e) {
        debugPrint('[OrderRingtoneService] Web test audio error: $e');
      }
    } else {
      try {
        FlutterRingtonePlayer().play(
          android: AndroidSounds.ringtone,
          ios: IosSounds.electronic,
          looping: true,
          volume: _volume,
          asAlarm: true,
        ).catchError((_) {});
      } catch (e) {
        debugPrint('[OrderRingtoneService] Native test audio error: $e');
      }
    }

    _testStopTimer?.cancel();
    _testStopTimer = Timer(const Duration(seconds: 4), () {
      if (_isTesting) {
        _stopAudioHardware();
      }
    });
  }

  void _playAudioHardware({String? orderId, String? summary}) {
    if (kIsWeb) {
      try {
        js.context.callMethod('startStayDrivOrderAlarm', [
          _volume,
          orderId ?? 'NEW_ORDER',
          summary ?? 'New food order placed. Tap to review & accept!'
        ]);
      } catch (e) {
        debugPrint('[OrderRingtoneService] Web start alarm error: $e');
      }
    } else {
      try {
        FlutterRingtonePlayer().play(
          android: AndroidSounds.ringtone,
          ios: IosSounds.electronic,
          looping: true,
          volume: _volume,
          asAlarm: true,
        ).catchError((_) {});
        // Periodic pulse to maintain continuous ringtone on Android alarm stream
        _nativeLoopTimer?.cancel();
        _nativeLoopTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
          if (_isRinging && !_isTesting) {
            try {
              FlutterRingtonePlayer().play(
                android: AndroidSounds.ringtone,
                ios: IosSounds.electronic,
                looping: true,
                volume: _volume,
                asAlarm: true,
              ).catchError((_) {});
            } catch (_) {}
          }
        });
      } catch (e) {
        debugPrint('[OrderRingtoneService] Native start alarm error: $e');
      }
    }
  }

  void _stopAudioHardware() {
    _isRinging = false;
    _isTesting = false;
    isRingingNotifier.value = false;
    _testStopTimer?.cancel();
    _nativeLoopTimer?.cancel();

    if (kIsWeb) {
      try {
        js.context.callMethod('stopStayDrivOrderAlarm', []);
      } catch (e) {
        debugPrint('[OrderRingtoneService] Web stop alarm error: $e');
      }
    } else {
      try {
        FlutterRingtonePlayer().stop().catchError((_) {});
      } catch (e) {
        debugPrint('[OrderRingtoneService] Native stop alarm error: $e');
      }
    }
    debugPrint('[OrderRingtoneService] Audio hardware stopped.');
  }

  Future<String> getNotificationPermission() async {
    if (kIsWeb) {
      try {
        final res = js.context.callMethod('getStayDrivNotificationPermission', []);
        return (res ?? 'default').toString();
      } catch (_) {
        return 'unsupported';
      }
    }
    return 'granted';
  }

  Future<String> requestNotificationPermission() async {
    if (kIsWeb) {
      try {
        final res = await js.context.callMethod('requestStayDrivNotificationPermission', []);
        return (res ?? 'default').toString();
      } catch (_) {
        return 'default';
      }
    }
    return 'granted';
  }
}
