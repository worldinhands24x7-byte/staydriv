import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'core/theme.dart';
import 'core/firebase_service.dart';
import 'core/network_config.dart';
import 'core/location_share_service.dart';
import 'core/push_notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'features/onboarding/screens/login_screen.dart';
import 'features/dashboard/screens/home_screen.dart';
import 'core/floating_widget_service.dart';
import 'features/notifications/services/notification_inbox_service.dart';

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await FirebaseService.initialize();
  } catch (_) {}
  debugPrint('[PUSH BACKGROUND] Remote message received: ${message.notification?.title ?? message.data['title']}');
}

class CellularHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    HttpOverrides.global = CellularHttpOverrides();
  }
  await FirebaseService.initialize();
  if (!kIsWeb) {
    try {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint('[PUSH] Failed to register background handler: $e');
    }
  }
  await NetworkConfig.init();
  if (!kIsWeb) {
    await NetworkConfig.autoDiscoverReachableBackend();
  }
  
  final currentHost = Uri.base.host;
  final isLocalhost = currentHost == 'localhost' || currentHost == '127.0.0.1';
  final defaultUrl = isLocalhost ? 'http://localhost:3000' : NetworkConfig.backendUrl;
  
  final prefs = await SharedPreferences.getInstance();
  
  // Extract and apply query parameter overrides immediately on startup
  final queryParams = Uri.base.queryParameters;
  if (queryParams.containsKey('role')) {
    final role = queryParams['role'];
    String uiRole = 'Customer';
    String phone = '9010922111';
    String displayName = 'Customer Web';
    String? selectedVehicle;
    
    if (role?.toLowerCase() == 'driver' || role?.toLowerCase() == 'pilot') {
      uiRole = 'Driver';
      phone = queryParams['phone'] ?? '7013213057';
      displayName = 'Pilot Partner';
      selectedVehicle = queryParams['vehicle'] ?? 'Bike';
    } else if (role?.toLowerCase() == 'admin') {
      uiRole = 'Admin';
      phone = queryParams['phone'] ?? '9010922111';
      displayName = 'StayDriv Admin';
    } else {
      phone = queryParams['phone'] ?? '9010922111';
    }
    
    final String uid = queryParams['uid'] ?? (uiRole == 'Admin' ? 'mock_uid_staydriv' : (uiRole == 'Driver' ? 'mock_uid_${phone}_pilot' : 'mock_uid_$phone'));
    
    await prefs.setBool('is_logged_in', true);
    await prefs.setString('user_name', displayName);
    await prefs.setString('user_role', uiRole);
    await prefs.setString('phone_number', phone);
    if (selectedVehicle != null) {
      await prefs.setString('selected_vehicle', selectedVehicle);
    } else {
      await prefs.remove('selected_vehicle');
    }
    await prefs.setString('mock_uid', uid);
    FirebaseService.setMockUid(uid);
  }

  String? savedUrl = prefs.getString('backend_url');
  
  // Force reset cached URLs if they are different from current session's default,
  // especially for native mobile builds where local IPs won't work on mobile networks.
  if (savedUrl != null) {
    final isLocalIp = savedUrl.contains('192.168.') || 
                        savedUrl.contains('10.') || 
                        savedUrl.contains('172.') || 
                        savedUrl.contains('127.0.0.1') || 
                        savedUrl.contains('localhost');
    final isTunnel = savedUrl.contains('.loca.lt') || savedUrl.contains('.lhr.life') || savedUrl.contains('.ngrok-free.app') || savedUrl.contains('.serveousercontent.com');
    
    if (!kIsWeb) {
      // For native mobile apps, reset local IPs or outdated tunnels to the default public URL
      if (isLocalIp || (isTunnel && savedUrl != defaultUrl)) {
        savedUrl = null;
      }
    } else {
      // For Web apps, reset local IPs if the page is not hosted on localhost,
      // or reset outdated tunnels if the URL differs.
      if ((isLocalIp && !isLocalhost) || (isTunnel && savedUrl != defaultUrl)) {
        savedUrl = null;
      }
    }
  }

  if (savedUrl == null || savedUrl.isEmpty) {
    savedUrl = defaultUrl;
    await prefs.setString('backend_url', savedUrl);
  }
  if (savedUrl.isNotEmpty) {
    try {
      NetworkConfig.backendUrl = savedUrl;
    } catch (_) {
      savedUrl = defaultUrl;
      try {
        NetworkConfig.backendUrl = savedUrl;
      } catch (_) {}
      await prefs.setString('backend_url', savedUrl);
    }
  }
  
  final bool isLoggedIn = prefs.getBool('is_logged_in') ?? false;
  final String? mockUid = prefs.getString('mock_uid');
  if (mockUid != null) {
    FirebaseService.setMockUid(mockUid);
  }

  // Check for cold-start deep link or shared location intent
  if (!kIsWeb) {
    try {
      const channel = MethodChannel('com.staydriv.app/location_share');
      final initialLink = await channel.invokeMethod<String>('getInitialSharedLocation');
      if (initialLink != null && initialLink.trim().isNotEmpty) {
        await LocationShareService.savePendingLink(initialLink.trim());
      }
    } catch (e) {
      debugPrint('Could not check initial link in main(): $e');
    }
  }
  
  runApp(StayDrivApp(
    isLoggedIn: isLoggedIn,
    userName: prefs.getString('user_name') ?? 'User',
    userRole: prefs.getString('user_role') ?? 'Customer',
    phoneNumber: prefs.getString('phone_number') ?? '',
    selectedVehicle: prefs.getString('selected_vehicle'),
  ));
}

class StayDrivApp extends StatefulWidget {
  final bool isLoggedIn;
  final String userName;
  final String userRole;
  final String phoneNumber;
  final String? selectedVehicle;

  const StayDrivApp({
    super.key,
    required this.isLoggedIn,
    required this.userName,
    required this.userRole,
    required this.phoneNumber,
    this.selectedVehicle,
  });

  @override
  State<StayDrivApp> createState() => _StayDrivAppState();
}

class _StayDrivAppState extends State<StayDrivApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize Push Notifications
    PushNotificationService().init(
      role: widget.userRole,
      phone: widget.phoneNumber,
    );

    NotificationInboxService().init(
      role: widget.userRole,
      phone: widget.phoneNumber,
    );

    PushNotificationService.inAppNotificationNotifier.addListener(_handleInAppNotification);
  }

  void _handleInAppNotification() {
    final item = PushNotificationService.inAppNotificationNotifier.value;
    if (item != null) {
      NotificationInboxService().fetchInbox();
      final ctx = rootScaffoldMessengerKey.currentContext;
      if (ctx != null) {
        PushNotificationService.showInAppBanner(ctx, item);
      }
      PushNotificationService.inAppNotificationNotifier.value = null;
    }
  }

  @override
  void dispose() {
    PushNotificationService.inAppNotificationNotifier.removeListener(_handleInAppNotification);
    WidgetsBinding.instance.removeObserver(this);
    FloatingWidgetService.hide();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      FloatingWidgetService.syncWithCurrentState(
        isMinimizing: true,
        userRole: widget.userRole,
      );
    } else if (state == AppLifecycleState.resumed) {
      FloatingWidgetService.hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      title: 'StayDriv',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: widget.isLoggedIn
          ? HomeScreen(
              userName: widget.userName,
              userRole: widget.userRole,
              phoneNumber: widget.phoneNumber,
              selectedVehicle: widget.selectedVehicle,
            )
          : const LoginScreen(),
    );
  }
}
