import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'theme.dart';

class SharedLocationResult {
  final String originalText;
  final String title;
  final LatLng? coordinates;
  final String? mapsUrl;

  // Rich StayDriv Ride Deep Link Parameters
  final bool isStayDrivRideLink;
  final String? pickupAddress;
  final LatLng? pickupLatLng;
  final String? dropAddress;
  final LatLng? dropLatLng;
  final String serviceType;
  final String? rideRef;
  final String? bookingId;
  final String? trackingToken;

  SharedLocationResult({
    required this.originalText,
    required this.title,
    this.coordinates,
    this.mapsUrl,
    this.isStayDrivRideLink = false,
    this.pickupAddress,
    this.pickupLatLng,
    this.dropAddress,
    this.dropLatLng,
    this.serviceType = 'bike',
    this.rideRef,
    this.bookingId,
    this.trackingToken,
  });

  bool get hasBothLocations =>
      (pickupAddress != null || pickupLatLng != null) &&
      (dropAddress != null || dropLatLng != null);

  bool get isTrackingLink =>
      trackingToken != null && trackingToken!.trim().isNotEmpty;

  @override
  String toString() =>
      'SharedLocationResult(title: $title, isStayDriv: $isStayDrivRideLink, pickup: $pickupAddress, drop: $dropAddress, service: $serviceType)';
}

class LocationShareService {
  static final LocationShareService _instance = LocationShareService._internal();
  static LocationShareService get instance => _instance;

  static const MethodChannel _channel = MethodChannel('com.staydriv.app/location_share');

  final StreamController<SharedLocationResult> _locationStreamController =
      StreamController<SharedLocationResult>.broadcast();

  Stream<SharedLocationResult> get onLocationShared => _locationStreamController.stream;

  bool _isInitialized = false;

  static String? _pendingRawLink;
  static String? get pendingRawLink => _pendingRawLink;

  LocationShareService._internal();

  /// Cache pending deep link so it survives login navigation or cold start
  static Future<void> savePendingLink(String link) async {
    _pendingRawLink = link;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_deep_link', link);
    } catch (_) {}
  }

  /// Retrieve and clear any pending deep link after login
  static Future<String?> consumePendingLink() async {
    if (_pendingRawLink != null && _pendingRawLink!.trim().isNotEmpty) {
      final link = _pendingRawLink;
      _pendingRawLink = null;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('pending_deep_link');
      } catch (_) {}
      return link;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final link = prefs.getString('pending_deep_link');
      if (link != null && link.trim().isNotEmpty) {
        await prefs.remove('pending_deep_link');
        return link;
      }
    } catch (_) {}
    return null;
  }

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

    // Check if app was cold-started from an intent or has a pending link
    _checkInitialIntent(onLocationReceived);
  }

  Future<void> _checkInitialIntent(Function(SharedLocationResult) onLocationReceived) async {
    try {
      String? rawData = await consumePendingLink();
      if (rawData == null || rawData.trim().isEmpty) {
        rawData = await _channel.invokeMethod<String>('getInitialSharedLocation');
      }
      if (rawData != null && rawData.trim().isNotEmpty) {
        final result = await parseSharedText(rawData);
        _locationStreamController.add(result);
        onLocationReceived(result);
      }
    } catch (e) {
      debugPrint('LocationShareService initial intent error: $e');
    }
  }

  /// Parses raw text, deep links, Google Maps URLs, or geo: URIs
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
    } else if (cleanText.startsWith('staydriv://') || cleanText.startsWith('geo:')) {
      foundUrl = cleanText;
    }

    // 2. CHECK FOR STAYDRIV RIDE BOOKING DEEP LINKS
    if (foundUrl != null &&
        (foundUrl.contains('staydriv.in') ||
         foundUrl.contains('staydriv.com') ||
         foundUrl.contains('cloudfront.net') ||
         foundUrl.startsWith('staydriv://'))) {
      try {
        final uri = Uri.parse(foundUrl);
        final params = uri.queryParameters;

        // Check for live tracking link (/track/:token)
        if (uri.path.contains('/track/')) {
          final parts = uri.path.split('/');
          final trackIdx = parts.indexOf('track');
          final token = (trackIdx != -1 && trackIdx + 1 < parts.length) ? parts[trackIdx + 1] : '';
          return SharedLocationResult(
            originalText: raw,
            title: 'Live Trip Tracking',
            isStayDrivRideLink: true,
            trackingToken: token.isNotEmpty ? token : params['token'],
            bookingId: params['rideId'] ?? params['bookingId'],
            rideRef: params['ref'],
          );
        }

        // Extract ride booking locations
        final pickup = params['pickup'] ?? params['pname'] ?? params['from'] ?? params['pickupName'];
        final drop = params['drop'] ?? params['dname'] ?? params['to'] ?? params['destination'] ?? params['dropName'];

        LatLng? pickupLatLng;
        final platStr = params['plat'] ?? params['pickupLat'] ?? params['fromLat'];
        final plngStr = params['plng'] ?? params['pickupLng'] ?? params['fromLng'];
        if (platStr != null && plngStr != null) {
          final plat = double.tryParse(platStr);
          final plng = double.tryParse(plngStr);
          if (plat != null && plng != null) {
            pickupLatLng = LatLng(plat, plng);
          }
        }

        LatLng? dropLatLng;
        final dlatStr = params['dlat'] ?? params['dropLat'] ?? params['toLat'];
        final dlngStr = params['dlng'] ?? params['dropLng'] ?? params['toLng'];
        if (dlatStr != null && dlngStr != null) {
          final dlat = double.tryParse(dlatStr);
          final dlng = double.tryParse(dlngStr);
          if (dlat != null && dlng != null) {
            dropLatLng = LatLng(dlat, dlng);
          }
        }

        final rawService = (params['service'] ?? params['serviceType'] ?? params['vehicle'] ?? 'bike').toLowerCase();
        String serviceType = 'bike';
        if (rawService.contains('auto')) {
          serviceType = 'auto';
        } else if (rawService.contains('car') || rawService.contains('cab')) {
          serviceType = 'car';
        } else if (rawService.contains('parcel') || rawService.contains('delivery')) {
          serviceType = 'parcel';
        } else if (rawService.contains('truck')) {
          serviceType = 'heavy_truck';
        }

        String rideTitle = 'StayDriv Ride';
        if (pickup != null && drop != null) {
          rideTitle = '$pickup → $drop';
        } else if (drop != null) {
          rideTitle = 'Ride to $drop';
        } else if (pickup != null) {
          rideTitle = 'Pickup from $pickup';
        }

        return SharedLocationResult(
          originalText: raw,
          title: rideTitle,
          isStayDrivRideLink: true,
          pickupAddress: pickup,
          pickupLatLng: pickupLatLng,
          dropAddress: drop,
          dropLatLng: dropLatLng,
          serviceType: serviceType,
          rideRef: params['ref'] ?? params['rideRef'],
          bookingId: params['bookingId'] ?? params['rideId'],
          mapsUrl: foundUrl,
        );
      } catch (e) {
        debugPrint('[LocationShareService] Error parsing StayDriv deep link: $e');
      }
    }

    // 3. CHECK FOR GEO: SCHEME (e.g. geo:17.4834,78.3871?q=... or geo:0,0?q=17.4834,78.3871(Title))
    if (cleanText.startsWith('geo:')) {
      try {
        final geoContent = cleanText.replaceFirst('geo:', '');
        final querySplit = geoContent.split('?');
        final latLngPart = querySplit.first;

        if (querySplit.length > 1) {
          final qParam = Uri.splitQueryString(querySplit[1])['q'] ?? '';
          if (qParam.isNotEmpty) {
            // Check if label enclosed in parentheses e.g. 17.48,78.38(Hitec City)
            final labelMatch = RegExp(r'\(([^)]+)\)').firstMatch(qParam);
            if (labelMatch != null) {
              locationTitle = labelMatch.group(1)!;
            } else if (!qParam.contains(',')) {
              locationTitle = qParam;
            }
            final qCoords = _extractCoordsFromText(qParam);
            if (qCoords != null) {
              foundCoords = qCoords;
            }
          }
        }

        if (foundCoords == null && latLngPart.contains(',')) {
          final parts = latLngPart.split(',');
          if (parts.length >= 2) {
            final lat = double.tryParse(parts[0].trim());
            final lng = double.tryParse(parts[1].trim());
            if (lat != null && lng != null && (lat != 0.0 || lng != 0.0)) {
              foundCoords = LatLng(lat, lng);
            }
          }
        }

        return SharedLocationResult(
          originalText: raw,
          title: locationTitle.isNotEmpty ? locationTitle : 'Dropped Location',
          coordinates: foundCoords,
        );
      } catch (e) {
        debugPrint('[LocationShareService] Error parsing geo URI: $e');
      }
    }

    // 4. PARSE GOOGLE MAPS OR STANDARD LOCATION URLS
    if (foundUrl != null) {
      final withoutUrl = cleanText.replaceFirst(foundUrl, '').trim();
      if (withoutUrl.isNotEmpty) {
        final lines = withoutUrl.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
        if (lines.isNotEmpty) {
          locationTitle = lines.first;
        }
      }

      foundCoords = _extractCoordsFromUrl(foundUrl);

      // If short URL (e.g. maps.app.goo.gl or goo.gl/maps), resolve redirect to get coordinates
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
    } else {
      final lines = cleanText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      if (lines.isNotEmpty) {
        locationTitle = lines.first;
      }
    }

    // 5. REGEX FALLBACK FOR COORDINATES IN PLAIN TEXT
    if (foundCoords == null) {
      foundCoords = _extractCoordsFromText(cleanText);
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

    return SharedLocationResult(
      originalText: raw,
      title: locationTitle,
      coordinates: foundCoords,
      mapsUrl: foundUrl,
    );
  }

  static LatLng? _extractCoordsFromText(String text) {
    try {
      final coordsRegex = RegExp(r'([-+]?\d{1,2}\.\d+)[,\s]+([-+]?\d{1,3}\.\d+)');
      final coordsMatch = coordsRegex.firstMatch(text);
      if (coordsMatch != null) {
        final lat = double.parse(coordsMatch.group(1)!);
        final lng = double.parse(coordsMatch.group(2)!);
        if (lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
          return LatLng(lat, lng);
        }
      }
    } catch (_) {}
    return null;
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
