import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';
import '../../../core/firebase_service.dart';
import '../../../core/network_config.dart';
import '../../../core/network_monitor.dart';
import '../../../core/razorpay_gateway.dart';
import '../../../services/api_service.dart';

import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../dashboard/screens/home_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final PageController _pageController = PageController(initialPage: 1);
  int _currentPage = 1;
  Timer? _carouselTimer;
  final TextEditingController _phoneController = TextEditingController(text: '90109 22111');
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _showOtpSheet = false;
  final List<TextEditingController> _otpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());

  String? _receivedOtp;
  int _resendCountdown = 0;
  Timer? _resendTimer;

  bool _isSendingOtp = false;
  bool _isSignInMode = false;
  bool _isLoggingIn = false;
  String _selectedRole = 'Pilot'; // Customer, Pilot, Admin
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
    
    // Set selected role from query parameters or default to Pilot
    final queryParams = Uri.base.queryParameters;
    final path = Uri.base.path.toLowerCase();
    final fullUrl = Uri.base.toString().toLowerCase();

    if (queryParams.containsKey('role')) {
      final role = queryParams['role']?.toLowerCase();
      if (role == 'customer') {
        _selectedRole = 'Customer';
        _phoneController.text = '90109 22111';
      } else if (role == 'admin') {
        _selectedRole = 'Admin';
        _phoneController.text = '90109 22111';
      } else {
        _selectedRole = 'Pilot';
        _phoneController.text = '90109 22111';
      }
    } else if (path.contains('customer') || fullUrl.contains('role=customer')) {
      _selectedRole = 'Customer';
      _phoneController.text = '90109 22111';
    } else if (path.contains('admin') || fullUrl.contains('role=admin')) {
      _selectedRole = 'Admin';
      _phoneController.text = '90109 22111';
    } else {
      _selectedRole = 'Pilot';
      _phoneController.text = '90109 22111';
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkQueryParameterOverrides();
    });
  }

  void _checkQueryParameterOverrides() async {
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


  Future<void> _triggerOtpRequest() async {

    final cleanPhone = _phoneController.text.replaceAll(' ', '').trim();
    if (cleanPhone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid 10-digit mobile number'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }
    
    setState(() {
      _isSendingOtp = true;
    });

    var res = await ApiService.sendOtp(cleanPhone);
    if (res['success'] != true) {
      debugPrint('[LoginScreen] First OTP request failed, auto-discovering reachable 5G backend...');
      final discoveredUrl = await NetworkConfig.autoDiscoverReachableBackend();
      debugPrint('[LoginScreen] Retrying OTP request with discovered backend: $discoveredUrl');
      res = await ApiService.sendOtp(cleanPhone);
    }
    
    if (mounted) {
      setState(() {
        _isSendingOtp = false;
      });
      if (res['success'] == true) {
        _playOtpReceivedSoundAndVibration();
        _receivedOtp = (res['otp'] ?? res['debugOtp'])?.toString();

        // Auto-fill the 6 OTP input boxes if OTP is received
        if (_receivedOtp != null && _receivedOtp!.length == 6) {
          for (int i = 0; i < 6; i++) {
            _otpControllers[i].text = _receivedOtp![i];
          }
        } else {
          for (var c in _otpControllers) {
            c.clear();
          }
        }

        // Start 30s resend timer
        _resendCountdown = 30;
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

        setState(() {
          _showOtpSheet = true;
        });
        if (_otpFocusNodes.isNotEmpty && (_receivedOtp == null || _receivedOtp!.isEmpty)) {
          _otpFocusNodes[0].requestFocus();
        }
        final String otpNotice = _receivedOtp != null
            ? '🔔 OTP Received! Your code is: $_receivedOtp'
            : (res['message'] ?? '🔔 OTP Received successfully!');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(otpNotice),
            backgroundColor: AppTheme.primaryColor,
            duration: const Duration(seconds: 8),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    res['message'] ?? 'Unable to send OTP. Please check your network and try again.',
                    style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFD32F2F),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _verifyOtp() async {
    String enteredOtp = _otpControllers.map((c) => c.text.trim()).join();
    
    if (enteredOtp.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the complete 6-digit OTP'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }
    
    setState(() {
      _isLoggingIn = true;
    });

    final phone = _phoneController.text.replaceAll(' ', '').replaceAll(RegExp(r'\D'), '').trim();
    var res = await ApiService.verifyOtp(phone, enteredOtp);
    if (res['success'] != true) {
      debugPrint('[LoginScreen] First verifyOtp failed, auto-discovering reachable 5G backend...');
      await NetworkConfig.autoDiscoverReachableBackend();
      res = await ApiService.verifyOtp(phone, enteredOtp);
    }

    if (!mounted) return;

    if (res['success'] == true) {
      final token = res['token'] as String?;
      final user = res['user'] as Map<String, dynamic>?;

      final String uiRole = (_selectedRole == 'Pilot' || _selectedRole == 'Driver')
          ? 'Driver'
          : (_selectedRole == 'Admin' ? 'Admin' : 'Customer');
      final displayName = user?['name'] ?? (uiRole == 'Driver' ? 'StayDriv Pilot' : (uiRole == 'Admin' ? 'StayDriv Admin' : 'StayDriv Customer'));
      final uid = user?['id'] ?? (uiRole == 'Driver' ? 'mock_uid_${phone}_pilot' : (uiRole == 'Admin' ? 'mock_uid_staydriv' : 'mock_uid_$phone'));


      final prefs = await SharedPreferences.getInstance();
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
          content: Text('OTP Verified Successfully! Logging in...'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => RegisterScreen(
            phoneNumber: phone,
            initialRole: uiRole,
          ),
        ),
        (route) => false,
      );
    } else {
      setState(() {
        _isLoggingIn = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message'] ?? 'Invalid or expired OTP'),
          backgroundColor: AppTheme.errorColor,
          duration: const Duration(seconds: 4),
        ),
      );
    }
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
                      Text(
                        'Pay for Day (Daily Pass)',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F1E4A),
                        ),
                      ),
                      Text(
                        'Drive all day with 0% platform commission',
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
                    amount: 49.0,
                    description: 'StayDriv Pilot Daily Pass (Pay for Day)',
                    onSuccess: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('has_daily_pass', true);
                      await prefs.setString('daily_pass_timestamp', DateTime.now().toIso8601String());
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✅ Pay for Day Pass Activated! Enter mobile number to start driving.'),
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
                  children: [
                    Text(
                      'Pay ₹49 & Activate Day Pass',
                      style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
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

  Widget _buildOptionCard({
    required String cardNumber,
    required Widget imageWidget,
    required String title,
    required String description,
    required bool isSelected,
    required VoidCallback onTap,
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
              child: Container(
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          _buildCustomerRoleTab(),
          const SizedBox(width: 6),
          _buildPilotRoleTab(),
          const SizedBox(width: 6),
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
            _phoneController.text = '90109 22111';
            _showOtpSheet = false;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFEFF5FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? const Color(0xFF1E60FF) : Colors.transparent,
              width: 2,
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
                      Icon(Icons.two_wheeler_rounded, size: 16, color: isSelected ? const Color(0xFF1E60FF) : const Color(0xFF475569)),
                      const SizedBox(width: 3),
                      Icon(Icons.electric_rickshaw_rounded, size: 16, color: isSelected ? const Color(0xFF1E60FF) : const Color(0xFF475569)),
                      const SizedBox(width: 3),
                      Icon(Icons.directions_car_rounded, size: 16, color: isSelected ? const Color(0xFF1E60FF) : const Color(0xFF475569)),
                      const SizedBox(width: 3),
                      Icon(Icons.local_shipping_rounded, size: 16, color: isSelected ? const Color(0xFF1E60FF) : const Color(0xFF475569)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Customer',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? const Color(0xFF1E60FF) : const Color(0xFF475569),
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
            _phoneController.text = '90109 22111';
            _showOtpSheet = false;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFEFF5FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? const Color(0xFF1E60FF) : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.handshake_rounded,
                size: 22,
                color: isSelected ? const Color(0xFF1E60FF) : const Color(0xFF475569),
              ),
              const SizedBox(height: 6),
              Text(
                'Pilot',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? const Color(0xFF1E60FF) : const Color(0xFF475569),
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
            _phoneController.text = '90109 22111';
            _showOtpSheet = false;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFEFF5FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? const Color(0xFF1E60FF) : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.admin_panel_settings_rounded,
                size: 22,
                color: isSelected ? const Color(0xFF1E60FF) : const Color(0xFF475569),
              ),
              const SizedBox(height: 6),
              Text(
                'Admin',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? const Color(0xFF1E60FF) : const Color(0xFF475569),
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

        // 2. TOP ROLE TABS
        _buildRoleSelectorCard(),
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
              description: 'Pay for day and\nstart driving.',
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
                    hintText: '90109 22111',
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
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Get OTP',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 22),
                    ],
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
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _showOtpSheet = false;
                  });
                },
              ),
              Text(
                'Verify Mobile',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F1E4A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Enter the 6-digit verification code sent via SMS to +91 ${_phoneController.text}',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 16),

          // In-App OTP Notification Banner
          if (_receivedOtp != null && _receivedOtp!.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFBFDBFE), width: 1.5),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFDBEAFE),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.mark_email_read_rounded, color: Color(0xFF1E60FF), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Verification OTP:',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1E40AF),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _receivedOtp!,
                          style: GoogleFonts.robotoMono(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1E60FF),
                            letterSpacing: 4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E60FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    onPressed: () {
                      if (_receivedOtp != null) {
                        for (int i = 0; i < 6 && i < _receivedOtp!.length; i++) {
                          _otpControllers[i].text = _receivedOtp![i];
                        }
                      }
                    },
                    icon: const Icon(Icons.touch_app, size: 14),
                    label: Text(
                      'Auto-Fill',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (index) {
              return SizedBox(
                width: 44,
                height: 52,
                child: TextField(
                  controller: _otpControllers[index],
                  focusNode: _otpFocusNodes[index],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.robotoMono(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1E60FF),
                  ),
                  maxLength: 1,
                  decoration: InputDecoration(
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF1E60FF), width: 2),
                    ),
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
          const SizedBox(height: 16),

          // Resend OTP Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Didn't receive the SMS?",
                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
              ),
              _resendCountdown > 0
                  ? Text(
                      'Resend in ${_resendCountdown}s',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF94A3B8),
                      ),
                    )
                  : TextButton.icon(
                      onPressed: _isSendingOtp ? null : () => _triggerOtpRequest(),
                      icon: _isSendingOtp
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh, size: 16, color: Color(0xFF1E60FF)),
                      label: Text(
                        'Resend OTP',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1E60FF),
                        ),
                      ),
                    ),
            ],
          ),
          const SizedBox(height: 12),

          // Test OTP Helper Note
          Center(
            child: Text(
              'Tip: You can also use universal test code 123456',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF94A3B8),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(height: 18),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E60FF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _isLoggingIn ? null : _verifyOtp,
              child: _isLoggingIn
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                    )
                  : Text(
                      'Verify & Proceed',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
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
                _selectedRole == 'Admin' ? 'Admin Portal Login' : 'Welcome to StayDriv',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F1E4A),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _selectedRole == 'Admin' ? 'Enter admin credentials to sign in' : 'Enter your mobile number to get started.',
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
                            hintText: '90109 22111',
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
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Get OTP',
                                style: GoogleFonts.hankenGrotesk(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                            ],
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
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
          // Network settings shortcut in top-right
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
