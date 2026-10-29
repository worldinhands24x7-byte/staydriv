import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../core/firebase_service.dart';
import '../services/api_service.dart';
import '../features/dashboard/screens/home_screen.dart';

class OtpScreen extends StatefulWidget {
  final String mobile;
  final String? initialCode;
  final String role;
  final String? verificationSessionId;

  const OtpScreen({
    super.key,
    required this.mobile,
    this.initialCode,
    this.role = 'CUSTOMER',
    this.verificationSessionId,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final List<TextEditingController> _otpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _isLoading = false;
  bool _isResending = false;
  String _errorMessage = '';
  
  String? _currentCode;
  String? _currentSessionId;
  int _attemptsRemaining = 5;
  int _expirySeconds = 300; // 5 minutes
  int _resendCooldown = 10;
  Timer? _expiryTimer;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    final secureRandom = Random.secure();
    _currentCode = (widget.initialCode != null && widget.initialCode!.length == 6)
        ? widget.initialCode
        : (100000 + secureRandom.nextInt(900000)).toString();
    _currentSessionId = widget.verificationSessionId;
    _startExpiryTimer();
    _startCooldownTimer();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _cooldownTimer?.cancel();
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _startExpiryTimer() {
    _expiryTimer?.cancel();
    _expirySeconds = 300;
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_expirySeconds > 0) {
        setState(() {
          _expirySeconds--;
        });
      } else {
        timer.cancel();
        setState(() {
          _currentCode = null;
        });
      }
    });
  }

  void _startCooldownTimer() {
    _cooldownTimer?.cancel();
    _resendCooldown = 10;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldown > 0) {
        setState(() {
          _resendCooldown--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  String _formatTimer(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _getEnteredOtp() {
    return _otpControllers.map((c) => c.text.trim()).join();
  }

  void _autoFillCode() {
    if (_currentCode != null && _currentCode!.length == 6) {
      for (int i = 0; i < 6; i++) {
        _otpControllers[i].text = _currentCode![i];
      }
      setState(() {
        _errorMessage = '';
      });
    }
  }

  void _handleVerifyOtp() async {
    final otp = _getEnteredOtp();
    if (otp.length != 6) {
      setState(() {
        _errorMessage = 'Please enter all 6 digits of the verification code';
      });
      return;
    }

    if (_expirySeconds <= 0 || _currentCode == null) {
      setState(() {
        _errorMessage = 'Verification code expired. Generate a new code.';
      });
      return;
    }

    if (_attemptsRemaining <= 0) {
      setState(() {
        _errorMessage = 'Maximum verification attempts exceeded. Please generate a new code.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    Map<String, dynamic>? res;
    try {
      res = await ApiService.verifyOtp(
        widget.mobile, 
        otp, 
        role: widget.role,
        verificationSessionId: _currentSessionId,
      );
    } catch (_) {}

    setState(() {
      _isLoading = false;
    });

    if (res == null || res['success'] != true) {
      final int remaining = res?['attemptsRemaining'] ?? (_attemptsRemaining > 0 ? _attemptsRemaining - 1 : 0);
      setState(() {
        _attemptsRemaining = remaining;
        if (_attemptsRemaining <= 0) {
          _currentCode = null;
        }
        _errorMessage = res?['message'] ?? (_attemptsRemaining <= 0 ? 'Maximum verification attempts exceeded. Please generate a new code.' : 'Invalid verification code. Please try again.');
      });
      return;
    }

    _expiryTimer?.cancel();
    _cooldownTimer?.cancel();

    final token = res['token'] as String?;
    final user = res['user'] as Map<String, dynamic>?;
    final bool isPilot = widget.role == 'PILOT' || widget.role == 'Driver';
    final uiRole = isPilot ? 'Driver' : 'Customer';
    final displayName = user?['name'] ?? (isPilot ? 'StayDriv Pilot' : 'StayDriv Customer');
    final uid = user?['id'] ?? (isPilot ? 'pilot_${widget.mobile}' : 'user_${widget.mobile}');

    final prefs = await SharedPreferences.getInstance();
    if (token != null) {
      await prefs.setString('jwt_token', token);
    }
    await prefs.setBool('is_logged_in', true);
    await prefs.setString('user_name', displayName);
    await prefs.setString('user_role', uiRole);
    await prefs.setString('user_mobile', widget.mobile);
    await prefs.setString('phone_number', widget.mobile);
    await prefs.setString('mock_uid', uid);
    FirebaseService.setMockUid(uid);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Login Verified Successfully! Welcome to StayDriv.'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => HomeScreen(
            userName: displayName,
            userRole: uiRole,
            phoneNumber: widget.mobile,
          ),
        ),
        (route) => false,
      );
    }
  }

  void _handleResendOtp() async {
    if (_resendCooldown > 0 || _isResending) return;

    setState(() {
      _isResending = true;
      _errorMessage = '';
      _currentCode = null; // Invalidate old code immediately
      _attemptsRemaining = 5;
    });

    for (var c in _otpControllers) {
      c.clear();
    }
    _focusNodes[0].requestFocus();

    try {
      final res = await ApiService.sendOtp(widget.mobile, role: widget.role);
      if (res['success'] == true) {
        final serverCode = (res['verificationCode'] ?? res['code'])?.toString();
        final sessId = (res['verificationSessionId'] ?? res['transactionId'])?.toString();
        final int exp = res['expiresIn'] as int? ?? 300;
        final int attempts = res['attemptsRemaining'] as int? ?? 5;
        if (serverCode != null && serverCode.length == 6) {
          setState(() {
            _currentCode = serverCode;
            _currentSessionId = sessId;
            _expirySeconds = exp;
            _attemptsRemaining = attempts;
          });
          _startExpiryTimer();
          _startCooldownTimer();
        }
      } else {
        setState(() {
          _errorMessage = res['message'] ?? 'Failed to request new code. Please try again.';
        });
      }
    } catch (_) {
      setState(() {
        _errorMessage = 'Network error requesting new code.';
      });
    }

    setState(() {
      _isResending = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Verify Mobile',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter the 6-digit verification code shown below.',
                style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 24),

              // In-App Verification Code Display Card (Requirement 2 & 5)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF1E60FF).withValues(alpha: 0.15),
                      const Color(0xFF0F172A).withValues(alpha: 0.8),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF1E60FF).withValues(alpha: 0.4), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.shield_outlined, size: 16, color: Color(0xFF60A5FA)),
                            const SizedBox(width: 6),
                            Text(
                              'Your verification code',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF60A5FA),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _expirySeconds > 30 ? const Color(0xFF1E293B) : const Color(0xFF7F1D1D),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.timer_outlined,
                                size: 12,
                                color: _expirySeconds > 30 ? Colors.white70 : const Color(0xFFFCA5A5),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatTimer(_expirySeconds),
                                style: GoogleFonts.robotoMono(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _expirySeconds > 30 ? Colors.white : const Color(0xFFFCA5A5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_expirySeconds > 0 && _currentCode != null && _currentCode!.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_currentCode!.length, (idx) {
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: 40,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF3B82F6), width: 1.5),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _currentCode![idx],
                              style: GoogleFonts.robotoMono(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF60A5FA),
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E60FF),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                            ),
                            onPressed: _autoFillCode,
                            icon: const Icon(Icons.flash_on_rounded, size: 16),
                            label: Text(
                              'Auto-Fill Code',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter this code in the boxes below.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white70,
                        ),
                      ),
                    ] else ...[
                      Text(
                        'Verification code expired. Generate a new code.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFF87171),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Security Attempts Status
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Attempts remaining: $_attemptsRemaining of 5',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _attemptsRemaining <= 2 ? const Color(0xFFEF4444) : Colors.white60,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 6-digit OTP fields
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (index) {
                  return SizedBox(
                    width: 48,
                    height: 58,
                    child: TextField(
                      controller: _otpControllers[index],
                      focusNode: _focusNodes[index],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 1,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: AppTheme.cardBackground,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                        ),
                      ),
                      onChanged: (value) {
                        if (value.isNotEmpty) {
                          if (index < 5) {
                            _focusNodes[index + 1].requestFocus();
                          } else {
                            _focusNodes[index].unfocus();
                            _handleVerifyOtp();
                          }
                        } else {
                          if (index > 0) {
                            _focusNodes[index - 1].requestFocus();
                          }
                        }
                      },
                    ),
                  );
                }),
              ),

              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.errorColor, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _errorMessage,
                        style: GoogleFonts.plusJakartaSans(color: AppTheme.errorColor, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 32),

              // Verify Button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: (_isLoading || _attemptsRemaining <= 0) ? null : _handleVerifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : Text(
                          'Verify & Proceed',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 24),

              // Resend / Generate New Code
              Center(
                child: _resendCooldown > 0
                    ? Text(
                        'Generate new code in ${_resendCooldown}s',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white54,
                          fontSize: 14,
                        ),
                      )
                    : TextButton.icon(
                        onPressed: _isResending ? null : _handleResendOtp,
                        icon: _isResending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(color: AppTheme.primaryColor, strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh, size: 18, color: AppTheme.primaryColor),
                        label: Text(
                          'Generate New Code',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTheme.primaryColor,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
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
}
