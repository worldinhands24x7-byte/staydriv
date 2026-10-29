import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/socket_service.dart';
import '../../../core/call_masking_service.dart';
import '../models/food_models.dart';
import '../services/food_service.dart';

class FoodOrderTrackingScreen extends StatefulWidget {
  final String orderId;
  final FoodOrder? initialOrder;

  const FoodOrderTrackingScreen({
    Key? key,
    required this.orderId,
    this.initialOrder,
  }) : super(key: key);

  @override
  State<FoodOrderTrackingScreen> createState() => _FoodOrderTrackingScreenState();
}

class _FoodOrderTrackingScreenState extends State<FoodOrderTrackingScreen> {
  final FoodService _foodService = FoodService();
  FoodOrder? _order;
  Timer? _pollingTimer;
  bool _isLoading = true;
  bool _isCancelling = false;

  GoogleMapController? _mapController;
  LatLng? _pilotLatLng;

  @override
  void initState() {
    super.initState();
    _order = widget.initialOrder;
    _fetchLatestOrder();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchLatestOrder());
    _initSocket();
  }

  void _initSocket() {
    try {
      SocketService().initSocket();
      SocketService().joinFoodOrder(widget.orderId);
      SocketService().addFoodOrderStatusListener(_onSocketStatusUpdate);
      SocketService().socket?.on('pilot_location', (data) {
        if (!mounted || data == null) return;
        try {
          final lat = double.tryParse(data['lat']?.toString() ?? '');
          final lng = double.tryParse(data['lng']?.toString() ?? '');
          if (lat != null && lng != null) {
            setState(() {
              _pilotLatLng = LatLng(lat, lng);
            });
          }
        } catch (_) {}
      });
      SocketService().socket?.on('food_pilot_location', (data) {
        if (!mounted || data == null) return;
        try {
          final lat = double.tryParse(data['lat']?.toString() ?? '');
          final lng = double.tryParse(data['lng']?.toString() ?? '');
          if (lat != null && lng != null) {
            setState(() {
              _pilotLatLng = LatLng(lat, lng);
            });
          }
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('[FoodOrderTracking] Socket init error: $e');
    }
  }

  void _onSocketStatusUpdate(Map<String, dynamic> data) {
    if (!mounted) return;
    try {
      final order = FoodOrder.fromJson(data);
      if (order.orderId == widget.orderId) {
        setState(() {
          _order = order;
          _isLoading = false;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    SocketService().removeFoodOrderStatusListener(_onSocketStatusUpdate);
    super.dispose();
  }

  Future<void> _fetchLatestOrder() async {
    final updated = await _foodService.fetchOrderDetails(widget.orderId);
    if (mounted && updated != null) {
      setState(() {
        _order = updated;
        _isLoading = false;
      });
    } else if (mounted && _order != null) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleCancelOrder() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancel Order?', style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
        content: Text(
          'Are you sure you want to cancel this order? This cannot be undone.',
          style: GoogleFonts.inter(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Order')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Cancel', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isCancelling = true);
    final ok = await _foodService.cancelOrder(widget.orderId, 'Customer cancelled from tracking screen');
    if (mounted) {
      setState(() => _isCancelling = false);
      if (ok) {
        _fetchLatestOrder();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order cancelled successfully.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not cancel order. It might already be in kitchen preparation.')),
        );
      }
    }
  }

  int _getStatusStepIndex(String status) {
    switch (status) {
      case 'placed':
        return 0;
      case 'accepted':
        return 1;
      case 'preparing':
        return 2;
      case 'ready_for_pickup':
      case 'pilot_assigned':
        return 3;
      case 'picked_up':
      case 'out_for_delivery':
        return 4;
      case 'delivered':
        return 5;
      default:
        return 0;
    }
  }

  String _getStatusHeading(String status) {
    switch (status) {
      case 'placed':
        return 'Order Placed with Restaurant';
      case 'accepted':
        return 'Order Accepted by Kitchen';
      case 'preparing':
        return 'Kitchen is Preparing Your Food';
      case 'ready_for_pickup':
        return 'Food Packed & Ready for Pickup';
      case 'pilot_assigned':
        return 'Delivery Pilot Assigned';
      case 'picked_up':
        return 'Pilot Picked Up Your Food';
      case 'out_for_delivery':
        return 'Pilot is Heading to Your Door';
      case 'delivery_failed_reported':
      case 'return_to_restaurant':
      case 'return_arrived_at_restaurant':
      case 'return_otp_pending':
        return 'Delivery Unsuccessful — Returning Food';
      case 'returned_to_restaurant':
        return 'Food Returned to Restaurant';
      case 'delivered':
        return 'Food Delivered! Bon Appétit!';
      case 'cancelled':
        return 'Order Cancelled';
      case 'rejected':
        return 'Order Declined by Restaurant';
      default:
        return 'Order Status: $status';
    }
  }

  String _getStatusSubtext(String status) {
    switch (status) {
      case 'placed':
        return 'Waiting for restaurant confirmation...';
      case 'accepted':
        return 'Kitchen confirmed and will start cooking shortly.';
      case 'preparing':
        return 'Fresh ingredients are being cooked with care.';
      case 'ready_for_pickup':
        return 'Food is ready and packed. Awaiting pilot pickup.';
      case 'pilot_assigned':
        return 'Pilot is on the way to collect your order from restaurant.';
      case 'picked_up':
        return 'Pilot has collected your food and is riding to your address.';
      case 'out_for_delivery':
        return 'Pilot is arriving at your delivery location.';
      case 'delivery_failed_reported':
      case 'return_to_restaurant':
        return 'Delivery could not be completed. Pilot is returning food package safely to the kitchen.';
      case 'return_arrived_at_restaurant':
      case 'return_otp_pending':
        return 'Pilot has arrived at the restaurant. Handing over package to kitchen staff.';
      case 'returned_to_restaurant':
        return 'Food package has been safely returned and verified by restaurant staff.';
      case 'delivered':
        return 'Delivered successfully. Thank you for using StayDriv!';
      case 'cancelled':
        return 'This order was cancelled.';
      case 'rejected':
        return 'The restaurant could not accept the order.';
      default:
        return 'Status updated.';
    }
  }

  Future<void> _callPilot(FoodOrder order) async {
    if (order.deliveryPartnerId.isEmpty && order.deliveryPartnerPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Delivery pilot has not been assigned to this order yet.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    await CallMaskingService().callFoodOrder(
      orderId: order.orderId,
      callerRole: 'customer',
      targetRole: 'pilot',
      contactName: order.deliveryPartnerName.isNotEmpty ? order.deliveryPartnerName : 'StayDriv Pilot',
      context: context,
    );
  }

  Future<void> _callRestaurant(FoodOrder order) async {
    await CallMaskingService().callFoodOrder(
      orderId: order.orderId,
      callerRole: 'customer',
      targetRole: 'restaurant',
      contactName: order.restaurantName.isNotEmpty ? order.restaurantName : 'Restaurant',
      context: context,
    );
  }

  void _fitMapBounds(LatLng p1, LatLng p2) {
    if (_mapController == null) return;
    try {
      final southwest = LatLng(
        math.min(p1.latitude, p2.latitude),
        math.min(p1.longitude, p2.longitude),
      );
      final northeast = LatLng(
        math.max(p1.latitude, p2.latitude),
        math.max(p1.longitude, p2.longitude),
      );
      final bounds = LatLngBounds(southwest: southwest, northeast: northeast);
      _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
    } catch (_) {}
  }

  Widget _buildLiveTrackingMap(FoodOrder order) {
    double? rLat = order.restaurantLat;
    double? rLng = order.restaurantLng;
    double? dLat = order.deliveryLat;
    double? dLng = order.deliveryLng;

    // Guard against coordinate inversion
    if (rLat != null && rLng != null && rLat > 50 && rLng < 40) {
      final t = rLat;
      rLat = rLng;
      rLng = t;
    }
    if (dLat != null && dLng != null && dLat > 50 && dLng < 40) {
      final t = dLat;
      dLat = dLng;
      dLng = t;
    }

    final bool hasValidRest = rLat != null && rLng != null && !rLat.isNaN && !rLng.isNaN && (rLat != 0.0 || rLng != 0.0);
    final bool hasValidDel = dLat != null && dLng != null && !dLat.isNaN && !dLng.isNaN && (dLat != 0.0 || dLng != 0.0);

    if (!hasValidRest || !hasValidDel) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Live map preview will appear once the restaurant and delivery coordinates are verified on the map.',
                style: GoogleFonts.inter(color: const Color(0xFF92400E), fontSize: 12.5, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      );
    }

    final restLatLng = LatLng(rLat, rLng);
    final delLatLng = LatLng(dLat, dLng);

    final markers = <Marker>{
      // Restaurant Pin
      Marker(
        markerId: const MarkerId('restaurant_pin'),
        position: restLatLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(
          title: '🏬 ${order.restaurantName}',
          snippet: order.restaurantAddress,
        ),
      ),
      // Customer Delivery Pin
      Marker(
        markerId: const MarkerId('customer_pin'),
        position: delLatLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: '📍 Delivery Address',
          snippet: order.deliveryAddress,
        ),
      ),
    };

    if (_pilotLatLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('pilot_pin'),
          position: _pilotLatLng!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(
            title: '🛵 ${order.deliveryPartnerName.isNotEmpty ? order.deliveryPartnerName : "StayDriv Pilot"}',
            snippet: 'On the way',
          ),
        ),
      );
    }

    final polylines = <Polyline>{
      Polyline(
        polylineId: const PolylineId('food_delivery_route'),
        points: [restLatLng, if (_pilotLatLng != null) _pilotLatLng!, delLatLng],
        color: const Color(0xFFEA580C),
        width: 4,
      ),
    };

    return Container(
      height: 230,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: restLatLng,
              zoom: 14.0,
            ),
            onMapCreated: (ctrl) {
              _mapController = ctrl;
              _fitMapBounds(restLatLng, delLatLng);
            },
            markers: markers,
            polylines: polylines,
            myLocationEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.storefront_rounded, color: Color(0xFFFB923C), size: 14),
                      const SizedBox(width: 4),
                      Text(
                        order.restaurantName,
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (order.distanceKm != null || order.prepTime.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      order.distanceKm != null ? '${order.distanceKm!.toStringAsFixed(1)} km' : order.prepTime,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Live Food Order Tracking',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1E293B),
          ),
        ),
      ),
      body: (_isLoading && order == null)
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFEA580C)))
          : order == null
              ? const Center(child: Text('Order details unavailable.'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Status Banner Card
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: (order.isReturnActive || order.isReturned)
                                ? const [Color(0xFFDC2626), Color(0xFF991B1B)]
                                : const [Color(0xFFEA580C), Color(0xFFC2410C)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: (order.isReturnActive || order.isReturned)
                                  ? const Color(0xFFDC2626).withOpacity(0.3)
                                  : const Color(0xFFEA580C).withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'ORDER ID: ${order.orderId}',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white.withOpacity(0.9),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    (order.isReturnActive || order.isReturned) ? 'RETURN' : 'LIVE',
                                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _getStatusHeading(order.orderStatus),
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _getStatusSubtext(order.orderStatus),
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                            if (order.returnReason.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Failure Reason: ${order.returnReason}',
                                  style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // 1.5 Interactive Live Tracking Map
                      _buildLiveTrackingMap(order),

                      // 2. Delivery OTP Card (if active delivery and not returning)
                      if (!order.isReturnActive && !order.isReturned && order.deliveryOtp.isNotEmpty && order.orderStatus != 'delivered' && order.orderStatus != 'cancelled' && order.orderStatus != 'rejected')
                        Container(
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFFED7AA)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFEDD5),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.key_rounded, color: Color(0xFFEA580C), size: 24),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Food Delivery Verification OTP',
                                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      order.deliveryOtp,
                                      style: GoogleFonts.robotoMono(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFFEA580C),
                                        letterSpacing: 2.0,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                'Share with Pilot',
                                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),

                      // 2.5 Assigned Delivery Pilot Card (when pilot is assigned)
                      if (order.deliveryPartnerName.isNotEmpty && order.orderStatus != 'delivered' && order.orderStatus != 'cancelled' && order.orderStatus != 'rejected')
                        Container(
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.two_wheeler_rounded, color: Color(0xFF2563EB), size: 24),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Assigned Delivery Pilot',
                                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      order.deliveryPartnerName,
                                      style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A)),
                                    ),
                                    Row(
                                      children: [
                                        const Icon(Icons.shield_rounded, size: 12, color: Color(0xFF10B981)),
                                        const SizedBox(width: 4),
                                        Text(
                                          'StayDriv Masked Line',
                                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF10B981)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (order.deliveryPartnerPhone.isNotEmpty)
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF10B981),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    elevation: 0,
                                  ),
                                  onPressed: () => _callPilot(order),
                                  icon: const Icon(Icons.phone_in_talk_rounded, size: 14),
                                  label: const Text('Call Pilot', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                                ),
                            ],
                          ),
                        ),

                      // 3. Progress Timeline
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Delivery Progress',
                              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B)),
                            ),
                            const SizedBox(height: 16),
                            _buildTimelineStep(0, 'Order Placed', 'Sent to restaurant kitchen', order.orderStatus),
                            _buildTimelineStep(1, 'Order Accepted', 'Restaurant confirmed order', order.orderStatus),
                            _buildTimelineStep(2, 'Cooking & Preparing', 'Freshly cooking your food', order.orderStatus),
                            _buildTimelineStep(3, 'Ready for Pickup', 'Food is packed and sealed', order.orderStatus),
                            _buildTimelineStep(4, 'Pilot On the Way', 'StayDriv delivery pilot en route', order.orderStatus),
                            if (order.isReturnActive || order.isReturned)
                              _buildTimelineStep(
                                5,
                                order.isReturned ? 'Returned to Restaurant' : 'Returning to Restaurant',
                                order.isReturned
                                    ? 'Food returned to kitchen (${order.returnReason})'
                                    : 'Delivery unsuccessful. Returning package to kitchen.',
                                order.orderStatus,
                                isLast: true,
                              )
                            else
                              _buildTimelineStep(5, 'Food Delivered', 'Delivered to your address', order.orderStatus, isLast: true),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // 4. Restaurant & Delivery Details Card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.store_rounded, size: 20, color: Color(0xFFEA580C)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        order.restaurantName,
                                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)),
                                      ),
                                      Text(
                                        order.restaurantAddress,
                                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ),
                                if (order.restaurantId.isNotEmpty || order.restaurantPhone.isNotEmpty)
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2563EB),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      elevation: 0,
                                    ),
                                    onPressed: () => _callRestaurant(order),
                                    icon: const Icon(Icons.phone_in_talk_rounded, size: 13),
                                    label: const Text('Call Restaurant', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                  ),
                              ],
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                            ),
                            Row(
                              children: [
                                const Icon(Icons.location_on_rounded, size: 20, color: Color(0xFF16A34A)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Delivering to',
                                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)),
                                      ),
                                      Text(
                                        order.deliveryAddress,
                                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                                      ),
                                      if (order.deliveryInstructions.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'Note: ${order.deliveryInstructions}',
                                          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFEA580C), fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // 5. Items Summary Card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Order Items (${order.items.length})',
                              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B)),
                            ),
                            const SizedBox(height: 10),
                            ...order.items.map((i) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${i.quantity}x ${i.item.name}',
                                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                                    ),
                                    Text(
                                      '₹${i.lineTotal.toStringAsFixed(0)}',
                                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                            const Divider(height: 16, color: Color(0xFFF1F5F9)),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total Paid',
                                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800),
                                ),
                                Text(
                                  '₹${order.totalAmount.toStringAsFixed(0)}',
                                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFFEA580C)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // 6. Cancel Button (Only if still in 'placed' state)
                      if (order.orderStatus == 'placed')
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFDC2626),
                              side: const BorderSide(color: Color(0xFFDC2626)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _isCancelling ? null : _handleCancelOrder,
                            child: _isCancelling
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(color: Color(0xFFDC2626), strokeWidth: 2),
                                  )
                                : Text(
                                    'Cancel Food Order',
                                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
                                  ),
                          ),
                        ),

                      const SizedBox(height: 30),
                    ],
                  ),
                ),
    );
  }

  Widget _buildTimelineStep(int stepIndex, String title, String subtitle, String currentStatus, {bool isLast = false}) {
    final activeIndex = _getStatusStepIndex(currentStatus);
    final isPassed = activeIndex >= stepIndex;
    final isCurrent = activeIndex == stepIndex;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isPassed ? const Color(0xFFEA580C) : const Color(0xFFE2E8F0),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: isPassed
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF94A3B8), shape: BoxShape.circle)),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 34,
                color: isPassed && activeIndex > stepIndex ? const Color(0xFFEA580C) : const Color(0xFFE2E8F0),
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: isCurrent || isPassed ? FontWeight.w700 : FontWeight.w500,
                  color: isCurrent ? const Color(0xFFEA580C) : (isPassed ? const Color(0xFF1E293B) : const Color(0xFF94A3B8)),
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }
}

