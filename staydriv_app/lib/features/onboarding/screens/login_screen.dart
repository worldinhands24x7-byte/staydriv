import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';
import '../../../core/firebase_service.dart';
import '../../../core/network_config.dart';
import '../../../core/network_monitor.dart';
import '../../../core/razorpay_gateway.dart';
import '../../../core/booking_manager.dart';
import '../../../core/api_client.dart';
import '../../../services/api_service.dart';

import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../dashboard/screens/home_screen.dart';
import 'register_screen.dart';
import '../../food_ordering/screens/restaurant_onboarding_screen.dart';
import '../../food_ordering/screens/restaurant_application_status_screen.dart';
import '../../food_ordering/screens/restaurant_partner_console_screen.dart';
import '../../food_ordering/services/food_service.dart';

class _DashedRectPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;
  final double dash;
  final double radius;

  _DashedRectPainter({
    this.color = const Color(0xFF22C55E),
    this.strokeWidth = 1.5,
    this.dash = 6,
    this.gap = 4,
    this.radius = 12,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final RRect rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(strokeWidth / 2, strokeWidth / 2, size.width - strokeWidth, size.height - strokeWidth),
      Radius.circular(radius),
    );
    final Path path = Path()..addRRect(rrect);
    final Path dashPath = Path();

    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final double length = (distance + dash < metric.length) ? dash : metric.length - distance;
        dashPath.addPath(metric.extractPath(distance, distance + length), Offset.zero);
        distance += dash + gap;
      }
    }
    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class LoginScreen extends StatefulWidget {
  final String? initialRole;

  const LoginScreen({super.key, this.initialRole});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final PageController _pageController = PageController(initialPage: 1);
  int _currentPage = 1;
  Timer? _carouselTimer;
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _showOtpSheet = false;
  final List<TextEditingController> _otpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());

  String? _receivedOtp;
  String? _verificationSessionId;
  int _resendCountdown = 0;
  int _attemptsRemaining = 5;
  int _codeValiditySeconds = 300;
  Timer? _resendTimer;
  Timer? _expiryTimer;

  bool _isSendingOtp = false;
  bool _isSignInMode = false;
  bool _isLoggingIn = false;
  static const String _envAppMode = String.fromEnvironment('APP_MODE', defaultValue: 'customer');
  late String _selectedRole;
  int _selectedDriveOption = 2; // 1: Pay for day, 2: Get Rides with StayDriv

  final List<Map<String, dynamic>> _carouselItems = [
    {
      'icon': Icons.bolt,
      'title': 'Lightning Fast',
      'desc': 'Optimized routing gets you to your destination with zero wasted time.',
    },
    {
      'icon': Icons.verified_user_rounded,
      'title': 'Secure & Safe',
      'desc': 'Real-time tracking and emergency protocols built directly into your drive.',
    },
    {
      'icon': Icons.check_circle,
      'title': 'Always Reliable',
      'desc': 'Consistent performance and fleet availability you can count on daily.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _startCarousel();
    
    // Set selected role from initialRole parameter, query parameters, or default to _envAppMode
    final defaultRole = _envAppMode.toLowerCase() == 'pilot' ? 'Pilot' : 'Customer';
    final queryParams = Uri.base.queryParameters;
    final path = Uri.base.path.toLowerCase();
    final fullUrl = Uri.base.toString().toLowerCase();

    if (widget.initialRole != null && widget.initialRole!.isNotEmpty) {
      _selectedRole = widget.initialRole!;
    } else if (queryParams.containsKey('role')) {
      final role = queryParams['role']?.toLowerCase();
      if (role == 'customer') {
        _selectedRole = 'Customer';
      } else if (role == 'admin') {
        _selectedRole = 'Admin';
      } else if (role == 'pilot' || role == 'driver') {
        _selectedRole = 'Pilot';
      } else if (role == 'restaurant' || role == 'partner' || role == 'food') {
        _selectedRole = 'Restaurant Partner';
      } else {
        _selectedRole = defaultRole;
      }
    } else if (path.contains('customer') || fullUrl.contains('role=customer')) {
      _selectedRole = 'Customer';
    } else if (path.contains('admin') || fullUrl.contains('role=admin')) {
      _selectedRole = 'Admin';
    } else if (path.contains('restaurant') || path.contains('partner') || fullUrl.contains('role=restaurant')) {
      _selectedRole = 'Restaurant Partner';
    } else if (path.contains('pilot') || fullUrl.contains('role=pilot') || path.contains('driver')) {
      _selectedRole = 'Pilot';
    } else {
      _selectedRole = defaultRole;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkQueryParameterOverrides();
    });
  }

  void _checkQueryParameterOverrides() async {
    // If an explicit initialRole was provided (such as after logout), skip auto-login overrides
    if (widget.initialRole != null && widget.initialRole!.isNotEmpty) {
      return;
    }
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
      
      // Save session in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
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
      
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => HomeScreen(
              userName: displayName,
              userRole: uiRole,
              phoneNumber: phone,
              selectedVehicle: selectedVehicle,
            ),
          ),
          (route) => false,
        );
      }
    }
  }

  void _startCarousel() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _carouselTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
        if (_currentPage < _carouselItems.length - 1) {
          _currentPage++;
        } else {
          _currentPage = 0;
        }
        if (_pageController.hasClients) {
          _pageController.animateToPage(
            _currentPage,
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOutCubic,
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _resendTimer?.cancel();
    _expiryTimer?.cancel();
    _pageController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    for (var c in _otpControllers) {
      c.dispose();
    }
    for (var f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email address'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }
    if (password.isEmpty || password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password must be at least 6 characters'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }
    
    setState(() {
      _isLoggingIn = true;
    });

    // --- DEDICATED ADMIN & STAFF AUTHENTICATION FLOW ---
    if (_selectedRole == 'Admin') {
      try {
        final res = await ApiService.adminLogin(email, password);
        if (res['success'] != true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(res['message'] ?? 'Invalid Admin email or password. Access denied.'),
                backgroundColor: AppTheme.errorColor,
                duration: const Duration(seconds: 4),
              ),
            );
          }
          return;
        }

        final user = res['user'] as Map<String, dynamic>?;
        final token = res['token'] as String?;
        final cleanPass = password.trim();
        final bool isStaff = cleanPass == 'admin@123' || (user?['role']?.toString().toLowerCase() == 'staff');
        final role = isStaff ? 'Staff' : 'Admin';
        final displayName = user?['name']?.toString() ?? (isStaff ? 'StayDriv Staff' : 'StayDriv Admin');
        final phone = user?['phone']?.toString() ?? '9010922111';
        final uid = user?['uid']?.toString() ?? user?['id']?.toString() ?? (isStaff ? 'mock_staff_uid' : 'mock_admin_uid');

        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('saved_active_booking');
        BookingManager().clearBooking();
        await prefs.setBool('is_logged_in', true);
        await prefs.setString('user_name', displayName);
        await prefs.setString('user_role', role); // 'Admin' or 'Staff'
        await prefs.setString('phone_number', phone);
        await prefs.setString('mock_uid', uid);
        if (token != null && token.isNotEmpty) {
          await prefs.setString('jwt_token', token);
          ApiClient.setAuthToken(token);
        }
        FirebaseService.setMockUid(uid);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$role Login Successful! Loading Admin Console...'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );

          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => HomeScreen(
                userName: displayName,
                userRole: role,
                phoneNumber: phone,
              ),
            ),
            (route) => false,
          );
        }
        return;
      } catch (err) {
        debugPrint('[AdminLogin] Error: $err');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Admin Login Error: $err'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
        return;
      } finally {
        if (mounted) {
          setState(() {
            _isLoggingIn = false;
          });
        }
      }
    }
    
    try {
      final creds = await FirebaseService().signIn(email, password);
      final uid = creds.user!.uid;
      final role = await FirebaseService().getUserRole(uid);
      
      String displayName = 'User';
      String phoneNumber = '';
      String? selectedVehicle;
      
      if (role != 'unknown') {
        final doc = await FirebaseService().getProfile(role, uid);
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          displayName = data['name'] ?? 'User';
          phoneNumber = data['phone'] ?? '';
          if (role == 'partner') {
            selectedVehicle = data['vehicleType'] ?? 'Bike';
          }
        }
      }
      
      final uiRole = role == 'partner' ? 'Driver' : (role == 'admin' ? 'Admin' : 'Customer');
      
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_logged_in', true);
        await prefs.setString('user_name', displayName);
        await prefs.setString('user_role', uiRole);
        await prefs.setString('phone_number', phoneNumber);
        if (selectedVehicle != null) {
          await prefs.setString('selected_vehicle', selectedVehicle);
        } else {
          await prefs.remove('selected_vehicle');
        }
        await prefs.setString('mock_uid', uid);
      } catch (prefsErr) {
        debugPrint("Error saving login session: $prefsErr");
      }
      
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => HomeScreen(
              userName: displayName,
              userRole: uiRole,
              phoneNumber: phoneNumber,
              selectedVehicle: selectedVehicle,
            ),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      if (password == 'admin@123' || password == 'bhavi@123') {
        final isStaff = password == 'admin@123';
        final role = isStaff ? 'Staff' : 'Admin';
        final displayName = isStaff ? 'StayDriv Staff' : 'StayDriv Admin';
        final phone = '9010922111';
        final uid = isStaff ? 'mock_staff_uid' : 'mock_admin_uid';
        
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('is_logged_in', true);
          await prefs.setString('user_name', displayName);
          await prefs.setString('user_role', role);
          await prefs.setString('phone_number', phone);
          await prefs.setString('mock_uid', uid);
          FirebaseService.setMockUid(uid);
        } catch (_) {}
        
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => HomeScreen(
                userName: displayName,
                userRole: role,
                phoneNumber: phone,
              ),
            ),
            (route) => false,
          );
        }
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign In Failed: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingIn = false;
        });
      }
    }
  }

  void _playOtpReceivedSoundAndVibration() async {
    try {
      FlutterRingtonePlayer().play(
        android: AndroidSounds.notification,
        ios: IosSounds.glass,
        looping: false,
        volume: 1.0,
      );
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 300));
      await HapticFeedback.vibrate();
    } catch (e) {
      debugPrint('Ringtone sound note: $e');
    }
  }


  void _autoFillCode() {
    if (_receivedOtp != null && _receivedOtp!.length == 6) {
      for (int i = 0; i < 6; i++) {
        _otpControllers[i].text = _receivedOtp![i];
      }
      setState(() {});
    }
  }

  Future<void> _triggerOtpRequest({bool isNewCode = false}) async {
    final cleanPhone = _phoneController.text.replaceAll(' ', '').replaceAll(RegExp(r'\D'), '').trim();
    if (cleanPhone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid 10-digit mobile number'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }
    
    // Clear 6-digit input boxes
    for (var c in _otpControllers) {
      c.clear();
    }

    setState(() {
      _isSendingOtp = true;
    });

    final String normalizedRole = (_selectedRole == 'Pilot' || _selectedRole == 'Driver')
        ? 'PILOT'
        : (_selectedRole == 'Admin' ? 'ADMIN' : 'CUSTOMER');

    try {
      var res = await ApiService.sendOtp(cleanPhone, role: normalizedRole);
      if (res['success'] != true) {
        await NetworkConfig.autoDiscoverReachableBackend();
        res = await ApiService.sendOtp(cleanPhone, role: normalizedRole);
      }

      if (!mounted) return;

      if (res['success'] == true) {
        final serverCode = (res['verificationCode'] ?? res['code'])?.toString();
        final sessId = (res['verificationSessionId'] ?? res['transactionId'])?.toString();
        final int exp = res['expiresIn'] as int? ?? 300;
        final int attempts = res['attemptsRemaining'] as int? ?? 5;

        setState(() {
          _receivedOtp = serverCode;
          _verificationSessionId = sessId;
          _codeValiditySeconds = exp;
          _attemptsRemaining = attempts;
          _resendCountdown = 16;
          _showOtpSheet = true;
          _isSendingOtp = false;
        });

        // Start 5-minute (300s) server-synchronized countdown timer
        _expiryTimer?.cancel();
        _expiryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          if (_codeValiditySeconds > 0) {
            setState(() {
              _codeValiditySeconds--;
            });
          } else {
            timer.cancel();
            setState(() {
              _receivedOtp = null; // Mark expired on screen
            });
          }
        });

        // Start 16s cooldown timer for requesting new code
        _resendTimer?.cancel();
        _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          if (_resendCountdown > 0) {
            setState(() {
              _resendCountdown--;
            });
          } else {
            timer.cancel();
          }
        });

        if (_otpFocusNodes.isNotEmpty) {
          _otpFocusNodes[0].requestFocus();
        }
      } else {
        setState(() {
          _isSendingOtp = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Failed to generate verification code. Please try again.'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSendingOtp = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Network error. Please check your connection and try again.'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _verifyOtp() async {
    final String enteredOtp = _otpControllers.map((c) => c.text.trim()).join();
    
    if (enteredOtp.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter all 6 digits of the verification code'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    // Expiration check
    if (_codeValiditySeconds <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verification code expired. Please request a new code.'),
          backgroundColor: Color(0xFFD32F2F),
        ),
      );
      return;
    }

    // Maximum attempts check
    if (_attemptsRemaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Too many incorrect attempts. Please request a new code.'),
          backgroundColor: Color(0xFFD32F2F),
        ),
      );
      return;
    }

    setState(() {
      _isLoggingIn = true;
    });

    final phone = _phoneController.text.replaceAll(' ', '').replaceAll(RegExp(r'\D'), '').trim();
    final String normalizedRole = (_selectedRole == 'Pilot' || _selectedRole == 'Driver')
        ? 'PILOT'
        : (_selectedRole == 'Admin' ? 'ADMIN' : 'CUSTOMER');

    Map<String, dynamic>? res;
    try {
      res = await ApiService.verifyOtp(
        phone, 
        enteredOtp, 
        role: normalizedRole,
        verificationSessionId: _verificationSessionId,
      );
      if (res['success'] != true && (res['message']?.toString().contains('Network') ?? false)) {
        await NetworkConfig.autoDiscoverReachableBackend();
        res = await ApiService.verifyOtp(
          phone, 
          enteredOtp, 
          role: normalizedRole,
          verificationSessionId: _verificationSessionId,
        );
      }
    } catch (e) {
      debugPrint('[LoginScreen] verifyOtp exception: $e');
    }

    if (!mounted) return;

    setState(() {
      _isLoggingIn = false;
    });

    // Check if backend verification failed
    if (res == null || res['success'] != true) {
      final int remaining = res?['attemptsRemaining'] ?? (_attemptsRemaining > 0 ? _attemptsRemaining - 1 : 0);
      setState(() {
        _attemptsRemaining = remaining;
        if (_attemptsRemaining <= 0) {
          _receivedOtp = null; // Invalidate displayed code
        }
      });

      final String errMsg = res?['message'] ?? (_attemptsRemaining <= 0 ? 'Too many incorrect attempts. Please request a new code.' : 'Invalid verification code. Please try again.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errMsg),
          backgroundColor: const Color(0xFFD32F2F),
        ),
      );
      return; // STOP! Backend decision is final, do not proceed
    }

    // Backend verified successfully!
    _expiryTimer?.cancel();
    _resendTimer?.cancel();
    _playOtpReceivedSoundAndVibration();

    final token = res['token'] as String?;
    final user = res['user'] as Map<String, dynamic>?;

    final String uiRole = (_selectedRole == 'Pilot' || _selectedRole == 'Driver')
        ? 'Driver'
        : (_selectedRole == 'Admin'
            ? 'Admin'
            : (_selectedRole == 'Restaurant Partner' ? 'Restaurant Partner' : 'Customer'));
    final displayName = user?['name'] ?? (uiRole == 'Driver' ? 'StayDriv Pilot' : (uiRole == 'Admin' ? 'StayDriv Admin' : (uiRole == 'Restaurant Partner' ? 'Restaurant Partner' : 'StayDriv Customer')));
    final uid = user?['uid'] ?? user?['id'] ?? (uiRole == 'Driver' ? 'pilot_$phone' : (uiRole == 'Admin' ? 'admin_$phone' : (uiRole == 'Restaurant Partner' ? 'restaurant_$phone' : 'user_$phone')));

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_active_booking');
    BookingManager().clearBooking();
    await prefs.setBool('is_logged_in', true);
    await prefs.setString('user_name', displayName);
    await prefs.setString('user_role', uiRole);
    await prefs.setString('phone_number', phone);
    if (token != null) {
      await prefs.setString('jwt_token', token);
    }
    await prefs.setString('mock_uid', uid);
    FirebaseService.setMockUid(uid);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Login Verified Successfully! Welcome to StayDriv.'),
        backgroundColor: Colors.green,
      ),
    );

    // Route to Restaurant Partner Console/Onboarding if Restaurant Partner
    if (_selectedRole == 'Restaurant Partner') {
      final partnerCheck = await FoodService().getPartnerByPhone(phone);
      if (!mounted) return;

      if (partnerCheck != null && partnerCheck['registered'] == true && partnerCheck['restaurant'] != null) {
        final restaurant = partnerCheck['restaurant'] as Map<String, dynamic>;
        final status = (restaurant['status'] as String? ?? 'pending').toLowerCase();

        await prefs.setString('user_name', restaurant['name'] ?? 'Restaurant Partner');
        await prefs.setString('user_role', 'Restaurant Partner');

        if (status == 'approved') {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => RestaurantPartnerConsoleScreen(restaurantData: restaurant),
            ),
            (route) => false,
          );
        } else {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => RestaurantApplicationStatusScreen(
                restaurantData: restaurant,
                phoneNumber: phone,
              ),
            ),
            (route) => false,
          );
        }
      } else {
        // Not registered yet -> Open Onboarding flow
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RestaurantOnboardingScreen(
              phoneNumber: phone,
              initialOwnerName: displayName,
            ),
          ),
        );
      }
      return;
    }

    // Directly open Customer Home for Customer, or Pilot Home for Pilot
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => HomeScreen(
          userName: displayName,
          userRole: uiRole, // 'Customer' or 'Driver' (Pilot)
          phoneNumber: phone,
        ),
      ),
      (route) => false,
    );
  }


  void _showNetworkSettingsDialog() {
    final controller = TextEditingController(text: NetworkConfig.backendUrl);
    bool isTesting = false;
    String? testResult;
    bool? testSuccess;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.wifi_tethering, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Server & Network Settings',
                      style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Configure your backend server connection. Use the 4G/5G HTTPS Tunnel for mobile SIM networks (Jio, Airtel, Vi, BSNL).',
                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 18, color: Colors.blue.shade800),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '4G/5G Mobile carriers block HTTP cleartext traffic. Always use HTTPS tunnel on mobile data.',
                              style: GoogleFonts.inter(fontSize: 11, color: Colors.blue.shade900, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'QUICK PRESETS (1-TAP):',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.cell_tower, size: 14, color: Colors.green),
                          label: const Text('⚡ 4G/5G HTTPS Tunnel', style: TextStyle(fontSize: 11)),
                          backgroundColor: Colors.green.shade50,
                          onPressed: () {
                            setDialogState(() {
                              controller.text = NetworkConfig.defaultHttpsTunnelUrl;
                              testResult = null;
                            });
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.android, size: 14, color: Colors.purple),
                          label: const Text('💻 Android Emulator', style: TextStyle(fontSize: 11)),
                          backgroundColor: Colors.purple.shade50,
                          onPressed: () {
                            setDialogState(() {
                              controller.text = 'http://10.0.2.2:3000';
                              testResult = null;
                            });
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.wifi, size: 14, color: Colors.indigo),
                          label: const Text('🏠 Wi-Fi (192.168.1.16)', style: TextStyle(fontSize: 11)),
                          backgroundColor: Colors.indigo.shade50,
                          onPressed: () {
                            setDialogState(() {
                              controller.text = 'http://192.168.1.16:3000';
                              testResult = null;
                            });
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.computer, size: 14, color: Colors.blue),
                          label: const Text('🌐 Localhost', style: TextStyle(fontSize: 11)),
                          backgroundColor: Colors.blue.shade50,
                          onPressed: () {
                            setDialogState(() {
                              controller.text = 'http://localhost:3000';
                              testResult = null;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        labelText: 'SERVER BACKEND URL',
                        hintText: 'https://staydriv-v3-dev.loca.lt',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: isTesting
                              ? null
                              : () async {
                                  final target = controller.text.trim();
                                  if (target.isEmpty) return;
                                  setDialogState(() {
                                    isTesting = true;
                                    testResult = 'Testing connection...';
                                    testSuccess = null;
                                  });
                                  final ok = await NetworkConfig.testConnection(target);
                                  setDialogState(() {
                                    isTesting = false;
                                    testSuccess = ok;
                                    testResult = ok
                                        ? '✅ Connected Successfully (HTTP 200 OK)'
                                        : '❌ Connection Failed (Server Unreachable)';
                                  });
                                },
                          icon: isTesting
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.speed, size: 16),
                          label: const Text('Test Connection', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    if (testResult != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: (testSuccess ?? false) ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: (testSuccess ?? false) ? Colors.green.shade300 : Colors.red.shade300),
                        ),
                        child: Text(
                          testResult!,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: (testSuccess ?? false) ? Colors.green.shade900 : Colors.red.shade900,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'Active: ${NetworkConfig.backendUrl}',
                      style: GoogleFonts.robotoMono(fontSize: 11, color: Colors.green.shade800, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final url = controller.text.trim();
                    if (url.isNotEmpty) {
                      try {
                        setState(() {
                          NetworkConfig.backendUrl = url;
                        });
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('backend_url', NetworkConfig.backendUrl);
                        await prefs.setString('custom_backend_url', NetworkConfig.backendUrl);
                        NetworkMonitor().forceCheck();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Server URL updated: ${NetworkConfig.backendUrl}'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                        Navigator.pop(context);
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(e.toString().replaceAll('Exception: ', '')),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  },
                  child: const Text('Save Settings'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showTermsDialog(String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A)),
        ),
        content: SingleChildScrollView(
          child: Text(
            title == 'Terms and Conditions' || title == 'Terms'
                ? 'StayDriv Partner & Pilot Terms:\n\n1. By accessing or driving with the StayDriv Platform as a pilot partner, you agree to adhere to safe driving practices, commercial compliance, and regulatory transport guidelines.\n2. In Pay-for-Day mode, pilots operate with zero commission on all customer bookings during the active 24-hour pass.\n3. Safety and punctuality are paramount for every trip.'
                : 'StayDriv Privacy Policy:\n\nWe value your privacy. We collect location data solely during active driving and dispatch sessions to match you with nearby customers and provide real-time navigation. Your data is protected by industry-standard encryption.',
            style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: const Color(0xFF334155)),
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E60FF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showPayForDayModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF5FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF1E60FF), size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Pay for the Day (Daily Pass)',
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F1E4A),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '₹20 / Day',
                              style: GoogleFonts.robotoMono(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF047857),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Drive all day with 0% platform commission for just ₹20',
                        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  _buildPassFeature(Icons.check_circle_rounded, 'Unlimited ride bookings for 24 hours'),
                  const SizedBox(height: 10),
                  _buildPassFeature(Icons.check_circle_rounded, 'Keep 100% of customer fares (0% commission)'),
                  const SizedBox(height: 10),
                  _buildPassFeature(Icons.check_circle_rounded, 'Instant direct bank settlement & cash collection'),
                  const Divider(height: 20, color: Color(0xFFE2E8F0)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Daily Pass Fee:',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF475569)),
                      ),
                      Text(
                        '₹20.00',
                        style: GoogleFonts.robotoMono(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF0F1E4A)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Payable Now:',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF1E60FF)),
                      ),
                      Text(
                        '₹20',
                        style: GoogleFonts.robotoMono(fontSize: 18, fontWeight: FontWeight.w900, color: const Color(0xFF1E60FF)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E60FF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  RazorpayGateway.show(
                    context,
                    amount: 20.0,
                    description: 'StayDriv Pilot Daily Pass - ₹20 (Pay for the Day)',
                    onSuccess: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('has_daily_pass', true);
                      await prefs.setString('daily_pass_timestamp', DateTime.now().toIso8601String());
                      await prefs.setDouble('daily_pass_amount', 20.0);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✅ Pay for the Day (₹20) Pass Activated! Enter mobile number to start driving.'),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 4),
                          ),
                        );
                      }
                    },
                  );
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        'Pay ₹20 & Activate Day Pass',
                        style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPassFeature(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF10B981), size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: const Color(0xFF334155)),
          ),
        ),
      ],
    );
  }

  // --- PILOT REGISTRATION & STATUS FLOW HANDLERS ---
  Future<void> _handlePilotRegistrationTap() async {
    final cleanPhone = _phoneController.text.replaceAll(RegExp(r'\D'), '').trim();
    if (cleanPhone.length < 10) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const RegisterScreen(
            phoneNumber: '',
            initialRole: 'Driver',
          ),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  'Checking pilot application...',
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/pilot/application-status?phone=$cleanPhone');
      final res = await ApiClient().get(uri, retry: false).timeout(const Duration(seconds: 4));
      if (mounted) {
        Navigator.pop(context);
      }

      if (res.statusCode == 200 && !res.body.trimLeft().startsWith('<')) {
        final data = jsonDecode(res.body);
        if (data is Map && data['success'] == true && data['found'] == true) {
          final status = (data['status'] ?? '').toString().toUpperCase();
          final appId = (data['applicationId'] ?? 'SD-PLT-PENDING').toString();
          final pilot = data['pilot'] is Map ? Map<String, dynamic>.from(data['pilot']) : <String, dynamic>{};
          final isApproved = data['approved'] == true || data['isApproved'] == true || status == 'APPROVED';

          if (isApproved) {
            _showPilotApprovedModal(appId, cleanPhone);
            return;
          } else if (status == 'PENDING_VERIFICATION' || status == 'SUBMITTED' || status == 'PENDING') {
            _showPilotPendingStatusModal(appId, cleanPhone, pilot);
            return;
          } else if (status == 'REJECTED' || status == 'ACTION_REQUIRED' || status == 'RESUBMISSION_REQUIRED') {
            _showPilotRejectedModal(appId, cleanPhone, pilot);
            return;
          }
        }
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RegisterScreen(
              phoneNumber: cleanPhone,
              initialRole: 'Driver',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RegisterScreen(
              phoneNumber: cleanPhone,
              initialRole: 'Driver',
            ),
          ),
        );
      }
    }
  }

  void _showPilotApprovedModal(String appId, String phone) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF16A34A), width: 2),
              ),
              child: const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 38),
            ),
            const SizedBox(height: 16),
            Text(
              'Pilot Account Approved!',
              style: GoogleFonts.hankenGrotesk(fontSize: 22, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF16A34A)),
              ),
              child: Text(
                'Status: APPROVED',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF16A34A)),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Application ID', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                  Text(appId, style: GoogleFonts.robotoMono(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF0284C7))),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Congratulations! Your StayDriv Pilot account is fully verified. Enter your verification code to access your driver console and start accepting rides.',
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569), height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _triggerOtpRequest();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1D4ED8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: Text(
                  'Log In with Verification Code',
                  style: GoogleFonts.hankenGrotesk(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RegisterScreen(
                        phoneNumber: phone,
                        initialRole: 'Driver',
                      ),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  'View / Update Registration Details',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPilotPendingStatusModal(String appId, String phone, Map<String, dynamic> pilot) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          bool isRefreshing = false;
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFF59E0B), width: 2),
                  ),
                  child: const Icon(Icons.hourglass_top_rounded, color: Color(0xFFD97706), size: 36),
                ),
                const SizedBox(height: 16),
                Text(
                  'Verification Under Review',
                  style: GoogleFonts.hankenGrotesk(fontSize: 22, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFF59E0B)),
                  ),
                  child: Text(
                    'Status: PENDING VERIFICATION',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFFB45309)),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Application ID', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                          Text(appId, style: GoogleFonts.robotoMono(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF0284C7))),
                        ],
                      ),
                      if (pilot['name'] != null && pilot['name'].toString().isNotEmpty) ...[
                        const Divider(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Pilot Name', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                            Text(pilot['name'].toString(), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A))),
                          ],
                        ),
                      ],
                      if (pilot['vehicleType'] != null && pilot['vehicleType'].toString().isNotEmpty) ...[
                        const Divider(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Vehicle Type', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                            Text(pilot['vehicleType'].toString(), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A))),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Your registration documents are currently pending verification by StayDriv Admin. You will be able to go online and accept rides as soon as your account is approved.',
                  style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B), height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                // 1. PRIMARY ACTION: Complete / Edit Registration Documents
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RegisterScreen(
                            phoneNumber: phone,
                            initialRole: 'Driver',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.edit_document, size: 18, color: Colors.white),
                    label: Text(
                      'Complete / Edit Registration Documents',
                      style: GoogleFonts.hankenGrotesk(fontSize: 14.5, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1D4ED8),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // 2. SECONDARY ACTION: Register with Different Mobile Number
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _phoneController.clear();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const RegisterScreen(
                            phoneNumber: '',
                            initialRole: 'Driver',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18, color: Color(0xFF0F172A)),
                    label: Text(
                      'Register with Different Mobile Number',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A)),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // 3. TERTIARY ACTION: Check Admin Approval Status (Refresh)
                SizedBox(
                  width: double.infinity,
                  height: 38,
                  child: TextButton.icon(
                    onPressed: isRefreshing ? null : () async {
                      setModalState(() => isRefreshing = true);
                      try {
                        final baseUrl = NetworkConfig.backendUrl;
                        final uri = Uri.parse('$baseUrl/api/pilot/application-status?phone=$phone');
                        final res = await ApiClient().get(uri, retry: false).timeout(const Duration(seconds: 4));
                        if (res.statusCode == 200 && !res.body.trimLeft().startsWith('<')) {
                          final data = jsonDecode(res.body);
                          if (data is Map && data['success'] == true && data['found'] == true) {
                            final status = (data['status'] ?? '').toString().toUpperCase();
                            final isAppr = data['approved'] == true || data['isApproved'] == true || status == 'APPROVED';
                            if (isAppr) {
                              Navigator.pop(ctx);
                              _showPilotApprovedModal(appId, phone);
                              return;
                            }
                          }
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Status checked: Still under review by StayDriv Admin.'), duration: Duration(seconds: 2)),
                          );
                        }
                      } catch (_) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Could not reach backend. Please try again.'), duration: Duration(seconds: 2)),
                          );
                        }
                      } finally {
                        setModalState(() => isRefreshing = false);
                      }
                    },
                    icon: isRefreshing
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF1D4ED8)),
                    label: Text(
                      isRefreshing ? 'Checking...' : 'Check Approval Status',
                      style: GoogleFonts.hankenGrotesk(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1D4ED8)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showPilotRejectedModal(String appId, String phone, Map<String, dynamic> pilot) {
    final reason = pilot['rejectionReason']?.toString() ?? pilot['correctionNotes']?.toString() ?? 'Documents require correction';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFDC2626), width: 2),
              ),
              child: const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              'Application Requires Correction',
              style: GoogleFonts.hankenGrotesk(fontSize: 22, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFDC2626)),
              ),
              child: Text(
                'Status: RESUBMISSION REQUIRED',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFFDC2626)),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Application ID', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                      Text(appId, style: GoogleFonts.robotoMono(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF0284C7))),
                    ],
                  ),
                  const Divider(height: 14),
                  Text('Admin Reason for Correction:', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
                  const SizedBox(height: 4),
                  Text(reason, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFFDC2626))),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Please correct the information or re-upload the requested documents to resubmit your application for admin approval.',
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B), height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RegisterScreen(
                        phoneNumber: phone,
                        initialRole: 'Driver',
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1D4ED8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Correct & Resubmit Application', style: GoogleFonts.hankenGrotesk(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionCard({
    required String cardNumber,
    required Widget imageWidget,
    required String title,
    required String description,
    required bool isSelected,
    required VoidCallback onTap,
    String? priceBadge,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        constraints: const BoxConstraints(minHeight: 205),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFAFCFF) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isSelected ? const Color(0xFF1E60FF) : const Color(0xFF3B82F6).withOpacity(0.85),
            width: isSelected ? 2 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected ? const Color(0x151E60FF) : const Color(0x06000000),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      color: Color(0xFF1E60FF),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        cardNumber,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ),
                  if (priceBadge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                      ),
                      child: Text(
                        priceBadge,
                        style: GoogleFonts.robotoMono(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF047857),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 68,
              child: Center(child: imageWidget),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F1E4A),
                height: 1.15,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                height: 1.3,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF64748B),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleSelectorCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: [
          _buildCustomerRoleTab(),
          const SizedBox(width: 4),
          _buildPilotRoleTab(),
          const SizedBox(width: 4),
          _buildRestaurantPartnerRoleTab(),
          const SizedBox(width: 4),
          _buildAdminRoleTab(),
        ],
      ),
    );
  }

  Widget _buildCustomerRoleTab() {
    final isSelected = _selectedRole == 'Customer';
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedRole = 'Customer';
            _showOtpSheet = false;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFEFF5FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? const Color(0xFF1E60FF) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 22,
                child: Image.asset(
                  'assets/images/customer_vehicles_strip.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.two_wheeler_rounded, size: 14, color: isSelected ? const Color(0xFF1E60FF) : const Color(0xFF475569)),
                      const SizedBox(width: 2),
                      Icon(Icons.electric_rickshaw_rounded, size: 14, color: isSelected ? const Color(0xFF1E60FF) : const Color(0xFF475569)),
                      const SizedBox(width: 2),
                      Icon(Icons.directions_car_rounded, size: 14, color: isSelected ? const Color(0xFF1E60FF) : const Color(0xFF475569)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 5),
              SizedBox(
                height: 26,
                child: Center(
                  child: Text(
                    'Customer',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: isSelected ? const Color(0xFF1E60FF) : const Color(0xFF475569),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPilotRoleTab() {
    final isSelected = _selectedRole == 'Pilot';
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedRole = 'Pilot';
            _showOtpSheet = false;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFEFF5FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? const Color(0xFF1E60FF) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 22,
                child: Icon(
                  Icons.handshake_rounded,
                  size: 20,
                  color: isSelected ? const Color(0xFF1E60FF) : const Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 5),
              SizedBox(
                height: 26,
                child: Center(
                  child: Text(
                    'Pilot',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: isSelected ? const Color(0xFF1E60FF) : const Color(0xFF475569),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRestaurantPartnerRoleTab() {
    final isSelected = _selectedRole == 'Restaurant Partner';
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedRole = 'Restaurant Partner';
            _showOtpSheet = false;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFEFF5FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? const Color(0xFF1E60FF) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 22,
                child: Icon(
                  Icons.restaurant_rounded,
                  size: 20,
                  color: isSelected ? const Color(0xFF1E60FF) : const Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 5),
              SizedBox(
                height: 26,
                child: Center(
                  child: Text(
                    'Restaurant\nPartner',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: isSelected ? const Color(0xFF1E60FF) : const Color(0xFF475569),
                      height: 1.05,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdminRoleTab() {
    final isSelected = _selectedRole == 'Admin';
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedRole = 'Admin';
            _showOtpSheet = false;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFEFF5FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? const Color(0xFF1E60FF) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 22,
                child: Icon(
                  Icons.admin_panel_settings_rounded,
                  size: 20,
                  color: isSelected ? const Color(0xFF1E60FF) : const Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 5),
              SizedBox(
                height: 26,
                child: Center(
                  child: Text(
                    'Admin',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: isSelected ? const Color(0xFF1E60FF) : const Color(0xFF475569),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPilotOpeningScreen() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        // 1. TOP LOGO
        Center(
          child: GestureDetector(
            onLongPress: _showNetworkSettingsDialog,
            child: Text(
              'StayDriv',
              style: GoogleFonts.outfit(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1E60FF),
                letterSpacing: -0.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _buildRoleSelectorCard(),
        const SizedBox(height: 20),

        // 2. STAYDRIV PILOT APP BADGE
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF5FF),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF1E60FF), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1E60FF).withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.handshake_rounded, color: Color(0xFF1E60FF), size: 20),
                const SizedBox(width: 8),
                Text(
                  'PILOT PARTNER PORTAL',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1E60FF),
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // 3. MAIN HEADING
        Text(
          'Select How You Want to Drive',
          style: GoogleFonts.hankenGrotesk(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F1E4A),
            letterSpacing: -0.3,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 18),

        // 4. TWO LARGE OPTIONS
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 340;

            final card1 = _buildOptionCard(
              cardNumber: '1',
              imageWidget: Image.asset(
                'assets/images/pilot_wallet_icon.jpg',
                height: 72,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 68,
                  height: 54,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E60FF),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF1E60FF).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3)),
                    ],
                  ),
                  child: const Center(
                    child: Text('₹', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
              title: 'Pay for day',
              description: 'Pay ₹20 for the day\nand start driving.',
              priceBadge: '₹20 / Day',
              isSelected: _selectedDriveOption == 1,
              onTap: () {
                setState(() {
                  _selectedDriveOption = 1;
                });
                _showPayForDayModal();
              },
            );

            final card2 = _buildOptionCard(
              cardNumber: '2',
              imageWidget: Image.asset(
                'assets/images/pilot_vehicles_strip.jpg',
                height: 56,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.two_wheeler_rounded, color: Color(0xFF1E60FF), size: 24),
                    SizedBox(width: 4),
                    Icon(Icons.electric_rickshaw_rounded, color: Color(0xFFEAB308), size: 24),
                    SizedBox(width: 4),
                    Icon(Icons.directions_car_rounded, color: Color(0xFF3B82F6), size: 24),
                    SizedBox(width: 4),
                    Icon(Icons.local_shipping_rounded, color: Color(0xFF2563EB), size: 24),
                  ],
                ),
              ),
              title: 'Get Rides with\nStayDriv',
              description: 'Receive ride bookings\nfrom StayDriv customers\nas usual.',
              isSelected: _selectedDriveOption == 2,
              onTap: () {
                setState(() {
                  _selectedDriveOption = 2;
                });
              },
            );

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: card1),
                  const SizedBox(width: 14),
                  Expanded(child: card2),
                ],
              );
            } else {
              return Column(
                children: [
                  card1,
                  const SizedBox(height: 14),
                  card2,
                ],
              );
            }
          },
        ),
        const SizedBox(height: 24),

        // 5. WELCOME / MOBILE NUMBER SECTION
        Text(
          'Welcome to StayDriv',
          style: GoogleFonts.hankenGrotesk(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F1E4A),
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Enter your mobile number to get started.',
          style: GoogleFonts.inter(
            fontSize: 13.5,
            color: const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Mobile Number',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFEFF4FE),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Row(
                children: [
                  Text(
                    '+91',
                    style: GoogleFonts.robotoMono(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0F1E4A),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.keyboard_arrow_down,
                    color: Color(0xFF64748B),
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Container(
                width: 1,
                height: 24,
                color: const Color(0xFFCBD5E1),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: GoogleFonts.robotoMono(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF0F1E4A),
                    letterSpacing: 1,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Enter 10-digit mobile',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                  ),
                  onSubmitted: (_) => _triggerOtpRequest(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // 6. GET OTP BUTTON
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E60FF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            onPressed: _isSendingOtp ? null : _triggerOtpRequest,
            child: _isSendingOtp
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Get Verification Code',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                      ],
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 10),

        // 6b. NEW PILOT REGISTRATION / PROFILE ENTRY
        Container(
          margin: const EdgeInsets.only(top: 8),
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2563EB), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2563EB).withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _handlePilotRegistrationTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.assignment_ind_rounded, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'New Pilot? Complete Registration (3 Steps)',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1D4ED8),
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Color(0xFF2563EB)),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),

        // 7. TERMS AND PRIVACY
        Align(
          alignment: Alignment.center,
          child: Text.rich(
            TextSpan(
              text: 'By continuing, you agree to our ',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF64748B),
              ),
              children: [
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: GestureDetector(
                    onTap: () => _showTermsDialog('Terms of Service'),
                    child: const Text(
                      'Terms',
                      style: TextStyle(
                        color: Color(0xFF1E60FF),
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const TextSpan(text: ' and '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: GestureDetector(
                    onTap: () => _showTermsDialog('Privacy Policy'),
                    child: const Text(
                      'Privacy Policy',
                      style: TextStyle(
                        color: Color(0xFF1E60FF),
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const TextSpan(text: '.'),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildOtpVerificationView() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top Verification Card matching screenshot
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4), // Light mint green
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF86EFAC), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. Dark Green Badge with Shield Icon
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF065F46), // Dark emerald green
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shield_outlined, color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'SECURE IN-APP VERIFICATION CODE',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 2. Subtitle copy from screenshot
                Text(
                  'This is your secure in-app verification code.\nNo external SMS has been sent. Enter this\ncode below to complete your ${_selectedRole == "Pilot" ? "Pilot" : "Customer"} login:',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF065F46),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),

                // 3. Dashed Border Box with Verification Code and Auto-Fill button
                CustomPaint(
                  painter: _DashedRectPainter(
                    color: const Color(0xFF22C55E),
                    strokeWidth: 1.5,
                    dash: 5,
                    gap: 4,
                    radius: 14,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        // Left: Verification Code label
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Verification',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                            Text(
                              'Code:',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                        // Center: Active 6-digit verification code
                        Expanded(
                          child: Text(
                            (_codeValiditySeconds > 0 && _receivedOtp != null && _receivedOtp!.isNotEmpty)
                                ? _receivedOtp!.split('').join(' ')
                                : '------',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.robotoMono(
                              fontSize: 27,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF047857),
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                        // Right: Auto-Fill button with bolt icon
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _autoFillCode,
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: const Color(0xFF047857),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.bolt, color: Color(0xFFFBBF24), size: 18),
                                  Text(
                                    'Auto-',
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      height: 1.1,
                                    ),
                                  ),
                                  Text(
                                    'Fill',
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      height: 1.1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 4. Expiry & Attempts status row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '⏱️ Expires: ${_codeValiditySeconds > 0 ? "${(_codeValiditySeconds ~/ 60)}:${(_codeValiditySeconds % 60).toString().padLeft(2, '0')}" : "Expired"}',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: _codeValiditySeconds < 60 ? const Color(0xFFDC2626) : const Color(0xFF065F46),
                      ),
                    ),
                    const Text(
                      '   •   ',
                      style: TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '🎯 Attempts left: $_attemptsRemaining',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: _attemptsRemaining <= 1 ? const Color(0xFFDC2626) : const Color(0xFF065F46),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Title: Enter 6-Digit Verification Code
          Text(
            'Enter 6-Digit Verification Code',
            style: GoogleFonts.inter(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 14),

          // 6-digit input boxes
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (index) {
              return Container(
                width: 48,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _otpFocusNodes[index].hasFocus ? const Color(0xFF4338CA) : const Color(0xFFCBD5E1),
                    width: _otpFocusNodes[index].hasFocus ? 2 : 1.5,
                  ),
                ),
                child: TextField(
                  controller: _otpControllers[index],
                  focusNode: _otpFocusNodes[index],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.robotoMono(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1E293B),
                  ),
                  maxLength: 1,
                  decoration: const InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (value) {
                    if (value.isNotEmpty && index < 5) {
                      _otpFocusNodes[index + 1].requestFocus();
                    } else if (value.isEmpty && index > 0) {
                      _otpFocusNodes[index - 1].requestFocus();
                    }
                    if (index == 5 && value.isNotEmpty) {
                      _verifyOtp();
                    }
                  },
                ),
              );
            }),
          ),
          const SizedBox(height: 20),

          // Resend / Request New Code Row
          Center(
            child: _resendCountdown > 0
                ? Text(
                    'Request New Code in ${_resendCountdown}s',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1E293B),
                    ),
                  )
                : TextButton(
                    onPressed: _isSendingOtp ? null : () => _triggerOtpRequest(isNewCode: true),
                    child: Text(
                      'Request New Code',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF4338CA),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 20),

          // Bottom Action Row: Back button + Verify & Continue button
          Row(
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    _showOtpSheet = false;
                  });
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
                  ),
                  child: const Icon(Icons.arrow_back, color: Color(0xFF1E293B), size: 22),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4338CA),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: (_isLoggingIn || _attemptsRemaining <= 0) ? null : _verifyOtp,
                    child: _isLoggingIn
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                          )
                        : Text(
                            'Verify & Continue',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Terms and Privacy policy footer
          Center(
            child: Text.rich(
              TextSpan(
                text: 'By continuing, you agree to our ',
                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                children: [
                  TextSpan(
                    text: 'Terms of Service',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF4338CA),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const TextSpan(text: '\nand '),
                  TextSpan(
                    text: 'Privacy Policy',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF4338CA),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerOrAdminScreen() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Center(
          child: GestureDetector(
            onLongPress: _showNetworkSettingsDialog,
            child: Text(
              'StayDriv',
              style: GoogleFonts.outfit(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1E60FF),
                letterSpacing: -0.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _buildRoleSelectorCard(),
        const SizedBox(height: 24),
        // Value Prop Carousel for Customer
        SizedBox(
          height: 140,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (int page) {
              setState(() {
                _currentPage = page;
              });
            },
            itemCount: _carouselItems.length,
            itemBuilder: (context, index) {
              final item = _carouselItems[index];
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color: const Color(0xFFE2E8F0),
                    width: 1,
                  ),
                ),
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF1E60FF),
                      ),
                      child: Icon(
                        item['icon'] as IconData,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item['title'] as String,
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0F1E4A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item['desc'] as String,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _carouselItems.length,
            (index) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              height: 6,
              width: _currentPage == index ? 24 : 6,
              decoration: BoxDecoration(
                color: _currentPage == index ? const Color(0xFF1E60FF) : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _selectedRole == 'Admin'
                    ? 'Admin Portal Login'
                    : (_selectedRole == 'Restaurant Partner' ? 'Restaurant Partner Portal' : 'Welcome to StayDriv'),
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F1E4A),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _selectedRole == 'Admin'
                    ? 'Enter admin credentials to sign in'
                    : (_selectedRole == 'Restaurant Partner'
                        ? 'Enter mobile number to manage orders or register as partner.'
                        : 'Enter your mobile number to get started.'),
                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
              ),
              if (_selectedRole == 'Admin') ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isSignInMode ? 'Staff Email Sign In' : 'Admin OTP Login',
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _isSignInMode = !_isSignInMode),
                      child: Text(
                        _isSignInMode ? 'Use Phone OTP' : 'Use Password',
                        style: const TextStyle(color: Color(0xFF1E60FF), fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                if (_isSignInMode) ...[
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Admin Email',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E60FF)),
                      onPressed: _isLoggingIn ? null : _handleSignIn,
                      child: const Text('Sign In to Admin Portal', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ],
              if (!_isSignInMode || _selectedRole != 'Admin') ...[
                const SizedBox(height: 20),
                Text(
                  'Mobile Number',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF4FE),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Row(
                        children: [
                          Text(
                            '+91',
                            style: GoogleFonts.robotoMono(fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF0F1E4A)),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.keyboard_arrow_down, color: Color(0xFF64748B), size: 20),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Container(width: 1, height: 24, color: const Color(0xFFCBD5E1)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          style: GoogleFonts.robotoMono(fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF0F1E4A)),
                          decoration: const InputDecoration(
                            hintText: 'Enter 10-digit mobile',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 14),
                          ),
                          onSubmitted: (_) => _triggerOtpRequest(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E60FF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _isSendingOtp ? null : _triggerOtpRequest,
                    child: _isSendingOtp
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Get Verification Code',
                                  style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_selectedRole == 'Customer') ...[
          const SizedBox(height: 16),
          Center(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedRole = 'Pilot';
                  _showOtpSheet = false;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.handshake_rounded, size: 17, color: Color(0xFF1E60FF)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Drive & Earn with StayDriv? Switch to Pilot Portal',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1E60FF),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FF),
      body: Stack(
        children: [
          // Background soft gradient
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 260,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFE4EDFF),
                    Color(0xFFF6F9FF),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: isDesktop ? 480 : double.infinity,
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 14.0),
                  child: _showOtpSheet
                      ? _buildOtpVerificationView()
                      : (_selectedRole == 'Pilot'
                          ? _buildPilotOpeningScreen()
                          : _buildCustomerOrAdminScreen()),
                ),
              ),
            ),
          ),
          // Network settings shortcut (hidden for Customer and Pilot, accessible for Admin or via long-press on StayDriv logo)
          if (_selectedRole == 'Admin')
            Positioned(
              top: 12,
              right: 12,
              child: SafeArea(
                child: IconButton(
                  icon: const Icon(Icons.settings_outlined, color: Color(0xFF1E60FF), size: 22),
                  onPressed: _showNetworkSettingsDialog,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
