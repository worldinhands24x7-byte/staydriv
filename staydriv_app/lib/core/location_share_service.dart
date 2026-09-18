import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'theme.dart';

class SharedLocationResult {
  final String originalText;
  final String title;
  final LatLng? coordinates;
  final String? mapsUrl;

  SharedLocationResult({
    required this.originalText,
    required this.title,
    this.coordinates,
    this.mapsUrl,
  });

  @override
  String toString() => 'SharedLocationResult(title: $title, coords: $coordinates, url: $mapsUrl)';
}

class LocationShareService {
  static final LocationShareService _instance = LocationShareService._internal();
  static LocationShareService get instance => _instance;

  static const MethodChannel _channel = MethodChannel('com.staydriv.app/location_share');

  final StreamController<SharedLocationResult> _locationStreamController =
      StreamController<SharedLocationResult>.broadcast();

  Stream<SharedLocationResult> get onLocationShared => _locationStreamController.stream;

  bool _isInitialized = false;

  LocationShareService._internal();

  void init({required Function(SharedLocationResult) onLocationReceived}) {
    if (_isInitialized) return;
    _isInitialized = true;

    // Listen for method channel invocations from native Android (onNewIntent)
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLocationReceived') {
        final rawText = call.arguments?.toString();
        if (rawText != null && rawText.trim().isNotEmpty) {
          final result = await parseSharedText(rawText);
          _locationStreamController.add(result);
          onLocationReceived(result);
        }
      }
    });

    // Check if app was cold-started from a share intent
    _checkInitialIntent(onLocationReceived);
  }

  Future<void> _checkInitialIntent(Function(SharedLocationResult) onLocationReceived) async {
    try {
      final initialData = await _channel.invokeMethod<String>('getInitialSharedLocation');
      if (initialData != null && initialData.trim().isNotEmpty) {
        final result = await parseSharedText(initialData);
        _locationStreamController.add(result);
        onLocationReceived(result);
      }
    } catch (e) {
      debugPrint('LocationShareService initial intent error: $e');
    }
  }

  /// Parses raw text shared from Google Maps or other apps
  static Future<SharedLocationResult> parseSharedText(String raw) async {
    String cleanText = raw.trim();
    String? foundUrl;
    LatLng? foundCoords;
    String locationTitle = 'Shared Location';

    // 1. Extract URL if present
    final urlRegex = RegExp(r'https?://[^\s]+');
    final match = urlRegex.firstMatch(cleanText);
    if (match != null) {
      foundUrl = match.group(0);
      // Remove URL from title candidate
      final withoutUrl = cleanText.replaceFirst(foundUrl!, '').trim();
      if (withoutUrl.isNotEmpty) {
        // First line or non-empty line as title
        final lines = withoutUrl.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
        if (lines.isNotEmpty) {
          locationTitle = lines.first;
        }
      }
    } else {
      final lines = cleanText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      if (lines.isNotEmpty) {
        locationTitle = lines.first;
      }
    }

    // Clean up generic prefixes from Google Maps
    if (locationTitle.startsWith('Share Current Location') ||
        locationTitle.startsWith('Dropped pin') ||
        locationTitle.isEmpty) {
      final lines = cleanText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      for (final line in lines) {
        if (!line.startsWith('http') &&
            !line.startsWith('Share Current Location') &&
            !line.startsWith('Dropped pin')) {
          locationTitle = line;
          break;
        }
      }
      if (locationTitle.isEmpty || locationTitle.startsWith('http')) {
        locationTitle = 'Google Maps Location';
      }
    }

    // 2. Direct regex search for lat,lng in text: e.g. 17.4834, 78.3871
    final coordsRegex = RegExp(r'([-+]?\d{1,2}\.\d+)[,\s]+([-+]?\d{1,3}\.\d+)');
    final coordsMatch = coordsRegex.firstMatch(cleanText);
    if (coordsMatch != null) {
      try {
        final lat = double.parse(coordsMatch.group(1)!);
        final lng = double.parse(coordsMatch.group(2)!);
        if (lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
          foundCoords = LatLng(lat, lng);
        }
      } catch (_) {}
    }

    // 3. Check geo: scheme URI: e.g. geo:17.4834,78.3871?q=...
    if (foundCoords == null && cleanText.startsWith('geo:')) {
      final geoContent = cleanText.replaceFirst('geo:', '');
      final querySplit = geoContent.split('?');
      final latLngPart = querySplit.first;
      final parts = latLngPart.split(',');
      if (parts.length >= 2) {
        try {
          final lat = double.parse(parts[0].trim());
          final lng = double.parse(parts[1].trim());
          foundCoords = LatLng(lat, lng);
        } catch (_) {}
      }
    }

    // 4. If URL exists and no coords yet, inspect and resolve Google Maps URL
    if (foundCoords == null && foundUrl != null) {
      foundCoords = _extractCoordsFromUrl(foundUrl);

      // If short URL (e.g. maps.app.goo.gl or goo.gl/maps), resolve redirect to get full URL
      if (foundCoords == null &&
          (foundUrl.contains('maps.app.goo.gl') || foundUrl.contains('goo.gl'))) {
        try {
          final client = http.Client();
          final request = http.Request('GET', Uri.parse(foundUrl))..followRedirects = true;
          final response = await client.send(request).timeout(const Duration(seconds: 3));
          final finalUrl = response.headers['location'] ?? response.request?.url.toString();
          if (finalUrl != null) {
            foundCoords = _extractCoordsFromUrl(finalUrl);
          }
          client.close();
        } catch (e) {
          debugPrint('Could not resolve Google Maps short URL: $e');
        }
      }
    }

    return SharedLocationResult(
      originalText: raw,
      title: locationTitle,
      coordinates: foundCoords,
      mapsUrl: foundUrl,
    );
  }

  static LatLng? _extractCoordsFromUrl(String url) {
    try {
      // Pattern 1: /@17.4834,78.3871
      final atMatch = RegExp(r'/@([-+]?\d{1,2}\.\d+),([-+]?\d{1,3}\.\d+)').firstMatch(url);
      if (atMatch != null) {
        final lat = double.parse(atMatch.group(1)!);
        final lng = double.parse(atMatch.group(2)!);
        return LatLng(lat, lng);
      }

      // Pattern 2: ?q=17.4834,78.3871 or &q=17.4834,78.3871 or ?ll=17.4834,78.3871
      final qMatch = RegExp(r'[?&](?:q|ll|query)=([-+]?\d{1,2}\.\d+)[,\s]+([-+]?\d{1,3}\.\d+)').firstMatch(url);
      if (qMatch != null) {
        final lat = double.parse(qMatch.group(1)!);
        final lng = double.parse(qMatch.group(2)!);
        return LatLng(lat, lng);
      }
    } catch (_) {}
    return null;
  }

  /// Displays the interactive location confirmation modal to the customer
  static void showSharedLocationPrompt({
    required BuildContext context,
    required SharedLocationResult location,
    required Function({required bool isDrop}) onLocationSelected,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: const Icon(
                      Icons.pin_drop_rounded,
                      color: Color(0xFF2563EB),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Google Maps Location Received',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF2563EB),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          location.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.onSurfaceColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              if (location.coordinates != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.my_location_rounded, size: 14, color: AppTheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text(
                        'Coordinates: ${location.coordinates!.latitude.toStringAsFixed(4)}, ${location.coordinates!.longitude.toStringAsFixed(4)}',
                        style: GoogleFonts.robotoMono(
                          fontSize: 12,
                          color: AppTheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              Text(
                'How would you like to use this location?',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),

              // Button 1: Set as Drop Destination (Recommended for bookings)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onLocationSelected(isDrop: true);
                  },
                  icon: const Icon(Icons.navigation_rounded, color: Colors.white, size: 20),
                  label: Text(
                    'Book Ride to this Location',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF004AC6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Button 2: Set as Pickup Location
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onLocationSelected(isDrop: false);
                  },
                  icon: const Icon(Icons.trip_origin_rounded, color: AppTheme.primaryColor, size: 18),
                  label: Text(
                    'Set as Pickup Location',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF004AC6), width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
