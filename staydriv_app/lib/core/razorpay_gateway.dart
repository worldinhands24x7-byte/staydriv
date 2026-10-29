import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'js_stub.dart' if (dart.library.js) 'dart:js' as js;
import 'network_config.dart';
import 'firebase_service.dart';
import 'api_client.dart';

/// Official Production Razorpay Payment Gateway for StayDriv
/// 
/// Uses Razorpay Flutter SDK for real payment collection (UPI, Cards, NetBanking, Wallets).
/// All orders are securely created on the StayDriv backend, and signatures are
/// cryptographically verified on the backend before completing payments.
class RazorpayGateway extends StatefulWidget {
  final double amount;
  final String description;
  final bool isPayout;
  final String? targetAccount;
  final String? bookingId;
  final String? customerPhone;
  final String? customerEmail;
  final VoidCallback onSuccess;
  final Function(String error)? onFailure;

  const RazorpayGateway({
    super.key,
    required this.amount,
    required this.description,
    this.isPayout = false,
    this.targetAccount,
    this.bookingId,
    this.customerPhone,
    this.customerEmail,
    required this.onSuccess,
    this.onFailure,
  });

  /// Entrypoint to open Razorpay payment flow across StayDriv screens.
  static void show(
    BuildContext context, {
    required double amount,
    required String description,
    bool isPayout = false,
    String? targetAccount,
    String? bookingId,
    String? customerPhone,
    String? customerEmail,
    required VoidCallback onSuccess,
    Function(String error)? onFailure,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: RazorpayGateway(
              amount: amount,
              description: description,
              isPayout: isPayout,
              targetAccount: targetAccount,
              bookingId: bookingId,
              customerPhone: customerPhone,
              customerEmail: customerEmail,
              onSuccess: onSuccess,
              onFailure: onFailure,
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
  // 0: Initializing/Ready, 1: Verifying Signature on Server, 2: Success, 3: Error
  int _status = 0;
  String _statusMessage = 'Connecting to Razorpay Secure Gateway...';
  String _errorMessage = '';
  String? _activeOrderId;

  late Razorpay _razorpay;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.isPayout) {
        _processPayout();
      } else {
        _initiateRazorpayOrder();
      }
    });
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  // --- 1. INITIATE REAL-TIME RAZORPAY ORDER ---
  Future<void> _initiateRazorpayOrder() async {
    setState(() {
      _status = 0;
      _statusMessage = 'Creating secure payment order...';
      _errorMessage = '';
    });

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final createOrderUrl = Uri.parse('$baseUrl/api/payment/create-order');

      // Fetch passenger contact details if available
      String phone = widget.customerPhone ?? '';
      String email = widget.customerEmail ?? 'customer@staydriv.com';
      final currentUid = FirebaseService().currentUid;
      if (phone.isEmpty && currentUid != null) {
        try {
          final doc = await FirebaseService().getProfile('customer', currentUid);
          if (doc.exists && doc.data() != null) {
            final data = doc.data() as Map<String, dynamic>;
            phone = data['phone'] ?? phone;
            email = data['email'] ?? email;
          }
        } catch (_) {}
      }

      final response = await ApiClient().post(
        createOrderUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'amount': widget.amount,
          'bookingId': widget.bookingId ?? '',
          'customerPhone': phone,
          'customerEmail': email,
        }),
        retry: true,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final String orderId = data['orderId'];
          final int amountInPaise = data['amount'];
          final String keyId = data['keyId'] ?? 'rzp_live_Ta9cOGnIySuBCb';
          _activeOrderId = orderId;

          // Open Native Razorpay Checkout
          final options = {
            'key': keyId,
            'amount': amountInPaise,
            'name': 'StayDriv',
            'description': widget.description,
            'order_id': orderId,
            'timeout': 300,
            'prefill': {
              'contact': phone,
              'email': email,
            },
            'theme': {
              'color': '#0B2545',
            },
            'modal': {
              'confirm_close': true,
            },
            'send_sms_hash': true,
          };

          setState(() {
            _statusMessage = 'Opening Razorpay Checkout...';
          });

          if (kIsWeb) {
            js.context['onStayDrivGatewayPaymentResult'] = js.allowInterop((resultStr) {
              try {
                final Map<String, dynamic> res = jsonDecode(resultStr.toString());
                final status = res['status']?.toString();
                if (status == 'success') {
                  final resp = PaymentSuccessResponse(
                    res['razorpay_payment_id']?.toString(),
                    res['razorpay_order_id']?.toString() ?? orderId,
                    res['razorpay_signature']?.toString(),
                    res,
                  );
                  _handlePaymentSuccess(resp);
                } else if (status == 'cancelled') {
                  _handlePaymentError(PaymentFailureResponse(
                    Razorpay.PAYMENT_CANCELLED,
                    'Payment was cancelled by user.',
                    null,
                  ));
                } else {
                  final errMsg = res['message']?.toString() ?? 'Payment failed.';
                  final errCode = res['code'] is int ? res['code'] as int : Razorpay.UNKNOWN_ERROR;
                  _handlePaymentError(PaymentFailureResponse(
                    errCode,
                    errMsg,
                    res['error'] is Map ? res['error'] as Map : null,
                  ));
                }
              } catch (e) {
                _handlePaymentError(PaymentFailureResponse(Razorpay.UNKNOWN_ERROR, 'Error parsing result: $e', null));
              }
            });

            js.context.callMethod('openStayDrivRazorpayCheckout', [
              jsonEncode(options),
              'onStayDrivGatewayPaymentResult',
            ]);
          } else {
            _razorpay.open(options);
          }
        } else {
          throw Exception(data['error'] ?? 'Order creation failed');
        }
      } else {
        throw Exception('Server responded with HTTP ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 3;
          _errorMessage = 'Could not start checkout: $e';
        });
      }
    }
  }

  // --- 2. HANDLE RAZORPAY NATIVE PAYMENT SUCCESS ---
  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    debugPrint("[RAZORPAY SUCCESS] Payment ID: ${response.paymentId}, Order ID: ${response.orderId}");

    if (!mounted) return;
    setState(() {
      _status = 1; // Transition to Server Signature Verification
      _statusMessage = 'Verifying payment with StayDriv secure server...';
    });

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final verifyUrl = Uri.parse('$baseUrl/api/payment/verify-signature');

      final verifyResponse = await ApiClient().post(
        verifyUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'razorpay_order_id': response.orderId ?? _activeOrderId,
          'razorpay_payment_id': response.paymentId,
          'razorpay_signature': response.signature,
          'bookingId': widget.bookingId ?? '',
        }),
        retry: true,
      );

      if (verifyResponse.statusCode == 200) {
        final data = jsonDecode(verifyResponse.body);
        if (data['success'] == true) {
          if (mounted) {
            setState(() {
              _status = 2; // Verified Success
              _statusMessage = 'Payment Verified & Captured!';
            });

            // Allow user to see success checkmark, then pop and invoke onSuccess
            Timer(const Duration(milliseconds: 1400), () {
              if (mounted) {
                Navigator.of(context, rootNavigator: true).pop();
                widget.onSuccess();
              }
            });
          }
        } else {
          throw Exception(data['error'] ?? 'Signature verification rejected by server');
        }
      } else {
        throw Exception('Server returned ${verifyResponse.statusCode} during signature check');
      }
    } catch (err) {
      if (mounted) {
        setState(() {
          _status = 3;
          _errorMessage = 'Payment verification failed: $err';
        });
        if (widget.onFailure != null) {
          widget.onFailure!(_errorMessage);
        }
      }
    }
  }

  // --- 3. HANDLE PAYMENT ERROR / CANCEL ---
  void _handlePaymentError(PaymentFailureResponse response) {
    debugPrint("[RAZORPAY FAILED] Code: ${response.code}, Message: ${response.message}");

    if (!mounted) return;
    String userMsg = 'Payment was cancelled or could not be completed.';
    if (response.message != null && response.message!.isNotEmpty) {
      userMsg = response.message!;
    }

    setState(() {
      _status = 3;
      _errorMessage = userMsg;
    });

    if (widget.onFailure != null) {
      widget.onFailure!(userMsg);
    }
  }

  // --- 4. HANDLE EXTERNAL WALLET ---
  void _handleExternalWallet(ExternalWalletResponse response) {
    debugPrint("[RAZORPAY WALLET] Selected: ${response.walletName}");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Redirecting to ${response.walletName ?? "wallet"}...'),
        backgroundColor: const Color(0xFF0B2545),
      ),
    );
  }

  // --- 5. PILOT EARNINGS PAYOUT HANDLER ---
  Future<void> _processPayout() async {
    setState(() {
      _status = 0;
      _statusMessage = 'Processing secure earnings withdrawal...';
      _errorMessage = '';
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
          'targetAccount': widget.targetAccount ?? 'pilot@upi',
        }),
        retry: true,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          if (mounted) {
            setState(() {
              _status = 2;
              _statusMessage = data['message'] ?? 'Payout Processed Successfully!';
            });

            Timer(const Duration(milliseconds: 1400), () {
              if (mounted) {
                Navigator.of(context, rootNavigator: true).pop();
                widget.onSuccess();
              }
            });
          }
        } else {
          throw Exception(data['error'] ?? 'Payout failed');
        }
      } else {
        String errMsg = 'Server responded with HTTP ${response.statusCode}';
        try {
          final data = jsonDecode(response.body);
          if (data['error'] != null && data['error'].toString().isNotEmpty) {
            errMsg = data['error'].toString();
          } else if (data['message'] != null && data['message'].toString().isNotEmpty) {
            errMsg = data['message'].toString();
          }
        } catch (_) {}
        throw Exception(errMsg);
      }
    } catch (e) {
      if (mounted) {
        String userErr = e.toString();
        if (userErr.startsWith('Exception: ')) {
          userErr = userErr.substring(11);
        }
        setState(() {
          _status = 3;
          _errorMessage = userErr;
        });
        if (widget.onFailure != null) {
          widget.onFailure!(userErr);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Logo & Branding
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF0B2545),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Text(
                    'S',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'StayDriv Pay',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0B2545),
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.lock_outline, size: 12, color: Colors.green),
                        const SizedBox(width: 4),
                        Text(
                          'Powered by Razorpay Live',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.green.shade800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '₹${widget.amount.toStringAsFixed(2)}',
                  style: GoogleFonts.robotoMono(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: const Color(0xFF0B2545),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 24),

          // Body Content depending on Status
          if (_status == 0 || _status == 1) ...[
            const SizedBox(
              width: 46,
              height: 46,
              child: CircularProgressIndicator(
                strokeWidth: 3.5,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0B2545)),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please complete payment via UPI, Card, NetBanking or Wallet.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ] else if (_status == 2) ...[
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: Color(0xFFDCFCE7),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded, color: Color(0xFF16A34A), size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              'Payment Successful!',
              style: GoogleFonts.hankenGrotesk(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF16A34A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Transaction verified and captured securely.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
          ] else ...[
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: Color(0xFFFEE2E2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded, color: Color(0xFFDC2626), size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              'Payment Not Completed',
              style: GoogleFonts.hankenGrotesk(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFFDC2626),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage.isNotEmpty
                  ? _errorMessage
                  : 'The transaction was cancelled or declined.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      Navigator.of(context, rootNavigator: true).pop();
                    },
                    child: Text('Close', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0B2545),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _initiateRazorpayOrder,
                    child: Text(
                      'Retry',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
