import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../core/js_stub.dart'
    if (dart.library.js) 'dart:js' as js;
import '../models/food_models.dart';
import '../services/food_service.dart';

/// StayDriv Platinum Food Membership Screen
/// 
/// Replaces Gold Membership with the luxury StayDriv Platinum Food Membership.
/// Features:
/// - 1:1 match with reference design (Screen 1 & Screen 2)
/// - ₹1 for 3 months offer (Free delivery above ₹99 within 7 km, Up to 30% extra off)
/// - Dynamic participating restaurant grid ("On Delivery" section)
/// - Razorpay Flutter SDK checkout integration with server-side HMAC-SHA256 verification
/// - Dynamic address selection & coupon code support
/// - Active membership dashboard with savings breakdown
class FoodMembershipScreen extends StatefulWidget {
  final VoidCallback? onOrderFoodPressed;

  const FoodMembershipScreen({
    super.key,
    this.onOrderFoodPressed,
  });

  @override
  State<FoodMembershipScreen> createState() => _FoodMembershipScreenState();
}

class _FoodMembershipScreenState extends State<FoodMembershipScreen> {
  final FoodService _foodService = FoodService();
  late Razorpay _razorpay;

  List<FoodMembershipPlanModel> _plans = [];
  CustomerFoodMembershipModel? _activeMembership;
  List<Map<String, dynamic>> _participatingRestaurants = [];

  bool _isLoading = true;
  bool _isProcessingPayment = false;
  String _customerId = 'CUST_STAYDRIV_01';
  String _customerPhone = '9876543210';
  String _customerName = 'Valued Customer';
  String _userAddress = 'Sri Balaji Layout, Gajularamaram, Hyderabad, Telangana 500055';

  // Coupon state
  final TextEditingController _couponController = TextEditingController();
  bool _isCouponApplied = false;
  String _appliedCouponCode = '';

  // Pending Razorpay order details for verification
  String? _pendingOrderId;
  FoodMembershipPlanModel? _pendingPlan;

  @override
  void initState() {
    super.initState();
    _initRazorpay();
    _loadUserAndMembershipData();
  }

  void _initRazorpay() {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleRazorpaySuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handleRazorpayError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleRazorpayWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    _couponController.dispose();
    super.dispose();
  }

  Future<void> _loadUserAndMembershipData() async {
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final storedPhone = prefs.getString('phone_number') ??
          prefs.getString('phone') ??
          prefs.getString('user_phone');
      final storedUid = prefs.getString('user_uid') ??
          prefs.getString('user_id') ??
          prefs.getString('uid');
      final cachedMemId = prefs.getString('active_food_membership_id') ??
          prefs.getString('platinum_membership_id');

      _customerPhone = (storedPhone != null && storedPhone.isNotEmpty)
          ? storedPhone
          : '9876543210';
      _customerId = (storedUid != null && storedUid.isNotEmpty)
          ? storedUid
          : (storedPhone != null && storedPhone.isNotEmpty ? 'CUST_$storedPhone' : 'CUST_STAYDRIV_01');
      _customerName = prefs.getString('user_name') ?? prefs.getString('name') ?? 'Valued Customer';
      _userAddress = prefs.getString('user_address') ??
          prefs.getString('saved_address') ??
          prefs.getString('pickup_address') ??
          'Sri Balaji Layout, Gajularamaram, Hyderabad, Telangana 500055';

      final results = await Future.wait([
        _foodService.fetchMembershipPlans(),
        _foodService.fetchCustomerMembership(_customerId, phone: _customerPhone, membershipId: cachedMemId),
        _foodService.fetchParticipatingRestaurants(),
      ]);

      final plans = results[0] as List<FoodMembershipPlanModel>;
      final membership = results[1] as CustomerFoodMembershipModel?;
      final restaurants = results[2] as List<Map<String, dynamic>>;

      if (membership != null) {
        await prefs.setString('active_food_membership_id', membership.membershipId);
        await prefs.setString('platinum_membership_id', membership.membershipId);
        await prefs.setString('platinum_membership_customer_id', _customerId);
        await prefs.setString('platinum_membership_phone', _customerPhone);
        await prefs.setBool('is_platinum_member', true);
      }

      if (mounted) {
        setState(() {
          _plans = plans;
          _activeMembership = membership;
          _participatingRestaurants = restaurants.isNotEmpty
              ? restaurants
              : _getDefaultReferenceRestaurants();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[FoodMembershipScreen] Error loading data: $e');
      if (mounted) {
        setState(() {
          _participatingRestaurants = _getDefaultReferenceRestaurants();
          _isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _getDefaultReferenceRestaurants() {
    return [
      {
        'restaurantId': 'rest_punjabi_affair',
        'name': 'Punjabi Affair',
        'extraDiscountPercent': 20,
        'tagline': 'North Indian, Mughlai',
        'rating': 4.3,
        'imageUrl': 'https://images.unsplash.com/photo-1589302168068-964664d93dc0?w=300&q=80',
      },
      {
        'restaurantId': 'rest_bakinnbros',
        'name': 'Bakinnbros',
        'extraDiscountPercent': 10,
        'tagline': 'Bakery, Cakes, Desserts',
        'rating': 4.5,
        'imageUrl': 'https://images.unsplash.com/photo-1578985545062-69928b1d9587?w=300&q=80',
      },
      {
        'restaurantId': 'rest_ks_bakers',
        'name': 'KS Bakers',
        'extraDiscountPercent': 10,
        'tagline': 'Bakery, Fast Food',
        'rating': 4.2,
        'imageUrl': 'https://images.unsplash.com/photo-1509440159596-0249088772ff?w=300&q=80',
      },
      {
        'restaurantId': 'rest_peacock_restro',
        'name': 'Peacock Restro',
        'extraDiscountPercent': 10,
        'tagline': 'Biryani, South Indian',
        'rating': 4.4,
        'imageUrl': 'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=300&q=80',
      },
    ];
  }

  FoodMembershipPlanModel? get _platinumPlan {
    if (_plans.isEmpty) {
      return FoodMembershipPlanModel(
        planId: 'plan_platinum_3m',
        planType: 'platinum',
        name: 'StayDriv Platinum Food Membership',
        tagline: '₹1 for 3 months • Free Delivery & Up to 30% Extra Off',
        description: 'Unlimited free delivery above ₹99 within 7 km & up to 30% extra off on food orders.',
        price: 1.0,
        originalPrice: 499.0,
        validityDays: 90,
        validityMonths: 3,
        minOrderAmount: 99.0,
        deliveryRadiusKm: 7.0,
        maxDiscountPercent: 30.0,
      );
    }
    return _plans.firstWhere(
      (p) => p.planType == 'platinum',
      orElse: () => _plans.first,
    );
  }

  // -------------------------------------------------------------
  // RAZORPAY PAYMENT INTEGRATION
  // -------------------------------------------------------------
  Future<void> _startRazorpayCheckout(FoodMembershipPlanModel plan) async {
    if (_isProcessingPayment) return;
    setState(() => _isProcessingPayment = true);
    _pendingPlan = plan;

    try {
      // 1. Create real order on StayDriv backend (amount: 100 paise = ₹1)
      final orderResponse = await _foodService.createMembershipOrder(
        customerId: _customerId,
        customerPhone: _customerPhone,
        customerName: _customerName,
        planId: plan.planId,
      );

      if (orderResponse == null) {
        throw Exception('Failed to create Razorpay order from StayDriv server');
      }

      if (orderResponse['alreadyActive'] == true) {
        setState(() => _isProcessingPayment = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(orderResponse['message']?.toString() ?? 'You already have an active Platinum membership!'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        }
        _loadUserAndMembershipData();
        return;
      }

      final String? orderId = orderResponse['orderId']?.toString();
      if (orderId == null || orderId.isEmpty) {
        throw Exception('Server did not return a valid payment order ID');
      }

      // Ensure amount is strictly 100 paise (₹1) as configured
      final int amountInPaise = orderResponse['amountInPaise'] is int
          ? orderResponse['amountInPaise'] as int
          : (orderResponse['amount'] is int && (orderResponse['amount'] as int) > 50
              ? orderResponse['amount'] as int
              : (plan.price * 100).toInt());

      final String keyId = orderResponse['keyId']?.toString() ?? 'rzp_live_Ta9cOGnIySuBCb';
      _pendingOrderId = orderId;

      debugPrint('[Razorpay] Opening real checkout for Order ID: $orderId, amount: $amountInPaise paise (₹${plan.price.toStringAsFixed(0)})');

      if (kIsWeb) {
        // --- Web Platform: Official Razorpay Web checkout.js integration ---
        js.context['onStayDrivMembershipPaymentResult'] = js.allowInterop((resultStr) {
          debugPrint('[Razorpay Web] Checkout callback result: $resultStr');
          try {
            final Map<String, dynamic> res = jsonDecode(resultStr.toString());
            final status = res['status']?.toString();

            if (status == 'success') {
              final rzpOrderId = res['razorpay_order_id']?.toString() ?? orderId;
              final rzpPaymentId = res['razorpay_payment_id']?.toString() ?? '';
              final rzpSignature = res['razorpay_signature']?.toString() ?? '';
              _handleServerVerification(rzpOrderId, rzpPaymentId, rzpSignature);
            } else if (status == 'cancelled') {
              _handleRazorpayError(PaymentFailureResponse(
                Razorpay.PAYMENT_CANCELLED,
                'Payment cancelled. You can retry whenever you are ready.',
                null,
              ));
            } else {
              final errMsg = res['message']?.toString() ?? 'Payment was unsuccessful.';
              final errCode = res['code'] is int ? res['code'] as int : Razorpay.UNKNOWN_ERROR;
              _handleRazorpayError(PaymentFailureResponse(
                errCode,
                errMsg,
                res['error'] is Map ? res['error'] as Map : null,
              ));
            }
          } catch (e) {
            _handleRazorpayError(PaymentFailureResponse(
              Razorpay.UNKNOWN_ERROR,
              'Error processing payment result: $e',
              null,
            ));
          }
        });

        final webOptions = {
          'key': keyId,
          'amount': amountInPaise,
          'currency': 'INR',
          'name': 'StayDriv',
          'description': 'StayDriv Platinum Food Membership (₹1 for 3 months)',
          'order_id': orderId,
          'prefill': {
            'contact': _customerPhone,
            'email': 'customer@staydriv.com',
            'name': _customerName,
          },
          'theme': {
            'color': '#0B0E14',
          },
          'modal': {
            'confirm_close': true,
          },
        };

        js.context.callMethod('openStayDrivRazorpayCheckout', [
          jsonEncode(webOptions),
          'onStayDrivMembershipPaymentResult',
        ]);
      } else {
        // --- Mobile Native Platform (Android / iOS): Official Razorpay Flutter SDK ---
        final options = {
          'key': keyId,
          'amount': amountInPaise,
          'name': 'StayDriv',
          'description': 'StayDriv Platinum Food Membership',
          'order_id': orderId,
          'prefill': {
            'contact': _customerPhone,
            'email': 'customer@staydriv.com',
            'name': _customerName,
          },
          'theme': {
            'color': '#0B0E14',
          },
          'modal': {
            'confirm_close': true,
          },
          'send_sms_hash': true,
        };

        _razorpay.open(options);
      }
    } catch (e) {
      debugPrint('[Razorpay] Error initiating order: $e');
      if (mounted) {
        setState(() => _isProcessingPayment = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment initiation failed: $e'),
            backgroundColor: const Color(0xFFDC2626),
            action: SnackBarAction(
              label: 'Retry Payment',
              textColor: const Color(0xFFFBBF24),
              onPressed: () => _startRazorpayCheckout(plan),
            ),
          ),
        );
      }
    }
  }

  void _handleRazorpaySuccess(PaymentSuccessResponse response) {
    debugPrint('[Razorpay] Payment Success! Payment ID: ${response.paymentId}');
    final orderId = response.orderId ?? _pendingOrderId ?? '';
    final paymentId = response.paymentId ?? '';
    final signature = response.signature ?? '';

    _handleServerVerification(orderId, paymentId, signature);
  }

  void _handleRazorpayError(PaymentFailureResponse response) {
    debugPrint('[Razorpay] Payment Error: ${response.code} - ${response.message}');
    
    // Explicitly record payment failure or cancellation on backend
    _foodService.recordMembershipPaymentFailure(
      gatewayOrderId: _pendingOrderId,
      customerId: _customerId,
      customerPhone: _customerPhone,
      errorCode: response.code,
      errorMessage: response.message,
    );

    if (mounted) {
      setState(() => _isProcessingPayment = false);
      final isCancelled = response.code == 2 || (response.message?.toLowerCase().contains('cancel') ?? false);
      final displayMessage = isCancelled
          ? 'Payment cancelled. You can retry whenever you are ready.'
          : (response.message != null && response.message!.isNotEmpty
              ? 'Payment failed: ${response.message}'
              : 'Payment cancelled or declined.');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(displayMessage),
          backgroundColor: const Color(0xFFDC2626),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Retry Payment',
            textColor: const Color(0xFFFBBF24),
            onPressed: () {
              final targetPlan = _pendingPlan ?? _platinumPlan;
              if (targetPlan != null) {
                _startRazorpayCheckout(targetPlan);
              }
            },
          ),
        ),
      );
    }
  }

  void _handleRazorpayWallet(ExternalWalletResponse response) {
    debugPrint('[Razorpay] External Wallet Selected: ${response.walletName}');
  }

  Future<void> _handleServerVerification(String orderId, String paymentId, String signature) async {
    final plan = _pendingPlan ?? _platinumPlan;
    if (plan == null) return;

    try {
      final activatedMembership = await _foodService.verifyMembershipPayment(
        customerId: _customerId,
        customerPhone: _customerPhone,
        customerName: _customerName,
        planId: plan.planId,
        gatewayOrderId: orderId,
        gatewayPaymentId: paymentId,
        gatewaySignature: signature,
        paymentMethod: 'razorpay',
      );

      if (!mounted) return;

      if (activatedMembership != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('active_food_membership_id', activatedMembership.membershipId);
        await prefs.setString('platinum_membership_id', activatedMembership.membershipId);
        await prefs.setString('platinum_membership_customer_id', _customerId);
        await prefs.setString('platinum_membership_phone', _customerPhone);
        await prefs.setBool('is_platinum_member', true);

        setState(() {
          _activeMembership = activatedMembership;
          _isProcessingPayment = false;
        });

        // Close checkout sheet if open
        Navigator.of(context).popUntil((route) => route.isFirst || route.settings.name == '/food_membership');

        // Show congratulations dialog
        _showSuccessActivationDialog(activatedMembership);

        // Also display celebratory SnackBar
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Congratulations! StayDriv Platinum is activated for 3 months.'),
            backgroundColor: Color(0xFF10B981),
            duration: Duration(seconds: 5),
          ),
        );
      } else {
        setState(() => _isProcessingPayment = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Payment verification failed. You can safely retry.'),
            backgroundColor: const Color(0xFFDC2626),
            action: SnackBarAction(
              label: 'Retry Payment',
              textColor: const Color(0xFFFBBF24),
              onPressed: () => _startRazorpayCheckout(plan),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('[Razorpay] Server verification error: $e');
      if (mounted) {
        setState(() => _isProcessingPayment = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification error: $e'),
            backgroundColor: const Color(0xFFDC2626),
            action: SnackBarAction(
              label: 'Retry Payment',
              textColor: const Color(0xFFFBBF24),
              onPressed: () => _startRazorpayCheckout(plan),
            ),
          ),
        );
      }
    }
  }

  // -------------------------------------------------------------
  // CHECKOUT BOTTOM SHEET (SCREEN 2 REFERENCE MATCH)
  // -------------------------------------------------------------
  void _showCheckoutSheet() {
    final plan = _platinumPlan;
    if (plan == null) return;

    // Calculate dynamic valid till date (e.g. 90 days from today)
    final validTillDate = DateTime.now().add(Duration(days: plan.validityDays));
    final validTillFormatted = '${validTillDate.day}th ${_monthName(validTillDate.month)} ${validTillDate.year}';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag Handle
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Top Luxury Black & Gold Header Card (Screen 2 Reference)
                    Container(
                      width: double.infinity,
                      height: 110,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F1420),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          children: [
                            // Gold curved wave accent on right
                            Positioned(
                              right: -30,
                              top: -20,
                              bottom: -20,
                              width: 140,
                              child: CustomPaint(
                                painter: _GoldWavePainter(),
                              ),
                            ),
                            // Content
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  // Gold Crown
                                  SizedBox(
                                    width: 54,
                                    height: 54,
                                    child: CustomPaint(
                                      painter: _CrownPainter(),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'STAYDRIV',
                                          style: GoogleFonts.inter(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                            letterSpacing: 1.5,
                                          ),
                                        ),
                                        Text(
                                          'PLATINUM',
                                          style: GoogleFonts.cinzel(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w900,
                                            color: const Color(0xFFF59E0B),
                                            letterSpacing: 2.0,
                                          ),
                                        ),
                                        Text(
                                          'FOOD MEMBERSHIP',
                                          style: GoogleFonts.inter(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: const Color(0xFFFDE68A),
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Membership details row: "3-month membership - ₹1" & "Valid Till ..."
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '3-month membership',
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Valid Till $validTillFormatted',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: const Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '₹${plan.price.toStringAsFixed(0)}',
                          style: GoogleFonts.inter(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFFD97706),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: Color(0xFFE2E8F0), thickness: 1),
                    const SizedBox(height: 16),

                    // Perk 1: Free delivery
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.two_wheeler_rounded,
                            color: Color(0xFFD97706),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'Free delivery under ${plan.deliveryRadiusKm.toStringAsFixed(0)} kms, above ₹${plan.minOrderAmount.toStringAsFixed(0)}',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Perk 2: Extra offers on delivery
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.confirmation_number_rounded,
                            color: Color(0xFFE11D48),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'Extra offers on delivery (Up to ${plan.maxDiscountPercent.toStringAsFixed(0)}% Extra Off)',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),

                    // Billing Address Card with [Change] button (Screen 2 Reference)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.location_on_rounded,
                              color: Color(0xFFEF4444),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Billing Address (Using current location)',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: const Color(0xFF64748B),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _userAddress,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: const Color(0xFF1E293B),
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => _showEditAddressDialog(setSheetState),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Change',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFFDC2626),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),

                    // Coral-Red Primary CTA Button (Screen 2 Reference: "Add Payment Method >")
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF2E55),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 3,
                          shadowColor: const Color(0xFFFF2E55).withOpacity(0.4),
                        ),
                        onPressed: _isProcessingPayment
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                _startRazorpayCheckout(plan);
                              },
                        child: _isProcessingPayment
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Add Payment Method • Pay ₹${plan.price.toStringAsFixed(0)}',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.white),
                                ],
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

  void _showEditAddressDialog(StateSetter setSheetState) {
    final controller = TextEditingController(text: _userAddress);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Billing Address', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16)),
        content: TextField(
          controller: controller,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'Enter complete billing address',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF2E55)),
            onPressed: () async {
              final newAddr = controller.text.trim();
              if (newAddr.isNotEmpty) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('user_address', newAddr);
                if (mounted) {
                  setState(() => _userAddress = newAddr);
                  setSheetState(() => _userAddress = newAddr);
                }
              }
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save Address', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // SUCCESS CONGRATULATIONS DIALOG
  // -------------------------------------------------------------
  void _showSuccessActivationDialog(CustomerFoodMembershipModel membership) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Color(0xFFF59E0B), width: 1.5),
          ),
          contentPadding: const EdgeInsets.all(22),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Gold Crown Badge
              SizedBox(
                width: 60,
                height: 60,
                child: CustomPaint(
                  painter: _CrownPainter(),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Welcome to Platinum!',
                style: GoogleFonts.cinzel(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFFBBF24),
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Your StayDriv Platinum Food Membership is active for 3 Months (90 Days).',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFFCBD5E1), height: 1.4),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Membership ID:', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8))),
                    Text(
                      membership.membershipId,
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFFFBBF24)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: const Color(0xFF0F172A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    if (widget.onOrderFoodPressed != null) {
                      widget.onOrderFoodPressed!();
                    }
                  },
                  child: Text(
                    'Order Food Now',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------
  // BUILD SCREEN
  // -------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final hasActiveMembership = _activeMembership != null && _activeMembership!.isActive;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0D14), // Deep Jet Black Theme
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0D14),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'StayDriv Platinum',
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF94A3B8)),
            onPressed: _loadUserAndMembershipData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)))
          : RefreshIndicator(
              onRefresh: _loadUserAndMembershipData,
              color: const Color(0xFFF59E0B),
              backgroundColor: const Color(0xFF1E2638),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                child: hasActiveMembership
                    ? _buildActivePlatinumView()
                    : _buildPlatinumOfferView(),
              ),
            ),
      bottomNavigationBar: !hasActiveMembership && !_isLoading
          ? _buildStickyBottomBar()
          : null,
    );
  }

  // -------------------------------------------------------------
  // SCREEN 1: PLATINUM OFFER VIEW (1:1 REFERENCE MATCH)
  // -------------------------------------------------------------
  Widget _buildPlatinumOfferView() {
    final plan = _platinumPlan;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. TOP LUXURY CARD WITH ARCHED BADGE & "₹1 for 3 months"
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 14),
              padding: const EdgeInsets.fromLTRB(18, 28, 18, 18),
              decoration: BoxDecoration(
                color: const Color(0xFF0F131D),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withOpacity(0.55),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFF59E0B).withOpacity(0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Row: "₹1 for 3 months" + 3D Gold Crown
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Pricing Text
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [Color(0xFFFEF08A), Color(0xFFF59E0B), Color(0xFFD97706)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ).createShader(bounds),
                              child: Text(
                                '₹${plan?.price.toStringAsFixed(0) ?? '1'}',
                                style: GoogleFonts.inter(
                                  fontSize: 44,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'for 3 months',
                                style: GoogleFonts.inter(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Gold Crown with sparkles
                      SizedBox(
                        width: 72,
                        height: 60,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomPaint(
                              size: const Size(60, 48),
                              painter: _CrownPainter(),
                            ),
                            const Positioned(
                              top: 2,
                              left: 4,
                              child: Icon(Icons.auto_awesome, color: Color(0xFFFDE68A), size: 14),
                            ),
                            const Positioned(
                              bottom: 6,
                              right: 2,
                              child: Icon(Icons.auto_awesome, color: Color(0xFFFEF08A), size: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Shiny Gold Button: "JOIN PLATINUM >"
                  InkWell(
                    onTap: _showCheckoutSheet,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFDE68A), Color(0xFFF59E0B), Color(0xFFD97706)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF59E0B).withOpacity(0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'JOIN PLATINUM',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF18181B),
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF18181B)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Arched Top Badge: "UNLIMITED FREE DELIVERIES & MORE"
            Positioned(
              top: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFEF08A), Color(0xFFF59E0B), Color(0xFFCA8A04)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF59E0B).withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  'UNLIMITED FREE DELIVERIES & MORE',
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF18181B),
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // 2. PRIVILEGES / PERKS SECTION (Screen 1 Reference)
        // Benefit 1: Free Delivery
        _buildBenefitTile(
          icon: Icons.two_wheeler_rounded,
          iconBgColor: const Color(0xFF1F2937),
          iconColor: const Color(0xFFFBBF24),
          title: 'Free delivery',
          description:
              'On orders above ₹${plan?.minOrderAmount.toStringAsFixed(0) ?? '99'} from restaurants within ${plan?.deliveryRadiusKm.toStringAsFixed(0) ?? '7'} km. Excludes a few restaurants with self-managed delivery. Surge fee may apply',
        ),
        const SizedBox(height: 16),

        // Benefit 2: Up to 30% extra off
        _buildBenefitTile(
          icon: Icons.confirmation_number_rounded,
          iconBgColor: const Color(0xFF1F2937),
          iconColor: const Color(0xFFF43F5E),
          title: 'Up to 30% extra off',
          description:
              'Above all existing offers at 20,000+ partner restaurants across India',
        ),
        const SizedBox(height: 24),

        // 3. "ON DELIVERY" SECTION (Screen 1 Reference)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'On Delivery',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            InkWell(
              onTap: () {
                if (widget.onOrderFoodPressed != null) widget.onOrderFoodPressed!();
              },
              child: Row(
                children: [
                  Text(
                    'See all',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFF59E0B),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Color(0xFFF59E0B)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 2x2 Grid of Participating Restaurants
        _buildRestaurantGrid(),
        const SizedBox(height: 14),

        // Pill Button: "See all restaurants ->"
        Center(
          child: InkWell(
            onTap: () {
              if (widget.onOrderFoodPressed != null) widget.onOrderFoodPressed!();
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF131823),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'See all restaurants',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // 4. COUPON CODE INPUT SECTION
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF111622),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: Row(
            children: [
              const Icon(Icons.confirmation_number_outlined, color: Color(0xFF94A3B8), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _couponController,
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: _isCouponApplied ? 'Applied: $_appliedCouponCode' : 'Have a coupon code?',
                    hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              InkWell(
                onTap: _applyCoupon,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _isCouponApplied ? const Color(0xFF10B981) : const Color(0xFF1E2638),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Text(
                    _isCouponApplied ? 'Applied' : 'Apply',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _isCouponApplied ? Colors.white : const Color(0xFFFBBF24),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // 5. FOOD-ONLY GUARANTEE CALLOUT
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded, color: Color(0xFF94A3B8), size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'StayDriv Platinum Food Membership applies strictly to StayDriv Food Order Now. Bike rides, auto rides, and taxi fares remain standard.',
                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8), height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _applyCoupon() {
    final code = _couponController.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() {
      _isCouponApplied = true;
      _appliedCouponCode = code;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Coupon "$code" applied! Platinum ₹1 fee active.'),
        backgroundColor: const Color(0xFF10B981),
      ),
    );
  }

  Widget _buildBenefitTile({
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: iconBgColor,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF374151)),
          ),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: const Color(0xFF94A3B8),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRestaurantGrid() {
    final list = _participatingRestaurants.take(4).toList();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: list.length,
      itemBuilder: (ctx, index) {
        final r = list[index];
        final name = r['name'] ?? 'Restaurant';
        final discount = r['extraDiscountPercent'] ?? 10;
        final imageUrl = r['imageUrl'] ?? '';

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF111622),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              // Food Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: imageUrl.isNotEmpty
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            color: const Color(0xFF1E293B),
                            child: const Icon(Icons.restaurant_rounded, color: Color(0xFFF59E0B), size: 22),
                          ),
                        )
                      : Container(
                          color: const Color(0xFF1E293B),
                          child: const Icon(Icons.restaurant_rounded, color: Color(0xFFF59E0B), size: 22),
                        ),
                ),
              ),
              const SizedBox(width: 8),
              // Name & Badge
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Extra $discount% OFF',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFF59E0B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------
  // STICKY BOTTOM FLOATING BAR (SCREEN 1 REFERENCE MATCH)
  // -------------------------------------------------------------
  Widget _buildStickyBottomBar() {
    final plan = _platinumPlan;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14),
        border: const Border(
          top: BorderSide(color: Color(0xFFD97706), width: 1.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // "₹1 for 3 months"
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFFFEF08A), Color(0xFFF59E0B), Color(0xFFD97706)],
                  ).createShader(bounds),
                  child: Text(
                    '₹${plan?.price.toStringAsFixed(0) ?? '1'}',
                    style: GoogleFonts.inter(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'for 3 months',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            // "JOIN PLATINUM >"
            InkWell(
              onTap: _showCheckoutSheet,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFDE68A), Color(0xFFF59E0B), Color(0xFFD97706)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF59E0B).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Text(
                      'JOIN PLATINUM',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF18181B),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Color(0xFF18181B)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // ACTIVE PLATINUM MEMBER VIEW
  // -------------------------------------------------------------
  Widget _buildActivePlatinumView() {
    final m = _activeMembership!;
    final formattedEnd = m.endDate != null
        ? '${m.endDate!.day} ${_monthName(m.endDate!.month)} ${m.endDate!.year}'
        : 'Active';
    final deliverySavings = (m.totalDiscountAvailed * 0.42).round();
    final foodSavings = (m.totalDiscountAvailed - deliverySavings).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Luxury Platinum Active Card
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF0F131D),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
            border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
          ),
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Platinum Emblem
              SizedBox(
                width: 60,
                height: 50,
                child: CustomPaint(painter: _CrownPainter()),
              ),
              const SizedBox(height: 6),
              Text(
                'PLATINUM',
                style: GoogleFonts.cinzel(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFF59E0B),
                  letterSpacing: 3.0,
                ),
              ),
              Text(
                'FOOD MEMBERSHIP',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFFDE68A),
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF10B981)),
                ),
                child: Text(
                  'ACTIVE TILL ${formattedEnd.toUpperCase()}',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF10B981),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'ID: ${m.membershipId}',
                style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 20),

              // SAVINGS TILL NOW
              Text(
                '★  SAVINGS TILL NOW  ★',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFF59E0B),
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),

              // On Delivery savings
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2234),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.two_wheeler_rounded, color: Color(0xFFF59E0B), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'On delivery (${m.ordersCount} orders)',
                        style: GoogleFonts.inter(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '₹$deliverySavings',
                      style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w900, color: const Color(0xFFFBBF24)),
                    ),
                  ],
                ),
              ),

              // On Food Dishes savings
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2234),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.local_offer_rounded, color: Color(0xFF10B981), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'On food dishes',
                        style: GoogleFonts.inter(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '₹$foodSavings',
                      style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w900, color: const Color(0xFF10B981)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // CURRENT PRIVILEGES
              Text(
                '★  CURRENT BENEFITS  ★',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFF59E0B),
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 10),

              _buildActiveBenefitRow(Icons.two_wheeler_rounded, 'Free delivery on orders above ₹99 within 7 km'),
              _buildActiveBenefitRow(Icons.confirmation_number_rounded, 'Up to 30% extra off across 20,000+ partner restaurants'),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Action Buttons Row
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 2,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  if (widget.onOrderFoodPressed != null) {
                    widget.onOrderFoodPressed!();
                  }
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.restaurant_menu_rounded, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Order Food Now',
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF475569)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              ),
              onPressed: _showCheckoutSheet,
              child: Text(
                'Extend Plan',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Participating Partner Restaurants
        Text(
          'Participating Partner Restaurants',
          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
        ),
        const SizedBox(height: 12),
        _buildRestaurantGrid(),
      ],
    );
  }

  Widget _buildActiveBenefitRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFFBBF24), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFCBD5E1), height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  String _monthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return (month >= 1 && month <= 12) ? months[month - 1] : '';
  }
}

// -------------------------------------------------------------
// CUSTOM PAINTERS FOR LUXURY GOLD CROWN & WAVE ACCENTS
// -------------------------------------------------------------
class _CrownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Gradient paint for 3D gold effect
    final crownPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFEF08A), Color(0xFFF59E0B), Color(0xFFB45309)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    // 5-point crown shape matching reference image
    final path = Path();
    path.moveTo(w * 0.05, h * 0.35); // Left outer peak
    path.lineTo(w * 0.25, h * 0.58); // Valley 1
    path.lineTo(w * 0.38, h * 0.18); // Mid-left peak
    path.lineTo(w * 0.50, h * 0.50); // Center valley
    path.lineTo(w * 0.62, h * 0.18); // Mid-right peak
    path.lineTo(w * 0.75, h * 0.58); // Valley 3
    path.lineTo(w * 0.95, h * 0.35); // Right outer peak
    path.lineTo(w * 0.88, h * 0.85); // Bottom right
    path.lineTo(w * 0.12, h * 0.85); // Bottom left
    path.close();

    canvas.drawPath(path, crownPaint);

    // Bottom decorative band
    final bandPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFDE68A), Color(0xFFD97706)],
      ).createShader(Rect.fromLTWH(0, h * 0.82, w, h * 0.14))
      ..style = PaintingStyle.fill;

    final bandRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.10, h * 0.82, w * 0.80, h * 0.12),
      const Radius.circular(3),
    );
    canvas.drawRRect(bandRect, bandPaint);

    // Pearls on peak tips
    final pearlPaint = Paint()..color = const Color(0xFFFFFBEB);
    canvas.drawCircle(Offset(w * 0.05, h * 0.35), w * 0.045, pearlPaint);
    canvas.drawCircle(Offset(w * 0.38, h * 0.18), w * 0.05, pearlPaint);
    canvas.drawCircle(Offset(w * 0.62, h * 0.18), w * 0.05, pearlPaint);
    canvas.drawCircle(Offset(w * 0.95, h * 0.35), w * 0.045, pearlPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GoldWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFEF08A), Color(0xFFF59E0B), Color(0xFFB45309)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(w * 0.2, 0);
    path.quadraticBezierTo(w * 0.1, h * 0.5, w * 0.6, h);
    path.lineTo(w, h);
    path.lineTo(w, 0);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
