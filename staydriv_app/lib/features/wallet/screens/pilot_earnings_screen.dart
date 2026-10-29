import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/api_client.dart';
import '../../../core/firebase_service.dart';
import '../../../core/network_config.dart';
import '../../../core/socket_service.dart';
import '../../../core/theme.dart';

class PilotEarningsScreen extends StatefulWidget {
  final double initialBalance;

  const PilotEarningsScreen({
    super.key,
    this.initialBalance = 0.0,
  });

  @override
  State<PilotEarningsScreen> createState() => _PilotEarningsScreenState();
}

class _PilotEarningsScreenState extends State<PilotEarningsScreen> {
  final TextEditingController _amountController = TextEditingController(text: '500');

  double _totalEarnings = 0.0;
  double _availableBalance = 0.0;
  double _withdrawableAmount = 0.0;
  double _withdrawnAmount = 0.0;
  double _pendingAmount = 0.0;
  double _reservedBalance = 0.0;
  Map<String, dynamic> _bankAccount = {};
  List<dynamic> _withdrawals = [];

  bool _isLoading = false;
  bool _isSubmittingWithdrawal = false;

  Map<String, dynamic>? _dailyPlanData;
  bool _isLoadingDailyPlan = false;
  bool _isPayingDailyPlan = false;

  final List<int> _quickAmounts = [100, 500, 1000, 2000];

  @override
  void initState() {
    super.initState();
    _availableBalance = widget.initialBalance;
    _withdrawableAmount = widget.initialBalance;
    SocketService().addPilotDailyPlanListener(_onDailyPlanSocketUpdate);
    SocketService().addPilotBookingAccessListener(_onBookingAccessSocketUpdate);
    _fetchEarnings();
    _fetchDailyPlan();
  }

  @override
  void dispose() {
    SocketService().removePilotDailyPlanListener(_onDailyPlanSocketUpdate);
    SocketService().removePilotBookingAccessListener(_onBookingAccessSocketUpdate);
    _amountController.dispose();
    super.dispose();
  }

  void _onDailyPlanSocketUpdate(Map<String, dynamic> data) {
    if (!mounted) return;
    final pid = data['pilotId'] ?? data['uid'] ?? data['pilotUid'];
    if (pid == null || pid.toString() == _currentUid) {
      _fetchDailyPlan();
      _fetchEarnings();
    }
  }

  void _onBookingAccessSocketUpdate(Map<String, dynamic> data) {
    if (!mounted) return;
    final pid = data['pilotId'] ?? data['uid'];
    if (pid == null || pid.toString() == _currentUid) {
      _fetchDailyPlan();
    }
  }

  String get _currentUid => FirebaseService().currentUid ?? 'pilot_guest';

  bool get _hasLinkedBank {
    final acc = (_bankAccount['accountNumber'] as String?)?.trim() ?? '';
    final upi = (_bankAccount['upiId'] as String?)?.trim() ?? '';
    return acc.isNotEmpty || upi.isNotEmpty;
  }

  // --- 1. Fetch live earnings and withdrawal history from backend ---
  Future<void> _fetchEarnings() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/pilot/earnings/$_currentUid');
      final response = await ApiClient().get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && mounted) {
          setState(() {
            _totalEarnings = (data['totalEarnings'] as num?)?.toDouble() ?? 0.0;
            _availableBalance = (data['availableBalance'] as num?)?.toDouble() ?? 0.0;
            _withdrawableAmount = (data['withdrawableAmount'] as num?)?.toDouble() ?? 0.0;
            _withdrawnAmount = (data['withdrawnAmount'] as num?)?.toDouble() ?? 0.0;
            _pendingAmount = (data['pendingAmount'] as num?)?.toDouble() ?? 0.0;
            _reservedBalance = (data['reservedBalance'] as num?)?.toDouble() ?? 0.0;
            _bankAccount = (data['bankAccount'] as Map<String, dynamic>?) ?? {};
            _withdrawals = (data['withdrawals'] as List<dynamic>?) ?? [];
          });
        }
      }
    } catch (e) {
      debugPrint('[PILOT EARNINGS] Error fetching earnings: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // --- 1.5 Fetch ₹20 Daily Plan Status & Booking Access ---
  Future<void> _fetchDailyPlan() async {
    if (!mounted) return;
    setState(() => _isLoadingDailyPlan = true);
    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/pilot/daily-plan/$_currentUid');
      final response = await ApiClient().get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && mounted) {
          setState(() {
            _dailyPlanData = Map<String, dynamic>.from(data);
          });
        }
      }
    } catch (e) {
      debugPrint('[PILOT EARNINGS] Error fetching daily plan: $e');
    } finally {
      if (mounted) setState(() => _isLoadingDailyPlan = false);
    }
  }

  Future<void> _payDailyPlanFee() async {
    if (_isPayingDailyPlan) return;
    final status = (_dailyPlanData?['planStatus'] ?? 'none').toString().toLowerCase();
    final expiresAtStr = _dailyPlanData?['expiresAt'] as String?;
    if (status == 'paid' && expiresAtStr != null) {
      try {
        final exp = DateTime.parse(expiresAtStr);
        if (DateTime.now().isBefore(exp)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Your ₹20 Daily Plan is already active. Duplicate payment is protected.'),
              backgroundColor: Color(0xFF16A34A),
            ),
          );
          return;
        }
      } catch (_) {}
    }

    setState(() => _isPayingDailyPlan = true);
    try {
      final txnId = 'DP_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(99999)}';
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/pilot/daily-plan/pay');
      final response = await ApiClient().post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'pilotUidOrPhone': _currentUid,
          'paymentMethod': 'UPI',
          'transactionId': txnId,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        if (mounted) {
          _showDailyPlanSuccessDialog(txnId);
          await _fetchDailyPlan();
          await _fetchEarnings();
        }
      } else {
        throw Exception(data['message'] ?? 'Payment failed');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment Error: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPayingDailyPlan = false);
    }
  }

  void _showDailyPlanSuccessDialog(String txnId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(color: Color(0xFFDCFCE7), shape: BoxShape.circle),
              child: const Icon(Icons.verified_rounded, color: Color(0xFF16A34A), size: 40),
            ),
            const SizedBox(height: 16),
            Text(
              '₹20 Daily Plan Activated!',
              style: GoogleFonts.hankenGrotesk(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'You will receive 100% of your ride and food-delivery earnings with 0% StayDriv commission for the next 24 hours.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
              child: Text(
                'Txn: $txnId',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Done', style: GoogleFonts.hankenGrotesk(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDailyPlanPaymentModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.bolt_rounded, color: Color(0xFF2563EB), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Activate ₹20 Daily Plan', style: GoogleFonts.hankenGrotesk(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('100% Ride & Food Delivery Earnings', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  _detailRow('Daily Plan Fee', '₹20.00 / 24 Hours', isBold: true, valueColor: const Color(0xFF0F172A)),
                  const Divider(height: 16),
                  _detailRow('StayDriv Commission', '0% (NO DEDUCTION)', isBold: true, valueColor: const Color(0xFF16A34A)),
                  const Divider(height: 16),
                  _detailRow('Ride Booking Earnings', '100% credited to pilot', valueColor: const Color(0xFF16A34A)),
                  const Divider(height: 16),
                  _detailRow('Food Delivery Earnings', '100% credited to pilot', valueColor: const Color(0xFF16A34A)),
                  const Divider(height: 16),
                  _detailRow('Plan Separation', '₹20 fee is never deducted from fares'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _payDailyPlanFee();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Pay ₹20 & Activate 100% Earnings', style: GoogleFonts.hankenGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 2. Link or Update Bank Account Dialog ---
  void _showBankDetailsDialog() {
    final formKey = GlobalKey<FormState>();
    final isUpiMode = ValueNotifier<bool>((_bankAccount['upiId'] ?? '').toString().isNotEmpty && (_bankAccount['accountNumber'] ?? '').toString().isEmpty);
    
    final holderCtrl = TextEditingController(text: _bankAccount['accountHolderName'] ?? '');
    final bankCtrl = TextEditingController(text: _bankAccount['bankName'] ?? '');
    final accCtrl = TextEditingController(text: _bankAccount['accountNumber'] ?? '');
    final ifscCtrl = TextEditingController(text: _bankAccount['ifsc'] ?? '');
    final upiCtrl = TextEditingController(text: _bankAccount['upiId'] ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text(
                'Linked Payout Account',
                style: GoogleFonts.hankenGrotesk(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
              ),
              const SizedBox(height: 4),
              Text(
                'Earnings and salary advances will be settled to this verified account.',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),

              ValueListenableBuilder<bool>(
                valueListenable: isUpiMode,
                builder: (context, useUpi, _) {
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('Bank Account (IMPS/NEFT)'),
                              selected: !useUpi,
                              onSelected: (val) => isUpiMode.value = false,
                              selectedColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                              labelStyle: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: !useUpi ? AppTheme.primaryColor : Colors.grey.shade700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('UPI ID (Instant)'),
                              selected: useUpi,
                              onSelected: (val) => isUpiMode.value = true,
                              selectedColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                              labelStyle: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: useUpi ? AppTheme.primaryColor : Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (!useUpi) ...[
                        TextFormField(
                          controller: holderCtrl,
                          decoration: const InputDecoration(labelText: 'Account Holder Name', border: OutlineInputBorder()),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter account holder name' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: bankCtrl,
                          decoration: const InputDecoration(labelText: 'Bank Name (e.g. SBI, HDFC, ICICI)', border: OutlineInputBorder()),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter bank name' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: accCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Bank Account Number', border: OutlineInputBorder()),
                          validator: (v) {
                            if (v == null || v.trim().length < 9) return 'Enter valid account number (min 9 digits)';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: ifscCtrl,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(labelText: 'Bank IFSC Code', border: OutlineInputBorder(), hintText: 'SBIN0001234'),
                          validator: (v) {
                            if (v == null || v.trim().length < 5) return 'Enter valid IFSC code';
                            return null;
                          },
                        ),
                      ] else ...[
                        TextFormField(
                          controller: holderCtrl,
                          decoration: const InputDecoration(labelText: 'Beneficiary Name', border: OutlineInputBorder()),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter name' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: upiCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'UPI ID / VPA',
                            border: OutlineInputBorder(),
                            hintText: 'mobile@upi or pilot@okaxis',
                          ),
                          validator: (v) {
                            if (v == null || !v.contains('@')) return 'Enter valid UPI ID containing @';
                            return null;
                          },
                        ),
                      ],
                    ],
                  );
                },
              ),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    Navigator.pop(ctx);
                    
                    setState(() => _isLoading = true);
                    try {
                      final baseUrl = NetworkConfig.backendUrl;
                      final uri = Uri.parse('$baseUrl/api/pilot/bank-account/save');
                      final res = await ApiClient().post(
                        uri,
                        headers: {'Content-Type': 'application/json'},
                        body: jsonEncode({
                          'uid': _currentUid,
                          'accountNumber': isUpiMode.value ? '' : accCtrl.text.trim(),
                          'ifsc': isUpiMode.value ? '' : ifscCtrl.text.trim().toUpperCase(),
                          'bankName': isUpiMode.value ? 'UPI Settlement' : bankCtrl.text.trim(),
                          'accountHolderName': holderCtrl.text.trim(),
                          'upiId': isUpiMode.value ? upiCtrl.text.trim() : '',
                        }),
                      );

                      if (res.statusCode == 200) {
                        final data = jsonDecode(res.body);
                        if (data['success'] == true) {
                          if (mounted) {
                            setState(() {
                              _bankAccount = data['bankAccount'] ?? {};
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Payout account linked and verified successfully!'),
                                backgroundColor: Color(0xFF16A34A),
                              ),
                            );
                          }
                          return;
                        }
                      }
                      throw Exception('Failed to save bank details');
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error saving bank details: $e'), backgroundColor: const Color(0xFFDC2626)),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _isLoading = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Save & Verify Payout Account', style: GoogleFonts.hankenGrotesk(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- 3. Confirmation Dialog before creating withdrawal request ---
  void _showWithdrawalConfirmationSheet(double amount) {
    final String targetInfo;
    if ((_bankAccount['upiId'] as String?)?.isNotEmpty ?? false) {
      targetInfo = 'UPI ID: ${_bankAccount['upiId']}';
    } else {
      final acc = (_bankAccount['accountNumber'] as String?) ?? '';
      final masked = acc.length > 4 ? '•••• ${acc.substring(acc.length - 4)}' : acc;
      targetInfo = '${_bankAccount['bankName'] ?? 'Bank Account'} ($masked)';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        bool isSubmitting = false;
        String? submissionError;

        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(modalCtx).padding.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(3)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Confirm Advance Withdrawal',
                      style: GoogleFonts.hankenGrotesk(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Please review the withdrawal request details before submitting.',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 18),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Withdrawal Amount', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600)),
                              Text(
                                '₹${amount.toStringAsFixed(2)}',
                                style: GoogleFonts.hankenGrotesk(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF16A34A)),
                              ),
                            ],
                          ),
                          const Divider(height: 18),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Settlement Destination', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600)),
                              Flexible(
                                child: Text(
                                  targetInfo,
                                  textAlign: TextAlign.right,
                                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.onSurfaceColor),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 18),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Available Balance', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600)),
                              Text(
                                '₹${_availableBalance.toStringAsFixed(2)}',
                                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.onSurfaceColor),
                              ),
                            ],
                          ),
                          const Divider(height: 18),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Applicable Charges', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600)),
                              Text(
                                '₹0.00 (Zero Fee)',
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF16A34A)),
                              ),
                            ],
                          ),
                          const Divider(height: 18),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Initial Status', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(6)),
                                child: Text(
                                  'PENDING APPROVAL',
                                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFFD97706)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 15, color: Color(0xFF64748B)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Funds will be safely reserved from your available balance while the request is verified by finance before payout.',
                            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600, height: 1.3),
                          ),
                        ),
                      ],
                    ),

                    if (submissionError != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(10)),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                submissionError!,
                                style: GoogleFonts.inter(color: const Color(0xFFDC2626), fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                setModalState(() {
                                  isSubmitting = true;
                                  submissionError = null;
                                });
                                setState(() => _isSubmittingWithdrawal = true);

                                try {
                                  final idempotencyKey = 'WTH_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(999999)}';
                                  final baseUrl = NetworkConfig.backendUrl;
                                  final uri = Uri.parse('$baseUrl/api/pilot/withdrawals/create');

                                  final response = await ApiClient().post(
                                    uri,
                                    headers: {
                                      'Content-Type': 'application/json',
                                      'Idempotency-Key': idempotencyKey,
                                    },
                                    body: jsonEncode({
                                      'uid': _currentUid,
                                      'amount': amount,
                                      'idempotencyKey': idempotencyKey,
                                      'targetAccount': targetInfo,
                                    }),
                                  );

                                  final data = jsonDecode(response.body);
                                  if (response.statusCode == 200 && data['success'] == true) {
                                    if (modalCtx.mounted) {
                                      Navigator.pop(modalCtx);
                                    }
                                    if (mounted) {
                                      final payoutId = data['payoutId'] ?? data['withdrawalId'] ?? 'WTH';
                                      _showWithdrawalSuccessDialog(amount, payoutId);
                                      _fetchEarnings();
                                    }
                                  } else {
                                    throw Exception(data['error'] ?? 'Withdrawal request failed');
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    setModalState(() {
                                      isSubmitting = false;
                                      submissionError = 'Could not submit request: $e';
                                    });
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() => _isSubmittingWithdrawal = false);
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          disabledBackgroundColor: AppTheme.primaryColor.withValues(alpha: 0.6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: isSubmitting
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                                  const SizedBox(width: 10),
                                  Text('Submitting Request...', style: GoogleFonts.hankenGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                                ],
                              )
                            : Text(
                                'Confirm & Submit Request',
                                style: GoogleFonts.hankenGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showWithdrawalSuccessDialog(double amount, String refId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(color: Color(0xFFDCFCE7), shape: BoxShape.circle),
              child: const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 40),
            ),
            const SizedBox(height: 16),
            Text(
              'Request Submitted',
              style: GoogleFonts.hankenGrotesk(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
            ),
            const SizedBox(height: 8),
            Text(
              'Your advance withdrawal of ₹${amount.toStringAsFixed(2)} has been submitted. Status: Pending Approval.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
              child: Text(
                'Reference: $refId',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.onSurfaceColor),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Done', style: GoogleFonts.hankenGrotesk(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showWithdrawalDetailsModal(Map<String, dynamic> w) {
    final id = w['withdrawalId'] ?? w['payoutId'] ?? 'WTH';
    final amount = (w['amount'] as num?)?.toDouble() ?? 0.0;
    final status = (w['status'] as String? ?? 'pending_approval').toLowerCase();
    final destination = w['maskedDestination'] ?? w['targetAccount'] ?? 'Linked Account';
    final utr = w['utr'] ?? '';
    final reason = w['rejectionReason'] ?? w['failureReason'] ?? '';
    final createdAtRaw = w['createdAt'] ?? '';

    String statusTitle = 'PENDING APPROVAL';
    Color statusColor = const Color(0xFFD97706);
    Color statusBg = const Color(0xFFFEF3C7);
    String statusDesc = 'Your advance withdrawal request has been submitted and is awaiting finance approval.';

    if (status == 'approved') {
      statusTitle = 'APPROVED';
      statusColor = const Color(0xFF2563EB);
      statusBg = const Color(0xFFEFF6FF);
      statusDesc = 'Your request has been approved and queued for bank transfer.';
    } else if (status == 'processing') {
      statusTitle = 'PROCESSING';
      statusColor = const Color(0xFF4F46E5);
      statusBg = const Color(0xFFEEF2FF);
      statusDesc = 'Payment provider is processing the bank transfer to your destination account.';
    } else if (status == 'paid' || status == 'completed') {
      statusTitle = 'PAID';
      statusColor = const Color(0xFF16A34A);
      statusBg = const Color(0xFFDCFCE7);
      statusDesc = 'Payment successfully transferred and confirmed by the bank.';
    } else if (status == 'rejected') {
      statusTitle = 'REJECTED';
      statusColor = const Color(0xFFDC2626);
      statusBg = const Color(0xFFFEE2E2);
      statusDesc = reason.isNotEmpty ? 'Rejected by finance: $reason' : 'Request was rejected by finance.';
    } else if (status == 'failed') {
      statusTitle = 'FAILED';
      statusColor = const Color(0xFFDC2626);
      statusBg = const Color(0xFFFEE2E2);
      statusDesc = reason.isNotEmpty ? 'Bank transfer failed: $reason' : 'Bank transfer failed. Reserved funds have been restored.';
    } else if (status == 'cancelled') {
      statusTitle = 'CANCELLED';
      statusColor = const Color(0xFF64748B);
      statusBg = const Color(0xFFF1F5F9);
      statusDesc = 'Withdrawal request was cancelled.';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(ctx).padding.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Withdrawal Details', style: GoogleFonts.hankenGrotesk(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(8)),
                  child: Text(statusTitle, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
              child: Column(
                children: [
                  _detailRow('Amount', '₹${amount.toStringAsFixed(2)}', isBold: true, valueColor: statusColor),
                  const Divider(height: 16),
                  _detailRow('Reference ID', id),
                  const Divider(height: 16),
                  _detailRow('Destination', destination),
                  if (utr.isNotEmpty) ...[
                    const Divider(height: 16),
                    _detailRow('Bank UTR', utr),
                  ],
                  if (createdAtRaw.isNotEmpty) ...[
                    const Divider(height: 16),
                    _detailRow('Date & Time', createdAtRaw),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(12)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_rounded, color: statusColor, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      statusDesc,
                      style: GoogleFonts.inter(fontSize: 12, color: statusColor, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Close', style: GoogleFonts.hankenGrotesk(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool isBold = false, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: valueColor ?? AppTheme.onSurfaceColor,
            ),
          ),
        ),
      ],
    );
  }

  void _handleWithdrawButtonPress() {
    final double? amt = double.tryParse(_amountController.text.trim());
    if (amt == null || amt < 100.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Minimum withdrawal amount is ₹100.00'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    if (amt > _withdrawableAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Amount exceeds your withdrawable balance (₹${_withdrawableAmount.toStringAsFixed(2)})'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
      return;
    }

    if (!_hasLinkedBank) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please link your bank account or UPI ID first before withdrawing.'),
          backgroundColor: Color(0xFFD97706),
        ),
      );
      _showBankDetailsDialog();
      return;
    }

    _showWithdrawalConfirmationSheet(amt);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context, _availableBalance);
      },
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.onSurfaceColor, size: 20),
            onPressed: () => Navigator.pop(context, _availableBalance),
          ),
          title: Text(
            'Pilot Salary & Earnings',
            style: GoogleFonts.hankenGrotesk(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
          ),
          actions: [
            IconButton(
              icon: _isLoading || _isLoadingDailyPlan
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor))
                  : const Icon(Icons.refresh_rounded, color: AppTheme.primaryColor),
              onPressed: (_isLoading || _isLoadingDailyPlan) ? null : () {
                _fetchEarnings();
                _fetchDailyPlan();
              },
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            await Future.wait([
              _fetchEarnings(),
              _fetchDailyPlan(),
            ]);
          },
          color: AppTheme.primaryColor,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Balance Summary Card
                _buildHeroBalanceCard(),

                const SizedBox(height: 16),

                // 1.5 Daily ₹20 Pilot Plan & Admin Booking Access Card
                _buildDailyPlanSection(),

                const SizedBox(height: 16),

                // 2. Secondary Metrics Grid
                _buildSecondaryMetricsGrid(),

                const SizedBox(height: 20),

                // 3. Linked Bank Account Card
                _buildLinkedBankAccountCard(),

                const SizedBox(height: 24),

                // 4. Withdraw Advance Form Section
                _buildWithdrawAdvanceSection(),

                const SizedBox(height: 28),

                // 5. Withdrawal Ledger List
                _buildWithdrawalsHeader(),
                const SizedBox(height: 12),
                _buildWithdrawalsList(),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroBalanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
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
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.stars_rounded, color: Color(0xFFFED01B), size: 15),
                    const SizedBox(width: 6),
                    Text(
                      'Pilot Real Earnings',
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Text(
                'Available Salary',
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Available Balance',
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('₹', style: GoogleFonts.hankenGrotesk(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(width: 4),
              Text(
                _availableBalance.toStringAsFixed(2),
                style: GoogleFonts.hankenGrotesk(fontSize: 38, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Withdrawable Now:', style: GoogleFonts.inter(color: Colors.white70, fontSize: 12)),
                Text(
                  '₹${_withdrawableAmount.toStringAsFixed(2)}',
                  style: GoogleFonts.hankenGrotesk(color: const Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
          ),
          if (_reservedBalance > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Reserved in Review:', style: GoogleFonts.inter(color: const Color(0xFFFDE68A), fontSize: 12)),
                  Text(
                    '₹${_reservedBalance.toStringAsFixed(2)}',
                    style: GoogleFonts.hankenGrotesk(color: const Color(0xFFFDE68A), fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDailyPlanSection() {
    final planStatus = (_dailyPlanData?['planStatus'] ?? 'none').toString().toLowerCase();
    final bool isPaid = planStatus == 'paid';
    final bool isExpired = planStatus == 'expired';
    final paidAtRaw = _dailyPlanData?['paidAt']?.toString() ?? '';
    final expiresAtRaw = _dailyPlanData?['expiresAt']?.toString() ?? '';
    final txnId = _dailyPlanData?['transactionId']?.toString() ?? '';
    final bookingAccess = (_dailyPlanData?['bookingAccessStatus'] ?? 'disabled').toString().toLowerCase();
    final bool isBookingEnabled = bookingAccess == 'enabled';
    final bookingReason = _dailyPlanData?['bookingAccessReason']?.toString() ?? '';

    final double rideEarnings = (_dailyPlanData?['todayRideEarnings'] as num?)?.toDouble() ?? 0.0;
    final double foodEarnings = (_dailyPlanData?['todayFoodEarnings'] as num?)?.toDouble() ?? 0.0;
    final double totalToday = (_dailyPlanData?['totalEarningsToday'] as num?)?.toDouble() ?? (rideEarnings + foodEarnings);

    String formatDt(String raw) {
      if (raw.isEmpty) return '--';
      try {
        final dt = DateTime.parse(raw).toLocal();
        return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {
        return raw;
      }
    }

    Color statusColor = const Color(0xFF64748B);
    Color statusBg = const Color(0xFFF1F5F9);
    String statusText = 'UNPAID';
    if (isPaid) {
      statusColor = const Color(0xFF16A34A);
      statusBg = const Color(0xFFDCFCE7);
      statusText = 'PAID (ACTIVE)';
    } else if (isExpired) {
      statusColor = const Color(0xFFDC2626);
      statusBg = const Color(0xFFFEE2E2);
      statusText = 'EXPIRED';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isPaid ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0),
          width: isPaid ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isPaid ? const Color(0xFFDCFCE7) : const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.electric_moped_rounded,
                      color: isPaid ? const Color(0xFF16A34A) : AppTheme.primaryColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daily ₹20 Pilot Plan',
                        style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
                      ),
                      Text(
                        '₹20 / Day • 24 Hours Access',
                        style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  statusText,
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          const SizedBox(height: 14),

          // 100% Earnings Guarantee: Exact Required Statement
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_rounded, color: Color(0xFF16A34A), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '100% booking earnings – no StayDriv commission deduction.',
                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF15803D)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Eligible bike, auto, car rides and food deliveries are credited at 100% with ₹0 platform commission.',
                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF166534)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Prominent DUTY ON / DUTY OFF Status Indicator (Admin-Controlled, Read-Only)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (isBookingEnabled && isPaid) ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (isBookingEnabled && isPaid) ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5),
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'AUTHORITATIVE DUTY STATUS',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade700, letterSpacing: 0.5),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: (isBookingEnabled && isPaid) ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            (isBookingEnabled && isPaid) ? Icons.check_circle_rounded : Icons.do_not_disturb_on_rounded,
                            size: 13,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            (isBookingEnabled && isPaid) ? 'DUTY ON' : 'DUTY OFF',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  (isBookingEnabled && isPaid)
                      ? '“Your duty is ON. You are eligible to receive bookings, subject to availability and vehicle eligibility.”'
                      : '“Your duty is currently OFF. Please contact the Admin to enable booking access.”',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: (isBookingEnabled && isPaid) ? const Color(0xFF166534) : const Color(0xFF991B1B),
                    height: 1.35,
                  ),
                ),
                if (!isBookingEnabled && bookingReason.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Admin Note: $bookingReason',
                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFDC2626), fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Plan Details List
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                _detailRow('Daily Plan Fee', '₹20.00'),
                if (paidAtRaw.isNotEmpty) ...[
                  const Divider(height: 14),
                  _detailRow('Payment Date & Time', formatDt(paidAtRaw)),
                ],
                if (expiresAtRaw.isNotEmpty) ...[
                  const Divider(height: 14),
                  _detailRow('24-Hour Expiry', formatDt(expiresAtRaw), isBold: isPaid, valueColor: isPaid ? const Color(0xFF16A34A) : const Color(0xFFDC2626)),
                ],
                if (txnId.isNotEmpty) ...[
                  const Divider(height: 14),
                  _detailRow('Transaction ID', txnId),
                ],
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Today's Earnings Breakdown (Rides + Food + Total)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Today's 100% Earnings", style: GoogleFonts.hankenGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                      child: Text('0% COMMISSION', style: GoogleFonts.robotoMono(fontSize: 9, color: const Color(0xFF34D399), fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Rides', style: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 11)),
                          const SizedBox(height: 2),
                          Text('₹${rideEarnings.toStringAsFixed(2)}', style: GoogleFonts.robotoMono(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Food Delivery', style: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 11)),
                          const SizedBox(height: 2),
                          Text('₹${foodEarnings.toStringAsFixed(2)}', style: GoogleFonts.robotoMono(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Total Today', style: GoogleFonts.inter(color: const Color(0xFFFBBF24), fontSize: 11, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('₹${totalToday.toStringAsFixed(2)}', style: GoogleFonts.robotoMono(color: const Color(0xFF34D399), fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Payment / Renewal Button
          if (isPaid) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Plan Active • Duplicate Charge Protected',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isPayingDailyPlan ? null : _confirmDailyPlanPaymentModal,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: _isPayingDailyPlan
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.bolt_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 6),
                          Text(
                            isExpired ? 'Renew ₹20 Daily Plan' : 'Pay ₹20 Daily Plan to Activate',
                            style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSecondaryMetricsGrid() {
    return Row(
      children: [
        Expanded(
          child: _buildMetricTile(
            'Total Earned',
            '₹${_totalEarnings.toStringAsFixed(2)}',
            Icons.trending_up_rounded,
            const Color(0xFF004AC6),
            const Color(0xFFEFF6FF),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricTile(
            'Withdrawn',
            '₹${_withdrawnAmount.toStringAsFixed(2)}',
            Icons.check_circle_outline_rounded,
            const Color(0xFF16A34A),
            const Color(0xFFF0FDF4),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricTile(
            'Pending',
            '₹${_pendingAmount.toStringAsFixed(2)}',
            Icons.schedule_rounded,
            const Color(0xFFD97706),
            const Color(0xFFFFFBEB),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile(String label, String value, IconData icon, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 10),
          Text(label, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.hankenGrotesk(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkedBankAccountCard() {
    final hasBank = _hasLinkedBank;
    final bankName = _bankAccount['bankName'] ?? 'Linked Bank Account';
    final acc = (_bankAccount['accountNumber'] as String?) ?? '';
    final masked = acc.length > 4 ? '•••• ${acc.substring(acc.length - 4)}' : acc;
    final ifsc = (_bankAccount['ifsc'] as String?) ?? '';
    final upi = (_bankAccount['upiId'] as String?) ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: hasBank ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: hasBank ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasBank ? Icons.account_balance_rounded : Icons.add_card_rounded,
              color: hasBank ? const Color(0xFF16A34A) : const Color(0xFFD97706),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      hasBank ? 'Payout Account' : 'Link Bank Account',
                      style: GoogleFonts.hankenGrotesk(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
                    ),
                    const SizedBox(width: 6),
                    if (hasBank)
                      const Icon(Icons.verified, color: Color(0xFF16A34A), size: 14),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  hasBank
                      ? (upi.isNotEmpty ? 'UPI: $upi' : '$bankName • $masked ($ifsc)')
                      : 'Required to receive advance withdrawals safely',
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _showBankDetailsDialog,
            child: Text(
              hasBank ? 'Edit' : 'Link Now',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWithdrawAdvanceSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Withdraw Salary Advance',
            style: GoogleFonts.hankenGrotesk(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
          ),
          const SizedBox(height: 4),
          Text(
            'Withdraw your eligible earnings advance directly to your linked bank account.',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: GoogleFonts.hankenGrotesk(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
            decoration: InputDecoration(
              prefixIcon: Container(
                padding: const EdgeInsets.only(left: 14, right: 6),
                alignment: Alignment.centerLeft,
                width: 38,
                child: Text('₹', style: GoogleFonts.hankenGrotesk(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
              ),
              hintText: 'Enter amount',
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2)),
            ),
          ),

          const SizedBox(height: 14),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ..._quickAmounts.map((amt) {
                  final isSelected = _amountController.text == amt.toString();
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text('₹$amt', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : AppTheme.onSurfaceColor)),
                      backgroundColor: isSelected ? AppTheme.primaryColor : const Color(0xFFF1F5F9),
                      side: BorderSide(color: isSelected ? AppTheme.primaryColor : Colors.transparent),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      onPressed: () => setState(() => _amountController.text = amt.toString()),
                    ),
                  );
                }),
                ActionChip(
                  label: Text('Max Withdrawable', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryColor)),
                  backgroundColor: const Color(0xFFEFF6FF),
                  side: const BorderSide(color: Color(0xFFBFDBFE)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  onPressed: () {
                    if (_withdrawableAmount > 0) {
                      setState(() => _amountController.text = _withdrawableAmount.toStringAsFixed(0));
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: (_isSubmittingWithdrawal || _withdrawableAmount < 100) ? null : _handleWithdrawButtonPress,
              icon: _isSubmittingWithdrawal
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.outbox_rounded, color: Colors.white, size: 20),
              label: Text(
                _withdrawableAmount < 100 ? 'Min Balance ₹100 Required' : 'Withdraw Advance',
                style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                disabledBackgroundColor: Colors.grey.shade400,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWithdrawalsHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Withdrawal History',
          style: GoogleFonts.hankenGrotesk(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
        ),
        Text(
          '${_withdrawals.length} requests',
          style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildWithdrawalsList() {
    if (_isLoading && _withdrawals.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 36),
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );
    }

    if (_withdrawals.isEmpty) {
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
              decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle),
              child: Icon(Icons.history_rounded, size: 36, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 14),
            Text('No Withdrawal Requests', style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor)),
            const SizedBox(height: 6),
            Text(
              'Your advance withdrawal requests and payouts will appear here.',
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
        itemCount: _withdrawals.length,
        separatorBuilder: (ctx, i) => Divider(height: 1, color: Colors.grey.shade100),
        itemBuilder: (ctx, i) {
          final w = _withdrawals[i] as Map<String, dynamic>;
          final id = w['withdrawalId'] ?? w['payoutId'] ?? 'WTH_${i + 1}';
          final amount = (w['amount'] as num?)?.toDouble() ?? 0.0;
          final status = (w['status'] as String? ?? 'pending_approval').toLowerCase();
          final createdAtRaw = w['createdAt'] ?? '';

          Color statusColor = const Color(0xFFD97706);
          Color statusBg = const Color(0xFFFEF3C7);
          String statusText = 'PENDING APPROVAL';
          IconData statusIcon = Icons.hourglass_top_rounded;

          if (status == 'paid' || status == 'completed') {
            statusColor = const Color(0xFF16A34A);
            statusBg = const Color(0xFFDCFCE7);
            statusText = 'PAID';
            statusIcon = Icons.check_circle_rounded;
          } else if (status == 'approved') {
            statusColor = const Color(0xFF2563EB);
            statusBg = const Color(0xFFEFF6FF);
            statusText = 'APPROVED';
            statusIcon = Icons.verified_rounded;
          } else if (status == 'processing') {
            statusColor = const Color(0xFF4F46E5);
            statusBg = const Color(0xFFEEF2FF);
            statusText = 'PROCESSING';
            statusIcon = Icons.sync_rounded;
          } else if (status == 'rejected') {
            statusColor = const Color(0xFFDC2626);
            statusBg = const Color(0xFFFEE2E2);
            statusText = 'REJECTED';
            statusIcon = Icons.cancel_rounded;
          } else if (status == 'failed') {
            statusColor = const Color(0xFFDC2626);
            statusBg = const Color(0xFFFEE2E2);
            statusText = 'FAILED';
            statusIcon = Icons.error_outline_rounded;
          } else if (status == 'cancelled') {
            statusColor = const Color(0xFF64748B);
            statusBg = const Color(0xFFF1F5F9);
            statusText = 'CANCELLED';
            statusIcon = Icons.block_rounded;
          }

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
            onTap: () => _showWithdrawalDetailsModal(w),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: statusBg, shape: BoxShape.circle),
              child: Icon(
                statusIcon,
                color: statusColor,
                size: 20,
              ),
            ),
            title: Text(
              'Salary Advance Payout',
              style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(formattedDate.isNotEmpty ? formattedDate : statusText, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600)),
                Text('Ref: $id', style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400)),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '- ₹${amount.toStringAsFixed(2)}',
                  style: GoogleFonts.hankenGrotesk(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    statusText,
                    style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: statusColor),
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
