import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/network_config.dart';

class DeliveryLocation {
  final String address;
  final String shortAddress;
  final double latitude;
  final double longitude;
  final String type; // 'current', 'home', 'work', 'other'
  final String? landmark;

  const DeliveryLocation({
    required this.address,
    required this.shortAddress,
    required this.latitude,
    required this.longitude,
    this.type = 'current',
    this.landmark,
  });

  String get displayTitle {
    switch (type.toLowerCase()) {
      case 'home':
        return 'Home';
      case 'work':
        return 'Work';
      case 'current':
        if (shortAddress.isNotEmpty && shortAddress != address) {
          return shortAddress;
        }
        return 'Current Location';
      default:
        if (shortAddress.isNotEmpty && shortAddress != address) {
          return shortAddress;
        }
        return 'Delivery Location';
    }
  }

  String get displaySubtitle {
    if (landmark != null && landmark!.isNotEmpty) {
      return '$landmark, $address';
    }
    return address;
  }

  Map<String, dynamic> toJson() => {
        'address': address,
        'shortAddress': shortAddress,
        'latitude': latitude,
        'longitude': longitude,
        'type': type,
        if (landmark != null) 'landmark': landmark,
      };

  factory DeliveryLocation.fromJson(Map<String, dynamic> json) {
    return DeliveryLocation(
      address: json['address'] as String? ?? 'Madhapur, Hyderabad, Telangana',
      shortAddress: json['shortAddress'] as String? ?? 'Madhapur, Hyderabad',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 17.4483,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 78.3800,
      type: json['type'] as String? ?? 'current',
      landmark: json['landmark'] as String?,
    );
  }

  DeliveryLocation copyWith({
    String? address,
    String? shortAddress,
    double? latitude,
    double? longitude,
    String? type,
    String? landmark,
  }) {
    return DeliveryLocation(
      address: address ?? this.address,
      shortAddress: shortAddress ?? this.shortAddress,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      type: type ?? this.type,
      landmark: landmark ?? this.landmark,
    );
  }
}

enum LocationPermissionState {
  granted,
  denied,
  deniedForever,
  serviceDisabled,
}

class FoodLocationService {
  static final FoodLocationService _instance = FoodLocationService._internal();
  factory FoodLocationService() => _instance;
  FoodLocationService._internal();

  static const String _prefKeyCurrent = 'staydriv_food_delivery_location_v2';
  static const String _prefKeySavedList = 'staydriv_food_saved_addresses_v2';

  String get _baseUrl => NetworkConfig.backendUrl;

  /// Check current device location permission state without requesting
  Future<LocationPermissionState> checkPermissionState() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled().timeout(
        const Duration(seconds: 2),
        onTimeout: () => false,
      );
      if (!serviceEnabled) {
        return LocationPermissionState.serviceDisabled;
      }

      final permission = await Geolocator.checkPermission().timeout(
        const Duration(seconds: 2),
        onTimeout: () => LocationPermission.denied,
      );
      if (permission == LocationPermission.deniedForever) {
        return LocationPermissionState.deniedForever;
      }
      if (permission == LocationPermission.denied) {
        return LocationPermissionState.denied;
      }
      return LocationPermissionState.granted;
    } catch (e) {
      debugPrint('[FoodLocationService] Error checking permission: $e');
      return LocationPermissionState.denied;
    }
  }

  /// Automatically detect device live GPS coordinates and reverse geocode
  Future<DeliveryLocation?> detectLiveGpsLocation({bool requestIfDenied = false}) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[FoodLocationService] Location service disabled');
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestIfDenied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        debugPrint('[FoodLocationService] Permission not granted: $permission');
        return null;
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 8),
        );
      } catch (e) {
        debugPrint('[FoodLocationService] High accuracy timeout, trying last known position: $e');
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        return null;
      }

      final resolved = await reverseGeocode(
        position.latitude,
        position.longitude,
        type: 'current',
      );

      // Cache as last known delivery location
      await saveCurrentLocation(resolved);
      return resolved;
    } catch (e) {
      debugPrint('[FoodLocationService] Error detecting GPS location: $e');
      return null;
    }
  }

  /// Reverse geocode latitude and longitude into human-readable delivery address
  Future<DeliveryLocation> reverseGeocode(
    double lat,
    double lng, {
    String type = 'current',
    String? landmark,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/places/reverse-geocode?lat=$lat&lng=$lng');
      final res = await http.get(uri).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['status'] == 'OK' || data['success'] == true) {
          String formatted = (data['formatted_address'] as String? ?? '').trim();
          String short = (data['short_address'] as String? ?? '').trim();

          // Strip trailing "India" or postal code prefixes if needed
          formatted = formatted.replaceAll(RegExp(r',?\s*India$', caseSensitive: false), '').trim();

          if (short.isEmpty && formatted.isNotEmpty) {
            final parts = formatted.split(',');
            short = parts.length > 1 ? '${parts[0].trim()}, ${parts[1].trim()}' : parts[0].trim();
          }

          if (formatted.isNotEmpty) {
            return DeliveryLocation(
              address: formatted,
              shortAddress: short.isNotEmpty ? short : formatted,
              latitude: lat,
              longitude: lng,
              type: type,
              landmark: landmark,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[FoodLocationService] Reverse geocode network error: $e');
    }

    // Graceful fallback if reverse geocoding is unavailable
    final fallbackShort = 'GPS (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})';
    return DeliveryLocation(
      address: 'Current Location (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})',
      shortAddress: fallbackShort,
      latitude: lat,
      longitude: lng,
      type: type,
      landmark: landmark,
    );
  }

  /// Search places autocomplete via StayDriv Places API
  Future<List<Map<String, String>>> searchPlaces(String query, {double? userLat, double? userLng}) async {
    if (query.trim().length < 2) return [];

    try {
      var urlStr = '$_baseUrl/api/places/autocomplete?input=${Uri.encodeComponent(query.trim())}';
      if (userLat != null && userLng != null) {
        urlStr += '&lat=$userLat&lng=$userLng';
      }

      final res = await http.get(Uri.parse(urlStr)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final predictions = data['predictions'] as List<dynamic>? ?? [];

        return predictions.map((p) {
          final desc = p['description'] as String? ?? '';
          final placeId = p['place_id'] as String? ?? '';
          final structured = p['structured_formatting'] as Map<String, dynamic>? ?? {};
          final mainText = structured['main_text'] as String? ?? desc.split(',').first;
          final secText = structured['secondary_text'] as String? ?? '';

          return {
            'place_id': placeId,
            'description': desc,
            'main_text': mainText,
            'secondary_text': secText,
          };
        }).toList();
      }
    } catch (e) {
      debugPrint('[FoodLocationService] Autocomplete search error: $e');
    }
    return [];
  }

  /// Resolve place_id or textual address into LatLng and formatted address
  Future<DeliveryLocation?> geocodePlace(
    String placeId,
    String description, {
    String type = 'other',
  }) async {
    try {
      final url = '$_baseUrl/api/places/geocode?place_id=${Uri.encodeComponent(placeId)}&address=${Uri.encodeComponent(description)}';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['status'] == 'OK' && data['location'] != null) {
          final loc = data['location'];
          final lat = (loc['lat'] as num).toDouble();
          final lng = (loc['lng'] as num).toDouble();
          final formatted = (data['formatted_address'] as String?)?.replaceAll(RegExp(r',?\s*India$', caseSensitive: false), '').trim() ?? description;
          final name = data['name'] as String? ?? description.split(',').first;

          return DeliveryLocation(
            address: formatted,
            shortAddress: name,
            latitude: lat,
            longitude: lng,
            type: type,
          );
        }
      }
    } catch (e) {
      debugPrint('[FoodLocationService] Geocode place error: $e');
    }
    return null;
  }

  /// Read the user's currently confirmed delivery location from cache
  Future<DeliveryLocation> getSavedLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefKeyCurrent);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        return DeliveryLocation.fromJson(jsonDecode(jsonStr));
      }
    } catch (e) {
      debugPrint('[FoodLocationService] Error reading saved location: $e');
    }

    // Default fallback in Hyderabad IT corridor
    return const DeliveryLocation(
      address: 'Flat 402, Highrise Heights, Madhapur, Hyderabad, Telangana',
      shortAddress: 'Madhapur, Hyderabad',
      latitude: 17.4483,
      longitude: 78.3800,
      type: 'home',
    );
  }

  /// Persist the selected delivery location
  Future<void> saveCurrentLocation(DeliveryLocation location) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyCurrent, jsonEncode(location.toJson()));
    } catch (e) {
      debugPrint('[FoodLocationService] Error saving current location: $e');
    }
  }

  /// Get list of saved preset addresses (Home, Work, Recent)
  Future<List<DeliveryLocation>> getSavedAddresses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final listStr = prefs.getStringList(_prefKeySavedList);
      if (listStr != null && listStr.isNotEmpty) {
        return listStr.map((str) => DeliveryLocation.fromJson(jsonDecode(str))).toList();
      }
    } catch (e) {
      debugPrint('[FoodLocationService] Error reading saved addresses: $e');
    }

    // Return initial default presets
    return const [
      DeliveryLocation(
        address: 'Flat 402, Highrise Heights, Madhapur, Hyderabad, Telangana',
        shortAddress: 'Madhapur, Hyderabad',
        latitude: 17.4483,
        longitude: 78.3800,
        type: 'home',
      ),
      DeliveryLocation(
        address: 'Cyber Towers, Hitec City Main Road, Madhapur, Hyderabad',
        shortAddress: 'Cyber Towers, Hitec City',
        latitude: 17.4504,
        longitude: 78.3808,
        type: 'work',
      ),
    ];
  }

  /// Save or update a preset address
  Future<void> saveAddressPreset(DeliveryLocation location) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = await getSavedAddresses();
      final updated = existing.where((e) => e.type != location.type || e.address != location.address).toList();
      updated.insert(0, location);

      // Keep max 5 saved addresses
      final trimmed = updated.take(5).toList();
      final encoded = trimmed.map((e) => jsonEncode(e.toJson())).toList();
      await prefs.setStringList(_prefKeySavedList, encoded);
    } catch (e) {
      debugPrint('[FoodLocationService] Error saving address preset: $e');
    }
  }
}
