import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../features/navigation/services/navigation_engine.dart';
import 'vehicle_marker_helper.dart';

/// Manages smooth, jitter-free 60 FPS marker interpolation, GPS accuracy filtering,
/// stationary drift suppression, and realistic heading rotation for live maps.
class SmoothMarkerAnimator {
  final void Function(LatLng position, double heading) onUpdate;
  final void Function(double speedKmh)? onSpeedUpdate;

  // Configuration thresholds
  final double maxAcceptableAccuracyMeters;
  final double maxImpliedSpeedMps; // ~200 km/h jump filter
  final Duration interpolationDuration;

  // Active state
  LatLng? _currentPosition;
  double _currentHeading = 0.0;
  double _currentSpeedKmh = 0.0;
  int? _lastTimestampMs;
  int? _lastFixTimeMs;

  // Animation controller
  Timer? _animTimer;
  LatLng? _startPosition;
  LatLng? _targetPosition;
  double _startHeading = 0.0;
  double _targetHeading = 0.0;
  int _animStartTimeMs = 0;
  int _animDurationMs = 900;

  SmoothMarkerAnimator({
    required this.onUpdate,
    this.onSpeedUpdate,
    this.maxAcceptableAccuracyMeters = 45.0,
    this.maxImpliedSpeedMps = 55.0, // 55 m/s = 198 km/h
    this.interpolationDuration = const Duration(milliseconds: 900),
  });

  LatLng? get currentPosition => _currentPosition;
  double get currentHeading => _currentHeading;
  double get currentSpeedKmh => _currentSpeedKmh;

  /// Feeds a new GPS update into the animator.
  /// Filters invalid points, rejects stale timestamps, suppresses stationary drift,
  /// rejects unrealistic jumps, and initiates smooth 60fps interpolation.
  void updateTarget({
    required LatLng position,
    double? heading,
    double? speedMps,
    double? accuracyMeters,
    int? timestampMs,
    List<LatLng>? routeForSnapping,
  }) {
    // 1. Reject invalid / null / out-of-range coordinates
    if (position.latitude < -90.0 ||
        position.latitude > 90.0 ||
        position.longitude < -180.0 ||
        position.longitude > 180.0 ||
        (position.latitude == 0.0 && position.longitude == 0.0)) {
      debugPrint('[GPS FILTER] Rejected invalid GPS coordinate: $position');
      return;
    }

    // 2. Reject stale / out-of-order packets if timestamp is provided
    if (timestampMs != null && _lastTimestampMs != null) {
      if (timestampMs < _lastTimestampMs!) {
        debugPrint('[GPS FILTER] Dropped stale packet: ts=$timestampMs < last=$_lastTimestampMs');
        return;
      }
    }
    if (timestampMs != null) {
      _lastTimestampMs = timestampMs;
    }

    // 3. Reject clearly inaccurate GPS readings (using accuracy value)
    final double rawSpeedMps = speedMps ?? 0.0;
    // Allow slightly higher threshold at highway speeds (> 15 m/s = 54 km/h)
    final double dynamicMaxAccuracy = rawSpeedMps > 15.0 ? 65.0 : maxAcceptableAccuracyMeters;
    if (accuracyMeters != null && accuracyMeters > dynamicMaxAccuracy) {
      debugPrint(
        '[GPS FILTER] Rejected low-accuracy GPS fix: accuracy=${accuracyMeters.toStringAsFixed(1)}m > max=${dynamicMaxAccuracy.toStringAsFixed(1)}m',
      );
      return;
    }

    final int nowMs = DateTime.now().millisecondsSinceEpoch;

    // 4. Reject unrealistic GPS jumps / teleportation
    if (_currentPosition != null) {
      final double distMeters = NavigationEngine.distanceBetweenMeters(_currentPosition!, position);
      final int dtMs = _lastFixTimeMs != null ? (nowMs - _lastFixTimeMs!) : 1000;
      final double dtSec = math.max(0.15, dtMs / 1000.0);
      final double impliedSpeed = distMeters / dtSec;

      // If implied speed is > maxImpliedSpeedMps and interval is short, it's an impossible GPS jump
      if (impliedSpeed > maxImpliedSpeedMps && dtSec < 8.0) {
        debugPrint(
          '[GPS FILTER] Rejected unrealistic GPS jump: dist=${distMeters.toStringAsFixed(1)}m in ${dtSec.toStringAsFixed(1)}s (${(impliedSpeed * 3.6).toStringAsFixed(1)} km/h)',
        );
        return;
      }
    }
    _lastFixTimeMs = nowMs;

    // 5. Stationary drift suppression
    // When the vehicle is stopped at a traffic signal or parking (speed < 0.8 m/s and dist < 2.5m),
    // do not let GPS noise wobble the avatar or spin its heading!
    if (_currentPosition != null) {
      final double distMeters = NavigationEngine.distanceBetweenMeters(_currentPosition!, position);
      if (rawSpeedMps < 0.8 && distMeters < 2.5) {
        // Vehicle is stationary: maintain previous valid heading and position
        _currentSpeedKmh = 0.0;
        onSpeedUpdate?.call(0.0);
        return;
      }
    }

    // 6. Road snapping (if route polyline is active and marker is within 25m)
    LatLng resolvedTarget = position;
    if (routeForSnapping != null && routeForSnapping.length > 1) {
      final double distToRoute = NavigationEngine.distanceToPolyline(position, routeForSnapping);
      if (distToRoute <= 25.0) {
        resolvedTarget = NavigationEngine.snapToPolyline(position, routeForSnapping);
      }
    }

    // 7. Calculate or smooth heading
    double resolvedHeading = _currentHeading;
    if (heading != null && heading > 0.0 && heading <= 360.0 && (_currentPosition == null || rawSpeedMps >= 0.8)) {
      resolvedHeading = heading;
    } else if (_currentPosition != null &&
        NavigationEngine.distanceBetweenMeters(_currentPosition!, resolvedTarget) >= 2.0) {
      resolvedHeading = NavigationEngine.computeBearing(_currentPosition!, resolvedTarget);
    }

    _currentSpeedKmh = math.max(0.0, rawSpeedMps * 3.6);
    onSpeedUpdate?.call(_currentSpeedKmh);

    // 8. Handle first initial fix immediately without interpolation delay
    if (_currentPosition == null) {
      _currentPosition = resolvedTarget;
      _currentHeading = resolvedHeading;
      onUpdate(_currentPosition!, _currentHeading);
      return;
    }

    // 9. Begin smooth 60 FPS interpolation to new target
    _startInterpolation(resolvedTarget, resolvedHeading);
  }

  void _startInterpolation(LatLng newTarget, double newHeading) {
    _animTimer?.cancel();

    _startPosition = _currentPosition!;
    _targetPosition = newTarget;

    _startHeading = _currentHeading;
    _targetHeading = newHeading;

    _animStartTimeMs = DateTime.now().millisecondsSinceEpoch;
    _animDurationMs = interpolationDuration.inMilliseconds;

    // ~60 FPS update interval (~16 ms)
    _animTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final int elapsed = DateTime.now().millisecondsSinceEpoch - _animStartTimeMs;
      double t = elapsed / _animDurationMs;

      if (t >= 1.0) {
        t = 1.0;
        timer.cancel();
        _animTimer = null;
      }

      // Linear easing along the track segment
      final lat = _startPosition!.latitude + (_targetPosition!.latitude - _startPosition!.latitude) * t;
      final lng = _startPosition!.longitude + (_targetPosition!.longitude - _startPosition!.longitude) * t;
      final currentPos = LatLng(lat, lng);

      // Shortest arc rotation interpolation
      final currentH = VehicleMarkerHelper.interpolateHeading(_startHeading, _targetHeading, t);

      _currentPosition = currentPos;
      _currentHeading = currentH;

      onUpdate(currentPos, currentH);
    });
  }

  /// Cancels any active interpolation and resets state.
  void dispose() {
    _animTimer?.cancel();
    _animTimer = null;
  }
}
