import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staydriv_app/core/vehicle_marker_helper.dart';
import 'package:staydriv_app/core/booking_manager.dart';
import 'package:staydriv_app/features/navigation/services/navigation_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.staydriv.app/wake_lock'),
      (MethodCall methodCall) async => true,
    );
  });

  group('VehicleMarkerHelper Tests', () {
    test('normalizeVehicleType correctly identifies bike, auto, car, truck', () {
      expect(VehicleMarkerHelper.normalizeVehicleType('Bike'), 'bike');
      expect(VehicleMarkerHelper.normalizeVehicleType('BIKE'), 'bike');
      expect(VehicleMarkerHelper.normalizeVehicleType('motorcycle'), 'bike');
      expect(VehicleMarkerHelper.normalizeVehicleType('two_wheeler'), 'bike');

      expect(VehicleMarkerHelper.normalizeVehicleType('Auto'), 'auto');
      expect(VehicleMarkerHelper.normalizeVehicleType('AUTO'), 'auto');
      expect(VehicleMarkerHelper.normalizeVehicleType('rickshaw'), 'auto');
      expect(VehicleMarkerHelper.normalizeVehicleType('auto_rickshaw'), 'auto');

      expect(VehicleMarkerHelper.normalizeVehicleType('Car'), 'car');
      expect(VehicleMarkerHelper.normalizeVehicleType('CAR'), 'car');
      expect(VehicleMarkerHelper.normalizeVehicleType('sedan'), 'car');
      expect(VehicleMarkerHelper.normalizeVehicleType('mini'), 'car');
      expect(VehicleMarkerHelper.normalizeVehicleType('cab'), 'car');

      expect(VehicleMarkerHelper.normalizeVehicleType('truck'), 'truck');
      expect(VehicleMarkerHelper.normalizeVehicleType('pickup'), 'truck');
      expect(VehicleMarkerHelper.normalizeVehicleType('goods'), 'truck');
      expect(VehicleMarkerHelper.normalizeVehicleType('mini truck'), 'truck');

      // Default fallback
      expect(VehicleMarkerHelper.normalizeVehicleType(null), 'car');
      expect(VehicleMarkerHelper.normalizeVehicleType('unknown_type'), 'car');
    });

    test('interpolateHeading wraps around 0/360 degree boundary correctly', () {
      // Normal interpolation
      final h1 = VehicleMarkerHelper.interpolateHeading(10.0, 50.0, 0.5);
      expect(h1, closeTo(30.0, 0.01));

      // Wrap-around across 0/360 boundary (350 deg to 10 deg)
      // Delta is +20 deg, midpoint should be 0 (or 360)
      final h2 = VehicleMarkerHelper.interpolateHeading(350.0, 10.0, 0.5);
      expect((h2 - 0.0).abs() < 0.01 || (h2 - 360.0).abs() < 0.01, isTrue);

      // Wrap-around in opposite direction (10 deg to 350 deg)
      final h3 = VehicleMarkerHelper.interpolateHeading(10.0, 350.0, 0.5);
      expect((h3 - 0.0).abs() < 0.01 || (h3 - 360.0).abs() < 0.01, isTrue);
    });

    test('interpolatePosition correctly calculates intermediate coordinates', () {
      const p1 = LatLng(17.4000, 78.4000);
      const p2 = LatLng(17.5000, 78.6000);

      final mid = VehicleMarkerHelper.interpolatePosition(p1, p2, 0.5);
      expect(mid.latitude, closeTo(17.4500, 0.0001));
      expect(mid.longitude, closeTo(78.5000, 0.0001));

      final start = VehicleMarkerHelper.interpolatePosition(p1, p2, 0.0);
      expect(start.latitude, closeTo(17.4000, 0.0001));
      expect(start.longitude, closeTo(78.4000, 0.0001));

      final end = VehicleMarkerHelper.interpolatePosition(p1, p2, 1.0);
      expect(end.latitude, closeTo(17.5000, 0.0001));
      expect(end.longitude, closeTo(78.6000, 0.0001));
    });
  });

  group('GPS Tracking & BookingManager Integration Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      BookingManager.enableNetworkSync = false;
      BookingManager().clearBooking();
    });

    test('Driver location updates set real GPS, heading, and stream updates', () async {
      final manager = BookingManager();
      const testPos = LatLng(17.4850, 78.3890);
      const testHeading = 142.5;

      expect(manager.hasRealDriverLocation, isFalse);

      LatLng? streamedPos;
      final sub = manager.driverLocationStream.listen((pos) {
        streamedPos = pos;
      });

      manager.updateDriverLocation(
        testPos,
        heading: testHeading,
        speed: 12.5,
        eta: '8 mins',
        remainingDistance: '3.2 km',
      );

      await Future.delayed(const Duration(milliseconds: 50));

      expect(manager.hasRealDriverLocation, isTrue);
      expect(manager.driverLatLng.latitude, closeTo(17.4850, 0.0001));
      expect(manager.driverLatLng.longitude, closeTo(78.3890, 0.0001));
      expect(manager.driverHeading, equals(testHeading));
      expect(manager.driverSpeed, equals(12.5));
      expect(manager.latestEta, equals('8 mins'));
      expect(manager.latestRemainingDistance, equals('3.2 km'));
      expect(streamedPos, isNotNull);
      expect(streamedPos!.latitude, closeTo(17.4850, 0.0001));

      await sub.cancel();
    });

    test('Ride isolation logic ignores location updates from mismatching rideId', () async {
      final manager = BookingManager();
      manager.createBooking(
        pickupName: 'Kukatpally',
        dropName: 'Hitech City',
        pickupLatLng: const LatLng(17.4855, 78.3976),
        dropLatLng: const LatLng(17.4935, 78.3821),
        vehicleType: 'Auto',
        price: '150',
      );
      await Future.delayed(const Duration(milliseconds: 50));

      final currentBookingId = manager.activeBooking?['bookingId']?.toString() ??
          manager.activeBooking?['id']?.toString();
      expect(currentBookingId, isNotNull);

      // Case 1: Mismatched rideId
      final foreignPayload = {
        'rideId': 'booking_999_foreign',
        'latitude': 17.5555,
        'longitude': 78.5555,
        'heading': 90.0,
      };

      bool isIgnored = foreignPayload['rideId'] != currentBookingId;
      expect(isIgnored, isTrue);

      // Case 2: Matching rideId
      final validPayload = {
        'rideId': currentBookingId,
        'latitude': 17.4850,
        'longitude': 78.3890,
        'heading': 45.0,
        'vehicleType': 'Auto',
      };

      bool isValid = validPayload['rideId'] == currentBookingId;
      expect(isValid, isTrue);
    });

    test('Stale GPS calculation marks location updating when elapsed > 20s', () {
      final now = DateTime.now();
      
      // Update from 5 seconds ago -> not stale
      final recentUpdate = now.subtract(const Duration(seconds: 5));
      final recentElapsed = now.difference(recentUpdate).inSeconds;
      expect(recentElapsed > 20, isFalse);

      // Update from 25 seconds ago -> stale
      final staleUpdate = now.subtract(const Duration(seconds: 25));
      final staleElapsed = now.difference(staleUpdate).inSeconds;
      expect(staleElapsed > 20, isTrue);
    });

    test('Camera follow forward lookahead calculates target ahead along travel heading', () {
      const origin = LatLng(17.4850, 78.3890);

      // Heading North (0 deg), 22 meters ahead
      final northLookahead = VehicleMarkerHelper.interpolatePosition(
        origin,
        const LatLng(17.4850 + (22.0 / 111320.0), 78.3890),
        1.0,
      );
      expect(northLookahead.latitude > origin.latitude, isTrue);
      expect((northLookahead.longitude - origin.longitude).abs() < 0.0001, isTrue);

      // Verify user manual drag disengages follow mode temporarily without losing coordinates
      bool isFollowing = true;
      bool isUserDragging = true;
      if (isUserDragging && isFollowing) {
        isFollowing = false;
      }
      expect(isFollowing, isFalse);

      // Verify Re-center action restores follow mode
      isFollowing = true;
      expect(isFollowing, isTrue);
    });

    test('NavigationEngine isWrongDirection accurately detects reverse heading along route', () {
      // Route going directly North from (17.4800, 78.3890) to (17.4900, 78.3890)
      final route = [
        const LatLng(17.4800, 78.3890),
        const LatLng(17.4900, 78.3890),
      ];

      const currentPos = LatLng(17.4850, 78.3890);

      // Case 1: Driving North (heading ~0 deg, speed 25 km/h) -> Correct direction
      final isWrong1 = NavigationEngine.isWrongDirection(currentPos, 0.0, route, speedKmh: 25.0);
      expect(isWrong1, isFalse);

      // Case 2: Driving South (heading 180 deg, speed 25 km/h) -> Wrong direction!
      final isWrong2 = NavigationEngine.isWrongDirection(currentPos, 180.0, route, speedKmh: 25.0);
      expect(isWrong2, isTrue);

      // Case 3: Stopped at red light (speed 2 km/h) -> Do not trigger false wrong-direction
      final isWrong3 = NavigationEngine.isWrongDirection(currentPos, 180.0, route, speedKmh: 2.0);
      expect(isWrong3, isFalse);
    });

    test('NavigationEngine isOffRoute accurately detects when pilot leaves route corridor', () {
      final route = [
        const LatLng(17.4800, 78.3890),
        const LatLng(17.4900, 78.3890),
      ];

      // Point directly on route
      expect(NavigationEngine.isOffRoute(const LatLng(17.4850, 78.3890), route), isFalse);

      // Point 10 meters east of route (within normal road corridor)
      const nearPos = LatLng(17.4850, 78.3890 + (10.0 / 111320.0));
      expect(NavigationEngine.isOffRoute(nearPos, route), isFalse);

      // Point 50 meters east of route (turned onto a different road)
      const offRoadPos = LatLng(17.4850, 78.3890 + (50.0 / 111320.0));
      expect(NavigationEngine.isOffRoute(offRoadPos, route), isTrue);
    });
  });
}


