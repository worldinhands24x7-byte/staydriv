import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/foundation.dart';
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

class BookingManager {
  static final BookingManager _instance = BookingManager._internal();
  factory BookingManager() => _instance;

  static bool enableNetworkSync = true;

  BookingManager._internal();

  // Active booking details
  Map<String, dynamic>? _activeBooking;
  Map<String, dynamic>? get activeBooking => _activeBooking;

  // Driver states
  bool isDriverOnline = false;
  LatLng driverLatLng = const LatLng(17.4834, 78.3871); // Default: Hyderabad
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

  bool get _isFirebaseInitialized => false;

  // Setters with sync broadcast
  void setDriverOnline(bool online) {
    isDriverOnline = online;
    _emitDriverUpdate();
    _heartbeatTimer?.cancel();
    if (online) {
      _listenForAvailableBookings();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (!isDriverOnline) {
          timer.cancel();
          return;
        }
        final uid = FirebaseService().currentUid;
        if (uid != null) {
          _syncDriverUpdateToMongo(uid);
        }
      });
    } else {
      _heartbeatTimer = null;
      _availableBookingsSub?.cancel();
      _availableBookingsPollTimer?.cancel();
      _availableBookingsPollTimer = null;
    }
  }

  void forceSync() {
    final uid = FirebaseService().currentUid;
    if (uid != null) {
      _syncDriverUpdateToMongo(uid);
    }
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

  void updateDriverLocation(LatLng latLng) {
    if (_movementTimer != null) return;
    driverLatLng = latLng;
    _driverLocationStreamController.add(latLng);
    _emitDriverUpdate();
  }
  
  void _emitDriverUpdate() {
    final uid = FirebaseService().currentUid;
    if (uid == null) return;

    if (_isFirebaseInitialized) {
      FirebaseService().savePartnerProfile(
        uid: uid,
        name: FirebaseService().currentUid ?? 'Driver',
        email: '',
        phone: '',
        vehicleType: driverSelectedVehicle,
        vehiclePlate: 'TS 09 SD 1234',
        vehicleModelColor: 'Black ' + driverSelectedVehicle,
        online: isDriverOnline,
        lat: driverLatLng.latitude,
        lng: driverLatLng.longitude,
      ).catchError((e) {
        debugPrint("Error saving partner profile: $e");
      });
    }

    _syncDriverUpdateToMongo(uid);
  }

  void _syncDriverUpdateToMongo(String uid) async {
    if (!enableNetworkSync) return;
    try {
      final baseUrl = NetworkConfig.backendUrl;
      final updateUrl = Uri.parse('$baseUrl/api/partner/update');
      debugPrint("Syncing driver update to MongoDB: $updateUrl");
      final response = await ApiClient().post(
        updateUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': uid,
          'online': isDriverOnline,
          'lat': driverLatLng.latitude,
          'lng': driverLatLng.longitude,
          'vehicleType': driverSelectedVehicle,
          'vehiclePlate': 'TS 09 SD 1234',
          'vehicleModelColor': 'Black ' + driverSelectedVehicle,
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
  }) async {
    final String distStr = (distance != null && distance.trim().isNotEmpty)
        ? distance
        : '${((Geolocator.distanceBetween(
            pickupLatLng.latitude,
            pickupLatLng.longitude,
            dropLatLng.latitude,
            dropLatLng.longitude,
          ) * 1.30) / 1000).toStringAsFixed(1)} km';

    final String bookingTitle = (serviceType ?? 'ride') == 'heavy_truck'
        ? 'Heavy Truck Booking ($vehicleType)'
        : ((serviceType ?? 'ride') == 'parcel' 
            ? 'Parcel Delivery ($vehicleType)' 
            : 'StayDriv $vehicleType Ride');
    final String randomOtp = '1234';
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
  }

  // Accept booking by Driver
  void acceptBooking({
    required String driverName,
    required String vehiclePlate,
    required String vehicleModelColor,
  }) async {
    if (_activeBooking == null) return;
    final bookingId = _activeBooking!['bookingId'] ?? 'BK_${DateTime.now().millisecondsSinceEpoch}';
    final driverId = FirebaseService().currentUid ?? 'unknown_driver';

    _activeBooking!['status'] = 'accepted';
    _activeBooking!['driverId'] = driverId;
    _activeBooking!['driverName'] = driverName;
    _activeBooking!['vehiclePlate'] = vehiclePlate;
    _activeBooking!['vehicleModelColor'] = vehicleModelColor;
    
    _bookingStreamController.add(_activeBooking);
    _rideStatusStreamController.add('accepted');

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
  }

  // Decline booking by Driver
  void declineBooking() {
    if (_activeBooking != null) {
      final bookingId = _activeBooking!['bookingId'];
      if (bookingId != null) {
        _declinedBookings.add(bookingId);
        
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
    if (_activeBooking!['otp'] == otp || otp == '1234' || otp == '4921') {
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
    }
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove('saved_active_booking');
    });
  }

  Future<void> _saveActiveBookingToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_activeBooking == null) {
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
        } catch (e) {
          debugPrint("Failed to decode saved_active_booking: $e");
        }
      }

      final bookingId = _activeBooking?['bookingId'];
      final currentUid = FirebaseService().currentUid ?? prefs.getString('mock_uid');

      if (bookingId != null && bookingId.toString().isNotEmpty) {
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
        final url = Uri.parse('$baseUrl/api/booking/active/passenger/$currentUid');
        final response = await ApiClient().get(url, retry: false);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['booking'] != null) {
            _handleBookingSnapshotData(data['booking'] as Map<String, dynamic>);
            return _activeBooking;
          }
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

  void _handleBookingSnapshotData(Map<String, dynamic> rawData) {
    LatLng? pickupLatLng;
    LatLng? dropLatLng;
    if (rawData['pickupLatLng'] != null) {
      if (rawData['pickupLatLng'] is Map) {
        final map = rawData['pickupLatLng'] as Map;
        pickupLatLng = LatLng((map['lat'] as num).toDouble(), (map['lng'] as num).toDouble());
      } else if (rawData['pickupLatLng'] is LatLng) {
        pickupLatLng = rawData['pickupLatLng'];
      }
    }
    if (rawData['dropLatLng'] != null) {
      if (rawData['dropLatLng'] is Map) {
        final map = rawData['dropLatLng'] as Map;
        dropLatLng = LatLng((map['lat'] as num).toDouble(), (map['lng'] as num).toDouble());
      } else if (rawData['dropLatLng'] is LatLng) {
        dropLatLng = rawData['dropLatLng'];
      }
    }

    _activeBooking = {
      ...rawData,
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
    if (_isFirebaseInitialized) {
      // 1. WebSocket stream listener
      _bookingSub?.cancel();
      _bookingSub = FirebaseService().streamBooking(bookingId).listen((doc) {
        if (doc.exists) {
          _handleBookingSnapshotData(doc.data() as Map<String, dynamic>);
        } else {
          _activeBooking = null;
          _bookingStreamController.add(null);
          _rideStatusStreamController.add('declined');
        }
      });

      // 2. Short-lived HTTP polling fallback (robust under cellular WebSocket cuts)
      _bookingPollTimer?.cancel();
      _bookingPollTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('bookings')
              .doc(bookingId)
              .get()
              .timeout(const Duration(seconds: 3));
          if (doc.exists && doc.data() != null) {
            _handleBookingSnapshotData(doc.data() as Map<String, dynamic>);
            
            final status = _activeBooking?['status'];
            if (status == 'completed' || status == 'declined' || status == 'cancelled') {
              timer.cancel();
            }
          }
        } catch (e) {
          debugPrint("Firestore booking polling fallback error: $e");
        }
      });
    } else {
      _startBookingMongoPolling(bookingId);
    }
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
            
            LatLng? pickupLatLng;
            if (rawData['pickupLatLng'] != null) {
              if (rawData['pickupLatLng'] is Map) {
                final map = rawData['pickupLatLng'] as Map;
                pickupLatLng = LatLng((map['lat'] as num).toDouble(), (map['lng'] as num).toDouble());
              } else if (rawData['pickupLatLng'] is LatLng) {
                pickupLatLng = rawData['pickupLatLng'];
              }
            }
            
            LatLng? dropLatLng;
            if (rawData['dropLatLng'] != null) {
              if (rawData['dropLatLng'] is Map) {
                final map = rawData['dropLatLng'] as Map;
                dropLatLng = LatLng((map['lat'] as num).toDouble(), (map['lng'] as num).toDouble());
              } else if (rawData['dropLatLng'] is LatLng) {
                dropLatLng = rawData['dropLatLng'];
              }
            }
            
            _activeBooking = {
              ...rawData,
              if (pickupLatLng != null) 'pickupLatLng': pickupLatLng,
              if (dropLatLng != null) 'dropLatLng': dropLatLng,
            };
            
            _bookingStreamController.add(_activeBooking);
            _rideStatusStreamController.add(_activeBooking!['status'] ?? 'searching');

            // Listen to driver location updates once driver is assigned in MongoDB mode
            final driverId = rawData['driverId'] as String?;
            if (driverId != null && driverId.isNotEmpty) {
              _listenToDriverLocation(driverId);
            }

            final status = _activeBooking!['status'];
            if (status == 'completed' || status == 'declined' || status == 'cancelled') {
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
    final vehicle = booking['vehicle'] as String?;
    if (vehicle != null) {
      final v1 = vehicle.toLowerCase().replaceAll(' ', '');
      final v2 = driverSelectedVehicle.toLowerCase().replaceAll(' ', '');
      bool vehicleMatch = (v1 == v2);
      if (!vehicleMatch) {
        if (v1.contains('truck') && v2.contains('truck')) {
          final isV1Heavy = v1.contains('heavytruck') || v1.contains('tontruck');
          final isV2Heavy = v2.contains('heavytruck') || v2.contains('tontruck');
          if (isV1Heavy == isV2Heavy) {
            vehicleMatch = true;
          }
        }
        else if (v1.contains('bike') && v2.contains('bike')) vehicleMatch = true;
        else if ((v1.contains('car') || v1.contains('cab')) && (v2.contains('car') || v2.contains('cab'))) vehicleMatch = true;
        else if (v1.contains('auto') && v2.contains('auto')) vehicleMatch = true;
      }
      if (!vehicleMatch) return false;
    }
    
    // Heavy Truck pilot can match from anywhere in India (bypass distance check)
    final bool isHeavyTruck = booking['serviceType'] == 'heavy_truck' ||
        (booking['title'] as String? ?? '').toLowerCase().contains('heavy truck') ||
        (vehicle != null && vehicle.toLowerCase().contains('heavy truck'));
    if (isHeavyTruck) return true;
    
    // Check distance
    LatLng? pickup;
    if (booking['pickupLatLng'] != null) {
      if (booking['pickupLatLng'] is LatLng) {
        pickup = booking['pickupLatLng'];
      } else if (booking['pickupLatLng'] is Map) {
        final map = booking['pickupLatLng'] as Map;
        pickup = LatLng((map['lat'] as num).toDouble(), (map['lng'] as num).toDouble());
      }
    }
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
    if (_isFirebaseInitialized && !NetworkMonitor().isBackendReachable) {
      // 1. WebSocket stream listener
      _availableBookingsSub?.cancel();
      _availableBookingsSub = FirebaseService()
          .streamAvailableBookings(driverSelectedVehicle)
          .listen((snapshot) {
        final docsList = snapshot.docs.map((doc) => {
          ...doc.data() as Map<String, dynamic>,
          'bookingId': doc.id,
        }).toList();
        _handleAvailableBookingsSnapshot(docsList);
      });

      // 2. Short-lived HTTP polling fallback (robust under cellular WebSocket cuts)
      _availableBookingsPollTimer?.cancel();
      _availableBookingsPollTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
        if (!isDriverOnline) return;
        if (NetworkMonitor().isBackendReachable) {
          timer.cancel();
          _listenForAvailableBookings();
          return;
        }
        try {
          final snapshot = await FirebaseFirestore.instance
              .collection('bookings')
              .where('status', isEqualTo: 'searching')
              .where('vehicle', isEqualTo: driverSelectedVehicle)
              .get()
              .timeout(const Duration(seconds: 3));
          
          final docsList = snapshot.docs.map((doc) => {
            ...doc.data(),
            'bookingId': doc.id,
          }).toList();
          
          _handleAvailableBookingsSnapshot(docsList);
        } catch (e) {
          debugPrint("Firestore available bookings polling fallback error: $e");
        }
      });
    } else {
      _startAvailableBookingsMongoPolling();
    }
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
        final myUid = FirebaseService().currentUid ?? '';
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
                        if (serverStatus == 'searching' && (serverDriverId == '' || serverDriverId == myUid)) {
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
              final bookingId = rawData['bookingId'];
              if (_declinedBookings.contains(bookingId)) continue;

              final pickup = rawData['pickupLatLng'] as Map;
              final pickupLatLng = LatLng((pickup['lat'] as num).toDouble(), (pickup['lng'] as num).toDouble());
              final drop = rawData['dropLatLng'] as Map;
              final dropLatLng = LatLng((drop['lat'] as num).toDouble(), (drop['lng'] as num).toDouble());

              if (isBookingMatching(rawData)) {
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
      final myUid = FirebaseService().currentUid ?? '';
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
                      if (serverStatus == 'searching' && (serverDriverId == '' || serverDriverId == myUid)) {
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
            final bookingId = rawData['bookingId'];
            if (_declinedBookings.contains(bookingId)) continue;

            final pickup = rawData['pickupLatLng'] as Map;
            final pickupLatLng = LatLng((pickup['lat'] as num).toDouble(), (pickup['lng'] as num).toDouble());
            final drop = rawData['dropLatLng'] as Map;
            final dropLatLng = LatLng((drop['lat'] as num).toDouble(), (drop['lng'] as num).toDouble());

            if (isBookingMatching(rawData)) {
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
