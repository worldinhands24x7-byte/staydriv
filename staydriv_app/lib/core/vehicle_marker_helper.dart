import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Helper for generating high-definition, directional, Google Maps-style navigation avatars
/// and booked vehicle-type map markers.
class VehicleMarkerHelper {
  static final Map<String, BitmapDescriptor> _markerCache = {};

  /// Normalizes vehicle type strings to standard categories:
  /// 'bike', 'auto', 'car', 'suv', 'truck', 'van'
  static String normalizeVehicleType(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'car';
    final lower = raw.toLowerCase().trim();

    if (lower.contains('bike') || lower.contains('moto') || lower.contains('scoot') || lower.contains('two')) {
      return 'bike';
    }
    if (lower.contains('auto') || lower.contains('rick') || lower.contains('tuk') || lower.contains('three')) {
      return 'auto';
    }
    if (lower.contains('truck') || lower.contains('heavy') || lower.contains('pickup') ||
        lower.contains('goods') || lower.contains('mini truck') || lower.contains('ace') || lower.contains('bolero')) {
      return 'truck';
    }
    if (lower.contains('xl') || lower.contains('car xl') || lower.contains('suv') || lower.contains('innova') || lower.contains('ertiga') ||
        lower.contains('fortuner') || lower.contains('creta') || lower.contains('xl6') || lower.contains('scorpio')) {
      return 'suv';
    }
    if (lower.contains('van') || lower.contains('omni') || lower.contains('eeco') || lower.contains('tempo')) {
      return 'van';
    }
    return 'car';
  }

  /// Returns the iconic Google Maps driving navigation puck / 3D chevron arrow.
  /// Large, high-contrast, razor-sharp on high-DPI displays.
  /// Used for Pilot / Driver navigation and Customer live ride tracking.
  static Future<BitmapDescriptor> getGoogleDrivingPuckMarker({int size = 256}) async {
    final cacheKey = 'google_driving_puck_$size';
    if (_markerCache.containsKey(cacheKey)) {
      return _markerCache[cacheKey]!;
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()));
    final center = Offset(size / 2.0, size / 2.0);

    // 1. Google Maps Forward Directional Illumination Headlight Cone / Beam (Points North 0°)
    _drawForwardDirectionalBeam(canvas, center, size.toDouble());

    // 2. Multi-Stage Realistic Ground Elevation Drop Shadow underneath puck
    // Soft ambient shadow
    final ambientShadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.38)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10.0);
    canvas.drawCircle(center + const Offset(0, 5), size * 0.38, ambientShadowPaint);

    // Contact crisp shadow
    final contactShadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawCircle(center + const Offset(0, 2), size * 0.37, contactShadowPaint);

    // 3. Signature Google Maps Navigation Blue GPS Accuracy Halo
    final haloPaint = Paint()
      ..color = const Color(0x334285F4) // Google Blue 20%
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, size * 0.46, haloPaint);

    final haloStroke = Paint()
      ..color = const Color(0x884285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(center, size * 0.46, haloStroke);

    // 4. Brilliant White Circular Core Puck Base Disc
    final puckBasePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, size * 0.37, puckBasePaint);

    // 5. Metallic / Slate Bevel Perimeter Rim for Razor-Sharp Road Contrast
    final puckRimPaint = Paint()
      ..color = const Color(0xFFCBD5E1) // Slate 300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2;
    canvas.drawCircle(center, size * 0.37, puckRimPaint);

    final innerRimPaint = Paint()
      ..color = const Color(0xFFF1F5F9) // Slate 100 inner highlight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, (size * 0.37) - 2.0, innerRimPaint);

    // 6. Iconic Google Maps 3D Navigation Chevron Arrow (Pointing North 0°)
    // Symmetrical chevron with central 3D fold crease
    final double tipY = center.dy - (size * 0.25);
    final double wingBottomY = center.dy + (size * 0.21);
    final double notchBottomY = center.dy + (size * 0.08);
    final double wingLeftX = center.dx - (size * 0.22);
    final double wingRightX = center.dx + (size * 0.22);

    // Left Facet (Google Royal Navigation Blue #1A73E8)
    final leftPath = Path()
      ..moveTo(center.dx, tipY)
      ..lineTo(wingLeftX, wingBottomY)
      ..lineTo(center.dx, notchBottomY)
      ..close();

    final leftGradient = ui.Gradient.linear(
      Offset(wingLeftX, tipY),
      Offset(center.dx, wingBottomY),
      [const Color(0xFF2563EB), const Color(0xFF1D4ED8)],
    );
    final leftPaint = Paint()
      ..shader = leftGradient
      ..style = PaintingStyle.fill;
    canvas.drawPath(leftPath, leftPaint);

    // Right Facet (Shaded Depth Shadow Navy #1557B0 for 3D crease)
    final rightPath = Path()
      ..moveTo(center.dx, tipY)
      ..lineTo(center.dx, notchBottomY)
      ..lineTo(wingRightX, wingBottomY)
      ..close();

    final rightGradient = ui.Gradient.linear(
      Offset(center.dx, tipY),
      Offset(wingRightX, wingBottomY),
      [const Color(0xFF1E40AF), const Color(0xFF172554)],
    );
    final rightPaint = Paint()
      ..shader = rightGradient
      ..style = PaintingStyle.fill;
    canvas.drawPath(rightPath, rightPaint);

    // Outer Crisp Chevron Bevel Border for extreme contrast
    final borderPath = Path()
      ..moveTo(center.dx, tipY)
      ..lineTo(wingLeftX, wingBottomY)
      ..lineTo(center.dx, notchBottomY)
      ..lineTo(wingRightX, wingBottomY)
      ..close();
    final borderPaint = Paint()
      ..color = const Color(0xFF1E3A8A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawPath(borderPath, borderPaint);

    // Crisp Center 3D Fold Crease Highlight
    final seamPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.80)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(center.dx, tipY), Offset(center.dx, notchBottomY), seamPaint);

    final picture = recorder.endRecording();
    final img = await picture.toImage(size, size);
    final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final descriptor = BitmapDescriptor.fromBytes(pngBytes!.buffer.asUint8List());

    _markerCache[cacheKey] = descriptor;
    return descriptor;
  }

  /// Returns the default Google Maps-style driving navigation avatar.
  /// By default, returns the iconic Google Maps 3D Chevron Navigation Puck.
  /// If vehicle-specific 3D avatar is requested, returns the high-contrast vehicle marker.
  static Future<BitmapDescriptor> getNavigationAvatarMarker({
    String? vehicleType,
    int size = 256,
    bool forceVehicleType = false,
  }) async {
    if (forceVehicleType && vehicleType != null && vehicleType.trim().isNotEmpty && vehicleType.toLowerCase() != 'puck') {
      return getCustomerVehicleMarker(vehicleType, size: size);
    }
    // Default Google Maps-style driving navigation avatar (puck & 3D chevron)
    return getGoogleDrivingPuckMarker(size: size);
  }

  /// Returns a high-DPI directional vehicle icon matching the exact booked vehicle type:
  /// Car, Bike, Auto, SUV, Van, Truck.
  /// Scaled up to 256px for ultra-sharp visibility on modern smartphones.
  static Future<BitmapDescriptor> getCustomerVehicleMarker(String? vehicleType, {int size = 256}) async {
    final type = normalizeVehicleType(vehicleType);
    final cacheKey = 'customer_vehicle_${type}_$size';

    if (_markerCache.containsKey(cacheKey)) {
      return _markerCache[cacheKey]!;
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()));
    final center = Offset(size / 2.0, size / 2.0);

    // 1. Soft Forward Heading Light Beam / Cone (Points North 0°)
    _drawForwardDirectionalBeam(canvas, center, size.toDouble());

    // 2. Navigation Ground Anchoring Halo
    _drawNavGroundHalo(canvas, center, size.toDouble());

    // 3. Render high-definition top-down vehicle based on booked type
    switch (type) {
      case 'bike':
        _drawTopDownBike(canvas, center, size.toDouble());
        break;
      case 'auto':
        _drawTopDownAuto(canvas, center, size.toDouble());
        break;
      case 'truck':
        _drawTopDownTruck(canvas, center, size.toDouble());
        break;
      case 'suv':
        _drawTopDownSuv(canvas, center, size.toDouble());
        break;
      case 'van':
        _drawTopDownVan(canvas, center, size.toDouble());
        break;
      case 'car':
      default:
        _drawTopDownCar(canvas, center, size.toDouble());
        break;
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(size, size);
    final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final descriptor = BitmapDescriptor.fromBytes(pngBytes!.buffer.asUint8List());

    _markerCache[cacheKey] = descriptor;
    return descriptor;
  }

  /// Backward-compatible alias that forwards to getCustomerVehicleMarker
  static Future<BitmapDescriptor> getVehicleMarker(String? vehicleType, {int size = 256}) async {
    return getCustomerVehicleMarker(vehicleType, size: size);
  }

  // --- COMMON NAVIGATION VISUAL ELEMENTS ---

  /// Draws a Google Maps-style soft forward illumination headlight beam / cone
  /// radiating forward (North 0°) from the vehicle center onto the road ahead.
  static void _drawForwardDirectionalBeam(Canvas canvas, Offset center, double size) {
    final beamPath = Path();
    beamPath.moveTo(center.dx, center.dy);
    final beamLength = size * 0.49;
    const halfAngleRad = 28.0 * (math.pi / 180.0); // ~28 degrees half-spread
    final leftX = center.dx - beamLength * math.sin(halfAngleRad);
    final rightX = center.dx + beamLength * math.sin(halfAngleRad);
    final topY = center.dy - beamLength * math.cos(halfAngleRad);

    beamPath.lineTo(leftX, topY);
    beamPath.arcToPoint(
      Offset(rightX, topY),
      radius: Radius.circular(beamLength),
      clockwise: true,
    );
    beamPath.close();

    final beamGradient = ui.Gradient.radial(
      center,
      beamLength,
      [
        const Color(0x664285F4), // Google Blue beam core
        const Color(0x334285F4),
        const Color(0x004285F4), // Smooth transparent fade at outer edge
      ],
      [0.0, 0.45, 1.0],
    );

    final beamPaint = Paint()
      ..shader = beamGradient
      ..style = PaintingStyle.fill;

    canvas.drawPath(beamPath, beamPaint);
  }

  /// Draws a subtle ground halo ring underneath the vehicle to guarantee high visibility
  /// across dark mode, satellite terrain, flyovers, and asphalt roads.
  static void _drawNavGroundHalo(Canvas canvas, Offset center, double size) {
    final haloPaint = Paint()
      ..color = const Color(0x222563EB)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, size * 0.42, haloPaint);

    final strokePaint = Paint()
      ..color = const Color(0x333B82F6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, size * 0.42, strokePaint);
  }

  // --- TOP-DOWN VECTOR VEHICLE DRAWING FUNCTIONS (ALL POINTING NORTH 0°) ---

  /// Top-down sleek sedan car
  static void _drawTopDownCar(Canvas canvas, Offset center, double size) {
    final double w = size * 0.42;
    final double h = size * 0.80;
    final rect = Rect.fromCenter(center: center, width: w, height: h);

    // Drop Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.38)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRRect(RRect.fromRectAndRadius(rect.shift(const Offset(0, 3)), Radius.circular(w * 0.30)), shadowPaint);

    // Body (Metallic Royal Navy Blue)
    final bodyPaint = Paint()..color = const Color(0xFF1E40AF);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(w * 0.28));
    canvas.drawRRect(rrect, bodyPaint);

    // Body trim outline for sharp road contrast
    final outlinePaint = Paint()
      ..color = const Color(0xFF60A5FA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawRRect(rrect, outlinePaint);

    // Windshield (Front curved glass)
    final windshieldRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy - h * 0.16),
      width: w * 0.78,
      height: h * 0.16,
    );
    final glassPaint = Paint()..color = const Color(0xFF0F172A);
    canvas.drawRRect(RRect.fromRectAndRadius(windshieldRect, const Radius.circular(4)), glassPaint);

    // Glass shine reflection
    final shinePaint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(center.dx - w * 0.25, center.dy - h * 0.19),
      Offset(center.dx + w * 0.1, center.dy - h * 0.13),
      shinePaint,
    );

    // Roof (Dark tinted glass top)
    final roofRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy + h * 0.03),
      width: w * 0.72,
      height: h * 0.22,
    );
    final roofPaint = Paint()..color = const Color(0xFF172554);
    canvas.drawRRect(RRect.fromRectAndRadius(roofRect, const Radius.circular(3)), roofPaint);

    // Rear Window
    final rearWindowRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy + h * 0.22),
      width: w * 0.74,
      height: h * 0.12,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(rearWindowRect, const Radius.circular(3)), glassPaint);

    // Headlights (Warm Amber/Yellow forward beams)
    final lightPaint = Paint()..color = const Color(0xFFFDE047);
    canvas.drawCircle(Offset(center.dx - w * 0.32, center.dy - h * 0.44), 3.5, lightPaint);
    canvas.drawCircle(Offset(center.dx + w * 0.32, center.dy - h * 0.44), 3.5, lightPaint);

    // Taillights (Red)
    final tailPaint = Paint()..color = const Color(0xFFEF4444);
    canvas.drawCircle(Offset(center.dx - w * 0.32, center.dy + h * 0.44), 3.0, tailPaint);
    canvas.drawCircle(Offset(center.dx + w * 0.32, center.dy + h * 0.44), 3.0, tailPaint);

    // Side Mirrors
    final mirrorPaint = Paint()..color = const Color(0xFF1E40AF);
    canvas.drawOval(Rect.fromCenter(center: Offset(center.dx - w * 0.54, center.dy - h * 0.18), width: 5, height: 9), mirrorPaint);
    canvas.drawOval(Rect.fromCenter(center: Offset(center.dx + w * 0.54, center.dy - h * 0.18), width: 5, height: 9), mirrorPaint);
  }

  /// Top-down streamlined motorcycle / scooter
  static void _drawTopDownBike(Canvas canvas, Offset center, double size) {
    final double w = size * 0.34;
    final double h = size * 0.80;

    // Drop Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.38)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawOval(Rect.fromCenter(center: center + const Offset(0, 3), width: w * 0.85, height: h * 0.92), shadowPaint);

    // Tires (Front & Rear)
    final tirePaint = Paint()..color = const Color(0xFF18181B);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(center.dx, center.dy - h * 0.36), width: w * 0.24, height: h * 0.22),
        const Radius.circular(3),
      ),
      tirePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(center.dx, center.dy + h * 0.34), width: w * 0.26, height: h * 0.24),
        const Radius.circular(3),
      ),
      tirePaint,
    );

    // Handlebars with grips
    final barPaint = Paint()
      ..color = const Color(0xFF27272A)
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(center.dx - w * 0.52, center.dy - h * 0.22),
      Offset(center.dx + w * 0.52, center.dy - h * 0.22),
      barPaint,
    );

    // Fuel Tank / Frame (Vibrant Emerald Green)
    final tankPaint = Paint()..color = const Color(0xFF16A34A);
    final tankRect = Rect.fromCenter(center: Offset(center.dx, center.dy - h * 0.08), width: w * 0.46, height: h * 0.22);
    canvas.drawRRect(RRect.fromRectAndRadius(tankRect, const Radius.circular(6)), tankPaint);

    // Rider Helmet (Circle with visor)
    final helmetPaint = Paint()..color = const Color(0xFF22C55E);
    canvas.drawCircle(Offset(center.dx, center.dy + h * 0.04), w * 0.34, helmetPaint);

    // Helmet Visor
    final visorPaint = Paint()..color = const Color(0xFF0F172A);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(center.dx, center.dy + h * 0.04), radius: w * 0.32),
      math.pi * 1.1,
      math.pi * 0.8,
      true,
      visorPaint,
    );

    // Seat & Tail Fender
    final seatPaint = Paint()..color = const Color(0xFF18181B);
    final seatRect = Rect.fromCenter(center: Offset(center.dx, center.dy + h * 0.22), width: w * 0.34, height: h * 0.20);
    canvas.drawRRect(RRect.fromRectAndRadius(seatRect, const Radius.circular(4)), seatPaint);

    // Front Headlight (Bright White/Yellow)
    final headlightPaint = Paint()..color = const Color(0xFFFEF08A);
    canvas.drawCircle(Offset(center.dx, center.dy - h * 0.44), 3.5, headlightPaint);
  }

  /// Top-down authentic Auto-Rickshaw (3-wheeler)
  static void _drawTopDownAuto(Canvas canvas, Offset center, double size) {
    final double w = size * 0.48;
    final double h = size * 0.78;

    // Drop Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.38)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final bodyPath = Path();
    bodyPath.moveTo(center.dx, center.dy - h * 0.48); // Tapered front nose
    bodyPath.lineTo(center.dx + w * 0.48, center.dy - h * 0.16);
    bodyPath.lineTo(center.dx + w * 0.48, center.dy + h * 0.46);
    bodyPath.lineTo(center.dx - w * 0.48, center.dy + h * 0.46);
    bodyPath.lineTo(center.dx - w * 0.48, center.dy - h * 0.16);
    bodyPath.close();
    canvas.drawPath(bodyPath.shift(const Offset(0, 3)), shadowPaint);

    // Front Single Tire
    final tirePaint = Paint()..color = const Color(0xFF18181B);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(center.dx, center.dy - h * 0.42), width: w * 0.18, height: h * 0.18),
        const Radius.circular(3),
      ),
      tirePaint,
    );

    // Canopy Roof - Front Half (Classic Bright Auto Yellow)
    final yellowPaint = Paint()..color = const Color(0xFFEAB308);
    final greenPaint = Paint()..color = const Color(0xFF15803D);

    canvas.drawPath(bodyPath, greenPaint); // Base chassis in auto green

    // Yellow Canopy Roof Overlay
    final roofRect = Rect.fromCenter(center: Offset(center.dx, center.dy - h * 0.05), width: w * 0.90, height: h * 0.52);
    canvas.drawRRect(RRect.fromRectAndRadius(roofRect, const Radius.circular(6)), yellowPaint);

    // Windshield (Front Glass Curved)
    final glassPaint = Paint()..color = const Color(0xFF0F172A);
    final windshieldRect = Rect.fromCenter(center: Offset(center.dx, center.dy - h * 0.22), width: w * 0.70, height: h * 0.10);
    canvas.drawRRect(RRect.fromRectAndRadius(windshieldRect, const Radius.circular(3)), glassPaint);

    // Rear Engine / Passenger Deck (Dark Green / Black)
    final rearDeckRect = Rect.fromCenter(center: Offset(center.dx, center.dy + h * 0.30), width: w * 0.88, height: h * 0.26);
    canvas.drawRRect(RRect.fromRectAndRadius(rearDeckRect, const Radius.circular(4)), greenPaint);

    // Auto Outline Border
    final borderPaint = Paint()
      ..color = const Color(0xFFCA8A04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;
    canvas.drawPath(bodyPath, borderPaint);

    // Headlight (Single center front lamp)
    final headlampPaint = Paint()..color = const Color(0xFFFEF9C3);
    canvas.drawCircle(Offset(center.dx, center.dy - h * 0.46), 4.0, headlampPaint);

    // Rear Dual Taillights
    final tailPaint = Paint()..color = const Color(0xFFEF4444);
    canvas.drawCircle(Offset(center.dx - w * 0.36, center.dy + h * 0.44), 3.0, tailPaint);
    canvas.drawCircle(Offset(center.dx + w * 0.36, center.dy + h * 0.44), 3.0, tailPaint);
  }

  /// Top-down muscular SUV / Crossover
  static void _drawTopDownSuv(Canvas canvas, Offset center, double size) {
    final double w = size * 0.48;
    final double h = size * 0.84;
    final rect = Rect.fromCenter(center: center, width: w, height: h);

    // Drop Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.40)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.drawRRect(RRect.fromRectAndRadius(rect.shift(const Offset(0, 3)), Radius.circular(w * 0.28)), shadowPaint);

    // SUV Body (Deep Sleek Graphite / Midnight Slate)
    final bodyPaint = Paint()..color = const Color(0xFF1E293B);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(w * 0.25));
    canvas.drawRRect(rrect, bodyPaint);

    // Outer Chrome Rim
    final outlinePaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;
    canvas.drawRRect(rrect, outlinePaint);

    // Panoramic Sunroof (Large glass center panel)
    final glassPaint = Paint()..color = const Color(0xFF0369A1);
    final roofGlass = Rect.fromCenter(center: Offset(center.dx, center.dy - h * 0.02), width: w * 0.72, height: h * 0.40);
    canvas.drawRRect(RRect.fromRectAndRadius(roofGlass, const Radius.circular(4)), glassPaint);

    // Front Windshield
    final windshieldRect = Rect.fromCenter(center: Offset(center.dx, center.dy - h * 0.22), width: w * 0.80, height: h * 0.14);
    canvas.drawRRect(RRect.fromRectAndRadius(windshieldRect, const Radius.circular(4)), Paint()..color = const Color(0xFF0F172A));

    // Roof Rails (Left & Right Silver Bars)
    final railPaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(center.dx - w * 0.40, center.dy - h * 0.16), Offset(center.dx - w * 0.40, center.dy + h * 0.22), railPaint);
    canvas.drawLine(Offset(center.dx + w * 0.40, center.dy - h * 0.16), Offset(center.dx + w * 0.40, center.dy + h * 0.22), railPaint);

    // Headlights (Dual Modern LED light bars)
    final ledPaint = Paint()..color = const Color(0xFFE0F2FE);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(center.dx - w * 0.32, center.dy - h * 0.46), width: 8, height: 4), const Radius.circular(1)),
      ledPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(center.dx + w * 0.32, center.dy - h * 0.46), width: 8, height: 4), const Radius.circular(1)),
      ledPaint,
    );

    // Taillights (Red LED light bars)
    final redLedPaint = Paint()..color = const Color(0xFFEF4444);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(center.dx - w * 0.32, center.dy + h * 0.46), width: 8, height: 4), const Radius.circular(1)),
      redLedPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(center.dx + w * 0.32, center.dy + h * 0.46), width: 8, height: 4), const Radius.circular(1)),
      redLedPaint,
    );
  }

  /// Top-down Goods Truck / Mini Truck (Cab + Freight Cargo Bed)
  static void _drawTopDownTruck(Canvas canvas, Offset center, double size) {
    final double w = size * 0.50;
    final double h = size * 0.88;

    // Drop Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.40)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: center + const Offset(0, 3), width: w, height: h), const Radius.circular(6)),
      shadowPaint,
    );

    // Front Driver Cabin (Vibrant Royal Purple / Indigo)
    final cabRect = Rect.fromCenter(center: Offset(center.dx, center.dy - h * 0.30), width: w * 0.92, height: h * 0.32);
    final cabPaint = Paint()..color = const Color(0xFF6D28D9);
    canvas.drawRRect(RRect.fromRectAndRadius(cabRect, const Radius.circular(6)), cabPaint);

    // Cabin Windshield
    final glassPaint = Paint()..color = const Color(0xFF0F172A);
    final windshieldRect = Rect.fromCenter(center: Offset(center.dx, center.dy - h * 0.36), width: w * 0.78, height: h * 0.12);
    canvas.drawRRect(RRect.fromRectAndRadius(windshieldRect, const Radius.circular(3)), glassPaint);

    // Extended Truck Side Mirrors
    final mirrorPaint = Paint()..color = const Color(0xFF4C1D95);
    canvas.drawRect(Rect.fromCenter(center: Offset(center.dx - w * 0.52, center.dy - h * 0.34), width: 6, height: 10), mirrorPaint);
    canvas.drawRect(Rect.fromCenter(center: Offset(center.dx + w * 0.52, center.dy - h * 0.34), width: 6, height: 10), mirrorPaint);

    // Cargo Bed / Freight Container (Sturdy White / Silver with cross bars)
    final bedRect = Rect.fromCenter(center: Offset(center.dx, center.dy + h * 0.16), width: w * 0.98, height: h * 0.58);
    final bedPaint = Paint()..color = const Color(0xFFF1F5F9);
    canvas.drawRRect(RRect.fromRectAndRadius(bedRect, const Radius.circular(4)), bedPaint);

    final bedOutline = Paint()
      ..color = const Color(0xFF7C3AED)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;
    canvas.drawRRect(RRect.fromRectAndRadius(bedRect, const Radius.circular(4)), bedOutline);

    // Container Corrugation Ribs
    final ribPaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..strokeWidth = 1.8;
    for (int i = -2; i <= 2; i++) {
      final y = center.dy + h * 0.16 + (i * (h * 0.10));
      canvas.drawLine(Offset(center.dx - w * 0.44, y), Offset(center.dx + w * 0.44, y), ribPaint);
    }

    // Front Headlights
    final lightPaint = Paint()..color = const Color(0xFFFEF08A);
    canvas.drawCircle(Offset(center.dx - w * 0.36, center.dy - h * 0.44), 3.5, lightPaint);
    canvas.drawCircle(Offset(center.dx + w * 0.36, center.dy - h * 0.44), 3.5, lightPaint);

    // Rear Hazard Reflectors
    final hazardPaint = Paint()..color = const Color(0xFFDC2626);
    canvas.drawRect(Rect.fromCenter(center: Offset(center.dx - w * 0.38, center.dy + h * 0.44), width: 7, height: 4), hazardPaint);
    canvas.drawRect(Rect.fromCenter(center: Offset(center.dx + w * 0.38, center.dy + h * 0.44), width: 7, height: 4), hazardPaint);
  }

  /// Top-down Van / Tempo
  static void _drawTopDownVan(Canvas canvas, Offset center, double size) {
    final double w = size * 0.46;
    final double h = size * 0.84;
    final rect = Rect.fromCenter(center: center, width: w, height: h);

    // Drop Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.38)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRRect(RRect.fromRectAndRadius(rect.shift(const Offset(0, 3)), Radius.circular(w * 0.25)), shadowPaint);

    // Van Body (Teal / Cyan Professional)
    final bodyPaint = Paint()..color = const Color(0xFF0F766E);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(w * 0.22));
    canvas.drawRRect(rrect, bodyPaint);

    final outlinePaint = Paint()
      ..color = const Color(0xFF2DD4BF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawRRect(rrect, outlinePaint);

    // Front Sloping Windshield
    final glassPaint = Paint()..color = const Color(0xFF0F172A);
    final windshield = Rect.fromCenter(center: Offset(center.dx, center.dy - h * 0.26), width: w * 0.80, height: h * 0.14);
    canvas.drawRRect(RRect.fromRectAndRadius(windshield, const Radius.circular(3)), glassPaint);

    // Side Windows
    final sideWindowLeft = Rect.fromCenter(center: Offset(center.dx - w * 0.36, center.dy + h * 0.05), width: w * 0.14, height: h * 0.44);
    final sideWindowRight = Rect.fromCenter(center: Offset(center.dx + w * 0.36, center.dy + h * 0.05), width: w * 0.14, height: h * 0.44);
    canvas.drawRRect(RRect.fromRectAndRadius(sideWindowLeft, const Radius.circular(2)), glassPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(sideWindowRight, const Radius.circular(2)), glassPaint);

    // Headlights
    final lightPaint = Paint()..color = const Color(0xFFFDE047);
    canvas.drawCircle(Offset(center.dx - w * 0.32, center.dy - h * 0.46), 3.5, lightPaint);
    canvas.drawCircle(Offset(center.dx + w * 0.32, center.dy - h * 0.46), 3.5, lightPaint);

    // Taillights
    final tailPaint = Paint()..color = const Color(0xFFEF4444);
    canvas.drawCircle(Offset(center.dx - w * 0.32, center.dy + h * 0.46), 3.0, tailPaint);
    canvas.drawCircle(Offset(center.dx + w * 0.32, center.dy + h * 0.46), 3.0, tailPaint);
  }

  /// Calculates the shortest angular interpolation between two headings in degrees [0, 360)
  /// Prevents marker from spinning 350 degrees when crossing North (e.g. 358 deg -> 2 deg)
  static double interpolateHeading(double from, double to, double fraction) {
    double diff = (to - from) % 360.0;
    if (diff > 180.0) diff -= 360.0;
    if (diff < -180.0) diff += 360.0;
    return (from + diff * fraction + 360.0) % 360.0;
  }

  /// Linearly interpolates between two LatLng positions
  static LatLng interpolatePosition(LatLng a, LatLng b, double fraction) {
    final lat = a.latitude + (b.latitude - a.latitude) * fraction;
    final lng = a.longitude + (b.longitude - a.longitude) * fraction;
    return LatLng(lat, lng);
  }
}
