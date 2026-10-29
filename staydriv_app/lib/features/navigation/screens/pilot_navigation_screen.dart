import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import '../../../core/api_client.dart';
import '../../../core/booking_manager.dart';
import '../../../core/network_config.dart';
import '../../../core/socket_service.dart';
import '../../../core/vehicle_marker_helper.dart';
import '../../../core/smooth_marker_animator.dart';
import '../../../core/wake_lock_service.dart';
import '../../../core/call_masking_service.dart';
import '../../../core/floating_widget_service.dart';
import '../services/navigation_engine.dart';

class PilotNavigationScreen extends StatefulWidget {
  final Map<String, dynamic> booking;
  final VoidCallback onRideCompleted;

  const PilotNavigationScreen({
    super.key,
    required this.booking,
    required this.onRideCompleted,
  });

  @override
  State<PilotNavigationScreen> createState() => _PilotNavigationScreenState();
}

class _PilotNavigationScreenState extends State<PilotNavigationScreen> with WidgetsBindingObserver {
  GoogleMapController? _mapController;

  // Locations
  late LatLng _destinationLatLng;
  late String _destinationAddress;
  LatLng _currentPilotLatLng = const LatLng(17.4834, 78.3871);
  double _currentHeading = 0.0;
  double _currentSpeedKmh = 0.0;

  // Route & Navigation Steps
  List<LatLng> _routePoints = [];
  List<LatLng> _passedRoutePoints = [];
  List<LatLng> _remainingRoutePoints = [];
  int _routeProgressIndex = 0;
  List<NavigationStep> _steps = [];
  int _currentStepIndex = 0;
  bool _isRerouting = false;
  int _consecutiveOffRouteCount = 0;
  String _rerouteReason = 'Rerouting...';
  bool _isInPipMode = false;

  // Navigation State
  bool _isDriverFollowing = true;
  bool _isUserDraggingMap = false;
  DateTime? _lastCameraUpdateTime;
  LatLng? _lastCameraUpdatePos;
  double _lastValidHeading = 0.0;
  bool _isMuted = false;
  bool _isDestinationReached = false;
  bool _isOverviewMode = false;

  // Navigation Stage
  String _navigationStage = 'to_pickup'; // 'to_pickup', 'to_drop', 'to_return'
  bool _isPickupReached = false;
  LatLng? _pickupLatLng;
  String _pickupAddress = '';
  final TextEditingController _startOtpController = TextEditingController();
  final TextEditingController _parcelDeliveryOtpController = TextEditingController();
  String _otpError = '';
  bool _isVerifyingDeliveryOtp = false;

  // Round Trip State
  bool _isRoundTrip = false;
  String _currentLeg = 'outward'; // 'outward', 'waiting', 'return', 'completed'
  int _waitingDurationSeconds = 0;
  Timer? _roundTripWaitTimer;
  double _additionalWaitingCharge = 0.0;
  static const double _waitingRatePerMinute = 2.5; // ₹2.5/min
  static const int _freeWaitingMinutes = 15; // 15 mins free waiting
  LatLng? _outwardDropLatLng;
  String _outwardDropAddress = '';
  LatLng? _returnDropLatLng;
  String _returnDropAddress = '';
  bool _isPickupLocationMissing = false;
  bool _isDropLocationMissing = false;
  bool _isReloadingCoordinates = false;

  // Progress metrics
  double _remainingDistanceMeters = 0.0;
  int _remainingDurationSeconds = 0;
  double _totalTripDistanceMeters = 1.0;

  // Stream & Timers
  StreamSubscription<Position>? _positionSub;
  Timer? _socketBroadcastTimer;

  // Markers
  BitmapDescriptor? _carMarkerIcon;

  void _updateRouteProgress(LatLng pos) {
    if (_routePoints.length < 2) return;

    final split = NavigationEngine.splitRouteAtPoint(
      pos,
      _routePoints,
      previousProgressIndex: _routeProgressIndex,
    );

    _routeProgressIndex = split.closestSegmentIndex;
    _passedRoutePoints = split.passedPoints;
    _remainingRoutePoints = split.remainingPoints;
    _remainingDistanceMeters = split.distanceRemainingMeters;
    _remainingDurationSeconds = math.max(10, (_remainingDistanceMeters / 8.5).round());
  }

  // High-performance smooth marker animator (60 FPS interpolation, drift & accuracy filtering)
  late final SmoothMarkerAnimator _markerAnimator = SmoothMarkerAnimator(
    onUpdate: (LatLng interpolatedPos, double interpolatedHeading) {
      if (!mounted) return;
      setState(() {
        _currentPilotLatLng = interpolatedPos;
        _currentHeading = interpolatedHeading;
        _updateRouteProgress(interpolatedPos);
      });
      // Smoothly update camera to follow moving vehicle without thrashing
      _maybeUpdateCameraDriverFollow(interpolatedPos, interpolatedHeading);
    },
    onSpeedUpdate: (double speedKmh) {
      if (!mounted) return;
      setState(() {
        _currentSpeedKmh = speedKmh;
      });
    },
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Setup native Android Picture-in-Picture mode listener
    WakeLockService.setPipModeListener((bool inPip) {
      if (mounted) {
        setState(() {
          _isInPipMode = inPip;
        });
      }
    });
    WakeLockService.enableAutoPip(false);

    _initDestinationData();
    _loadCustomCarMarker();
    _startForegroundKeepAlive();
    _initializePilotGpsAndRoute();
    _startSocketBroadcastLoop();
  }

  void _initDestinationData() {
    _isRoundTrip = widget.booking['isRoundTrip'] == true ||
        widget.booking['tripType'] == 'ROUND_TRIP' ||
        widget.booking['tripType'] == 'round_trip';
    _currentLeg = widget.booking['currentLeg']?.toString() ?? 'outward';

    final drop = NavigationEngine.extractDropLatLng(widget.booking);
    if (drop != null && (drop.latitude != 0.0 || drop.longitude != 0.0)) {
      _outwardDropLatLng = drop;
      _isDropLocationMissing = false;
    } else {
      _outwardDropLatLng = null;
      _isDropLocationMissing = true;
    }
    _outwardDropAddress = widget.booking['drop'] as String? ?? 'Destination';

    final pickup = NavigationEngine.extractPickupLatLng(widget.booking);
    if (pickup != null && (pickup.latitude != 0.0 || pickup.longitude != 0.0)) {
      _pickupLatLng = pickup;
      _returnDropLatLng = pickup;
      _isPickupLocationMissing = false;
    } else {
      _isPickupLocationMissing = true;
      _pickupLatLng = null;
      _returnDropLatLng = null;
    }
    _pickupAddress = widget.booking['pickup'] as String? ?? 'Pickup Location';
    _returnDropAddress = _pickupAddress;

    // Use the pilot's actual live GPS coordinates as the starting point (NEVER overwrite with pickup)
    if (BookingManager().hasRealDriverLocation) {
      _currentPilotLatLng = BookingManager().realDriverLatLng!;
    } else {
      _currentPilotLatLng = BookingManager().driverLatLng;
    }

    final bookingStatus = widget.booking['status']?.toString() ?? 'accepted';
    if (bookingStatus == 'accepted' || bookingStatus == 'arrived' || bookingStatus == 'heading_to_pickup') {
      _navigationStage = 'to_pickup';
      _destinationLatLng = _pickupLatLng ?? _currentPilotLatLng;
      _destinationAddress = _pickupAddress;
      if (bookingStatus == 'arrived') {
        _isPickupReached = true;
      }
    } else if (_isRoundTrip && _currentLeg == 'return') {
      _navigationStage = 'to_return';
      _destinationLatLng = _returnDropLatLng ?? _outwardDropLatLng ?? _currentPilotLatLng;
      _destinationAddress = _returnDropAddress;
    } else {
      _navigationStage = 'to_drop';
      _destinationLatLng = _outwardDropLatLng ?? _currentPilotLatLng;
      _destinationAddress = _outwardDropAddress;
    }
  }

  Future<void> _reloadBookingCoordinates() async {
    final bId = widget.booking['bookingId']?.toString() ??
        widget.booking['orderId']?.toString() ??
        widget.booking['id']?.toString() ??
        widget.booking['_id']?.toString() ??
        '';
    if (bId.isEmpty) return;

    setState(() {
      _isReloadingCoordinates = true;
    });

    try {
      final isFood = widget.booking['isFoodOrder'] == true ||
          widget.booking['serviceType'] == 'food' ||
          bId.startsWith('FD_');
      final baseUrl = NetworkConfig.backendUrl;
      final uri = isFood
          ? Uri.parse('$baseUrl/api/food/orders/$bId')
          : Uri.parse('$baseUrl/api/booking/$bId?role=pilot');
      final res = await ApiClient().get(uri, timeout: const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final bookingData = (data['order'] ?? data['booking']) as Map<String, dynamic>? ?? {};
        final reloadedPickup = NavigationEngine.extractPickupLatLng(bookingData);
        final reloadedDrop = NavigationEngine.extractDropLatLng(bookingData);

        if (reloadedPickup != null && (reloadedPickup.latitude != 0.0 || reloadedPickup.longitude != 0.0)) {
          _pickupLatLng = reloadedPickup;
          _returnDropLatLng = reloadedPickup;
          _isPickupLocationMissing = false;
        }
        if (reloadedDrop != null && (reloadedDrop.latitude != 0.0 || reloadedDrop.longitude != 0.0)) {
          _outwardDropLatLng = reloadedDrop;
          _isDropLocationMissing = false;
        }

        if (_navigationStage == 'to_pickup' && _pickupLatLng != null) {
          setState(() {
            _destinationLatLng = _pickupLatLng!;
            _isReloadingCoordinates = false;
          });
          await _requestRouteFromApi(_currentPilotLatLng, _destinationLatLng);
          return;
        } else if (_navigationStage == 'to_drop' && _outwardDropLatLng != null) {
          setState(() {
            _destinationLatLng = _outwardDropLatLng!;
            _isReloadingCoordinates = false;
          });
          await _requestRouteFromApi(_currentPilotLatLng, _destinationLatLng);
          return;
        }
      }
    } catch (e) {
      debugPrint('[PilotNavigation] Error reloading booking coordinates: $e');
    }

    if (mounted) {
      setState(() {
        _isReloadingCoordinates = false;
      });
      final missingType = _navigationStage == 'to_pickup' ? 'pickup' : 'delivery';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load valid destination $missingType coordinates. Please contact customer or support.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _initializePilotGpsAndRoute() async {
    // 1. Fetch real GPS position immediately
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[PILOT GPS] Location service is disabled on device');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        try {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 4),
          );
          final livePos = LatLng(pos.latitude, pos.longitude);
          _currentPilotLatLng = livePos;
          _currentHeading = pos.heading;
          BookingManager().updateDriverLocation(
            livePos,
            heading: pos.heading,
            speed: pos.speed,
          );
        } catch (posErr) {
          debugPrint('[PILOT GPS] Initial GPS fix error: $posErr');
        }
      }
    } catch (e) {
      debugPrint('[PILOT GPS] Location init note: $e');
    }

    // 2. If destination coordinates are missing, attempt initial reload
    if (_navigationStage == 'to_pickup' && (_isPickupLocationMissing || _pickupLatLng == null)) {
      await _reloadBookingCoordinates();
    } else if (_navigationStage == 'to_drop' && (_isDropLocationMissing || _outwardDropLatLng == null)) {
      await _reloadBookingCoordinates();
    } else {
      await _requestRouteFromApi(_currentPilotLatLng, _destinationLatLng);
    }

    // 3. Start live stream
    _startLiveGpsTracking();
  }

  void _loadCustomCarMarker() async {
    try {
      final vType = widget.booking['vehicleType']?.toString() ??
          widget.booking['vehicle']?.toString() ??
          BookingManager().driverSelectedVehicle;
      // Load standard Google Maps-style driving navigation avatar (size 256 for large, crisp visibility)
      final icon = await VehicleMarkerHelper.getNavigationAvatarMarker(
        vehicleType: vType,
        size: 256,
      );
      if (mounted) {
        setState(() {
          _carMarkerIcon = icon;
        });
      }
    } catch (e) {
      debugPrint('[PilotNavigation] Error loading Google navigation avatar marker: $e');
    }
  }

  void _startForegroundKeepAlive() {
    WakeLockService.acquireWakeLock();
    WakeLockService.startForegroundService(
      title: 'StayDriv In-App Navigation',
      message: 'Navigating to: $_destinationAddress',
    );
  }

  Future<void> _fetchInitialRoute() async {
    await _requestRouteFromApi(_currentPilotLatLng, _destinationLatLng);
  }

  Future<void> _requestRouteFromApi(LatLng origin, LatLng destination) async {
    final baseUrl = NetworkConfig.backendUrl;
    final uri = Uri.parse(
        '$baseUrl/api/directions?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}');

    try {
      final res = await ApiClient().get(uri, timeout: const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['status'] == 'OK' && data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final polylineStr = route['overview_polyline']?['points'] ?? '';
          final List<LatLng> decoded = NavigationEngine.decodePolyline(polylineStr);

          final legs = route['legs'] as List?;
          final List<NavigationStep> parsedSteps = [];
          double totalMeters = 0.0;
          int totalSeconds = 0;

          if (legs != null && legs.isNotEmpty) {
            final leg = legs[0];
            totalMeters = (leg['distance']?['value'] as num?)?.toDouble() ?? 0.0;
            totalSeconds = (leg['duration']?['value'] as num?)?.toInt() ?? 0;

            final stepsJson = leg['steps'] as List?;
            if (stepsJson != null) {
              for (var s in stepsJson) {
                parsedSteps.add(NavigationStep.fromGoogleStep(s));
              }
            }
          }

          if (decoded.isNotEmpty) {
            setState(() {
              _routePoints = decoded;
              _routeProgressIndex = 0;
              _passedRoutePoints = [];
              _remainingRoutePoints = List<LatLng>.from(decoded);
              _steps = parsedSteps;
              _currentStepIndex = 0;
              _remainingDistanceMeters = totalMeters;
              _remainingDurationSeconds = totalSeconds;
              if (_totalTripDistanceMeters <= 1.0 || totalMeters > _totalTripDistanceMeters) {
                _totalTripDistanceMeters = totalMeters > 0 ? totalMeters : 1000.0;
              }
              _isRerouting = false;
            });

            _updateRouteProgress(_currentPilotLatLng);
            _updateCameraView();
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('[PilotNavigation] Route fetch note: $e');
    }

    // Secondary fallback: Direct OSRM driving route to guarantee real road navigation
    if (_routePoints.isEmpty) {
      try {
        final osrmUri = Uri.parse(
          'https://router.project-osrm.org/route/v1/driving/${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}?overview=full',
        );
        final osrmRes = await ApiClient().get(osrmUri, timeout: const Duration(seconds: 8));
        if (osrmRes.statusCode == 200) {
          final osrmData = jsonDecode(osrmRes.body);
          if (osrmData['code'] == 'Ok' && osrmData['routes'] != null && osrmData['routes'].isNotEmpty) {
            final oRoute = osrmData['routes'][0];
            final geometry = oRoute['geometry']?.toString() ?? '';
            final decoded = NavigationEngine.decodePolyline(geometry);
            final double dist = (oRoute['distance'] as num?)?.toDouble() ?? NavigationEngine.distanceBetweenMeters(origin, destination);
            final int dur = (oRoute['duration'] as num?)?.toInt() ?? (dist / 8.5).round();
            if (decoded.isNotEmpty) {
              setState(() {
                _routePoints = decoded;
                _routeProgressIndex = 0;
                _passedRoutePoints = [];
                _remainingRoutePoints = List<LatLng>.from(decoded);
                _remainingDistanceMeters = dist;
                _remainingDurationSeconds = dur;
                if (_totalTripDistanceMeters <= 1.0 || dist > _totalTripDistanceMeters) {
                  _totalTripDistanceMeters = dist > 0 ? dist : 1000.0;
                }
                _isRerouting = false;
              });
              _updateRouteProgress(_currentPilotLatLng);
              _updateCameraView();
              return;
            }
          }
        }
      } catch (osrmErr) {
        debugPrint('[PilotNavigation] OSRM fallback note: $osrmErr');
      }
    }

    // Fallback: Direct line interpolation
    if (_routePoints.isEmpty) {
      setState(() {
        _routePoints = [origin, destination];
        _routeProgressIndex = 0;
        _passedRoutePoints = [];
        _remainingRoutePoints = [origin, destination];
        _remainingDistanceMeters = NavigationEngine.distanceBetweenMeters(origin, destination);
        _remainingDurationSeconds = (_remainingDistanceMeters / 10).round();
        _isRerouting = false;
      });
      _updateRouteProgress(_currentPilotLatLng);
    }
  }

  void _startLiveGpsTracking() async {
    // Listen to real GPS location updates from device hardware with high accuracy
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[PILOT GPS] Location service is disabled on device');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      // Initial immediate fix so marker immediately displays at real GPS position without waiting
      try {
        final initialPos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 4),
        );
        _onNewPosition(initialPos);
      } catch (e) {
        debugPrint('[PILOT GPS] Initial GPS fix note: $e');
      }

      final locationSettings = defaultTargetPlatform == TargetPlatform.android
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 0,
              forceLocationManager: false,
              intervalDuration: const Duration(milliseconds: 1000),
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 1,
            );

      _positionSub = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen((Position pos) {
        _onNewPosition(pos);
      });
    } catch (e) {
      debugPrint('[PILOT GPS] GPS stream error: $e');
    }
  }

  void _onNewPosition(Position pos) {
    if (!mounted) return;

    final rawPos = LatLng(pos.latitude, pos.longitude);

    // Reject null / impossible / out-of-range coordinates
    if (rawPos.latitude < -90 ||
        rawPos.latitude > 90 ||
        rawPos.longitude < -180 ||
        rawPos.longitude > 180 ||
        (rawPos.latitude == 0.0 && rawPos.longitude == 0.0)) {
      return;
    }

    // Feed real GPS reading into the 60 FPS Smooth Marker Animator
    // This applies accuracy filtering, stationary drift suppression, shortest-arc heading rotation,
    // and road polyline attachment without manual teleportation.
    _markerAnimator.updateTarget(
      position: rawPos,
      heading: pos.heading,
      speedMps: pos.speed,
      accuracyMeters: pos.accuracy,
      timestampMs: pos.timestamp.millisecondsSinceEpoch,
      routeForSnapping: _routePoints,
    );

    // Sync validated location data to BookingManager singleton for background synchronization
    final remainingDistStr = NavigationEngine.formatTripDistance(_remainingDistanceMeters);
    final etaStr = NavigationEngine.formatDurationMinutes(_remainingDurationSeconds);
    final effectiveHeading = _markerAnimator.currentHeading;
    final effectiveSpeed = _markerAnimator.currentSpeedKmh;

    BookingManager().updateDriverLocation(
      rawPos,
      heading: effectiveHeading,
      speed: effectiveSpeed,
      accuracy: pos.accuracy,
      eta: etaStr,
      remainingDistance: remainingDistStr,
      navigationStatus: _isDestinationReached ? 'arrived' : (_isRerouting ? 'rerouting' : 'navigating'),
    );

    // Check Destination or Pickup Arrival (< 50m)
    if (_navigationStage == 'to_pickup') {
      if (NavigationEngine.isDestinationReached(rawPos, _destinationLatLng, thresholdMeters: 50.0)) {
        if (!_isPickupReached) {
          _handlePickupReached();
        }
      }
    } else {
      if (NavigationEngine.isDestinationReached(rawPos, _destinationLatLng, thresholdMeters: 50.0)) {
        if (!_isDestinationReached) {
          _handleDestinationReached();
        }
        return;
      }
    }

    // Step progression
    _progressNavigationStep(rawPos);

    // Off-Route Detection (> 35m) & Wrong-Direction Detection (> 110 deg against route flow)
    final bool offRoute = NavigationEngine.isOffRoute(rawPos, _routePoints, thresholdMeters: 35.0);
    final bool wrongDirection = NavigationEngine.isWrongDirection(
      rawPos,
      effectiveHeading,
      _routePoints,
      speedKmh: effectiveSpeed,
    );

    if (offRoute || wrongDirection) {
      _consecutiveOffRouteCount++;
      if (_consecutiveOffRouteCount >= 2 && !_isRerouting) {
        final reason = wrongDirection ? 'Wrong direction' : 'Different road';
        _triggerReroute(rawPos, reason: reason);
      }
    } else {
      _consecutiveOffRouteCount = 0;
    }

    // Smoothly update camera to follow vehicle on new GPS fix
    _maybeUpdateCameraDriverFollow(rawPos, effectiveHeading);
  }

  void _progressNavigationStep(LatLng currentPos) {
    if (_steps.isEmpty || _currentStepIndex >= _steps.length) return;

    final currentStep = _steps[_currentStepIndex];
    final distToStepEnd = NavigationEngine.distanceBetweenMeters(currentPos, currentStep.endLocation);

    if (distToStepEnd < 30.0) {
      if (_currentStepIndex + 1 < _steps.length) {
        setState(() {
          _currentStepIndex++;
        });
        _playTurnChime();
      }
    }

    // Update remaining distance
    final distToDest = NavigationEngine.distanceBetweenMeters(currentPos, _destinationLatLng);
    setState(() {
      _remainingDistanceMeters = distToDest;
      _remainingDurationSeconds = math.max(60, (distToDest / 8.5).round()); // ~30 km/h avg speed
    });
  }

  void _triggerReroute(LatLng offPos, {String reason = 'Rerouting'}) async {
    setState(() {
      _isRerouting = true;
      _rerouteReason = reason;
    });
    _playTurnChime();
    debugPrint('[PilotNavigation] Deviation detected ($reason)! Auto-recalculating route from $offPos...');
    _emitLiveLocationToCustomer(); // Alert customer app of rerouting in-progress
    await _requestRouteFromApi(offPos, _destinationLatLng);
    _consecutiveOffRouteCount = 0;
    _emitLiveLocationToCustomer(); // Broadcast updated distance and ETA
  }

  void _handlePickupReached() {
    WakeLockService.wakeUpScreen();
    _playTurnChime();
    setState(() {
      _isPickupReached = true;
      _remainingDistanceMeters = 0.0;
      _remainingDurationSeconds = 0;
    });
    BookingManager().driverArrived();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Arrived at Customer Pickup! Tap START RIDE to enter OTP and proceed to destination.'),
        backgroundColor: Color(0xFF16A34A),
        duration: Duration(seconds: 4),
      ),
    );
  }

  void _startRideFromPickup() async {
    _startForegroundKeepAlive();
    if (_outwardDropLatLng == null || (_outwardDropLatLng!.latitude == 0.0 && _outwardDropLatLng!.longitude == 0.0)) {
      await _reloadBookingCoordinates();
    }

    if (_outwardDropLatLng == null || (_outwardDropLatLng!.latitude == 0.0 && _outwardDropLatLng!.longitude == 0.0)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Cannot navigate: Customer delivery pin is not configured.'),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
      }
      return;
    }

    setState(() {
      _isPickupReached = false;
      _isDestinationReached = false;
      _navigationStage = 'to_drop';
      _destinationLatLng = _outwardDropLatLng!;
      _destinationAddress = _outwardDropAddress;
      _routePoints = [];
      _passedRoutePoints = [];
      _remainingRoutePoints = [];
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ride Started! Navigating to: $_destinationAddress'),
        backgroundColor: const Color(0xFF16A34A),
        duration: const Duration(seconds: 3),
      ),
    );

    await _requestRouteFromApi(_currentPilotLatLng, _destinationLatLng);
  }

  void _showStartTripOtpDialog() {
    _startOtpController.clear();
    setState(() => _otpError = '');
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isParcel = widget.booking['serviceType'] == 'parcel';
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(
              isParcel ? 'Enter Sender OTP' : 'Enter Customer OTP',
              style: GoogleFonts.hankenGrotesk(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isParcel
                      ? 'Ask the sender for the 4-digit pickup OTP'
                      : 'Ask the customer for the 4-digit ride start OTP',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _startOtpController,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.robotoMono(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 8),
                  decoration: InputDecoration(
                    hintText: '• • • •',
                    errorText: _otpError.isNotEmpty ? _otpError : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    counterText: '',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  final otp = _startOtpController.text.trim();
                  if (otp.length != 4) {
                    setDialogState(() {
                      _otpError = 'Please enter a valid 4-digit OTP';
                    });
                    return;
                  }
                  final bId = widget.booking['bookingId']?.toString() ??
                      widget.booking['id']?.toString() ??
                      widget.booking['_id']?.toString();
                  final res = await BookingManager().verifyStartOtp(otp: otp, bookingId: bId);
                  if (res['success'] == true) {
                    Navigator.pop(ctx);
                    _startRideFromPickup();
                  } else {
                    setDialogState(() {
                      _otpError = res['error'] ?? 'Invalid OTP. Ask customer again.';
                    });
                  }
                },
                child: Text(isParcel ? 'Verify & Start Delivery' : 'Verify & Start Ride'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showParcelDeliveryOtpDialog() {
    _parcelDeliveryOtpController.clear();
    setState(() {
      _otpError = '';
      _isVerifyingDeliveryOtp = false;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final enteredDigits = _parcelDeliveryOtpController.text.trim();
          final isOtpComplete = enteredDigits.length == 4;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.inventory_2_rounded, color: Color(0xFF16A34A), size: 24),
                const SizedBox(width: 8),
                Text(
                  'Verify Delivery OTP',
                  style: GoogleFonts.hankenGrotesk(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ask the customer for the 4-digit delivery OTP shown on their screen to complete delivery.',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _parcelDeliveryOtpController,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.robotoMono(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 12),
                  onChanged: (val) {
                    setDialogState(() {
                      if (_otpError.isNotEmpty) _otpError = '';
                    });
                  },
                  decoration: InputDecoration(
                    hintText: '• • • •',
                    hintStyle: const TextStyle(letterSpacing: 10),
                    errorText: _otpError.isNotEmpty ? _otpError : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    counterText: '',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: _isVerifyingDeliveryOtp ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF16A34A).withOpacity(0.5),
                  disabledForegroundColor: Colors.white70,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
                onPressed: (_isVerifyingDeliveryOtp || !isOtpComplete)
                    ? null
                    : () async {
                        final entered = _parcelDeliveryOtpController.text.trim();
                        if (entered.length != 4) {
                          setDialogState(() {
                            _otpError = 'Please enter all 4 digits of the OTP';
                          });
                          return;
                        }
                        setDialogState(() {
                          _isVerifyingDeliveryOtp = true;
                          _otpError = '';
                        });

                        final bookingId = widget.booking['bookingId']?.toString() ??
                            widget.booking['id']?.toString() ??
                            widget.booking['_id']?.toString() ?? '';

                        final result = await BookingManager().verifyParcelDeliveryOtp(
                          bookingId: bookingId,
                          otp: entered,
                        );

                        if (result['success'] == true) {
                          Navigator.pop(ctx);
                          _finishAndCompleteRide();
                        } else {
                          setDialogState(() {
                            _isVerifyingDeliveryOtp = false;
                            _otpError = result['error'] ?? 'Invalid OTP. Please try again.';
                          });
                        }
                      },
                child: _isVerifyingDeliveryOtp
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Verify & Complete'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _handleDestinationReached() {
    WakeLockService.wakeUpScreen();
    _playTurnChime();

    if (_isRoundTrip && _currentLeg == 'outward') {
      setState(() {
        _currentLeg = 'waiting';
        _isDestinationReached = true;
        _remainingDistanceMeters = 0.0;
        _remainingDurationSeconds = 0;
      });

      BookingManager().driverArrivedAtDestination();

      _roundTripWaitTimer?.cancel();
      _roundTripWaitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _waitingDurationSeconds++;
          final chargeableMinutes = math.max(0, (_waitingDurationSeconds ~/ 60) - _freeWaitingMinutes);
          _additionalWaitingCharge = (chargeableMinutes * _waitingRatePerMinute).toDouble();
        });
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Arrived at Destination! Leg 1 completed. Waiting timer active.'),
          backgroundColor: Color(0xFF7E22CE),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    setState(() {
      _isDestinationReached = true;
      _remainingDistanceMeters = 0.0;
      _remainingDurationSeconds = 0;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isRoundTrip ? 'Return destination reached! Please complete the round trip.' : 'Destination reached! Please complete the ride.'),
        backgroundColor: const Color(0xFF16A34A),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _startReturnLegJourney() async {
    _roundTripWaitTimer?.cancel();
    setState(() {
      _currentLeg = 'return';
      _isDestinationReached = false;
      _destinationLatLng = _returnDropLatLng ?? _currentPilotLatLng;
      _destinationAddress = _returnDropAddress;
    });

    BookingManager().driverStartReturnJourney();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Starting Return Journey (Leg 2)... Navigation active.'),
        backgroundColor: Color(0xFF16A34A),
        duration: Duration(seconds: 3),
      ),
    );

    await _requestRouteFromApi(_currentPilotLatLng, _destinationLatLng);
  }

  void _completeRoundTripJourney() {
    _roundTripWaitTimer?.cancel();
    WakeLockService.enableAutoPip(false);
    WakeLockService.setPipModeListener(null);
    BookingManager().completeRoundTrip(additionalWaitingCharge: _additionalWaitingCharge);
    widget.onRideCompleted();
    Navigator.of(context).pop();
  }

  void _playTurnChime() {
    if (_isMuted) return;
    try {
      FlutterRingtonePlayer().play(
        android: AndroidSounds.notification,
        ios: IosSounds.glass,
        looping: false,
        volume: 0.8,
      );
    } catch (_) {}
  }

  void _startSocketBroadcastLoop() {
    _socketBroadcastTimer?.cancel();
    _socketBroadcastTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _emitLiveLocationToCustomer();
    });
  }

  void _emitLiveLocationToCustomer() {
    final bookingId = widget.booking['bookingId']?.toString() ??
        widget.booking['id']?.toString() ??
        widget.booking['_id']?.toString() ??
        'BK_${DateTime.now().millisecondsSinceEpoch}';
    final pilotId = widget.booking['driverId']?.toString() ??
        widget.booking['pilotId']?.toString() ??
        BookingManager().effectiveUid;

    final remainingDistStr = NavigationEngine.formatTripDistance(_remainingDistanceMeters);
    final etaStr = NavigationEngine.formatDurationMinutes(_remainingDurationSeconds);

    final vType = widget.booking['vehicleType']?.toString() ??
        widget.booking['vehicle']?.toString() ??
        BookingManager().driverSelectedVehicle;

    SocketService().emitRideLocation(
      rideId: bookingId,
      pilotId: pilotId,
      vehicleType: vType,
      latitude: _currentPilotLatLng.latitude,
      longitude: _currentPilotLatLng.longitude,
      heading: _currentHeading,
      speed: _currentSpeedKmh,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      remainingDistance: remainingDistStr,
      eta: etaStr,
      navigationStatus: _isDestinationReached ? 'arrived' : (_isRerouting ? 'rerouting' : 'navigating'),
    );
  }

  static LatLng _computeLookahead(LatLng origin, double bearingDeg, double distanceMeters) {
    if (distanceMeters <= 0.0) return origin;
    const double earthRadius = 6371000.0;
    final double radBearing = bearingDeg * (math.pi / 180.0);
    final double radLat = origin.latitude * (math.pi / 180.0);
    final double radLng = origin.longitude * (math.pi / 180.0);
    final double distRatio = distanceMeters / earthRadius;

    final double newLat = math.asin(
      math.sin(radLat) * math.cos(distRatio) +
      math.cos(radLat) * math.sin(distRatio) * math.cos(radBearing),
    );
    final double newLng = radLng + math.atan2(
      math.sin(radBearing) * math.sin(distRatio) * math.cos(radLat),
      math.cos(distRatio) - math.sin(radLat) * math.sin(newLat),
    );
    return LatLng(newLat * (180.0 / math.pi), newLng * (180.0 / math.pi));
  }

  void _maybeUpdateCameraDriverFollow(LatLng pos, double heading) {
    if (!_isDriverFollowing || _isOverviewMode || _mapController == null) return;
    if (_isUserDraggingMap) return;

    final now = DateTime.now();
    // Maintain heading stability: if stopped or very slow, keep previous valid heading to prevent map spin
    if (_currentSpeedKmh > 2.0 || _lastValidHeading == 0.0) {
      if (heading != 0.0) {
        _lastValidHeading = heading;
      }
    }

    final double effectiveHeading = _lastValidHeading != 0.0 ? _lastValidHeading : heading;

    // Throttle native camera animations to ~600ms or when displacement >= 2.5m
    // This allows smooth native transitions without animation aborts or platform-channel congestion
    final elapsedMs = _lastCameraUpdateTime == null
        ? 999999
        : now.difference(_lastCameraUpdateTime!).inMilliseconds;
    final distMeters = _lastCameraUpdatePos == null
        ? 999999.0
        : NavigationEngine.distanceBetweenMeters(_lastCameraUpdatePos!, pos);

    if (elapsedMs >= 600 || distMeters >= 2.5) {
      _lastCameraUpdateTime = now;
      _lastCameraUpdatePos = pos;
      _updateCameraDriverFollow(pos, effectiveHeading);
    }
  }

  void _updateCameraDriverFollow(LatLng pos, double heading) {
    if (_mapController == null) return;
    // Position vehicle in lower-middle area of screen with upcoming route clearly ahead
    final targetPos = _computeLookahead(pos, heading, 22.0);
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: targetPos,
          zoom: 18.0,
          tilt: 45.0,
          bearing: heading,
        ),
      ),
    );
  }

  void _updateCameraView() {
    if (_mapController == null || _routePoints.isEmpty) return;
    if (_isDriverFollowing && !_isOverviewMode) {
      _updateCameraDriverFollow(_currentPilotLatLng, _currentHeading);
    } else {
      _fitWholeRoute();
    }
  }

  void _fitWholeRoute() {
    if (_mapController == null || _routePoints.isEmpty) return;

    double minLat = _routePoints.first.latitude;
    double maxLat = _routePoints.first.latitude;
    double minLng = _routePoints.first.longitude;
    double maxLng = _routePoints.first.longitude;

    for (var p in _routePoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        60.0,
      ),
    );
  }

  void _finishAndCompleteRide() {
    WakeLockService.enableAutoPip(false);
    WakeLockService.setPipModeListener(null);
    BookingManager().completeRide();
    widget.onRideCompleted();
    Navigator.of(context).pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      // Show StayDriv Floating Mini Screen (movable logo & navigation bubble) when minimized during navigation
      final active = widget.booking;
      final custName = (active['passengerName'] ?? 'Customer').toString();
      final drop = (active['dropAddress'] ?? active['drop'] ?? _destinationAddress).toString();
      final status = (active['status'] ?? 'started').toString();
      FloatingWidgetService.show(
        role: 'Pilot',
        status: status,
        title: 'StayDriv Navigation',
        subtitle: drop.isNotEmpty ? 'Drop: $drop' : 'Navigating with $custName',
        isPilot: true,
      );
    } else if (state == AppLifecycleState.resumed) {
      FloatingWidgetService.hide();
    }
    super.didChangeAppLifecycleState(state);
  }

  @override
  void dispose() {
    FloatingWidgetService.hide();
    WidgetsBinding.instance.removeObserver(this);
    WakeLockService.enableAutoPip(false);
    WakeLockService.setPipModeListener(null);
    _roundTripWaitTimer?.cancel();
    _markerAnimator.dispose();
    _positionSub?.cancel();
    _socketBroadcastTimer?.cancel();
    WakeLockService.stopForegroundService();
    WakeLockService.releaseWakeLock();
    super.dispose();
  }

  Set<Polyline> _buildNavigationPolylines() {
    final polylines = <Polyline>{};

    // 1. PASSED / TRAVELLED ROUTE (BLACK) - behind the moving pilot vehicle
    if (_passedRoutePoints.length >= 2) {
      // Outer Charcoal Casing for road contrast
      polylines.add(
        Polyline(
          polylineId: const PolylineId('nav_route_passed_casing'),
          points: _passedRoutePoints,
          color: const Color(0xFF1E1E1E),
          width: 14,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          zIndex: 1,
        ),
      );
      // Inner Deep Black Core (#000000)
      polylines.add(
        Polyline(
          polylineId: const PolylineId('nav_route_passed_core'),
          points: _passedRoutePoints,
          color: Colors.black,
          width: 9,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          zIndex: 2,
        ),
      );
    }

    // 2. REMAINING / UPCOMING ROUTE (BLUE) - in front of the moving pilot vehicle
    if (_remainingRoutePoints.length >= 2) {
      // Outer Navy Casing
      polylines.add(
        Polyline(
          polylineId: const PolylineId('nav_route_remaining_casing'),
          points: _remainingRoutePoints,
          color: const Color(0xFF1557B0),
          width: 14,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          zIndex: 3,
        ),
      );
      // Inner Vibrant Google Maps Navigation Blue Core (#1A73E8)
      polylines.add(
        Polyline(
          polylineId: const PolylineId('nav_route_remaining_inner'),
          points: _remainingRoutePoints,
          color: const Color(0xFF1A73E8),
          width: 9,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          zIndex: 4,
        ),
      );
    } else if (_routePoints.isNotEmpty) {
      // Fallback: If not yet moving, full route is vibrant blue
      polylines.add(
        Polyline(
          polylineId: const PolylineId('nav_route_casing'),
          points: _routePoints,
          color: const Color(0xFF1557B0),
          width: 14,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          zIndex: 1,
        ),
      );
      polylines.add(
        Polyline(
          polylineId: const PolylineId('nav_route_inner'),
          points: _routePoints,
          color: const Color(0xFF1A73E8),
          width: 9,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          zIndex: 2,
        ),
      );
    }

    return polylines;
  }

  Set<Marker> _buildNavigationMarkers() {
    final markers = <Marker>{};

    // 1. Road-snapped Pilot Vehicle Marker with bearing & speed
    markers.add(
      Marker(
        markerId: const MarkerId('pilot_vehicle'),
        position: _currentPilotLatLng,
        rotation: _currentHeading,
        flat: true,
        anchor: const Offset(0.5, 0.5),
        zIndex: 100.0,
        icon: _carMarkerIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(
          title: '${widget.booking['vehicleType'] ?? 'Pilot'} Vehicle',
          snippet: '${_currentSpeedKmh.toStringAsFixed(0)} km/h',
        ),
      ),
    );

    final bool isFoodOrder = widget.booking['isFoodOrder'] == true ||
        widget.booking['serviceType'] == 'food';

    if (isFoodOrder) {
      // 2. Exact Restaurant Pickup Pin
      if (_pickupLatLng != null && (_pickupLatLng!.latitude != 0.0 || _pickupLatLng!.longitude != 0.0)) {
        final restName = widget.booking['restaurantName'] ?? widget.booking['pickupLocationName'] ?? 'Restaurant';
        markers.add(
          Marker(
            markerId: const MarkerId('restaurant_pickup_pin'),
            position: _pickupLatLng!,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              _navigationStage == 'to_pickup' ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueYellow,
            ),
            zIndex: _navigationStage == 'to_pickup' ? 95.0 : 80.0,
            infoWindow: InfoWindow(
              title: '🏬 $restName (Pickup)',
              snippet: _pickupAddress,
            ),
          ),
        );
      }

      // 3. Exact Customer Delivery Pin
      if (_outwardDropLatLng != null && (_outwardDropLatLng!.latitude != 0.0 || _outwardDropLatLng!.longitude != 0.0)) {
        final custName = widget.booking['customerName'] ?? widget.booking['passengerName'] ?? 'Customer';
        markers.add(
          Marker(
            markerId: const MarkerId('customer_delivery_pin'),
            position: _outwardDropLatLng!,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              _navigationStage == 'to_drop' ? BitmapDescriptor.hueRed : BitmapDescriptor.hueGreen,
            ),
            zIndex: _navigationStage == 'to_drop' ? 95.0 : 80.0,
            infoWindow: InfoWindow(
              title: '📍 $custName (Delivery)',
              snippet: _outwardDropAddress,
            ),
          ),
        );
      }
    } else {
      // Standard Ride Destination or Pickup Marker
      markers.add(
        Marker(
          markerId: const MarkerId('destination_flag'),
          position: _destinationLatLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            _navigationStage == 'to_pickup'
                ? BitmapDescriptor.hueGreen
                : BitmapDescriptor.hueRed,
          ),
          infoWindow: InfoWindow(
            title: _navigationStage == 'to_pickup'
                ? 'Customer Pickup: $_destinationAddress'
                : (_isRoundTrip && _currentLeg == 'return' ? 'Return: $_destinationAddress' : 'Destination: $_destinationAddress'),
          ),
        ),
      );
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final nextStep = _steps.isNotEmpty && _currentStepIndex < _steps.length
        ? _steps[_currentStepIndex]
        : null;
    final thenStep = _steps.isNotEmpty && _currentStepIndex + 1 < _steps.length
        ? _steps[_currentStepIndex + 1]
        : null;

    final distanceToNextManeuver = nextStep != null
        ? NavigationEngine.distanceBetweenMeters(_currentPilotLatLng, nextStep.endLocation)
        : _remainingDistanceMeters;

    final progressRatio = _totalTripDistanceMeters > 0
        ? math.max(0.0, math.min(1.0, 1.0 - (_remainingDistanceMeters / _totalTripDistanceMeters)))
        : 0.0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. GOOGLE MAP INTERACTION WITH USER TOUCH LISTENER
          Listener(
            onPointerDown: (_) {
              _isUserDraggingMap = true;
            },
            onPointerMove: (_) {
              _isUserDraggingMap = true;
              if (_isDriverFollowing) {
                setState(() => _isDriverFollowing = false);
              }
            },
            onPointerUp: (_) {
              _isUserDraggingMap = false;
            },
            onPointerCancel: (_) {
              _isUserDraggingMap = false;
            },
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _currentPilotLatLng,
                zoom: 17.5,
                tilt: 45.0,
                bearing: _currentHeading,
              ),
              onMapCreated: (controller) {
                _mapController = controller;
                _updateCameraView();
              },
              onCameraMoveStarted: () {
                // Only disengage follow mode if the user is physically touching and dragging the map
                if (_isUserDraggingMap && _isDriverFollowing) {
                  setState(() => _isDriverFollowing = false);
                }
              },
              polylines: _buildNavigationPolylines(),
              markers: _buildNavigationMarkers(),
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              trafficEnabled: true,
            ),
          ),

          // 2. PiP Mode Streamlined Overlay vs Full Navigation HUD
          if (_isInPipMode)
            _buildPipOverlay(nextStep, distanceToNextManeuver)
          else ...[
            // TOP TURN-BY-TURN NAVIGATION BANNER (Signature Google Maps Green)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isPickupLocationMissing)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFB00020),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3)),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Customer pickup GPS coordinates unavailable. Tap to reload.',
                                  style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: _isReloadingCoordinates ? null : _reloadBookingCoordinates,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFFB00020),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: _isReloadingCoordinates
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFB00020)))
                                    : const Text('Retry', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                      _buildGoogleTurnBanner(nextStep, distanceToNextManeuver),
                      if (thenStep != null) _buildThenPreviewBanner(thenStep),
                    ],
                  ),
                ),
              ),
            ),

            // 3. FLOATING SPEEDOMETER BADGE (Bottom Left)
            Positioned(
              left: 16,
              bottom: 180,
              child: _buildSpeedometerBadge(),
            ),

            // 4. FLOATING MAP ACTION BUTTONS (Bottom Right: Recenter, Overview, Sound)
            Positioned(
              right: 16,
              bottom: 180,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_isDriverFollowing)
                    FloatingActionButton.small(
                      heroTag: 'recenter_btn',
                      backgroundColor: Colors.white,
                      onPressed: () {
                        setState(() {
                          _isDriverFollowing = true;
                          _isOverviewMode = false;
                        });
                        _updateCameraDriverFollow(_currentPilotLatLng, _currentHeading);
                      },
                      child: const Icon(Icons.my_location_rounded, color: Color(0xFF1E3A8A)),
                    ),
                  const SizedBox(height: 10),
                  FloatingActionButton.small(
                    heroTag: 'overview_btn',
                    backgroundColor: Colors.white,
                    onPressed: () {
                      setState(() {
                        _isOverviewMode = !_isOverviewMode;
                        _isDriverFollowing = !_isOverviewMode;
                      });
                      if (_isOverviewMode) {
                        _fitWholeRoute();
                      } else {
                        _updateCameraDriverFollow(_currentPilotLatLng, _currentHeading);
                      }
                    },
                    child: Icon(
                      _isOverviewMode ? Icons.navigation_rounded : Icons.map_rounded,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FloatingActionButton.small(
                    heroTag: 'sound_btn',
                    backgroundColor: Colors.white,
                    onPressed: () {
                      setState(() => _isMuted = !_isMuted);
                    },
                    child: Icon(
                      _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      color: _isMuted ? Colors.red : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),

            // 5. BOTTOM NAVIGATION HUD (Google Navigation Bottom Sheet)
            Align(
              alignment: Alignment.bottomCenter,
              child: _buildBottomNavigationHud(progressRatio),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPipOverlay(NavigationStep? step, double distToManeuver) {
    final bool isArrived = _isDestinationReached;
    final iconData = isArrived
        ? Icons.check_circle_rounded
        : (_isRerouting
            ? Icons.sync_rounded
            : (step != null ? NavigationEngine.getManeuverIcon(step.maneuver) : Icons.straight_rounded));
    final titleText = isArrived
        ? 'Arrived'
        : (_isRerouting ? '$_rerouteReason...' : NavigationEngine.formatDistanceToManeuver(distToManeuver));
    final instruction = isArrived ? 'Destination reached' : (step?.instruction ?? 'Drive along route');
    final etaStr = NavigationEngine.formatDurationMinutes(_remainingDurationSeconds);
    final distStr = NavigationEngine.formatTripDistance(_remainingDistanceMeters);

    return Positioned.fill(
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Compact Top Turn Banner
            Container(
              margin: const EdgeInsets.all(6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _isRerouting ? const Color(0xFFB45309) : const Color(0xFF0F5132),
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 2)),
                ],
              ),
              child: Row(
                children: [
                  Icon(iconData, color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          titleText,
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          instruction,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Compact Bottom ETA Pill
            Container(
              margin: const EdgeInsets.all(6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 2)),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    etaStr,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF22C55E),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(width: 4, height: 4, decoration: const BoxDecoration(color: Colors.white38, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Text(
                    distStr,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleTurnBanner(NavigationStep? step, double distToManeuver) {
    final bool isArrived = _isDestinationReached;
    final Color bannerColor = isArrived
        ? const Color(0xFF15803D)
        : (_isRerouting ? const Color(0xFFB45309) : const Color(0xFF0F5132));

    final iconData = isArrived
        ? Icons.check_circle_rounded
        : (_isRerouting
            ? Icons.sync_rounded
            : (step != null ? NavigationEngine.getManeuverIcon(step.maneuver) : Icons.straight_rounded));

    final titleText = isArrived
        ? 'Destination Reached'
        : (_isRerouting ? '$_rerouteReason...' : NavigationEngine.formatDistanceToManeuver(distToManeuver));

    final instructionText = isArrived
        ? 'You have arrived at $_destinationAddress'
        : (step != null ? step.instruction : 'Proceed to destination route');

    return Container(
      decoration: BoxDecoration(
        color: bannerColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(iconData, color: Colors.white, size: 36),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isRoundTrip) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _currentLeg == 'waiting'
                          ? 'LEG 1 COMPLETE • WAITING'
                          : (_currentLeg == 'return' ? 'ROUND TRIP • LEG 2 (RETURN)' : 'ROUND TRIP • LEG 1 (OUTWARD)'),
                      style: GoogleFonts.robotoMono(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                  ),
                ],
                Text(
                  titleText,
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  instructionText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.92),
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThenPreviewBanner(NavigationStep thenStep) {
    return Container(
      margin: const EdgeInsets.only(top: 4, left: 16, right: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0B3B24),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 0.5),
      ),
      child: Row(
        children: [
          Text(
            'Then',
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF4ADE80)),
          ),
          const SizedBox(width: 8),
          Icon(NavigationEngine.getManeuverIcon(thenStep.maneuver), color: Colors.white70, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              thenStep.instruction,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedometerBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 3)),
        ],
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _currentSpeedKmh.toInt().toString(),
            style: GoogleFonts.hankenGrotesk(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Colors.black87,
            ),
          ),
          Text(
            'km/h',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigationHud(double progressRatio) {
    final etaClock = NavigationEngine.formatEtaClockTime(_remainingDurationSeconds);
    final durationText = NavigationEngine.formatDurationMinutes(_remainingDurationSeconds);
    final distanceText = NavigationEngine.formatTripDistance(_remainingDistanceMeters);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // Trip metrics row
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                durationText,
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF15803D), // Navigation Green
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '($distanceText)',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'ETA',
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                  Text(
                    etaClock,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Linear route progress indicator
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressRatio,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF16A34A)),
              minHeight: 5,
            ),
          ),

          const SizedBox(height: 10),

          // Destination Address snippet
          Row(
            children: [
              const Icon(Icons.location_on_rounded, color: Colors.redAccent, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _destinationAddress,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          const SizedBox(height: 16),

          if (_isRoundTrip && _currentLeg == 'waiting') ...[
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFAF5FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD8B4FE)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFF7E22CE),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.timer_outlined, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Waiting: ${(_waitingDurationSeconds ~/ 60).toString().padLeft(2, '0')}:${(_waitingDurationSeconds % 60).toString().padLeft(2, '0')}',
                          style: GoogleFonts.hankenGrotesk(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF581C87)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _additionalWaitingCharge > 0
                              ? 'Waiting charges accrued: ₹${_additionalWaitingCharge.toStringAsFixed(0)} (₹2.5/min)'
                              : 'Free waiting time active (first 15 mins free)',
                          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF7E22CE)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _callCustomerMasked,
                    icon: const Icon(Icons.phone_in_talk_rounded, color: Color(0xFF7E22CE), size: 20),
                    label: Text(
                      'Call',
                      style: GoogleFonts.hankenGrotesk(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF7E22CE)),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF7E22CE), width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _startReturnLegJourney,
                      icon: const Icon(Icons.u_turn_left_rounded, size: 22),
                      label: Text(
                        'START RETURN (LEG 2)',
                        style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7E22CE),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            Builder(
              builder: (context) {
                final bool isParcel = widget.booking['serviceType'] == 'parcel' ||
                    (widget.booking['vehicle']?.toString().toLowerCase().contains('parcel') ?? false);
                final bool isFoodOrder = widget.booking['isFoodOrder'] == true ||
                    widget.booking['serviceType'] == 'food';

                if (_navigationStage == 'to_pickup') {
                  return Row(
                    children: [
                      SizedBox(
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: isFoodOrder ? _callRestaurantMasked : _callCustomerMasked,
                          icon: const Icon(Icons.phone_in_talk_rounded, color: Color(0xFF16A34A), size: 20),
                          label: Text(
                            isFoodOrder ? 'Restaurant' : 'Call',
                            style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF16A34A)),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF16A34A), width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              if (!_isPickupReached) {
                                _handlePickupReached();
                              } else {
                                if (isFoodOrder) {
                                  _startRideFromPickup();
                                } else {
                                  _showStartTripOtpDialog();
                                }
                              }
                            },
                            icon: Icon(_isPickupReached ? Icons.play_arrow_rounded : Icons.check_circle_rounded, size: 22),
                            label: Text(
                              isFoodOrder
                                  ? (_isPickupReached ? 'FOOD COLLECTED (PROCEED TO DROP)' : 'ARRIVED AT RESTAURANT')
                                  : (_isPickupReached ? 'START RIDE (ENTER OTP)' : 'I HAVE ARRIVED AT PICKUP'),
                              style: GoogleFonts.hankenGrotesk(fontSize: 12.5, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF16A34A),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 3,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }

                // Stage is to_drop or to_return
                return Row(
                  children: [
                    SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _callCustomerMasked,
                        icon: const Icon(Icons.phone_in_talk_rounded, color: Color(0xFF16A34A), size: 20),
                        label: Text(
                          'Call',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF16A34A),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF16A34A), width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () {
                            if (isParcel) {
                              _showParcelDeliveryOtpDialog();
                            } else if (_isRoundTrip && _currentLeg == 'return') {
                              if (_isDestinationReached) {
                                _completeRoundTripJourney();
                              } else {
                                _showManualCompleteConfirmDialog();
                              }
                            } else if (_isRoundTrip && _currentLeg == 'outward') {
                              if (_isDestinationReached) {
                                _handleDestinationReached();
                              } else {
                                _showManualCompleteConfirmDialog();
                              }
                            } else {
                              if (_isDestinationReached) {
                                _finishAndCompleteRide();
                              } else {
                                _showManualCompleteConfirmDialog();
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: (isParcel || _isDestinationReached)
                                ? const Color(0xFF16A34A)
                                : (_isRoundTrip && _currentLeg == 'return' ? const Color(0xFF7E22CE) : const Color(0xFFDC2626)),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 3,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isParcel
                                    ? Icons.verified_rounded
                                    : (_isDestinationReached ? Icons.check_circle_rounded : Icons.flag_rounded),
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isParcel
                                    ? 'VERIFY DELIVERY OTP'
                                    : (_isDestinationReached
                                        ? (_isRoundTrip && _currentLeg == 'return' ? 'COMPLETE ROUND TRIP' : (_isRoundTrip ? 'LEG 1 ARRIVED' : 'COMPLETE'))
                                        : (_isRoundTrip && _currentLeg == 'outward' ? 'ARRIVED (LEG 1)' : 'END TRIP')),
                                style: GoogleFonts.hankenGrotesk(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  void _callCustomerMasked() {
    final bId = widget.booking['bookingId']?.toString() ??
        widget.booking['id']?.toString() ??
        widget.booking['_id']?.toString() ??
        '';
    final customerName = widget.booking['passengerName'] as String? ?? 'Customer';

    if (bId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot initiate call: booking ID missing.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    CallMaskingService().callCustomer(
      bookingId: bId,
      customerName: customerName,
      context: context,
    );
  }

  void _callRestaurantMasked() {
    final bId = widget.booking['bookingId']?.toString() ??
        widget.booking['orderId']?.toString() ??
        widget.booking['id']?.toString() ??
        '';
    final restPhone = widget.booking['restaurantPhone'] as String? ?? '';
    final restName = widget.booking['restaurantName'] as String? ?? 'Restaurant';

    if (restPhone.isNotEmpty) {
      launchUrl(Uri.parse('tel:$restPhone'));
      return;
    }

    if (bId.isNotEmpty) {
      CallMaskingService().callCustomer(
        bookingId: bId,
        customerName: restName,
        context: context,
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Restaurant phone number unavailable.'), backgroundColor: Colors.red),
    );
  }

  void _showManualCompleteConfirmDialog() {
    final bool isOutwardRoundTrip = _isRoundTrip && _currentLeg == 'outward';
    final bool isReturnRoundTrip = _isRoundTrip && _currentLeg == 'return';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          isOutwardRoundTrip ? 'Arrived at Destination (Leg 1)?' : (isReturnRoundTrip ? 'Complete Round Trip Now?' : 'Complete Ride Now?'),
          style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold),
        ),
        content: Text(
          isOutwardRoundTrip
              ? 'Are you at the outward destination? Tapping Confirm will end Leg 1 and start the passenger waiting timer.'
              : (isReturnRoundTrip
                  ? 'Are you at the return destination? Tapping Complete will end the round trip and proceed to fare collection.'
                  : 'Are you at the destination? Tapping Complete will end navigation and proceed to customer fare collection.'),
          style: GoogleFonts.inter(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Continue Navigation', style: GoogleFonts.inter(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              if (isOutwardRoundTrip) {
                _handleDestinationReached();
              } else if (isReturnRoundTrip) {
                _completeRoundTripJourney();
              } else {
                _finishAndCompleteRide();
              }
            },
            child: Text(
              isOutwardRoundTrip ? 'Yes, Leg 1 Arrived' : 'Yes, Complete',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
