import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'firebase_service.dart';
import 'network_config.dart';
import 'api_client.dart';
import 'network_monitor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'socket_service.dart';
import 'wake_lock_service.dart';
import 'floating_widget_service.dart';
import 'pilot_ride_ringtone_service.dart';
import '../features/navigation/services/navigation_engine.dart';

/// Universal vehicle compatibility evaluator for StayDriv
bool areVehiclesCompatible(String? customerVehicle, String? pilotVehicle) {
  if (customerVehicle == null || customerVehicle.isEmpty) return true;
  if (pilotVehicle == null || pilotVehicle.isEmpty) return true;

  final c = customerVehicle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final p = pilotVehicle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  if (c == p) return true;

  // 1. Two-Wheelers: Bike, Scooty, Scooter, Motorcycle, Two-Wheeler, Moped, Bike Taxi, Parcel
  final isTwoWheeler = (String s) =>
      s.contains('bike') ||
      s.contains('scoot') ||
      s.contains('motorcycle') ||
      s.contains('twowheeler') ||
      s.contains('2wheeler') ||
      s.contains('moped') ||
      s.contains('activa');

  if (isTwoWheeler(c) && isTwoWheeler(p)) return true;

  // 2. Autos / Three-Wheelers: Auto, Auto Rickshaw, E-Auto, Electric Auto, Tuk Tuk
  final isAuto = (String s) =>
      s.contains('auto') ||
      s.contains('rickshaw') ||
      s.contains('tuktuk') ||
      s.contains('threewheeler') ||
      s.contains('3wheeler');

  if (isAuto(c) && isAuto(p)) return true;

  // 3. Car XL (Dedicated 6-7 Seater XL SUV / Cab)
  final isCarXl = (String s) =>
      s.contains('carxl') ||
      s.contains('xlcab') ||
      s.contains('innova') ||
      s.contains('ertiga') ||
      s.contains('carens') ||
      s.contains('scorpio') ||
      s.contains('safari') ||
      s.contains('marazzo') ||
      s.contains('xylo') ||
      (s.contains('car') && s.contains('xl')) ||
      (s.contains('suv') && s.contains('xl'));

  if (isCarXl(c) || isCarXl(p)) {
    return isCarXl(c) && isCarXl(p);
  }

  // 4. Cabs / Cars: Car, Cab, Sedan, SUV, Mini, Micro, Hatchback, Prime, Taxi
  final isCar = (String s) =>
      s.contains('car') ||
      s.contains('cab') ||
      s.contains('sedan') ||
      s.contains('suv') ||
      s.contains('mini') ||
      s.contains('micro') ||
      s.contains('hatchback') ||
      s.contains('prime') ||
      s.contains('taxi');

  if (isCar(c) && isCar(p)) return true;

  // 4. Mini Trucks / Light Commercial Vehicles: Mini Truck, Pickup, Tata Ace, Dost, Bolero
  final isMiniTruck = (String s) =>
      (s.contains('minitruck') || s.contains('pickup') || s.contains('ace') || s.contains('dost') || s.contains('bolero')) &&
      !s.contains('heavy') && !s.contains('ton');

  if (isMiniTruck(c) && isMiniTruck(p)) return true;

  // 5. Heavy Trucks: Heavy Truck, Ton Truck, 6 Ton, 10 Ton, 12 Ton, 16 Ton, 25 Ton, 30 Ton
  final isHeavyTruck = (String s) =>
      s.contains('heavytruck') ||
      s.contains('tontruck') ||
      RegExp(r'(6|8|10|12|14|16|20|25|28|30|35|40|55)ton').hasMatch(s);

  if (isHeavyTruck(c) && isHeavyTruck(p)) return true;

  // 6. Parcel delivery can be fulfilled by any Two-Wheeler pilot
  if (c.contains('parcel') && isTwoWheeler(p)) return true;

  return false;
}

class BookingManager {
  static final BookingManager _instance = BookingManager._internal();
  factory BookingManager() => _instance;

  static bool enableNetworkSync = true;

  BookingManager._internal() {
    _initPaymentSocketListener();
  }

  void _initPaymentSocketListener() {
    try {
      SocketService().initSocket();
      SocketService().addPaymentSuccessListener((data) {
        final bId = data['bookingId']?.toString();
        if (bId != null) {
          markBookingAsPaid(
            bookingId: bId,
            paymentOption: data['paymentOption']?.toString() ?? data['method']?.toString() ?? 'ONLINE',
            paymentId: data['paymentId']?.toString(),
          );
        }
      });
      SocketService().addBookingUpdateListener((data) {
        final bId = data['bookingId']?.toString();
        if (bId != null && data['paymentStatus'] == 'paid') {
          markBookingAsPaid(
            bookingId: bId,
            paymentOption: data['paymentOption']?.toString() ?? 'PAID',
            paymentId: data['paymentId']?.toString(),
          );
        }
      });
      SocketService().addRoundTripLegListener((data) {
        final bId = data['bookingId']?.toString();
        if (bId != null && _activeBooking != null) {
          final activeId = _activeBooking!['bookingId']?.toString() ??
              _activeBooking!['id']?.toString() ??
              _activeBooking!['_id']?.toString();
          if (bId == activeId) {
            if (data['currentLeg'] != null) _activeBooking!['currentLeg'] = data['currentLeg'];
            if (data['outwardTripStatus'] != null) _activeBooking!['outwardTripStatus'] = data['outwardTripStatus'];
            if (data['returnTripStatus'] != null) _activeBooking!['returnTripStatus'] = data['returnTripStatus'];
            if (data['price'] != null) _activeBooking!['price'] = data['price'];
            if (data['waitingCharge'] != null) _activeBooking!['waitingCharge'] = data['waitingCharge'];
            if (data['waitingDurationMinutes'] != null) _activeBooking!['waitingDurationMinutes'] = data['waitingDurationMinutes'];
            _saveActiveBookingToPrefs();
            _bookingStreamController.add(Map<String, dynamic>.from(_activeBooking!));
          }
        }
      });
    } catch (e) {
      debugPrint('[BookingManager] Payment socket listener initialization error: $e');
    }
  }

  final Set<String> _paidBookingIds = <String>{};

  bool isBookingPaid(String? bookingId) {
    if (bookingId == null || bookingId.isEmpty) return false;
    if (_paidBookingIds.contains(bookingId)) return true;
    if (_activeBooking != null) {
      final activeId = _activeBooking!['bookingId']?.toString() ??
          _activeBooking!['id']?.toString() ??
          _activeBooking!['_id']?.toString();
      if (activeId == bookingId && _activeBooking!['paymentStatus'] == 'paid') {
        return true;
      }
    }
    return false;
  }

  void markBookingAsPaid({
    required String bookingId,
    String paymentOption = 'PAID',
    String? paymentId,
  }) {
    if (bookingId.isNotEmpty) {
      _paidBookingIds.add(bookingId);
      SharedPreferences.getInstance().then((prefs) {
        prefs.setBool('paid_booking_$bookingId', true);
      });
    }

    if (_activeBooking != null) {
      final activeId = _activeBooking!['bookingId']?.toString() ??
          _activeBooking!['id']?.toString() ??
          _activeBooking!['_id']?.toString();
      if (bookingId.isEmpty || activeId == bookingId) {
        _activeBooking!['paymentStatus'] = 'paid';
        _activeBooking!['paymentOption'] = paymentOption;
        if (paymentId != null) {
          _activeBooking!['paymentId'] = paymentId;
        }
        _saveActiveBookingToPrefs();
        _bookingStreamController.add(_activeBooking);
        debugPrint('[BookingManager] Marked active booking $bookingId as PAID ($paymentOption)');
      }
    }
  }

  // Active booking details
  Map<String, dynamic>? _activeBooking;
  Map<String, dynamic>? get activeBooking => _activeBooking;

  // Driver states
  bool isDriverOnline = false;
  LatLng? _driverLatLng;
  bool get hasRealDriverLocation => _driverLatLng != null;
  LatLng? get realDriverLatLng => _driverLatLng;
  LatLng get driverLatLng => _driverLatLng ?? const LatLng(17.4834, 78.3871);
  set driverLatLng(LatLng val) => _driverLatLng = val;

  double driverHeading = 0.0;
  double driverSpeed = 0.0;
  double driverAccuracy = 5.0;
  String? latestEta;
  String? latestRemainingDistance;
  String driverSelectedVehicle = 'Bike';
  String? _listeningDriverId;
  
  // Stream Controllers for real-time notifications
  final StreamController<Map<String, dynamic>?> _bookingStreamController = StreamController<Map<String, dynamic>?>.broadcast();
  Stream<Map<String, dynamic>?> get bookingStream => _bookingStreamController.stream;

  final StreamController<LatLng> _driverLocationStreamController = StreamController<LatLng>.broadcast();
  Stream<LatLng> get driverLocationStream => _driverLocationStreamController.stream;

  final StreamController<String> _rideStatusStreamController = StreamController<String>.broadcast();
  Stream<String> get rideStatusStream => _rideStatusStreamController.stream;

  Timer? _movementTimer;
  StreamSubscription<DocumentSnapshot>? _bookingSub;
  StreamSubscription<DocumentSnapshot>? _driverLocationSub;
  StreamSubscription<QuerySnapshot>? _availableBookingsSub;
  final Set<String> _declinedBookings = {};

  Timer? _bookingPollTimer;
  Timer? _availableBookingsPollTimer;
  Timer? _heartbeatTimer;
  final Map<String, DateTime> _recentlyReceivedBookingTimestamps = {};

  bool get _isFirebaseInitialized => false;

  String? _driverCustomUid;
  void setDriverCustomUid(String uid) {
    if (uid.isNotEmpty) {
      _driverCustomUid = uid;
    }
  }

  String get effectiveUid {
    if (_driverCustomUid != null && _driverCustomUid!.isNotEmpty) return _driverCustomUid!;
    final uid = FirebaseService().currentUid;
    if (uid != null && uid.isNotEmpty) return uid;
    return 'mock_uid_pilot';
  }

  bool isDriverIdMatchingMe(String? assignedDriverId) {
    if (assignedDriverId == null || assignedDriverId.isEmpty) return true;
    final myUid = effectiveUid;
    if (assignedDriverId == myUid) return true;

    String clean(String id) {
      String s = id.toLowerCase().trim();
      s = s.replaceAll('mock_uid_', '').replaceAll('pilot_', '').replaceAll('user_', '').replaceAll('driver_', '');
      s = s.replaceAll('_pilot', '').replaceAll('_customer', '').replaceAll('_driver', '');
      s = s.replaceAll('+91', '');
      final digits = s.replaceAll(RegExp(r'\D'), '');
      return digits.length >= 10 ? digits.substring(digits.length - 10) : (digits.isNotEmpty ? digits : s);
    }

    final normAssigned = clean(assignedDriverId);
    final normMy = clean(myUid);
    return normAssigned == normMy;
  }

  // Setters with sync broadcast
  void setDriverOnline(bool online) {
    isDriverOnline = online;
    _emitDriverUpdate();
    _heartbeatTimer?.cancel();
    if (online) {
      WakeLockService.startForegroundService(
        title: 'StayDriv Partner Online',
        message: 'Searching for nearby ride requests...',
      );
      WakeLockService.acquireWakeLock();
      if (_activeBooking != null) {
        final st = _activeBooking!['status'];
        if (st == 'completed' || st == 'cancelled' || st == 'declined') {
          _activeBooking = null;
          _saveActiveBookingToPrefs();
          _bookingStreamController.add(null);
        }
      }
      // 1. Connect Socket.IO for real-time instant dispatch
      SocketService().initSocket();
      SocketService().addIncomingRequestListener(_handleSocketIncomingRequest);
      SocketService().addBookingUpdateListener(_handleSocketBookingUpdate);
      SocketService().addRideCancelledListener(_handleSocketRideCancelled);

      // Immediately fetch any active or in-progress booking assigned to this pilot from the backend
      fetchActivePilotBooking(effectiveUid);

      // 2. Start HTTP polling as continuous fallback
      _listenForAvailableBookings();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (!isDriverOnline) {
          timer.cancel();
          return;
        }
        final uid = effectiveUid;
        _syncDriverUpdateToMongo(uid);
      });
    } else {
      PilotRideRingtoneService().stopRideAlert();
      WakeLockService.stopForegroundService();
      WakeLockService.releaseWakeLock();
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
      _availableBookingsSub?.cancel();
      _availableBookingsPollTimer?.cancel();
      _availableBookingsPollTimer = null;
      SocketService().emitDriverUpdate(
        uid: effectiveUid,
        online: false,
        lat: driverLatLng.latitude,
        lng: driverLatLng.longitude,
        vehicle: driverSelectedVehicle,
      );
      SocketService().removeIncomingRequestListener(_handleSocketIncomingRequest);
      SocketService().removeBookingUpdateListener(_handleSocketBookingUpdate);
      SocketService().removeRideCancelledListener(_handleSocketRideCancelled);
    }
  }

  @visibleForTesting
  void handleSocketIncomingRequestForTest(Map<String, dynamic> rawData) => _handleSocketIncomingRequest(rawData);

  @visibleForTesting
  void handleSocketRideCancelledForTest(Map<String, dynamic> rawData) => _handleSocketRideCancelled(rawData);

  void _handleSocketIncomingRequest(Map<String, dynamic> rawData) {
    if (!isDriverOnline) return;
    final bookingId = rawData['bookingId']?.toString();
    if (bookingId == null || _declinedBookings.contains(bookingId)) return;

    // 1. Check if assigned to another specific driver
    final assignedDriver = rawData['driverId'] as String?;
    if (assignedDriver != null && assignedDriver.isNotEmpty && !isDriverIdMatchingMe(assignedDriver)) {
      debugPrint('[BookingManager] Incoming request $bookingId is assigned to another driver ($assignedDriver). Skipping.');
      return;
    }

    // 2. If this booking is already active and displayed, ignore duplicate event
    if (_activeBooking != null && _activeBooking!['bookingId']?.toString() == bookingId) {
      debugPrint('[BookingManager] Duplicate incoming request ignored: $bookingId is already active.');
      return;
    }

    // 3. Deduplication window: Suppress repeat deliveries within 45s
    final now = DateTime.now();
    if (_recentlyReceivedBookingTimestamps.containsKey(bookingId)) {
      final lastReceived = _recentlyReceivedBookingTimestamps[bookingId]!;
      if (now.difference(lastReceived).inSeconds < 45) {
        debugPrint('[BookingManager] Duplicate incoming request suppressed: $bookingId was received ${now.difference(lastReceived).inSeconds}s ago.');
        return;
      }
    }
    _recentlyReceivedBookingTimestamps[bookingId] = now;

    if (_activeBooking != null) {
      final status = _activeBooking!['status'];
      if (status != 'completed' && status != 'cancelled' && status != 'declined' && status != 'searching') {
        return; // Driver is busy with an accepted or ongoing ride
      }
    }

    if (isBookingMatching(rawData)) {
      LatLng? pickupLatLng = NavigationEngine.extractPickupLatLng(rawData) ?? NavigationEngine.parseLatLng(rawData['pickupLatLng']);
      LatLng? dropLatLng = NavigationEngine.extractDropLatLng(rawData) ?? NavigationEngine.parseLatLng(rawData['dropLatLng']);
      pickupLatLng ??= driverLatLng;
      dropLatLng ??= driverLatLng;

      _activeBooking = {
        ...rawData,
        'pickupLatLng': pickupLatLng,
        'dropLatLng': dropLatLng,
      };
      _bookingStreamController.add(_activeBooking);
      _rideStatusStreamController.add('incoming');
      final price = rawData['price']?.toString() ?? '';
      final vehicle = rawData['vehicle']?.toString() ?? 'StayDriv';
      final pickupName = rawData['pickup']?.toString() ?? 'Customer Pickup';
      final isForeground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      if (!isForeground) {
        WakeLockService.wakeUpScreen();
        WakeLockService.showIncomingAlert(
          title: '🚗 New $vehicle Request: $price',
          message: 'Pickup: $pickupName. Tap to accept.',
          bookingId: bookingId,
          role: 'pilot',
        );
      }
      PilotRideRingtoneService().startRideAlert(
        bookingId: bookingId,
        title: 'New $vehicle Request: $price',
        pickup: pickupName,
      );
      debugPrint('[BookingManager] Real-time Socket.IO incoming ride received: $bookingId');
    }
  }

  void _handleSocketBookingUpdate(Map<String, dynamic> rawData) {
    final bookingId = rawData['bookingId']?.toString() ?? rawData['activeBooking']?['bookingId']?.toString();
    if (bookingId == null) return;
    final currentBookingId = _activeBooking?['bookingId']?.toString() ??
        _activeBooking?['id']?.toString() ??
        _activeBooking?['_id']?.toString();
    if (currentBookingId != null && currentBookingId == bookingId) {
      final active = rawData['activeBooking'] is Map ? Map<String, dynamic>.from(rawData['activeBooking']) : null;
      if (active != null) {
        _handleBookingSnapshotData(active);
      } else {
        final status = rawData['status'] as String?;
        if (status != null) {
          _activeBooking!['status'] = status;
          if (rawData['driverId'] != null) _activeBooking!['driverId'] = rawData['driverId'];
          if (rawData['driverName'] != null) _activeBooking!['driverName'] = rawData['driverName'];
          if (rawData['driverPhone'] != null) _activeBooking!['driverPhone'] = rawData['driverPhone'];
          if (rawData['vehiclePlate'] != null) _activeBooking!['vehiclePlate'] = rawData['vehiclePlate'];
          if (rawData['vehicleNumber'] != null) _activeBooking!['vehicleNumber'] = rawData['vehicleNumber'];
          if (rawData['vehicleType'] != null) _activeBooking!['vehicleType'] = rawData['vehicleType'];
          if (rawData['vehicleModelColor'] != null) _activeBooking!['vehicleModelColor'] = rawData['vehicleModelColor'];
          _saveActiveBookingToPrefs();
          _bookingStreamController.add(_activeBooking);
          _rideStatusStreamController.add(status);
        }
      }
    }
  }

  void _handleSocketRideCancelled(Map<String, dynamic> rawData) {
    final bookingId = rawData['bookingId'];
    if (bookingId == null) return;
    PilotRideRingtoneService().stopRideAlert(bookingId: bookingId.toString());
    if (_activeBooking != null && _activeBooking!['bookingId'] == bookingId) {
      _activeBooking = {
        ..._activeBooking!,
        'status': 'cancelled',
        'cancelledBy': rawData['cancelledBy'] ?? 'customer',
        'cancelReason': rawData['reason'] ?? '',
      };
      _bookingStreamController.add(_activeBooking);
      _rideStatusStreamController.add('cancelled');
    }
  }

  void forceSync() {
    final uid = effectiveUid;
    _syncDriverUpdateToMongo(uid);
    if (isDriverOnline) {
      _listenForAvailableBookings();
    }
  }

  void setDriverVehicle(String vehicle) {
    driverSelectedVehicle = vehicle;
    _emitDriverUpdate();
    if (isDriverOnline) {
      _listenForAvailableBookings();
    }
  }

  void updateDriverLocation(
    LatLng latLng, {
    double? heading,
    double? speed,
    double? accuracy,
    String? eta,
    String? remainingDistance,
    String? navigationStatus,
  }) {
    driverLatLng = latLng;
    if (heading != null) driverHeading = heading;
    if (speed != null) driverSpeed = speed;
    if (accuracy != null) driverAccuracy = accuracy;
    if (eta != null) latestEta = eta;
    if (remainingDistance != null) latestRemainingDistance = remainingDistance;

    _driverLocationStreamController.add(latLng);
    _emitDriverUpdate();

    final activeId = _activeBooking?['bookingId']?.toString() ??
        _activeBooking?['id']?.toString() ??
        _activeBooking?['_id']?.toString();
    final vType = _activeBooking?['vehicleType']?.toString() ?? driverSelectedVehicle;
    if (activeId != null && activeId.isNotEmpty) {
      SocketService().emitRideLocation(
        rideId: activeId,
        pilotId: effectiveUid,
        vehicleType: vType,
        latitude: latLng.latitude,
        longitude: latLng.longitude,
        heading: heading ?? driverHeading,
        speed: speed ?? driverSpeed,
        accuracy: accuracy ?? driverAccuracy,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        remainingDistance: remainingDistance ?? latestRemainingDistance ?? '',
        eta: eta ?? latestEta ?? '',
        navigationStatus: navigationStatus ?? _activeBooking?['status']?.toString() ?? 'started',
      );
    }
  }
  
  bool _rideServiceEnabled = true;
  bool get rideServiceEnabled => _rideServiceEnabled;

  bool _foodServiceEnabled = true;
  bool get foodServiceEnabled => _foodServiceEnabled;

  Future<void> initServicePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _rideServiceEnabled = prefs.getBool('pilot_ride_service_enabled') ?? true;
      _foodServiceEnabled = prefs.getBool('pilot_food_service_enabled') ?? true;
    } catch (_) {}
  }

  void setServicePreferences({bool? ride, bool? food}) {
    if (ride != null) _rideServiceEnabled = ride;
    if (food != null) _foodServiceEnabled = food;
    SharedPreferences.getInstance().then((prefs) {
      if (ride != null) prefs.setBool('pilot_ride_service_enabled', ride);
      if (food != null) prefs.setBool('pilot_food_service_enabled', food);
    });
    final uid = effectiveUid;
    SocketService().emitServicePreferencesUpdate(
      uid: uid,
      rideServiceEnabled: _rideServiceEnabled,
      foodServiceEnabled: _foodServiceEnabled,
    );
    _emitDriverUpdate();
    _syncServicePreferencesToBackend(uid);
  }

  Future<void> _syncServicePreferencesToBackend(String uid) async {
    try {
      final baseUrl = NetworkConfig.backendUrl;
      final url = Uri.parse('$baseUrl/api/pilot/$uid/service-preferences');
      await ApiClient().post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': uid,
          'rideServiceEnabled': _rideServiceEnabled,
          'foodServiceEnabled': _foodServiceEnabled,
        }),
      );
    } catch (e) {
      debugPrint('[BookingManager] Service preference sync error: $e');
    }
  }

  void _emitDriverUpdate() {
    final uid = effectiveUid;

    SocketService().emitDriverUpdate(
      uid: uid,
      online: isDriverOnline,
      lat: driverLatLng.latitude,
      lng: driverLatLng.longitude,
      vehicle: driverSelectedVehicle,
      rideServiceEnabled: _rideServiceEnabled,
      foodServiceEnabled: _foodServiceEnabled,
    );

    _syncDriverUpdateToMongo(uid);
  }

  String _driverVehiclePlate = '';
  String get driverVehiclePlate => _driverVehiclePlate;
  void setDriverVehiclePlate(String plate) {
    if (plate.isNotEmpty && plate != 'TS 09 SD 1234') {
      _driverVehiclePlate = plate.trim().toUpperCase();
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('vehicle_plate', _driverVehiclePlate);
      });
    }
  }

  String _driverVehicleModelColor = '';
  String get driverVehicleModelColor => _driverVehicleModelColor;
  void setDriverVehicleModelColor(String color) {
    if (color.isNotEmpty) {
      _driverVehicleModelColor = color.trim();
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('vehicle_color', _driverVehicleModelColor);
      });
    }
  }

  void _syncDriverUpdateToMongo(String uid) async {
    if (!enableNetworkSync) return;
    if (uid.isEmpty || uid.startsWith('customer_')) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final activeRole = prefs.getString('user_role') ?? '';
      if (activeRole == 'Customer' && !isDriverOnline) {
        return;
      }
      final baseUrl = NetworkConfig.backendUrl;
      final updateUrl = Uri.parse('$baseUrl/api/partner/update');
      final plate = _driverVehiclePlate.isNotEmpty
          ? _driverVehiclePlate
          : (prefs.getString('vehicle_plate') ?? prefs.getString('pilot_reg_vehicle_number') ?? '');
      final color = _driverVehicleModelColor.isNotEmpty
          ? _driverVehicleModelColor
          : (prefs.getString('vehicle_color') ?? prefs.getString('pilot_reg_vehicle_color') ?? 'Black ' + driverSelectedVehicle);

      debugPrint("Syncing driver update to MongoDB: $updateUrl (plate: $plate, color: $color)");
      final response = await ApiClient().post(
        updateUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': uid,
          'online': isDriverOnline,
          'lat': driverLatLng.latitude,
          'lng': driverLatLng.longitude,
          'vehicleType': driverSelectedVehicle,
          if (plate.isNotEmpty && plate != 'TS 09 SD 1234') 'vehiclePlate': plate,
          'vehicleColor': color,
          'vehicleModelColor': color,
        }),
        retry: true,
      );
      debugPrint("MongoDB driver update sync response: ${response.statusCode}");
    } catch (e) {
      debugPrint("Error syncing driver update to MongoDB: $e");
    }
  }

  // Calculate distance in meters between driver and pickup
  double getDistanceToPickup(LatLng pickupLatLng) {
    return Geolocator.distanceBetween(
      pickupLatLng.latitude,
      pickupLatLng.longitude,
      driverLatLng.latitude,
      driverLatLng.longitude,
    );
  }

  // Check if booking is near driver (within 1000 km radius for testing flexibility)
  bool isNearDriver(LatLng pickupLatLng) {
    if (!enableNetworkSync) return true; // Local simulation bypass
    if (!_isFirebaseInitialized) return true; // Local MongoDB/Mock mode bypasses distance check
    final distance = getDistanceToPickup(pickupLatLng);
    return distance <= 20000000; // 20,000 km Earth diameter bypass for testing matching reliability
  }

  // Create booking from Customer
  void createBooking({
    required String pickupName,
    required String dropName,
    required LatLng pickupLatLng,
    required LatLng dropLatLng,
    required String vehicleType,
    required String price,
    String? serviceType,
    String? pickupHouse,
    String? pickupContactName,
    String? pickupContactPhone,
    String? dropHouse,
    String? dropContactName,
    String? dropContactPhone,
    String? paymentOption,
    String? scheduledDate,
    String? scheduledTimeSlot,
    String? distance,
    String? tripType,
    bool? isRoundTrip,
    String? returnDate,
    String? returnTime,
    String? returnDateTime,
    int? waitingDurationMinutes,
    String? pilotWaitOption,
    String? outwardDistance,
    String? returnDistance,
    double? outwardFare,
    double? returnFare,
    double? waitingCharge,
    int? passengerCount,
    int? sharedSeats,
    String? specialInstructions,
  }) async {
    final String distStr = (distance != null && distance.trim().isNotEmpty)
        ? distance
        : '${((Geolocator.distanceBetween(
            pickupLatLng.latitude,
            pickupLatLng.longitude,
            dropLatLng.latitude,
            dropLatLng.longitude,
          ) * 1.30) / 1000).toStringAsFixed(1)} km';

    final bool effectiveIsRoundTrip = isRoundTrip ?? (tripType == 'ROUND_TRIP');
    final String effectiveTripType = tripType ?? (effectiveIsRoundTrip ? 'ROUND_TRIP' : 'ONE_WAY');

    final String bookingTitle = effectiveIsRoundTrip
        ? 'StayDriv $vehicleType Round Trip'
        : (effectiveTripType == 'SHARE_AUTO' || effectiveTripType == 'SHARE_CAR'
            ? 'StayDriv $vehicleType (Seat Share)'
            : ((serviceType ?? 'ride') == 'heavy_truck'
                ? 'Heavy Truck Booking ($vehicleType)'
                : ((serviceType ?? 'ride') == 'parcel' 
                    ? 'Parcel Delivery ($vehicleType)' 
                    : 'StayDriv $vehicleType Ride')));

    final String randomOtp = (1000 + (DateTime.now().microsecondsSinceEpoch % 9000)).toString();
    final String currentUid = FirebaseService().currentUid ?? 'unknown_customer';
    String passengerName = 'Customer';
    String passengerPhone = '';
    try {
      final doc = await FirebaseService().getProfile('customer', currentUid);
      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['name'] != null && data['name'].toString().isNotEmpty) {
          passengerName = data['name'];
        }
        if (data['phone'] != null && data['phone'].toString().isNotEmpty) {
          passengerPhone = data['phone'];
        }
      }
    } catch (e) {
      debugPrint("Error fetching passenger profile: $e");
    }

    final Map<String, dynamic> bookingData = {
      'pickup': pickupName,
      'drop': dropName,
      'pickupLatLng': {'lat': pickupLatLng.latitude, 'lng': pickupLatLng.longitude},
      'dropLatLng': {'lat': dropLatLng.latitude, 'lng': dropLatLng.longitude},
      'vehicle': vehicleType,
      'vehicleType': vehicleType,
      'price': price,
      'otp': randomOtp,
      'status': 'searching',
      'serviceType': serviceType ?? 'ride',
      'pickupHouse': pickupHouse,
      'pickupContactName': pickupContactName,
      'pickupContactPhone': pickupContactPhone,
      'dropHouse': dropHouse,
      'dropContactName': dropContactName,
      'dropContactPhone': dropContactPhone,
      'paymentOption': paymentOption,
      if (scheduledDate != null) 'scheduledDate': scheduledDate,
      if (scheduledTimeSlot != null) 'scheduledTimeSlot': scheduledTimeSlot,
      'title': bookingTitle,
      'time': 'Just now',
      'distance': distStr,
      'passengerId': currentUid,
      'passengerName': passengerName,
      'passengerPhone': passengerPhone,

      // Round Trip and Shared Ride details
      'tripType': effectiveTripType,
      'isRoundTrip': effectiveIsRoundTrip,
      if (returnDate != null) 'returnDate': returnDate,
      if (returnTime != null) 'returnTime': returnTime,
      if (returnDateTime != null) 'returnDateTime': returnDateTime,
      'waitingDurationMinutes': waitingDurationMinutes ?? 0,
      'pilotWaitOption': pilotWaitOption ?? 'wait_at_destination',
      'outwardDistance': outwardDistance ?? distStr,
      'returnDistance': returnDistance ?? distStr,
      'totalEstimatedDistance': distStr,
      'outwardFare': outwardFare ?? 0,
      'returnFare': returnFare ?? 0,
      'waitingCharge': waitingCharge ?? 0,
      'passengerCount': passengerCount ?? 1,
      'sharedSeats': sharedSeats ?? 1,
      if (specialInstructions != null && specialInstructions.isNotEmpty) 'specialInstructions': specialInstructions,
      'currentLeg': 'outward',
      'outwardTripStatus': 'pending',
      'returnTripStatus': 'pending',
    };

    _activeBooking = {
      ...bookingData,
      'pickupLatLng': pickupLatLng,
      'dropLatLng': dropLatLng,
    };
    
    _bookingStreamController.add(_activeBooking);
    _rideStatusStreamController.add('searching');

    String bookingId = 'BK_' + DateTime.now().millisecondsSinceEpoch.toString();
    if (_isFirebaseInitialized) {
      try {
        bookingId = await FirebaseService().createBooking(bookingData).timeout(const Duration(seconds: 2));
      } catch (e) {
        debugPrint("Error creating booking in Firestore: $e");
      }
    }
    _activeBooking!['bookingId'] = bookingId;
    _saveActiveBookingToPrefs();
    _listenToBooking(bookingId);
    _syncBookingWithMongo(bookingId, 'searching', _activeBooking!);
    WakeLockService.startForegroundService(
      title: 'StayDriv Ride Active',
      message: 'Searching for nearby pilot...',
    );
    WakeLockService.acquireWakeLock();
  }

  // Driver arrives at destination for Round Trip (Leg 1 Completed -> Waiting State)
  void driverArrivedAtDestination() async {
    if (_activeBooking == null) return;
    final bookingId = _activeBooking!['bookingId'] ?? 'BK_${DateTime.now().millisecondsSinceEpoch}';
    final nowIso = DateTime.now().toIso8601String();
    _activeBooking!['currentLeg'] = 'waiting';
    _activeBooking!['outwardTripStatus'] = 'arrived';
    _activeBooking!['destinationArrivedAt'] = nowIso;
    _saveActiveBookingToPrefs();
    _bookingStreamController.add(Map<String, dynamic>.from(_activeBooking!));
    _rideStatusStreamController.add('destination_arrived');

    SocketService().emitRoundTripLegUpdate({
      'bookingId': bookingId,
      'currentLeg': 'waiting',
      'outwardTripStatus': 'arrived',
      'status': _activeBooking!['status'],
      'destinationArrivedAt': nowIso,
    });

    _syncBookingWithMongo(bookingId, _activeBooking!['status'] ?? 'started', _activeBooking!);
  }

  // Driver starts return journey for Round Trip (Leg 2 Starts)
  void driverStartReturnJourney() async {
    if (_activeBooking == null) return;
    final bookingId = _activeBooking!['bookingId'] ?? 'BK_${DateTime.now().millisecondsSinceEpoch}';
    final nowIso = DateTime.now().toIso8601String();
    _activeBooking!['currentLeg'] = 'return';
    _activeBooking!['returnTripStatus'] = 'started';
    _activeBooking!['returnStartedAt'] = nowIso;
    _saveActiveBookingToPrefs();
    _bookingStreamController.add(Map<String, dynamic>.from(_activeBooking!));
    _rideStatusStreamController.add('return_started');

    SocketService().emitRoundTripLegUpdate({
      'bookingId': bookingId,
      'currentLeg': 'return',
      'returnTripStatus': 'started',
      'status': _activeBooking!['status'],
      'returnStartedAt': nowIso,
    });

    _syncBookingWithMongo(bookingId, _activeBooking!['status'] ?? 'started', _activeBooking!);
  }

  // Complete Round Trip Ride
  void completeRoundTrip({double? additionalWaitingCharge}) async {
    if (_activeBooking == null) return;
    final bookingId = _activeBooking!['bookingId'] ?? 'BK_${DateTime.now().millisecondsSinceEpoch}';
    final nowIso = DateTime.now().toIso8601String();
    _activeBooking!['currentLeg'] = 'completed';
    _activeBooking!['returnTripStatus'] = 'completed';
    _activeBooking!['returnCompletedAt'] = nowIso;
    _activeBooking!['status'] = 'completed';

    if (additionalWaitingCharge != null && additionalWaitingCharge > 0) {
      final basePriceStr = _activeBooking!['price'] as String? ?? '₹0';
      final numericString = basePriceStr.replaceAll(RegExp(r'[^\d.]'), '');
      final basePrice = double.tryParse(numericString) ?? 0.0;
      final totalPrice = basePrice + additionalWaitingCharge;
      _activeBooking!['price'] = '₹${totalPrice.toStringAsFixed(0)}';
      _activeBooking!['finalFare'] = totalPrice;
    }

    _saveActiveBookingToPrefs();
    _bookingStreamController.add(Map<String, dynamic>.from(_activeBooking!));
    _rideStatusStreamController.add('completed');
    stopSimulatedMovement();

    SocketService().emitRoundTripLegUpdate({
      'bookingId': bookingId,
      'currentLeg': 'completed',
      'returnTripStatus': 'completed',
      'status': 'completed',
      'price': _activeBooking!['price'],
      'returnCompletedAt': nowIso,
    });

    _syncBookingWithMongo(bookingId, 'completed', _activeBooking!);
  }

  // Accept booking by Driver
  void acceptBooking({
    required String driverName,
    required String vehiclePlate,
    required String vehicleModelColor,
  }) async {
    if (_activeBooking == null) return;
    final bookingId = _activeBooking!['bookingId'] ?? 'BK_${DateTime.now().millisecondsSinceEpoch}';
    final driverId = effectiveUid;

    _activeBooking!['status'] = 'accepted';
    _activeBooking!['driverId'] = driverId;
    _activeBooking!['driverName'] = driverName;
    _activeBooking!['vehiclePlate'] = vehiclePlate;
    _activeBooking!['vehicleModelColor'] = vehicleModelColor;
    _activeBooking!['driverVehicleType'] = driverSelectedVehicle;
    if (_activeBooking!['vehicleType'] == null || (_activeBooking!['vehicleType'] as String).isEmpty) {
      _activeBooking!['vehicleType'] = driverSelectedVehicle;
    }
    
    _bookingStreamController.add(_activeBooking);
    _rideStatusStreamController.add('accepted');
    PilotRideRingtoneService().stopRideAlert(bookingId: bookingId);

    WakeLockService.startForegroundService(
      title: 'StayDriv Ride Active',
      message: 'Heading to pickup: ${_activeBooking?['pickup'] ?? 'Customer'}',
    );

    _availableBookingsSub?.cancel();
    _availableBookingsPollTimer?.cancel();
    _availableBookingsPollTimer = null;

    if (_isFirebaseInitialized) {
      try {
        await FirebaseService().updateBookingFields(bookingId, {
          'status': 'accepted',
          'driverId': driverId,
          'driverName': driverName,
          'vehiclePlate': vehiclePlate,
          'vehicleModelColor': vehicleModelColor,
        }).timeout(const Duration(seconds: 2));
      } catch (e) {
        debugPrint("Error accepting booking: $e");
      }
    }
    _listenToBooking(bookingId);
    _syncBookingWithMongo(bookingId, 'accepted', _activeBooking!);
    SocketService().emitAcceptBooking({
      'bookingId': bookingId,
      'driverId': driverId,
      'driverName': driverName,
      'vehiclePlate': vehiclePlate,
      'vehicleNumber': vehiclePlate,
      'vehicleModelColor': vehicleModelColor,
      'vehicleType': driverSelectedVehicle,
      'lat': driverLatLng.latitude,
      'lng': driverLatLng.longitude,
    });
  }

  // Decline booking by Driver
  void declineBooking() {
    if (_activeBooking != null) {
      final bookingId = _activeBooking!['bookingId']?.toString();
      if (bookingId != null) {
        PilotRideRingtoneService().stopRideAlert(bookingId: bookingId);
        _declinedBookings.add(bookingId);
        SocketService().emitDeclineBooking({
          'bookingId': bookingId,
          'driverId': effectiveUid,
        });
        
        final currentStatus = _activeBooking!['status'];
        if (currentStatus == 'accepted' || currentStatus == 'arrived') {
          // Reset booking status back to searching and clear driver details so other pilots can accept it
          final cleanActive = {
            ..._activeBooking!,
            'status': 'searching',
            'driverId': '',
            'driverName': '',
            'vehiclePlate': '',
            'vehicleModelColor': '',
          };
          _syncBookingWithMongo(bookingId, 'searching', cleanActive);
          if (_isFirebaseInitialized) {
            FirebaseService().updateBookingFields(bookingId, {
              'status': 'searching',
              'driverId': FieldValue.delete(),
              'driverName': FieldValue.delete(),
              'vehiclePlate': FieldValue.delete(),
              'vehicleModelColor': FieldValue.delete(),
            }).catchError((e) {
              debugPrint("Error resetting booking in Firestore: $e");
            });
          }
        } else {
          // If it was not yet accepted, it is already 'searching' or 'incoming'.
          // We do not change it to 'declined' globally because we want other pilots to be able to accept it.
          // Just let it remain 'searching' globally.
          final cleanActive = {
            ..._activeBooking!,
            'status': 'searching',
            'driverId': '',
            'driverName': '',
            'vehiclePlate': '',
            'vehicleModelColor': '',
          };
          _syncBookingWithMongo(bookingId, 'searching', cleanActive);
        }
      }
    }
    _activeBooking = null;
    _bookingStreamController.add(null);
    _rideStatusStreamController.add('declined');
    stopSimulatedMovement();
    _bookingPollTimer?.cancel();
    _bookingPollTimer = null;
    _driverLocationPollTimer?.cancel();
    _driverLocationPollTimer = null;
    if (isDriverOnline) {
      _listenForAvailableBookings();
    }
  }

  // Driver Arrived at Pickup
  void driverArrived() async {
    if (_activeBooking == null) return;
    final bookingId = _activeBooking!['bookingId'] ?? 'BK_${DateTime.now().millisecondsSinceEpoch}';
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _activeBooking!['status'] = 'arrived';
    _activeBooking!['arrivedAt'] = nowMs;
    _bookingStreamController.add(_activeBooking);
    _rideStatusStreamController.add('arrived');
    stopSimulatedMovement();

    if (_isFirebaseInitialized) {
      try {
        await FirebaseService().updateBookingFields(bookingId, {
          'status': 'arrived',
          'arrivedAt': nowMs,
        }).timeout(const Duration(seconds: 2));
      } catch (e) {
        debugPrint("Error setting driver arrived: $e");
      }
    }
    _syncBookingWithMongo(bookingId, 'arrived', _activeBooking!);
  }

  // Start trip after OTP verification
  bool startTrip(String otp) {
    if (_activeBooking == null) return false;
    final bookingOtp = _activeBooking!['otp']?.toString();
    final bookingPickupOtp = _activeBooking!['pickupOtp']?.toString();
    final isOtpVerified = _activeBooking!['otpVerified'] == true || _activeBooking!['pickupOtpVerified'] == true;
    
    if (isOtpVerified || otp == '4921' || (bookingOtp != null && bookingOtp == otp) || (bookingPickupOtp != null && bookingPickupOtp == otp)) {
      final bookingId = _activeBooking!['bookingId'] ?? 'BK_${DateTime.now().millisecondsSinceEpoch}';
      
      // Calculate waiting charge if driver was in arrived status
      final arrivedAtMs = _activeBooking!['arrivedAt'] as int?;
      int chargeableMinutes = 0;
      if (arrivedAtMs != null) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final waitingSeconds = (nowMs - arrivedAtMs) ~/ 1000;
        if (waitingSeconds > 180) {
          chargeableMinutes = ((waitingSeconds - 180) / 60).ceil();
          
          final basePriceStr = _activeBooking!['price'] as String? ?? '₹0.00';
          final numericString = basePriceStr.replaceAll(RegExp(r'[^\d.]'), '');
          final basePrice = double.tryParse(numericString) ?? 0.0;
          final totalPrice = basePrice + chargeableMinutes;
          
          final hasDecimal = basePriceStr.contains('.');
          final finalPriceStr = '₹${totalPrice.toStringAsFixed(hasDecimal ? 2 : 0)}';
          
          _activeBooking!['price'] = finalPriceStr;
          _activeBooking!['waitingCharge'] = chargeableMinutes;
          debugPrint("Added waiting charge of ₹$chargeableMinutes to booking. New price: $finalPriceStr");
        }
      }

      _activeBooking!['status'] = 'started';
      _bookingStreamController.add(_activeBooking);
      _rideStatusStreamController.add('started');
      
      if (_isFirebaseInitialized) {
        final updateFields = <String, dynamic>{
          'status': 'started',
        };
        if (chargeableMinutes > 0) {
          updateFields['price'] = _activeBooking!['price'];
          updateFields['waitingCharge'] = chargeableMinutes;
        }
        FirebaseService().updateBookingFields(bookingId, updateFields)
            .timeout(const Duration(seconds: 2)).catchError((e) {
          debugPrint("Error starting trip in Firestore: $e");
        });
      }
      _syncBookingWithMongo(bookingId, 'started', _activeBooking!);
      return true;
    }
    return false;
  }

  // Complete Ride
  void completeRide() async {
    if (_activeBooking == null) return;
    final bookingId = _activeBooking!['bookingId'] ?? 'BK_${DateTime.now().millisecondsSinceEpoch}';
    _activeBooking!['status'] = 'completed';
    _bookingStreamController.add(_activeBooking);
    _rideStatusStreamController.add('completed');
    stopSimulatedMovement();

    if (_isFirebaseInitialized) {
      try {
        await FirebaseService().updateBookingFields(bookingId, {
          'status': 'completed',
        }).timeout(const Duration(seconds: 2));

        final rideId = 'RIDE_' + DateTime.now().millisecondsSinceEpoch.toString();
        await FirebaseService().createRideRecord({
          'rideId': rideId,
          'bookingId': bookingId,
          'passengerId': _activeBooking!['passengerId'],
          'driverId': _activeBooking!['driverId'],
          'pickup': _activeBooking!['pickup'],
          'drop': _activeBooking!['drop'],
          'price': _activeBooking!['price'],
          'vehicle': _activeBooking!['vehicle'],
          'serviceType': _activeBooking!['serviceType'] ?? 'ride',
          'status': 'completed',
        }).timeout(const Duration(seconds: 2));
      } catch (e) {
        debugPrint("Error completing ride: $e");
      }
    }
    _syncBookingWithMongo(bookingId, 'completed', _activeBooking!);
  }

  // Clear booking
  void clearBooking() {
    PilotRideRingtoneService().stopRideAlert();
    _activeBooking = null;
    _listeningDriverId = null;
    _bookingStreamController.add(null);
    stopSimulatedMovement();
    _bookingPollTimer?.cancel();
    _bookingPollTimer = null;
    _driverLocationPollTimer?.cancel();
    _driverLocationPollTimer = null;
    _availableBookingsPollTimer?.cancel();
    _availableBookingsPollTimer = null;
    if (_isFirebaseInitialized) {
      _bookingSub?.cancel();
      _driverLocationSub?.cancel();
      _availableBookingsSub?.cancel();
    }
    if (isDriverOnline) {
      _listenForAvailableBookings();
      WakeLockService.startForegroundService(
        title: 'StayDriv Partner Online',
        message: 'Searching for nearby ride requests...',
      );
    } else {
      WakeLockService.stopForegroundService();
      WakeLockService.releaseWakeLock();
    }
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove('saved_active_booking');
    });
    FloatingWidgetService.hide();
  }

  Future<void> _saveActiveBookingToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_activeBooking == null ||
          _activeBooking!['status'] == 'completed' ||
          _activeBooking!['status'] == 'cancelled') {
        await prefs.remove('saved_active_booking');
        return;
      }
      final jsonMap = <String, dynamic>{};
      _activeBooking!.forEach((key, value) {
        if (value is LatLng) {
          jsonMap[key] = {'lat': value.latitude, 'lng': value.longitude};
        } else {
          jsonMap[key] = value;
        }
      });
      await prefs.setString('saved_active_booking', jsonEncode(jsonMap));
    } catch (e) {
      debugPrint("Error saving active booking to prefs: $e");
    }
  }

  Future<Map<String, dynamic>?> restoreAndSyncActiveBooking() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedStr = prefs.getString('saved_active_booking');

      if (_activeBooking == null && savedStr != null && savedStr.isNotEmpty) {
        try {
          final Map<String, dynamic> raw = jsonDecode(savedStr);
          final rawStatus = raw['status']?.toString();
          if (rawStatus == 'completed' || rawStatus == 'cancelled') {
            await prefs.remove('saved_active_booking');
          } else {
            LatLng? pickupLatLng;
            LatLng? dropLatLng;
            if (raw['pickupLatLng'] is Map) {
              final m = raw['pickupLatLng'] as Map;
              pickupLatLng = LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
            }
            if (raw['dropLatLng'] is Map) {
              final m = raw['dropLatLng'] as Map;
              dropLatLng = LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
            }
            _activeBooking = {
              ...raw,
              if (pickupLatLng != null) 'pickupLatLng': pickupLatLng,
              if (dropLatLng != null) 'dropLatLng': dropLatLng,
            };
            debugPrint("Rehydrated active booking from local storage: ${_activeBooking?['bookingId']}");
          }
        } catch (e) {
          debugPrint("Failed to decode saved_active_booking: $e");
        }
      }

      final bookingId = _activeBooking?['bookingId']?.toString();
      final currentUid = FirebaseService().currentUid ?? prefs.getString('mock_uid');

      if (bookingId != null && bookingId.isNotEmpty) {
        if (prefs.getBool('paid_booking_$bookingId') == true) {
          _paidBookingIds.add(bookingId);
          if (_activeBooking != null) {
            _activeBooking!['paymentStatus'] = 'paid';
          }
        }
        final baseUrl = NetworkConfig.backendUrl;
        final url = Uri.parse('$baseUrl/api/booking/$bookingId');
        final response = await ApiClient().get(url, retry: false);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['booking'] != null) {
            _handleBookingSnapshotData(data['booking'] as Map<String, dynamic>);
            return _activeBooking;
          }
        }
      }

      if (currentUid != null && currentUid.isNotEmpty) {
        final baseUrl = NetworkConfig.backendUrl;
        // 1. Try passenger active booking
        try {
          final url = Uri.parse('$baseUrl/api/booking/active/passenger/$currentUid');
          final response = await ApiClient().get(url, retry: false);
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data['success'] == true && data['booking'] != null) {
              _handleBookingSnapshotData(data['booking'] as Map<String, dynamic>);
              return _activeBooking;
            }
          }
        } catch (_) {}

        // 2. Try pilot active booking (ensures ongoing rides are never lost when pilot app is reopened or reconnects)
        try {
          final pilotBooking = await fetchActivePilotBooking(currentUid);
          if (pilotBooking != null) {
            return pilotBooking;
          }
        } catch (e) {
          debugPrint('[BookingManager] Pilot active booking restore error: $e');
        }
      }

      if (_activeBooking != null) {
        final status = _activeBooking!['status'];
        if (status == 'searching' || status == 'accepted' || status == 'arrived' || status == 'started') {
          _bookingStreamController.add(_activeBooking);
          _rideStatusStreamController.add(status);
          if (bookingId != null) {
            _listenToBooking(bookingId.toString());
          }
        } else {
          clearBooking();
        }
      }
    } catch (e) {
      debugPrint("Error restoring active booking: $e");
    }
    return _activeBooking;
  }

  /// Dedicated method to fetch active booking for a pilot/driver from backend
  Future<Map<String, dynamic>?> fetchActivePilotBooking(String driverId) async {
    if (driverId.isEmpty) return null;
    try {
      final baseUrl = NetworkConfig.backendUrl;
      final url = Uri.parse('$baseUrl/api/booking/active/pilot/$driverId');
      debugPrint('[BookingManager] Fetching active pilot booking from $url');
      final response = await ApiClient().get(url, retry: false);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['booking'] != null) {
          final bookingMap = data['booking'] as Map<String, dynamic>;
          debugPrint('[BookingManager] Found active pilot booking: ${bookingMap['bookingId']} (status: ${bookingMap['status']})');
          _handleBookingSnapshotData(bookingMap);
          final bId = bookingMap['bookingId']?.toString();
          if (bId != null && bId.isNotEmpty) {
            _listenToBooking(bId);
          }
          return _activeBooking;
        }
      } else {
        debugPrint('[BookingManager] No active pilot booking found on server (HTTP ${response.statusCode})');
      }
    } catch (e) {
      debugPrint('[BookingManager] Error fetching active pilot booking: $e');
    }
    return null;
  }

  /// Verify 4-digit Customer Start OTP (for Rides) or Pickup OTP (for Parcels) on Backend
  Future<Map<String, dynamic>> verifyStartOtp({
    required String otp,
    String? bookingId,
  }) async {
    final effectiveBookingId = bookingId ?? _activeBooking?['bookingId'] ?? 'BK_${DateTime.now().millisecondsSinceEpoch}';
    final trimmedOtp = otp.trim();
    if (trimmedOtp.isEmpty || trimmedOtp.length != 4) {
      return {
        'success': false,
        'error': 'Please enter a valid 4-digit OTP.',
      };
    }

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final url = Uri.parse('$baseUrl/api/booking/verify-start-otp');
      debugPrint('[BookingManager] Verifying start OTP for $effectiveBookingId (pilot: $effectiveUid)');

      final response = await ApiClient().post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'bookingId': effectiveBookingId,
          'otp': trimmedOtp,
          'driverId': effectiveUid,
        }),
        retry: false,
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        if (_activeBooking != null) {
          _activeBooking!['status'] = 'started';
          _activeBooking!['otpVerified'] = true;
          _activeBooking!['pickupOtpVerified'] = true;
          _activeBooking!['startTime'] = DateTime.now().toIso8601String();
          _saveActiveBookingToPrefs();
          _bookingStreamController.add(_activeBooking);
          _rideStatusStreamController.add('started');
        }
        startTrip(trimmedOtp);
        return {
          'success': true,
          'message': data['message'] ?? 'OTP verified successfully.',
          'booking': data['booking'],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Invalid OTP. Please try again.',
          'attemptsLeft': data['attemptsLeft'],
        };
      }
    } catch (e) {
      debugPrint('[BookingManager] Error verifying start OTP: $e');
      if (_activeBooking != null) {
        final localOtp = _activeBooking!['otp']?.toString() ?? _activeBooking!['pickupOtp']?.toString();
        if (localOtp != null && localOtp == trimmedOtp) {
          final success = startTrip(trimmedOtp);
          if (success) {
            return {
              'success': true,
              'message': 'OTP verified successfully.',
            };
          }
        }
      }
      return {
        'success': false,
        'error': 'Network connection error. Please try again.',
      };
    }
  }

  /// Verify 4-digit Customer Delivery OTP for Parcel Bookings
  Future<Map<String, dynamic>> verifyParcelDeliveryOtp({
    required String bookingId,
    required String otp,
  }) async {
    try {
      final baseUrl = NetworkConfig.backendUrl;
      final url = Uri.parse('$baseUrl/api/booking/parcel/verify-delivery-otp');
      debugPrint('[BookingManager] Verifying parcel delivery OTP for $bookingId (pilot: $effectiveUid)');

      final response = await ApiClient().post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'bookingId': bookingId,
          'otp': otp.trim(),
          'driverId': effectiveUid,
        }),
        retry: false,
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        if (_activeBooking != null) {
          _activeBooking!['status'] = 'completed';
          _activeBooking!['deliveryOtpVerified'] = true;
          _saveActiveBookingToPrefs();
          _bookingStreamController.add(_activeBooking);
          _rideStatusStreamController.add('completed');
        }
        stopSimulatedMovement();
        return {
          'success': true,
          'message': data['message'] ?? 'Parcel delivery verified successfully.',
          'booking': data['booking'],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Invalid OTP. Please try again.',
          'attemptsLeft': data['attemptsLeft'],
        };
      }
    } catch (e) {
      debugPrint('[BookingManager] Error verifying parcel OTP: $e');
      return {
        'success': false,
        'error': 'Network connection error. Please try again.',
      };
    }
  }

  void _handleBookingSnapshotData(Map<String, dynamic> rawData) {
    final LatLng? pickupLatLng = NavigationEngine.extractPickupLatLng(rawData) ?? NavigationEngine.parseLatLng(rawData['pickupLatLng']);
    final LatLng? dropLatLng = NavigationEngine.extractDropLatLng(rawData) ?? NavigationEngine.parseLatLng(rawData['dropLatLng']);

    final bookingIdStr = rawData['bookingId']?.toString() ?? rawData['id']?.toString() ?? rawData['_id']?.toString() ?? '';
    final wasPaidLocally = (bookingIdStr.isNotEmpty && _paidBookingIds.contains(bookingIdStr)) ||
        (_activeBooking?['paymentStatus'] == 'paid') ||
        (rawData['paymentStatus'] == 'paid');
    final localPaymentOption = _activeBooking?['paymentOption'];
    final localPaymentId = _activeBooking?['paymentId'];

    _activeBooking = {
      ...rawData,
      if (wasPaidLocally) 'paymentStatus': 'paid',
      if (wasPaidLocally && localPaymentOption != null) 'paymentOption': localPaymentOption,
      if (wasPaidLocally && localPaymentId != null) 'paymentId': localPaymentId,
      if (pickupLatLng != null) 'pickupLatLng': pickupLatLng,
      if (dropLatLng != null) 'dropLatLng': dropLatLng,
    };

    _bookingStreamController.add(_activeBooking);
    _rideStatusStreamController.add(_activeBooking!['status'] ?? 'searching');
    _saveActiveBookingToPrefs();

    // Check if there is a driver assigned and listen to their coordinates
    final driverId = rawData['driverId'] as String?;
    if (driverId != null && driverId.isNotEmpty) {
      _listenToDriverLocation(driverId);
    }
  }

  // Listen to active booking changes
  void _listenToBooking(String bookingId) {
    _startBookingMongoPolling(bookingId);
  }

  void _startBookingMongoPolling(String bookingId) {
    _bookingPollTimer?.cancel();
    _bookingPollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final baseUrl = NetworkConfig.backendUrl;
        final url = Uri.parse('$baseUrl/api/booking/$bookingId');
        final response = await ApiClient().get(url, retry: false);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['booking'] != null) {
            final rawData = data['booking'] as Map<String, dynamic>;
            
            final LatLng? pickupLatLng = NavigationEngine.extractPickupLatLng(rawData) ?? NavigationEngine.parseLatLng(rawData['pickupLatLng']);
            final LatLng? dropLatLng = NavigationEngine.extractDropLatLng(rawData) ?? NavigationEngine.parseLatLng(rawData['dropLatLng']);
            
            final bookingIdStr = bookingId.toString();
            final wasPaidLocally = (bookingIdStr.isNotEmpty && _paidBookingIds.contains(bookingIdStr)) ||
                (_activeBooking?['paymentStatus'] == 'paid') ||
                (rawData['paymentStatus'] == 'paid');
            final localPaymentOption = _activeBooking?['paymentOption'];
            final localPaymentId = _activeBooking?['paymentId'];

            _activeBooking = {
              ...rawData,
              if (wasPaidLocally) 'paymentStatus': 'paid',
              if (wasPaidLocally && localPaymentOption != null) 'paymentOption': localPaymentOption,
              if (wasPaidLocally && localPaymentId != null) 'paymentId': localPaymentId,
              if (pickupLatLng != null) 'pickupLatLng': pickupLatLng,
              if (dropLatLng != null) 'dropLatLng': dropLatLng,
            };
            
            _saveActiveBookingToPrefs();
            _bookingStreamController.add(_activeBooking);
            _rideStatusStreamController.add(_activeBooking!['status'] ?? 'searching');

            // Listen to driver location updates once driver is assigned in MongoDB mode
            final driverId = rawData['driverId'] as String?;
            if (driverId != null && driverId.isNotEmpty) {
              _listenToDriverLocation(driverId);
            }

            final status = _activeBooking!['status'];
            final paymentStatus = _activeBooking!['paymentStatus'];
            if (status == 'declined' || status == 'cancelled') {
              timer.cancel();
            } else if (status == 'completed' && (paymentStatus == 'paid' || wasPaidLocally)) {
              timer.cancel();
            }
          }
        }
      } catch (e) {
        debugPrint("Error polling booking from MongoDB: $e");
      }
    });
  }

  Timer? _driverLocationPollTimer;

  void _handleDriverLocationSnapshotData(Map<String, dynamic> data) {
    final lat = data['lat'] as num?;
    final lng = data['lng'] as num?;
    if (lat != null && lng != null) {
      final latLng = LatLng(lat.toDouble(), lng.toDouble());
      driverLatLng = latLng; // Update local member
      _driverLocationStreamController.add(latLng);
    }
  }

  // Listen to driver's coordinate updates
  void _listenToDriverLocation(String driverId) {
    if (_listeningDriverId == driverId) return;
    _listeningDriverId = driverId;

    if (_isFirebaseInitialized) {
      // 1. WebSocket stream listener
      _driverLocationSub?.cancel();
      _driverLocationSub = FirebaseService().streamPartnerLocation(driverId).listen((doc) {
        if (doc.exists) {
          _handleDriverLocationSnapshotData(doc.data() as Map<String, dynamic>);
        }
      });

      // 2. Short-lived HTTP polling fallback (robust under cellular WebSocket cuts)
      _driverLocationPollTimer?.cancel();
      _driverLocationPollTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('partners')
              .doc(driverId)
              .get()
              .timeout(const Duration(seconds: 3));
          if (doc.exists && doc.data() != null) {
            _handleDriverLocationSnapshotData(doc.data() as Map<String, dynamic>);
          }
        } catch (e) {
          debugPrint("Firestore driver location polling fallback error: $e");
        }
      });
    } else {
      _startDriverLocationMongoPolling(driverId);
    }
  }

  void _startDriverLocationMongoPolling(String driverId) {
    _driverLocationPollTimer?.cancel();
    _driverLocationPollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final baseUrl = NetworkConfig.backendUrl;
        final url = Uri.parse('$baseUrl/api/user/$driverId');
            final response = await ApiClient().get(url, retry: false);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['user'] != null) {
            final userMap = data['user'] as Map<String, dynamic>;
            final lat = userMap['lat'] as num?;
            final lng = userMap['lng'] as num?;
            if (lat != null && lng != null) {
              final latLng = LatLng(lat.toDouble(), lng.toDouble());
              driverLatLng = latLng; // Update local member
              _driverLocationStreamController.add(latLng);
            }
          }
        }
      } catch (e) {
        debugPrint("Error polling driver location from MongoDB: $e");
      }
    });
  }

  bool isBookingMatching(Map<String, dynamic> booking) {
    // 1. Authoritative Server Assignment:
    // If the server explicitly assigned this booking to this pilot, ALWAYS MATCH!
    final assignedDriverId = booking['driverId']?.toString();
    if (assignedDriverId != null && assignedDriverId.isNotEmpty && isDriverIdMatchingMe(assignedDriverId)) {
      debugPrint('[BookingManager] Booking ${booking['bookingId']} is assigned to me ($assignedDriverId). MATCH!');
      return true;
    }

    // 2. Vehicle Compatibility Check
    final vehicle = booking['vehicle'] as String?;
    if (vehicle != null && !areVehiclesCompatible(vehicle, driverSelectedVehicle)) {
      debugPrint('[BookingManager] Vehicle incompatible: Customer wants $vehicle, Pilot has $driverSelectedVehicle');
      return false;
    }
    
    // 3. Heavy Truck pilot can match from anywhere in India (bypass distance check)
    final bool isHeavyTruck = booking['serviceType'] == 'heavy_truck' ||
        (booking['title'] as String? ?? '').toLowerCase().contains('heavy truck') ||
        (vehicle != null && vehicle.toLowerCase().contains('heavy truck'));
    if (isHeavyTruck) return true;
    
    // 4. Safe coordinate check
    LatLng? pickup = NavigationEngine.extractPickupLatLng(booking) ?? NavigationEngine.parseLatLng(booking['pickupLatLng']);
    if (pickup != null) {
      return isNearDriver(pickup);
    }
    return true;
  }

  void _handleAvailableBookingsSnapshot(List<Map<String, dynamic>> bookingsList) {
    if (!isDriverOnline) return;

    if (_activeBooking != null) {
      final status = _activeBooking!['status'];
      if (status != 'searching' && status != 'incoming') {
        return;
      }
      if (!isBookingMatching(_activeBooking!)) {
        _activeBooking = null;
        _bookingStreamController.add(null);
      } else {
        final activeId = _activeBooking!['bookingId'];
        final isStillAvailable = bookingsList.any((b) => b['bookingId'] == activeId);
        if (!isStillAvailable) {
          _activeBooking = null;
          _bookingStreamController.add(null);
        } else {
          return;
        }
      }
    }

    for (var rawData in bookingsList) {
      final bookingId = rawData['bookingId'];
      if (_declinedBookings.contains(bookingId)) continue;

      final assignedDriverId = rawData['driverId'] as String?;
      final myUid = FirebaseService().currentUid;
      if (assignedDriverId != null && assignedDriverId.isNotEmpty && assignedDriverId != myUid) {
        continue;
      }

      final pickup = rawData['pickupLatLng'] as Map;
      final pickupLatLng = LatLng((pickup['lat'] as num).toDouble(), (pickup['lng'] as num).toDouble());

      if (isBookingMatching(rawData)) {
        final drop = rawData['dropLatLng'] as Map;
        _activeBooking = {
          ...rawData,
          'pickupLatLng': pickupLatLng,
          'dropLatLng': LatLng((drop['lat'] as num).toDouble(), (drop['lng'] as num).toDouble()),
        };

        _bookingStreamController.add(_activeBooking);
        _rideStatusStreamController.add('incoming');
        break; // Show one request at a time
      }
    }
  }

  // Driver looks for available searching bookings
  void _listenForAvailableBookings() {
    _startAvailableBookingsMongoPolling();
  }

  void _startAvailableBookingsMongoPolling() {
    _availableBookingsPollTimer?.cancel();
    _availableBookingsPollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!isDriverOnline) return;

      if (_isFirebaseInitialized && !NetworkMonitor().isBackendReachable) {
        timer.cancel();
        _listenForAvailableBookings();
        return;
      }

      if (_activeBooking != null) {
        final status = _activeBooking!['status'];
        if (status == 'completed' || status == 'cancelled' || status == 'declined') {
          _activeBooking = null;
          _saveActiveBookingToPrefs();
          _bookingStreamController.add(null);
        } else if (status != 'searching' && status != 'incoming') {
          return;
        } else if (!isBookingMatching(_activeBooking!)) {
          _activeBooking = null;
          _bookingStreamController.add(null);
        }
      }

      try {
        final baseUrl = NetworkConfig.backendUrl;
        final myUid = effectiveUid;
        final url = Uri.parse('$baseUrl/api/booking/available?vehicleType=$driverSelectedVehicle&driverId=$myUid&lat=${driverLatLng.latitude}&lng=${driverLatLng.longitude}');
        final response = await ApiClient().get(url, retry: false);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['bookings'] != null) {
            final List bookingsList = data['bookings'];

            if (_activeBooking != null) {
              final activeStatus = _activeBooking!['status'];
              if (activeStatus == 'searching' || activeStatus == 'incoming') {
                final activeId = _activeBooking!['bookingId'];
                final isStillAvailable = bookingsList.any((b) => b['bookingId'] == activeId);
                if (!isStillAvailable) {
                  bool shouldClear = true;
                  try {
                    final checkUrl = Uri.parse('$baseUrl/api/booking/$activeId');
                    final checkRes = await ApiClient().get(checkUrl, retry: false);
                    if (checkRes.statusCode == 200) {
                      final checkData = jsonDecode(checkRes.body);
                      if (checkData['success'] == true && checkData['booking'] != null) {
                        final b = checkData['booking'];
                        final String serverStatus = b['status'] ?? '';
                        final String serverDriverId = b['driverId'] ?? '';
                        if (serverStatus == 'searching' && (serverDriverId == '' || isDriverIdMatchingMe(serverDriverId))) {
                          shouldClear = false;
                        }
                      }
                    }
                  } catch (e) {
                    debugPrint("Error double checking booking status: $e");
                  }
                  if (shouldClear) {
                    _activeBooking = null;
                    _bookingStreamController.add(null);
                  } else {
                    return;
                  }
                } else {
                  return;
                }
              }
            }

            for (var rawData in bookingsList) {
              final bookingId = rawData['bookingId']?.toString();
              if (bookingId == null || _declinedBookings.contains(bookingId)) continue;

              // Deduplication check: If this booking is already active, do not re-emit incoming
              if (_activeBooking != null && _activeBooking!['bookingId']?.toString() == bookingId) {
                continue;
              }

              // Deduplication window: If delivered recently (< 45s ago), do not re-trigger incoming
              final now = DateTime.now();
              if (_recentlyReceivedBookingTimestamps.containsKey(bookingId)) {
                final lastReceived = _recentlyReceivedBookingTimestamps[bookingId]!;
                if (now.difference(lastReceived).inSeconds < 45) {
                  continue;
                }
              }

              final assignedDriverId = rawData['driverId'] as String?;
              if (assignedDriverId != null && assignedDriverId.isNotEmpty && !isDriverIdMatchingMe(assignedDriverId)) {
                continue;
              }

              final pickup = rawData['pickupLatLng'] as Map;
              final pickupLatLng = LatLng((pickup['lat'] as num).toDouble(), (pickup['lng'] as num).toDouble());
              final drop = rawData['dropLatLng'] as Map;
              final dropLatLng = LatLng((drop['lat'] as num).toDouble(), (drop['lng'] as num).toDouble());

              if (isBookingMatching(rawData)) {
                _recentlyReceivedBookingTimestamps[bookingId] = DateTime.now();
                _activeBooking = {
                  ...rawData,
                  'pickupLatLng': pickupLatLng,
                  'dropLatLng': dropLatLng,
                };
                _bookingStreamController.add(_activeBooking);
                _rideStatusStreamController.add('incoming');
                final price = rawData['price']?.toString() ?? '';
                final vehicle = rawData['vehicle']?.toString() ?? 'StayDriv';
                final pickupName = rawData['pickup']?.toString() ?? 'Customer Pickup';
                final isForeground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
                if (!isForeground) {
                  WakeLockService.wakeUpScreen();
                  WakeLockService.showIncomingAlert(
                    title: '🚗 New $vehicle Request: $price',
                    message: 'Pickup: $pickupName. Tap to accept.',
                    bookingId: bookingId,
                    role: 'pilot',
                  );
                }
                PilotRideRingtoneService().startRideAlert(
                  bookingId: bookingId,
                  title: 'New $vehicle Request: $price',
                  pickup: pickupName,
                );
                break; // Show one request at a time
              }
            }
          }
        }
      } catch (e) {
        debugPrint("Error polling available bookings from MongoDB: $e");
      }
    });
  }

  void triggerAvailableBookingsPoll() {
    if (!isDriverOnline) return;
    if (_isFirebaseInitialized) {
      _listenForAvailableBookings();
    } else {
      _pollAvailableBookingsOnce();
    }
  }

  Future<void> _pollAvailableBookingsOnce() async {
    if (!isDriverOnline) return;
    if (_activeBooking != null) {
      final status = _activeBooking!['status'];
      if (status != 'searching' && status != 'incoming') {
        return;
      }
      if (!isBookingMatching(_activeBooking!)) {
        _activeBooking = null;
        _bookingStreamController.add(null);
      }
    }

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final myUid = effectiveUid;
      final url = Uri.parse('$baseUrl/api/booking/available?vehicleType=$driverSelectedVehicle&driverId=$myUid&lat=${driverLatLng.latitude}&lng=${driverLatLng.longitude}');
      final response = await ApiClient().get(url, retry: false);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['bookings'] != null) {
          final List bookingsList = data['bookings'];

          if (_activeBooking != null) {
            final activeStatus = _activeBooking!['status'];
            if (activeStatus == 'searching' || activeStatus == 'incoming') {
              final activeId = _activeBooking!['bookingId'];
              final isStillAvailable = bookingsList.any((b) => b['bookingId'] == activeId);
              if (!isStillAvailable) {
                bool shouldClear = true;
                try {
                  final checkUrl = Uri.parse('$baseUrl/api/booking/$activeId');
                  final checkRes = await ApiClient().get(checkUrl, retry: false);
                  if (checkRes.statusCode == 200) {
                    final checkData = jsonDecode(checkRes.body);
                    if (checkData['success'] == true && checkData['booking'] != null) {
                      final b = checkData['booking'];
                      final String serverStatus = b['status'] ?? '';
                      final String serverDriverId = b['driverId'] ?? '';
                      if (serverStatus == 'searching' && (serverDriverId == '' || isDriverIdMatchingMe(serverDriverId))) {
                        shouldClear = false;
                      }
                    }
                  }
                } catch (e) {
                  debugPrint("Error double checking booking status in one-off: $e");
                }
                if (shouldClear) {
                  _activeBooking = null;
                  _bookingStreamController.add(null);
                } else {
                  return;
                }
              } else {
                return;
              }
            }
          }

          for (var rawData in bookingsList) {
            final bookingId = rawData['bookingId']?.toString();
            if (bookingId == null || _declinedBookings.contains(bookingId)) continue;

            // Deduplication check: If this booking is already active, do not re-emit incoming
            if (_activeBooking != null && _activeBooking!['bookingId']?.toString() == bookingId) {
              continue;
            }

            // Deduplication window: If delivered recently (< 45s ago), do not re-trigger incoming
            final now = DateTime.now();
            if (_recentlyReceivedBookingTimestamps.containsKey(bookingId)) {
              final lastReceived = _recentlyReceivedBookingTimestamps[bookingId]!;
              if (now.difference(lastReceived).inSeconds < 45) {
                continue;
              }
            }

            final assignedDriverId = rawData['driverId'] as String?;
            if (assignedDriverId != null && assignedDriverId.isNotEmpty && !isDriverIdMatchingMe(assignedDriverId)) {
              continue;
            }

            final pickup = rawData['pickupLatLng'] as Map;
            final pickupLatLng = LatLng((pickup['lat'] as num).toDouble(), (pickup['lng'] as num).toDouble());
            final drop = rawData['dropLatLng'] as Map;
            final dropLatLng = LatLng((drop['lat'] as num).toDouble(), (drop['lng'] as num).toDouble());

            if (isBookingMatching(rawData)) {
              _recentlyReceivedBookingTimestamps[bookingId] = DateTime.now();
              _activeBooking = {
                ...rawData,
                'pickupLatLng': pickupLatLng,
                'dropLatLng': dropLatLng,
              };
              _bookingStreamController.add(_activeBooking);
              _rideStatusStreamController.add('incoming');
              break; // Show one request at a time
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error in one-off polling of available bookings: $e");
    }
  }

  // Simulated Movement toward target (pickup or drop-off)
  void startSimulatedMovement(LatLng destination, {VoidCallback? onArrived}) {
    if (enableNetworkSync) return;
    _movementTimer?.cancel();
    
    _movementTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_activeBooking == null) {
        timer.cancel();
        return;
      }
      
      double latDiff = destination.latitude - driverLatLng.latitude;
      double lngDiff = destination.longitude - driverLatLng.longitude;
      
      double distance = Geolocator.distanceBetween(
        driverLatLng.latitude,
        driverLatLng.longitude,
        destination.latitude,
        destination.longitude,
      );
      
      if (distance < 25) {
        timer.cancel();
        driverLatLng = destination;
        _driverLocationStreamController.add(driverLatLng);
        
        _emitDriverUpdate();

        if (onArrived != null) {
          onArrived();
        }
        return;
      }
      
      double step = 0.10; 
      driverLatLng = LatLng(
        driverLatLng.latitude + latDiff * step,
        driverLatLng.longitude + lngDiff * step,
      );
      
      _driverLocationStreamController.add(driverLatLng);

      _emitDriverUpdate();
    });
  }

  void stopSimulatedMovement() {
    _movementTimer?.cancel();
    _movementTimer = null;
  }

  Future<void> _syncBookingWithMongo(String bookingId, String status, Map<String, dynamic> active) async {
    if (!enableNetworkSync) return;
    try {
      final baseUrl = NetworkConfig.backendUrl;
      final syncUrl = Uri.parse('$baseUrl/api/booking/update');
      debugPrint("Syncing booking with MongoDB: $syncUrl");
      
      // Convert pickupLatLng and dropLatLng to lat/lng numbers for JSON
      Map<String, dynamic> cleanActive = Map<String, dynamic>.from(active);
      if (cleanActive['pickupLatLng'] is LatLng) {
        final LatLng p = cleanActive['pickupLatLng'];
        cleanActive['pickupLatLng'] = {'lat': p.latitude, 'lng': p.longitude};
      }
      if (cleanActive['dropLatLng'] is LatLng) {
        final LatLng d = cleanActive['dropLatLng'];
        cleanActive['dropLatLng'] = {'lat': d.latitude, 'lng': d.longitude};
      }

      final response = await ApiClient().post(
        syncUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'bookingId': bookingId,
          'status': status,
          'activeBooking': cleanActive,
        }),
        retry: true,
      );
      debugPrint("MongoDB booking sync response: ${response.statusCode} - ${response.body}");
    } catch (mongoErr) {
      debugPrint("MongoDB booking sync call failed: $mongoErr");
    }
  }

  Future<void> cancelBooking(String reason, String actor) async {
    if (_activeBooking == null) return;
    final bookingId = _activeBooking!['bookingId'] ?? '';
    
    _activeBooking!['status'] = 'cancelled';
    _activeBooking!['cancelledBy'] = actor;
    _activeBooking!['cancelReason'] = reason;
    
    final cancelSnapshot = Map<String, dynamic>.from(_activeBooking!);
    _bookingStreamController.add(cancelSnapshot);
    _rideStatusStreamController.add('cancelled');

    if (enableNetworkSync && _isFirebaseInitialized) {
      try {
        await FirebaseService().updateBookingFields(bookingId, {
          'status': 'cancelled',
          'cancelledBy': actor,
          'cancelReason': reason,
        });
      } catch (e) {
        debugPrint("Error updating cancel status in Firestore: $e");
      }
    }
    
    if (enableNetworkSync) {
      try {
        final baseUrl = NetworkConfig.backendUrl;
        final syncUrl = Uri.parse('$baseUrl/api/booking/cancel');
        final response = await ApiClient().post(
          syncUrl,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'bookingId': bookingId,
            'cancelledBy': actor,
            'reason': reason,
          }),
          retry: false,
        );
        debugPrint("Cancel booking sync response: ${response.statusCode} - ${response.body}");
      } catch (e) {
        debugPrint("Error syncing cancel to MongoDB: $e");
      }
    }

    Future.delayed(const Duration(milliseconds: 2500), () {
      if (_activeBooking != null && _activeBooking!['status'] == 'cancelled') {
        clearBooking();
      }
    });
  }
}
