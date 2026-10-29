import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../services/food_location_service.dart';

class LocationPinResult {
  final double latitude;
  final double longitude;
  final String address;
  final String locationDetails;

  const LocationPinResult({
    required this.latitude,
    required this.longitude,
    required this.address,
    this.locationDetails = '',
  });
}

class LocationPinPickerDialog extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final String? initialAddress;
  final String? initialDetails;
  final String title;
  final String confirmButtonText;
  final String detailsHint;

  const LocationPinPickerDialog({
    super.key,
    this.initialLat,
    this.initialLng,
    this.initialAddress,
    this.initialDetails,
    this.title = 'Set Exact Location on Map',
    this.confirmButtonText = 'Confirm & Save Location',
    this.detailsHint = 'Entrance / landmark / pickup instructions (optional)',
  });

  static Future<LocationPinResult?> show(
    BuildContext context, {
    double? initialLat,
    double? initialLng,
    String? initialAddress,
    String? initialDetails,
    String title = 'Set Exact Location on Map',
    String confirmButtonText = 'Confirm & Save Location',
    String detailsHint = 'Entrance / landmark / pickup instructions (optional)',
  }) {
    return showDialog<LocationPinResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LocationPinPickerDialog(
        initialLat: initialLat,
        initialLng: initialLng,
        initialAddress: initialAddress,
        initialDetails: initialDetails,
        title: title,
        confirmButtonText: confirmButtonText,
        detailsHint: detailsHint,
      ),
    );
  }

  @override
  State<LocationPinPickerDialog> createState() => _LocationPinPickerDialogState();
}

class _LocationPinPickerDialogState extends State<LocationPinPickerDialog> {
  GoogleMapController? _mapController;
  late LatLng _currentCenter;
  late TextEditingController _addressCtrl;
  late TextEditingController _detailsCtrl;
  late TextEditingController _searchCtrl;

  bool _isReverseGeocoding = false;
  bool _isSearching = false;
  List<Map<String, String>> _searchPredictions = [];
  Timer? _searchDebounce;
  bool _isLocatingUser = false;

  // Default coordinate: Hyderabad / Cyberabad area (StayDriv hub)
  static const LatLng _defaultCoord = LatLng(17.4485, 78.3748);

  @override
  void initState() {
    super.initState();
    double lat = widget.initialLat ?? 0.0;
    double lng = widget.initialLng ?? 0.0;

    // Safety: check for inverted coordinates (e.g. lat > 50 and lng < 40 in India)
    if (lat > 50 && lng < 40) {
      final temp = lat;
      lat = lng;
      lng = temp;
    }

    if (lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180 && (lat != 0.0 || lng != 0.0)) {
      _currentCenter = LatLng(lat, lng);
    } else {
      _currentCenter = _defaultCoord;
    }

    _addressCtrl = TextEditingController(text: widget.initialAddress ?? '');
    _detailsCtrl = TextEditingController(text: widget.initialDetails ?? '');
    _searchCtrl = TextEditingController();

    // If initial address is empty, reverse geocode current center
    if (_addressCtrl.text.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerReverseGeocode(_currentCenter);
      });
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _addressCtrl.dispose();
    _detailsCtrl.dispose();
    _searchCtrl.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _triggerReverseGeocode(LatLng target) async {
    if (!mounted) return;
    setState(() => _isReverseGeocoding = true);

    try {
      final loc = await FoodLocationService().reverseGeocode(target.latitude, target.longitude);
      if (!mounted) return;
      if (loc.address.isNotEmpty && !loc.address.startsWith('Current Location (')) {
        setState(() {
          _addressCtrl.text = loc.address;
        });
      }
    } catch (e) {
      debugPrint('[LocationPinPicker] Reverse geocode error: $e');
    } finally {
      if (mounted) setState(() => _isReverseGeocoding = false);
    }
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _isSearching = false;
        _searchPredictions = [];
      });
      return;
    }

    setState(() => _isSearching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      final preds = await FoodLocationService().searchPlaces(
        query,
        userLat: _currentCenter.latitude,
        userLng: _currentCenter.longitude,
      );
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchPredictions = preds;
      });
    });
  }

  Future<void> _selectPrediction(Map<String, String> pred) async {
    final placeId = pred['place_id'] ?? '';
    final desc = pred['description'] ?? pred['main_text'] ?? '';
    setState(() {
      _searchCtrl.clear();
      _searchPredictions = [];
      _isSearching = false;
      _addressCtrl.text = desc;
    });

    FocusScope.of(context).unfocus();

    try {
      final resolved = await FoodLocationService().geocodePlace(placeId, desc);
      if (!mounted) return;
      if (resolved != null && (resolved.latitude != 0 || resolved.longitude != 0)) {
        final newCoord = LatLng(resolved.latitude, resolved.longitude);
        setState(() {
          _currentCenter = newCoord;
          if (resolved.address.isNotEmpty) {
            _addressCtrl.text = resolved.address;
          }
        });
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(newCoord, 16.5));
      }
    } catch (e) {
      debugPrint('[LocationPinPicker] Geocode place error: $e');
    }
  }

  Future<void> _locateUserGps() async {
    setState(() => _isLocatingUser = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied. Please search or drag pin manually.')),
          );
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 4),
      );

      final userCoord = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() => _currentCenter = userCoord);
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(userCoord, 17.0));
      _triggerReverseGeocode(userCoord);
    } catch (e) {
      debugPrint('[LocationPinPicker] GPS location error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not fetch GPS position. Please drag map pin to location.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocatingUser = false);
    }
  }

  void _onConfirm() {
    double lat = _currentCenter.latitude;
    double lng = _currentCenter.longitude;

    // Safety: check for inverted coordinates (India is ~6-38° N, 68-98° E)
    if (lat > 50 && lng < 40) {
      final temp = lat;
      lat = lng;
      lng = temp;
    }

    if (lat < -90 || lat > 90 || lng < -180 || lng > 180 || (lat == 0.0 && lng == 0.0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a valid location on the map'), backgroundColor: Colors.red),
      );
      return;
    }

    final addr = _addressCtrl.text.trim();
    if (addr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide or confirm the street address'), backgroundColor: Colors.red),
      );
      return;
    }

    Navigator.of(context).pop(LocationPinResult(
      latitude: lat,
      longitude: lng,
      address: addr,
      locationDetails: _detailsCtrl.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isCompact = size.width < 600;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : (size.width - 560) / 2,
        vertical: isCompact ? 16 : 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 580,
          maxHeight: size.height * 0.88,
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
              ),
              child: Row(
                children: [
                  const Icon(Icons.place_rounded, color: Color(0xFFEF4444), size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(null),
                  ),
                ],
              ),
            ),

            // Search Bar & Autocomplete Stack
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  color: const Color(0xFF1E293B),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearchChanged,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search restaurant address, landmark, area...',
                      hintStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF38BDF8), size: 18),
                      suffixIcon: _isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)),
                              ),
                            )
                          : (_searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, color: Colors.white54, size: 16),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _searchPredictions = []);
                                  },
                                )
                              : null),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                      ),
                    ),
                  ),
                ),

                // Search Results Dropdown Overlay
                if (_searchPredictions.isNotEmpty)
                  Positioned(
                    top: 50,
                    left: 12,
                    right: 12,
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(10),
                      color: const Color(0xFF1E293B),
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 180),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.5)),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: _searchPredictions.length,
                          separatorBuilder: (context, index) => const Divider(height: 1, color: Colors.white10),
                          itemBuilder: (context, idx) {
                            final pred = _searchPredictions[idx];
                            return ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              leading: const Icon(Icons.location_on_outlined, color: Color(0xFF38BDF8), size: 16),
                              title: Text(
                                pred['main_text'] ?? '',
                                style: GoogleFonts.inter(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                              ),
                              subtitle: (pred['secondary_text'] ?? '').isNotEmpty
                                  ? Text(
                                      pred['secondary_text']!,
                                      style: GoogleFonts.inter(color: Colors.white60, fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    )
                                  : null,
                              onTap: () => _selectPrediction(pred),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            // Interactive GoogleMap with Center Movable Pin
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _currentCenter,
                      zoom: 16.5,
                    ),
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    compassEnabled: true,
                    mapToolbarEnabled: false,
                    onMapCreated: (ctrl) => _mapController = ctrl,
                    onCameraMove: (pos) {
                      _currentCenter = pos.target;
                    },
                    onCameraIdle: () {
                      _triggerReverseGeocode(_currentCenter);
                    },
                  ),

                  // Exact Centered Pin Marker
                  IgnorePointer(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 34), // Pin point sits exactly on center
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFEF4444), width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.pan_tool_alt_rounded, color: Color(0xFF38BDF8), size: 11),
                                const SizedBox(width: 4),
                                Text(
                                  'Move map to place pin',
                                  style: GoogleFonts.inter(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Icon(
                            Icons.location_on,
                            color: Color(0xFFEF4444),
                            size: 42,
                            shadows: [
                              Shadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 4)),
                            ],
                          ),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.4),
                                  blurRadius: 3,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Floating "Locate Me" Button
                  Positioned(
                    right: 14,
                    bottom: 14,
                    child: FloatingActionButton.small(
                      heroTag: 'pin_picker_locate_me_${widget.title.hashCode}',
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: const Color(0xFF38BDF8),
                      elevation: 4,
                      onPressed: _isLocatingUser ? null : _locateUserGps,
                      child: _isLocatingUser
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)))
                          : const Icon(Icons.my_location_rounded, size: 20),
                    ),
                  ),

                  // Geocoding progress badge
                  if (_isReverseGeocoding)
                    Positioned(
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white)),
                            const SizedBox(width: 6),
                            Text('Fetching address...', style: GoogleFonts.inter(color: Colors.white, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Bottom Confirmation Panel
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                border: Border(top: BorderSide(color: Color(0xFF1E293B))),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Coordinates badge
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.gps_fixed_rounded, color: Color(0xFF38BDF8), size: 12),
                            const SizedBox(width: 5),
                            Text(
                              '${_currentCenter.latitude.toStringAsFixed(6)}, ${_currentCenter.longitude.toStringAsFixed(6)}',
                              style: GoogleFonts.jetBrainsMono(
                                color: const Color(0xFFE2E8F0),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Exact Pickup Coordinates',
                        style: GoogleFonts.inter(color: Colors.white54, fontSize: 10.5),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Formatted Address Field
                  TextField(
                    controller: _addressCtrl,
                    maxLines: 2,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      labelText: 'Formatted Address *',
                      labelStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 11),
                      prefixIcon: const Icon(Icons.home_work_outlined, color: Color(0xFFEF4444), size: 16),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Location Details / Instructions Field
                  TextField(
                    controller: _detailsCtrl,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: widget.detailsHint,
                      hintStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
                      prefixIcon: const Icon(Icons.door_front_door_outlined, color: Color(0xFF38BDF8), size: 16),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Action Buttons: Cancel & Confirm
                  Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => Navigator.of(context).pop(null),
                          child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _onConfirm,
                          icon: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
                          label: Text(
                            widget.confirmButtonText,
                            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
