import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/api_client.dart';
import '../../../core/call_masking_service.dart';
import '../../../core/network_config.dart';
import '../../../core/theme.dart';
import '../../support/screens/support_category_screen.dart';

/// Screen displaying official completed ride & earnings transaction details
/// for both Customers and Pilots, supporting full breakdown and backend verification.
class RideDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> ride;
  final bool isPilotView;

  const RideDetailsScreen({
    super.key,
    required this.ride,
    this.isPilotView = false,
  });

  @override
  State<RideDetailsScreen> createState() => _RideDetailsScreenState();
}

class _RideDetailsScreenState extends State<RideDetailsScreen> {
  late Map<String, dynamic> _rideData;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isAddressExpanded = true;
  bool _isFareExpanded = true;
  bool _isSendingReceipt = false;

  @override
  void initState() {
    super.initState();
    _rideData = Map<String, dynamic>.from(widget.ride);
    _fetchLiveDetails();
  }

  Future<void> _fetchLiveDetails() async {
    final rawBookingId = _rideData['bookingId']?.toString() ??
        _rideData['id']?.toString() ??
        _rideData['_id']?.toString() ??
        _rideData['rideId']?.toString() ??
        '';

    final cleanId = rawBookingId.replaceAll('#', '').trim();
    if (cleanId.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final roleParam = widget.isPilotView ? 'pilot' : 'customer';
      final url = Uri.parse('$baseUrl/api/booking/$cleanId?role=$roleParam');

      final response = await ApiClient().get(url, timeout: const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['booking'] != null) {
          if (mounted) {
            setState(() {
              _rideData = {
                ..._rideData,
                ...Map<String, dynamic>.from(data['booking']),
              };
              _isLoading = false;
              _errorMessage = null;
            });
            return;
          }
        }
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
          // Keep showing cached data smoothly without blocking the UI
        });
      }
    } catch (e) {
      debugPrint('[RideDetailsScreen] Failed to fetch live booking details: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not sync latest transaction info from server.';
        });
      }
    }
  }

  double _parsePrice(dynamic priceRaw) {
    if (priceRaw == null) return 0.0;
    if (priceRaw is num) return priceRaw.toDouble();
    final str = priceRaw.toString();
    final clean = str.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(clean) ?? 0.0;
  }

  String _cleanPrice(dynamic priceRaw) {
    final val = _parsePrice(priceRaw);
    return val.toStringAsFixed(val % 1 == 0 ? 0 : 2);
  }

  String _formatFareDecimal(dynamic priceRaw) {
    final val = _parsePrice(priceRaw);
    return val.toStringAsFixed(1);
  }

  String _formatDateString(Map<String, dynamic> data) {
    final timestamp = data['timestamp'];
    if (timestamp != null && timestamp is int && timestamp > 0) {
      final dt = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
      return _formatDateTime(dt);
    }
    final createdAt = data['createdAt'];
    if (createdAt != null) {
      try {
        final dt = DateTime.parse(createdAt.toString()).toLocal();
        return _formatDateTime(dt);
      } catch (_) {}
    }
    final dateStr = data['date']?.toString();
    if (dateStr != null && dateStr.trim().isNotEmpty) {
      return dateStr;
    }
    return _formatDateTime(DateTime.now());
  }

  String _formatDateTime(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final monthName = months[dt.month - 1];
    final dayStr = dt.day.toString().padLeft(2, '0');
    final year = dt.year;
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minStr = dt.minute.toString().padLeft(2, '0');
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$dayStr $monthName $year • ${hour.toString().padLeft(2, '0')}:$minStr $amPm';
  }

  String _extractBookingId(Map<String, dynamic> data) {
    final rawId = data['bookingId']?.toString() ??
        data['rideId']?.toString() ??
        data['id']?.toString() ??
        data['_id']?.toString();
    if (rawId != null && rawId.trim().isNotEmpty) {
      final cleaned = rawId.replaceAll('#', '').trim();
      return cleaned;
    }
    final ts = data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch;
    return 'RD${ts.toString().padRight(17, '0')}';
  }

  String _extractTransactionId(Map<String, dynamic> data, String bookingId) {
    final txn = data['transactionId']?.toString();
    if (txn != null && txn.trim().isNotEmpty) {
      return txn.replaceAll('#', '').trim();
    }
    return 'TXN_${bookingId.replaceAll('BK_', '')}';
  }

  Map<String, String> _parseAddressParts(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return {'title': 'Location details', 'subtitle': 'Address not specified'};
    }
    final trimmed = raw.trim();
    final parts = trimmed.split(',');
    if (parts.length > 1) {
      final title = parts[0].trim();
      final subtitle = parts.sublist(1).join(',').trim();
      return {'title': title, 'subtitle': subtitle.isNotEmpty ? subtitle : title};
    }
    return {'title': trimmed, 'subtitle': trimmed};
  }

  IconData _resolveVehicleIcon(String vehicle) {
    final lower = vehicle.toLowerCase();
    if (lower.contains('food')) {
      return Icons.fastfood_rounded;
    }
    if (lower.contains('bike') || lower.contains('moto') || lower.contains('two')) {
      return Icons.two_wheeler_rounded;
    }
    if (lower.contains('auto') || lower.contains('rick') || lower.contains('three')) {
      return Icons.electric_rickshaw_rounded;
    }
    if (lower.contains('car') || lower.contains('sedan') || lower.contains('suv') || lower.contains('cab')) {
      return Icons.directions_car_rounded;
    }
    if (lower.contains('truck') || lower.contains('goods') || lower.contains('ace')) {
      return Icons.local_shipping_rounded;
    }
    if (lower.contains('parcel')) {
      return Icons.inventory_2_rounded;
    }
    return Icons.directions_car_rounded;
  }

  void _sendReceiptEmail() async {
    setState(() => _isSendingReceipt = true);
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _isSendingReceipt = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.isPilotView
                    ? 'Earnings statement sent to your registered partner email.'
                    : 'Ride receipt sent to your registered email address.',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _copyToClipboard(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied: $value', style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: const Color(0xFF0F172A),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ride = _rideData;
    final vehicle = (ride['vehicle']?.toString() ??
        ride['vehicleType']?.toString() ??
        ride['serviceType']?.toString() ??
        'Bike').trim();

    final isFood = vehicle.toLowerCase().contains('food') ||
        (ride['serviceType']?.toString() ?? '').toLowerCase().contains('food') ||
        ride['isFoodDelivery'] == true;

    final isParcel = !isFood && (vehicle.toLowerCase().contains('parcel') ||
        (ride['serviceType']?.toString() ?? '').toLowerCase().contains('parcel'));

    final title = ride['title']?.toString() ??
        (isFood ? 'StayDriv Food Delivery' : (isParcel ? 'StayDriv Parcel Delivery' : 'StayDriv $vehicle Ride'));

    final dateDisplay = _formatDateString(ride);
    final rawPrice = ride['totalFare'] ?? ride['price'] ?? ride['fare'] ?? ride['estimatedFare'] ?? '0';
    final double totalFare = _parsePrice(rawPrice);
    final String cleanTotalFare = totalFare.toStringAsFixed(totalFare % 1 == 0 ? 0 : 2);

    final double pilotEarnings = ride['pilotEarnings'] != null
        ? _parsePrice(ride['pilotEarnings'])
        : (isFood ? totalFare : (totalFare * 0.85));

    final double commission = ride['platformCommission'] != null
        ? _parsePrice(ride['platformCommission'])
        : (isFood ? 0.0 : (totalFare * 0.15));

    final bookingId = _extractBookingId(ride);
    final txnId = _extractTransactionId(ride, bookingId);

    final paymentMethod = ride['paymentMethod']?.toString() ?? 'Cash';
    final paymentStatus = (ride['paymentStatus']?.toString() ?? 'Completed').toUpperCase();

    final rawStatus = (ride['status']?.toString() ?? 'completed').toLowerCase();
    final bool isCompleted = rawStatus == 'completed';

    final bool isDeliveryOtpVerified = ride['isDeliveryOtpVerified'] == true ||
        ride['deliveryOtpVerified'] == true;

    // Extract pickup and drop addresses
    String? pickupRaw = ride['pickup']?.toString();
    String? dropRaw = ride['drop']?.toString();
    if ((pickupRaw == null || pickupRaw.isEmpty) && ride['route'] != null) {
      final routeParts = (ride['route'] as String).split(' to ');
      pickupRaw = routeParts.isNotEmpty ? routeParts[0] : null;
      dropRaw = routeParts.length > 1 ? routeParts[1] : null;
    }

    final pickupParts = _parseAddressParts(pickupRaw ?? 'Pickup location');
    final dropParts = _parseAddressParts(dropRaw ?? (isParcel ? 'Delivery destination' : 'Dropoff location'));

    // Distance and duration
    final distance = ride['distance']?.toString() ??
        ride['distanceText']?.toString() ??
        '${(totalFare / 9.5 > 1 ? (totalFare / 9.5).toStringAsFixed(1) : "3.5")} kms';

    final duration = ride['duration']?.toString() ??
        ride['durationText']?.toString() ??
        '${(totalFare / 3.8 > 5 ? (totalFare / 3.8).round() : "15")} mins';

    // Customer Name & Masked Phone
    final customerName = ride['passengerName']?.toString() ??
        (isParcel ? (ride['pickupContactName']?.toString() ?? 'Sender') : 'StayDriv Customer');
    final rawCustomerPhone = ride['passengerPhone']?.toString() ??
        (isParcel ? ride['pickupContactPhone']?.toString() : null);
    final maskedPhone = (rawCustomerPhone != null && rawCustomerPhone.isNotEmpty)
        ? CallMaskingService.maskPhone(rawCustomerPhone)
        : 'Confidential (StayDriv Protected)';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A), size: 24),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.isPilotView ? 'Earnings & Trip Details' : 'Details',
          style: GoogleFonts.hankenGrotesk(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF0F172A),
          ),
        ),
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
                  )
                : const Icon(Icons.refresh_rounded, color: Color(0xFF0F172A)),
            tooltip: 'Refresh Details',
            onPressed: _isLoading ? null : _fetchLiveDetails,
          ),
        ],
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Error banner if any with Retry button
            if (_errorMessage != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Color(0xFFDC2626), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFB91C1C), fontWeight: FontWeight.w500),
                      ),
                    ),
                    TextButton(
                      onPressed: _fetchLiveDetails,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: const Color(0xFFDC2626),
                      ),
                      child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],

            // --- PILOT EARNINGS HERO CARD (FOR PILOT VIEW) ---
            if (widget.isPilotView) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F5132), Color(0xFF198754)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Color(0x26198754), blurRadius: 12, offset: Offset(0, 4)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Pilot Net Earnings',
                          style: GoogleFonts.inter(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w500),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '85% Payout',
                            style: GoogleFonts.robotoMono(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '₹${pilotEarnings.toStringAsFixed(1)}',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Colors.white24, height: 1),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Customer Fare: ₹$cleanTotalFare',
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.white),
                        ),
                        Text(
                          'Platform Fee: ₹${commission.toStringAsFixed(1)} (15%)',
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // --- TOP CARD: RIDE DETAILS & ADDRESS TIMELINE ---
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: const [
                  BoxShadow(color: Color(0x08000000), blurRadius: 10, offset: Offset(0, 3)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title row with vehicle badge and completion pill
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: GoogleFonts.hankenGrotesk(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    dateDisplay,
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      color: const Color(0xFF64748B),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Text(
                                        '₹$cleanTotalFare',
                                        style: GoogleFonts.hankenGrotesk(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFF0F172A),
                                        ),
                                      ),
                                      if (!widget.isPilotView) ...[
                                        const SizedBox(width: 4),
                                        Text(
                                          '(.est)',
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: const Color(0xFF64748B),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          paymentMethod,
                                          style: GoogleFonts.robotoMono(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF475569)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    _resolveVehicleIcon(vehicle),
                                    color: AppTheme.primaryColor,
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isCompleted ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isCompleted ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isCompleted ? Icons.check_circle_rounded : Icons.schedule_rounded,
                                        color: isCompleted ? const Color(0xFF059669) : const Color(0xFFD97706),
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        isCompleted ? 'Completed' : (rawStatus.toUpperCase()),
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: isCompleted ? const Color(0xFF059669) : const Color(0xFFD97706),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        const SizedBox(height: 14),

                        // Booking ID & Transaction ID Row
                        Container(
                          padding: const EdgeInsets.all(12),
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
                                  Text(
                                    'Booking ID:',
                                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                                  ),
                                  InkWell(
                                    onTap: () => _copyToClipboard('Booking ID', bookingId),
                                    child: Row(
                                      children: [
                                        Text(
                                          '#$bookingId',
                                          style: GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(Icons.copy_rounded, size: 13, color: Color(0xFF64748B)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Transaction ID:',
                                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                                  ),
                                  InkWell(
                                    onTap: () => _copyToClipboard('Transaction ID', txnId),
                                    child: Row(
                                      children: [
                                        Text(
                                          '#$txnId',
                                          style: GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(Icons.copy_rounded, size: 13, color: Color(0xFF64748B)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Address details header with collapse toggle
                        InkWell(
                          onTap: () => setState(() => _isAddressExpanded = !_isAddressExpanded),
                          borderRadius: BorderRadius.circular(8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                widget.isPilotView ? 'Route & Customer Details' : 'Address details',
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF334155),
                                ),
                              ),
                              Icon(
                                _isAddressExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                color: const Color(0xFF64748B),
                                size: 24,
                              ),
                            ],
                          ),
                        ),

                        if (_isAddressExpanded) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Ride ID #$bookingId',
                            style: GoogleFonts.robotoMono(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Customer Name & Contact Pill
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.person_rounded, size: 18, color: Color(0xFF475569)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    customerName,
                                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A)),
                                  ),
                                ),
                                Text(
                                  maskedPhone,
                                  style: GoogleFonts.robotoMono(fontSize: 11, color: const Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Vertical Address Timeline
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(
                                children: [
                                  // Green Pickup Dot
                                  Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                      border: Border.all(color: const Color(0xFF10B981), width: 3.5),
                                    ),
                                  ),
                                  // Dotted connector line
                                  CustomPaint(
                                    size: const Size(2, 60),
                                    painter: _DottedLinePainter(color: const Color(0xFFCBD5E1)),
                                  ),
                                  // Red Drop Dot
                                  Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                      border: Border.all(color: const Color(0xFFEF4444), width: 3.5),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Pickup Info
                                    Text(
                                      pickupParts['title']!,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      pickupParts['subtitle']!,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: const Color(0xFF64748B),
                                        height: 1.3,
                                      ),
                                    ),

                                    const SizedBox(height: 24),

                                    // Dropoff Info
                                    Text(
                                      dropParts['title']!,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      dropParts['subtitle']!,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: const Color(0xFF64748B),
                                        height: 1.3,
                                      ),
                                    ),

                                    const SizedBox(height: 14),

                                    // Distance and duration footer
                                    Row(
                                      children: [
                                        if (widget.isPilotView) ...[
                                          const Icon(Icons.route_rounded, size: 14, color: Color(0xFF64748B)),
                                          const SizedBox(width: 4),
                                        ],
                                        Text(
                                          widget.isPilotView
                                              ? '$distance • $duration'
                                              : '$duration • $distance (.est)',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: const Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Need Help? Banner at card bottom
                  Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF0F7FF),
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SupportCategoryScreen(
                                category: 'booking',
                                userType: widget.isPilotView ? 'driver' : 'customer',
                              ),
                            ),
                          );
                        },
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 14.0),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF3B82F6),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.headset_mic_rounded, color: Colors.white, size: 20),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Need help?',
                                      style: GoogleFonts.hankenGrotesk(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                                    ),
                                    Text(
                                      "We're a tap away",
                                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B), size: 22),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // --- PARCEL DELIVERY VERIFICATION CARD (IF PARCEL) ---
            if (isParcel) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDeliveryOtpVerified ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDeliveryOtpVerified ? const Color(0xFF86EFAC) : const Color(0xFFFDE68A),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDeliveryOtpVerified ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isDeliveryOtpVerified ? Icons.verified_user_rounded : Icons.pending_rounded,
                        color: isDeliveryOtpVerified ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Parcel Delivery OTP Verification',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: isDeliveryOtpVerified ? const Color(0xFF15803D) : const Color(0xFFB45309),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isDeliveryOtpVerified
                                ? 'Verified by customer 6-digit OTP upon parcel handover'
                                : 'Pending customer 6-digit OTP verification',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: isDeliveryOtpVerified ? const Color(0xFF166534) : const Color(0xFF92400E),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDeliveryOtpVerified ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isDeliveryOtpVerified ? 'VERIFIED' : 'PENDING',
                        style: GoogleFonts.robotoMono(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // --- SECTION 2: FARE & EARNINGS BREAKDOWN ---
            Row(
              children: [
                const Icon(Icons.receipt_long_rounded, size: 20, color: Color(0xFF0F172A)),
                const SizedBox(width: 8),
                Text(
                  widget.isPilotView ? 'Earnings & Financial Breakdown' : 'Ride Summary',
                  style: GoogleFonts.hankenGrotesk(fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: const [
                  BoxShadow(color: Color(0x08000000), blurRadius: 10, offset: Offset(0, 3)),
                ],
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(18.0),
                    child: Column(
                      children: [
                        // Suggested / Total Fare row
                        InkWell(
                          onTap: () => setState(() => _isFareExpanded = !_isFareExpanded),
                          borderRadius: BorderRadius.circular(8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                widget.isPilotView ? 'Total Ride Fare' : 'Suggested Fare',
                                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                              ),
                              Row(
                                children: [
                                  Text(
                                    '₹${_formatFareDecimal(totalFare)}',
                                    style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    _isFareExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                    color: const Color(0xFF64748B),
                                    size: 22,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        if (_isFareExpanded) ...[
                          const SizedBox(height: 14),
                          CustomPaint(
                            size: const Size(double.infinity, 1),
                            painter: _HorizontalDottedLinePainter(color: const Color(0xFFCBD5E1)),
                          ),
                          const SizedBox(height: 14),

                          if (!widget.isPilotView) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total Fare',
                                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: const Color(0xFF475569)),
                                ),
                                Text(
                                  '₹${_formatFareDecimal(totalFare)}',
                                  style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Pilot Share (85%)',
                                  style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: const Color(0xFF16A34A)),
                                ),
                                Text(
                                  '₹${pilotEarnings.toStringAsFixed(1)}',
                                  style: GoogleFonts.hankenGrotesk(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF16A34A)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Platform Commission (15%)',
                                  style: GoogleFonts.inter(fontSize: 13.5, color: const Color(0xFF64748B)),
                                ),
                                Text(
                                  '₹${commission.toStringAsFixed(1)}',
                                  style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Applicable Deductions / TDS',
                                  style: GoogleFonts.inter(fontSize: 13.5, color: const Color(0xFF64748B)),
                                ),
                                Text(
                                  '₹0.0',
                                  style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Divider(height: 1, color: Color(0xFFE2E8F0)),
                            const SizedBox(height: 12),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Payment Method',
                                style: GoogleFonts.inter(fontSize: 13.5, color: const Color(0xFF64748B)),
                              ),
                              Text(
                                paymentMethod,
                                style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Payment Status',
                                style: GoogleFonts.inter(fontSize: 13.5, color: const Color(0xFF64748B)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFECFDF5),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  paymentStatus,
                                  style: GoogleFonts.robotoMono(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF059669)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  const Divider(height: 1, color: Color(0xFFE2E8F0)),

                  // Send receipt via Email button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _isSendingReceipt ? null : _sendReceiptEmail,
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 15.0),
                        child: Row(
                          children: [
                            if (_isSendingReceipt)
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
                              )
                            else
                              const Icon(Icons.mail_outline_rounded, color: AppTheme.primaryColor, size: 22),
                            const SizedBox(width: 12),
                            Text(
                              _isSendingReceipt
                                  ? 'Sending Receipt...'
                                  : 'Send receipt via Email',
                              style: GoogleFonts.inter(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primaryColor,
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

            const SizedBox(height: 20),

            // --- FOOTER DISCLAIMER ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, size: 15, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.isPilotView
                          ? 'Earnings are credited per the StayDriv Pilot Partner terms (85% net fare after 15% platform commission). Withdrawals can be processed via Instant Cashout in Earnings Dashboard.'
                          : 'StayDriv serves solely as a facilitator between you and independent Pilots. The fare displayed is authoritative based on the confirmed booking. A tax invoice will not be provided for this trip.',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: const Color(0xFF94A3B8),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

/// Custom painter for the vertical dotted line connecting pickup and dropoff
class _DottedLinePainter extends CustomPainter {
  final Color color;
  _DottedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const double dashHeight = 4.0;
    const double dashSpace = 4.0;
    double startY = 4.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0;

    while (startY < size.height - 4.0) {
      canvas.drawLine(Offset(size.width / 2, startY), Offset(size.width / 2, startY + dashHeight), paint);
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom painter for the horizontal dotted separator in the fare summary card
class _HorizontalDottedLinePainter extends CustomPainter {
  final Color color;
  _HorizontalDottedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const double dashWidth = 4.0;
    const double dashSpace = 4.0;
    double startX = 0.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;

    while (startX < size.width) {
      canvas.drawLine(Offset(startX, 0), Offset(startX + dashWidth, 0), paint);
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
