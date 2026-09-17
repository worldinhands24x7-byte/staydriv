import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'network_config.dart';
import 'firebase_service.dart';
import 'api_client.dart';


class RazorpayGateway extends StatefulWidget {
  final double amount;
  final String description;
  final String apiKey;
  final bool isPayout;
  final String? targetAccount; // UPI ID or Bank Account for payouts
  final VoidCallback onSuccess;

  const RazorpayGateway({
    super.key,
    required this.amount,
    required this.description,
    this.apiKey = 'rzp_live_Ta9cOGnIySuBCb',
    this.isPayout = false,
    this.targetAccount,
    required this.onSuccess,
  });

  static void show(
    BuildContext context, {
    required double amount,
    required String description,
    bool isPayout = false,
    String? targetAccount,
    required VoidCallback onSuccess,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 450),
            child: RazorpayGateway(
              amount: amount,
              description: description,
              isPayout: isPayout,
              targetAccount: targetAccount,
              onSuccess: onSuccess,
            ),
          ),
        ),
      ),
    );
  }

  @override
  State<RazorpayGateway> createState() => _RazorpayGatewayState();
}

class _RazorpayGatewayState extends State<RazorpayGateway> {
  int _screenState = 0; // 0 = Payment Methods / Details, 1 = Processing, 2 = Success
  String _selectedMethod = 'UPI';
  String _upiSubMethod = 'vpa'; // 'vpa' or 'qr'
  Timer? _statusPollTimer;
  
  // Input fields for simulation
  final TextEditingController _upiController = TextEditingController(text: 'customer@okaxis');
  final TextEditingController _cardNoController = TextEditingController(text: '4111 1111 1111 1111');
  final TextEditingController _cardExpiryController = TextEditingController(text: '12/29');
  final TextEditingController _cardCvvController = TextEditingController(text: '123');

  // Developer Sample Mode toggle (false = Real-Time Live Razorpay Gateway)
  bool _isDeveloperSampleMode = false;

  @override
  void dispose() {
    _upiController.dispose();
    _cardNoController.dispose();
    _cardExpiryController.dispose();
    _cardCvvController.dispose();
    _statusPollTimer?.cancel();
    super.dispose();
  }

  void _simulatePaymentSuccess() {
    setState(() {
      _screenState = 1; // Transition to processing loader screen
    });

    Timer(const Duration(milliseconds: 1100), () {
      if (mounted) {
        setState(() {
          _screenState = 2; // Success screen!
        });

        Timer(const Duration(milliseconds: 1400), () {
          if (mounted) {
            Navigator.pop(context); // Close the dialog
            widget.onSuccess();
          }
        });
      }
    });
  }

  void _simulatePaymentFailure() {
    setState(() {
      _screenState = 1; // Transition to processing loader screen
    });

    Timer(const Duration(milliseconds: 900), () {
      if (mounted) {
        setState(() {
          _screenState = 0; // Return to checkout screen
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Sample Payment Test: Simulated payment decline/failure.'),
            backgroundColor: Colors.redAccent,
            duration: Duration(seconds: 3),
          ),
        );
      }
    });
  }

  void _startRealCheckout() async {
    setState(() {
      _screenState = 1; // Transition to processing loader screen
    });

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final createOrderUrl = Uri.parse('$baseUrl/api/payment/create-order');

      // 1. Request Order Creation on Backend
      final response = await ApiClient().post(
        createOrderUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'amount': widget.amount,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final String orderId = data['orderId'];

          // 2. Launch Hosted Checkout URL
          final String checkoutUrl = '$baseUrl/checkout.html'
              '?orderId=$orderId'
              '&amount=${data['amount']}'
              '&key=${widget.apiKey}';

          final Uri uri = Uri.parse(checkoutUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);

            // 3. Start Polling Order Status
            _statusPollTimer?.cancel();
            _statusPollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
              try {
                final statusUrl = Uri.parse('$baseUrl/api/payment/status/$orderId');
                final statusResponse = await ApiClient().get(statusUrl, retry: false);
                if (statusResponse.statusCode == 200) {
                  final statusData = jsonDecode(statusResponse.body);
                  if (statusData['success'] == true) {
                    final String status = statusData['status'];
                    if (status == 'verified') {
                      timer.cancel();
                      if (mounted) {
                        setState(() {
                          _screenState = 2; // Success screen!
                        });
                        
                        // Complete checkout after showing success screen
                        Timer(const Duration(milliseconds: 1500), () {
                          if (mounted) {
                            Navigator.pop(context); // Close the dialog
                            widget.onSuccess();
                          }
                        });
                      }
                    } else if (status == 'failed') {
                      timer.cancel();
                      if (mounted) {
                        setState(() {
                          _screenState = 0; // Return to checkout screen to retry
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Payment verification failed. Please try again.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  }
                }
              } catch (pollErr) {
                debugPrint("Error polling status: $pollErr");
              }
            });

          } else {
            throw Exception('Could not launch payment browser');
          }
        } else {
          throw Exception(data['error'] ?? 'Order creation failed');
        }
      } else {
        throw Exception('Server responded with status code ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _screenState = 0; // Back to checkout input screen
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Checkout initialization failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _startRealPayout() async {
    setState(() {
      _screenState = 1; // Transition to processing loader screen
    });

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final payoutUrl = Uri.parse('$baseUrl/api/payment/payout');
      final currentUid = FirebaseService().currentUid ?? 'unknown_pilot';

      final response = await ApiClient().post(
        payoutUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': currentUid,
          'amount': widget.amount,
          'targetAccount': widget.targetAccount ?? 'driver@upi',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          if (mounted) {
            setState(() {
              _screenState = 2; // Success screen!
            });

            Timer(const Duration(milliseconds: 1500), () {
              if (mounted) {
                Navigator.pop(context); // Close the dialog
                widget.onSuccess();
              }
            });
          }
        } else {
          throw Exception(data['error'] ?? 'Payout execution failed');
        }
      } else {
        throw Exception('Server responded with status code ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _screenState = 0; // Return to payout detail view to retry
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payout failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_screenState == 0) {
      return widget.isPayout ? _buildPayoutDetailsScreen() : _buildCheckoutScreen();
    } else if (_screenState == 1) {
      return _buildProcessingScreen();
    } else {
      return _buildSuccessScreen();
    }
  }

  // --- CUSTOMER CHECKOUT GATEWAY ---
  Widget _buildCheckoutScreen() {
    return Container(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Razorpay branding header
          Container(
            color: const Color(0xFF0B2545),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Razorpay Blue-box styled Logo
                        Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(
                            color: Color(0xFF3399FF),
                            borderRadius: BorderRadius.all(Radius.circular(4)),
                          ),
                          child: const Center(
                            child: Text(
                              'R',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Razorpay Secure',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.description,
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                Text(
                  '₹${widget.amount.toStringAsFixed(2)}',
                  style: GoogleFonts.robotoMono(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),

          // Mode Banner with Interactive Developer Toggle
          Container(
            color: _isDeveloperSampleMode ? const Color(0xFFEFF6FF) : Colors.green.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Icon(
                  _isDeveloperSampleMode ? Icons.science_rounded : Icons.check_circle_outline,
                  color: _isDeveloperSampleMode ? const Color(0xFF1D4ED8) : Colors.green.shade900,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isDeveloperSampleMode
                            ? 'SAMPLE MODE (Developer Test)'
                            : 'LIVE MODE | ${widget.apiKey}',
                        style: GoogleFonts.robotoMono(
                          color: _isDeveloperSampleMode ? const Color(0xFF1E40AF) : Colors.green.shade900,
                          fontWeight: FontWeight.bold,
                          fontSize: 10.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _isDeveloperSampleMode
                            ? 'Instant test simulation • No real money required'
                            : 'Live production checkout active',
                        style: GoogleFonts.inter(
                          fontSize: 9.5,
                          color: _isDeveloperSampleMode ? const Color(0xFF3B82F6) : Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () {
                    setState(() {
                      _isDeveloperSampleMode = !_isDeveloperSampleMode;
                    });
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _isDeveloperSampleMode ? const Color(0xFFDBEAFE) : Colors.green.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _isDeveloperSampleMode ? const Color(0xFF93C5FD) : Colors.green.shade400,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isDeveloperSampleMode ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                          size: 18,
                          color: _isDeveloperSampleMode ? const Color(0xFF1D4ED8) : Colors.green.shade800,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isDeveloperSampleMode ? 'Sample' : 'Live',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: _isDeveloperSampleMode ? const Color(0xFF1D4ED8) : Colors.green.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Payment Mode Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                _buildMethodTab('UPI', Icons.qr_code_2_rounded),
                const SizedBox(width: 10),
                _buildMethodTab('Card', Icons.credit_card_rounded),
                const SizedBox(width: 10),
                _buildMethodTab('Netbanking', Icons.account_balance_rounded),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Interactive Details Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: _selectedMethod == 'UPI'
                ? _buildUpiSection()
                : _selectedMethod == 'Card'
                    ? _buildCardSection()
                    : _buildNetbankingSection(),
          ),

          const SizedBox(height: 24),

          // Proceed Button & Secure badge
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              children: [
                if (_isDeveloperSampleMode) ...[
                  // Primary Developer Sample Payment Button
                  ElevatedButton(
                    onPressed: _simulatePaymentSuccess,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E60FF),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.bolt_rounded, color: Colors.amberAccent, size: 22),
                        const SizedBox(width: 6),
                        Text(
                          'Pay Now (Sample Test) • ₹${widget.amount.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _simulatePaymentFailure,
                          icon: const Icon(Icons.close_rounded, size: 14, color: Colors.red),
                          label: Text(
                            'Simulate Failure',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.red.shade700,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.red.shade200),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _startRealCheckout,
                          icon: const Icon(Icons.open_in_browser_rounded, size: 14, color: Color(0xFF1E60FF)),
                          label: Text(
                            'Real Checkout',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1E60FF),
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.blue.shade200),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  // Live Mode Real Checkout Button
                  ElevatedButton(
                    onPressed: _startRealCheckout,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3399FF),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.security, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Pay Now • ₹${widget.amount.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _simulatePaymentSuccess,
                    icon: const Icon(Icons.bolt_rounded, size: 14, color: Color(0xFF1E60FF)),
                    label: Text(
                      'Developer Quick Test (Sample Bypass)',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF1E60FF)),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isDeveloperSampleMode ? Icons.science_outlined : Icons.lock,
                      color: _isDeveloperSampleMode ? const Color(0xFF3B82F6) : Colors.grey.shade400,
                      size: 13,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isDeveloperSampleMode
                          ? 'DEVELOPER TEST ENVIRONMENT • NO REAL MONEY DEDUCTED'
                          : 'SECURED BY RAZORPAY • PCI-DSS COMPLIANT',
                      style: GoogleFonts.robotoMono(
                        fontSize: 8.5,
                        color: _isDeveloperSampleMode ? const Color(0xFF2563EB) : Colors.grey.shade400,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- PARTNER PAYOUT GATEWAY ---
  Widget _buildPayoutDetailsScreen() {
    return Container(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Payout branding header
          Container(
            color: const Color(0xFF0F172A),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: Color(0xFF5046E5),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 14),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Razorpay Payouts',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                Text(
                  '₹${widget.amount.toStringAsFixed(2)}',
                  style: GoogleFonts.robotoMono(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),

          // Mode Banner with Interactive Developer Toggle
          Container(
            color: _isDeveloperSampleMode ? const Color(0xFFEFF6FF) : Colors.green.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Icon(
                  _isDeveloperSampleMode ? Icons.science_rounded : Icons.check_circle_outline,
                  color: _isDeveloperSampleMode ? const Color(0xFF1D4ED8) : Colors.green.shade900,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isDeveloperSampleMode
                            ? 'SAMPLE MODE (Developer Cashout)'
                            : 'LIVE MODE | ${widget.apiKey}',
                        style: GoogleFonts.robotoMono(
                          color: _isDeveloperSampleMode ? const Color(0xFF1E40AF) : Colors.green.shade900,
                          fontWeight: FontWeight.bold,
                          fontSize: 10.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _isDeveloperSampleMode
                            ? 'Instant payout simulation • No RazorpayX balance required'
                            : 'Live RazorpayX payout transfer active',
                        style: GoogleFonts.inter(
                          fontSize: 9.5,
                          color: _isDeveloperSampleMode ? const Color(0xFF3B82F6) : Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () {
                    setState(() {
                      _isDeveloperSampleMode = !_isDeveloperSampleMode;
                    });
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _isDeveloperSampleMode ? const Color(0xFFDBEAFE) : Colors.green.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _isDeveloperSampleMode ? const Color(0xFF93C5FD) : Colors.green.shade400,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isDeveloperSampleMode ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                          size: 18,
                          color: _isDeveloperSampleMode ? const Color(0xFF1D4ED8) : Colors.green.shade800,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isDeveloperSampleMode ? 'Sample' : 'Live',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: _isDeveloperSampleMode ? const Color(0xFF1D4ED8) : Colors.green.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RECIPIENT ACCOUNT DETAILS',
                  style: GoogleFonts.robotoMono(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF5046E5).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.account_balance_wallet, color: Color(0xFF5046E5), size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.targetAccount ?? 'driver@upi',
                              style: GoogleFonts.robotoMono(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Instant UPI Transfer (VPA)',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Transaction Description',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.description,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Payout button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              children: [
                if (_isDeveloperSampleMode) ...[
                  ElevatedButton(
                    onPressed: _simulatePaymentSuccess,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5046E5),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.bolt_rounded, color: Colors.amberAccent, size: 22),
                        const SizedBox(width: 6),
                        Text(
                          'Confirm Cashout (Sample Test) • ₹${widget.amount.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _startRealPayout,
                    icon: const Icon(Icons.flash_on, size: 14, color: Color(0xFF5046E5)),
                    label: Text(
                      'Real RazorpayX Payout',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF5046E5)),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.indigo.shade200),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ] else ...[
                  ElevatedButton(
                    onPressed: _startRealPayout,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5046E5),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.flash_on, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Confirm Instant Cashout',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _simulatePaymentSuccess,
                    icon: const Icon(Icons.bolt_rounded, size: 14, color: Color(0xFF5046E5)),
                    label: Text(
                      'Developer Quick Test (Sample Cashout)',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF5046E5)),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isDeveloperSampleMode ? Icons.science_outlined : Icons.lock,
                      color: _isDeveloperSampleMode ? const Color(0xFF6366F1) : Colors.grey.shade400,
                      size: 13,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isDeveloperSampleMode
                          ? 'DEVELOPER TEST ENVIRONMENT • NO REAL PAYOUT WIRE'
                          : 'DIRECT BANK WIRE VIA RAZORPAY API',
                      style: GoogleFonts.robotoMono(
                        fontSize: 8.5,
                        color: _isDeveloperSampleMode ? const Color(0xFF4F46E5) : Colors.grey.shade400,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodTab(String method, IconData icon) {
    final isSelected = _selectedMethod == method;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedMethod = method;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF3399FF).withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? const Color(0xFF3399FF) : Colors.grey.shade300,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? const Color(0xFF3399FF) : Colors.grey.shade600,
                size: 20,
              ),
              const SizedBox(height: 6),
              Text(
                method,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? const Color(0xFF3399FF) : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUpiSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: ChoiceChip(
                label: const Text('UPI ID'),
                selected: _upiSubMethod == 'vpa',
                onSelected: (val) {
                  if (val) setState(() => _upiSubMethod = 'vpa');
                },
                selectedColor: const Color(0xFF3399FF).withOpacity(0.15),
                checkmarkColor: const Color(0xFF3399FF),
                labelStyle: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  color: _upiSubMethod == 'vpa' ? const Color(0xFF3399FF) : Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ChoiceChip(
                label: const Text('QR Scan'),
                selected: _upiSubMethod == 'qr',
                onSelected: (val) {
                  if (val) setState(() => _upiSubMethod = 'qr');
                },
                selectedColor: const Color(0xFF3399FF).withOpacity(0.15),
                checkmarkColor: const Color(0xFF3399FF),
                labelStyle: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  color: _upiSubMethod == 'qr' ? const Color(0xFF3399FF) : Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_upiSubMethod == 'vpa') ...[
          Text(
            'ENTER UPI ID',
            style: GoogleFonts.robotoMono(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _upiController,
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              hintText: 'yourname@okbank',
              prefixIcon: const Icon(Icons.alternate_email, color: Color(0xFF3399FF)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'UPI apps supported: Google Pay, PhonePe, Paytm, BHIM UPI etc.',
            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey),
          ),
        ] else ...[
          Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300, width: 2),
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.white,
                  ),
                  child: Image.network(
                    'https://api.qrserver.com/v1/create-qr-code/?size=150x150&data='
                    'upi://pay?pa=staydriv@axisbank%26pn=StayDriv%26am=${widget.amount}%26cu=INR',
                    width: 150,
                    height: 150,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 150,
                        height: 150,
                        color: Colors.grey.shade100,
                        child: const Icon(Icons.qr_code_2_rounded, size: 80, color: Colors.grey),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Scan this QR Code from any UPI App to Pay',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Amount: ₹${widget.amount.toStringAsFixed(2)}',
                  style: GoogleFonts.robotoMono(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: const Color(0xFF3399FF),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCardSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'CARD NUMBER',
          style: GoogleFonts.robotoMono(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _cardNoController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            hintText: '4111 1111 1111 1111',
            prefixIcon: const Icon(Icons.credit_card, color: Color(0xFF3399FF)),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'EXPIRY DATE',
                    style: GoogleFonts.robotoMono(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _cardExpiryController,
                    decoration: InputDecoration(
                      hintText: 'MM/YY',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'CVV',
                    style: GoogleFonts.robotoMono(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _cardCvvController,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: '123',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNetbankingSection() {
    final List<Map<String, String>> popularBanks = [
      {'name': 'State Bank of India', 'code': 'SBI'},
      {'name': 'HDFC Bank', 'code': 'HDFC'},
      {'name': 'ICICI Bank', 'code': 'ICICI'},
      {'name': 'Axis Bank', 'code': 'AXIS'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'POPULAR BANKS',
          style: GoogleFonts.robotoMono(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: popularBanks.map((bank) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                bank['code']!,
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // --- LOADER STATE ---
  Widget _buildProcessingScreen() {
    final themeColor = widget.isPayout ? const Color(0xFF5046E5) : const Color(0xFF3399FF);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(themeColor),
            strokeWidth: 4,
          ),
          const SizedBox(height: 32),
          Text(
            widget.isPayout ? 'Processing Cashout...' : 'Authorizing Transaction...',
            style: GoogleFonts.hankenGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.isPayout 
                ? 'Contacting banking servers via Razorpay Payouts'
                : 'Securing connection with bank server',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  // --- SUCCESS STATE ---
  Widget _buildSuccessScreen() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: Color(0xFF10B981),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 44),
          ),
          const SizedBox(height: 32),
          Text(
            widget.isPayout ? 'Cashout Completed!' : 'Payment Successful!',
            style: GoogleFonts.hankenGrotesk(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.isPayout
                ? 'Funds transferred successfully. ID: payout_${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}'
                : 'Transaction successful. ID: pay_${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}',
            textAlign: TextAlign.center,
            style: GoogleFonts.robotoMono(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}
