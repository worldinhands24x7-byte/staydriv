import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../../core/theme.dart';
import '../../../core/razorpay_gateway.dart';
import '../../../core/booking_manager.dart';
import '../../../core/firebase_service.dart';
import '../../../core/network_monitor.dart';
import '../../live_tracking/screens/live_tracking_screen.dart';
import '../../../core/network_config.dart';
import '../../../core/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlacePredictionItem {
  final String description;
  final String mainText;
  final String secondaryText;
  final String placeId;
  final double? lat;
  final double? lng;

  PlacePredictionItem({
    required this.description,
    required this.mainText,
    required this.secondaryText,
    required this.placeId,
    this.lat,
    this.lng,
  });

  factory PlacePredictionItem.fromJson(Map<String, dynamic> json) {
    return PlacePredictionItem(
      description: json['description'] ?? '',
      mainText: json['main_text'] ?? (json['description'] ?? '').split(',')[0].trim(),
      secondaryText: json['secondary_text'] ?? '',
      placeId: json['place_id'] ?? '',
      lat: json['lat'] != null ? (json['lat'] as num).toDouble() : null,
      lng: json['lng'] != null ? (json['lng'] as num).toDouble() : null,
    );
  }
}

class RideSelectionScreen extends StatefulWidget {
  final String serviceType;
  final String userName;
  final String phoneNumber;
  final String? initialDropAddress;
  final LatLng? initialDropLatLng;
  final String? initialPickupAddress;
  final LatLng? initialPickupLatLng;
  
  const RideSelectionScreen({
    super.key,
    required this.serviceType,
    this.userName = 'Customer',
    this.phoneNumber = '9999999999',
    this.initialDropAddress,
    this.initialDropLatLng,
    this.initialPickupAddress,
    this.initialPickupLatLng,
  });

  @override
  State<RideSelectionScreen> createState() => _RideSelectionScreenState();
}

class _RideSelectionScreenState extends State<RideSelectionScreen> {
  int _currentStep = 0; // 0 = Location selection screen, 1 = Select on map, 2 = Route Map & Booking
  double _cancellationCharge = 0.0;
  bool _selectingPickupOnMap = true;

  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropController = TextEditingController();
  
  final FocusNode _pickupFocusNode = FocusNode();
  final FocusNode _dropFocusNode = FocusNode();
  bool _isPickupActive = true;

  LatLng? _pickupLatLng;
  LatLng? _dropLatLng;

  String _pickupQuery = '';
  String _dropQuery = '';
  List<PlacePredictionItem> _pickupPredictions = [];
  List<PlacePredictionItem> _dropPredictions = [];
  Timer? _debounceTimer;
  bool _isLoadingPredictions = false;

  final List<Map<String, dynamic>> _quickDestinations = [
    {
      'title': 'Secunderabad Stn',
      'subtitle': 'Railway Station, Secunderabad',
      'icon': Icons.train_rounded,
      'latLng': const LatLng(17.4344, 78.5015),
    },
    {
      'title': 'RGIA Airport',
      'subtitle': 'Shamshabad, Hyderabad',
      'icon': Icons.flight_takeoff_rounded,
      'latLng': const LatLng(17.2403, 78.4294),
    },
    {
      'title': 'Hitech City',
      'subtitle': 'Cyber Towers, Madhapur',
      'icon': Icons.business_rounded,
      'latLng': const LatLng(17.4504, 78.3808),
    },
    {
      'title': 'Charminar',
      'subtitle': 'Old City, Hyderabad',
      'icon': Icons.account_balance_rounded,
      'latLng': const LatLng(17.3616, 78.4747),
    },
    {
      'title': 'Gachibowli',
      'subtitle': 'Financial District / DLF',
      'icon': Icons.location_city_rounded,
      'latLng': const LatLng(17.4401, 78.3489),
    },
    {
      'title': 'Ameerpet',
      'subtitle': 'Metro Station / Crossroads',
      'icon': Icons.subway_rounded,
      'latLng': const LatLng(17.4375, 78.4483),
    },
    {
      'title': 'Jubilee Hills',
      'subtitle': 'Road No. 36 / Checkpost',
      'icon': Icons.nature_people_rounded,
      'latLng': const LatLng(17.4319, 78.4073),
    },
  ];

  int _selectedOptionIndex = 0;
  bool _isConfirming = false;

  // Parcel Specific State Variables
  bool get _isParcel => widget.serviceType == 'parcel' || widget.serviceType == 'heavy_truck';
  int _parcelStep = 0; // 0=Pickup Search, 1=Confirm Pickup Details, 2=Parcel Dashboard, 3=Confirm Drop Details, 4=Route & Fare, 5=Drop Search

  final TextEditingController _pickupHouseController = TextEditingController(text: 'House No -84, Rishipranavam residancy');
  final TextEditingController _pickupNameController = TextEditingController();
  final TextEditingController _pickupPhoneController = TextEditingController();
  bool _pickupUseMyContact = false;
  String _pickupFavourite = '';

  final TextEditingController _dropHouseController = TextEditingController();
  final TextEditingController _dropNameController = TextEditingController();
  final TextEditingController _dropPhoneController = TextEditingController();
  bool _dropUseMyContact = false;
  String _dropFavourite = '';

  GoogleMapController? _mapController;
  final LatLng _center = const LatLng(17.4834, 78.3871); // Default center (Hyderabad)
  final String _apiKey = 'AIzaSyD2Lw1UPJAVtzSBY4JARHS6yV284w2hneg';

  String? _distance;
  String? _duration;
  
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  List<LatLng> _routePoints = [];
  
  LatLng _mapSelectionCenter = const LatLng(17.4834, 78.3871);
  String _selectedPaymentMethod = 'Pay After Ride';
  DateTime? _heavyTruckDate;
  String? _heavyTruckTimeSlot;
  bool _acceptHeavyTruckTollgateTerms = false;

  // Previous searched locations (starts empty, populated dynamically)
  final List<Map<String, dynamic>> _historyLocations = [];


  // Saved places
  String _savedHomeAddress = 'House No -84, Rishipranavam residancy, balaji layout, Gajularamaram, Hyderabad';
  LatLng _savedHomeLatLng = const LatLng(17.526395, 78.424095);
  String _savedWorkAddress = 'Cyber Towers, Hitech City, Madhapur, Hyderabad';
  LatLng _savedWorkLatLng = const LatLng(17.4504, 78.3808);

  Future<void> _loadSavedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedHome = prefs.getString('saved_home_address');
      final savedHomeLat = prefs.getDouble('saved_home_lat');
      final savedHomeLng = prefs.getDouble('saved_home_lng');
      final savedHouse = prefs.getString('saved_pickup_house');
      final savedWork = prefs.getString('saved_work_address');
      final savedWorkLat = prefs.getDouble('saved_work_lat');
      final savedWorkLng = prefs.getDouble('saved_work_lng');

      if (mounted) {
        setState(() {
          if (savedHome != null && savedHome.isNotEmpty) {
            _savedHomeAddress = savedHome;
            if (savedHomeLat != null && savedHomeLng != null) {
              _savedHomeLatLng = LatLng(savedHomeLat, savedHomeLng);
            }
          }
          if (savedHouse != null && savedHouse.isNotEmpty) {
            _pickupHouseController.text = savedHouse;
          } else {
            _pickupHouseController.text = 'House No -84, Rishipranavam residancy';
          }
          if (savedWork != null && savedWork.isNotEmpty) {
            _savedWorkAddress = savedWork;
            if (savedWorkLat != null && savedWorkLng != null) {
              _savedWorkLatLng = LatLng(savedWorkLat, savedWorkLng);
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading saved preferences: $e');
    }
  }

  void _selectHomeAddress() {
    setState(() {
      _pickupHouseController.text = 'House No -84, Rishipranavam residancy';
      _pickupController.text = _savedHomeAddress;
      _pickupQuery = _savedHomeAddress;
      _pickupLatLng = _savedHomeLatLng;
      _pickupPredictions = [];
      if (_dropController.text.isEmpty) {
        _isPickupActive = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _dropFocusNode.requestFocus();
        });
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Selected Home: House No -84, Rishipranavam residancy, Balaji Layout'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );

    _checkAndCalculateRoute();
  }

  void _selectWorkAddress() {
    setState(() {
      if (_isPickupActive && _pickupController.text.isNotEmpty) {
        _dropController.text = _savedWorkAddress;
        _dropQuery = _savedWorkAddress;
        _dropLatLng = _savedWorkLatLng;
        _dropPredictions = [];
      } else {
        _pickupController.text = _savedWorkAddress;
        _pickupQuery = _savedWorkAddress;
        _pickupLatLng = _savedWorkLatLng;
        _pickupPredictions = [];
        if (_dropController.text.isEmpty) {
          _isPickupActive = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _dropFocusNode.requestFocus();
          });
        }
      }
    });

    _checkAndCalculateRoute();
  }

  @override
  void initState() {
    super.initState();
    _loadCancellationCharge();
    _loadSavedPreferences();

    _pickupHouseController.addListener(() {
      final text = _pickupHouseController.text.trim();
      if (text.isNotEmpty) {
        SharedPreferences.getInstance().then((prefs) {
          prefs.setString('saved_pickup_house', text);
        });
      }
    });
    
    _pickupFocusNode.addListener(() {
      if (_pickupFocusNode.hasFocus) {
        setState(() {
          _isPickupActive = true;
        });
      }
    });

    _dropFocusNode.addListener(() {
      if (_dropFocusNode.hasFocus) {
        setState(() {
          _isPickupActive = false;
        });
      }
    });

    _pickupController.addListener(() {
      final text = _pickupController.text;
      if (_pickupFocusNode.hasFocus && text != _pickupQuery) {
        _pickupQuery = text;
        _onQueryChanged(text, true);
      }
    });

    _dropController.addListener(() {
      final text = _dropController.text;
      if (_dropFocusNode.hasFocus && text != _dropQuery) {
        _dropQuery = text;
        _onQueryChanged(text, false);
      }
    });

    final isDelivery = widget.serviceType == 'delivery' || widget.serviceType == 'parcel' || widget.serviceType == 'heavy_truck';
    if (isDelivery) {
      _selectedOptionIndex = 0;
      _selectedPaymentMethod = widget.serviceType == 'heavy_truck' ? 'Advance Pay (Pickup Balance)' : 'Pay at Pickup';
    } else {
      if (widget.serviceType == 'bike') {
        _selectedOptionIndex = 0;
      } else if (widget.serviceType == 'auto') {
        _selectedOptionIndex = 1;
      } else if (widget.serviceType == 'car' || widget.serviceType == 'cab') {
        _selectedOptionIndex = 2;
      }
    }
    if (widget.serviceType == 'heavy_truck') {
      _initHeavyTruckDateTime();
    }
    _applyInitialLocations();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleInitialStartup();
    });
  }

  void _applyInitialLocations() {
    if (widget.initialDropAddress != null && widget.initialDropAddress!.isNotEmpty) {
      _dropController.text = widget.initialDropAddress!;
      _dropQuery = widget.initialDropAddress!;
      _dropLatLng = widget.initialDropLatLng;
    }
    if (widget.initialPickupAddress != null && widget.initialPickupAddress!.isNotEmpty) {
      _pickupController.text = widget.initialPickupAddress!;
      _pickupQuery = widget.initialPickupAddress!;
      _pickupLatLng = widget.initialPickupLatLng;
    }
  }

  Future<void> _handleInitialStartup() async {
    // 1. If drop coordinates are missing but drop address is provided, resolve them
    if (_dropLatLng == null && _dropController.text.isNotEmpty) {
      final geo = await _geocodeAddress(_dropController.text);
      if (geo != null && mounted) {
        setState(() {
          _dropLatLng = geo;
        });
      }
    }

    // 2. If pickup was provided without coordinates, resolve it
    if (_pickupController.text.isNotEmpty && _pickupLatLng == null) {
      final geo = await _geocodeAddress(_pickupController.text);
      if (geo != null && mounted) {
        setState(() {
          _pickupLatLng = geo;
        });
      }
    }

    // 3. If pickup is not provided, detect current location
    if (_pickupController.text.isEmpty) {
      await _detectCurrentLocation();
    } else if (mounted && _pickupLatLng != null && _dropLatLng != null) {
      _checkAndCalculateRoute();
    }
  }

  DateTime? _getSlotDateTime(DateTime? date, String? slot) {
    if (date == null || slot == null) return null;
    try {
      final parts = slot.trim().split(' ');
      if (parts.length < 2) return null;
      final timeParts = parts[0].split(':');
      int hour = int.parse(timeParts[0]);
      int minute = int.parse(timeParts[1]);
      final isPm = parts[1].toUpperCase() == 'PM';
      if (isPm && hour != 12) hour += 12;
      if (!isPm && hour == 12) hour = 0;
      return DateTime(date.year, date.month, date.day, hour, minute);
    } catch (e) {
      return null;
    }
  }

  bool _isSlotAtLeast5HoursAhead(DateTime? date, String? slot) {
    final slotDt = _getSlotDateTime(date, slot);
    if (slotDt == null) return false;
    final minValidTime = DateTime.now().add(const Duration(hours: 5));
    return slotDt.isAfter(minValidTime) || slotDt.isAtSameMomentAs(minValidTime);
  }

  bool _isHeavyTruckTimeSlotValid() {
    return _isSlotAtLeast5HoursAhead(_heavyTruckDate, _heavyTruckTimeSlot);
  }

  void _initHeavyTruckDateTime() {
    final dates = _getHeavyTruckDates();
    if (dates.isNotEmpty) {
      _heavyTruckDate = dates.first;
      final validSlots = _getHeavyTruckTimeSlotsForDate(_heavyTruckDate!);
      _heavyTruckTimeSlot = validSlots.isNotEmpty ? validSlots.first : null;
    }
  }

  List<String> _getHeavyTruckTimeSlotsForDate(DateTime date) {
    // 5-hour interval slots (e.g., 5:00 hours gap)
    final List<String> all5HourSlots = [
      '06:00 AM',
      '11:00 AM',
      '04:00 PM',
      '09:00 PM',
      '02:00 AM',
    ];

    final List<String> validSlots = [];
    for (final slot in all5HourSlots) {
      if (_isSlotAtLeast5HoursAhead(date, slot)) {
        validSlots.add(slot);
      }
    }
    return validSlots;
  }

  List<DateTime> _getHeavyTruckDates() {
    final now = DateTime.now();
    final List<DateTime> dates = [];
    final today = DateTime(now.year, now.month, now.day);

    for (int i = 0; i < 7; i++) {
      final date = today.add(Duration(days: i));
      if (_getHeavyTruckTimeSlotsForDate(date).isNotEmpty) {
        dates.add(date);
      }
    }
    return dates;
  }

  void _loadCancellationCharge() async {
    try {
      final uid = FirebaseService().currentUid;
      if (uid != null) {
        final doc = await FirebaseService().getProfile('customer', uid);
        if (doc.exists && doc.data() != null) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['pendingCancellationCharge'] != null) {
            setState(() {
              _cancellationCharge = (data['pendingCancellationCharge'] as num).toDouble();
            });
            debugPrint("Loaded pending cancellation charge: $_cancellationCharge");
          }
        }
      }
    } catch (e) {
      debugPrint("Error loading cancellation charge: $e");
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _pickupController.dispose();
    _dropController.dispose();
    _pickupFocusNode.dispose();
    _dropFocusNode.dispose();
    _pickupHouseController.dispose();
    _pickupNameController.dispose();
    _pickupPhoneController.dispose();
    _dropHouseController.dispose();
    _dropNameController.dispose();
    _dropPhoneController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String text, bool isPickup) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      _fetchPredictions(text, isPickup);
    });
  }

  Future<void> _fetchPredictions(String query, bool isPickup) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || trimmed.length < 2) {
      if (mounted) {
        setState(() {
          if (isPickup) {
            _pickupPredictions = [];
          } else {
            _dropPredictions = [];
          }
          _isLoadingPredictions = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingPredictions = true;
      });
    }

    final backendUrl = NetworkConfig.backendUrl;
    final userCoord = isPickup ? _pickupLatLng : _dropLatLng;
    String endpoint = '$backendUrl/api/places/autocomplete?input=${Uri.encodeComponent(trimmed)}';
    if (userCoord != null) {
      endpoint += '&lat=${userCoord.latitude}&lng=${userCoord.longitude}';
    }

    try {
      final response = await ApiClient().get(Uri.parse(endpoint), retry: false).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['predictions'] != null) {
          final List list = data['predictions'];
          final items = list.map((p) => PlacePredictionItem.fromJson(p)).toList();
          if (mounted) {
            setState(() {
              if (isPickup) {
                _pickupPredictions = items;
              } else {
                _dropPredictions = items;
              }
              _isLoadingPredictions = false;
            });
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching autocomplete from backend: $e');
    }

    // Direct Google Places Autocomplete fallback for mobile platforms (no CORS)
    if (!kIsWeb) {
      try {
        final directUrl = 'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${Uri.encodeComponent(trimmed)}&components=country:in&key=$_apiKey';
        final response = await http.get(Uri.parse(directUrl)).timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['status'] == 'OK' && data['predictions'] != null) {
            final List list = data['predictions'];
            final items = list.map((p) => PlacePredictionItem(
              description: p['description'] ?? '',
              mainText: p['structured_formatting'] != null ? p['structured_formatting']['main_text'] ?? '' : (p['description'] ?? '').split(',')[0],
              secondaryText: p['structured_formatting'] != null ? p['structured_formatting']['secondary_text'] ?? '' : '',
              placeId: p['place_id'] ?? '',
            )).toList();
            if (mounted) {
              setState(() {
                if (isPickup) {
                  _pickupPredictions = items;
                } else {
                  _dropPredictions = items;
                }
                _isLoadingPredictions = false;
              });
              return;
            }
          }
        }
      } catch (e) {
        debugPrint('Direct mobile autocomplete fallback error: $e');
      }
    }

    if (mounted) {
      setState(() {
        _isLoadingPredictions = false;
      });
    }
  }

  Future<LatLng?> _geocodeAddress(String address, {String? placeId}) async {
    final backendUrl = NetworkConfig.backendUrl;
    String endpoint = '$backendUrl/api/places/geocode?';
    if (placeId != null && placeId.isNotEmpty) {
      endpoint += 'place_id=${Uri.encodeComponent(placeId)}';
      if (address.isNotEmpty) {
        endpoint += '&address=${Uri.encodeComponent(address)}';
      }
    } else {
      endpoint += 'address=${Uri.encodeComponent(address)}';
    }

    try {
      final response = await ApiClient().get(Uri.parse(endpoint), retry: false).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['location'] != null) {
          final loc = data['location'];
          return LatLng((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble());
        }
      }
    } catch (e) {
      debugPrint('Backend geocoding error: $e');
    }

    // Direct Google API fallback on mobile
    if (!kIsWeb) {
      try {
        final directUrl = placeId != null && placeId.isNotEmpty
            ? 'https://maps.googleapis.com/maps/api/place/details/json?place_id=${Uri.encodeComponent(placeId)}&fields=geometry&key=$_apiKey'
            : 'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(address)}&components=country:in&key=$_apiKey';
        final response = await http.get(Uri.parse(directUrl)).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['status'] == 'OK') {
            final loc = placeId != null && placeId.isNotEmpty
                ? data['result']['geometry']['location']
                : data['results'][0]['geometry']['location'];
            return LatLng((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble());
          }
        }
      } catch (e) {
        debugPrint('Direct mobile geocoding fallback error: $e');
      }
    }

    // Quick history or popular location matches
    for (var item in _historyLocations) {
      if (address.toLowerCase().contains(item['title'].toString().toLowerCase())) {
        return item['latLng'] as LatLng;
      }
    }
    for (var item in _quickDestinations) {
      if (address.toLowerCase().contains(item['title'].toString().toLowerCase())) {
        return item['latLng'] as LatLng;
      }
    }

    return _center;
  }

  Future<String> _reverseGeocode(LatLng latLng) async {
    final backendUrl = NetworkConfig.backendUrl;
    final endpoint = '$backendUrl/api/places/reverse-geocode?lat=${latLng.latitude}&lng=${latLng.longitude}';

    try {
      final response = await ApiClient().get(Uri.parse(endpoint), retry: false).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final detailedAddr = data['detailed_address'] as String?;
          final fullAddr = data['formatted_address'] as String?;
          final shortAddr = data['short_address'] as String?;
          if (detailedAddr != null && detailedAddr.isNotEmpty && !detailedAddr.startsWith('Location (')) {
            return detailedAddr;
          }
          if (fullAddr != null && fullAddr.isNotEmpty && !fullAddr.startsWith('Location (')) {
            return fullAddr;
          }
          if (shortAddr != null && shortAddr.isNotEmpty && !shortAddr.startsWith('Location (')) {
            return shortAddr;
          }
        }
      }
    } catch (e) {
      debugPrint('Backend reverse-geocode error: $e');
    }

    // Direct Google API fallback on mobile
    if (!kIsWeb) {
      try {
        final directUrl = 'https://maps.googleapis.com/maps/api/geocode/json?latlng=${latLng.latitude},${latLng.longitude}&key=$_apiKey';
        final response = await http.get(Uri.parse(directUrl)).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['status'] == 'OK' && data['results'] != null && data['results'].isNotEmpty) {
            String best = data['results'][0]['formatted_address'] as String;
            best = best.replaceFirst(RegExp(r'^[A-Z0-9]{4,8}\+[A-Z0-9]{2,4},?\s*', caseSensitive: false), '').trim();
            best = best.replaceFirst(RegExp(r',\s*India$', caseSensitive: false), '').trim();
            return best;
          }
        }
      } catch (e) {
        debugPrint('Direct mobile reverse-geocode error: $e');
      }
    }

    return 'Current Location (${latLng.latitude.toStringAsFixed(3)}, ${latLng.longitude.toStringAsFixed(3)})';
  }

  Future<void> _detectCurrentLocation() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Detecting current location...'),
        duration: Duration(seconds: 1),
      ),
    );

    LatLng latLng = const LatLng(17.4834, 78.3871); // Default center (Hyderabad)
    String address = 'Kukatpally, Hyderabad';
    bool gotRealLocation = false;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (serviceEnabled && (permission == LocationPermission.always || permission == LocationPermission.whileInUse)) {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 6),
        );
        latLng = LatLng(position.latitude, position.longitude);
        gotRealLocation = true;
        address = await _reverseGeocode(latLng);
      } else {
        debugPrint('Location service disabled or permission denied');
      }
    } catch (e) {
      debugPrint('Error getting device location: $e');
    }

    if (!gotRealLocation) {
      address = await _reverseGeocode(latLng);
    }

    if (mounted) {
      final house = _pickupHouseController.text.trim();
      String fullPickup = address;
      if (address.toLowerCase().contains('gajularamaram') && !address.toLowerCase().contains('balaji layout')) {
        fullPickup = 'Sri Balaji Layout, $address';
      }
      if (house.isNotEmpty && !fullPickup.toLowerCase().contains(house.toLowerCase())) {
        fullPickup = '$house, $fullPickup';
      }

      setState(() {
        _pickupController.text = fullPickup;
        _pickupQuery = fullPickup;
        _pickupLatLng = latLng;
        _pickupPredictions = [];

        // If drop destination is empty, automatically advance to drop
        if (_dropController.text.isEmpty) {
          _isPickupActive = false;
        }
      });

      if (_dropController.text.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _dropFocusNode.requestFocus();
          }
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(gotRealLocation 
              ? 'Pickup location detected: $address' 
              : 'Using default pickup ($address)'),
          backgroundColor: gotRealLocation ? Colors.green.shade700 : Colors.orange.shade800,
          duration: const Duration(seconds: 2),
        ),
      );

      _checkAndCalculateRoute();
    }
  }

  void _swapLocations() {
    setState(() {
      final tempText = _pickupController.text;
      final tempLatLng = _pickupLatLng;
      final tempQuery = _pickupQuery;

      _pickupController.text = _dropController.text;
      _pickupLatLng = _dropLatLng;
      _pickupQuery = _dropQuery;

      _dropController.text = tempText;
      _dropLatLng = tempLatLng;
      _dropQuery = tempQuery;

      _pickupPredictions = [];
      _dropPredictions = [];

      if (_dropController.text.isEmpty) {
        _isPickupActive = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _dropFocusNode.requestFocus();
        });
      } else if (_pickupController.text.isEmpty) {
        _isPickupActive = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _pickupFocusNode.requestFocus();
        });
      }
    });

    _checkAndCalculateRoute();
  }

  void _selectHistoryItem(String title, String subtitle, LatLng coordinates) {
    final bool targetPickup = _isPickupActive && _pickupController.text.isEmpty;

    setState(() {
      if (targetPickup) {
        _pickupController.text = title;
        _pickupQuery = title;
        _pickupLatLng = coordinates;
        _pickupPredictions = [];
        if (_dropController.text.isEmpty) {
          _isPickupActive = false;
        }
      } else {
        _dropController.text = title;
        _dropQuery = title;
        _dropLatLng = coordinates;
        _dropPredictions = [];
      }
    });

    if (targetPickup && _dropController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _dropFocusNode.requestFocus();
      });
    }

    _checkAndCalculateRoute();
  }

  void _selectQuickDestination(Map<String, dynamic> item) {
    final title = item['title'] as String;
    final subtitle = item['subtitle'] as String;
    final coord = item['latLng'] as LatLng;
    final full = '$title, $subtitle';

    final bool targetPickup = _isPickupActive && _pickupController.text.isEmpty;

    setState(() {
      if (targetPickup) {
        _pickupController.text = full;
        _pickupQuery = full;
        _pickupLatLng = coord;
        _pickupPredictions = [];
        if (_dropController.text.isEmpty) {
          _isPickupActive = false;
        }
      } else {
        _dropController.text = full;
        _dropQuery = full;
        _dropLatLng = coord;
        _dropPredictions = [];
      }
    });

    if (targetPickup && _dropController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _dropFocusNode.requestFocus();
      });
    }

    _checkAndCalculateRoute();
  }

  Future<void> _submitAddress(String address, bool isPickup) async {
    if (address.isEmpty) return;
    
    setState(() {
      if (isPickup) {
        _pickupController.text = address;
        _pickupPredictions = [];
      } else {
        _dropController.text = address;
        _dropPredictions = [];
      }
    });

    final coordinates = await _geocodeAddress(address);
    if (coordinates != null) {
      setState(() {
        if (isPickup) {
          _pickupLatLng = coordinates;
          if (_isParcel && widget.serviceType != 'heavy_truck') {
            _parcelStep = 1;
          }
        } else {
          _dropLatLng = coordinates;
          if (_isParcel) {
            _parcelStep = 3;
          }
        }
        
        // Add to search history dynamically
        final hasAddress = _historyLocations.any((item) =>
            item['address'].toString().toLowerCase() == address.toLowerCase() ||
            item['title'].toString().toLowerCase() == address.toLowerCase());
        if (!hasAddress) {
          String title = address;
          String displayAddress = address;
          int firstComma = address.indexOf(',');
          if (firstComma != -1) {
            title = address.substring(0, firstComma).trim();
            displayAddress = address.substring(firstComma + 1).trim();
          }
          if (title.isNotEmpty) {
            _historyLocations.insert(0, {
              'title': title,
              'address': displayAddress,
              'latLng': coordinates,
            });
          }
        }
      });
      if (isPickup && widget.serviceType == 'heavy_truck' && _mapController != null) {
        _mapController!.animateCamera(CameraUpdate.newLatLng(coordinates));
      }
      _checkAndCalculateRoute();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not find location: $address')),
        );
      }
    }
  }

  Future<void> _selectPredictionItem(PlacePredictionItem item) async {
    final isPickup = _isPickupActive;
    final displayTitle = item.mainText.isNotEmpty ? item.mainText : item.description;
    final fullText = item.description.isNotEmpty ? item.description : displayTitle;

    setState(() {
      if (isPickup) {
        _pickupController.text = fullText;
        _pickupQuery = fullText;
        _pickupPredictions = [];
      } else {
        _dropController.text = fullText;
        _dropQuery = fullText;
        _dropPredictions = [];
      }
    });

    LatLng? coord;
    if (item.lat != null && item.lng != null) {
      coord = LatLng(item.lat!, item.lng!);
    } else {
      coord = await _geocodeAddress(fullText, placeId: item.placeId);
    }

    if (coord != null) {
      setState(() {
        if (isPickup) {
          _pickupLatLng = coord;
          if (_isParcel && widget.serviceType != 'heavy_truck') {
            _parcelStep = 1;
          }
          if (_dropController.text.isEmpty) {
            _isPickupActive = false;
          }
        } else {
          _dropLatLng = coord;
          if (_isParcel) {
            _parcelStep = 3;
          }
        }

        final hasAddress = _historyLocations.any((h) =>
            h['title'].toString().toLowerCase() == displayTitle.toLowerCase());
        if (!hasAddress) {
          _historyLocations.insert(0, {
            'title': displayTitle,
            'address': item.secondaryText.isNotEmpty ? item.secondaryText : fullText,
            'latLng': coord,
          });
        }
      });

      if (isPickup && _dropController.text.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _dropFocusNode.requestFocus();
        });
      }

      _checkAndCalculateRoute();
    }
  }
  void _checkAndCalculateRoute() {
    if (_pickupLatLng != null && _dropLatLng != null) {
      _calculateRouteFromLatLng(_pickupLatLng!, _dropLatLng!);
    }
  }

  Future<void> _calculateRouteFromLatLng(LatLng origin, LatLng destination) async {
    final String backendBaseUrl = NetworkConfig.backendUrl;
    final Uri url = Uri.parse('$backendBaseUrl/api/directions?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}');
        
    try {
      final response = await ApiClient().get(url, timeout: const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final route = data['routes'][0];
          final leg = route['legs'][0];
          
          final String polylineStr = route['overview_polyline']['points'];
          List<LatLng> polylineCoordinates = _decodePolyline(polylineStr);
          
          final Polyline polyline = Polyline(
            polylineId: const PolylineId('route'),
            color: AppTheme.primaryColor,
            points: polylineCoordinates,
            width: 5,
          );
          
          final startMarker = Marker(
            markerId: const MarkerId('start'),
            position: origin,
            infoWindow: InfoWindow(title: 'Pickup', snippet: _pickupController.text),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          );
          
          final endMarker = Marker(
            markerId: const MarkerId('end'),
            position: destination,
            infoWindow: InfoWindow(title: 'Destination', snippet: _dropController.text),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          );

          setState(() {
            _distance = leg['distance']['text'];
            _duration = leg['duration']['text'];
            _polylines = {polyline};
            _markers = {startMarker, endMarker};
            _routePoints = polylineCoordinates;
            _currentStep = 2; // Route screen
          });

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_mapController != null) {
              final bounds = LatLngBounds(
                southwest: LatLng(
                  origin.latitude < destination.latitude ? origin.latitude : destination.latitude,
                  origin.longitude < destination.longitude ? origin.longitude : destination.longitude,
                ),
                northeast: LatLng(
                  origin.latitude > destination.latitude ? origin.latitude : destination.latitude,
                  origin.longitude > destination.longitude ? origin.longitude : destination.longitude,
                ),
              );
              _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60.0));
            }
          });
        } else {
          _setupFallbackRoute(origin, destination);
        }
      } else {
        _setupFallbackRoute(origin, destination);
      }
    } catch (e) {
      debugPrint('Error fetching directions: $e');
      _setupFallbackRoute(origin, destination);
    }
  }

  void _setupFallbackRoute(LatLng origin, LatLng destination) {
    final Polyline polyline = Polyline(
      polylineId: const PolylineId('route'),
      color: AppTheme.primaryColor,
      points: [origin, destination],
      width: 5,
    );
    
    final startMarker = Marker(
      markerId: const MarkerId('start'),
      position: origin,
      infoWindow: InfoWindow(title: 'Pickup', snippet: _pickupController.text),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
    );
    
    final endMarker = Marker(
      markerId: const MarkerId('end'),
      position: destination,
      infoWindow: InfoWindow(title: 'Destination', snippet: _dropController.text),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
    );

    final double roadDistKm = (Geolocator.distanceBetween(
      origin.latitude, origin.longitude,
      destination.latitude, destination.longitude,
    ) * 1.30) / 1000;
    final int estMins = (roadDistKm / 0.5).round().clamp(3, 120);

    setState(() {
      _distance = '${roadDistKm.toStringAsFixed(1)} km';
      _duration = '$estMins mins';
      _polylines = {polyline};
      _markers = {startMarker, endMarker};
      _routePoints = [origin, destination];
      _currentStep = 2;
    });


    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_mapController != null) {
        final bounds = LatLngBounds(
          southwest: LatLng(
            origin.latitude < destination.latitude ? origin.latitude : destination.latitude,
            origin.longitude < destination.longitude ? origin.longitude : destination.longitude,
          ),
          northeast: LatLng(
            origin.latitude > destination.latitude ? origin.latitude : destination.latitude,
            origin.longitude > destination.longitude ? origin.longitude : destination.longitude,
          ),
        );
        _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60.0));
      }
    });
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> poly = [];
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

      poly.add(LatLng((lat / 1E5).toDouble(), (lng / 1E5).toDouble()));
    }
    return poly;
  }

  double _parseDistance(String distanceStr) {
    final cleanStr = distanceStr.replaceAll(RegExp(r'[^0-9.]'), '');
    double val = double.tryParse(cleanStr) ?? 0.0;
    if (distanceStr.toLowerCase().contains('m') && !distanceStr.toLowerCase().contains('k')) {
      val = val / 1000.0;
    }
    return val;
  }

  String _calculateFareText(double basic, double perKm, {double? upTo275Fare}) {
    if (_distance == null) {
      final total = basic + _cancellationCharge;
      return '₹${total.toStringAsFixed(0)}';
    }
    double km = _parseDistance(_distance!);
    double fare;
    if (widget.serviceType == 'heavy_truck') {
      final double flat275 = upTo275Fare ?? (basic * 2.5);
      if (km <= 100.0) {
        fare = basic;
      } else if (km <= 275.0) {
        fare = flat275;
      } else {
        fare = flat275 + (km - 275.0) * perKm;
      }
    } else {
      if (km <= 2.0) {
        fare = basic;
      } else {
        fare = basic + (km - 2.0) * perKm;
      }
    }
    final total = fare + _cancellationCharge;
    return '₹${total.toStringAsFixed(0)}';
  }

  void _openMapSelection() {
    setState(() {
      _selectingPickupOnMap = _isPickupActive;
      final currentCoord = _selectingPickupOnMap ? _pickupLatLng : _dropLatLng;
      _mapSelectionCenter = currentCoord ?? _center;
      _currentStep = 1; // Map select
    });
  }  Future<void> _confirmMapSelection() async {
    final selectedCoord = _mapSelectionCenter;
    final isPickup = _selectingPickupOnMap;
    
    // Set a placeholder address first
    final String placeholder = 'Selected from Map (${selectedCoord.latitude.toStringAsFixed(4)}, ${selectedCoord.longitude.toStringAsFixed(4)})';
    
    setState(() {
      if (isPickup) {
        _pickupController.text = placeholder;
        _pickupQuery = placeholder;
        _pickupLatLng = selectedCoord;
        _pickupPredictions = [];
        if (_isParcel) {
          _parcelStep = 1;
        }
        if (_dropController.text.isEmpty) {
          _isPickupActive = false;
        }
      } else {
        _dropController.text = placeholder;
        _dropQuery = placeholder;
        _dropLatLng = selectedCoord;
        _dropPredictions = [];
        if (_isParcel) {
          _parcelStep = 3;
        }
      }
      _currentStep = 0; // Return to selection screen
    });

    if (isPickup && _dropController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _dropFocusNode.requestFocus();
      });
    }

    _checkAndCalculateRoute();

    // Fetch actual address in the background
    final realAddress = await _reverseGeocode(selectedCoord);
    if (mounted) {
      setState(() {
        if (isPickup) {
          if (_pickupController.text == placeholder) {
            _pickupController.text = realAddress;
            _pickupQuery = realAddress;
          }
        } else {
          if (_dropController.text == placeholder) {
            _dropController.text = realAddress;
            _dropQuery = realAddress;
          }
        }

        // Add map selected location to history once geocoded/resolved
        final hasAddress = _historyLocations.any((item) =>
            item['address'].toString().toLowerCase() == realAddress.toLowerCase() ||
            item['title'].toString().toLowerCase() == realAddress.toLowerCase());
        if (!hasAddress && realAddress.isNotEmpty) {
          String title = realAddress;
          String displayAddress = realAddress;
          int firstComma = realAddress.indexOf(',');
          if (firstComma != -1) {
            title = realAddress.substring(0, firstComma).trim();
            displayAddress = realAddress.substring(firstComma + 1).trim();
          }
          if (title.isNotEmpty) {
            _historyLocations.insert(0, {
              'title': title,
              'address': displayAddress,
              'latLng': selectedCoord,
            });
          }
        }
      });
    }
  }
  void _selectPaymentMethod() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select Payment Method',
                    style: GoogleFonts.hankenGrotesk(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
                  ),
                  const SizedBox(height: 16),
                  if (widget.serviceType == 'heavy_truck') ...[
                    ListTile(
                      leading: const Icon(Icons.payment_rounded, color: Colors.green),
                      title: Text('Advance Pay (Pickup Balance)', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
                      subtitle: Text('Pay ₹0 advance online now, and the remaining balance at the pickup location.', style: GoogleFonts.inter(fontSize: 12)),
                      trailing: _selectedPaymentMethod == 'Advance Pay (Pickup Balance)' 
                          ? const Icon(Icons.check_circle, color: AppTheme.primaryColor) 
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedPaymentMethod = 'Advance Pay (Pickup Balance)';
                        });
                        setModalState(() {});
                        Navigator.pop(context);
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.payment_rounded, color: Colors.blue),
                      title: Text('Advance Pay (Drop Balance)', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
                      subtitle: Text('Pay ₹0 advance online now, and the remaining balance at the drop destination.', style: GoogleFonts.inter(fontSize: 12)),
                      trailing: _selectedPaymentMethod == 'Advance Pay (Drop Balance)' 
                          ? const Icon(Icons.check_circle, color: AppTheme.primaryColor) 
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedPaymentMethod = 'Advance Pay (Drop Balance)';
                        });
                        setModalState(() {});
                        Navigator.pop(context);
                      },
                    ),
                  ] else if (_isParcel) ...[
                    ListTile(
                      leading: const Icon(Icons.arrow_upward_rounded, color: Colors.green),
                      title: Text('Pay at Pickup', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
                      subtitle: Text('Pay at the pickup location upon package collection', style: GoogleFonts.inter(fontSize: 12)),
                      trailing: _selectedPaymentMethod == 'Pay at Pickup' 
                          ? const Icon(Icons.check_circle, color: AppTheme.primaryColor) 
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedPaymentMethod = 'Pay at Pickup';
                        });
                        setModalState(() {});
                        Navigator.pop(context);
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.arrow_downward_rounded, color: Colors.blue),
                      title: Text('Pay at Drop', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
                      subtitle: Text('Pay at the destination location upon package delivery', style: GoogleFonts.inter(fontSize: 12)),
                      trailing: _selectedPaymentMethod == 'Pay at Drop' 
                          ? const Icon(Icons.check_circle, color: AppTheme.primaryColor) 
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedPaymentMethod = 'Pay at Drop';
                        });
                        setModalState(() {});
                        Navigator.pop(context);
                      },
                    ),
                  ] else ...[
                    ListTile(
                      leading: const Icon(Icons.money_rounded, color: Colors.green),
                      title: Text('Pay After Ride', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
                      subtitle: Text('Pay with Cash or UPI directly to driver after the ride', style: GoogleFonts.inter(fontSize: 12)),
                      trailing: _selectedPaymentMethod == 'Pay After Ride' 
                          ? const Icon(Icons.check_circle, color: AppTheme.primaryColor) 
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedPaymentMethod = 'Pay After Ride';
                        });
                        setModalState(() {});
                        Navigator.pop(context);
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.payment_rounded, color: Colors.indigo),
                      title: Text('Pay Online Now (Razorpay)', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
                      subtitle: Text('Pay upfront using Razorpay secure checkout', style: GoogleFonts.inter(fontSize: 12)),
                      trailing: _selectedPaymentMethod == 'Razorpay Now' 
                          ? const Icon(Icons.check_circle, color: AppTheme.primaryColor) 
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedPaymentMethod = 'Razorpay Now';
                        });
                        setModalState(() {});
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ],
              ),
            );
          }
        );
      },
    );
  }

  void _confirmBooking(String selectedVehicle, String selectedPrice) {
    if (NetworkMonitor().currentStatus == NetworkStatus.disconnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot book a ride while offline. Please check your internet connection.'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    final cleanStr = selectedPrice.replaceAll(RegExp(r'[^0-9.]'), '');
    final priceVal = double.tryParse(cleanStr) ?? 150.0;

    void proceedToBooking() {
      if (widget.serviceType == 'heavy_truck' && !_isHeavyTruckTimeSlotValid()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a time slot at least 5 hours from the current time.'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
        return;
      }
      final houseDetails = _pickupHouseController.text.trim();
      String effectivePickup = _pickupController.text.trim();
      if (houseDetails.isNotEmpty && !effectivePickup.toLowerCase().contains(houseDetails.toLowerCase())) {
        effectivePickup = '$houseDetails, $effectivePickup';
      }

      BookingManager().createBooking(
        pickupName: effectivePickup,
        dropName: _dropController.text,
        pickupLatLng: _pickupLatLng ?? const LatLng(17.4834, 78.3871),
        dropLatLng: _dropLatLng ?? const LatLng(17.4854, 78.3891),
        vehicleType: selectedVehicle,
        price: selectedPrice,
        serviceType: widget.serviceType,
        pickupHouse: houseDetails.isNotEmpty ? houseDetails : null,
        pickupContactName: _pickupNameController.text,
        pickupContactPhone: _pickupPhoneController.text,
        dropHouse: _dropHouseController.text,
        dropContactName: _dropNameController.text,
        dropContactPhone: _dropPhoneController.text,
        paymentOption: _selectedPaymentMethod,
        scheduledDate: widget.serviceType == 'heavy_truck' && _heavyTruckDate != null
            ? '${_heavyTruckDate!.year}-${_heavyTruckDate!.month.toString().padLeft(2, '0')}-${_heavyTruckDate!.day.toString().padLeft(2, '0')}'
            : null,
        scheduledTimeSlot: widget.serviceType == 'heavy_truck' ? _heavyTruckTimeSlot : null,
        distance: _distance,
      );

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LiveTrackingScreen(
            vehicleType: selectedVehicle,
            price: selectedPrice,
            routePoints: _routePoints.isNotEmpty ? _routePoints : null,
          ),
        ),
      );
    }

    if (widget.serviceType == 'heavy_truck') {
      final double advanceAmount = 0.0;
      if (advanceAmount == 0.0) {
        proceedToBooking();
      } else {
        RazorpayGateway.show(
          context,
          amount: advanceAmount,
          description: 'StayDriv Heavy Truck Advance - $selectedVehicle',
          onSuccess: proceedToBooking,
        );
      }
    } else if (_selectedPaymentMethod == 'Razorpay Now') {
      RazorpayGateway.show(
        context,
        amount: priceVal,
        description: 'StayDriv Ride Booking - $selectedVehicle',
        onSuccess: proceedToBooking,
      );
    } else {
      // Pay After Ride (Cash or UPI to driver)
      proceedToBooking();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentStep == 1) {
      return _buildMapSelectionStep();
    }
    if (_isParcel) {
      return _buildParcelFlow();
    }
    if (_currentStep == 0) {
      return _buildLocationSelectionStep();
    } else {
      return _buildRouteAndBookingStep();
    }
  }
  // STEP 0: Location Entry & History List (No Map)
  Widget _buildLocationSelectionStep() {
    final activePredictions = _isPickupActive ? _pickupPredictions : _dropPredictions;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isPickupActive ? 'Select Pickup Location' : 'Select Drop Destination',
              style: GoogleFonts.hankenGrotesk(
                fontWeight: FontWeight.w700,
                color: Colors.black87,
                fontSize: 18,
              ),
            ),
            Text(
              _isPickupActive ? 'Where should the driver pick you up?' : 'Where would you like to go?',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w500,
                color: _isPickupActive ? Colors.green.shade700 : Colors.orange.shade800,
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0, top: 10.0, bottom: 10.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Text(
                    'For me',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down, color: Colors.black87, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Prominent FROM and TO Route Card
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  // Row 1: FROM (Pickup Location)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _isPickupActive ? const Color(0xFFF0FDF4) : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _isPickupActive ? Colors.green.shade600 : Colors.grey.shade300,
                        width: _isPickupActive ? 1.8 : 1.0,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Green FROM pill
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: _isPickupActive ? Colors.green.shade700 : Colors.grey.shade600,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'FROM',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'PICKUP LOCATION',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: _isPickupActive ? Colors.green.shade800 : Colors.grey.shade600,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  TextField(
                                    controller: _pickupController,
                                    focusNode: _pickupFocusNode,
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                    textInputAction: TextInputAction.next,
                                    onSubmitted: (val) {
                                      _submitAddress(val, true);
                                      if (_dropController.text.isEmpty) {
                                        setState(() => _isPickupActive = false);
                                        _dropFocusNode.requestFocus();
                                      }
                                    },
                                    onTap: () {
                                      setState(() {
                                        _isPickupActive = true;
                                      });
                                    },
                                    decoration: InputDecoration(
                                      hintText: 'Enter pickup spot or use current location',
                                      hintStyle: GoogleFonts.inter(
                                        color: Colors.grey.shade400,
                                        fontSize: 14,
                                        fontWeight: FontWeight.normal,
                                      ),
                                      border: InputBorder.none,
                                      isDense: false,
                                      contentPadding: const EdgeInsets.symmetric(vertical: 6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_pickupController.text.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.cancel, size: 20, color: Colors.grey),
                                splashRadius: 20,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  setState(() {
                                    _pickupController.clear();
                                    _pickupQuery = '';
                                    _pickupLatLng = null;
                                    _pickupPredictions = [];
                                  });
                                },
                              )
                            else
                              IconButton(
                                icon: Icon(Icons.my_location, size: 20, color: Colors.green.shade700),
                                splashRadius: 20,
                                tooltip: 'Detect current location',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: _detectCurrentLocation,
                              ),
                          ],
                        ),
                        // Dedicated House / Flat / Residency input with spacious comfortable typing space
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _isPickupActive ? Colors.green.shade400 : Colors.grey.shade300,
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.home_work_outlined, size: 18, color: _isPickupActive ? Colors.green.shade700 : Colors.grey.shade600),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _pickupHouseController,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'House / Flat / Residency (e.g. House No -84, Rishipranavam)',
                                    hintStyle: GoogleFonts.inter(
                                      color: Colors.grey.shade400,
                                      fontSize: 13,
                                      fontWeight: FontWeight.normal,
                                    ),
                                    border: InputBorder.none,
                                    isDense: false,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                                  ),
                                ),
                              ),
                              if (_pickupHouseController.text.isNotEmpty)
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      _pickupHouseController.clear();
                                    });
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.all(4.0),
                                    child: Icon(Icons.clear, size: 16, color: Colors.grey),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Middle Connector with Swap Button
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 10.0),
                    child: Row(
                      children: [
                        const SizedBox(width: 16),
                        Column(
                          children: [
                            Container(width: 2, height: 3, color: Colors.grey.shade400),
                            const SizedBox(height: 2),
                            Container(width: 2, height: 3, color: Colors.grey.shade400),
                          ],
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: _swapLocations,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade300),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.swap_vert_rounded, size: 16, color: AppTheme.primaryColor),
                                const SizedBox(width: 4),
                                Text(
                                  'Swap (⇅)',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),

                  // Row 2: TO (Drop Destination) with spacious comfortable typing space
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: !_isPickupActive ? const Color(0xFFFFF7ED) : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: !_isPickupActive ? Colors.orange.shade700 : Colors.grey.shade300,
                        width: !_isPickupActive ? 1.8 : 1.0,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Orange TO pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: !_isPickupActive ? Colors.orange.shade800 : Colors.grey.shade600,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'TO',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'DROP DESTINATION',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: !_isPickupActive ? Colors.orange.shade800 : Colors.grey.shade600,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              const SizedBox(height: 4),
                              TextField(
                                controller: _dropController,
                                focusNode: _dropFocusNode,
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                                textInputAction: TextInputAction.search,
                                onSubmitted: (val) => _submitAddress(val, false),
                                onTap: () {
                                  setState(() {
                                    _isPickupActive = false;
                                  });
                                },
                                decoration: InputDecoration(
                                  hintText: 'Where are you going? (e.g. Secunderabad)',
                                  hintStyle: GoogleFonts.inter(
                                    color: Colors.grey.shade400,
                                    fontSize: 14,
                                    fontWeight: FontWeight.normal,
                                  ),
                                  border: InputBorder.none,
                                  isDense: false,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_dropController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.cancel, size: 20, color: Colors.grey),
                            splashRadius: 20,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              setState(() {
                                _dropController.clear();
                                _dropQuery = '';
                                _dropLatLng = null;
                                _dropPredictions = [];
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Horizontal Buttons: Select on map & Add stops
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _openMapSelection,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        backgroundColor: Colors.white,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.location_on_outlined, color: Colors.black87, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Select on map',
                            style: GoogleFonts.hankenGrotesk(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Multi-stop trips are simulated.')),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        backgroundColor: Colors.white,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              Transform.rotate(
                                angle: 0.785398, // 45 degrees
                                child: Container(
                                  width: 13,
                                  height: 13,
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              const Icon(Icons.add, color: Colors.white, size: 9),
                            ],
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Add stops',
                            style: GoogleFonts.hankenGrotesk(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),

            // Saved Places Quick Bar (Home & Work 1-Tap)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ActionChip(
                      elevation: 0,
                      backgroundColor: const Color(0xFFF0FDF4),
                      side: BorderSide(color: Colors.green.shade300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      avatar: Icon(Icons.home_rounded, size: 15, color: Colors.green.shade700),
                      label: Text(
                        '🏠 Home: House No -84, Rishipranavam...',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.green.shade800,
                        ),
                      ),
                      onPressed: _selectHomeAddress,
                    ),
                    const SizedBox(width: 8),
                    ActionChip(
                      elevation: 0,
                      backgroundColor: const Color(0xFFEFF6FF),
                      side: BorderSide(color: Colors.blue.shade200),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      avatar: Icon(Icons.work_rounded, size: 14, color: Colors.blue.shade700),
                      label: Text(
                        '💼 Work: Hitech City',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade800,
                        ),
                      ),
                      onPressed: _selectWorkAddress,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 2),

            // Quick Popular Destinations Strip (Instant 1-tap booking for customers)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Row(
                children: [
                  const Icon(Icons.flash_on_rounded, size: 16, color: Colors.amber),
                  const SizedBox(width: 4),
                  Text(
                    'Quick Destinations (1-Tap)',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Popular in Hyderabad',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 38,
              margin: const EdgeInsets.only(bottom: 6),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: _quickDestinations.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final dest = _quickDestinations[index];
                  return ActionChip(
                    elevation: 0,
                    backgroundColor: Colors.white,
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    avatar: Icon(dest['icon'] as IconData, size: 14, color: AppTheme.primaryColor),
                    label: Text(
                      dest['title'] as String,
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    onPressed: () => _selectQuickDestination(dest),
                  );
                },
              ),
            ),

            if (_isLoadingPredictions)
              const LinearProgressIndicator(minHeight: 2, color: AppTheme.primaryColor, backgroundColor: Colors.transparent),

            const Divider(height: 1),
            Expanded(
              child: activePredictions.isNotEmpty
                  ? ListView.separated(
                      itemCount: activePredictions.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
                      itemBuilder: (context, index) {
                        final pred = activePredictions[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.location_on, color: AppTheme.primaryColor, size: 20),
                          ),
                          title: Text(
                            pred.mainText,
                            style: GoogleFonts.hankenGrotesk(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87),
                          ),
                          subtitle: pred.secondaryText.isNotEmpty
                              ? Text(
                                  pred.secondaryText,
                                  style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : null,
                          trailing: const Icon(Icons.north_west_rounded, size: 16, color: Colors.grey),
                          onTap: () => _selectPredictionItem(pred),
                        );
                      },
                    )
                  : ListView(
                      children: [
                        // 1-Tap Saved Home option (House No -84, Rishipranavam residancy, balaji layout, Gajularamaram)
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.green.shade300),
                            ),
                            child: Icon(Icons.home_rounded, color: Colors.green.shade700, size: 20),
                          ),
                          title: Row(
                            children: [
                              Text(
                                'Home (Saved Pickup)',
                                style: GoogleFonts.hankenGrotesk(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Colors.green.shade900,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '1-TAP',
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.green.shade800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            'House No -84, Rishipranavam residancy, balaji layout, Gajularamaram, Hyderabad',
                            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.north_west_rounded, size: 16, color: Colors.green),
                          onTap: _selectHomeAddress,
                        ),
                        const Divider(height: 1),

                        // Current Location option
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.my_location, color: Colors.green.shade700, size: 20),
                          ),
                          title: Text(
                            'Your Current GPS Location',
                            style: GoogleFonts.hankenGrotesk(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.green.shade800,
                            ),
                          ),
                          subtitle: Text(
                            _pickupController.text.isNotEmpty
                                ? 'Currently: ${_pickupController.text}'
                                : 'Tap to detect your exact GPS spot',
                            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: _detectCurrentLocation,
                        ),
                        if (_historyLocations.isNotEmpty) const Divider(height: 1),
                        // History list
                        ..._historyLocations.map((item) {
                          return Container(
                            decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                            ),
                            child: ListTile(
                              leading: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.history, color: Colors.grey.shade700, size: 20),
                              ),
                              title: Text(
                                item['title'] as String,
                                style: GoogleFonts.hankenGrotesk(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  color: Colors.black87,
                                ),
                              ),
                              subtitle: Text(
                                item['address'] as String,
                                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Icon(Icons.north_west_rounded, color: Colors.grey.shade400, size: 16),
                              onTap: () => _selectHistoryItem(
                                item['title'] as String,
                                item['address'] as String,
                                item['latLng'] as LatLng,
                              ),
                            ),
                          );
                        }),
                        if (_historyLocations.isEmpty && !_isPickupActive) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                            child: Text(
                              'Suggested Destinations in Hyderabad',
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                          ..._quickDestinations.map((dest) {
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                              leading: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withOpacity(0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(dest['icon'] as IconData, color: AppTheme.primaryColor, size: 18),
                              ),
                              title: Text(
                                dest['title'] as String,
                                style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87),
                              ),
                              subtitle: Text(
                                dest['subtitle'] as String,
                                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
                              ),
                              trailing: const Icon(Icons.north_west_rounded, size: 16, color: Colors.grey),
                              onTap: () => _selectQuickDestination(dest),
                            );
                          }),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
  // STEP 1: Select Location on Map (Pin in Center)
  Widget _buildMapSelectionStep() {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _mapSelectionCenter,
              zoom: 15.0,
            ),
            onMapCreated: (controller) => _mapController = controller,
            onCameraMove: (CameraPosition pos) {
              _mapSelectionCenter = pos.target;
            },
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
          ),
          // Center static pin icon
          Align(
            alignment: Alignment.center,
            child: Container(
              margin: const EdgeInsets.only(bottom: 35),
              child: Icon(
                Icons.location_on,
                size: 44,
                color: _selectingPickupOnMap ? Colors.green : Colors.red,
              ),
            ),
          ),
          // Top overlay guide banner
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Card(
                color: Colors.white.withOpacity(0.95),
                margin: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info, color: _selectingPickupOnMap ? Colors.green : Colors.red),
                      const SizedBox(width: 8),
                      Text(
                        _selectingPickupOnMap 
                            ? 'Move map to select pickup location' 
                            : 'Move map to select drop location',
                        style: GoogleFonts.hankenGrotesk(
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Back button
          Positioned(
            top: 50,
            left: 20,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: Colors.white,
              onPressed: () {
                setState(() {
                  _currentStep = 0;
                });
              },
              child: const Icon(Icons.arrow_back, color: Colors.black),
            ),
          ),
          // Bottom confirm location button
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: ElevatedButton(
              onPressed: _confirmMapSelection,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: Text(
                'Confirm Location',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // STEP 2: Map Route & Booking Options Panel
  Widget _buildRouteAndBookingStep() {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 600;
    final isDelivery = widget.serviceType == 'delivery' || widget.serviceType == 'parcel' || widget.serviceType == 'heavy_truck';
    
    // Fares/options selection bike, auto, car
    final List<Map<String, dynamic>> options = widget.serviceType == 'heavy_truck'
      ? [
          {
            'icon': Icons.local_shipping_rounded,
            'image': 'assets/images/heavy_truck.png',
            'title': '6 Ton Truck',
            'desc': '6 Tyre - Up to 6 Ton',
            'time': '10 min away',
            'basicFare': 4800.0,
            'perKmFare': 48.0,
            'upTo275Fare': 14500.0,
          },
          {
            'icon': Icons.local_shipping_rounded,
            'image': 'assets/images/heavy_truck.png',
            'title': '8 Ton Truck',
            'desc': '6 Tyre - Up to 8 Ton',
            'time': '12 min away',
            'basicFare': 5500.0,
            'perKmFare': 55.0,
            'upTo275Fare': 16500.0,
          },
          {
            'icon': Icons.local_shipping_rounded,
            'image': 'assets/images/heavy_truck.png',
            'title': '10 Ton Truck',
            'desc': '6 Tyre - Up to 10 Ton',
            'time': '12 min away',
            'basicFare': 5800.0,
            'perKmFare': 58.0,
            'upTo275Fare': 17500.0,
          },
          {
            'icon': Icons.local_shipping_rounded,
            'image': 'assets/images/heavy_truck.png',
            'title': '12 Ton Truck',
            'desc': '6 Tyre - Up to 12 Ton',
            'time': '15 min away',
            'basicFare': 6000.0,
            'perKmFare': 60.0,
            'upTo275Fare': 18000.0,
          },
          {
            'icon': Icons.local_shipping_rounded,
            'image': 'assets/images/heavy_truck.png',
            'title': '25 Ton Truck',
            'desc': '12 Tyre - Up to 25 Ton',
            'time': '18 min away',
            'basicFare': 6500.0,
            'perKmFare': 65.0,
            'upTo275Fare': 19500.0,
          },
          {
            'icon': Icons.local_shipping_rounded,
            'image': 'assets/images/heavy_truck.png',
            'title': '30 Ton Truck',
            'desc': '14 Tyre - Up to 30 Ton',
            'time': '20 min away',
            'basicFare': 7100.0,
            'perKmFare': 71.0,
            'upTo275Fare': 21500.0,
          },
          {
            'icon': Icons.local_shipping_rounded,
            'image': 'assets/images/heavy_truck.png',
            'title': '35 Ton Truck',
            'desc': '16 Tyre - Up to 35 Ton',
            'time': '25 min away',
            'basicFare': 7500.0,
            'perKmFare': 75.0,
            'upTo275Fare': 23500.0,
          },
        ]
      : (isDelivery 
          ? [
              {
                'icon': Icons.two_wheeler_rounded,
                'image': 'assets/images/bike.png',
                'title': 'Bike',
                'desc': 'Small parcels, documents',
                'time': '3 min away',
                'basicFare': 30.0,
                'perKmFare': 12.0,
              },
              {
                'icon': Icons.electric_rickshaw_rounded,
                'image': 'assets/images/auto.png',
                'title': 'Auto',
                'desc': 'Medium weight packages',
                'time': '1 min away',
                'basicFare': 50.0,
                'perKmFare': 15.0,
              },
              {
                'icon': Icons.airport_shuttle_rounded,
                'image': 'assets/images/mini_truck.png',
                'title': 'Mini Truck',
                'desc': 'Large transport / goods',
                'time': '8 min away',
                'basicFare': 150.0,
                'perKmFare': 30.0,
              },
              {
                'icon': Icons.local_shipping_rounded,
                'image': 'assets/images/heavy_truck.png',
                'title': 'Heavy Truck',
                'desc': 'Retail, goods transport',
                'time': '12 min away',
                'basicFare': 300.0,
                'perKmFare': 45.0,
              },
            ]
          : [
              {
                'icon': Icons.two_wheeler_rounded,
                'image': 'assets/images/bike.png',
                'title': 'Bike',
                'desc': 'Quick solo travel',
                'time': '3 min away',
                'basicFare': 20.0,
                'perKmFare': 10.0,
              },
              {
                'icon': Icons.electric_rickshaw_rounded,
                'image': 'assets/images/auto.png',
                'title': 'Auto',
                'desc': 'Eco-friendly & fast',
                'time': '1 min away',
                'basicFare': 40.0,
                'perKmFare': 15.0,
                'badge': 'Fastest',
              },
              {
                'icon': Icons.directions_car_rounded,
                'image': 'assets/images/car.png',
                'title': 'Car',
                'desc': 'Comfortable AC cab',
                'time': '5 min away',
                'basicFare': 60.0,
                'perKmFare': 18.0,
              },
            ]);

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _pickupLatLng ?? _center,
              zoom: 13.0,
            ),
            onMapCreated: (controller) => _mapController = controller,
            polylines: _polylines,
            markers: _markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),

          // Back button
          Positioned(
            top: 50,
            left: 20,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: Colors.white,
              onPressed: () {
                setState(() {
                  _currentStep = 0; // Return to location selection
                });
              },
              child: const Icon(Icons.arrow_back, color: Colors.black),
            ),
          ),

          // Bottom Ride Selection Details Sheet
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: isDesktop ? 500 : double.infinity,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x0D000000),
                    blurRadius: 40,
                    offset: Offset(0, -12),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handlebar
                  Center(
                    child: Container(
                      width: 48,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Route info overlay
                  if (_distance != null && _duration != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.directions, color: AppTheme.primaryColor),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Distance: $_distance  •  Time: $_duration',
                              style: GoogleFonts.hankenGrotesk(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryColor,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  Text(
                    isDelivery ? 'Select Parcel Type' : 'Select Ride Type',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.onSurfaceColor,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Option List
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const BouncingScrollPhysics(),
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final item = options[index];
                        final isSelected = _selectedOptionIndex == index;
                        final computedPrice = _calculateFareText(
                          (item['basicFare'] as num).toDouble(),
                          (item['perKmFare'] as num).toDouble(),
                          upTo275Fare: item['upTo275Fare'] != null ? (item['upTo275Fare'] as num).toDouble() : null,
                        );
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedOptionIndex = index;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isSelected ? AppTheme.surfaceContainerLow : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected ? AppTheme.primaryColor : AppTheme.outlineVariant.withOpacity(0.3),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Stack(
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 56,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        color: AppTheme.surfaceContainer,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: item['image'] != null
                                          ? Padding(
                                              padding: const EdgeInsets.all(4.0),
                                              child: Image.asset(
                                                item['image'] as String,
                                                fit: BoxFit.contain,
                                                errorBuilder: (_, __, ___) => Icon(
                                                  item['icon'] as IconData,
                                                  color: AppTheme.primaryColor,
                                                  size: 28,
                                                ),
                                              ),
                                            )
                                          : Icon(
                                              item['icon'] as IconData,
                                              color: AppTheme.primaryColor,
                                              size: 28,
                                            ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item['title'] as String,
                                            style: GoogleFonts.hankenGrotesk(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.onSurfaceColor,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            item['desc'] as String,
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: AppTheme.onSurfaceVariant,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            item['time'] as String,
                                            style: GoogleFonts.robotoMono(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color: AppTheme.primaryColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      computedPrice,
                                      style: GoogleFonts.hankenGrotesk(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.onSurfaceColor,
                                      ),
                                    ),
                                  ],
                                ),
                                if (item['badge'] != null)
                                  Positioned(
                                    top: 0,
                                    right: 50,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: const BoxDecoration(
                                        color: AppTheme.primaryColor,
                                        borderRadius: BorderRadius.all(Radius.circular(10)),
                                      ),
                                      child: Text(
                                        item['badge'] as String,
                                        style: GoogleFonts.robotoMono(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (widget.serviceType == 'heavy_truck') ...[
                    Builder(
                      builder: (context) {
                        final selectedItem = options[_selectedOptionIndex];
                        final double basic = (selectedItem['basicFare'] as num).toDouble();
                        final double perKm = (selectedItem['perKmFare'] as num).toDouble();
                        final double? upTo275 = selectedItem['upTo275Fare'] != null ? (selectedItem['upTo275Fare'] as num).toDouble() : null;
                        
                        final computedPriceText = _calculateFareText(basic, perKm, upTo275Fare: upTo275);
                        final cleanStr = computedPriceText.replaceAll(RegExp(r'[^0-9.]'), '');
                        final double totalFare = double.tryParse(cleanStr) ?? basic;
                        
                        final double advance = 1.0;
                        final double balance = (totalFare - 1.0) < 0 ? 0.0 : totalFare - 1.0;
                        
                        return Container(
                          margin: const EdgeInsets.only(top: 8, bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade200.withOpacity(0.5)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Total Heavy Cargo Fare:',
                                    style: GoogleFonts.hankenGrotesk(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                                  ),
                                  Text(
                                    '₹${totalFare.toStringAsFixed(0)}',
                                    style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Divider(height: 1),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.flash_on, size: 14, color: AppTheme.primaryColor),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Advance Pay Online (Razorpay):',
                                        style: GoogleFonts.hankenGrotesk(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    '₹${advance.toStringAsFixed(0)}',
                                    style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Remaining Balance:',
                                        style: GoogleFonts.hankenGrotesk(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey.shade700),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    '₹${balance.toStringAsFixed(0)}',
                                    style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Payment Selector
                  InkWell(
                    onTap: _selectPaymentMethod,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.3)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: _isParcel
                                  ? (_selectedPaymentMethod == 'Pay at Pickup' ? Colors.green.withOpacity(0.1) : Colors.blue.withOpacity(0.1))
                                  : (_selectedPaymentMethod == 'Pay After Ride' ? Colors.green.withOpacity(0.1) : Colors.indigo.withOpacity(0.1)),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isParcel
                                  ? (_selectedPaymentMethod == 'Pay at Pickup' ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded)
                                  : (_selectedPaymentMethod == 'Pay After Ride' ? Icons.money_rounded : Icons.payment_rounded),
                              color: _isParcel
                                  ? (_selectedPaymentMethod == 'Pay at Pickup' ? Colors.green : Colors.blue)
                                  : (_selectedPaymentMethod == 'Pay After Ride' ? Colors.green : Colors.indigo),
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.serviceType == 'heavy_truck'
                                      ? _selectedPaymentMethod
                                      : (_isParcel
                                          ? _selectedPaymentMethod
                                          : (_selectedPaymentMethod == 'Pay After Ride' ? 'Pay After Ride (Cash/UPI)' : 'Pay Online Now (Razorpay)')),
                                  style: GoogleFonts.robotoMono(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.onSurfaceColor,
                                  ),
                                ),
                                Text(
                                  widget.serviceType == 'heavy_truck'
                                      ? (_selectedPaymentMethod == 'Advance Pay (Pickup Balance)'
                                          ? 'Pay ₹0 advance online, remaining at pickup'
                                          : 'Pay ₹0 advance online, remaining at drop')
                                      : (_isParcel
                                          ? (_selectedPaymentMethod == 'Pay at Pickup' ? 'Pay at the pickup location' : 'Pay at the drop destination')
                                          : (_selectedPaymentMethod == 'Pay After Ride' ? 'Pay to driver at destination' : 'Secure payment via card/UPI')),
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: AppTheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: AppTheme.outlineColor, size: 20),
                        ],
                      ),
                    ),
                  ),
                  if (_cancellationCharge > 0) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 16, color: Colors.amber),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Includes ₹${_cancellationCharge.toStringAsFixed(0)} previous cancellation charge',
                              style: GoogleFonts.inter(fontSize: 12, color: Colors.amber.shade900, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (widget.serviceType == 'heavy_truck') ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2), // Very light red
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Caution: Flat advance payment of ₹0 is non-refundable if the booking is cancelled.',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF991B1B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: _acceptHeavyTruckTollgateTerms,
                            activeColor: AppTheme.primaryColor,
                            onChanged: (bool? val) {
                              setState(() {
                                _acceptHeavyTruckTollgateTerms = val ?? false;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _acceptHeavyTruckTollgateTerms = !_acceptHeavyTruckTollgateTerms;
                              });
                            },
                            child: Text(
                              'I accept that tollgate and any other additional charges are payable by the customer.',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Confirm Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isConfirming || (widget.serviceType == 'heavy_truck' && !_acceptHeavyTruckTollgateTerms) ? null : () {
                        final selected = options[_selectedOptionIndex];
                        final priceText = _calculateFareText(
                          (selected['basicFare'] as num).toDouble(),
                          (selected['perKmFare'] as num).toDouble(),
                          upTo275Fare: selected['upTo275Fare'] != null ? (selected['upTo275Fare'] as num).toDouble() : null,
                        );
                        _confirmBooking(
                          selected['title'] as String,
                          priceText,
                        );
                      },
                      child: _isConfirming
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  isDelivery ? 'Confirm Parcel Request' : 'Confirm Booking',
                                  style: GoogleFonts.hankenGrotesk(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.arrow_forward, size: 20),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- PARCEL FLOW METHODS ---

  Widget _buildParcelFlow() {
    switch (_parcelStep) {
      case 0:
        if (widget.serviceType == 'heavy_truck') {
          return _buildHeavyTruckPickupEntry();
        }
        return _buildParcelAddressEntry(isPickup: true);
      case 1:
        return _buildConfirmDetailsStep(isPickup: true);
      case 2:
        return _buildParcelDashboard();
      case 3:
        return _buildConfirmDetailsStep(isPickup: false);
      case 4:
        return _buildRouteAndBookingStep();
      case 5:
        return _buildParcelAddressEntry(isPickup: false);
      default:
        if (widget.serviceType == 'heavy_truck') {
          return _buildHeavyTruckPickupEntry();
        }
        return _buildParcelAddressEntry(isPickup: true);
    }
  }

  Widget _buildQuickSlotChip(String label, String targetSlot, List<String> availableSlots) {
    final isAllowed = _isSlotAtLeast5HoursAhead(_heavyTruckDate, targetSlot);
    final isSelected = _heavyTruckTimeSlot == targetSlot;

    return InkWell(
      onTap: () {
        if (!isAllowed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Please select a time slot at least 5 hours from the current time.',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFFD32F2F),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 3),
            ),
          );
          return;
        }
        setState(() {
          _heavyTruckTimeSlot = targetSlot;
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF1E60FF)
              : (isAllowed ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.02)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF3B82F6)
                : (isAllowed ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.04)),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : (isAllowed ? Colors.white70 : Colors.white24),
          ),
        ),
      ),
    );
  }

  Widget _buildHeavyTruckPickupEntry() {
    final dates = _getHeavyTruckDates();
    if (_heavyTruckDate == null && dates.isNotEmpty) {
      _heavyTruckDate = dates.first;
    }
    final timeSlots = _heavyTruckDate != null ? _getHeavyTruckTimeSlotsForDate(_heavyTruckDate!) : <String>[];
    if (_heavyTruckTimeSlot == null && timeSlots.isNotEmpty) {
      _heavyTruckTimeSlot = timeSlots.first;
    } else if (_heavyTruckTimeSlot != null && !timeSlots.contains(_heavyTruckTimeSlot)) {
      _heavyTruckTimeSlot = timeSlots.isNotEmpty ? timeSlots.first : null;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF080B13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF080B13),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Heavy Truck Booking',
          style: GoogleFonts.hankenGrotesk(
            fontWeight: FontWeight.w700,
            color: Colors.white,
            fontSize: 20,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Select Date & Time Slot Card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF111729),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select Date',
                    style: GoogleFonts.hankenGrotesk(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<DateTime>(
                        value: _heavyTruckDate,
                        dropdownColor: const Color(0xFF111729),
                        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70),
                        isExpanded: true,
                        items: dates.map((date) {
                          final daysOfWeek = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                          final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                          final formatted = '${daysOfWeek[date.weekday - 1]}, ${date.day} ${months[date.month - 1]} ${date.year}';
                          return DropdownMenuItem<DateTime>(
                            value: date,
                            child: Text(
                              formatted,
                              style: GoogleFonts.inter(color: Colors.white, fontSize: 15),
                            ),
                          );
                        }).toList(),
                        onChanged: (newDate) {
                          if (newDate != null) {
                            setState(() {
                              _heavyTruckDate = newDate;
                              final newSlots = _getHeavyTruckTimeSlotsForDate(newDate);
                              if (newSlots.isNotEmpty) {
                                _heavyTruckTimeSlot = newSlots.first;
                              }
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Select Time Slot',
                    style: GoogleFonts.hankenGrotesk(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isHeavyTruckTimeSlotValid()
                            ? Colors.white.withOpacity(0.1)
                            : const Color(0xFFEF4444),
                        width: _isHeavyTruckTimeSlotValid() ? 1.0 : 1.5,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: (timeSlots.contains(_heavyTruckTimeSlot)) ? _heavyTruckTimeSlot : (timeSlots.isNotEmpty ? timeSlots.first : null),
                        dropdownColor: const Color(0xFF111729),
                        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 22),
                        isExpanded: true,
                        items: timeSlots.map((slot) {
                          return DropdownMenuItem<String>(
                            value: slot,
                            child: Row(
                              children: [
                                const Icon(Icons.access_time_rounded, size: 16, color: Color(0xFF3B82F6)),
                                const SizedBox(width: 8),
                                Text(
                                  slot,
                                  style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (newSlot) {
                          if (newSlot != null) {
                            if (!_isSlotAtLeast5HoursAhead(_heavyTruckDate, newSlot)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(Icons.error_outline, color: Colors.white, size: 20),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Please select a time slot at least 5 hours from the current time.',
                                          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                  backgroundColor: const Color(0xFFD32F2F),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  duration: const Duration(seconds: 4),
                                ),
                              );
                              return;
                            }
                            setState(() {
                              _heavyTruckTimeSlot = newSlot;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  if (!_isHeavyTruckTimeSlotValid()) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0x29EF4444),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFEF4444), width: 1.2),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Please select a time slot at least 5 hours from the current time.',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFFFCA5A5),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  // Quick-pick 5-hour Interval Timing Chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _buildQuickSlotChip('🌅 06:00 AM', '06:00 AM', timeSlots),
                      _buildQuickSlotChip('☀️ 11:00 AM', '11:00 AM', timeSlots),
                      _buildQuickSlotChip('🌆 04:00 PM', '04:00 PM', timeSlots),
                      _buildQuickSlotChip('🌙 09:00 PM', '09:00 PM', timeSlots),
                    ],
                  ),
                ],
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Confirm Address Pin',
                style: GoogleFonts.hankenGrotesk(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
            
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Colors.black87, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _pickupController,
                      focusNode: _pickupFocusNode,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.black, // Explicitly pure black typed letters
                      ),
                      cursorColor: Colors.black,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (val) {
                        _submitAddress(val, true);
                      },
                      onTap: () {
                        setState(() {
                          _isPickupActive = true;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search address or area..',
                        hintStyle: GoogleFonts.inter(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  if (_pickupController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.cancel, color: Colors.grey, size: 20),
                      splashRadius: 18,
                      onPressed: () {
                        setState(() {
                          _pickupController.clear();
                          _pickupPredictions.clear();
                        });
                      },
                    ),
                ],
              ),
            ),
            
            const SizedBox(height: 8),
            
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _pickupLatLng ?? _center,
                        zoom: 15.0,
                      ),
                      onMapCreated: (controller) => _mapController = controller,
                      myLocationEnabled: true,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      markers: _pickupLatLng != null
                          ? {
                              Marker(
                                markerId: const MarkerId('pickup_pin'),
                                position: _pickupLatLng!,
                                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                              )
                            }
                          : {},
                      onCameraMove: (position) {
                        _mapSelectionCenter = position.target;
                      },
                    ),
                  ),
                  
                  if (_pickupPredictions.isNotEmpty && _pickupFocusNode.hasFocus)
                    Positioned(
                      left: 16,
                      right: 16,
                      top: 8,
                      bottom: 8,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.12),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ListView.separated(
                          itemCount: _pickupPredictions.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                          itemBuilder: (context, index) {
                            final pred = _pickupPredictions[index];
                            return ListTile(
                              leading: const Icon(Icons.location_on, color: AppTheme.primaryColor, size: 22),
                              title: Text(
                                pred.mainText,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: pred.secondaryText.isNotEmpty
                                  ? Text(
                                      pred.secondaryText,
                                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
                                    )
                                  : null,
                              onTap: () {
                                _pickupFocusNode.unfocus();
                                _selectPredictionItem(pred);
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 20,
                    child: ElevatedButton(
                      onPressed: () {
                        if (widget.serviceType == 'heavy_truck' && !_isHeavyTruckTimeSlotValid()) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  const Icon(Icons.error_outline, color: Colors.white, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Please select a time slot at least 5 hours from the current time.',
                                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                              backgroundColor: const Color(0xFFD32F2F),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              duration: const Duration(seconds: 4),
                            ),
                          );
                          return;
                        }
                        if (_pickupController.text.isEmpty || _pickupLatLng == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please select or search a pickup address first'),
                              backgroundColor: AppTheme.errorColor,
                            ),
                          );
                          return;
                        }
                        setState(() {
                          _parcelStep = 1;
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        elevation: 4,
                      ),
                      child: Text(
                        'Confirm Location',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParcelAddressEntry({required bool isPickup}) {
    final activePredictions = isPickup ? _pickupPredictions : _dropPredictions;
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            setState(() {
              if (isPickup) {
                Navigator.pop(context);
              } else {
                _parcelStep = 2;
              }
            });
          },
        ),
        title: Text(
          isPickup ? 'Pickup from' : 'Drop to',
          style: GoogleFonts.hankenGrotesk(
            fontWeight: FontWeight.w700,
            color: Colors.black,
            fontSize: 22,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isPickup ? Colors.green : Colors.red,
                          width: 2.5,
                        ),
                        color: Colors.white,
                      ),
                      child: Center(
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isPickup ? Colors.green : Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: isPickup ? _pickupController : _dropController,
                        focusNode: isPickup ? _pickupFocusNode : _dropFocusNode,
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black),
                        cursorColor: Colors.black,
                        textInputAction: TextInputAction.search,
                        autofocus: true,
                        onSubmitted: (val) {
                          _submitAddress(val, isPickup);
                        },
                        onTap: () {
                          setState(() {
                            _isPickupActive = isPickup;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: isPickup ? 'Search pickup address' : 'Search drop address',
                          hintStyle: GoogleFonts.inter(color: Colors.grey.shade500, fontSize: 16),
                          filled: true,
                          fillColor: Colors.white,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _isPickupActive = isPickup;
                      _selectingPickupOnMap = isPickup;
                      final currentCoord = isPickup ? _pickupLatLng : _dropLatLng;
                      _mapSelectionCenter = currentCoord ?? _center;
                      _currentStep = 1; // Map select
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    backgroundColor: Colors.white,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.location_on_outlined, color: Colors.black87, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Select on map',
                        style: GoogleFonts.hankenGrotesk(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(),
            Expanded(
              child: activePredictions.isNotEmpty
                  ? ListView.separated(
                      itemCount: activePredictions.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
                      itemBuilder: (context, index) {
                        final pred = activePredictions[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.location_on, color: AppTheme.primaryColor, size: 20),
                          ),
                          title: Text(
                            pred.mainText,
                            style: GoogleFonts.hankenGrotesk(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87),
                          ),
                          subtitle: pred.secondaryText.isNotEmpty
                              ? Text(
                                  pred.secondaryText,
                                  style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : null,
                          trailing: const Icon(Icons.north_west_rounded, size: 16, color: Colors.grey),
                          onTap: () => _selectPredictionItem(pred),
                        );
                      },
                    )
                  : ListView(
                      children: [
                        if (isPickup) ...[
                          ListTile(
                            leading: const Icon(Icons.my_location, color: Colors.blueAccent),
                            title: Text(
                              'Current location',
                              style: GoogleFonts.hankenGrotesk(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Colors.blueAccent,
                              ),
                            ),
                            subtitle: Text(
                              'Use device GPS coordinates',
                              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
                            ),
                            onTap: _detectCurrentLocation,
                          ),
                          if (_historyLocations.isNotEmpty) const Divider(height: 1),
                        ],
                        ..._historyLocations.map((item) {
                          return Container(
                            decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                            ),
                            child: ListTile(
                              leading: Icon(Icons.history, color: Colors.grey.shade600),
                              title: Text(
                                item['title'] as String,
                                style: GoogleFonts.hankenGrotesk(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  color: Colors.black87,
                                ),
                              ),
                              subtitle: Text(
                                item['address'] as String,
                                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Icon(Icons.favorite_border_rounded, color: Colors.grey.shade400, size: 20),
                              onTap: () => _selectHistoryItem(
                                item['title'] as String,
                                item['address'] as String,
                                item['latLng'] as LatLng,
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmDetailsStep({required bool isPickup}) {
    final selectedCoord = isPickup ? _pickupLatLng : _dropLatLng;
    final addressText = isPickup ? _pickupController.text : _dropController.text;
    final houseController = isPickup ? _pickupHouseController : _dropHouseController;
    final nameController = isPickup ? _pickupNameController : _dropNameController;
    final phoneController = isPickup ? _pickupPhoneController : _dropPhoneController;
    final useMyContact = isPickup ? _pickupUseMyContact : _dropUseMyContact;
    final selectedFavourite = isPickup ? _pickupFavourite : _dropFavourite;

    if (selectedCoord == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: selectedCoord,
              zoom: 15.0,
            ),
            markers: {
              Marker(
                markerId: const MarkerId('confirm_pin'),
                position: selectedCoord,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  isPickup ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
                ),
              ),
            },
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
          ),

          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isPickup ? Colors.green : Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        addressText,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          if (isPickup) {
                            _parcelStep = 0;
                          } else {
                            _parcelStep = 5;
                          }
                        });
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        backgroundColor: Colors.grey.shade100,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      child: Text(
                        'Edit',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            left: 16,
            bottom: 490,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: CircleAvatar(
                backgroundColor: Colors.white,
                radius: 20,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black, size: 20),
                  onPressed: () {
                    setState(() {
                      if (isPickup) {
                        _parcelStep = 0;
                      } else {
                        _parcelStep = 2;
                      }
                    });
                  },
                ),
              ),
            ),
          ),

          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 470,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: houseController,
                            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black),
                            cursorColor: Colors.black,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              prefixIcon: const Icon(Icons.home_outlined),
                              hintText: 'House no./ Building (optional)',
                              hintStyle: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Add contact details',
                            style: GoogleFonts.hankenGrotesk(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: nameController,
                            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black),
                            cursorColor: Colors.black,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              prefixIcon: const Icon(Icons.person_outline),
                              suffixIcon: const Icon(Icons.contact_phone_outlined, color: Colors.grey),
                              hintText: 'Name*',
                              hintStyle: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            onChanged: (val) {
                              if (useMyContact && val != widget.userName) {
                                setState(() {
                                  if (isPickup) {
                                    _pickupUseMyContact = false;
                                  } else {
                                    _dropUseMyContact = false;
                                  }
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: useMyContact,
                                  activeColor: AppTheme.primaryColor,
                                  onChanged: (bool? checked) {
                                    setState(() {
                                      if (isPickup) {
                                        _pickupUseMyContact = checked ?? false;
                                        if (_pickupUseMyContact) {
                                          _pickupNameController.text = widget.userName;
                                          _pickupPhoneController.text = widget.phoneNumber;
                                        } else {
                                          _pickupNameController.clear();
                                          _pickupPhoneController.clear();
                                        }
                                      } else {
                                        _dropUseMyContact = checked ?? false;
                                        if (_dropUseMyContact) {
                                          _dropNameController.text = widget.userName;
                                          _dropPhoneController.text = widget.phoneNumber;
                                        } else {
                                          _dropNameController.clear();
                                          _dropPhoneController.clear();
                                        }
                                      }
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    final newVal = !useMyContact;
                                    if (isPickup) {
                                      _pickupUseMyContact = newVal;
                                      if (_pickupUseMyContact) {
                                        _pickupNameController.text = widget.userName;
                                        _pickupPhoneController.text = widget.phoneNumber;
                                      } else {
                                        _pickupNameController.clear();
                                        _pickupPhoneController.clear();
                                      }
                                    } else {
                                      _dropUseMyContact = newVal;
                                      if (_dropUseMyContact) {
                                        _dropNameController.text = widget.userName;
                                        _dropPhoneController.text = widget.phoneNumber;
                                      } else {
                                        _dropNameController.clear();
                                        _dropPhoneController.clear();
                                      }
                                    }
                                  });
                                },
                                child: Text(
                                  'Use my contact for this booking',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: phoneController,
                            keyboardType: TextInputType.phone,
                            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black),
                            cursorColor: Colors.black,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              prefixIcon: const Icon(Icons.phone_outlined),
                              hintText: 'Phone Number*',
                              hintStyle: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            onChanged: (val) {
                              if (useMyContact && val != widget.phoneNumber) {
                                setState(() {
                                  if (isPickup) {
                                    _pickupUseMyContact = false;
                                  } else {
                                    _dropUseMyContact = false;
                                  }
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Add to favourites',
                            style: GoogleFonts.hankenGrotesk(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildFavouriteChip(
                                  label: 'Work',
                                  icon: Icons.work_outline,
                                  isSelected: selectedFavourite == 'Work',
                                  onTap: () => _toggleFavourite(isPickup, 'Work'),
                                ),
                                const SizedBox(width: 8),
                                _buildFavouriteChip(
                                  label: 'Gym',
                                  icon: Icons.fitness_center,
                                  isSelected: selectedFavourite == 'Gym',
                                  onTap: () => _toggleFavourite(isPickup, 'Gym'),
                                ),
                                const SizedBox(width: 8),
                                _buildFavouriteChip(
                                  label: 'College',
                                  icon: Icons.school_outlined,
                                  isSelected: selectedFavourite == 'College',
                                  onTap: () => _toggleFavourite(isPickup, 'College'),
                                ),
                                const SizedBox(width: 8),
                                _buildFavouriteChip(
                                  label: 'Hostel',
                                  icon: Icons.home_work_outlined,
                                  isSelected: selectedFavourite == 'Hostel',
                                  onTap: () => _toggleFavourite(isPickup, 'Hostel'),
                                ),
                                const SizedBox(width: 8),
                                _buildFavouriteChip(
                                  label: 'Add New',
                                  icon: Icons.add,
                                  isSelected: false,
                                  onTap: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Custom favourite added!')),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: (nameController.text.trim().isNotEmpty && phoneController.text.trim().isNotEmpty)
                            ? () {
                                setState(() {
                                  if (isPickup) {
                                    _parcelStep = 2;
                                  } else {
                                    _checkAndCalculateRoute();
                                    _parcelStep = 4;
                                  }
                                });
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text(
                          isPickup ? 'Confirm pickup details' : 'Confirm drop details',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParcelDashboard() {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 600;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            setState(() {
              _parcelStep = 1;
            });
          },
        ),
        title: Text(
          'Doorstep pickup & delivery',
          style: GoogleFonts.hankenGrotesk(
            fontWeight: FontWeight.w700,
            color: Colors.black,
            fontSize: 18,
          ),
        ),
      ),
      body: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: isDesktop ? 600 : double.infinity),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFE0F2FE), Color(0xFFEFF6FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PARCEL',
                          style: GoogleFonts.robotoMono(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            color: const Color(0xFF1E40AF),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Instant local delivery',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: Image.asset(
                            'assets/images/bike.png',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(Icons.two_wheeler_rounded, size: 36, color: Colors.blue.shade700),
                          ),
                        ),
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: Image.asset(
                            'assets/images/parcel.png',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(Icons.inventory_2_rounded, size: 36, color: Colors.blue.shade600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: Image.asset(
                            'assets/images/heavy_truck.png',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(Icons.local_shipping_rounded, size: 36, color: Colors.blue.shade500),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.02),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(top: 2),
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.green, width: 2),
                                    color: Colors.white,
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: Colors.green,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Pickup from location',
                                        style: GoogleFonts.hankenGrotesk(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _pickupController.text + 
                                            (_pickupHouseController.text.trim().isNotEmpty
                                                ? ', House: ${_pickupHouseController.text}'
                                                : ''),
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${_pickupNameController.text} (${_pickupPhoneController.text})',
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, color: Colors.grey),
                                  onPressed: () {
                                    setState(() {
                                      _parcelStep = 1;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            right: 16,
                            bottom: 0,
                            child: Transform.translate(
                              offset: const Offset(0, 16),
                              child: Material(
                                elevation: 3,
                                shape: const CircleBorder(),
                                color: Colors.white,
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: _swapPickupAndDrop,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    child: const Icon(
                                      Icons.swap_vert_rounded,
                                      color: AppTheme.primaryColor,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 2),
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.red, width: 2),
                                color: Colors.white,
                              ),
                              child: Center(
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _dropLatLng == null
                                  ? InkWell(
                                      onTap: () {
                                        setState(() {
                                          _isPickupActive = false;
                                          _parcelStep = 5;
                                        });
                                      },
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Drop to',
                                            style: GoogleFonts.hankenGrotesk(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.shade50.withOpacity(0.4),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: Colors.blue.shade100),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(Icons.search, color: Colors.blueAccent, size: 18),
                                                const SizedBox(width: 8),
                                                Text(
                                                  'Search drop address',
                                                  style: GoogleFonts.inter(
                                                    color: Colors.blue.shade700,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Drop to location',
                                          style: GoogleFonts.hankenGrotesk(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _dropController.text + 
                                              (_dropHouseController.text.trim().isNotEmpty
                                                  ? ', House: ${_dropHouseController.text}'
                                                  : ''),
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${_dropNameController.text} (${_dropPhoneController.text})',
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                            if (_dropLatLng != null) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, color: Colors.grey),
                                onPressed: () {
                                  setState(() {
                                    _parcelStep = 3;
                                  });
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Container(
                width: double.infinity,
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'By continuing, you agree to our Terms & Conditions',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Read about ',
                          style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500),
                        ),
                        GestureDetector(
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Prohibited items: Weapons, Illegal drugs, Explosives, etc.')),
                            );
                          },
                          child: Text(
                            'prohibited items',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_pickupLatLng != null && _dropLatLng != null) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _checkAndCalculateRoute();
                              _parcelStep = 4;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            'Proceed to Booking',
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _swapPickupAndDrop() {
    setState(() {
      final tempAddress = _pickupController.text;
      _pickupController.text = _dropController.text;
      _dropController.text = tempAddress;

      final tempLatLng = _pickupLatLng;
      _pickupLatLng = _dropLatLng;
      _dropLatLng = tempLatLng;

      final tempHouse = _pickupHouseController.text;
      _pickupHouseController.text = _dropHouseController.text;
      _dropHouseController.text = tempHouse;

      final tempName = _pickupNameController.text;
      _pickupNameController.text = _dropNameController.text;
      _dropNameController.text = tempName;

      final tempPhone = _pickupPhoneController.text;
      _pickupPhoneController.text = _dropPhoneController.text;
      _dropPhoneController.text = tempPhone;

      final tempUseMyContact = _pickupUseMyContact;
      _pickupUseMyContact = _dropUseMyContact;
      _dropUseMyContact = tempUseMyContact;

      final tempFav = _pickupFavourite;
      _pickupFavourite = _dropFavourite;
      _dropFavourite = tempFav;
    });

    _checkAndCalculateRoute();
  }

  Widget _buildFavouriteChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor.withOpacity(0.08) : Colors.grey.shade50,
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.grey.shade200,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? AppTheme.primaryColor : Colors.grey.shade600,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? AppTheme.primaryColor : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleFavourite(bool isPickup, String value) {
    setState(() {
      if (isPickup) {
        _pickupFavourite = (_pickupFavourite == value) ? '' : value;
      } else {
        _dropFavourite = (_dropFavourite == value) ? '' : value;
      }
    });
  }
}
