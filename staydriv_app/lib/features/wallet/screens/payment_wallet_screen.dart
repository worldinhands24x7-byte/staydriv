import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../core/api_client.dart';
import '../../../core/firebase_service.dart';
import '../../../core/network_config.dart';
import '../../../core/theme.dart';

class PaymentWalletScreen extends StatefulWidget {
  final double initialBalance;

  const PaymentWalletScreen({
    super.key,
    this.initialBalance = 0.0,
  });

  @override
  State<PaymentWalletScreen> createState() => _PaymentWalletScreenState();
}

class _PaymentWalletScreenState extends State<PaymentWalletScreen> {
  late Razorpay _razorpay;
  final TextEditingController _amountController = TextEditingController(text: '100');
  
  double _walletBalance = 0.0;
  bool _isLoading = false;
  bool _isProcessingTopUp = false;
  String? _activeOrderId;
  double _pendingTopUpAmount = 0.0;
  List<dynamic> _transactions = [];

  // Quick amount suggestions
  final List<int> _quickAmounts = [100, 200, 500, 1000, 2000];

  @override
  void initState() {
    super.initState();
    _walletBalance = widget.initialBalance;

    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);

    _fetchWalletData();
  }

  @override
  void dispose() {
    _razorpay.clear();
    _amountController.dispose();
    super.dispose();
  }

  String get _currentUid => FirebaseService().currentUid ?? 'guest';

  // --- Fetch live wallet balance and ledger from StayDriv backend ---
  Future<void> _fetchWalletData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/customer/wallet/$_currentUid');
      final response = await ApiClient().get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          if (mounted) {
            setState(() {
              _walletBalance = (data['walletBalance'] as num?)?.toDouble() ?? 0.0;
              _transactions = (data['transactions'] as List<dynamic>?) ?? [];
            });
          }
        }
      }
    } catch (e) {
      debugPrint('[WALLET] Error fetching wallet data: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // --- Start Real-time Razorpay Top-up Order ---
  Future<void> _initiateTopUp() async {
    final double? amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount < 1.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid amount (Minimum ₹1.00)'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    setState(() {
      _isProcessingTopUp = true;
      _pendingTopUpAmount = amount;
    });

    try {
      // Get customer phone/email
      String phone = '';
      String email = 'customer@staydriv.com';
      try {
        final doc = await FirebaseService().getProfile('customer', _currentUid);
        if (doc.exists && doc.data() != null) {
          final data = doc.data() as Map<String, dynamic>;
          phone = data['phone'] ?? phone;
          email = data['email'] ?? email;
        }
      } catch (_) {}

      final baseUrl = NetworkConfig.backendUrl;
      final createOrderUri = Uri.parse('$baseUrl/api/customer/wallet/topup/create-order');

      final response = await ApiClient().post(
        createOrderUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': _currentUid,
          'amount': amount,
          'customerPhone': phone,
          'customerEmail': email,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          _activeOrderId = data['orderId'];
          final int amountInPaise = data['amount'];
          final String keyId = data['keyId'] ?? 'rzp_live_Ta9cOGnIySuBCb';

          final options = {
            'key': keyId,
            'amount': amountInPaise,
            'name': 'StayDriv Wallet',
            'description': 'Add Money to StayDriv Wallet',
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
        } else {
          throw Exception(data['error'] ?? 'Order creation failed');
        }
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessingTopUp = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not initiate payment: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  // --- Razorpay Payment Success Handler ---
  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    debugPrint('[WALLET SUCCESS] Order: ${response.orderId}, Payment: ${response.paymentId}');

    if (!mounted) return;
    setState(() => _isProcessingTopUp = true);

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final verifyUri = Uri.parse('$baseUrl/api/customer/wallet/topup/verify');

      final verifyResponse = await ApiClient().post(
        verifyUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': _currentUid,
          'razorpay_order_id': response.orderId ?? _activeOrderId,
          'razorpay_payment_id': response.paymentId,
          'razorpay_signature': response.signature,
          'amount': _pendingTopUpAmount,
        }),
      );

      if (verifyResponse.statusCode == 200) {
        final data = jsonDecode(verifyResponse.body);
        if (data['success'] == true) {
          final updatedBal = (data['walletBalance'] as num?)?.toDouble() ?? (_walletBalance + _pendingTopUpAmount);
          if (mounted) {
            setState(() {
              _walletBalance = updatedBal;
              _isProcessingTopUp = false;
            });

            // Show confirmed active UPI message
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Add Money to StayDriv wallet via UPI is active. Added ₹${_pendingTopUpAmount.toStringAsFixed(2)} to wallet.',
                  style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600),
                ),
                backgroundColor: const Color(0xFF16A34A),
                duration: const Duration(seconds: 4),
              ),
            );

            // Refresh ledger
            _fetchWalletData();
          }
          return;
        } else {
          throw Exception(data['error'] ?? 'Payment verification rejected');
        }
      } else {
        throw Exception('Server verification returned ${verifyResponse.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessingTopUp = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification error: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  // --- Razorpay Payment Failure Handler ---
  void _handlePaymentError(PaymentFailureResponse response) {
    debugPrint('[WALLET ERROR] Code: ${response.code}, Message: ${response.message}');
    if (!mounted) return;
    setState(() => _isProcessingTopUp = false);

    String errMsg = 'Payment cancelled or failed.';
    if (response.message != null && response.message!.isNotEmpty) {
      try {
        final parsed = jsonDecode(response.message!);
        if (parsed['error'] != null && parsed['error']['description'] != null) {
          errMsg = parsed['error']['description'];
        } else {
          errMsg = response.message!;
        }
      } catch (_) {
        errMsg = response.message!;
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errMsg),
        backgroundColor: const Color(0xFFDC2626),
      ),
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Selected external wallet: ${response.walletName}'),
        backgroundColor: const Color(0xFF004AC6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context, _walletBalance);
      },
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.onSurfaceColor, size: 20),
            onPressed: () => Navigator.pop(context, _walletBalance),
          ),
          title: Text(
            'Payment Wallet',
            style: GoogleFonts.hankenGrotesk(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.onSurfaceColor,
            ),
          ),
          actions: [
            IconButton(
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
                    )
                  : const Icon(Icons.refresh_rounded, color: AppTheme.primaryColor),
              tooltip: 'Refresh balance',
              onPressed: _isLoading ? null : _fetchWalletData,
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _fetchWalletData,
          color: AppTheme.primaryColor,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Balance Card
                _buildBalanceCard(),

                const SizedBox(height: 24),

                // 2. Add Money Section
                _buildAddMoneySection(),

                const SizedBox(height: 28),

                // 3. Transactions Ledger Header & List
                _buildTransactionsHeader(),
                const SizedBox(height: 12),
                _buildTransactionsList(),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF003FA8), Color(0xFF0056E0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF004AC6).withOpacity(0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shield_rounded, color: Colors.white, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'StayDriv Secure Wallet',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Image.network(
                'https://cdn.razorpay.com/static/assets/logo/payment.svg',
                height: 16,
                errorBuilder: (ctx, err, stack) => const Icon(Icons.lock_outline_rounded, color: Colors.white70, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Total Available Balance',
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '₹',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                _walletBalance.toStringAsFixed(2),
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF4ADE80), size: 14),
              const SizedBox(width: 6),
              Text(
                'Instant ride checkout & zero cancellation hold',
                style: GoogleFonts.inter(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddMoneySection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add Money to Wallet',
            style: GoogleFonts.hankenGrotesk(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppTheme.onSurfaceColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Fast top-up via UPI (GPay, PhonePe, Paytm), Cards & Net Banking',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),

          // Amount input field
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: GoogleFonts.hankenGrotesk(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.onSurfaceColor,
            ),
            decoration: InputDecoration(
              prefixIcon: Container(
                padding: const EdgeInsets.only(left: 14, right: 6),
                alignment: Alignment.centerLeft,
                width: 38,
                child: Text(
                  '₹',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
              hintText: 'Enter amount',
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Quick Amount Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _quickAmounts.map((amt) {
                final isSelected = _amountController.text == amt.toString();
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(
                      '+ ₹$amt',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : AppTheme.onSurfaceColor,
                      ),
                    ),
                    backgroundColor: isSelected ? AppTheme.primaryColor : const Color(0xFFF1F5F9),
                    side: BorderSide(
                      color: isSelected ? AppTheme.primaryColor : Colors.transparent,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    onPressed: () {
                      setState(() {
                        _amountController.text = amt.toString();
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 18),

          // Add Money Action Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isProcessingTopUp ? null : _initiateTopUp,
              icon: _isProcessingTopUp
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                    )
                  : const Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 20),
              label: Text(
                _isProcessingTopUp ? 'Opening Razorpay...' : 'Proceed to Add Money',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                disabledBackgroundColor: AppTheme.primaryColor.withOpacity(0.6),
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),

          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_rounded, size: 13, color: Color(0xFF16A34A)),
              const SizedBox(width: 5),
              Text(
                '100% Secure 256-bit encrypted Razorpay Checkout',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Transaction History',
          style: GoogleFonts.hankenGrotesk(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: AppTheme.onSurfaceColor,
          ),
        ),
        Text(
          '${_transactions.length} entries',
          style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildTransactionsList() {
    if (_isLoading && _transactions.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 36),
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );
    }

    if (_transactions.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.receipt_long_rounded, size: 36, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 14),
            Text(
              'No Transactions Yet',
              style: GoogleFonts.hankenGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.onSurfaceColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add money to your StayDriv wallet to see your transaction history here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _transactions.length,
        separatorBuilder: (ctx, index) => Divider(height: 1, color: Colors.grey.shade100),
        itemBuilder: (ctx, index) {
          final tx = _transactions[index] as Map<String, dynamic>;
          final type = tx['type'] ?? 'credit';
          final isCredit = type == 'credit';
          final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
          final description = tx['description'] ?? (isCredit ? 'Wallet Top-up' : 'Ride Payment');
          final status = tx['status'] ?? 'Success';
          final paymentId = tx['razorpayPaymentId'] ?? '';
          final createdAtRaw = tx['createdAt'] ?? '';

          String formattedDate = '';
          if (createdAtRaw.isNotEmpty) {
            try {
              final dt = DateTime.parse(createdAtRaw).toLocal();
              formattedDate = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
            } catch (_) {
              formattedDate = createdAtRaw;
            }
          }

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isCredit ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                color: isCredit ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                size: 20,
              ),
            ),
            title: Text(
              description,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.onSurfaceColor,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(
                  formattedDate.isNotEmpty ? formattedDate : status,
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600),
                ),
                if (paymentId.isNotEmpty)
                  Text(
                    'ID: $paymentId',
                    style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400),
                  ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isCredit ? '+' : '-'} ₹${amount.toStringAsFixed(2)}',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isCredit ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF16A34A),
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
}
