import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class NetworkConfig {
  static const String defaultHttpsTunnelUrl = 'https://aaron-unity-alternatives-canvas.trycloudflare.com';
  static String _backendUrl = defaultHttpsTunnelUrl;

  static List<String> get presetUrls => [
    'https://aaron-unity-alternatives-canvas.trycloudflare.com',
    'http://192.168.1.16:3000',
    'http://localhost:3000',
    'http://10.0.2.2:3000',
  ];

  static Map<String, String> get standardBypassHeaders => {
    'Bypass-Tunnel-Reminder': 'true',
    'bypass-tunnel-reminder': 'true',
    'ngrok-skip-browser-warning': 'true',
    'User-Agent': 'StayDrivApp/1.0',
    'Accept': 'application/json, text/plain, */*',
  };

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString('custom_backend_url') ?? prefs.getString('backend_url');
      if (savedUrl != null && savedUrl.trim().isNotEmpty) {
        final isOldExpired = savedUrl.contains('silk-flu') ||
            savedUrl.contains('staydriv-v3-dev') ||
            savedUrl.contains('qualified-seems');
        final isLocalHostOnly = savedUrl.contains('localhost') || savedUrl.contains('127.0.0.1');
        if (isOldExpired || (!kIsWeb && defaultTargetPlatform == TargetPlatform.android && isLocalHostOnly)) {
          _backendUrl = defaultHttpsTunnelUrl;
        } else {
          _backendUrl = savedUrl.trim();
        }
      } else {
        _backendUrl = defaultHttpsTunnelUrl;
      }
    } catch (e) {
      debugPrint('NetworkConfig init error: $e');
    }
  }

  static String get backendUrl {
    final cleanUrl = _backendUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (kIsWeb && (cleanUrl.contains('.loca.lt') || cleanUrl.contains('.trycloudflare.com') || cleanUrl.contains('.lhr.life') || cleanUrl.contains('.serveousercontent.com'))) {
      return Uri.base.origin;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      if (cleanUrl.contains('localhost') || cleanUrl.contains('127.0.0.1')) {
        return defaultHttpsTunnelUrl;
      }
      return cleanUrl;
    }
    return cleanUrl;
  }

  static set backendUrl(String url) {
    final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (clean.isNotEmpty) {
      _backendUrl = clean;
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('custom_backend_url', clean);
        prefs.setString('backend_url', clean);
      });
    }
  }

  static Future<bool> testConnection(String targetUrl) async {
    try {
      final clean = targetUrl.trim().replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse('$clean/api/health');
      final response = await http.get(
        uri,
        headers: standardBypassHeaders,
      ).timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('NetworkConfig testConnection failed for $targetUrl: $e');
      return false;
    }
  }

  static Future<String> autoDiscoverReachableBackend() async {
    for (final candidate in presetUrls) {
      final isHealthy = await testConnection(candidate);
      if (isHealthy) {
        debugPrint('[NetworkConfig] Auto-discovered working cellular backend: $candidate');
        backendUrl = candidate;
        return backendUrl;
      }
    }
    return backendUrl;
  }
}
