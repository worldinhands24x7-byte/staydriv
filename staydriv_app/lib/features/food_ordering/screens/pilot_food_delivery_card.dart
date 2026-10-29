import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/booking_manager.dart';
import '../../../core/call_masking_service.dart';
import '../../../core/js_stub.dart'
    if (dart.library.js) 'dart:js' as js;
import '../../../core/socket_service.dart';
import '../../../core/wake_lock_service.dart';
import '../../dashboard/widgets/console_switcher_sheet.dart';
import '../../navigation/screens/pilot_navigation_screen.dart';
import '../models/food_models.dart';
import '../services/food_service.dart';

class PilotFoodDeliveryCard extends StatefulWidget {
  final String pilotId;
  final String pilotName;
  final String pilotPhone;
  final String vehicleType;
  final bool isOnline;
  final bool autoStartPolling;
  final bool foodServiceEnabled;

  const PilotFoodDeliveryCard({
    super.key,
    required this.pilotId,
    required this.pilotName,
    required this.pilotPhone,
    this.vehicleType = 'Bike',
    required this.isOnline,
    this.autoStartPolling = true,
    this.foodServiceEnabled = true,
  });

  @override
  State<PilotFoodDeliveryCard> createState() => _PilotFoodDeliveryCardState();
}

class _PilotFoodDeliveryCardState extends State<PilotFoodDeliveryCard> {
  final FoodService _foodService = FoodService();
  Timer? _pollTimer;
  Timer? _nativeLoopTimer;
  Timer? _testStopTimer;
  Timer? _countdownTimer;
  int _incomingTaskCountdown = 45;
  bool _isTestingSound = false;

  FoodOrder? _activeDeliveryOrder;
  List<FoodOrder> _availableTasks = [];
  bool _isLoading = false;
  bool _isRinging = false;
  bool _isNavigating = false;

  @visibleForTesting
  List<FoodOrder> get availableTasks => _availableTasks;

  @visibleForTesting
  bool get isRinging => _isRinging;

  @visibleForTesting
  bool get isTestingSound => _isTestingSound;

  @visibleForTesting
  void addAvailableTaskForTest(FoodOrder task) {
    setState(() {
      _availableTasks.add(task);
    });
    _startRingtoneAlert(
      orderId: task.orderId,
      restaurantName: task.restaurantName,
      earnings: task.pilotEarnings > 0 ? task.pilotEarnings : task.deliveryFee,
    );
  }

  @visibleForTesting
  void setActiveDeliveryOrderForTest(FoodOrder? order) {
    setState(() {
      _activeDeliveryOrder = order;
    });
  }

  @visibleForTesting
  FoodOrder? get activeDeliveryOrder => _activeDeliveryOrder;

  @visibleForTesting
  void startRingtoneAlertForTest({String? orderId, String? restaurantName, double? earnings}) {
    _startRingtoneAlert(orderId: orderId, restaurantName: restaurantName, earnings: earnings);
  }

  bool get isBike {
    final v = widget.vehicleType.toLowerCase().trim();
    if (v.contains('auto') ||
        v.contains('rickshaw') ||
        v.contains('car') ||
        v.contains('suv') ||
        v.contains('truck') ||
        v.contains('van') ||
        v.contains('sedan') ||
        v.contains('mini')) {
      return false;
    }
    return v.contains('bike') || v.contains('scoot') || v.contains('moto') || v.contains('2-wheel');
  }

  IconData get vehicleIcon {
    if (isBike) return Icons.two_wheeler_rounded;
    final v = widget.vehicleType.toLowerCase();
    if (v.contains('auto') || v.contains('rickshaw')) return Icons.electric_rickshaw_rounded;
    return Icons.directions_car_rounded;
  }

  @override
  void initState() {
    super.initState();
    if (isBike && widget.autoStartPolling) {
      _startPolling();
      _initSocket();
    }
  }

  void _initSocket() {
    if (!isBike) return;
    try {
      SocketService().initSocket();
      SocketService().joinPilotFood(widget.pilotId);
      SocketService().addFoodDeliveryRequestListener(_onIncomingFoodDeliveryRequest);
      SocketService().addFoodOrderStatusListener(_onFoodOrderStatusUpdate);
    } catch (e) {
      debugPrint('[PilotFoodDeliveryCard] Socket init error: $e');
    }
  }

  /// Starts loud, continuous audio buzzer alert across Web and Native mobile
  void _startRingtoneAlert({String? orderId, String? restaurantName, double? earnings}) {
    if (!isBike) return;
    if (!_isRinging && widget.isOnline) {
      _isRinging = true;
      _incomingTaskCountdown = 45;
      _countdownTimer?.cancel();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _availableTasks.isEmpty) {
          timer.cancel();
          return;
        }
        if (_incomingTaskCountdown > 0) {
          setState(() {
            _incomingTaskCountdown--;
          });
        } else {
          timer.cancel();
          _stopRingtoneAlert();
          setState(() {
            if (_availableTasks.isNotEmpty) {
              _availableTasks.removeAt(0);
            }
          });
        }
      });

      if (kIsWeb) {
        try {
          final summary = 'New food delivery from ${restaurantName ?? "Restaurant"}. Earn ₹${(earnings ?? 40).toStringAsFixed(0)}. Tap to accept!';
          js.context.callMethod('startStayDrivOrderAlarm', [
            1.0,
            orderId ?? 'FOOD_TASK',
            summary,
            '🔔 StayDriv Pilot Console',
          ]);
        } catch (e) {
          debugPrint('[PilotFoodDeliveryCard] Web alarm error: $e');
        }
      } else {
        try {
          WakeLockService.wakeUpScreen();
          WakeLockService.bringAppToForeground();
          HapticFeedback.heavyImpact();
          FlutterRingtonePlayer().play(
            android: AndroidSounds.ringtone,
            ios: IosSounds.electronic,
            looping: true,
            volume: 1.0,
            asAlarm: true,
          ).catchError((_) {});

          // Continuous loop pulse timer for native streams
          _nativeLoopTimer?.cancel();
          _nativeLoopTimer = Timer.periodic(const Duration(milliseconds: 2000), (_) {
            if (_isRinging && mounted) {
              try {
                HapticFeedback.heavyImpact();
                FlutterRingtonePlayer().play(
                  android: AndroidSounds.ringtone,
                  ios: IosSounds.electronic,
                  looping: true,
                  volume: 1.0,
                  asAlarm: true,
                ).catchError((_) {});
              } catch (_) {}
            }
          });
        } catch (e) {
          debugPrint('[PilotFoodDeliveryCard] Native ringtone error: $e');
        }
      }
      if (mounted) setState(() {});
    }
  }

  /// Stops audio buzzer across all platforms
  void _stopRingtoneAlert({bool notify = true}) {
    _isRinging = false;
    _countdownTimer?.cancel();
    _nativeLoopTimer?.cancel();
    _testStopTimer?.cancel();

    if (kIsWeb) {
      try {
        js.context.callMethod('stopStayDrivOrderAlarm');
      } catch (e) {
        debugPrint('[PilotFoodDeliveryCard] Web stop alarm error: $e');
      }
    } else {
      try {
        FlutterRingtonePlayer().stop().catchError((_) {});
      } catch (e) {
        debugPrint('[PilotFoodDeliveryCard] Native stop ringtone error: $e');
      }
    }
    if (notify && mounted) setState(() {});
  }

  /// 4-second Test Buzzer allows pilot to test and confirm sound alert anytime
  void testBuzzer() {
    if (_isTestingSound) {
      _stopRingtoneAlert();
      setState(() => _isTestingSound = false);
      return;
    }

    setState(() => _isTestingSound = true);

    if (kIsWeb) {
      try {
        js.context.callMethod('playStayDrivTestChime', [1.0]);
      } catch (e) {
        debugPrint('[PilotFoodDeliveryCard] Web test chime error: $e');
      }
    } else {
      try {
        HapticFeedback.heavyImpact();
        FlutterRingtonePlayer().play(
          android: AndroidSounds.ringtone,
          ios: IosSounds.electronic,
          looping: true,
          volume: 1.0,
          asAlarm: true,
        ).catchError((_) {});
      } catch (e) {
        debugPrint('[PilotFoodDeliveryCard] Native test sound error: $e');
      }
    }

    _testStopTimer?.cancel();
    _testStopTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isTestingSound) {
        _stopRingtoneAlert();
        setState(() => _isTestingSound = false);
      }
    });
  }

  Future<void> _openNavigation(
    double? lat,
    double? lng,
    String address, {
    String targetName = 'Destination',
    double? originLat,
    double? originLng,
    String? originAddress,
  }) async {
    try {
      double? effLat = lat;
      double? effLng = lng;
      if (effLat != null && effLng != null) {
        if (effLat > 50 && effLng < 40) {
          final temp = effLat;
          effLat = effLng;
          effLng = temp;
        }
      }

      if ((effLat == null || effLat == 0.0) && address.isNotEmpty) {
        final match = RegExp(r'(-?\d{1,2}\.\d+)[,\s]+(-?\d{1,3}\.\d+)').firstMatch(address);
        if (match != null) {
          effLat = double.tryParse(match.group(1) ?? '');
          effLng = double.tryParse(match.group(2) ?? '');
          if (effLat != null && effLng != null && effLat > 50 && effLng < 40) {
            final temp = effLat;
            effLat = effLng;
            effLng = temp;
          }
        }
      }

      double? effOrigLat = originLat;
      double? effOrigLng = originLng;
      if (effOrigLat != null && effOrigLng != null) {
        if (effOrigLat > 50 && effOrigLng < 40) {
          final temp = effOrigLat;
          effOrigLat = effOrigLng;
          effOrigLng = temp;
        }
      }
      if ((effOrigLat == null || effOrigLat == 0.0) && originAddress != null && originAddress.isNotEmpty) {
        final match = RegExp(r'(-?\d{1,2}\.\d+)[,\s]+(-?\d{1,3}\.\d+)').firstMatch(originAddress);
        if (match != null) {
          effOrigLat = double.tryParse(match.group(1) ?? '');
          effOrigLng = double.tryParse(match.group(2) ?? '');
          if (effOrigLat != null && effOrigLng != null && effOrigLat > 50 && effOrigLng < 40) {
            final temp = effOrigLat;
            effOrigLat = effOrigLng;
            effOrigLng = temp;
          }
        }
      }

      if (effLat != null && effLng != null && effLat != 0.0 && effLng != 0.0) {
        // Use mode=d (driving) for road turn-by-turn navigation with live road traffic.
        final googleNavUri = Uri.parse('google.navigation:q=$effLat,$effLng&mode=d');

        String originParam = '';
        if (effOrigLat != null && effOrigLng != null && effOrigLat != 0.0 && effOrigLng != 0.0) {
          originParam = '&origin=$effOrigLat,$effOrigLng';
        } else if (originAddress != null && originAddress.trim().isNotEmpty) {
          originParam = '&origin=${Uri.encodeComponent(originAddress.trim())}';
        }

        final webMapUri = Uri.parse('https://www.google.com/maps/dir/?api=1$originParam&destination=$effLat,$effLng&travelmode=driving');

        if (await canLaunchUrl(googleNavUri)) {
          await launchUrl(googleNavUri);
          return;
        }
        await launchUrl(webMapUri, mode: LaunchMode.externalApplication);
      } else if (address.trim().isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ Exact GPS coordinates missing for $targetName. Navigating using street address.'),
              backgroundColor: const Color(0xFFF59E0B),
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: () => _checkAvailableOrders(),
              ),
            ),
          );
        }
        String originParam = '';
        if (effOrigLat != null && effOrigLng != null && effOrigLat != 0.0 && effOrigLng != 0.0) {
          originParam = '&origin=$effOrigLat,$effOrigLng';
        } else if (originAddress != null && originAddress.trim().isNotEmpty) {
          originParam = '&origin=${Uri.encodeComponent(originAddress.trim())}';
        }

        final webDirUri = Uri.parse('https://www.google.com/maps/dir/?api=1$originParam&destination=${Uri.encodeComponent(address)}&travelmode=driving');
        await launchUrl(webDirUri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Cannot navigate: $targetName has no valid GPS coordinates or address.'),
              backgroundColor: const Color(0xFFDC2626),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[PilotFoodDeliveryCard] Navigation launch error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Navigation error: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  Future<void> _callCustomer(FoodOrder order) async {
    await CallMaskingService().callFoodOrder(
      orderId: order.orderId,
      callerRole: 'pilot',
      targetRole: 'customer',
      contactName: order.customerName.isNotEmpty ? order.customerName : 'Customer',
      context: context,
    );
  }

  Future<void> _callRestaurant(FoodOrder order) async {
    await CallMaskingService().callFoodOrder(
      orderId: order.orderId,
      callerRole: 'pilot',
      targetRole: 'restaurant',
      contactName: order.restaurantName.isNotEmpty ? order.restaurantName : 'Restaurant',
      context: context,
    );
  }

  void _onIncomingFoodDeliveryRequest(Map<String, dynamic> data) {
    if (!mounted || !widget.isOnline || !isBike || !widget.foodServiceEnabled) return;
    try {
      final order = FoodOrder.fromJson(data);
      final pilotPhoneDigits = widget.pilotPhone.replaceAll(RegExp(r'\D'), '');
      final last10 = pilotPhoneDigits.length >= 10 ? pilotPhoneDigits.substring(pilotPhoneDigits.length - 10) : pilotPhoneDigits;
      final isRelevant = order.deliveryPartnerId.isEmpty ||
          order.deliveryPartnerId == widget.pilotId ||
          (last10.isNotEmpty && order.deliveryPartnerId.contains(last10)) ||
          order.deliveryPartnerPhone == widget.pilotPhone;

      // Real accepted orders only — never unaccepted ('placed') orders
      final isEligibleStatus = order.orderStatus == 'accepted' || order.orderStatus == 'preparing' || order.orderStatus == 'ready_for_pickup';

      if (isRelevant && (isEligibleStatus || order.deliveryPartnerId.isNotEmpty)) {
        setState(() {
          final exists = _availableTasks.any((t) => t.orderId == order.orderId);
          if (!exists) {
            _availableTasks.insert(0, order);
          }
        });

        // Trigger continuous audible ringtone alert for pilot
        _startRingtoneAlert(
          orderId: order.orderId,
          restaurantName: order.restaurantName,
          earnings: order.pilotEarnings > 0 ? order.pilotEarnings : order.deliveryFee,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(vehicleIcon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('NEW FOOD DELIVERY: ${order.restaurantName} (₹${order.deliveryFee.toStringAsFixed(0)})'),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      debugPrint('[PilotFoodDeliveryCard] Parse error: $e');
    }
  }

  void _onFoodOrderStatusUpdate(Map<String, dynamic> data) {
    if (!mounted) return;
    try {
      final order = FoodOrder.fromJson(data);
      if (_activeDeliveryOrder != null && _activeDeliveryOrder!.orderId == order.orderId) {
        if (order.orderStatus == 'delivered' || order.orderStatus == 'cancelled' || order.orderStatus == 'returned_to_restaurant') {
          setState(() {
            _activeDeliveryOrder = null;
          });
          _stopRingtoneAlert();
        } else {
          final wasReady = _activeDeliveryOrder!.orderStatus == 'ready_for_pickup';
          final isNowReady = order.orderStatus == 'ready_for_pickup';
          setState(() {
            _activeDeliveryOrder = order;
          });
          // Alert pilot when restaurant partner marks order ready for pickup
          if (isNowReady && !wasReady) {
            _playReadyNotificationAlert(order);
          }
        }
      }
    } catch (_) {}
    _checkAvailableOrders();
  }

  /// Alert pilot with sound/vibration and banner when restaurant marks order ready for pickup
  void _playReadyNotificationAlert(FoodOrder order) {
    if (!mounted) return;
    try {
      HapticFeedback.heavyImpact();
      if (kIsWeb) {
        try {
          js.context.callMethod('playStayDrivTestChime', [1.0]);
        } catch (_) {}
      } else {
        try {
          FlutterRingtonePlayer().play(
            android: AndroidSounds.notification,
            ios: IosSounds.glass,
            volume: 1.0,
          ).catchError((_) {});
        } catch (_) {}
      }
    } catch (_) {}

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '🍱 Order #${order.orderId} is Ready for Pickup at ${order.restaurantName}!',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Confirm Pickup',
          textColor: Colors.white,
          onPressed: () => _markPickedUp(order),
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant PilotFoodDeliveryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOnline != oldWidget.isOnline) {
      if (widget.isOnline) {
        if (widget.foodServiceEnabled) {
          _checkAvailableOrders();
        }
      } else {
        _stopRingtoneAlert();
        setState(() {
          _availableTasks = [];
        });
      }
    }
    if (oldWidget.foodServiceEnabled && !widget.foodServiceEnabled) {
      _stopRingtoneAlert();
      setState(() {
        _availableTasks = [];
      });
    } else if (!oldWidget.foodServiceEnabled && widget.foodServiceEnabled && widget.isOnline) {
      _checkAvailableOrders();
    }
  }

  @override
  void dispose() {
    _stopRingtoneAlert(notify: false);
    _pollTimer?.cancel();
    _nativeLoopTimer?.cancel();
    _testStopTimer?.cancel();
    _countdownTimer?.cancel();
    SocketService().removeFoodDeliveryRequestListener(_onIncomingFoodDeliveryRequest);
    SocketService().removeFoodOrderStatusListener(_onFoodOrderStatusUpdate);
    super.dispose();
  }

  void _startPolling() {
    if (!isBike) return;
    _checkAvailableOrders();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (widget.isOnline && mounted && isBike) {
        _checkAvailableOrders();
      }
    });
  }

  Future<void> _checkAvailableOrders() async {
    if (!widget.isOnline || !isBike) return;
    try {
      final orders = await _foodService.fetchPilotAvailableOrders(
        pilotId: widget.pilotId,
        vehicleType: widget.vehicleType,
      );
      if (!mounted) return;

      FoodOrder? activeOrder;
      final waitingTasks = <FoodOrder>[];

      final pilotPhoneDigits = widget.pilotPhone.replaceAll(RegExp(r'\D'), '');
      final last10Phone = pilotPhoneDigits.length >= 10 ? pilotPhoneDigits.substring(pilotPhoneDigits.length - 10) : pilotPhoneDigits;

      for (var o in orders) {
        final isMyOrder = (o.deliveryPartnerId.isNotEmpty &&
                (o.deliveryPartnerId == widget.pilotId ||
                 (last10Phone.isNotEmpty && o.deliveryPartnerId.contains(last10Phone)))) ||
            (o.deliveryPartnerPhone.isNotEmpty &&
                (o.deliveryPartnerPhone == widget.pilotPhone ||
                 (last10Phone.isNotEmpty && o.deliveryPartnerPhone.replaceAll(RegExp(r'\D'), '').endsWith(last10Phone))));

        if (isMyOrder &&
            o.orderStatus != 'delivered' &&
            o.orderStatus != 'cancelled' &&
            o.orderStatus != 'returned_to_restaurant') {
          activeOrder = o;
        } else if (o.deliveryPartnerId.isEmpty &&
                   (o.orderStatus == 'accepted' || o.orderStatus == 'preparing' || o.orderStatus == 'ready_for_pickup')) {
          waitingTasks.add(o);
        }
      }

      setState(() {
        if (activeOrder != null) {
          _activeDeliveryOrder = activeOrder;
        }
        _availableTasks = waitingTasks;
      });

      // Ringing alert if available tasks exist and no active delivery
      if (waitingTasks.isNotEmpty && _activeDeliveryOrder == null) {
        final firstTask = waitingTasks.first;
        _startRingtoneAlert(
          orderId: firstTask.orderId,
          restaurantName: firstTask.restaurantName,
          earnings: firstTask.pilotEarnings > 0 ? firstTask.pilotEarnings : firstTask.deliveryFee,
        );
      } else if (waitingTasks.isEmpty) {
        _stopRingtoneAlert();
      }
    } catch (_) {}
  }

  Future<void> _acceptOrder(FoodOrder order) async {
    _stopRingtoneAlert();
    setState(() => _isLoading = true);
    final success = await _foodService.pilotAcceptOrder(
      order.orderId,
      widget.pilotId,
      widget.pilotName,
      widget.pilotPhone,
    );

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (success) {
        _activeDeliveryOrder = order;
        _availableTasks.removeWhere((o) => o.orderId == order.orderId);
      }
    });

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delivery Task Accepted: ${order.orderId}. Ready for restaurant pickup.'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: 'Navigate',
            textColor: Colors.white,
            onPressed: () => _navigateToRestaurantPickup(order),
          ),
          duration: const Duration(seconds: 4),
        ),
      );

      // Manual navigation only: Keep pilot on Order Details screen. Do not launch navigation automatically.
    }
  }

  void _startInAppNavigation(FoodOrder order, {required bool toCustomer}) {
    if (_isNavigating || !mounted) return;
    _isNavigating = true;
    final bookingMap = <String, dynamic>{
      'bookingId': order.orderId,
      'orderId': order.orderId,
      'serviceType': 'food',
      'vehicle': 'Food Delivery',
      'vehicleType': 'Food Delivery',
      'pickup': order.restaurantAddress,
      'pickupLocationName': order.restaurantName,
      'restaurantName': order.restaurantName,
      'restaurantAddress': order.restaurantAddress,
      'pickupLatLng': {'lat': order.restaurantLat, 'lng': order.restaurantLng},
      'restaurantLatLng': {'lat': order.restaurantLat, 'lng': order.restaurantLng},
      'restaurantLat': order.restaurantLat,
      'restaurantLng': order.restaurantLng,
      'drop': order.deliveryAddress,
      'dropLocationName': order.customerName,
      'customerName': order.customerName,
      'deliveryAddress': order.deliveryAddress,
      'deliveryInstructions': order.deliveryInstructions,
      'dropLatLng': {'lat': order.deliveryLat, 'lng': order.deliveryLng},
      'deliveryLatLng': {'lat': order.deliveryLat, 'lng': order.deliveryLng},
      'deliveryLat': order.deliveryLat,
      'deliveryLng': order.deliveryLng,
      'status': toCustomer ? 'heading_to_drop' : 'heading_to_pickup',
      'isFoodOrder': true,
      'customerPhone': order.customerPhone,
      'passengerPhone': order.customerPhone,
      'restaurantPhone': order.restaurantPhone,
    };

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PilotNavigationScreen(
          booking: bookingMap,
          onRideCompleted: () {
            _checkAvailableOrders();
          },
        ),
      ),
    ).then((_) {
      if (mounted) {
        setState(() {
          _isNavigating = false;
        });
      } else {
        _isNavigating = false;
      }
    });
  }

  Future<void> _navigateToRestaurantPickup(FoodOrder order) async {
    final rLat = order.restaurantLat;
    final rLng = order.restaurantLng;

    if (rLat == null || rLng == null || rLat.isNaN || rLng.isNaN || (rLat == 0.0 && rLng == 0.0)) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF0F172A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFEF4444)),
            ),
            title: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Restaurant Location Not Set',
                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
            content: Text(
              '${order.restaurantName} has not configured their exact map pin coordinates in their Restaurant Partner Console.\n\nPlease call the restaurant to ask them to set their location pin in Store Profile.',
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK', style: TextStyle(color: Colors.white70)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _callRestaurant(order);
                },
                icon: const Icon(Icons.phone, size: 14, color: Colors.white),
                label: const Text('Call Restaurant', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      }
      return;
    }

    _startInAppNavigation(order, toCustomer: false);
  }

  Future<void> _markPickedUp(FoodOrder order) async {
    setState(() => _isLoading = true);
    final success = await _foodService.pilotPickupOrder(order.orderId, widget.pilotId);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Order Picked Up! Ready for delivery to customer.'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: 'Navigate',
            textColor: Colors.white,
            onPressed: () => _navigateToCustomerLocation(order),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
      setState(() {
        if (_activeDeliveryOrder != null && _activeDeliveryOrder!.orderId == order.orderId) {
          _activeDeliveryOrder = _activeDeliveryOrder!.copyWith(orderStatus: 'out_for_delivery');
        }
      });
      _checkAvailableOrders();

      // Manual navigation only: Keep pilot on Order Details screen. Do not launch navigation automatically.
    }
  }

  /// Launch map navigation directly to customer drop location from pilot's current GPS position
  Future<void> _navigateToCustomerLocation(FoodOrder order) async {
    final dLat = order.deliveryLat;
    final dLng = order.deliveryLng;

    if (dLat == null || dLng == null || dLat.isNaN || dLng.isNaN || (dLat == 0.0 && dLng == 0.0)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Customer delivery pin is not set for order ${order.orderId}. Please contact customer.'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
      return;
    }

    _startInAppNavigation(order, toCustomer: true);
  }

  // Complete delivery with customer OTP
  void _showCompleteDeliveryOtpDialog(FoodOrder order) {
    final otpController = TextEditingController();
    String error = '';
    bool isVerifying = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.verified_user_rounded, color: Colors.green),
                  const SizedBox(width: 8),
                  Text('Verify Delivery OTP', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ask the customer for the 4-digit Delivery Verification OTP to confirm handover:',
                    style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.robotoMono(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 8),
                    decoration: InputDecoration(
                      hintText: '• • • •',
                      errorText: error.isNotEmpty ? error : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isVerifying ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  onPressed: isVerifying
                      ? null
                      : () async {
                          final otp = otpController.text.trim();
                          if (otp.length != 4) {
                            setDlgState(() => error = 'Please enter 4-digit OTP');
                            return;
                          }
                          setDlgState(() {
                            isVerifying = true;
                            error = '';
                          });

                          final res = await _foodService.pilotDeliverOrder(order.orderId, widget.pilotId, otp);
                          if (!mounted) return;

                          if (res['success'] == true) {
                            if (ctx.mounted) Navigator.pop(ctx);
                            setState(() {
                              _activeDeliveryOrder = null;
                            });
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Delivery Completed Successfully! Earning added to wallet.'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } else {
                            setDlgState(() {
                              isVerifying = false;
                              error = res['message'] ?? 'Invalid OTP. Handover could not be verified.';
                            });
                          }
                        },
                  child: isVerifying
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Verify & Finish', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Confirmation dialog required:
  // Title: Delivery Failed
  // Message: The customer has not received the order. Do you want to return the food to the restaurant?
  // Buttons: Cancel, Confirm Return
  void _showFailedDeliveryConfirmationDialog(FoodOrder order) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.report_problem_rounded, color: Color(0xFFEF4444), size: 24),
              const SizedBox(width: 8),
              Text(
                'Delivery Failed',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: Text(
            'The customer has not received the order. Do you want to return the food to the restaurant?',
            style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF334155), height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _showSelectFailureReasonSheet(order);
              },
              child: Text(
                'Confirm Return',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  // Failed delivery reason selection & return submission
  void _showSelectFailureReasonSheet(FoodOrder order) {
    final reasons = [
      'Customer is not answering calls',
      'Customer is unavailable at the delivery location',
      'Customer refused to accept the order',
      'Customer provided an incorrect address',
      'Customer requested cancellation after dispatch',
      'Customer cannot be contacted after the permitted waiting period',
      'Safety issue at the delivery location',
      'Other (enter mandatory explanation)',
    ];

    String selectedReason = reasons.first;
    final notesController = TextEditingController();
    bool isSubmitting = false;
    String error = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 18,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Unable to Deliver Order',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Report failed delivery & start safe return to restaurant',
                                style: GoogleFonts.inter(color: Colors.white60, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Order summary card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Order ID: ${order.orderId}',
                                style: GoogleFonts.robotoMono(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '₹${order.totalAmount.toStringAsFixed(0)}',
                                style: GoogleFonts.outfit(color: const Color(0xFFF59E0B), fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white10, height: 14),
                          Text(
                            '🏪 Restaurant: ${order.restaurantName}',
                            style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '📍 Return to: ${order.restaurantAddress.isNotEmpty ? order.restaurantAddress : 'Restaurant kitchen'}',
                            style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '👤 Customer: ${order.customerName} (Masked)',
                            style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Mandatory reason dropdown
                    Text(
                      'MANDATORY REASON *',
                      style: GoogleFonts.inter(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedReason,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1E293B),
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                          items: reasons.map((r) {
                            return DropdownMenuItem<String>(
                              value: r,
                              child: Text(
                                r,
                                style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setSheetState(() {
                                selectedReason = val;
                                error = '';
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Explanation notes
                    Text(
                      selectedReason.startsWith('Other') ? 'EXPLANATION NOTES (MANDATORY) *' : 'ADDITIONAL NOTES (OPTIONAL)',
                      style: GoogleFonts.inter(
                        color: selectedReason.startsWith('Other') ? const Color(0xFFF87171) : Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: notesController,
                      maxLines: 2,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: selectedReason.startsWith('Other')
                            ? 'Please provide detailed reason for non-delivery...'
                            : 'Any context about the customer or location...',
                        hintStyle: GoogleFonts.inter(color: Colors.white30, fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.white24)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF3B82F6))),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Notice alert box
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Color(0xFFF59E0B), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Food package MUST be returned safely to the restaurant within 45 minutes. The restaurant staff will inspect the food and provide a 4-digit Return Verification OTP to close this order.',
                              style: GoogleFonts.inter(color: const Color(0xFFFDE68A), fontSize: 11.5, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (error.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(error, style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12)),
                    ],

                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white24),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFDC2626),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    final notes = notesController.text.trim();
                                    if (selectedReason.startsWith('Other') && notes.isEmpty) {
                                      setSheetState(() => error = 'Please enter explanation notes');
                                      return;
                                    }

                                    setSheetState(() {
                                      isSubmitting = true;
                                      error = '';
                                    });

                                    final effectivePilotId = order.deliveryPartnerId.isNotEmpty ? order.deliveryPartnerId : widget.pilotId;
                                    final effectivePilotPhone = widget.pilotPhone.isNotEmpty ? widget.pilotPhone : widget.pilotId;

                                    final res = await _foodService.reportFailedDelivery(
                                      orderId: order.orderId,
                                      pilotId: effectivePilotId,
                                      pilotPhone: effectivePilotPhone,
                                      reason: selectedReason,
                                      notes: notes,
                                    );

                                    if (!mounted) return;

                                    if (res['success'] == true) {
                                      if (ctx.mounted) Navigator.pop(ctx);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Failed delivery reported. Please return food to the restaurant.'),
                                            backgroundColor: Color(0xFFF59E0B),
                                            duration: Duration(seconds: 4),
                                          ),
                                        );
                                        _checkAvailableOrders();
                                        // Manual navigation only: Keep pilot on Order Details screen without auto-opening navigation.
                                      }
                                    } else {
                                      setSheetState(() {
                                        isSubmitting = false;
                                        error = res['message'] ?? 'Failed to report. Please try again.';
                                      });
                                    }
                                  },
                            child: isSubmitting
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : Text(
                                    'Confirm & Return to Restaurant',
                                    style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                          ),
                        ),
                      ],
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

  // Dialog for pilot to verify restaurant return OTP
  void _showVerifyReturnOtpDialog(FoodOrder order) {
    final otpController = TextEditingController();
    String error = '';
    bool isVerifying = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.inventory_2_rounded, color: Color(0xFF10B981)),
                  const SizedBox(width: 8),
                  Text('Restaurant Return OTP', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Order ID: ${order.orderId}', style: GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                        const SizedBox(height: 2),
                        Text('Restaurant: ${order.restaurantName}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF475569))),
                        if (order.restaurantAddress.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text('Return Address: ${order.restaurantAddress}', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                        ],
                        if (order.returnReason.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text('Return Reason: ${order.returnReason}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFFDC2626))),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Hand over the returned food package to ${order.restaurantName} kitchen staff, and enter the 4-digit Return Verification OTP they provide:',
                    style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.robotoMono(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 8),
                    decoration: InputDecoration(
                      hintText: '• • • •',
                      errorText: error.isNotEmpty ? error : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isVerifying ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                  onPressed: isVerifying
                      ? null
                      : () async {
                          final otp = otpController.text.trim();
                          if (otp.length != 4) {
                            setDlgState(() => error = 'Please enter 4-digit Return OTP');
                            return;
                          }
                          setDlgState(() {
                            isVerifying = true;
                            error = '';
                          });

                          final effectivePilotId = order.deliveryPartnerId.isNotEmpty ? order.deliveryPartnerId : widget.pilotId;
                          final effectivePilotPhone = widget.pilotPhone.isNotEmpty ? widget.pilotPhone : widget.pilotId;

                          final res = await _foodService.verifyReturnOtp(
                            orderId: order.orderId,
                            pilotId: effectivePilotId,
                            pilotPhone: effectivePilotPhone,
                            otp: otp,
                          );
                          if (!mounted) return;

                          if (res['success'] == true) {
                            if (ctx.mounted) Navigator.pop(ctx);
                            setState(() {
                              _activeDeliveryOrder = null;
                            });
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Return Verified & Completed! Food package accepted by restaurant.'),
                                  backgroundColor: Color(0xFF10B981),
                                ),
                              );
                            }
                            _checkAvailableOrders();
                          } else {
                            setDlgState(() {
                              isVerifying = false;
                              error = res['message'] ?? 'Invalid or expired Return OTP. Please verify code with restaurant staff.';
                            });
                          }
                        },
                  child: isVerifying
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Verify OTP & Complete Return', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOnline || !isBike) return const SizedBox.shrink();

    // 1. If pilot has an active delivery task
    if (_activeDeliveryOrder != null) {
      final order = _activeDeliveryOrder!;
      final isReturning = order.isReturnActive;
      final isPickedUp = order.orderStatus == 'picked_up' || order.orderStatus == 'out_for_delivery' || order.orderStatus == 'arrived_at_customer';

      return Container(
        margin: const EdgeInsets.only(top: 10, bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isReturning ? const Color(0xFFEF4444) : const Color(0xFFF59E0B),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card Header
            Row(
              children: [
                Icon(
                  isReturning ? Icons.keyboard_return_rounded : vehicleIcon,
                  color: isReturning ? const Color(0xFFEF4444) : const Color(0xFFF59E0B),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isReturning ? 'Return to Restaurant: ${order.orderId}' : 'Active Food Delivery: ${order.orderId}',
                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.hub_outlined, color: Colors.white70, size: 19),
                          tooltip: 'Switch Console (Customer, Pilot, Restaurant, Admin)',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => ConsoleSwitcherSheet.show(
                            context,
                            currentRole: 'Driver',
                            userPhone: widget.pilotPhone,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isReturning ? const Color(0xFFEF4444).withOpacity(0.2) : const Color(0xFFF59E0B).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isReturning
                                ? 'RETURNING'
                                : '₹${(order.pilotEarnings > 0 ? order.pilotEarnings : (order.originalDeliveryFee > 0 ? order.originalDeliveryFee : order.deliveryFee)).toStringAsFixed(0)} EARN',
                            style: GoogleFonts.robotoMono(
                              color: isReturning ? const Color(0xFFF87171) : const Color(0xFFF59E0B),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (order.isPlatinumDelivery)
                      Padding(
                        padding: const EdgeInsets.only(top: 2.0),
                        child: Text(
                          '👑 StayDriv Funded',
                          style: GoogleFonts.inter(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF38BDF8),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Order details
            Text(
              'Restaurant: ${order.restaurantName}',
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
            ),
            if (isReturning) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.assignment_return_rounded, color: Color(0xFFF87171), size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'RETURNING TO RESTAURANT',
                          style: GoogleFonts.inter(color: const Color(0xFFFCA5A5), fontSize: 11.5, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '🏪 Return to: ${order.restaurantName}',
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Address: ${order.restaurantAddress}',
                      style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
                    ),
                    if (order.restaurantLat != null && order.restaurantLng != null && order.restaurantLat != 0.0)
                      Text(
                        'Target GPS: ${order.restaurantLat!.toStringAsFixed(5)}, ${order.restaurantLng!.toStringAsFixed(5)}',
                        style: GoogleFonts.robotoMono(color: const Color(0xFFFCA5A5), fontSize: 10.5, fontWeight: FontWeight.w600),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      '⚠️ Reason: ${order.returnReason}',
                      style: GoogleFonts.inter(color: const Color(0xFFFCA5A5), fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                    if (order.returnDeadline != null)
                      Text(
                        'Return Deadline: ${order.returnDeadline!.hour}:${order.returnDeadline!.minute.toString().padLeft(2, '0')}',
                        style: GoogleFonts.inter(color: Colors.white60, fontSize: 11),
                      ),
                  ],
                ),
              ),
            ] else ...[
              // Customer Drop Preview with GPS Coordinates
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person_pin_circle_rounded, color: Color(0xFFF59E0B), size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Customer: ${order.customerName}',
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '📍 Delivery Drop: ${order.deliveryAddress}',
                      style: GoogleFonts.inter(color: Colors.white70, fontSize: 11.5),
                    ),
                    if (order.deliveryLat != null && order.deliveryLng != null && order.deliveryLat != 0.0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2.0),
                        child: Text(
                          'Target GPS: ${order.deliveryLat!.toStringAsFixed(5)}, ${order.deliveryLng!.toStringAsFixed(5)}',
                          style: GoogleFonts.robotoMono(color: const Color(0xFF60A5FA), fontSize: 10.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 6),

            // Calling Buttons: Call Customer & Call Restaurant
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF34D399),
                      side: const BorderSide(color: Color(0xFF10B981), width: 1),
                      backgroundColor: const Color(0xFF10B981).withOpacity(0.12),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _callCustomer(order),
                    icon: const Icon(Icons.phone_in_talk_rounded, size: 14, color: Color(0xFF34D399)),
                    label: Text(
                      'Call Customer',
                      style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF93C5FD),
                      side: const BorderSide(color: Color(0xFF3B82F6), width: 1),
                      backgroundColor: const Color(0xFF3B82F6).withOpacity(0.12),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _callRestaurant(order),
                    icon: const Icon(Icons.storefront_rounded, size: 14, color: Color(0xFF60A5FA)),
                    label: Text(
                      'Call Restaurant',
                      style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Ready for Pickup Notification Banner
            if (order.orderStatus == 'ready_for_pickup') ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF10B981), width: 1.2),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Color(0xFF34D399), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'FOOD READY FOR PICKUP!',
                            style: GoogleFonts.inter(
                              color: const Color(0xFFA7F3D0),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '${order.restaurantName} has packed the food. Go to kitchen counter & tap Confirm Pickup.',
                            style: GoogleFonts.inter(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Navigation Button
            InkWell(
              onTap: () {
                if (isReturning) {
                  _openNavigation(
                    order.restaurantLat,
                    order.restaurantLng,
                    order.restaurantAddress,
                    targetName: 'Restaurant Return (${order.restaurantName})',
                    originLat: order.deliveryLat,
                    originLng: order.deliveryLng,
                    originAddress: order.deliveryAddress,
                  );
                } else {
                  _navigateToRestaurantPickup(order);
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                decoration: BoxDecoration(
                  color: isReturning ? const Color(0xFFDC2626).withOpacity(0.18) : const Color(0xFF2563EB).withOpacity(0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isReturning ? const Color(0xFFEF4444).withOpacity(0.4) : const Color(0xFF3B82F6).withOpacity(0.4),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isReturning ? Icons.keyboard_return_rounded : Icons.navigation_rounded,
                      color: isReturning ? const Color(0xFFFCA5A5) : const Color(0xFF60A5FA),
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        isReturning
                            ? 'Navigate to Restaurant for Return (${isBike ? 'Bike' : 'Drive'})'
                            : 'Navigate to Restaurant Pickup',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: isReturning ? const Color(0xFFFCA5A5) : const Color(0xFF93C5FD),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Action Buttons
            if (isReturning) ...[
              // Dedicated Return Handover Card
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF10B981).withOpacity(0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.inventory_2_rounded, size: 16, color: Color(0xFF34D399)),
                        const SizedBox(width: 6),
                        Text(
                          'Restaurant Return Handover',
                          style: GoogleFonts.inter(color: const Color(0xFFA7F3D0), fontWeight: FontWeight.w800, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Hand over food package to ${order.restaurantName} staff. Enter the 4-digit Return Verification OTP provided by restaurant:',
                      style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _showVerifyReturnOtpDialog(order),
                        icon: const Icon(Icons.verified_user_rounded, size: 16, color: Colors.white),
                        label: const Text(
                          'Enter Restaurant Return OTP',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Standard delivery actions:
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onPressed: isPickedUp ? null : () => _markPickedUp(order),
                      child: Text(
                        isPickedUp ? 'Picked Up ✓' : 'Confirm Pickup',
                        style: TextStyle(fontSize: 12, color: isPickedUp ? Colors.white38 : Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onPressed: () => _showCompleteDeliveryOtpDialog(order),
                      child: const Text('Complete (OTP)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                ],
              ),

              // Dedicated "Navigate to Customer Location" button (matching Navigate to Restaurant Pickup button)
              const SizedBox(height: 10),
              InkWell(
                onTap: () => _navigateToCustomerLocation(order),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF3B82F6).withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.navigation_rounded,
                        color: Color(0xFF60A5FA),
                        size: 15,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Navigate to Customer Location',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: const Color(0xFF93C5FD),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Failed Delivery / Return to Restaurant Button (active once food picked up)
              if (isPickedUp) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: const Color(0xFF991B1B).withOpacity(0.55),
                      side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 2,
                    ),
                    onPressed: () => _showFailedDeliveryConfirmationDialog(order),
                    icon: const Icon(Icons.report_problem_rounded, size: 16, color: Color(0xFFFCA5A5)),
                    label: Text(
                      'Delivery Failed / Return to Restaurant',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 12.5, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ],
        ),
      );
    }

    // 2. If available food delivery orders are waiting (and food service is enabled)
    if (widget.foodServiceEnabled && _availableTasks.isNotEmpty) {
      final task = _availableTasks.first;
      return Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // High-Visibility Audio Alert Banner & Mute Action
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: _isRinging ? const Color(0xFF450A0A) : const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _isRinging ? const Color(0xFFEF4444) : const Color(0xFF334155),
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isRinging ? Icons.notifications_active_rounded : Icons.notifications_off_outlined,
                    color: _isRinging ? const Color(0xFFFCA5A5) : Colors.white60,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isRinging
                          ? '🚨 LOUD BUZZER RINGING'
                          : '🔔 Food Delivery Alert (Muted)',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _isRinging ? const Color(0xFF991B1B) : Colors.white12,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '⏱️ ${_incomingTaskCountdown}s',
                      style: GoogleFonts.robotoMono(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () {
                      if (_isRinging) {
                        _stopRingtoneAlert();
                      } else {
                        _startRingtoneAlert(
                          orderId: task.orderId,
                          restaurantName: task.restaurantName,
                          earnings: task.pilotEarnings > 0 ? task.pilotEarnings : task.deliveryFee,
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _isRinging ? 'Mute 🔕' : 'Unmute 🔔',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(vehicleIcon, color: const Color(0xFF10B981), size: 20),
                    const SizedBox(width: 6),
                    Text(
                      'Food Delivery Available',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '₹${(task.pilotEarnings > 0 ? task.pilotEarnings : (task.originalDeliveryFee > 0 ? task.originalDeliveryFee : task.deliveryFee)).toStringAsFixed(0)} EARN',
                        style: GoogleFonts.robotoMono(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    if (task.isPlatinumDelivery)
                      Padding(
                        padding: const EdgeInsets.only(top: 2.0),
                        child: Text(
                          '👑 StayDriv Funded',
                          style: GoogleFonts.inter(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF38BDF8),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${task.restaurantName} • ${task.items.length} items',
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
            ),
            Text(
              'Drop: ${task.deliveryAddress}',
              style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white60,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    onPressed: () {
                      _stopRingtoneAlert();
                      setState(() {
                        _availableTasks.removeAt(0);
                      });
                    },
                    child: const Text('Pass', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                    onPressed: _isLoading ? null : () => _acceptOrder(task),
                    child: _isLoading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Accept Delivery', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // 3. Idle / Listening status
    final bool isPaused = !widget.foodServiceEnabled;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isPaused ? const Color(0xFFF1F5F9) : const Color(0xFF10B981).withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPaused ? const Color(0xFFCBD5E1) : const Color(0xFF10B981).withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isPaused ? Icons.pause_circle_filled_rounded : vehicleIcon,
            size: 16,
            color: isPaused ? const Color(0xFF64748B) : const Color(0xFF10B981),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isPaused ? 'Food Delivery: Paused' : 'Food Delivery: Ready & Listening',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isPaused ? const Color(0xFF334155) : const Color(0xFF059669),
                  ),
                ),
                Text(
                  isPaused
                      ? 'Food delivery is paused in Service Preferences above'
                      : 'Loud buzzer alert will ring automatically on incoming orders',
                  style: GoogleFonts.inter(
                    fontSize: 9.5,
                    color: isPaused ? const Color(0xFF64748B) : const Color(0xFF15803D),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          if (isPaused)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'PAUSED',
                style: GoogleFonts.robotoMono(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF475569),
                ),
              ),
            )
          else
            // Test Buzzer Button
            InkWell(
              onTap: testBuzzer,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _isTestingSound ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _isTestingSound ? const Color(0xFFF87171) : const Color(0xFF86EFAC),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isTestingSound ? Icons.volume_up_rounded : Icons.notifications_active_outlined,
                      size: 13,
                      color: _isTestingSound ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isTestingSound ? 'Buzzer Playing...' : 'Test Buzzer',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: _isTestingSound ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
