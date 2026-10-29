import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api_client.dart';
import '../../../core/firebase_service.dart';
import '../../../core/network_config.dart';
import '../../../core/theme.dart';
import '../../../core/booking_manager.dart';
import '../../../core/socket_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RideCompletedPaymentPanel extends StatefulWidget {
  final Map<String, dynamic> booking;
  final VoidCallback onPaymentCompleted;

  const RideCompletedPaymentPanel({
    super.key,
    required this.booking,
    required this.onPaymentCompleted,
  });

  @override
  State<RideCompletedPaymentPanel> createState() => _RideCompletedPaymentPanelState();
}

class _RideCompletedPaymentPanelState extends State<RideCompletedPaymentPanel> {
  // Static in-memory cache to ensure QR code stability and prevent blinking across parent rebuilds
  static final Map<String, Map<String, dynamic>> _cachedCustomerQrSessions = {};

  late Razorpay _razorpay;
  
  bool _isProcessing = false;
  bool _isPaid = false;
  String _paidMethod = '';
  String _transactionReference = '';
  String? _activeOrderId;

  // Real Wallet Balance from Backend
  double _walletBalance = 0.0;
  bool _isLoadingWallet = true;

  // Gateway Supported Payment Methods Configuration
  // ignore: unused_field
  bool _isPaytmConfigured = false;

  // Scan & Pay / UPI QR state
  bool _showQrSection = false;
  String? _qrImageUrl;
  String? _upiUri;
  // ignore: unused_field
  String? _payeeUpiId;
  // ignore: unused_field
  String? _payeeName;
  bool _isLoadingQr = false;
  String _pendingVerificationNote = '';

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleRazorpaySuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handleRazorpayError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);

    // Restore cached QR session if already created
    final cached = _cachedCustomerQrSessions[_bookingId];
    if (cached != null) {
      _qrImageUrl = cached['qrImageUrl'] as String?;
      _upiUri = cached['upiUri'] as String?;
      _payeeUpiId = (cached['payeeUpiId'] ?? cached['upiId']) as String?;
      _payeeName = cached['payeeName'] as String?;
    }

    final status = widget.booking['paymentStatus'] as String?;
    final isAlreadyPaid = (status == 'paid') || BookingManager().isBookingPaid(_bookingId);
    if (isAlreadyPaid) {
      _isPaid = true;
      _paidMethod = widget.booking['paymentOption'] ?? 'Paid';
      _transactionReference = widget.booking['paymentId'] ?? widget.booking['bookingId'] ?? '';
    }

    if (_bookingId.isNotEmpty) {
      SharedPreferences.getInstance().then((prefs) {
        if (prefs.getBool('paid_booking_$_bookingId') == true && mounted) {
          setState(() {
            _isPaid = true;
            if (_paidMethod.isEmpty) _paidMethod = 'Paid';
          });
        }
      });
    }

    SocketService().addPaymentSuccessListener(_handleSocketPaymentSuccess);
    _verifyPaymentStatusWithServer();
    _fetchRealCustomerWallet();
    _fetchGatewayPaymentMethods();
  }

  void _handleSocketPaymentSuccess(Map<String, dynamic> data) {
    final bId = data['bookingId']?.toString();
    if (bId != null && bId == _bookingId && mounted) {
      setState(() {
        _isPaid = true;
        _paidMethod = data['paymentOption']?.toString() ?? data['method']?.toString() ?? 'Paid';
        _transactionReference = data['paymentId']?.toString() ?? data['transactionId']?.toString() ?? bId;
        _isProcessing = false;
      });
      BookingManager().markBookingAsPaid(
        bookingId: _bookingId,
        paymentOption: _paidMethod,
        paymentId: _transactionReference,
      );
      widget.onPaymentCompleted();
    }
  }

  Future<void> _verifyPaymentStatusWithServer() async {
    if (_bookingId.isEmpty) return;
    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/booking/$_bookingId/payment-status');
      final res = await ApiClient().get(uri, retry: false);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['paymentStatus'] == 'paid' && mounted) {
          setState(() {
            _isPaid = true;
            _paidMethod = data['paymentOption'] ?? 'Paid';
            _transactionReference = data['paymentId'] ?? data['transactionId'] ?? _bookingId;
          });
          BookingManager().markBookingAsPaid(
            bookingId: _bookingId,
            paymentOption: _paidMethod,
            paymentId: _transactionReference,
          );
          widget.onPaymentCompleted();
        }
      }
    } catch (e) {
      debugPrint('[PaymentPanel] Backend payment verification note: $e');
    }
  }

  // Fetch real customer wallet balance from backend
  Future<void> _fetchRealCustomerWallet() async {
    final uid = FirebaseService().currentUid;
    if (uid == null || uid.isEmpty) {
      if (mounted) setState(() => _isLoadingWallet = false);
      return;
    }

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/customer/wallet/$uid');
      final res = await ApiClient().get(uri, retry: false);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && mounted) {
          setState(() {
            _walletBalance = (data['walletBalance'] as num?)?.toDouble() ?? 0.0;
            _isLoadingWallet = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('[PaymentPanel] Wallet balance fetch note: $e');
    }

    if (mounted) {
      setState(() => _isLoadingWallet = false);
    }
  }

  // Fetch payment configuration from backend (only enables Paytm if configured)
  Future<void> _fetchGatewayPaymentMethods() async {
    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/payment/methods');
      final res = await ApiClient().get(uri, retry: false);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && mounted) {
          setState(() {
            _isPaytmConfigured = data['methods']?['paytmWallet'] == true;
          });
        }
      }
    } catch (e) {
      debugPrint('[PaymentPanel] Gateway config note: $e');
    }
  }

  @override
  void dispose() {
    SocketService().removePaymentSuccessListener(_handleSocketPaymentSuccess);
    _razorpay.clear();
    super.dispose();
  }

  String get _bookingId {
    final directId = widget.booking['bookingId'] ?? widget.booking['id'] ?? widget.booking['_id'];
    if (directId != null && directId.toString().isNotEmpty && directId != 'booking_active') {
      return directId.toString();
    }
    final active = BookingManager().activeBooking;
    final activeId = active?['bookingId'] ?? active?['id'] ?? active?['_id'];
    if (activeId != null && activeId.toString().isNotEmpty && activeId != 'booking_active') {
      return activeId.toString();
    }
    return directId?.toString() ?? '';
  }

  double get _fareAmount {
    final priceStr = widget.booking['price'] as String? ?? '₹0';
    final cleanStr = priceStr.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(cleanStr) ?? 0.0;
  }

  String get _displayFare {
    final fare = _fareAmount;
    if (fare == fare.roundToDouble()) {
      return '₹${fare.toInt()}';
    }
    return '₹${fare.toStringAsFixed(2)}';
  }

  // --- 1. CASH PAYMENT FLOW ---
  void _handleCashPayment() {
    if (_isPaid) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Confirm Cash Payment',
          style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: Text(
          'Please confirm that you are paying $_displayFare in cash directly to your StayDriv pilot.',
          style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _confirmCashOnServer();
            },
            child: Text('Confirm Paid', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCashOnServer() async {
    setState(() => _isProcessing = true);

    final currentUid = FirebaseService().currentUid ?? '';
    final pId = widget.booking['passengerId'] ?? currentUid;

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/booking/pay-cash');
      final res = await ApiClient().post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'bookingId': _bookingId,
          'uid': currentUid,
          'passengerId': pId,
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && mounted) {
          final txId = data['transactionId'] ?? 'CASH_CONFIRMED';
          setState(() {
            _isPaid = true;
            _paidMethod = 'Cash Payment';
            _transactionReference = txId;
          });
          BookingManager().markBookingAsPaid(
            bookingId: _bookingId,
            paymentOption: 'Cash Payment',
            paymentId: txId,
          );
          widget.onPaymentCompleted();
          return;
        }
      }
    } catch (e) {
      debugPrint('[PaymentPanel] Note on cash network sync: $e');
    }

    final fallbackTxId = 'CASH_${DateTime.now().millisecondsSinceEpoch}';
    if (mounted) {
      setState(() {
        _isPaid = true;
        _paidMethod = 'Cash Payment';
        _transactionReference = fallbackTxId;
      });
      BookingManager().markBookingAsPaid(
        bookingId: _bookingId,
        paymentOption: 'Cash Payment',
        paymentId: fallbackTxId,
      );
      widget.onPaymentCompleted();
    }
  }

  // --- 2. RAZORPAY UPI / ONLINE PAYMENT FLOW ---
  // ignore: unused_element
  Future<void> _handleRazorpayPayment() async {
    if (_isPaid) return;

    final double fare = _fareAmount;
    if (fare <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid ride fare amount'), backgroundColor: Color(0xFFDC2626)),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/payment/create-order');

      String phone = widget.booking['passengerPhone'] ?? '';
      String email = 'customer@staydriv.com';
      try {
        final uid = FirebaseService().currentUid;
        if (uid != null) {
          final doc = await FirebaseService().getProfile('customer', uid);
          if (doc.exists && doc.data() != null) {
            final data = doc.data() as Map<String, dynamic>;
            phone = data['phone'] ?? phone;
            email = data['email'] ?? email;
          }
        }
      } catch (_) {}

      final res = await ApiClient().post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'amount': fare,
          'bookingId': _bookingId,
          'customerPhone': phone,
          'customerEmail': email,
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          if (data['alreadyPaid'] == true || data['paymentStatus'] == 'paid') {
            if (mounted) {
              setState(() {
                _isPaid = true;
                _paidMethod = data['paymentOption'] ?? 'Online';
                _transactionReference = data['paymentId'] ?? data['orderId'] ?? _bookingId;
                _isProcessing = false;
              });
              BookingManager().markBookingAsPaid(
                bookingId: _bookingId,
                paymentOption: _paidMethod,
                paymentId: _transactionReference,
              );
              widget.onPaymentCompleted();
            }
            return;
          }

          _activeOrderId = data['orderId'];
          final int amountInPaise = data['amount'] is int ? data['amount'] : (data['amount'] as num).toInt();
          final String keyId = data['keyId'] ?? 'rzp_live_Ta9cOGnIySuBCb';

          final options = {
            'key': keyId,
            'amount': amountInPaise,
            'name': 'StayDriv',
            'description': 'StayDriv Ride Payment',
            'order_id': _activeOrderId,
            'timeout': 300,
            'prefill': {
              'contact': phone,
              'email': email,
            },
            'theme': {
              'color': '#004AC6',
            },
            'modal': {
              'confirm_close': true,
            },
            'send_sms_hash': true,
          };

          _razorpay.open(options);
          return;
        }
      }
      throw Exception('Failed to create Razorpay payment order');
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open payment checkout: $e'), backgroundColor: const Color(0xFFDC2626)),
        );
      }
    }
  }

  void _handleRazorpaySuccess(PaymentSuccessResponse response) async {
    debugPrint('[RIDE PAYMENT SUCCESS] Order: ${response.orderId}, Payment: ${response.paymentId}');

    if (!mounted) return;
    setState(() => _isProcessing = true);

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/payment/verify-signature');

      final res = await ApiClient().post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'razorpay_order_id': response.orderId ?? _activeOrderId,
          'razorpay_payment_id': response.paymentId,
          'razorpay_signature': response.signature,
          'bookingId': _bookingId,
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && mounted) {
          final pId = response.paymentId ?? data['paymentId'] ?? '';
          setState(() {
            _isPaid = true;
            _paidMethod = 'Razorpay UPI';
            _transactionReference = pId;
            _isProcessing = false;
          });
          BookingManager().markBookingAsPaid(
            bookingId: _bookingId,
            paymentOption: 'Razorpay UPI',
            paymentId: pId,
          );
          widget.onPaymentCompleted();
          return;
        }
      }
      throw Exception('Payment signature verification rejected by server');
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Verification error: $e'), backgroundColor: const Color(0xFFDC2626)),
        );
      }
    }
  }

  void _handleRazorpayError(PaymentFailureResponse response) {
    debugPrint('[RIDE PAYMENT ERROR] Message: ${response.message}');
    if (!mounted) return;
    setState(() => _isProcessing = false);

    String errMsg = 'Payment cancelled or failed. You can retry or choose another option.';
    if (response.message != null && response.message!.isNotEmpty) {
      try {
        final parsed = jsonDecode(response.message!);
        if (parsed['error'] != null && parsed['error']['description'] != null) {
          errMsg = parsed['error']['description'];
        }
      } catch (_) {}
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(errMsg), backgroundColor: const Color(0xFFDC2626)),
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    debugPrint('[RIDE PAYMENT WALLET] ${response.walletName}');
  }

  // --- 3. STAYDRIV WALLET PAYMENT FLOW ---
  void _handleStayDrivWalletPayment() {
    if (_isPaid) return;

    final fare = _fareAmount;
    if (_walletBalance < fare) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined, color: Color(0xFFDC2626), size: 24),
              const SizedBox(width: 8),
              Text('Insufficient Balance', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Text(
            'Your StayDriv Wallet balance is ₹${_walletBalance.toStringAsFixed(2)}, but the ride fare is $_displayFare.\n\nPlease select Cash Payment to complete your payment.',
            style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade700, height: 1.4),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: Text('Choose Another Option', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ],
        ),
      );
      return;
    }

    // Sufficient balance: show confirmation dialog
    final balanceAfter = _walletBalance - fare;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF004AC6), size: 24),
            const SizedBox(width: 8),
            Text('Pay from Wallet', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Confirm deducting $_displayFare from your StayDriv Wallet balance.', style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade700)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Current Balance:', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600)),
                      Text('₹${_walletBalance.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Ride Fare:', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600)),
                      Text('- $_displayFare', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFDC2626))),
                    ],
                  ),
                  const Divider(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Balance After:', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                      Text('₹${balanceAfter.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF16A34A))),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF004AC6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _processWalletDeduction();
            },
            child: Text('Confirm & Pay', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _processWalletDeduction() async {
    setState(() => _isProcessing = true);

    final currentUid = FirebaseService().currentUid ?? '';
    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/customer/wallet/pay-ride');
      final res = await ApiClient().post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'bookingId': _bookingId,
          'uid': currentUid,
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && mounted) {
          final txId = data['transactionId'] ?? 'WALLET_${DateTime.now().millisecondsSinceEpoch}';
          setState(() {
            _isPaid = true;
            _paidMethod = 'StayDriv Wallet';
            _transactionReference = txId;
            _walletBalance = (data['walletBalance'] as num?)?.toDouble() ?? (_walletBalance - _fareAmount);
            _isProcessing = false;
          });
          BookingManager().markBookingAsPaid(
            bookingId: _bookingId,
            paymentOption: 'StayDriv Wallet',
            paymentId: txId,
          );
          widget.onPaymentCompleted();
          return;
        }
      } else {
        final data = jsonDecode(res.body);
        if (data['insufficientBalance'] == true && mounted) {
          setState(() => _isProcessing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['message'] ?? 'Insufficient wallet balance'), backgroundColor: const Color(0xFFDC2626)),
          );
          return;
        }
      }
      throw Exception('Server rejected wallet deduction');
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Wallet deduction failed: $e'), backgroundColor: const Color(0xFFDC2626)),
        );
      }
    }
  }

  // --- 4. SCAN & PAY / UPI QR FLOW ---
  // ignore: unused_element
  void _handleScanAndPayTap() {
    if (_isPaid) return;

    setState(() {
      _showQrSection = !_showQrSection;
      _pendingVerificationNote = '';
    });

    if (_showQrSection && _qrImageUrl == null) {
      _fetchDynamicQrCode();
    }
  }

  Future<void> _fetchDynamicQrCode() async {
    // Return cached session immediately to avoid any re-rendering or blinking
    if (_cachedCustomerQrSessions.containsKey(_bookingId)) {
      final cached = _cachedCustomerQrSessions[_bookingId]!;
      setState(() {
        _qrImageUrl = cached['qrImageUrl'] as String?;
        _upiUri = cached['upiUri'] as String?;
        _payeeUpiId = (cached['payeeUpiId'] ?? cached['upiId']) as String?;
        _payeeName = cached['payeeName'] as String?;
        _isLoadingQr = false;
      });
      return;
    }

    setState(() => _isLoadingQr = true);

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/booking/payment/qr/$_bookingId');
      final res = await ApiClient().get(uri);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && mounted) {
          final qrImg = data['qrImageUrl'] as String?;
          final upi = data['upiUri'] as String?;
          final uId = data['upiId'] as String?;
          final pName = data['payeeName'] as String?;

          _cachedCustomerQrSessions[_bookingId] = {
            'qrImageUrl': qrImg,
            'upiUri': upi,
            'upiId': uId,
            'payeeName': pName,
          };

          setState(() {
            _qrImageUrl = qrImg;
            _upiUri = upi;
            _payeeUpiId = uId;
            _payeeName = pName;
            _isLoadingQr = false;
          });
          return;
        }
      }
      throw Exception('QR generation returned status ${res.statusCode}');
    } catch (e) {
      if (mounted) {
        final fare = _fareAmount;
        final cleanBookingRef = _bookingId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
        final fallbackUri = 'upi://pay?pa=staydriv@icici&pn=StayDriv%20Pilot&am=${fare.toStringAsFixed(2)}&cu=INR&tn=Ride_$cleanBookingRef&tr=TXN_$cleanBookingRef';
        final fallbackQrUrl = 'https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=${Uri.encodeComponent(fallbackUri)}';

        _cachedCustomerQrSessions[_bookingId] = {
          'qrImageUrl': fallbackQrUrl,
          'upiUri': fallbackUri,
          'upiId': 'staydriv@icici',
          'payeeName': 'StayDriv Pilot',
        };

        setState(() {
          _upiUri = fallbackUri;
          _payeeUpiId = 'staydriv@icici';
          _payeeName = 'StayDriv Pilot';
          _qrImageUrl = fallbackQrUrl;
          _isLoadingQr = false;
        });
      }
    }
  }

  Future<void> _launchUpiApp() async {
    if (_upiUri == null) return;
    try {
      final uri = Uri.parse(_upiUri!);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No supported UPI app found. Please scan the QR code above.'), backgroundColor: Color(0xFFD97706)),
        );
      }
    } catch (e) {
      debugPrint('[PaymentPanel] UPI launch note: $e');
    }
  }

  Future<void> _verifyScanAndPay() async {
    setState(() {
      _isProcessing = true;
      _pendingVerificationNote = '';
    });

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/booking/payment/verify-upi');
      final res = await ApiClient().post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'bookingId': _bookingId,
          'referenceId': 'SCAN_PAY_${DateTime.now().millisecondsSinceEpoch}',
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && mounted) {
          final txId = data['transactionId'] ?? 'UPI_QR_CONFIRMED';
          setState(() {
            _isPaid = true;
            _paidMethod = 'Scan & Pay (UPI QR)';
            _transactionReference = txId;
            _isProcessing = false;
            _showQrSection = false;
            _cachedCustomerQrSessions.remove(_bookingId);
          });
          BookingManager().markBookingAsPaid(
            bookingId: _bookingId,
            paymentOption: 'Scan & Pay (UPI QR)',
            paymentId: txId,
          );
          widget.onPaymentCompleted();
          return;
        }
      }
      throw Exception('Payment not verified yet');
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _pendingVerificationNote = 'Payment Pending: Confirmation not received yet. Please complete payment in your UPI app and tap Verify.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF004AC6), width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0x2B000000), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: _isPaid ? _buildPaidReceiptView() : _buildSelectPaymentModeView(),
    );
  }

  // --- VIEW 1: SELECT PAYMENT MODE (MATCHING USER SCREENSHOT) ---
  Widget _buildSelectPaymentModeView() {
    final fare = _fareAmount;
    final isWalletSufficient = _walletBalance >= fare;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ride Completed',
          style: GoogleFonts.hankenGrotesk(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.onSurfaceColor,
          ),
        ),
        const SizedBox(height: 12),

        // Orange Banner: Ride Fare
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF37A20),
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.center,
          child: Text(
            'Ride Fare',
            style: GoogleFonts.hankenGrotesk(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Large Fare Amount: e.g. ₹46
        Text(
          _displayFare,
          style: GoogleFonts.hankenGrotesk(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: AppTheme.onSurfaceColor,
          ),
        ),

        const SizedBox(height: 16),

        // Subheader: SELECT PAYMENT MODE
        Text(
          'SELECT PAYMENT MODE',
          style: GoogleFonts.robotoMono(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF004AC6),
            letterSpacing: 1.0,
          ),
        ),

        const SizedBox(height: 12),

        // Option 1: Cash Payment
        _buildPaymentOptionCard(
          iconWidget: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF16A34A), width: 1.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.money_rounded, color: Color(0xFF16A34A), size: 20),
          ),
          title: 'Cash Payment',
          onTap: _isProcessing ? null : _handleCashPayment,
        ),

        const SizedBox(height: 10),

        // Option 2: StayDriv Wallet (Real backend balance)
        _buildPaymentOptionCard(
          iconWidget: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF7C3AED), size: 24),
          title: 'StayDriv Wallet',
          subtitleText: _isLoadingWallet
              ? 'Loading balance...'
              : (isWalletSufficient
                  ? 'Balance: ₹${_walletBalance.toStringAsFixed(2)}'
                  : 'Insufficient: ₹${_walletBalance.toStringAsFixed(2)}'),
          badgeText: _isLoadingWallet ? null : (isWalletSufficient ? '₹${_walletBalance.toInt()}' : 'LOW BALANCE'),
          badgeColor: isWalletSufficient ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
          onTap: _isProcessing ? null : _handleStayDrivWalletPayment,
        ),

        if (_isProcessing) ...[
          const SizedBox(height: 16),
          const Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF004AC6))),
                SizedBox(width: 10),
                Text('Connecting to Secure Gateway...', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // --- Dynamic Scan & Pay Expandable View ---
  // ignore: unused_element
  Widget _buildScanAndPayExpandedView() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF86EFAC), width: 1.2),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Dynamic Ride QR', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF166534))),
              Text(_displayFare, style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 14, color: const Color(0xFF166534))),
            ],
          ),
          const SizedBox(height: 10),
          if (_isLoadingQr)
            const Padding(
              padding: EdgeInsets.all(24.0),
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF16A34A)),
            )
          else if (_qrImageUrl != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
              child: Image.network(
                _qrImageUrl!,
                key: ValueKey('cust_qr_$_bookingId'),
                width: 160,
                height: 160,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                cacheWidth: 320,
                cacheHeight: 320,
              ),
            ),
            const SizedBox(height: 8),
            Text('Scan with PhonePe, Google Pay, Paytm or BHIM', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade700)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.open_in_new_rounded, size: 14),
                    label: Text('Open UPI App', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF004AC6),
                      side: const BorderSide(color: Color(0xFF004AC6)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _launchUpiApp,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 14),
                    label: Text('Verify Paid', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _verifyScanAndPay,
                  ),
                ),
              ],
            ),
          ],
          if (_pendingVerificationNote.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _pendingVerificationNote,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFD97706), fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentOptionCard({
    required Widget iconWidget,
    required String title,
    String? subtitleText,
    String? badgeText,
    Color? badgeColor,
    required VoidCallback? onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                iconWidget,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.onSurfaceColor,
                          height: 1.2,
                        ),
                      ),
                      if (subtitleText != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitleText,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: subtitleText.startsWith('Insufficient') ? const Color(0xFFDC2626) : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (badgeText != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: badgeColor ?? const Color(0xFF3B4890),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badgeText,
                      style: GoogleFonts.robotoMono(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8), size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- VIEW 2: PAYMENT SUCCESSFUL RECEIPT ---
  Widget _buildPaidReceiptView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(
            color: Color(0xFFDCFCE7),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded, color: Color(0xFF16A34A), size: 34),
        ),
        const SizedBox(height: 12),
        Text(
          'Payment Successful',
          style: GoogleFonts.hankenGrotesk(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.onSurfaceColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$_displayFare paid via $_paidMethod',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF16A34A),
          ),
        ),
        if (_transactionReference.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Ref: $_transactionReference',
            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: widget.onPaymentCompleted,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              'Continue to Rate Pilot',
              style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }
}
