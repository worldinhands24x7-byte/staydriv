import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/api_client.dart';
import '../../../../core/booking_manager.dart';
import '../../../../core/network_config.dart';
import '../../../../core/theme.dart';

class PilotPaymentPendingPanel extends StatefulWidget {
  final Map<String, dynamic> booking;
  final Function(String method) onPaymentCompleted;

  const PilotPaymentPendingPanel({
    super.key,
    required this.booking,
    required this.onPaymentCompleted,
  });

  @override
  State<PilotPaymentPendingPanel> createState() => _PilotPaymentPendingPanelState();
}

class _PilotPaymentPendingPanelState extends State<PilotPaymentPendingPanel> {
  // Static in-memory cache to preserve QR payment session across widget rebuilds and lifecycle
  static final Map<String, Map<String, dynamic>> _cachedQrSessions = {};

  bool _isProcessing = false;
  bool _showQrSection = false;
  String _paymentStatus = 'pending'; // 'pending', 'received', 'completed', 'failed'
  String _paidMethod = '';
  String _transactionReference = '';
  String _errorMessage = '';

  // Dynamic QR Details
  String? _qrImageUrl;
  String? _upiUri;
  String? _payeeUpiId;
  String? _payeeName;
  bool _isLoadingQr = false;

  final TextEditingController _utrController = TextEditingController();
  StreamSubscription<Map<String, dynamic>?>? _bookingSub;

  @override
  void initState() {
    super.initState();
    final status = widget.booking['paymentStatus'] as String?;
    if (status == 'paid') {
      _paymentStatus = 'completed';
      _paidMethod = widget.booking['paymentOption'] ?? 'Paid';
      _transactionReference = widget.booking['paymentId'] ?? widget.booking['transactionId'] ?? 'CONFIRMED';
    }

    // Restore cached QR session if one already exists for this booking
    final cached = _cachedQrSessions[_bookingId];
    if (cached != null) {
      _qrImageUrl = cached['qrImageUrl'] as String?;
      _upiUri = cached['upiUri'] as String?;
      _payeeUpiId = (cached['payeeUpiId'] ?? cached['upiId']) as String?;
      _payeeName = cached['payeeName'] as String?;
    }

    // Subscribe to live socket booking stream for real-time customer payment updates
    _bookingSub = BookingManager().bookingStream.listen((booking) {
      if (mounted && booking != null) {
        final currentPaymentStatus = booking['paymentStatus'] as String?;
        if (currentPaymentStatus == 'paid' && _paymentStatus != 'completed') {
          setState(() {
            _paymentStatus = 'completed';
            _paidMethod = booking['paymentOption'] ?? 'Online UPI';
            _transactionReference = booking['transactionId'] ?? booking['paymentId'] ?? 'VERIFIED';
            _isProcessing = false;
            _showQrSection = false;
            _cachedQrSessions.remove(_bookingId);
          });
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant PilotPaymentPendingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final status = widget.booking['paymentStatus'] as String?;
    if (status == 'paid' && _paymentStatus != 'completed') {
      setState(() {
        _paymentStatus = 'completed';
        _paidMethod = widget.booking['paymentOption'] ?? 'Online UPI';
        _transactionReference = widget.booking['transactionId'] ?? widget.booking['paymentId'] ?? 'CONFIRMED';
        _isProcessing = false;
        _showQrSection = false;
        _cachedQrSessions.remove(_bookingId);
      });
    }
  }

  @override
  void dispose() {
    _bookingSub?.cancel();
    _utrController.dispose();
    super.dispose();
  }

  String get _bookingId => widget.booking['bookingId'] ?? widget.booking['id'] ?? widget.booking['_id'] ?? '';

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

  bool get _isParcel => widget.booking['serviceType'] == 'parcel';

  // --- 1. CASH PAYMENT FLOW ---
  void _handleCashPaymentTap() {
    if (_paymentStatus == 'completed') return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.money_rounded, color: Color(0xFF16A34A), size: 26),
            const SizedBox(width: 8),
            Text(
              'Confirm Cash Received',
              style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Text(
          'Please confirm that you have physically collected $_displayFare in cash from the customer.',
          style: GoogleFonts.inter(fontSize: 14, color: Colors.black87, height: 1.4),
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
            child: Text('Confirm Cash Received', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCashOnServer() async {
    setState(() {
      _isProcessing = true;
      _paymentStatus = 'received';
      _errorMessage = '';
    });

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/pilot/payment/confirm-cash');
      final res = await ApiClient().post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'bookingId': _bookingId,
          'pilotId': widget.booking['driverId'] ?? '',
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && mounted) {
          setState(() {
            _paymentStatus = 'completed';
            _paidMethod = 'Cash Received';
            _transactionReference = data['transactionId'] ?? 'CASH_CONFIRMED';
            _isProcessing = false;
          });
          return;
        }
      }
      throw Exception('Server rejected cash payment confirmation');
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _paymentStatus = 'failed';
          _errorMessage = 'Could not confirm cash payment: $e';
        });
      }
    }
  }

  // --- 2. UPI TRANSFER & DYNAMIC QR FLOW ---
  void _handleUpiTransferTap() {
    if (_paymentStatus == 'completed') return;

    setState(() {
      _showQrSection = !_showQrSection;
    });

    if (_showQrSection && _qrImageUrl == null) {
      _fetchDynamicQrCode();
    }
  }

  Future<void> _fetchDynamicQrCode() async {
    // If a session is already cached for this booking, use it immediately to avoid re-rendering/blinking
    if (_cachedQrSessions.containsKey(_bookingId)) {
      final cached = _cachedQrSessions[_bookingId]!;
      setState(() {
        _qrImageUrl = cached['qrImageUrl'] as String?;
        _upiUri = cached['upiUri'] as String?;
        _payeeUpiId = (cached['payeeUpiId'] ?? cached['upiId']) as String?;
        _payeeName = cached['payeeName'] as String?;
        _isLoadingQr = false;
      });
      return;
    }

    setState(() {
      _isLoadingQr = true;
      _errorMessage = '';
    });

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/pilot/payment/qr/$_bookingId');
      final res = await ApiClient().get(uri);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && mounted) {
          final qrImg = data['qrImageUrl'] as String?;
          final upi = data['upiUri'] as String?;
          final uId = data['upiId'] as String?;
          final pName = data['payeeName'] as String?;

          // Save in cache so subsequent rebuilds never flicker or fetch again
          _cachedQrSessions[_bookingId] = {
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
      throw Exception('Server returned status ${res.statusCode}');
    } catch (e) {
      if (mounted) {
        // Fallback standard UPI URI construction with literal '@' for NPCI compliance
        final fare = _fareAmount;
        final upiId = 'staydriv@icici';
        final cleanBookingRef = _bookingId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
        final fallbackUri = 'upi://pay?pa=$upiId&pn=StayDriv%20Pilot&am=${fare.toStringAsFixed(2)}&cu=INR&tn=Ride_$cleanBookingRef&tr=TXN_$cleanBookingRef';
        final fallbackQrUrl = 'https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=${Uri.encodeComponent(fallbackUri)}';

        _cachedQrSessions[_bookingId] = {
          'qrImageUrl': fallbackQrUrl,
          'upiUri': fallbackUri,
          'upiId': upiId,
          'payeeName': 'StayDriv Pilot',
        };

        setState(() {
          _upiUri = fallbackUri;
          _payeeUpiId = upiId;
          _payeeName = 'StayDriv Pilot';
          _qrImageUrl = fallbackQrUrl;
          _isLoadingQr = false;
        });
      }
    }
  }

  // --- 3. VERIFY UPI PAYMENT ---
  void _showVerifyUpiDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Verify UPI Transfer',
          style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the UPI Reference ID or 12-digit UTR from the customer\'s payment receipt:',
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _utrController,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                hintText: 'e.g. 4235XXXXXXXX or UPI Ref',
                labelText: 'UPI UTR / Reference ID (Optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Required: Check that money has arrived in your UPI app or StayDriv account before confirming.',
              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFD97706), fontWeight: FontWeight.w500),
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
              _verifyUpiOnServer(_utrController.text.trim());
            },
            child: Text('Verify & Confirm', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyUpiOnServer(String referenceId) async {
    setState(() {
      _isProcessing = true;
      _errorMessage = '';
    });

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/pilot/payment/verify-upi');
      final res = await ApiClient().post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'bookingId': _bookingId,
          'pilotId': widget.booking['driverId'] ?? '',
          'referenceId': referenceId,
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && mounted) {
          setState(() {
            _paymentStatus = 'completed';
            _paidMethod = 'UPI Transfer';
            _transactionReference = data['referenceId'] ?? data['transactionId'] ?? 'UPI_VERIFIED';
            _isProcessing = false;
          });
          return;
        }
      }
      throw Exception('Server rejected UPI payment verification');
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _paymentStatus = 'failed';
          _errorMessage = 'Could not verify UPI payment: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Top Pill: PILOT PARTNER (Orange Background)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFE66B1E),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'PILOT PARTNER',
            style: GoogleFonts.hankenGrotesk(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 1.0,
            ),
          ),
        ),

        // Main White Card matching the user's screenshot
        Container(
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
          child: _paymentStatus == 'completed'
              ? _buildPaymentCompletedReceipt()
              : _buildPaymentSelectionView(),
        ),
      ],
    );
  }

  // --- VIEW: PAYMENT SELECTION CARD ---
  Widget _buildPaymentSelectionView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isParcel ? 'Delivery Completed' : 'Ride Completed',
          style: GoogleFonts.hankenGrotesk(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.onSurfaceColor,
          ),
        ),
        const SizedBox(height: 8),

        Text(
          'Collect payment from customer:',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 4),

        // Large Fare Text: e.g. ₹118
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

        // Option 1: Cash Received (Green Cash Note)
        _buildPaymentOptionTile(
          iconWidget: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF16A34A), width: 1.8),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.money_rounded, color: Color(0xFF16A34A), size: 22),
          ),
          title: 'Cash Received',
          onTap: _isProcessing ? null : _handleCashPaymentTap,
        ),

        const SizedBox(height: 12),

        // Option 2: UPI Transfer (Blue QR Scan)
        _buildPaymentOptionTile(
          iconWidget: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF2563EB), size: 26),
          title: 'UPI Transfer',
          isSelected: _showQrSection,
          onTap: _isProcessing ? null : _handleUpiTransferTap,
        ),

        if (_errorMessage.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage,
                    style: GoogleFonts.inter(color: const Color(0xFFDC2626), fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ],

        // --- EXPANDED DYNAMIC QR CODE SECTION ---
        if (_showQrSection) ...[
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 10),
          _buildDynamicQrView(),
        ],

        if (_isProcessing) ...[
          const SizedBox(height: 16),
          const Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF004AC6))),
                SizedBox(width: 10),
                Text('Verifying with StayDriv server...', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPaymentOptionTile({
    required Widget iconWidget,
    required String title,
    bool isSelected = false,
    required VoidCallback? onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
          width: isSelected ? 2.0 : 1.2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                iconWidget,
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.onSurfaceColor,
                    ),
                  ),
                ),
                Icon(
                  isSelected ? Icons.keyboard_arrow_up_rounded : Icons.chevron_right_rounded,
                  color: const Color(0xFF94A3B8),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- DYNAMIC QR CODE CONTAINER ---
  Widget _buildDynamicQrView() {
    if (_isLoadingQr) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            children: [
              CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF004AC6)),
              SizedBox(height: 12),
              Text('Generating Live Payment QR...', style: TextStyle(fontSize: 13, color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Status Badge: Payment Pending
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF59E0B)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD97706)),
              ),
              const SizedBox(width: 8),
              Text(
                'Status: Payment Pending',
                style: GoogleFonts.robotoMono(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFB45309),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        Text(
          'Customer scans to pay $_displayFare',
          style: GoogleFonts.hankenGrotesk(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: AppTheme.onSurfaceColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Supports Google Pay, PhonePe, Paytm, BHIM & all UPI apps',
          style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 14),

        // QR Code Image Box
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
            boxShadow: const [
              BoxShadow(color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 4)),
            ],
          ),
          child: _qrImageUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    _qrImageUrl!,
                    key: ValueKey('qr_img_$_bookingId'),
                    width: 200,
                    height: 200,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    cacheWidth: 400,
                    cacheHeight: 400,
                    errorBuilder: (_, __, ___) => Container(
                      width: 200,
                      height: 200,
                      color: Colors.grey.shade100,
                      child: const Center(child: Icon(Icons.qr_code_2_rounded, size: 80, color: Colors.grey)),
                    ),
                  ),
                )
              : const SizedBox(width: 200, height: 200),
        ),

        const SizedBox(height: 12),
        if (_payeeUpiId != null) ...[
          Text(
            'UPI ID: $_payeeUpiId',
            style: GoogleFonts.robotoMono(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
          ),
        ],

        const SizedBox(height: 16),

        // Verify Payment Button
        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.verified_rounded, color: Colors.white, size: 18),
            label: Text(
              'Verify UPI Payment',
              style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF004AC6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _isProcessing ? null : _showVerifyUpiDialog,
          ),
        ),
      ],
    );
  }

  // --- VIEW: PAYMENT COMPLETED RECEIPT ---
  Widget _buildPaymentCompletedReceipt() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            color: Color(0xFFDCFCE7),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded, color: Color(0xFF16A34A), size: 38),
        ),
        const SizedBox(height: 14),

        Text(
          'Payment Received',
          style: GoogleFonts.hankenGrotesk(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.onSurfaceColor,
          ),
        ),
        const SizedBox(height: 6),

        Text(
          '$_displayFare collected via $_paidMethod',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF16A34A),
          ),
        ),
        const SizedBox(height: 4),

        if (_transactionReference.isNotEmpty) ...[
          Text(
            'Ref ID: $_transactionReference',
            style: GoogleFonts.robotoMono(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],

        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: () {
              widget.onPaymentCompleted(_paidMethod);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              'Finish & Continue',
              style: GoogleFonts.hankenGrotesk(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
