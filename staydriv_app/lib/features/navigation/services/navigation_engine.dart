import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Representation of a single turn-by-turn navigation step parsed from Google Directions API
class NavigationStep {
  final String instruction;
  final String rawInstruction;
  final String maneuver;
  final double distanceMeters;
  final String distanceText;
  final int durationSeconds;
  final String durationText;
  final LatLng startLocation;
  final LatLng endLocation;
  final List<LatLng> polylinePoints;

  NavigationStep({
    required this.instruction,
    required this.rawInstruction,
    required this.maneuver,
    required this.distanceMeters,
    required this.distanceText,
    required this.durationSeconds,
    required this.durationText,
    required this.startLocation,
    required this.endLocation,
    required this.polylinePoints,
  });

  factory NavigationStep.fromGoogleStep(Map<String, dynamic> stepJson) {
    final String rawHtml = stepJson['html_instructions'] ?? '';
    final String cleanText = NavigationEngine.stripHtml(rawHtml);
    final String maneuverStr = stepJson['maneuver'] ?? '';

    final num distVal = stepJson['distance']?['value'] ?? 0;
    final String distTxt = stepJson['distance']?['text'] ?? '${distVal.toInt()} m';

    final num durVal = stepJson['duration']?['value'] ?? 0;
    final String durTxt = stepJson['duration']?['text'] ?? '';

    final startLat = (stepJson['start_location']?['lat'] as num?)?.toDouble() ?? 0.0;
    final startLng = (stepJson['start_location']?['lng'] as num?)?.toDouble() ?? 0.0;

    final endLat = (stepJson['end_location']?['lat'] as num?)?.toDouble() ?? 0.0;
    final endLng = (stepJson['end_location']?['lng'] as num?)?.toDouble() ?? 0.0;

    final String polyPoints = stepJson['polyline']?['points'] ?? '';
    final List<LatLng> decoded = NavigationEngine.decodePolyline(polyPoints);

    return NavigationStep(
      instruction: cleanText,
      rawInstruction: rawHtml,
      maneuver: maneuverStr,
      distanceMeters: distVal.toDouble(),
      distanceText: distTxt,
      durationSeconds: durVal.toInt(),
      durationText: durTxt,
      startLocation: LatLng(startLat, startLng),
      endLocation: LatLng(endLat, endLng),
      polylinePoints: decoded,
    );
  }
}

/// Core computational engine for In-App Turn-by-Turn Google Maps Navigation
class NavigationEngine {
  /// Strips HTML tags (<b>, <div>, etc.) commonly returned by Google Directions API
  static String stripHtml(String htmlString) {
    return htmlString
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Calculates the Haversine distance in meters between two geographical coordinates
  static double distanceBetweenMeters(LatLng p1, LatLng p2) {
    const double earthRadius = 6371000; // meters
    final dLat = _degToRad(p2.latitude - p1.latitude);
    final dLon = _degToRad(p2.longitude - p1.longitude);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(p1.latitude)) *
            math.cos(_degToRad(p2.latitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  /// Computes the bearing/heading angle in degrees [0, 360) from p1 to p2
  static double computeBearing(LatLng p1, LatLng p2) {
    final lat1 = _degToRad(p1.latitude);
    final lat2 = _degToRad(p2.latitude);
    final dLon = _degToRad(p2.longitude - p1.longitude);

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final radians = math.atan2(y, x);
    final degrees = (radians * 180 / math.pi + 360) % 360;
    return degrees;
  }

  /// Snaps a GPS point to the nearest segment along a polyline
  /// Returns the snapped LatLng coordinate
  static LatLng snapToPolyline(LatLng point, List<LatLng> polyline) {
    if (polyline.isEmpty) return point;
    if (polyline.length == 1) return polyline.first;

    double minDistance = double.infinity;
    LatLng snappedPoint = polyline.first;

    for (int i = 0; i < polyline.length - 1; i++) {
      final a = polyline[i];
      final b = polyline[i + 1];
      final proj = _projectPointOnSegment(point, a, b);
      final dist = distanceBetweenMeters(point, proj);

      if (dist < minDistance) {
        minDistance = dist;
        snappedPoint = proj;
      }
    }

    return snappedPoint;
  }

  /// Calculates minimum perpendicular distance from point to the polyline
  static double distanceToPolyline(LatLng point, List<LatLng> polyline) {
    if (polyline.isEmpty) return 0.0;
    if (polyline.length == 1) return distanceBetweenMeters(point, polyline.first);

    double minDistance = double.infinity;
    for (int i = 0; i < polyline.length - 1; i++) {
      final a = polyline[i];
      final b = polyline[i + 1];
      final proj = _projectPointOnSegment(point, a, b);
      final dist = distanceBetweenMeters(point, proj);
      if (dist < minDistance) {
        minDistance = dist;
      }
    }

    return minDistance;
  }

  /// Checks if pilot has deviated from the route (> 35 meters)
  static bool isOffRoute(LatLng currentPos, List<LatLng> routePoints, {double thresholdMeters = 35.0}) {
    if (routePoints.isEmpty) return false;
    final dist = distanceToPolyline(currentPos, routePoints);
    return dist > thresholdMeters;
  }

  /// Checks if pilot is driving in the wrong direction relative to the active route
  /// Compares actual vehicle GPS heading against the expected travel heading of the closest route segment
  static bool isWrongDirection(
    LatLng currentPos,
    double heading,
    List<LatLng> routePoints, {
    double speedKmh = 10.0,
  }) {
    if (routePoints.length < 2 || heading == 0.0 || speedKmh < 8.0) return false;

    // Find closest route segment
    int bestIndex = 0;
    double minDistance = double.infinity;
    for (int i = 0; i < routePoints.length - 1; i++) {
      final a = routePoints[i];
      final b = routePoints[i + 1];
      final proj = _projectPointOnSegment(currentPos, a, b);
      final dist = distanceBetweenMeters(currentPos, proj);
      if (dist < minDistance) {
        minDistance = dist;
        bestIndex = i;
      }
    }

    // Only assess heading if within 60 meters of the route corridor
    if (minDistance <= 60.0) {
      final a = routePoints[bestIndex];
      final b = routePoints[bestIndex + 1];
      final expectedBearing = computeBearing(a, b);

      double diff = (heading - expectedBearing).abs() % 360;
      if (diff > 180) diff = 360 - diff;

      // Deviation greater than 110 degrees indicates driving opposite/backwards relative to route
      return diff > 110.0;
    }
    return false;
  }

  /// Checks if pilot has arrived at destination (< 50 meters)
  static bool isDestinationReached(LatLng currentPos, LatLng destination, {double thresholdMeters = 50.0}) {
    final dist = distanceBetweenMeters(currentPos, destination);
    return dist <= thresholdMeters;
  }

  /// Maps Google Directions maneuver strings to Flutter IconData
  static IconData getManeuverIcon(String maneuver) {
    final m = maneuver.toLowerCase().trim();
    if (m.contains('uturn-left') || m.contains('uturn-right') || m.contains('uturn')) {
      return Icons.u_turn_left_rounded;
    }
    if (m.contains('turn-slight-left')) return Icons.turn_slight_left_rounded;
    if (m.contains('turn-slight-right')) return Icons.turn_slight_right_rounded;
    if (m.contains('turn-sharp-left')) return Icons.turn_sharp_left_rounded;
    if (m.contains('turn-sharp-right')) return Icons.turn_sharp_right_rounded;
    if (m.contains('turn-left')) return Icons.turn_left_rounded;
    if (m.contains('turn-right')) return Icons.turn_right_rounded;
    if (m.contains('merge')) return Icons.merge_rounded;
    if (m.contains('fork-left')) return Icons.fork_left_rounded;
    if (m.contains('fork-right')) return Icons.fork_right_rounded;
    if (m.contains('roundabout')) return Icons.roundabout_left_rounded;
    if (m.contains('ramp-left') || m.contains('ramp-right')) return Icons.alt_route_rounded;
    if (m.contains('straight')) return Icons.straight_rounded;
    return Icons.navigation_rounded;
  }

  /// Formats distance in meters into friendly "In 250 m" or "In 1.4 km" string
  static String formatDistanceToManeuver(double meters) {
    if (meters < 50) {
      return 'Now';
    }
    if (meters < 1000) {
      final rounded = ((meters / 10).round() * 10).toInt();
      return 'In $rounded m';
    }
    final km = meters / 1000;
    return 'In ${km.toStringAsFixed(1)} km';
  }

  /// Formats remaining trip distance
  static String formatTripDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toInt()} m';
    }
    final km = meters / 1000;
    return '${km.toStringAsFixed(1)} km';
  }

  /// Formats remaining trip duration and estimated clock arrival time
  static String formatEtaClockTime(int durationSeconds) {
    final arrival = DateTime.now().add(Duration(seconds: durationSeconds));
    final hour = arrival.hour > 12 ? arrival.hour - 12 : (arrival.hour == 0 ? 12 : arrival.hour);
    final period = arrival.hour >= 12 ? 'PM' : 'AM';
    final minuteStr = arrival.minute.toString().padLeft(2, '0');
    return '$hour:$minuteStr $period';
  }

  static String formatDurationMinutes(int durationSeconds) {
    if (durationSeconds < 60) {
      return '< 1 min';
    }
    final minutes = (durationSeconds / 60).round();
    if (minutes < 60) {
      return '$minutes min';
    }
    final hours = minutes ~/ 60;
    final remainingMin = minutes % 60;
    return '${hours}h ${remainingMin}m';
  }

  /// Decodes Google Maps encoded polyline into `List<LatLng>`
  static List<LatLng> decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  // Helper projection math
  static LatLng _projectPointOnSegment(LatLng p, LatLng a, LatLng b) {
    final x = p.longitude;
    final y = p.latitude;
    final x1 = a.longitude;
    final y1 = a.latitude;
    final x2 = b.longitude;
    final y2 = b.latitude;

    final dx = x2 - x1;
    final dy = y2 - y1;

    if (dx == 0 && dy == 0) return a;

    final t = ((x - x1) * dx + (y - y1) * dy) / (dx * dx + dy * dy);

    if (t < 0) return a;
    if (t > 1) return b;

    return LatLng(y1 + t * dy, x1 + t * dx);
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);

  /// Splits a planned route into passed (travelled) and remaining (upcoming) segments
  /// based on the pilot's live GPS position.
  ///
  /// - The passed route segment is behind the vehicle (to be displayed in BLACK).
  /// - The remaining route segment is ahead of the vehicle (to be displayed in BLUE).
  /// - Both segments meet seamlessly at the snapped projection point with zero gap.
  /// - Uses monotonic progress tracking so small GPS variations or jitters do not cause
  ///   the progress to erratically jump backwards.
  static RouteSplitResult splitRouteAtPoint(
    LatLng currentPos,
    List<LatLng> routePoints, {
    int previousProgressIndex = 0,
    double snapToleranceMeters = 80.0,
  }) {
    if (routePoints.isEmpty) {
      return RouteSplitResult(
        passedPoints: const [],
        remainingPoints: const [],
        closestSegmentIndex: 0,
        snappedPosition: currentPos,
        distanceRemainingMeters: 0.0,
      );
    }
    if (routePoints.length == 1) {
      return RouteSplitResult(
        passedPoints: const [],
        remainingPoints: List<LatLng>.from(routePoints),
        closestSegmentIndex: 0,
        snappedPosition: routePoints.first,
        distanceRemainingMeters: 0.0,
      );
    }

    // Determine forward search window starting from previousProgressIndex
    final int safeStartIndex = previousProgressIndex.clamp(0, routePoints.length - 2);
    final int windowEnd = (safeStartIndex + 30).clamp(0, routePoints.length - 2);

    double minDistance = double.infinity;
    int bestIndex = safeStartIndex;
    LatLng bestProj = routePoints[safeStartIndex];

    // Search within forward window
    for (int i = safeStartIndex; i <= windowEnd; i++) {
      final a = routePoints[i];
      final b = routePoints[i + 1];
      final proj = _projectPointOnSegment(currentPos, a, b);
      final dist = distanceBetweenMeters(currentPos, proj);

      if (dist < minDistance) {
        minDistance = dist;
        bestIndex = i;
        bestProj = proj;
      }
    }

    // If vehicle is outside local window tolerance, check full route
    if (minDistance > snapToleranceMeters) {
      for (int i = 0; i < routePoints.length - 1; i++) {
        final a = routePoints[i];
        final b = routePoints[i + 1];
        final proj = _projectPointOnSegment(currentPos, a, b);
        final dist = distanceBetweenMeters(currentPos, proj);

        if (dist < minDistance) {
          minDistance = dist;
          bestIndex = i;
          bestProj = proj;
        }
      }
    }

    // Enforce monotonic forward progress: do not regress unless substantial deviation
    final int resolvedIndex = (bestIndex < previousProgressIndex && (previousProgressIndex - bestIndex) <= 2)
        ? previousProgressIndex
        : bestIndex;

    // 1. Build PASSED points (BLACK): Start from 0 to resolvedIndex, ending at bestProj
    final passed = <LatLng>[];
    for (int i = 0; i <= resolvedIndex; i++) {
      passed.add(routePoints[i]);
    }
    if (passed.isNotEmpty && distanceBetweenMeters(passed.last, bestProj) > 1.0) {
      passed.add(bestProj);
    }

    // 2. Build REMAINING points (BLUE): Start from bestProj to route end
    final remaining = <LatLng>[];
    remaining.add(bestProj);
    for (int i = resolvedIndex + 1; i < routePoints.length; i++) {
      remaining.add(routePoints[i]);
    }

    // 3. Compute remaining distance in meters along the polyline
    double remainingDist = 0.0;
    for (int i = 0; i < remaining.length - 1; i++) {
      remainingDist += distanceBetweenMeters(remaining[i], remaining[i + 1]);
    }

    return RouteSplitResult(
      passedPoints: passed,
      remainingPoints: remaining,
      closestSegmentIndex: resolvedIndex,
      snappedPosition: bestProj,
      distanceRemainingMeters: remainingDist,
    );
  }

  /// Safely extracts and validates LatLng from dynamic coordinates (LatLng, Map, GeoJSON, reverse lat/lng checks)
  static LatLng? parseLatLng(dynamic val, [dynamic secondaryVal]) {
    LatLng? result;
    if (val is LatLng) {
      result = val;
    } else if (val is Map) {
      final lat = val['lat'] ?? val['latitude'];
      final lng = val['lng'] ?? val['longitude'];
      if (lat != null && lng != null) {
        final dLat = lat is num ? lat.toDouble() : double.tryParse(lat.toString());
        final dLng = lng is num ? lng.toDouble() : double.tryParse(lng.toString());
        if (dLat != null && dLng != null && (dLat != 0.0 || dLng != 0.0)) {
          result = LatLng(dLat, dLng);
        }
      }
    } else if (val is List && val.length >= 2) {
      final n1 = val[0] is num ? (val[0] as num).toDouble() : double.tryParse(val[0].toString());
      final n2 = val[1] is num ? (val[1] as num).toDouble() : double.tryParse(val[1].toString());
      if (n1 != null && n2 != null) {
        if (n1 > 50 && n2 < 40) {
          result = LatLng(n2, n1); // GeoJSON [lng, lat] for India
        } else {
          result = LatLng(n1, n2);
        }
      }
    }

    if (result == null && secondaryVal != null) {
      return parseLatLng(secondaryVal);
    }

    if (result != null) {
      // Validate bounds and detect accidental reverse latitude/longitude (India is ~6-38° N, 68-98° E)
      if (result.latitude > 50.0 && result.longitude < 40.0) {
        // Accidental inversion! Swap latitude and longitude
        result = LatLng(result.longitude, result.latitude);
      }
      // Check valid globe ranges
      if (result.latitude >= -90.0 && result.latitude <= 90.0 &&
          result.longitude >= -180.0 && result.longitude <= 180.0 &&
          (result.latitude != 0.0 || result.longitude != 0.0)) {
        return result;
      }
    }

    return null;
  }

  /// Authoritatively extracts customer pickup LatLng from any supported booking schema field
  static LatLng? extractPickupLatLng(Map<String, dynamic>? booking) {
    if (booking == null) return null;
    return parseLatLng(
      booking['pickupLatLng'] ??
          booking['restaurantLatLng'] ??
          (booking['restaurantLat'] != null && booking['restaurantLng'] != null
              ? {'lat': booking['restaurantLat'], 'lng': booking['restaurantLng']}
              : null),
      booking['customerLocation'] ??
          booking['pickupLocation'] ??
          (booking['pickupLat'] != null && booking['pickupLng'] != null
              ? {'lat': booking['pickupLat'], 'lng': booking['pickupLng']}
              : (booking['pickup_lat'] != null && booking['pickup_lng'] != null
                  ? {'lat': booking['pickup_lat'], 'lng': booking['pickup_lng']}
                  : (booking['originLat'] != null && booking['originLng'] != null
                      ? {'lat': booking['originLat'], 'lng': booking['originLng']}
                      : null))),
    );
  }

  /// Authoritatively extracts customer destination LatLng from any supported booking schema field
  static LatLng? extractDropLatLng(Map<String, dynamic>? booking) {
    if (booking == null) return null;
    return parseLatLng(
      booking['dropLatLng'] ??
          booking['deliveryLatLng'] ??
          (booking['deliveryLat'] != null && booking['deliveryLng'] != null
              ? {'lat': booking['deliveryLat'], 'lng': booking['deliveryLng']}
              : null),
      booking['destinationLocation'] ??
          booking['dropLocation'] ??
          (booking['dropLat'] != null && booking['dropLng'] != null
              ? {'lat': booking['dropLat'], 'lng': booking['dropLng']}
              : (booking['drop_lat'] != null && booking['drop_lng'] != null
                  ? {'lat': booking['drop_lat'], 'lng': booking['drop_lng']}
                  : (booking['destLat'] != null && booking['destLng'] != null
                      ? {'lat': booking['destLat'], 'lng': booking['destLng']}
                      : null))),
    );
  }
}

/// Represents the result of splitting a navigation route into passed (travelled)
/// and remaining (upcoming) segments based on the vehicle's live GPS position.
class RouteSplitResult {
  /// The road segments behind the vehicle, rendered in BLACK
  final List<LatLng> passedPoints;

  /// The road segments ahead of the vehicle, rendered in BLUE
  final List<LatLng> remainingPoints;

  /// The index of the route segment closest to the vehicle
  final int closestSegmentIndex;

  /// The exact snapped position along the route where passed and remaining meet
  final LatLng snappedPosition;

  /// Remaining distance in meters along the polyline to the destination
  final double distanceRemainingMeters;

  const RouteSplitResult({
    required this.passedPoints,
    required this.remainingPoints,
    required this.closestSegmentIndex,
    required this.snappedPosition,
    required this.distanceRemainingMeters,
  });
}
