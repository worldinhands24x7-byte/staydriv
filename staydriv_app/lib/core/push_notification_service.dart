import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'network_config.dart';
import '../features/notifications/services/notification_inbox_service.dart';

class PushNotificationItem {
  final String title;
  final String body;
  final String type; // 'push', 'promo', 'alert', 'emergency'
  final String? campaignId;
  final DateTime timestamp;

  PushNotificationItem({
    required this.title,
    required this.body,
    this.type = 'push',
    this.campaignId,
    required this.timestamp,
  });
}

class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final ValueNotifier<PushNotificationItem?> inAppNotificationNotifier = ValueNotifier(null);

  String? _currentToken;
  String _userRole = 'customer';
  String? _uid;
  String? _phone;
  bool _initialized = false;

  String? get fcmToken => _currentToken;

  Future<void> init({
    required String role,
    String? uid,
    String? phone,
  }) async {
    _userRole = role.toLowerCase().contains('pilot') || role.toLowerCase().contains('driver') 
      ? 'partner' 
      : 'customer';
    _uid = uid;
    _phone = phone;

    if (_initialized) {
      // If already initialized, just ensure backend registration is up-to-date
      if (_currentToken != null) {
        _syncTokenToBackend(_currentToken!);
      }
      return;
    }

    try {
      if (Firebase.apps.isEmpty) {
        debugPrint('[PUSH] Firebase not initialized yet, skipping FCM setup');
        return;
      }

      // 1. Request Notification Permission (Android 13+ & iOS)
      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: true,
        provisional: false,
        sound: true,
      );

      debugPrint('[PUSH] Notification authorization status: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        
        // 2. Obtain FCM Registration Token
        try {
          _currentToken = await _messaging.getToken();
          debugPrint('[PUSH] FCM Token acquired: ${_currentToken?.substring(0, 15)}...');
          if (_currentToken != null) {
            await _saveTokenLocally(_currentToken!);
            await _syncTokenToBackend(_currentToken!);
          }
        } catch (e) {
          debugPrint('[PUSH] Could not fetch FCM token: $e');
        }

        // 3. Listen to token refresh
        _messaging.onTokenRefresh.listen((newToken) {
          debugPrint('[PUSH] FCM Token refreshed: ${newToken.substring(0, 15)}...');
          _currentToken = newToken;
          _saveTokenLocally(newToken);
          _syncTokenToBackend(newToken);
        });

        // 4. Subscribe to broad topics
        try {
          await _messaging.subscribeToTopic('all');
          if (_userRole == 'customer') {
            await _messaging.subscribeToTopic('customers');
          } else if (_userRole == 'partner') {
            await _messaging.subscribeToTopic('partners');
          }
          debugPrint('[PUSH] Subscribed to topic "all" and "${_userRole == 'partner' ? 'partners' : 'customers'}"');
        } catch (topicErr) {
          debugPrint('[PUSH] Topic subscription error: $topicErr');
        }

        // 5. Handle Foreground Messages
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          debugPrint('[PUSH] Foreground message received: ${message.notification?.title}');
          final title = message.notification?.title ?? message.data['title'] ?? 'StayDriv Notification';
          final body = message.notification?.body ?? message.data['body'] ?? '';
          final type = message.data['type'] ?? 'push';
          final campaignId = message.data['campaignId'];

          final item = PushNotificationItem(
            title: title,
            body: body,
            type: type,
            campaignId: campaignId,
            timestamp: DateTime.now(),
          );

          inAppNotificationNotifier.value = item;
          NotificationInboxService().fetchInbox();
        });

        // 6. Handle notification click when app is in background or opened
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          debugPrint('[PUSH] Notification clicked: ${message.data}');
          NotificationInboxService().fetchInbox();
        });

        // 7. Check if app was opened from terminated state by a notification
        final initialMsg = await _messaging.getInitialMessage();
        if (initialMsg != null) {
          debugPrint('[PUSH] App launched from notification: ${initialMsg.data}');
          NotificationInboxService().fetchInbox();
        }

        _initialized = true;
      }
    } catch (e) {
      debugPrint('[PUSH] Error initializing push notification service: $e');
    }
  }

  Future<void> _saveTokenLocally(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('staydriv_fcm_token', token);
    } catch (_) {}
  }

  Future<void> _syncTokenToBackend(String token) async {
    try {
      final backendUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$backendUrl/api/notifications/register-token');

      final body = jsonEncode({
        'token': token,
        'uid': _uid,
        'phone': _phone,
        'role': _userRole,
        'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        'appType': 'staydriv_combined',
      });

      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        debugPrint('[PUSH] Token successfully registered with backend server');
      } else {
        debugPrint('[PUSH] Backend token registration returned ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      debugPrint('[PUSH] Failed to sync push token with backend: $e');
    }
  }

  /// Show in-app notification banner at the top of the screen
  static void showInAppBanner(BuildContext context, PushNotificationItem item) {
    final isEmergency = item.type == 'emergency';
    final isPromo = item.type == 'promo';

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        backgroundColor: isEmergency ? const Color(0xFFDC2626) : const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isEmergency ? const Color(0xFFEF4444) : const Color(0xFFEA580C),
            width: 1.5,
          ),
        ),
        duration: const Duration(seconds: 6),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isEmergency 
                  ? Colors.white.withOpacity(0.2) 
                  : (isPromo ? const Color(0xFF10B981).withOpacity(0.2) : const Color(0xFFEA580C).withOpacity(0.2)),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isEmergency ? Icons.warning_amber_rounded : (isPromo ? Icons.local_offer_rounded : Icons.notifications_active_rounded),
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.body,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: Colors.white.withOpacity(0.9),
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
