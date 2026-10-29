import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staydriv_app/core/smooth_marker_animator.dart';
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

  group('VehicleMarkerHelper Navigation Avatars & Booked Vehicle Icons', () {
    test('normalizeVehicleType correctly categorizes all supported vehicle types', () {
      expect(VehicleMarkerHelper.normalizeVehicleType('Car'), 'car');
      expect(VehicleMarkerHelper.normalizeVehicleType('Sedan'), 'car');
      expect(VehicleMarkerHelper.normalizeVehicleType('Bike'), 'bike');
      expect(VehicleMarkerHelper.normalizeVehicleType('Motorcycle'), 'bike');
      expect(VehicleMarkerHelper.normalizeVehicleType('Auto'), 'auto');
      expect(VehicleMarkerHelper.normalizeVehicleType('Auto-Rickshaw'), 'auto');
      expect(VehicleMarkerHelper.normalizeVehicleType('SUV'), 'suv');
      expect(VehicleMarkerHelper.normalizeVehicleType('Innova'), 'suv');
      expect(VehicleMarkerHelper.normalizeVehicleType('Ertiga'), 'suv');
      expect(VehicleMarkerHelper.normalizeVehicleType('Truck'), 'truck');
      expect(VehicleMarkerHelper.normalizeVehicleType('Mini Truck'), 'truck');
      expect(VehicleMarkerHelper.normalizeVehicleType('Goods'), 'truck');
      expect(VehicleMarkerHelper.normalizeVehicleType('Van'), 'van');
      expect(VehicleMarkerHelper.normalizeVehicleType('Omni'), 'van');
      expect(VehicleMarkerHelper.normalizeVehicleType(null), 'car');
    });

    test('getGoogleDrivingPuckMarker generates valid navigation marker', () async {
      final marker = await VehicleMarkerHelper.getGoogleDrivingPuckMarker(size: 120);
      expect(marker, isNotNull);
    });

    test('getCustomerVehicleMarker generates vehicle-specific icons for each booked type', () async {
      final types = ['car', 'bike', 'auto', 'suv', 'truck', 'van'];
      for (final type in types) {
        final icon = await VehicleMarkerHelper.getCustomerVehicleMarker(type, size: 196);
        expect(icon, isNotNull, reason: 'Marker for $type should not be null');
      }
    });

    test('getNavigationAvatarMarker supports both vehicle type scaling and default navigation puck', () async {
      final carAvatar = await VehicleMarkerHelper.getNavigationAvatarMarker(vehicleType: 'Car', size: 196);
      expect(carAvatar, isNotNull);

      final puckAvatar = await VehicleMarkerHelper.getNavigationAvatarMarker(vehicleType: null, size: 196);
      expect(puckAvatar, isNotNull);

      final defaultAvatar = await VehicleMarkerHelper.getNavigationAvatarMarker();
      expect(defaultAvatar, isNotNull);
    });

    test('interpolateHeading wraps shortest arc across 360/0 degree meridian', () {
      // 355 deg to 5 deg: shortest rotation is +10 deg, midpoint is 0 deg (or 360 deg)
      final mid1 = VehicleMarkerHelper.interpolateHeading(355.0, 5.0, 0.5);
      expect((mid1 - 0.0).abs() < 0.01 || (mid1 - 360.0).abs() < 0.01, isTrue);

      // 5 deg to 355 deg: shortest rotation is -10 deg, midpoint is 0 deg (or 360 deg)
      final mid2 = VehicleMarkerHelper.interpolateHeading(5.0, 355.0, 0.5);
      expect((mid2 - 0.0).abs() < 0.01 || (mid2 - 360.0).abs() < 0.01, isTrue);

      // 90 deg to 180 deg: midpoint is 135 deg
      final mid3 = VehicleMarkerHelper.interpolateHeading(90.0, 180.0, 0.5);
      expect(mid3, closeTo(135.0, 0.01));
    });
  });

  group('SmoothMarkerAnimator GPS Accuracy, Drift & Interpolation Tests', () {
    test('Initial fix sets position and heading immediately without delay', () {
      LatLng? updatedPos;
      double? updatedHeading;

      final animator = SmoothMarkerAnimator(
        onUpdate: (pos, heading) {
          updatedPos = pos;
          updatedHeading = heading;
        },
      );

      const firstPos = LatLng(17.4834, 78.3871);
      animator.updateTarget(
        position: firstPos,
        heading: 45.0,
        speedMps: 5.0,
        accuracyMeters: 8.0,
      );

      expect(updatedPos, equals(firstPos));
      expect(updatedHeading, equals(45.0));
      expect(animator.currentPosition, equals(firstPos));
      expect(animator.currentHeading, equals(45.0));
      expect(animator.currentSpeedKmh, closeTo(18.0, 0.1)); // 5.0 m/s * 3.6 = 18.0 km/h

      animator.dispose();
    });

    test('Filters out low-accuracy GPS readings (> 45m)', () {
      LatLng? lastPos;
      final animator = SmoothMarkerAnimator(
        onUpdate: (pos, heading) => lastPos = pos,
      );

      const goodPos = LatLng(17.4834, 78.3871);
      animator.updateTarget(
        position: goodPos,
        heading: 90.0,
        speedMps: 4.0,
        accuracyMeters: 10.0,
      );
      expect(lastPos, equals(goodPos));

      // Coordinate with poor accuracy (> 45m)
      const inaccuratePos = LatLng(17.4900, 78.3900);
      animator.updateTarget(
        position: inaccuratePos,
        heading: 90.0,
        speedMps: 4.0,
        accuracyMeters: 65.0, // Inaccurate!
      );

      // Target should be rejected, so targetPosition remains at goodPos
      expect(animator.currentPosition, equals(goodPos));

      animator.dispose();
    });

    test('Rejects stale timestamps when packets arrive out-of-order', () {
      LatLng? lastPos;
      final animator = SmoothMarkerAnimator(
        onUpdate: (pos, heading) => lastPos = pos,
      );

      const pos1 = LatLng(17.4834, 78.3871);
      animator.updateTarget(
        position: pos1,
        heading: 0.0,
        timestampMs: 10000,
      );
      expect(lastPos, equals(pos1));

      // Stale packet with timestamp < 10000
      const stalePos = LatLng(17.4830, 78.3860);
      animator.updateTarget(
        position: stalePos,
        heading: 0.0,
        timestampMs: 9500, // Stale!
      );

      // Stale packet dropped
      expect(animator.currentPosition, equals(pos1));

      animator.dispose();
    });

    test('Suppresses stationary GPS drift when vehicle is stopped (< 0.8 m/s, < 2.5m)', () {
      final animator = SmoothMarkerAnimator(
        onUpdate: (pos, heading) {},
      );

      const stationaryPos = LatLng(17.483400, 78.387100);
      animator.updateTarget(
        position: stationaryPos,
        heading: 120.0,
        speedMps: 0.0,
        accuracyMeters: 5.0,
      );

      // Slight GPS jitter (1.2 meters away) while stopped
      const jitterPos = LatLng(17.483408, 78.387106);
      animator.updateTarget(
        position: jitterPos,
        heading: 250.0, // Erratic random heading from jitter
        speedMps: 0.2, // ~0.7 km/h drift noise
        accuracyMeters: 6.0,
      );

      // Heading must remain frozen at 120.0 deg (not wobbled to 250.0 deg)
      expect(animator.currentHeading, equals(120.0));
      expect(animator.currentPosition, equals(stationaryPos));

      animator.dispose();
    });

    test('Snaps to route polyline when within 25m', () {
      final List<LatLng> route = [
        const LatLng(17.483000, 78.387000),
        const LatLng(17.483000, 78.390000),
      ];

      LatLng? updatedPos;
      final animator = SmoothMarkerAnimator(
        onUpdate: (pos, heading) => updatedPos = pos,
      );

      // GPS point 8 meters north of route segment
      const nearPos = LatLng(17.483070, 78.388000);
      animator.updateTarget(
        position: nearPos,
        heading: 90.0,
        speedMps: 10.0,
        routeForSnapping: route,
      );

      // Initial fix snapped onto route latitude 17.483000
      expect(updatedPos, isNotNull);
      expect(updatedPos!.latitude, closeTo(17.483000, 0.00005));

      animator.dispose();
    });
  });

  group('BookingManager GPS Accuracy & Timestamp Pipeline Integration', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      BookingManager.enableNetworkSync = false;
      BookingManager().clearBooking();
    });

    test('updateDriverLocation saves and broadcasts accuracy and speed', () {
      final manager = BookingManager();
      const testPos = LatLng(17.4850, 78.3890);

      manager.updateDriverLocation(
        testPos,
        heading: 180.0,
        speed: 35.0,
        accuracy: 4.2,
        eta: '10 mins',
        remainingDistance: '4.5 km',
      );

      expect(manager.driverLatLng, equals(testPos));
      expect(manager.driverHeading, equals(180.0));
      expect(manager.driverSpeed, equals(35.0));
      expect(manager.driverAccuracy, equals(4.2));
      expect(manager.latestEta, equals('10 mins'));
      expect(manager.latestRemainingDistance, equals('4.5 km'));
    });
  });
}
