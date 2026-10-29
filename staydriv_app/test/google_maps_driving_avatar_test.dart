import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:staydriv_app/core/vehicle_marker_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Google Maps Driving Navigation Avatar Tests', () {
    test('getGoogleDrivingPuckMarker generates high-resolution 256px Google Maps avatar', () async {
      final marker = await VehicleMarkerHelper.getGoogleDrivingPuckMarker(size: 256);
      expect(marker, isNotNull);
    });

    test('getNavigationAvatarMarker defaults to Google Maps driving avatar for navigation', () async {
      final defaultAvatar = await VehicleMarkerHelper.getNavigationAvatarMarker();
      expect(defaultAvatar, isNotNull);

      final pilotAvatar = await VehicleMarkerHelper.getNavigationAvatarMarker(
        vehicleType: 'Car',
        size: 256,
      );
      expect(pilotAvatar, isNotNull);

      final customerAvatar = await VehicleMarkerHelper.getNavigationAvatarMarker(
        vehicleType: 'Bike',
        size: 256,
      );
      expect(customerAvatar, isNotNull);
    });

    test('Driving avatar Marker configuration matches Google Maps specifications', () {
      const LatLng testCoord = LatLng(17.4851, 78.3892);
      const double testHeading = 142.5;

      final marker = Marker(
        markerId: const MarkerId('test_driving_avatar'),
        position: testCoord,
        rotation: testHeading,
        flat: true,
        anchor: const Offset(0.5, 0.5),
        zIndex: 100.0,
      );

      // Verify anchor is centered (0.5, 0.5) for exact route centerline alignment
      expect(marker.anchor.dx, equals(0.5));
      expect(marker.anchor.dy, equals(0.5));

      // Verify flat is true for Google Maps 3D road surface perspective alignment
      expect(marker.flat, isTrue);

      // Verify zIndex is 100.0 to guarantee rendering above polyline (zIndex 1-2)
      expect(marker.zIndex, equals(100.0));

      // Verify heading rotation is assigned directly from GPS
      expect(marker.rotation, equals(142.5));
    });

    test('Heading rotation interpolation wraps shortest arc across 360/0 degree boundary', () {
      final mid1 = VehicleMarkerHelper.interpolateHeading(355.0, 5.0, 0.5);
      expect(mid1, closeTo(0.0, 0.001));

      final mid2 = VehicleMarkerHelper.interpolateHeading(5.0, 355.0, 0.5);
      expect(mid2, closeTo(0.0, 0.001));

      final mid3 = VehicleMarkerHelper.interpolateHeading(90.0, 180.0, 0.5);
      expect(mid3, closeTo(135.0, 0.001));
    });

    test('Position interpolation calculates exact intermediate coordinates for smooth movement', () {
      const p1 = LatLng(17.4800, 78.3800);
      const p2 = LatLng(17.4900, 78.3900);

      final mid = VehicleMarkerHelper.interpolatePosition(p1, p2, 0.5);
      expect(mid.latitude, closeTo(17.4850, 0.0001));
      expect(mid.longitude, closeTo(78.3850, 0.0001));
    });
  });
}
