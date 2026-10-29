import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:staydriv_app/features/navigation/services/navigation_engine.dart';
import 'package:flutter/material.dart';

void main() {
  group('NavigationEngine Unit Tests', () {
    test('stripHtml cleans Google directions instructions correctly', () {
      const html = 'Turn <b>left</b> onto <b>9th Phase Rd</b><div style="font-size:0.9em">Pass by SBI</div>';
      final cleaned = NavigationEngine.stripHtml(html);
      expect(cleaned, 'Turn left onto 9th Phase Rd Pass by SBI');
    });

    test('distanceBetweenMeters calculates accurate distance', () {
      // 1 degree latitude is approx 111 km
      const p1 = LatLng(17.4834, 78.3871);
      const p2 = LatLng(17.4844, 78.3871);
      final dist = NavigationEngine.distanceBetweenMeters(p1, p2);
      expect(dist, greaterThan(100.0));
      expect(dist, lessThan(120.0));
    });

    test('computeBearing computes correct cardinal headings', () {
      // North: 0 deg
      const origin = LatLng(17.0, 78.0);
      const north = LatLng(18.0, 78.0);
      final bearingNorth = NavigationEngine.computeBearing(origin, north);
      expect(bearingNorth, closeTo(0.0, 1.0));

      // East: ~90 deg
      const east = LatLng(17.0, 79.0);
      final bearingEast = NavigationEngine.computeBearing(origin, east);
      expect(bearingEast, closeTo(90.0, 2.0));
    });

    test('isOffRoute accurately identifies when vehicle deviates > 40m', () {
      final route = [
        const LatLng(17.4800, 78.3800),
        const LatLng(17.4900, 78.3800),
      ];

      // On route point
      const onRoutePoint = LatLng(17.4850, 78.3801);
      expect(NavigationEngine.isOffRoute(onRoutePoint, route, thresholdMeters: 40.0), isFalse);

      // Off route point (approx 200m east)
      const offRoutePoint = LatLng(17.4850, 78.3820);
      expect(NavigationEngine.isOffRoute(offRoutePoint, route, thresholdMeters: 40.0), isTrue);
    });

    test('isDestinationReached detects within 50m threshold', () {
      const destination = LatLng(17.48340, 78.38710);
      // 15 meters away
      const near = LatLng(17.48350, 78.38710);
      // 500 meters away
      const far = LatLng(17.48800, 78.38710);

      expect(NavigationEngine.isDestinationReached(near, destination, thresholdMeters: 50.0), isTrue);
      expect(NavigationEngine.isDestinationReached(far, destination, thresholdMeters: 50.0), isFalse);
    });

    test('getManeuverIcon correctly maps turn maneuvers', () {
      expect(NavigationEngine.getManeuverIcon('turn-left'), Icons.turn_left_rounded);
      expect(NavigationEngine.getManeuverIcon('turn-right'), Icons.turn_right_rounded);
      expect(NavigationEngine.getManeuverIcon('uturn-left'), Icons.u_turn_left_rounded);
      expect(NavigationEngine.getManeuverIcon('merge'), Icons.merge_rounded);
      expect(NavigationEngine.getManeuverIcon('straight'), Icons.straight_rounded);
    });

    test('decodePolyline decodes standard encoded polyline', () {
      // Encoded polyline for (38.5, -120.2) to (40.7, -120.95) to (43.252, -126.453)
      const encoded = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';
      final points = NavigationEngine.decodePolyline(encoded);
      expect(points.length, 3);
      expect(points[0].latitude, closeTo(38.5, 0.001));
      expect(points[0].longitude, closeTo(-120.2, 0.001));
    });

    test('formatDistanceToManeuver formats meters and kilometers properly', () {
      expect(NavigationEngine.formatDistanceToManeuver(450), 'In 450 m');
      expect(NavigationEngine.formatDistanceToManeuver(1500), 'In 1.5 km');
      expect(NavigationEngine.formatTripDistance(450), '450 m');
      expect(NavigationEngine.formatTripDistance(1500), '1.5 km');
    });

    test('splitRouteAtPoint correctly splits route into passed (black) and remaining (blue)', () {
      // 3-point route: A -> B -> C
      final route = [
        const LatLng(17.4800, 78.3800), // A
        const LatLng(17.4850, 78.3800), // B
        const LatLng(17.4900, 78.3800), // C
      ];

      // Vehicle at start point A
      final atStart = NavigationEngine.splitRouteAtPoint(
        const LatLng(17.4800, 78.3800),
        route,
      );
      // Passed points should be minimal (< 2 or at A)
      expect(atStart.passedPoints.length, lessThanOrEqualTo(2));
      expect(atStart.remainingPoints.length, equals(3));
      expect(atStart.remainingPoints.last, equals(route.last));

      // Vehicle moves midway between A and B: (17.4825, 78.3800)
      final midAB = NavigationEngine.splitRouteAtPoint(
        const LatLng(17.4825, 78.3800),
        route,
      );
      // Passed points: [A, midPoint]
      expect(midAB.passedPoints.length, equals(2));
      expect(midAB.passedPoints.first, equals(route.first));
      expect(midAB.passedPoints.last.latitude, closeTo(17.4825, 0.0001));

      // Remaining points: [midPoint, B, C]
      expect(midAB.remainingPoints.length, equals(3));
      expect(midAB.remainingPoints.first.latitude, closeTo(17.4825, 0.0001));
      expect(midAB.remainingPoints.last, equals(route.last));

      // Both segments meet exactly at the snapped position with zero gap
      expect(midAB.passedPoints.last, equals(midAB.remainingPoints.first));

      // Vehicle moves past B towards C: (17.4875, 78.3800)
      final pastB = NavigationEngine.splitRouteAtPoint(
        const LatLng(17.4875, 78.3800),
        route,
        previousProgressIndex: midAB.closestSegmentIndex,
      );
      // Passed points: [A, B, midBC]
      expect(pastB.passedPoints.length, equals(3));
      expect(pastB.passedPoints[0], equals(route[0]));
      expect(pastB.passedPoints[1], equals(route[1]));
      expect(pastB.passedPoints[2].latitude, closeTo(17.4875, 0.0001));

      // Remaining points: [midBC, C]
      expect(pastB.remainingPoints.length, equals(2));
      expect(pastB.remainingPoints.first, equals(pastB.passedPoints.last));
      expect(pastB.remainingPoints.last, equals(route[2]));
      expect(pastB.distanceRemainingMeters, lessThan(midAB.distanceRemainingMeters));
    });

    test('parseLatLng parses LatLng, Map, List, and detects inverted Indian coordinates', () {
      // 1. Direct LatLng
      final c1 = NavigationEngine.parseLatLng(const LatLng(17.4834, 78.3871));
      expect(c1?.latitude, 17.4834);
      expect(c1?.longitude, 78.3871);

      // 2. Map with lat / lng
      final c2 = NavigationEngine.parseLatLng({'lat': 17.4834, 'lng': 78.3871});
      expect(c2?.latitude, 17.4834);
      expect(c2?.longitude, 78.3871);

      // 3. Map with latitude / longitude
      final c3 = NavigationEngine.parseLatLng({'latitude': '17.4834', 'longitude': '78.3871'});
      expect(c3?.latitude, 17.4834);
      expect(c3?.longitude, 78.3871);

      // 4. GeoJSON [lng, lat] for India (lng ~78, lat ~17)
      final c4 = NavigationEngine.parseLatLng([78.3871, 17.4834]);
      expect(c4?.latitude, 17.4834);
      expect(c4?.longitude, 78.3871);

      // 5. Inverted Indian coordinates in map: {lat: 78.3871, lng: 17.4834}
      final c5 = NavigationEngine.parseLatLng({'lat': 78.3871, 'lng': 17.4834});
      expect(c5?.latitude, 17.4834);
      expect(c5?.longitude, 78.3871);
    });

    test('extractPickupLatLng and extractDropLatLng extract from various payload structures', () {
      final booking1 = {
        'pickupLocation': {'latitude': 17.4834, 'longitude': 78.3871},
        'destinationLocation': {'latitude': 17.4920, 'longitude': 78.3980},
      };
      final p1 = NavigationEngine.extractPickupLatLng(booking1);
      final d1 = NavigationEngine.extractDropLatLng(booking1);
      expect(p1?.latitude, 17.4834);
      expect(d1?.latitude, 17.4920);

      final booking2 = {
        'pickupLat': 17.4834,
        'pickupLng': 78.3871,
        'dropLat': 17.4920,
        'dropLng': 78.3980,
      };
      final p2 = NavigationEngine.extractPickupLatLng(booking2);
      final d2 = NavigationEngine.extractDropLatLng(booking2);
      expect(p2?.latitude, 17.4834);
      expect(d2?.latitude, 17.4920);

      // Inverted booking coordinates
      final booking3 = {
        'pickupLatLng': {'lat': 78.3871, 'lng': 17.4834},
      };
      final p3 = NavigationEngine.extractPickupLatLng(booking3);
      expect(p3?.latitude, 17.4834);
      expect(p3?.longitude, 78.3871);
    });
  });
}
