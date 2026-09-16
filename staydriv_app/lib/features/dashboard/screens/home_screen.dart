import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:staydriv_app/core/js_stub.dart'
    if (dart.library.js) 'dart:js' as js;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import '../../../core/api_client.dart';
import '../../../core/network_monitor.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/firebase_service.dart';
import '../../../core/network_config.dart';
import '../../../core/theme.dart';
import '../../../core/razorpay_gateway.dart';
import '../../../core/booking_manager.dart';
import '../../../core/twilio_service.dart';
import '../../ride_selection/screens/ride_selection_screen.dart';
import '../../activity_history/screens/activity_screen.dart';
import '../../onboarding/screens/login_screen.dart';
import '../../live_tracking/screens/live_tracking_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeScreen extends StatefulWidget {
  final String userName;
  final String userRole;
  final String phoneNumber;
  final String? selectedVehicle;
  
  const HomeScreen({
    super.key,
    required this.userName,
    required this.userRole,
    required this.phoneNumber,
    this.selectedVehicle,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentTabIndex = 0;
  LatLng _center = const LatLng(17.4834, 78.3871);

  String _formatDateToCustomString(dynamic input) {
    if (input == null) return '';
    final dateStr = input.toString();
    if (dateStr.isEmpty) return '';
    try {
      DateTime? dt;
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateStr)) {
        final parts = dateStr.split('-');
        dt = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      } else {
        dt = DateTime.tryParse(dateStr);
      }
      if (dt == null) return dateStr;
      
      final List<String> months = [
        'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
        'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'
      ];
      final dayStr = dt.day.toString().padLeft(2, '0');
      final monthStr = months[dt.month - 1];
      final yearStr = dt.year.toString();
      
      return "$dayStr-$monthStr-$yearStr";
    } catch (_) {
      return dateStr;
    }
  }

  // Profile edit states
  late String _editableUserName;
  String _emailAddress = 'Not Provided';
  String _dateOfBirth = 'Not Provided';
  String? _profilePhotoPath;

  // Verification Documents states
  String? _aadhaarFront;
  String? _aadhaarBack;
  String? _licenseFront;
  String? _licenseBack;
  String? _rcFront;
  String? _rcBack;
  String? _fitness;
  String? _permit;

  String? _photoName;
  String? _photoSize;
  String? _aadhaarFrontName;
  String? _aadhaarFrontSize;
  String? _aadhaarBackName;
  String? _aadhaarBackSize;
  String? _licenseFrontName;
  String? _licenseFrontSize;
  String? _licenseBackName;
  String? _licenseBackSize;
  String? _rcFrontName;
  String? _rcFrontSize;
  String? _rcBackName;
  String? _rcBackSize;
  String? _fitnessName;
  String? _fitnessSize;
  String? _permitName;
  String? _permitSize;

  bool _isLoadingProfile = false;
  double _pilotSalary = 5000.0;
  double _customerCancellationCharge = 0.0;

  Set<Marker> _markers = {
    const Marker(markerId: MarkerId('d1'), position: LatLng(17.4854, 78.3891)),
    const Marker(markerId: MarkerId('d2'), position: LatLng(17.4814, 78.3851)),
    const Marker(markerId: MarkerId('d3'), position: LatLng(17.4874, 78.3841)),
    const Marker(markerId: MarkerId('d4'), position: LatLng(17.4804, 78.3911)),
    const Marker(markerId: MarkerId('d5'), position: LatLng(17.4844, 78.3881)),
  };

  // Driver Partner states
  String _selectedVehicle = 'Bike';
  bool _isOnline = false;
  String _driverStatus = 'offline'; // 'offline', 'online', 'incoming_request', 'heading_to_pickup', 'arrived_pickup', 'on_trip', 'payment_pending'
  Map<String, dynamic>? _activeBooking;
  double _totalEarnings = 1250.0;
  bool _isAdvanceWithdrawn = false;
  List<Map<String, dynamic>> _completedRides = [];
  Timer? _bookingTimer;
  
  // Incoming Request logic
  int _incomingRequestCountdown = 10;
  Timer? _countdownTimer;

  LatLng? _driverMapCenter = const LatLng(17.4834, 78.3871); // Default: Hyderabad
  GoogleMapController? _driverMapController;
  GoogleMapController? _customerMapController;
  final TextEditingController _otpTextController = TextEditingController(text: '1234');
  final TextEditingController _adminSearchController = TextEditingController();
  String _otpError = '';
  List<LatLng> _driverRoutePoints = [];

  StreamSubscription<Map<String, dynamic>?>? _bookingSub;
  StreamSubscription<LatLng>? _driverLocationSub;
  StreamSubscription<String>? _rideStatusSub;
  StreamSubscription<Position>? _gpsSub;

  // Admin streams
  Stream<QuerySnapshot>? _adminBookingsStream;
  Stream<QuerySnapshot>? _adminDriversStream;

  Timer? _adminMongoPollTimer;
  List<Map<String, dynamic>> _mongoAdminBookings = [];
  List<Map<String, dynamic>> _mongoAdminDrivers = [];
  Map<String, dynamic>? _selectedDriverForDocApproval;
  String _adminSearchQuery = '';

  StreamSubscription<NetworkStatus>? _networkSub;
  NetworkStatus _networkStatus = NetworkStatus.connected;
  bool _showSuccessBanner = false;
  Timer? _successBannerTimer;

  bool get _isFirebaseInitialized => false;
  
  bool _isRatingSheetShowing = false;
  double _customerRating = 5.0;
  final TextEditingController _customerFeedbackController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _editableUserName = widget.userName;
    _driverMapCenter = BookingManager().driverLatLng;
    if (widget.selectedVehicle != null) {
      _selectedVehicle = widget.selectedVehicle!;
    }
    if (widget.userRole == 'Driver' || widget.userRole == 'Customer') {
      _loadCompletedRides();
      _loadProfileData();
    }
    if (widget.userRole == 'Customer') {
      _startCustomerGpsTracking();
      _subscribeToCustomerBookingManager();
      BookingManager().restoreAndSyncActiveBooking();
    }
    if (widget.userRole == 'Admin') {
      if (_isFirebaseInitialized) {
        _adminBookingsStream = FirebaseFirestore.instance
            .collection('bookings')
            .orderBy('createdAt', descending: true)
            .limit(10)
            .snapshots();
        _adminDriversStream = FirebaseFirestore.instance
            .collection('partners')
            .snapshots();
      } else {
        _startAdminMongoPolling();
      }
    }

    _networkStatus = NetworkMonitor().currentStatus;
    _networkSub = NetworkMonitor().statusStream.listen((status) {
      if (mounted) {
        setState(() {
          if (status == NetworkStatus.connected && 
              (_networkStatus == NetworkStatus.disconnected || _networkStatus == NetworkStatus.reconnecting || _networkStatus == NetworkStatus.weak)) {
            _showSuccessBanner = true;
            _successBannerTimer?.cancel();
            _successBannerTimer = Timer(const Duration(seconds: 3), () {
              if (mounted) {
                setState(() {
                  _showSuccessBanner = false;
                });
              }
            });
          }
          _networkStatus = status;
        });
      }
    });
  }

  void _startCustomerGpsTracking() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
        final latLng = LatLng(pos.latitude, pos.longitude);
        if (mounted) {
          setState(() {
            _center = latLng;
            _markers = {
              Marker(markerId: const MarkerId('d1'), position: LatLng(latLng.latitude + 0.002, latLng.longitude + 0.002)),
              Marker(markerId: const MarkerId('d2'), position: LatLng(latLng.latitude - 0.002, latLng.longitude - 0.002)),
              Marker(markerId: const MarkerId('d3'), position: LatLng(latLng.latitude + 0.004, latLng.longitude - 0.003)),
              Marker(markerId: const MarkerId('d4'), position: LatLng(latLng.latitude - 0.003, latLng.longitude + 0.004)),
              Marker(markerId: const MarkerId('d5'), position: LatLng(latLng.latitude + 0.001, latLng.longitude - 0.001)),
            };
          });
          if (_customerMapController != null) {
            _customerMapController!.animateCamera(CameraUpdate.newLatLng(latLng));
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting customer GPS position: $e');
    }
  }

  void _showNetworkSettingsDialog() {
    final controller = TextEditingController(text: NetworkConfig.backendUrl);
    bool isTesting = false;
    String? testResult;
    bool? testSuccess;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.wifi_tethering, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Server & Network Settings',
                      style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Configure your backend server connection. Use the 4G/5G HTTPS Tunnel for mobile SIM networks (Jio, Airtel, Vi, BSNL).',
                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 18, color: Colors.blue.shade800),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '4G/5G Mobile carriers block HTTP cleartext traffic. Always use HTTPS tunnel on mobile data.',
                              style: GoogleFonts.inter(fontSize: 11, color: Colors.blue.shade900, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'QUICK PRESETS (1-TAP):',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.cell_tower, size: 14, color: Colors.green),
                          label: const Text('⚡ 4G/5G HTTPS Tunnel', style: TextStyle(fontSize: 11)),
                          backgroundColor: Colors.green.shade50,
                          onPressed: () {
                            setDialogState(() {
                              controller.text = NetworkConfig.defaultHttpsTunnelUrl;
                              testResult = null;
                            });
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.android, size: 14, color: Colors.purple),
                          label: const Text('💻 Android Emulator', style: TextStyle(fontSize: 11)),
                          backgroundColor: Colors.purple.shade50,
                          onPressed: () {
                            setDialogState(() {
                              controller.text = 'http://10.0.2.2:3000';
                              testResult = null;
                            });
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.computer, size: 14, color: Colors.blue),
                          label: const Text('🌐 Localhost', style: TextStyle(fontSize: 11)),
                          backgroundColor: Colors.blue.shade50,
                          onPressed: () {
                            setDialogState(() {
                              controller.text = 'http://localhost:3000';
                              testResult = null;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        labelText: 'SERVER BACKEND URL',
                        hintText: 'https://staydriv-v3-dev.loca.lt',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: isTesting
                              ? null
                              : () async {
                                  final target = controller.text.trim();
                                  if (target.isEmpty) return;
                                  setDialogState(() {
                                    isTesting = true;
                                    testResult = 'Testing connection...';
                                    testSuccess = null;
                                  });
                                  final ok = await NetworkConfig.testConnection(target);
                                  setDialogState(() {
                                    isTesting = false;
                                    testSuccess = ok;
                                    testResult = ok
                                        ? '✅ Connected Successfully (HTTP 200 OK)'
                                        : '❌ Connection Failed (Server Unreachable)';
                                  });
                                },
                          icon: isTesting
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.speed, size: 16),
                          label: const Text('Test Connection', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    if (testResult != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: (testSuccess ?? false) ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: (testSuccess ?? false) ? Colors.green.shade300 : Colors.red.shade300),
                        ),
                        child: Text(
                          testResult!,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: (testSuccess ?? false) ? Colors.green.shade900 : Colors.red.shade900,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'Active: ${NetworkConfig.backendUrl}',
                      style: GoogleFonts.robotoMono(fontSize: 11, color: Colors.green.shade800, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final url = controller.text.trim();
                    if (url.isNotEmpty) {
                      try {
                        setState(() {
                          NetworkConfig.backendUrl = url;
                        });
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('backend_url', NetworkConfig.backendUrl);
                        await prefs.setString('custom_backend_url', NetworkConfig.backendUrl);
                        NetworkMonitor().forceCheck();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Server URL updated: ${NetworkConfig.backendUrl}'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                        Navigator.pop(context);
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(e.toString().replaceAll('Exception: ', '')),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  },
                  child: const Text('Save Settings'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _startAdminMongoPolling() {
    _adminMongoPollTimer?.cancel();
    _adminMongoPollTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
      if (!mounted) return;
      try {
        final baseUrl = NetworkConfig.backendUrl;
        
        final bookingsUrl = Uri.parse('$baseUrl/api/admin/bookings');
        final bResponse = await ApiClient().get(bookingsUrl, retry: false);
        if (bResponse.statusCode == 200) {
          final bData = jsonDecode(bResponse.body);
          if (bData['success'] == true && bData['bookings'] != null) {
            final List rawBookings = bData['bookings'];
            if (mounted) {
              setState(() {
                _mongoAdminBookings = List<Map<String, dynamic>>.from(rawBookings);
              });
            }
          }
        }

        final driversUrl = Uri.parse('$baseUrl/api/admin/drivers');
        final dResponse = await ApiClient().get(driversUrl, retry: false);
        if (dResponse.statusCode == 200) {
          final dData = jsonDecode(dResponse.body);
          if (dData['success'] == true && dData['drivers'] != null) {
            final List rawDrivers = dData['drivers'];
            if (mounted) {
              setState(() {
                _mongoAdminDrivers = List<Map<String, dynamic>>.from(rawDrivers);
              });
            }
          }
        }
      } catch (e) {
        debugPrint("Error polling Admin data from MongoDB: $e");
      }
    });
  }

  void _loadCompletedRides() async {
    final uid = FirebaseService().currentUid;
    if (uid == null) return;
    
    if (!_isFirebaseInitialized) {
      // Fetch from MongoDB via API
      try {
        final baseUrl = NetworkConfig.backendUrl;
        final url = Uri.parse('$baseUrl/api/user/$uid/rides?role=${widget.userRole}&allStatuses=true');
        final response = await ApiClient().get(url, retry: false);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['bookings'] != null) {
            final List rawBookings = data['bookings'];
            List<Map<String, dynamic>> rides = [];
            double earnings = 0.0;
            
            for (var booking in rawBookings) {
              final status = booking['status'] as String? ?? 'completed';
              if (status != 'completed' && status != 'accepted') {
                continue;
              }
              final priceStr = booking['price'] as String? ?? '₹0';
              final cleanStr = priceStr.replaceAll(RegExp(r'[^0-9.]'), '');
              final priceVal = double.tryParse(cleanStr) ?? 0.0;
              earnings += priceVal * 0.85; // 85% goes to driver, 15% is commission
              
              final vehicle = booking['vehicle'] as String? ?? 'Bike';
              
              int timestampMs = DateTime.now().millisecondsSinceEpoch;
              if (booking['scheduledDate'] != null) {
                try {
                  final dateStr = booking['scheduledDate'] as String;
                  final parsedDate = DateTime.parse(dateStr);
                  timestampMs = parsedDate.millisecondsSinceEpoch;
                } catch (_) {}
              } else if (booking['createdAt'] != null) {
                try {
                  timestampMs = DateTime.parse(booking['createdAt']).millisecondsSinceEpoch;
                } catch (_) {
                  if (booking['createdAt'] is int) {
                    timestampMs = booking['createdAt'];
                  }
                }
              }

              final serviceType = (vehicle == 'Bike')
                  ? 'bike'
                  : (vehicle == 'Auto'
                      ? 'auto'
                      : (vehicle == 'Car' ? 'car' : 'parcel'));
              
              rides.add({
                'date': _formatTimestamp(timestampMs),
                'price': priceStr,
                'icon': _getVehicleIcon(vehicle),
                'title': 'StayDriv $vehicle Ride',
                'route': '${booking['pickup'] ?? ''} to ${booking['drop'] ?? ''}',
                'pickup': booking['pickup'] ?? '',
                'drop': booking['drop'] ?? '',
                'scheduledDate': booking['scheduledDate'] ?? '',
                'scheduledTimeSlot': booking['scheduledTimeSlot'] ?? '',
                'passengerPhone': booking['passengerPhone'] ?? booking['pickupContactPhone'] ?? '',
                'passengerName': booking['passengerName'] ?? booking['pickupContactName'] ?? '',
                'timestamp': timestampMs,
                'vehicle': vehicle,
                'serviceType': serviceType,
                'status': status,
              });
            }
            
            // Sort by timestamp descending
            rides.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));
            
            if (mounted) {
              setState(() {
                _completedRides = rides;
                if (widget.userRole == 'Driver') {
                  _totalEarnings = earnings;
                }
              });
            }
          }
        }
      } catch (e) {
        debugPrint("Error loading completed rides from MongoDB: $e");
      }
      return;
    }
    
    try {
      final String roleField = widget.userRole == 'Driver' ? 'driverId' : 'passengerId';
      final snapshot = await FirebaseFirestore.instance
          .collection('rides')
          .where(roleField, isEqualTo: uid)
          .where('status', isEqualTo: 'completed')
          .get();
          
      List<Map<String, dynamic>> rides = [];
      double earnings = 0.0;
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final priceStr = data['price'] as String? ?? '₹0';
        final cleanStr = priceStr.replaceAll(RegExp(r'[^0-9.]'), '');
        final priceVal = double.tryParse(cleanStr) ?? 0.0;
        earnings += priceVal * 0.85; // 85% goes to driver, 15% is commission
        
        final vehicle = data['vehicle'] as String? ?? 'Bike';
        final timestamp = (data['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;
        
        final serviceType = (vehicle == 'Bike')
            ? 'bike'
            : (vehicle == 'Auto'
                ? 'auto'
                : (vehicle == 'Car' ? 'car' : 'parcel'));

        rides.add({
          'date': _formatTimestamp(timestamp),
          'price': priceStr,
          'icon': _getVehicleIcon(vehicle),
          'title': 'StayDriv $vehicle Ride',
          'route': '${data['pickup'] ?? ''} to ${data['drop'] ?? ''}',
          'timestamp': timestamp,
          'vehicle': vehicle,
          'serviceType': serviceType,
        });
      }
      
      // Sort by timestamp descending
      rides.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));
      
      if (mounted) {
        setState(() {
          _completedRides = rides;
          if (widget.userRole == 'Driver') {
            _totalEarnings = earnings;
          }
        });
      }
    } catch (e) {
      debugPrint("Error loading completed rides: $e");
    }
  }

  void _loadProfileData() async {
    final uid = FirebaseService().currentUid;
    if (uid == null) return;
    setState(() {
      _isLoadingProfile = true;
    });
    try {
      final role = widget.userRole == 'Driver' ? 'partner' : 'customer';
      final doc = await FirebaseService().getProfile(role, uid);
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null) {
          setState(() {
            _profilePhotoPath = data['photo'] ?? data['photoUrl'];
            _aadhaarFront = data['aadhaarFront'];
            _aadhaarBack = data['aadhaarBack'];
            _licenseFront = data['licenseFront'];
            _licenseBack = data['licenseBack'];
            _rcFront = data['rcFront'];
            _rcBack = data['rcBack'];
            _fitness = data['fitness'];
            _permit = data['permit'];
            if (data['salary'] != null) {
              _pilotSalary = (data['salary'] as num).toDouble();
            }
            if (data['pendingCancellationCharge'] != null) {
              _customerCancellationCharge = (data['pendingCancellationCharge'] as num).toDouble();
            }
            if (data['name'] != null && data['name'].toString().isNotEmpty) {
              _editableUserName = data['name'];
            }
            if (data['email'] != null && data['email'].toString().isNotEmpty) {
              _emailAddress = data['email'];
            }
            if (data['dob'] != null && data['dob'].toString().isNotEmpty) {
              _dateOfBirth = data['dob'];
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading profile: $e");
    } finally {
      setState(() {
        _isLoadingProfile = false;
      });
    }
  }

  Future<void> _updatePartnerProfileOnBackend({
    String? photo,
    String? aadhaarFront,
    String? aadhaarBack,
    String? licenseFront,
    String? licenseBack,
    String? rcFront,
    String? rcBack,
    String? fitness,
    String? permit,
    String? name,
  }) async {
    final uid = FirebaseService().currentUid;
    if (uid == null) return;

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final updateUrl = Uri.parse('$baseUrl/api/partner/update');
      
      final body = {
        'uid': uid,
        if (photo != null) 'photo': photo,
        if (aadhaarFront != null) 'aadhaarFront': aadhaarFront,
        if (aadhaarBack != null) 'aadhaarBack': aadhaarBack,
        if (licenseFront != null) 'licenseFront': licenseFront,
        if (licenseBack != null) 'licenseBack': licenseBack,
        if (rcFront != null) 'rcFront': rcFront,
        if (rcBack != null) 'rcBack': rcBack,
        if (fitness != null) 'fitness': fitness,
        if (permit != null) 'permit': permit,
        if (name != null) 'name': name,
      };

      final response = await ApiClient().post(
        updateUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      debugPrint("Partner profile update response: ${response.statusCode} - ${response.body}");
    } catch (e) {
      debugPrint("Error updating partner profile on backend: $e");
    }

    if (_isFirebaseInitialized) {
      try {
        final Map<String, dynamic> firestoreUpdates = {
          if (photo != null) 'photo': photo,
          if (aadhaarFront != null) 'aadhaarFront': aadhaarFront,
          if (aadhaarBack != null) 'aadhaarBack': aadhaarBack,
          if (licenseFront != null) 'licenseFront': licenseFront,
          if (licenseBack != null) 'licenseBack': licenseBack,
          if (rcFront != null) 'rcFront': rcFront,
          if (rcBack != null) 'rcBack': rcBack,
          if (fitness != null) 'fitness': fitness,
          if (permit != null) 'permit': permit,
          if (name != null) 'name': name,
        };
        if (firestoreUpdates.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('partners')
              .doc(uid)
              .set(firestoreUpdates, SetOptions(merge: true));
        }
      } catch (e) {
        debugPrint("Error syncing profile updates to Firestore: $e");
      }
    }
  }

  Future<void> _pickAndUploadImage(String type) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg'],
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.first;
      
      final ext = (file.extension ?? '').toLowerCase();
      if (ext != 'jpg' && ext != 'jpeg') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid file type! Only .jpeg and .jpg formats are accepted.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      List<int> bytes;
      if (kIsWeb) {
        if (file.bytes == null) return;
        bytes = file.bytes!;
      } else {
        if (file.path == null) return;
        bytes = await io.File(file.path!).readAsBytes();
      }

      final sizeKb = bytes.length / 1024;
      final sizeStr = '${sizeKb.toStringAsFixed(2)} KB';
      final fileName = file.name;

      bool? confirmUpload = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('Confirm Upload', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('File Name: $fileName', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                Text('File Size: $sizeStr', style: GoogleFonts.inter(color: AppTheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                Container(
                  height: 180,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.outlineVariant),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      Uint8List.fromList(bytes),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Upload'),
              ),
            ],
          );
        },
      );

      if (confirmUpload != true) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Uploading document to server...', style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      );

      final uid = FirebaseService().currentUid ?? 'pilot_user';
      final docUrl = await FirebaseService().uploadProfilePictureToMongo(uid, bytes, ext);
      
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (type == 'photo') {
        await _updatePartnerProfileOnBackend(photo: docUrl);
        setState(() {
          _profilePhotoPath = docUrl;
          _photoName = fileName;
          _photoSize = sizeStr;
        });
      } else if (type == 'aadhaarFront') {
        await _updatePartnerProfileOnBackend(aadhaarFront: docUrl);
        setState(() {
          _aadhaarFront = docUrl;
          _aadhaarFrontName = fileName;
          _aadhaarFrontSize = sizeStr;
        });
      } else if (type == 'aadhaarBack') {
        await _updatePartnerProfileOnBackend(aadhaarBack: docUrl);
        setState(() {
          _aadhaarBack = docUrl;
          _aadhaarBackName = fileName;
          _aadhaarBackSize = sizeStr;
        });
      } else if (type == 'licenseFront') {
        await _updatePartnerProfileOnBackend(licenseFront: docUrl);
        setState(() {
          _licenseFront = docUrl;
          _licenseFrontName = fileName;
          _licenseFrontSize = sizeStr;
        });
      } else if (type == 'licenseBack') {
        await _updatePartnerProfileOnBackend(licenseBack: docUrl);
        setState(() {
          _licenseBack = docUrl;
          _licenseBackName = fileName;
          _licenseBackSize = sizeStr;
        });
      } else if (type == 'rcFront') {
        await _updatePartnerProfileOnBackend(rcFront: docUrl);
        setState(() {
          _rcFront = docUrl;
          _rcFrontName = fileName;
          _rcFrontSize = sizeStr;
        });
      } else if (type == 'rcBack') {
        await _updatePartnerProfileOnBackend(rcBack: docUrl);
        setState(() {
          _rcBack = docUrl;
          _rcBackName = fileName;
          _rcBackSize = sizeStr;
        });
      } else if (type == 'fitness') {
        await _updatePartnerProfileOnBackend(fitness: docUrl);
        setState(() {
          _fitness = docUrl;
          _fitnessName = fileName;
          _fitnessSize = sizeStr;
        });
      } else if (type == 'permit') {
        await _updatePartnerProfileOnBackend(permit: docUrl);
        setState(() {
          _permit = docUrl;
          _permitName = fileName;
          _permitSize = sizeStr;
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully uploaded $fileName!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _adminMongoPollTimer?.cancel();
    _bookingTimer?.cancel();
    _otpTextController.dispose();
    _gpsSub?.cancel();
    _bookingSub?.cancel();
    _driverLocationSub?.cancel();
    _rideStatusSub?.cancel();
    _networkSub?.cancel();
    _successBannerTimer?.cancel();
    _customerFeedbackController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("HomeScreen: App resumed! Force syncing partner status & restoring active booking immediately.");
      BookingManager().forceSync();
      if (widget.userRole == 'Customer') {
        BookingManager().restoreAndSyncActiveBooking();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // We use an IndexedStack to manage the top-level app tabs.
    // Index 0: Main Home Dashboard View
    // Index 1: Activity View
    // Index 2: Profile View (Mock)
    // Index 3: Help View (Mock)
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _currentTabIndex,
            children: [
              _buildDashboardView(),
              ActivityScreen(
            userRole: widget.userRole,
            totalEarnings: _totalEarnings,
            completedRides: _completedRides,
            isAdvanceWithdrawn: _isAdvanceWithdrawn,
            onWithdrawAdvance: () {
              setState(() {
                _totalEarnings -= 200.0;
                _isAdvanceWithdrawn = true;
              });
            },
            onGoToHome: () {
              setState(() {
                _currentTabIndex = 0;
              });
            },
            onWithdrawMoney: (amount) {
              setState(() {
                _totalEarnings -= amount;
              });
            },
          ),
          _buildProfileView(),
          _buildHelpView(),
        ],
      ),
      _buildNetworkStatusBanner(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor.withOpacity(0.8),
          border: const Border(
            top: BorderSide(color: Color(0x1FC3C6D7), width: 1),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.home_rounded, 'Home'),
                _buildNavItem(1, Icons.explore_rounded, 'Activity'),
                _buildNavItem(2, Icons.person_rounded, 'Profile'),
                _buildNavItem(3, Icons.help_outline_rounded, 'Help'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNetworkStatusBanner() {
    if (_networkStatus == NetworkStatus.disconnected) {
      return Container(
        width: double.infinity,
        color: AppTheme.errorColor,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(
              'No Internet Connection',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    } else if (_showSuccessBanner) {
      return Container(
        width: double.infinity,
        color: Colors.green,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(
              'Connection Restored',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isActive = _currentTabIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentTabIndex = index;
        });
        if (index == 1) {
          _loadCompletedRides();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primaryAccent.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? AppTheme.primaryColor : AppTheme.onSurfaceVariant,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.robotoMono(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? AppTheme.primaryColor : AppTheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardView() {
    if (widget.userRole == 'Driver') {
      return _buildDriverDashboardView();
    } else if (widget.userRole == 'Admin') {
      return _buildAdminDashboardView();
    }
     return Stack(
      children: [
        Column(
          children: [
            // Top App Bar
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Avatar Profile Leading
                    GestureDetector(
                      onTap: () => setState(() => _currentTabIndex = 2),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.5)),
                          color: AppTheme.surfaceContainerHigh,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: const Icon(Icons.person, color: AppTheme.primaryColor),
                        ),
                      ),
                    ),
                    
                    // Logo Headline
                    Text(
                      'StayDriv',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryColor,
                        letterSpacing: -0.5,
                      ),
                    ),
                    
                    // Notifications Trailing
                    Stack(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.notifications_none_rounded, color: AppTheme.onSurfaceColor),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('No new notifications')),
                            );
                          },
                        ),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppTheme.errorColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Scrollable Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    // Services Grid Title
                    Text(
                      'What do you need today?',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.onSurfaceColor,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Bento Grid
                    Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildBentoItem(
                                icon: Icons.two_wheeler_rounded,
                                imageAsset: 'assets/images/bike.png',
                                title: 'Bike Taxi',
                                desc: 'Quick commutes',
                                serviceType: 'bike',
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildBentoItem(
                                icon: Icons.electric_rickshaw_rounded,
                                imageAsset: 'assets/images/auto.png',
                                title: 'Auto',
                                desc: 'Fast & local',
                                badge: 'FAST',
                                serviceType: 'auto',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildBentoItem(
                                icon: Icons.directions_car_rounded,
                                imageAsset: 'assets/images/car.png',
                                title: 'Car',
                                desc: 'Comfortable rides',
                                serviceType: 'car',
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildBentoItem(
                                icon: Icons.airport_shuttle_rounded,
                                imageAsset: 'assets/images/parcel.png',
                                title: 'Parcel',
                                desc: 'Parcel & logistics',
                                serviceType: 'parcel',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildBentoItem(
                          icon: Icons.local_shipping_rounded,
                          imageAsset: 'assets/images/heavy_truck.png',
                          title: 'Heavy Truck',
                          desc: 'Heavy cargo, 6 to 35 Ton transport',
                          serviceType: 'heavy_truck',
                          isFullWidth: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    _buildMapPreview(),
                    const SizedBox(height: 28),
                    // Offers & Promotions
                    Text(
                      'Offers & Promotions',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.onSurfaceColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 130,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _buildPromoCard(
                            category: 'LIMITED TIME',
                            title: '20% off first cab ride',
                            code: 'STAY20',
                            bgColor: AppTheme.surfaceContainer,
                            textColor: AppTheme.onSurfaceColor,
                            accentColor: AppTheme.primaryColor,
                          ),
                          const SizedBox(width: 16),
                          _buildPromoCard(
                            category: 'CUSTOMER PASS',
                            title: 'Unlock flat fares for routes',
                            code: 'VIEW PASSES',
                            bgColor: AppTheme.primaryColor,
                            textColor: Colors.white,
                            accentColor: AppTheme.safetyYellow,
                            isPrimaryBg: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_activeBooking != null &&
            (_activeBooking!['status'] == 'searching' ||
                _activeBooking!['status'] == 'accepted' ||
                _activeBooking!['status'] == 'arrived' ||
                _activeBooking!['status'] == 'started'))
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _buildActiveRideBanner(),
          ),
      ],
    );
  }

  Widget _buildBentoItem({
    required IconData icon,
    String? imageAsset,
    required String title,
    required String desc,
    String? badge,
    required String serviceType,
    bool isFullWidth = false,
  }) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RideSelectionScreen(
              serviceType: serviceType,
              userName: _editableUserName,
              phoneNumber: widget.phoneNumber,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.3), width: 1),
        ),
        padding: const EdgeInsets.all(12),
        child: isFullWidth
            ? Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: imageAsset != null
                        ? Padding(
                            padding: const EdgeInsets.all(3.0),
                            child: Image.asset(
                              imageAsset,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Icon(icon, color: AppTheme.primaryColor, size: 22),
                            ),
                          )
                        : Icon(icon, color: AppTheme.primaryColor, size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.onSurfaceColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          desc,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppTheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppTheme.primaryColor, size: 20),
                ],
              )
            : Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: imageAsset != null
                            ? Padding(
                                padding: const EdgeInsets.all(3.0),
                                child: Image.asset(
                                  imageAsset,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => Icon(icon, color: AppTheme.primaryColor, size: 24),
                                ),
                              )
                            : Icon(icon, color: AppTheme.primaryColor, size: 20),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.onSurfaceColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            desc,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppTheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (badge != null)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.safetyYellow,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.bolt, color: AppTheme.safetyYellowText, size: 10),
                            const SizedBox(width: 2),
                            Text(
                              badge,
                              style: GoogleFonts.robotoMono(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.safetyYellowText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildMapPreview() {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.5), width: 1),
      ),
      child: Stack(
        children: [
          // Google Map preview showing drivers nearby
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _center,
                  zoom: 14.0,
                ),
                markers: _markers,
                onMapCreated: (controller) {
                  _customerMapController = controller;
                },
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
              ),
            ),
          ),
          // Floating overlay: active count
          Positioned(
            bottom: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(color: Color(0x1F2563EB), blurRadius: 12, offset: Offset(0, 4)),
                ],
                border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppTheme.primaryColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '8 Drivers Nearby',
                    style: GoogleFonts.robotoMono(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.onSurfaceColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Floating overlay: GPS button
          Positioned(
            bottom: 12,
            right: 12,
            child: GestureDetector(
              onTap: _startCustomerGpsTracking,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(color: Color(0x1F2563EB), blurRadius: 12, offset: Offset(0, 4)),
                  ],
                  border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.3)),
                ),
                child: const Icon(Icons.my_location, size: 18, color: AppTheme.onSurfaceColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromoCard({
    required String category,
    required String title,
    required String code,
    required Color bgColor,
    required Color textColor,
    required Color accentColor,
    bool isPrimaryBg = false,
  }) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                category,
                style: GoogleFonts.robotoMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isPrimaryBg ? Colors.white.withOpacity(0.8) : accentColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                code,
                style: GoogleFonts.robotoMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isPrimaryBg ? Colors.white : AppTheme.onSurfaceVariant,
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: isPrimaryBg ? Colors.white : accentColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _changeProfilePhoto() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.upload_file, color: AppTheme.primaryColor),
                title: const Text('Upload JPG/JPEG Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadImage('photo');
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Upload Mock Photo 1 (Professional)'),
                onTap: () {
                  setState(() {
                    _profilePhotoPath = 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150';
                  });
                  _updatePartnerProfileOnBackend(photo: _profilePhotoPath);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Upload Mock Photo 2 (Casual)'),
                onTap: () {
                  setState(() {
                    _profilePhotoPath = 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150';
                  });
                  _updatePartnerProfileOnBackend(photo: _profilePhotoPath);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Remove Photo', style: const TextStyle(color: Colors.red)),
                onTap: () {
                  setState(() {
                    _profilePhotoPath = null;
                  });
                  _updatePartnerProfileOnBackend(photo: '');
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditProfileDialog() {
    final nameController = TextEditingController(text: _editableUserName);
    final emailController = TextEditingController(text: _emailAddress == 'Not Provided' ? '' : _emailAddress);
    final dobController = TextEditingController(text: _dateOfBirth == 'Not Provided' ? '' : _dateOfBirth);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit Profile Details', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Full Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(labelText: 'Email Address'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dobController,
                  decoration: const InputDecoration(labelText: 'Date of Birth (DD/MM/YYYY)', hintText: 'DD/MM/YYYY'),
                  keyboardType: TextInputType.datetime,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _editableUserName = nameController.text.trim().isNotEmpty ? nameController.text.trim() : _editableUserName;
                  _emailAddress = emailController.text.trim().isNotEmpty ? emailController.text.trim() : 'Not Provided';
                  _dateOfBirth = dobController.text.trim().isNotEmpty ? dobController.text.trim() : 'Not Provided';
                });
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProfileView() {
    return Scaffold(
      appBar: AppBar(
        title: Text('My Profile', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: AppTheme.primaryColor),
            onPressed: _showNetworkSettingsDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Stack(
              children: [
                GestureDetector(
                  onTap: _changeProfilePhoto,
                  child: CircleAvatar(
                    radius: 55,
                    backgroundColor: AppTheme.primaryAccent,
                    backgroundImage: _profilePhotoPath != null ? NetworkImage(_profilePhotoPath!) : null,
                    child: _profilePhotoPath == null ? const Icon(Icons.person, size: 65, color: Colors.white) : null,
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _changeProfilePhoto,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _editableUserName,
              style: GoogleFonts.hankenGrotesk(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            Text(
              widget.userRole == 'Driver' ? 'Pilot' : 'Customer',
              style: GoogleFonts.robotoMono(color: AppTheme.primaryColor, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Personal Information',
                  style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
                ),
                TextButton.icon(
                  onPressed: _showEditProfileDialog,
                  icon: const Icon(Icons.edit, size: 14),
                  label: Text('Edit', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildProfileTile(Icons.person_outline, 'Full Name', _editableUserName),
            _buildProfileTile(Icons.phone, 'Mobile Number', '+91 ${widget.phoneNumber}'),
            _buildProfileTile(Icons.email, 'Email Address', _emailAddress),
            _buildProfileTile(Icons.calendar_today, 'Date of Birth', _dateOfBirth),
            if (widget.userRole == 'Driver') ...[
              const Divider(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Verification Documents',
                    style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_isLoadingProfile)
                const Center(child: CircularProgressIndicator())
              else ...[
                _buildDocUploadTile('Aadhaar Card - Front', _aadhaarFront, 'aadhaarFront', _aadhaarFrontName, _aadhaarFrontSize),
                _buildDocUploadTile('Aadhaar Card - Back', _aadhaarBack, 'aadhaarBack', _aadhaarBackName, _aadhaarBackSize),
                _buildDocUploadTile('Driving License - Front', _licenseFront, 'licenseFront', _licenseFrontName, _licenseFrontSize),
                _buildDocUploadTile('Driving License - Back', _licenseBack, 'licenseBack', _licenseBackName, _licenseBackSize),
                _buildDocUploadTile('Vehicle RC - Front', _rcFront, 'rcFront', _rcFrontName, _rcFrontSize),
                _buildDocUploadTile('Vehicle RC - Back', _rcBack, 'rcBack', _rcBackName, _rcBackSize),
                if (_selectedVehicle == 'Car' || _selectedVehicle == 'Mini Truck' || _selectedVehicle == 'Heavy Truck') ...[
                  _buildDocUploadTile('Fitness Certificate', _fitness, 'fitness', _fitnessName, _fitnessSize),
                  _buildDocUploadTile('Vehicle Permit', _permit, 'permit', _permitName, _permitSize),
                ],
              ],
            ],
            const Divider(height: 32),
            if (widget.userRole == 'Driver')
              _buildProfileTile(Icons.account_balance_wallet, 'Pilot Salary Balance', '₹${_pilotSalary.toStringAsFixed(2)}')
            else
              _buildProfileTile(
                Icons.account_balance_wallet, 
                'Payment Wallet', 
                _customerCancellationCharge > 0 
                    ? 'UPI linked | Prev Penalty: ₹${_customerCancellationCharge.toStringAsFixed(0)}' 
                    : 'UPI linked'
              ),
            _buildProfileTile(Icons.settings, 'Settings', 'Preferences & Notifications'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => LoginScreen()),
                  (route) => false,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.errorColor,
                minimumSize: const Size(120, 45),
              ),
              child: const Text('Logout', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileTile(IconData icon, String title, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppTheme.primaryColor),
        title: Text(title, style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: GoogleFonts.inter()),
        trailing: const Icon(Icons.chevron_right, color: AppTheme.outlineColor),
      ),
    );
  }

  Widget _buildDocUploadTile(String label, String? url, String type, String? fileName, String? fileSize) {
    final hasUploaded = url != null && url.isNotEmpty;
    
    String displayFileName = fileName ?? '';
    if (displayFileName.isEmpty && hasUploaded) {
      displayFileName = url.split('/').last;
      displayFileName = displayFileName.split('?').first;
    }
    String displayFileSize = fileSize ?? '';
    if (displayFileSize.isEmpty && hasUploaded) {
      displayFileSize = 'JPEG Image';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasUploaded ? Colors.green.withOpacity(0.3) : AppTheme.outlineVariant.withOpacity(0.3),
        ),
      ),
      child: ListTile(
        leading: Icon(
          hasUploaded ? Icons.check_circle : Icons.upload_file_rounded,
          color: hasUploaded ? Colors.green : AppTheme.primaryColor,
        ),
        title: Text(label, style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
        subtitle: hasUploaded
            ? Text('$displayFileName ($displayFileSize)', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.onSurfaceVariant))
            : Text('Upload JPG/JPEG document', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.onSurfaceVariant)),
        trailing: hasUploaded
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.visibility, color: AppTheme.primaryColor),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            title: Text(label, style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold)),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (displayFileName.isNotEmpty)
                                  Text(displayFileName, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                                if (displayFileSize.isNotEmpty)
                                  Text(displayFileSize, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.onSurfaceVariant)),
                                const SizedBox(height: 12),
                                Container(
                                  height: 240,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppTheme.outlineVariant),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(
                                      url,
                                      fit: BoxFit.contain,
                                      loadingBuilder: (context, child, loadingProgress) {
                                        if (loadingProgress == null) return child;
                                        return const Center(child: CircularProgressIndicator());
                                      },
                                      errorBuilder: (context, error, stackTrace) {
                                        return const Center(
                                          child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close'),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.sync_rounded, color: AppTheme.onSurfaceVariant),
                    onPressed: () => _pickAndUploadImage(type),
                  ),
                ],
              )
            : ElevatedButton(
                onPressed: () => _pickAndUploadImage(type),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Upload', style: TextStyle(fontSize: 12)),
              ),
      ),
    );
  }

  Widget _buildHelpView() {
    return Scaffold(
      appBar: AppBar(
        title: Text('StayDriv Support', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How can we help you?',
              style: GoogleFonts.hankenGrotesk(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView(
                children: [
                  _buildHelpTile('Booking issue', 'Problems making a ride request'),
                  _buildHelpTile('Payment and refund', 'Questions about wallet or transaction fails'),
                  _buildHelpTile('Safety concerns', 'Emergency report & support protocols'),
                  _buildHelpTile('Driver complaints', 'Feedback on ride quality or drivers'),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.headset_mic, color: AppTheme.primaryColor, size: 28),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Call emergency helpline', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold)),
                        Text('24/7 dedicated support desk', style: GoogleFonts.inter(fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.call, color: AppTheme.primaryColor),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpTile(String title, String desc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.3)),
      ),
      child: ListTile(
        title: Text(title, style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
        subtitle: Text(desc, style: GoogleFonts.inter(fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.outlineColor),
        onTap: () {},
      ),
    );
  }

  // ==========================================
  // DRIVER PARTNER CONSOLE AND STATE METHODS
  // ==========================================

  void _toggleDuty(bool value) {
    setState(() {
      _isOnline = value;
      _driverStatus = value ? 'online' : 'offline';
    });

    _bookingTimer?.cancel();
    if (value) {
      BookingManager().setDriverOnline(true);
      BookingManager().setDriverVehicle(_selectedVehicle);
      _startGpsTracking();
      _subscribeToBookingManager();
    } else {
      _stopRinging();
      BookingManager().setDriverOnline(false);
      _gpsSub?.cancel();
      _bookingSub?.cancel();
      _driverLocationSub?.cancel();
      _rideStatusSub?.cancel();
      _activeBooking = null;
      _countdownTimer?.cancel();
      BookingManager().stopSimulatedMovement();
    }
  }

  void _startRinging() {
    try {
      if (kIsWeb) {
        js.context.callMethod('startStayDrivRinging');
      } else {
        FlutterRingtonePlayer().playRingtone();
      }
    } catch (e) {
      debugPrint('Error starting ring: $e');
    }
  }

  void _stopRinging() {
    _countdownTimer?.cancel();
    try {
      if (kIsWeb) {
        js.context.callMethod('stopStayDrivRinging');
      } else {
        FlutterRingtonePlayer().stop();
      }
    } catch (e) {
      debugPrint('Error stopping ring: $e');
    }
  }

  void _startGpsTracking() async {
    _gpsSub?.cancel();
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        final latLng = LatLng(pos.latitude, pos.longitude);
        BookingManager().updateDriverLocation(latLng);
        setState(() {
          _driverMapCenter = latLng;
        });
      }
    } catch (e) {
      debugPrint('Error getting initial GPS position: $e');
    }

    try {
      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((Position pos) {
        if (_isOnline) {
          final latLng = LatLng(pos.latitude, pos.longitude);
          BookingManager().updateDriverLocation(latLng);
        }
      }, onError: (e) {
        debugPrint('GPS stream error: $e');
      });
    } catch (e) {
      debugPrint('Error listening to GPS stream: $e');
    }
  }

  bool _isNearAndMatching(Map<String, dynamic>? active) {
    if (active == null) return false;
    
    // Check if the booking has been accepted by another driver
    final driverId = active['driverId'] as String?;
    final myUid = FirebaseService().currentUid;
    final status = active['status'] as String? ?? 'searching';
    if (status != 'searching' && status != 'incoming') {
      if (driverId != myUid) {
        debugPrint('StayDriv Match Failed: Booking is in status $status and belongs to driver $driverId (my UID: $myUid)');
        return false;
      }
    }
    
    // Link with both: Check if vehicle matches AND driver is near pickup
    final vehicle = active['vehicle'] as String?;
    if (vehicle != null && _selectedVehicle != null) {
      final v1 = vehicle.toLowerCase().replaceAll(' ', '');
      final v2 = _selectedVehicle.toLowerCase().replaceAll(' ', '');
      bool matches = (v1 == v2);
      if (!matches) {
        if (v1.contains('truck') && v2.contains('truck')) {
          final isV1Heavy = v1.contains('heavytruck') || v1.contains('tontruck');
          final isV2Heavy = v2.contains('heavytruck') || v2.contains('tontruck');
          if (isV1Heavy == isV2Heavy) {
            matches = true;
          }
        }
        else if (v1.contains('bike') && v2.contains('bike')) matches = true;
        else if ((v1.contains('car') || v1.contains('cab')) && (v2.contains('car') || v2.contains('cab'))) matches = true;
        else if (v1.contains('auto') && v2.contains('auto')) matches = true;
      }
      if (!matches) {
        debugPrint('StayDriv Match Failed: Vehicle mismatch (Customer wants $vehicle, Driver is $_selectedVehicle)');
        return false;
      }
    }

    // Bypass distance check for Heavy Truck matching (can match anywhere in India)
    final bool isHeavyTruck = active['serviceType'] == 'heavy_truck' ||
        (active['title'] as String? ?? '').toLowerCase().contains('heavy truck') ||
        (active['vehicle'] as String? ?? '').toLowerCase().contains('heavy truck');
    if (isHeavyTruck) {
      debugPrint('StayDriv Match Success: Driver is matching Heavy Truck anywhere in India!');
      return true;
    }

    // Bypass distance check for local MongoDB/Mock mode
    if (!_isFirebaseInitialized) {
      debugPrint('StayDriv Match Success: Driver is near and matching (Bypassed distance check in Mock/MongoDB mode)!');
      return true;
    }

    final pickup = active['pickupLatLng'] as LatLng?;
    if (pickup != null && _driverMapCenter != null) {
      final distance = Geolocator.distanceBetween(
        _driverMapCenter!.latitude,
        _driverMapCenter!.longitude,
        pickup.latitude,
        pickup.longitude,
      );
      // Increased to 20,000 km radius to ensure emulator-to-real-device matching works across coordinates
      if (distance > 20000000) {
        debugPrint('StayDriv Match Failed: Distance too far ($distance meters)');
        return false;
      }
    }
    
    debugPrint('StayDriv Match Success: Driver is near and matching!');
    return true;
  }


  void _handleBookingUpdate(Map<String, dynamic>? active) {
    if (active == null) {
      _stopRinging();
      setState(() {
        _activeBooking = null;
        _driverStatus = _isOnline ? 'online' : 'offline';
        _driverRoutePoints = [];
      });
      return;
    }

    final status = active['status'] as String? ?? 'searching';

    // Prioritize cancellation notification so pilot always receives the popup when customer cancels
    if (status == 'cancelled') {
      _stopRinging();
      final cancelledBy = active['cancelledBy'] as String?;
      if (cancelledBy == 'customer' || cancelledBy == null) {
        _showCustomerCancelledNotificationToPilot(active);
      } else {
        setState(() {
          _activeBooking = null;
          _driverStatus = _isOnline ? 'online' : 'offline';
          _driverRoutePoints = [];
        });
      }
      return;
    }

    if (_isNearAndMatching(active)) {
      // Heavy Truck pilots should NOT see any ride progress screen (keep them online/idle)
      final bool isHeavyTruck = active['serviceType'] == 'heavy_truck' ||
          (active['title'] as String? ?? '').toLowerCase().contains('heavy truck') ||
          (active['vehicle'] as String? ?? '').toLowerCase().contains('heavy truck');

      if (isHeavyTruck && status != 'searching' && status != 'incoming') {
        _stopRinging();
        setState(() {
          _activeBooking = null;
          _driverStatus = _isOnline ? 'online' : 'offline';
          _driverRoutePoints = [];
        });
        return;
      }

      final prevStatus = _driverStatus;
      
      final normalizedActive = Map<String, dynamic>.from(active);
      if (normalizedActive['pickupLatLng'] != null && normalizedActive['pickupLatLng'] is! LatLng) {
        final map = normalizedActive['pickupLatLng'] as Map;
        normalizedActive['pickupLatLng'] = LatLng((map['lat'] as num).toDouble(), (map['lng'] as num).toDouble());
      }
      if (normalizedActive['dropLatLng'] != null && normalizedActive['dropLatLng'] is! LatLng) {
        final map = normalizedActive['dropLatLng'] as Map;
        normalizedActive['dropLatLng'] = LatLng((map['lat'] as num).toDouble(), (map['lng'] as num).toDouble());
      }

      setState(() {
        _activeBooking = normalizedActive;
        
        if (status == 'searching' || status == 'incoming') {
          _driverStatus = 'incoming_request';
        } else if (status == 'accepted') {
          _driverStatus = 'heading_to_pickup';
        } else if (status == 'arrived') {
          _driverStatus = 'arrived_pickup';
        } else if (status == 'started') {
          _driverStatus = 'on_trip';
        } else if (status == 'completed') {
          _driverStatus = 'payment_pending';
        }
      });
      
      if (_driverStatus == 'incoming_request' && prevStatus != 'incoming_request') {
        _startRinging();
        _incomingRequestCountdown = 10;
        _countdownTimer?.cancel();
        _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          if (_incomingRequestCountdown > 0) {
            setState(() {
              _incomingRequestCountdown--;
            });
          } else {
            timer.cancel();
          }
        });
      } else if (prevStatus == 'incoming_request' && _driverStatus != 'incoming_request') {
        _stopRinging();
      }
    } else {
      _stopRinging();
      setState(() {
        _activeBooking = null;
        _driverStatus = _isOnline ? 'online' : 'offline';
      });
    }
  }

  void _subscribeToCustomerBookingManager() {
    _bookingSub?.cancel();
    _rideStatusSub?.cancel();
    _driverLocationSub?.cancel();

    _bookingSub = BookingManager().bookingStream.listen((Map<String, dynamic>? active) {
      if (mounted) {
        _handleCustomerBookingUpdate(active);
      }
    });

    _rideStatusSub = BookingManager().rideStatusStream.listen((String status) {
      if (mounted) {
        final active = BookingManager().activeBooking;
        _handleCustomerBookingUpdate(active);
      }
    });

    _driverLocationSub = BookingManager().driverLocationStream.listen((LatLng pos) {
      if (mounted) {
        setState(() {
          _markers = _markers.map((m) {
            if (m.markerId.value == 'driver') {
              return m.copyWith(positionParam: pos);
            }
            return m;
          }).toSet();
        });
      }
    });

    final initialActive = BookingManager().activeBooking;
    if (initialActive != null) {
      _handleCustomerBookingUpdate(initialActive);
    }
  }

  void _handleCustomerBookingUpdate(Map<String, dynamic>? active) {
    if (active == null) {
      setState(() {
        _activeBooking = null;
      });
      return;
    }

    final normalizedActive = Map<String, dynamic>.from(active);
    if (normalizedActive['pickupLatLng'] != null && normalizedActive['pickupLatLng'] is! LatLng) {
      final map = normalizedActive['pickupLatLng'] as Map;
      normalizedActive['pickupLatLng'] = LatLng((map['lat'] as num).toDouble(), (map['lng'] as num).toDouble());
    }
    if (normalizedActive['dropLatLng'] != null && normalizedActive['dropLatLng'] is! LatLng) {
      final map = normalizedActive['dropLatLng'] as Map;
      normalizedActive['dropLatLng'] = LatLng((map['lat'] as num).toDouble(), (map['lng'] as num).toDouble());
    }

    setState(() {
      _activeBooking = normalizedActive;
    });

    final status = normalizedActive['status'] as String? ?? 'searching';
    final cancelledBy = normalizedActive['cancelledBy'] as String?;

    if (status == 'cancelled' && (cancelledBy == 'pilot' || cancelledBy == 'driver')) {
      _showPilotCancelledNotificationToCustomer(normalizedActive);
      return;
    }

    if (status == 'completed') {
      _showCustomerRatingSheet(normalizedActive);
    }
  }

  bool _isPilotCancelledShowing = false;

  void _showPilotCancelledNotificationToCustomer(Map<String, dynamic> booking) {
    if (_isPilotCancelledShowing) return;
    _isPilotCancelledShowing = true;

    final reason = booking['cancelReason'] as String? ?? booking['reason'] as String? ?? 'Pilot was unable to fulfill request';

    try {
      FlutterRingtonePlayer().play(
        android: AndroidSounds.notification,
        ios: IosSounds.glass,
        looping: false,
        volume: 1.0,
      );
      HapticFeedback.vibrate();
    } catch (e) {
      debugPrint("Ringtone/Haptic error on pilot cancellation: $e");
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🔔 RIDE CANCELLED BY PILOT: $reason'),
        backgroundColor: AppTheme.errorColor,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
      ),
    );
    
    setState(() {
      _activeBooking = null;
    });
    BookingManager().clearBooking();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.cancel, color: AppTheme.errorColor, size: 28),
            SizedBox(width: 10),
            Expanded(child: Text('Pilot Cancelled Ride', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
          ],
        ),
        content: Text(
          'Your pilot has cancelled this ride request.\n\nReason: "$reason"\n\nYou can request another ride anytime.',
          style: const TextStyle(fontSize: 15, color: Colors.black87),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _isPilotCancelledShowing = false;
            },
            child: const Text('OK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  bool _isCustomerCancelledShowing = false;

  void _showCustomerCancelledNotificationToPilot(Map<String, dynamic> booking) {
    if (_isCustomerCancelledShowing) return;
    _isCustomerCancelledShowing = true;

    final reason = booking['cancelReason'] as String? ?? booking['reason'] as String? ?? 'Customer cancelled the ride request';

    try {
      FlutterRingtonePlayer().play(
        android: AndroidSounds.notification,
        ios: IosSounds.glass,
        looping: false,
        volume: 1.0,
      );
      HapticFeedback.vibrate();
    } catch (e) {
      debugPrint("Ringtone/Haptic error on customer cancellation: $e");
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🔔 RIDE CANCELLED BY CUSTOMER: $reason'),
        backgroundColor: AppTheme.errorColor,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
      ),
    );
    
    setState(() {
      _activeBooking = null;
      _driverStatus = _isOnline ? 'online' : 'offline';
      _driverRoutePoints = [];
    });
    BookingManager().clearBooking();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.cancel, color: AppTheme.errorColor, size: 28),
            SizedBox(width: 10),
            Expanded(child: Text('Customer Cancelled Ride', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
          ],
        ),
        content: Text(
          'The customer has cancelled this ride request.\n\nReason: "$reason"\n\nYou are online and ready for new ride requests.',
          style: const TextStyle(fontSize: 15, color: Colors.black87),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _isCustomerCancelledShowing = false;
            },
            child: const Text('OK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showCustomerRatingSheet(Map<String, dynamic> booking) {
    if (_isRatingSheetShowing) return;
    _isRatingSheetShowing = true;

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final driverName = booking['driverName'] as String? ?? 'StayDriv Partner';
            final price = booking['price'] as String? ?? '₹0';
            final waitingCharge = booking['waitingCharge'] as int? ?? 0;
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.outlineVariant.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check, color: Colors.white, size: 36),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Ride Completed!',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.onSurfaceColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    waitingCharge > 0
                        ? 'You have arrived safely. Fare charged: $price (includes ₹$waitingCharge Waiting Charge)'
                        : 'You have arrived safely. Fare charged: $price',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppTheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const Divider(height: 32),
                  Text(
                    'Rate $driverName',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.onSurfaceColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final starVal = index + 1;
                      final isFilled = _customerRating >= starVal;
                      return IconButton(
                        icon: Icon(
                          isFilled ? Icons.star_rounded : Icons.star_border_rounded,
                          color: AppTheme.safetyYellow,
                          size: 36,
                        ),
                        onPressed: () {
                          setSheetState(() {
                            _customerRating = starVal.toDouble();
                          });
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _customerFeedbackController,
                    decoration: const InputDecoration(
                      labelText: 'ADD MORE FEEDBACK',
                      hintText: 'Great drive, very helpful!',
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        BookingManager().clearBooking();
                        _customerFeedbackController.clear();
                        _isRatingSheetShowing = false;
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Feedback submitted! Thank you for riding with StayDriv.'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                      ),
                      child: Text(
                        'Submit Feedback',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).then((_) {
      _isRatingSheetShowing = false;
    });
  }

  Widget _buildActiveRideBanner() {
    if (_activeBooking == null) return const SizedBox.shrink();
    final status = _activeBooking!['status'] as String? ?? 'searching';
    final vehicle = _activeBooking!['vehicle'] as String? ?? 'Ride';
    final price = _activeBooking!['price'] as String? ?? '₹0';
    
    String statusText = 'Searching for Pilot...';
    IconData statusIcon = Icons.search;
    Color statusColor = AppTheme.primaryColor;

    if (status == 'accepted') {
      statusText = 'Pilot is coming to pickup';
      statusIcon = Icons.directions_bike;
      statusColor = Colors.orange;
    } else if (status == 'arrived') {
      statusText = 'Pilot has arrived!';
      statusIcon = Icons.pin_drop;
      statusColor = Colors.green;
    } else if (status == 'started') {
      statusText = 'On the way to destination';
      statusIcon = Icons.navigation;
      statusColor = AppTheme.primaryColor;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(statusIcon, color: statusColor, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Active StayDriv $vehicle',
                  style: GoogleFonts.hankenGrotesk(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppTheme.onSurfaceColor,
                  ),
                ),
                Text(
                  statusText,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => LiveTrackingScreen(
                    vehicleType: vehicle,
                    price: price,
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: Text(
              'Track',
              style: GoogleFonts.hankenGrotesk(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _subscribeToBookingManager() {
    _bookingSub?.cancel();
    _driverLocationSub?.cancel();
    _rideStatusSub?.cancel();

    _driverLocationSub = BookingManager().driverLocationStream.listen((LatLng pos) {
      if (mounted && _isOnline) {
        setState(() {
          _driverMapCenter = pos;
        });
        if (_driverMapController != null) {
          if (_driverStatus == 'heading_to_pickup' || _driverStatus == 'arrived_pickup') {
            LatLng? pickup;
            if (_activeBooking?['pickupLatLng'] != null) {
              if (_activeBooking?['pickupLatLng'] is LatLng) {
                pickup = _activeBooking?['pickupLatLng'] as LatLng;
              } else if (_activeBooking?['pickupLatLng'] is Map) {
                final map = _activeBooking?['pickupLatLng'] as Map;
                pickup = LatLng((map['lat'] as num).toDouble(), (map['lng'] as num).toDouble());
              }
            }
            if (pickup != null) {
              _zoomToRoute(pos, pickup);
            } else {
              _driverMapController!.animateCamera(CameraUpdate.newLatLng(pos));
            }
          } else if (_driverStatus == 'on_trip') {
            LatLng? drop;
            if (_activeBooking?['dropLatLng'] != null) {
              if (_activeBooking?['dropLatLng'] is LatLng) {
                drop = _activeBooking?['dropLatLng'] as LatLng;
              } else if (_activeBooking?['dropLatLng'] is Map) {
                final map = _activeBooking?['dropLatLng'] as Map;
                drop = LatLng((map['lat'] as num).toDouble(), (map['lng'] as num).toDouble());
              }
            }
            if (drop != null) {
              _zoomToRoute(pos, drop);
            } else {
              _driverMapController!.animateCamera(CameraUpdate.newLatLng(pos));
            }
          } else {
            _driverMapController!.animateCamera(CameraUpdate.newLatLng(pos));
          }
        }
      }
    });

    _rideStatusSub = BookingManager().rideStatusStream.listen((String status) {
      if (!mounted || !_isOnline) return;
      
      final active = BookingManager().activeBooking;
      _handleBookingUpdate(active);
      
      if (_activeBooking != null && _isNearAndMatching(_activeBooking!)) {
        final pickup = _activeBooking!['pickupLatLng'] as LatLng?;
        final drop = _activeBooking!['dropLatLng'] as LatLng?;
        if (status == 'accepted' && pickup != null) {
          _driverRoutePoints = [];
          _fetchDriverRouteDirections(_driverMapCenter!, pickup);
          _zoomToRoute(_driverMapCenter!, pickup);
        } else if (status == 'started' && pickup != null && drop != null) {
          _driverRoutePoints = [];
          _fetchDriverRouteDirections(pickup, drop);
          _zoomToRoute(pickup, drop);
        }
      }
    });

    _bookingSub = BookingManager().bookingStream.listen((Map<String, dynamic>? active) {
      if (!mounted || !_isOnline) return;
      _handleBookingUpdate(active);
    });

    final initialActive = BookingManager().activeBooking;
    if (initialActive != null) {
      _handleBookingUpdate(initialActive);
      if (_isNearAndMatching(initialActive)) {
        final status = initialActive['status'] as String? ?? 'searching';
        LatLng? pickup;
        if (initialActive['pickupLatLng'] != null) {
          if (initialActive['pickupLatLng'] is LatLng) {
            pickup = initialActive['pickupLatLng'] as LatLng;
          } else if (initialActive['pickupLatLng'] is Map) {
            final map = initialActive['pickupLatLng'] as Map;
            pickup = LatLng((map['lat'] as num).toDouble(), (map['lng'] as num).toDouble());
          }
        }
        LatLng? drop;
        if (initialActive['dropLatLng'] != null) {
          if (initialActive['dropLatLng'] is LatLng) {
            drop = initialActive['dropLatLng'] as LatLng;
          } else if (initialActive['dropLatLng'] is Map) {
            final map = initialActive['dropLatLng'] as Map;
            drop = LatLng((map['lat'] as num).toDouble(), (map['lng'] as num).toDouble());
          }
        }
        if (status == 'accepted' && pickup != null) {
          _fetchDriverRouteDirections(_driverMapCenter!, pickup);
        } else if (status == 'started' && pickup != null && drop != null) {
          _fetchDriverRouteDirections(pickup, drop);
        }
      }
    }
  }

  void _acceptBooking() {
    _stopRinging();
    if (_activeBooking == null) return;
    
    // Check if this booking request is for a Heavy Truck
    final isHeavyTruck = _activeBooking!['serviceType'] == 'heavy_truck' ||
        (_activeBooking!['title'] as String? ?? '').toLowerCase().contains('heavy truck');

    if (isHeavyTruck) {
      String? customerPhone = _activeBooking!['passengerPhone'] as String?;
      if (customerPhone == null || customerPhone.isEmpty) {
        final pId = _activeBooking!['passengerId'] as String? ?? '';
        if (pId.startsWith('mock_uid_')) {
          customerPhone = pId.replaceFirst('mock_uid_', '');
        } else {
          customerPhone = pId;
        }
      }
      
      if (customerPhone.isNotEmpty) {
        debugPrint("Heavy Truck accepted. Sending Twilio message to customer: $customerPhone");
        TwilioService.sendMessage(
          customerPhone,
          "Your booking is accpeted our pilot contact with you shortly and our contact number is 9010922111",
        ).then((error) {
          if (error != null) {
            debugPrint("Twilio SMS send error: $error");
          } else {
            debugPrint("Twilio SMS sent successfully to customer $customerPhone");
          }
        });
      }
    }

    BookingManager().acceptBooking(
      driverName: widget.userName,
      vehiclePlate: 'TS 09 SD 1234',
      vehicleModelColor: 'Black ' + _selectedVehicle,
    );

    _loadCompletedRides();

    if (isHeavyTruck) {
      setState(() {
        _activeBooking = null;
        _driverStatus = _isOnline ? 'online' : 'offline';
        _driverRoutePoints = [];
      });
      BookingManager().clearBooking();
      return;
    }

    final pickup = _activeBooking!['pickupLatLng'] as LatLng;
    if (_driverMapCenter != null) {
      _fetchDriverRouteDirections(_driverMapCenter!, pickup);
      _zoomToRoute(_driverMapCenter!, pickup);
    }
    BookingManager().startSimulatedMovement(pickup);
  }

  void _declineBooking() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        final reasons = [
          'Pickup distance is too far',
          'Drop location is in high-traffic zone',
          'Heavy traffic on pickup route',
          'Refueling/charging needed',
          'Taking a personal break',
        ];
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Decline Booking Request',
                style: GoogleFonts.hankenGrotesk(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
              ),
              const SizedBox(height: 6),
              Text(
                'Please select a suitable reason for declining this ride.',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: reasons.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      title: Text(reasons[index], style: GoogleFonts.inter(fontSize: 14)),
                      trailing: const Icon(Icons.chevron_right, size: 16),
                      onTap: () {
                        Navigator.pop(context);
                        _stopRinging();
                        BookingManager().declineBooking();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _verifyPickupOtp() {
    final otp = _otpTextController.text;
    final success = BookingManager().startTrip(otp);
    if (success) {
      setState(() {
        _otpError = '';
        _otpTextController.clear();
      });
      final drop = _activeBooking!['dropLatLng'] as LatLng;
      BookingManager().startSimulatedMovement(drop);
    } else {
      setState(() {
        _otpError = 'Invalid OTP. Ask customer again. (Required OTP is ${_activeBooking?['otp'] ?? '4921'})';
      });
    }
  }

  void _callContact(String? phone, String name) async {
    final cleanPhone = (phone ?? '').replaceAll(RegExp(r'[^\d+]'), '').trim();
    if (cleanPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Phone number not available for this contact'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    // Attempt TATA Smartflo call masking first
    try {
      final myPhone = widget.phoneNumber.isNotEmpty ? widget.phoneNumber : '9999999999';
      final response = await ApiClient().post(
        Uri.parse('${NetworkConfig.backendUrl}/api/call/mask'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'fromPhone': myPhone,
          'toPhone': cleanPhone,
        }),
        timeout: const Duration(seconds: 15),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Connecting via TATA Smartflo masked call to $name...'),
                backgroundColor: AppTheme.primaryColor,
              ),
            );
            _showInAppCallDialog(cleanPhone, name);
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('TATA Smartflo call masking attempt: $e - proceeding to direct call dialer');
    }

    // Fallback to real phone dialer
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: cleanPhone,
    );
    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      } else {
        debugPrint('Could not launch dialer for $launchUri');
      }
    } catch (e) {
      debugPrint('Error launching dialer: $e');
    }

    // Show custom calling dialog in-app
    _showInAppCallDialog(cleanPhone, name);
  }


  void _showInAppCallDialog(String phoneNumber, String contactName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _InAppCallOverlay(
          phoneNumber: phoneNumber,
          contactName: contactName,
        );
      },
    );
  }

  void _showPilotCancelDialog(String currentStatus) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Ride?'),
        content: Text(
          currentStatus == 'arrived'
              ? 'WARNING: You have already reached the customer. Cancelling now will deduct ₹10 from your salary.'
              : 'Are you sure you want to cancel this ride request?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Go Back'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              BookingManager().cancelBooking('Pilot cancelled', 'pilot');
              _loadProfileData(); // Reload to update salary balance display
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Yes, Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmPayment(String method) {
    if (_activeBooking == null) return;
    
    final priceStr = _activeBooking!['price'] as String;
    final cleanStr = priceStr.replaceAll(RegExp(r'[^0-9.]'), '');
    final double fareVal = double.tryParse(cleanStr) ?? 0.0;
    
    final newRide = {
      'date': 'Today, ' + TimeOfDay.now().format(context),
      'price': priceStr,
      'icon': _getVehicleIcon(_selectedVehicle),
      'title': 'StayDriv $_selectedVehicle Ride',
      'route': '${_activeBooking!['pickup']} to ${_activeBooking!['drop']}',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'vehicle': _selectedVehicle,
    };

    final double netEarnings = fareVal * 0.85;
    final double commission = fareVal * 0.15;

    setState(() {
      _totalEarnings += netEarnings;
      _completedRides.insert(0, newRide);
    });

    BookingManager().clearBooking();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Payment of $priceStr received! ₹${netEarnings.toStringAsFixed(2)} added to your wallet (15% commission of ₹${commission.toStringAsFixed(2)} sent to admin).',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  IconData _getVehicleIcon(String vehicle) {
    if (vehicle == 'Bike') return Icons.two_wheeler_rounded;
    if (vehicle == 'Auto') return Icons.electric_rickshaw_rounded;
    if (vehicle == 'Car') return Icons.directions_car_rounded;
    if (vehicle == 'Mini Truck') return Icons.airport_shuttle_rounded;
    return Icons.local_shipping_rounded;
  }

  String _formatTimestamp(int timestampMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final monthStr = months[dt.month - 1];
    final hourStr = dt.hour.toString().padLeft(2, '0');
    final minStr = dt.minute.toString().padLeft(2, '0');
    return '$monthStr ${dt.day}, $hourStr:$minStr';
  }

  Future<void> _fetchDriverRouteDirections(LatLng origin, LatLng destination) async {
    final String baseUrl = NetworkConfig.backendUrl;
    final Uri url = Uri.parse('$baseUrl/api/directions?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}');
    
    try {
      final response = await ApiClient().get(url, timeout: const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final route = data['routes'][0];
          final String polylineStr = route['overview_polyline']['points'];
          final List<LatLng> polylineCoordinates = _decodePolyline(polylineStr);
          setState(() {
            _driverRoutePoints = polylineCoordinates;
          });
          return;
        }
      }
      _setDriverFallbackRoute(origin, destination);
    } catch (e) {
      debugPrint('Error fetching driver route directions: $e');
      _setDriverFallbackRoute(origin, destination);
    }
  }

  void _setDriverFallbackRoute(LatLng origin, LatLng destination) {
    if (!mounted) return;
    setState(() {
      _driverRoutePoints = [origin, destination];
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

  void _zoomToRoute(LatLng from, LatLng to) {
    if (_driverMapController != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          final latDiff = (from.latitude - to.latitude).abs();
          final lngDiff = (from.longitude - to.longitude).abs();
          
          if (latDiff < 0.002 && lngDiff < 0.002) {
            _driverMapController!.animateCamera(CameraUpdate.newLatLngZoom(from, 15.0));
            return;
          }

          final bounds = LatLngBounds(
            southwest: LatLng(
              from.latitude < to.latitude ? from.latitude : to.latitude,
              from.longitude < to.longitude ? from.longitude : to.longitude,
            ),
            northeast: LatLng(
              from.latitude > to.latitude ? from.latitude : to.latitude,
              from.longitude > to.longitude ? from.longitude : to.longitude,
            ),
          );
          _driverMapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60.0));
        } catch (e) {
          debugPrint('Error zooming to route bounds: $e');
          try {
            _driverMapController!.animateCamera(CameraUpdate.newLatLngZoom(from, 15.0));
          } catch (innerErr) {
            debugPrint('Error fallback camera: $innerErr');
          }
        }
      });
    }
  }

  Set<Marker> _getDriverMarkers() {
    if (_driverMapCenter == null) return {};
    if (_activeBooking == null) {
      return {
        Marker(
          markerId: const MarkerId('driver_pos'),
          position: _driverMapCenter!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(title: 'You (Driver)', snippet: 'Vehicle: $_selectedVehicle'),
        ),
      };
    }
    
    LatLng? pickup;
    if (_activeBooking!['pickupLatLng'] != null) {
      if (_activeBooking!['pickupLatLng'] is LatLng) {
        pickup = _activeBooking!['pickupLatLng'] as LatLng;
      } else if (_activeBooking!['pickupLatLng'] is Map) {
        final map = _activeBooking!['pickupLatLng'] as Map;
        pickup = LatLng((map['lat'] as num).toDouble(), (map['lng'] as num).toDouble());
      }
    }
    
    LatLng? drop;
    if (_activeBooking!['dropLatLng'] != null) {
      if (_activeBooking!['dropLatLng'] is LatLng) {
        drop = _activeBooking!['dropLatLng'] as LatLng;
      } else if (_activeBooking!['dropLatLng'] is Map) {
        final map = _activeBooking!['dropLatLng'] as Map;
        drop = LatLng((map['lat'] as num).toDouble(), (map['lng'] as num).toDouble());
      }
    }

    if (pickup == null || drop == null) {
      return {
        Marker(
          markerId: const MarkerId('driver_pos'),
          position: _driverMapCenter!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'You (Driver)'),
        ),
      };
    }
    
    final Set<Marker> markers = {
      Marker(
        markerId: const MarkerId('driver_pos'),
        position: _driverMapCenter!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'You (Driver)'),
      ),
    };
    
    if (_driverStatus == 'heading_to_pickup' || _driverStatus == 'arrived_pickup') {
      markers.add(
        Marker(
          markerId: const MarkerId('pickup_pos'),
          position: pickup,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(title: 'Customer Pickup', snippet: _activeBooking!['pickup']),
        ),
      );
    } else if (_driverStatus == 'on_trip') {
      markers.add(
        Marker(
          markerId: const MarkerId('drop_pos'),
          position: drop,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(title: 'Customer Destination', snippet: _activeBooking!['drop']),
        ),
      );
    }
    
    return markers;
  }

  Set<Polyline> _getDriverPolylines() {
    if (_activeBooking == null || _driverMapCenter == null) return {};
    
    LatLng? pickup;
    if (_activeBooking!['pickupLatLng'] != null) {
      if (_activeBooking!['pickupLatLng'] is LatLng) {
        pickup = _activeBooking!['pickupLatLng'] as LatLng;
      } else if (_activeBooking!['pickupLatLng'] is Map) {
        final map = _activeBooking!['pickupLatLng'] as Map;
        pickup = LatLng((map['lat'] as num).toDouble(), (map['lng'] as num).toDouble());
      }
    }
    
    LatLng? drop;
    if (_activeBooking!['dropLatLng'] != null) {
      if (_activeBooking!['dropLatLng'] is LatLng) {
        drop = _activeBooking!['dropLatLng'] as LatLng;
      } else if (_activeBooking!['dropLatLng'] is Map) {
        final map = _activeBooking!['dropLatLng'] as Map;
        drop = LatLng((map['lat'] as num).toDouble(), (map['lng'] as num).toDouble());
      }
    }

    if (pickup == null || drop == null) return {};
    
    if (_driverStatus == 'heading_to_pickup') {
      return {
        Polyline(
          polylineId: const PolylineId('to_pickup'),
          color: Colors.green,
          points: _driverRoutePoints.isNotEmpty ? _driverRoutePoints : [_driverMapCenter!, pickup],
          width: 5,
        ),
      };
    } else if (_driverStatus == 'on_trip') {
      return {
        Polyline(
          polylineId: const PolylineId('to_drop'),
          color: AppTheme.primaryColor,
          points: _driverRoutePoints.isNotEmpty ? _driverRoutePoints : [_driverMapCenter!, drop],
          width: 5,
        ),
      };
    }
    return {};
  }

  Future<void> _updateDriverApproval(String uid, String name, String phone, bool approved) async {
    try {
      if (_isFirebaseInitialized && uid.isNotEmpty && !uid.startsWith('mock_uid_')) {
        await FirebaseFirestore.instance
            .collection('partners')
            .doc(uid)
            .update({'approved': approved});
      }

      final baseUrl = NetworkConfig.backendUrl;
      final updateUrl = Uri.parse('$baseUrl/api/partner/update');
      final response = await ApiClient().post(
        updateUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': uid,
          'approved': approved,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint("Successfully updated driver approval in MongoDB");
      }

      final pilotMsg = approved
          ? "Congratulations $name! Your StayDriv Pilot account has been APPROVED. You can now go online to accept rides."
          : "Hello $name, your StayDriv Pilot account verification was NOT APPROVED. Please contact support.";

      final customerMsg = approved
          ? "StayDriv Notification: Pilot $name ($phone) has been APPROVED."
          : "StayDriv Notification: Pilot $name ($phone) has been NOT APPROVED.";

      if (phone.isNotEmpty) {
        await TwilioService.sendMessage(phone, pilotMsg);
      }
      if (widget.phoneNumber.isNotEmpty) {
        await TwilioService.sendMessage(widget.phoneNumber, customerMsg);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pilot status updated to ${approved ? "APPROVED" : "NOT APPROVED"}. SMS sent.'),
            backgroundColor: approved ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error updating driver approval: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating pilot status: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }



  Widget _buildDocApprovalDetailView(Map<String, dynamic> driverData) {
    final uid = driverData['uid'] ?? '';
    final name = driverData['name'] ?? 'Driver';
    final phone = driverData['phone'] ?? '';
    final vehicleType = driverData['vehicleType'] ?? 'Bike';
    final vehiclePlate = driverData['vehiclePlate'] ?? 'TS 09 SD 1234';
    final isApproved = driverData['approved'] == true;

    final photo = driverData['photo'] as String?;
    final aadhaarFront = driverData['aadhaarFront'] as String?;
    final aadhaarBack = driverData['aadhaarBack'] as String?;
    final licenseFront = driverData['licenseFront'] as String?;
    final licenseBack = driverData['licenseBack'] as String?;
    final rcFront = driverData['rcFront'] as String?;
    final rcBack = driverData['rcBack'] as String?;
    final fitness = driverData['fitness'] as String?;
    final permit = driverData['permit'] as String?;

    final showExtraDocs = vehicleType == 'Car' || vehicleType == 'Mini Truck' || vehicleType == 'Heavy Truck';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Verify Documents: $name',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.onSurfaceColor,
                  ),
                ),
                Text(
                  'Review submitted files for +91 $phone',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isApproved ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isApproved ? 'APPROVED' : 'PENDING APPROVAL',
                style: GoogleFonts.robotoMono(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isApproved ? Colors.green : Colors.orange,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.15,
          children: [
            _buildDocPreviewCard('Aadhaar Card - Front', Icons.badge_outlined, aadhaarFront),
            _buildDocPreviewCard('Aadhaar Card - Back', Icons.badge_outlined, aadhaarBack),
            _buildDocPreviewCard('Driving License - Front', Icons.contact_mail_outlined, licenseFront),
            _buildDocPreviewCard('Driving License - Back', Icons.contact_mail_outlined, licenseBack),
            _buildDocPreviewCard('Vehicle RC - Front', Icons.directions_car_outlined, rcFront),
            _buildDocPreviewCard('Vehicle RC - Back', Icons.directions_car_outlined, rcBack),
            _buildDocPreviewCard('Driver Profile Photo', Icons.face_outlined, photo),
            if (showExtraDocs) ...[
              _buildDocPreviewCard('Fitness Certificate', Icons.description_outlined, fitness),
              _buildDocPreviewCard('Vehicle Permit', Icons.vpn_key_outlined, permit),
            ],
          ],
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vehicle Details',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.onSurfaceColor,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Vehicle Type:', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant)),
                  Text(vehicleType, style: GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('License Plate:', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant)),
                  Text(vehiclePlate, style: GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  _updateDriverApproval(uid, name, phone, false);
                  setState(() {
                    _selectedDriverForDocApproval = null;
                  });
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  'Not Approve',
                  style: GoogleFonts.hankenGrotesk(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  _updateDriverApproval(uid, name, phone, true);
                  setState(() {
                    _selectedDriverForDocApproval = null;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  'Approve Pilot',
                  style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildDocPreviewCard(String docName, IconData icon, String? docUrl) {
    final hasUploaded = docUrl != null && docUrl.isNotEmpty;
    return InkWell(
      onTap: () {
        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text(docName, style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold)),
              content: Container(
                width: 300,
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[350]!),
                ),
                child: hasUploaded
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          docUrl,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const Center(child: CircularProgressIndicator());
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(child: Icon(Icons.broken_image, size: 48, color: Colors.grey));
                          },
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, size: 48, color: AppTheme.outlineColor),
                          const SizedBox(height: 12),
                          Text(
                            'No Document Uploaded',
                            style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          Text(
                            'Pilot has not submitted this file yet.',
                            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.onSurfaceVariant),
                          ),
                        ],
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasUploaded 
                ? AppTheme.outlineVariant.withOpacity(0.3) 
                : Colors.red.withOpacity(0.2),
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon, 
                    color: hasUploaded ? AppTheme.primaryColor : Colors.grey, 
                    size: 18
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: hasUploaded 
                        ? Colors.green.withOpacity(0.12) 
                        : Colors.red.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    hasUploaded ? 'UPLOADED' : 'PENDING',
                    style: GoogleFonts.robotoMono(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: hasUploaded ? Colors.green : Colors.red,
                    ),
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  docName,
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: hasUploaded ? AppTheme.onSurfaceColor : AppTheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  hasUploaded ? 'Tap to view file' : 'Not submitted',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: AppTheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminDashboardView() {
    if (!_isFirebaseInitialized) {
      return _buildAdminDashboardContent(
        bookings: _mongoAdminBookings,
        drivers: _mongoAdminDrivers,
        isLoading: false,
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _adminBookingsStream,
      builder: (context, bookingsSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: _adminDriversStream,
          builder: (context, driversSnapshot) {
            final List<Map<String, dynamic>> bookingsList = bookingsSnapshot.hasData
                ? bookingsSnapshot.data!.docs.map((doc) => doc.data() as Map<String, dynamic>).toList()
                : [];
            final List<Map<String, dynamic>> driversList = driversSnapshot.hasData
                ? driversSnapshot.data!.docs.map((doc) => doc.data() as Map<String, dynamic>).toList()
                : [];

            return _buildAdminDashboardContent(
              bookings: bookingsList,
              drivers: driversList,
              isLoading: !bookingsSnapshot.hasData || !driversSnapshot.hasData,
            );
          },
        );
      },
    );
  }

  Future<void> _showAdvanceTruckRidesHistoryDialog(String driverId, String driverName) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final url = Uri.parse('$baseUrl/api/user/$driverId/rides?role=Driver&allStatuses=true');
      final response = await ApiClient().get(url, retry: false);
      
      if (mounted) Navigator.pop(context); // Close loading dialog

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['bookings'] != null) {
          final List rawBookings = data['bookings'];
          
          final List filteredBookings = rawBookings.where((b) {
            // Must be scheduled/advance booking
            final hasScheduledDate = b['scheduledDate'] != null && (b['scheduledDate'] as String).isNotEmpty;
            if (!hasScheduledDate) return false;

            // Must be Heavy Truck
            final serviceType = (b['serviceType'] as String? ?? '').toLowerCase();
            final title = (b['title'] as String? ?? '').toLowerCase();
            final vehicle = (b['vehicle'] as String? ?? '').toLowerCase();
            final isHeavyTruck = serviceType == 'heavy_truck' || title.contains('heavy truck') || vehicle.contains('heavy truck') || vehicle.contains('ton truck');
            
            return isHeavyTruck;
          }).toList();

          if (mounted) {
            _showAdvanceHistoryDetailsBottomSheet(driverName, filteredBookings);
          }
        } else {
          throw Exception("Invalid data structure");
        }
      } else {
        throw Exception("Server status code: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to fetch advance rides history: $e"),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  void _showAdvanceHistoryDetailsBottomSheet(String driverName, List bookings) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: const BoxDecoration(
            color: AppTheme.surfaceContainerLowest,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Advance Truck Booking History",
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.onSurfaceColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Pilot: $driverName (${bookings.length} rides)",
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: AppTheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: bookings.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history_toggle_off_rounded, size: 48, color: AppTheme.onSurfaceVariant.withOpacity(0.5)),
                            const SizedBox(height: 12),
                            Text(
                              "No advance bookings found",
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: bookings.length,
                        itemBuilder: (context, index) {
                          final b = bookings[index];
                          final pickup = b['pickup'] ?? 'Unknown pickup';
                          final drop = b['drop'] ?? 'Unknown dropoff';
                          final price = b['price'] ?? '₹0';
                          final customerName = b['passengerName'] ?? 'No Customer Name';
                          final schedDateRaw = b['scheduledDate'] ?? '';
                          final schedDate = schedDateRaw.isNotEmpty ? _formatDateToCustomString(schedDateRaw) : 'No Date';
                          final schedTime = b['scheduledTimeSlot'] ?? '';
                          final status = (b['status'] as String? ?? 'searching').toUpperCase();
                          final vehicle = b['vehicle'] ?? 'Heavy Truck';
                          
                          Color statusColor = Colors.grey;
                          if (status == 'COMPLETED') {
                            statusColor = Colors.green;
                          } else if (status == 'ACCEPTED' || status == 'ARRIVED' || status == 'STARTED') {
                            statusColor = Colors.blue;
                          } else if (status == 'SEARCHING' || status == 'INCOMING') {
                            statusColor = Colors.orange;
                          } else if (status == 'CANCELLED' || status == 'TIMED_OUT') {
                            statusColor = Colors.red;
                          }

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: AppTheme.outlineVariant.withOpacity(0.4)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "Customer: $customerName (${b['passengerPhone'] ?? ''})",
                                              style: GoogleFonts.hankenGrotesk(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: AppTheme.primaryColor,
                                              ),
                                            ),
                                            Text(
                                              vehicle,
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                color: AppTheme.onSurfaceVariant.withOpacity(0.7),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        price,
                                        style: GoogleFonts.robotoMono(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: AppTheme.onSurfaceColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "From: $pickup",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppTheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "To: $drop",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppTheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        "Sched: $schedDate $schedTime",
                                        style: GoogleFonts.robotoMono(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.onSurfaceVariant,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: statusColor.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          status,
                                          style: GoogleFonts.robotoMono(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: statusColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showRidesHistoryDialog(String driverId, String driverName, {required bool todayOnly}) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final url = Uri.parse('$baseUrl/api/user/$driverId/rides?role=Driver');
      final response = await ApiClient().get(url, retry: false);
      
      if (mounted) Navigator.pop(context); // Close loading dialog

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['bookings'] != null) {
          final List rawBookings = data['bookings'];
          
          final now = DateTime.now();
          final List filteredBookings = rawBookings.where((b) {
            final dateStr = b['createdAt'] as String?;
            if (dateStr == null) return !todayOnly;
            final date = DateTime.tryParse(dateStr);
            if (date == null) return !todayOnly;
            if (todayOnly) {
              return date.year == now.year && date.month == now.month && date.day == now.day;
            }
            return true;
          }).toList();

          if (mounted) {
            _showHistoryDetailsBottomSheet(driverName, filteredBookings, todayOnly);
          }
        } else {
          throw Exception("Invalid data structure");
        }
      } else {
        throw Exception("Server status code: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to fetch rides history: $e"),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  void _showHistoryDetailsBottomSheet(String driverName, List bookings, bool todayOnly) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: const BoxDecoration(
            color: AppTheme.surfaceContainerLowest,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            todayOnly ? "Today's Ride History" : "Total Ride History",
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.onSurfaceColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Pilot: $driverName (${bookings.length} completed)",
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: AppTheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: bookings.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history_toggle_off_rounded, size: 48, color: AppTheme.onSurfaceVariant.withOpacity(0.5)),
                            const SizedBox(height: 12),
                            Text(
                              "No rides completed",
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: bookings.length,
                        itemBuilder: (context, index) {
                          final b = bookings[index];
                          final pickup = b['pickup'] ?? 'Unknown pickup';
                          final drop = b['drop'] ?? 'Unknown dropoff';
                          final price = b['price'] ?? '₹0';
                          final customerName = b['passengerName'] ?? 'No Customer Name';
                          
                          String dateFormatted = '';
                          try {
                            final dateStr = b['createdAt'] as String?;
                            if (dateStr != null) {
                              final dt = DateTime.parse(dateStr);
                              dateFormatted = "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
                            }
                          } catch (_) {}

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: AppTheme.outlineVariant.withOpacity(0.4)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          "Customer: $customerName",
                                          style: GoogleFonts.hankenGrotesk(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: AppTheme.primaryColor,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        price,
                                        style: GoogleFonts.robotoMono(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: AppTheme.onSurfaceColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "From: $pickup",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppTheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "To: $drop",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppTheme.onSurfaceVariant,
                                    ),
                                  ),
                                  if (dateFormatted.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          dateFormatted,
                                          style: GoogleFonts.robotoMono(
                                            fontSize: 10,
                                            color: AppTheme.onSurfaceVariant.withOpacity(0.6),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'COMPLETED',
                                            style: GoogleFonts.robotoMono(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAdminDashboardContent({
    required List<Map<String, dynamic>> bookings,
    required List<Map<String, dynamic>> drivers,
    required bool isLoading,
  }) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 600;

    final activeDrivers = drivers.length;
    final searchingBookings = bookings.where((b) => b['status'] == 'searching').length;

    final filteredBookings = bookings.where((b) {
      if (_adminSearchQuery.isEmpty) return true;
      final title = (b['title'] ?? '').toString().toLowerCase();
      final pickup = (b['pickup'] ?? '').toString().toLowerCase();
      final drop = (b['drop'] ?? '').toString().toLowerCase();
      final driver = (b['driverName'] ?? '').toString().toLowerCase();
      final status = (b['status'] ?? '').toString().toLowerCase();
      final query = _adminSearchQuery.toLowerCase();
      return title.contains(query) ||
          pickup.contains(query) ||
          drop.contains(query) ||
          driver.contains(query) ||
          status.contains(query);
    }).toList();

    final filteredDrivers = drivers.where((d) {
      if (_adminSearchQuery.isEmpty) return true;
      final name = (d['name'] ?? '').toString().toLowerCase();
      final phone = (d['phone'] ?? '').toString().toLowerCase();
      final vehicle = (d['vehicleType'] ?? '').toString().toLowerCase();
      final plate = (d['vehiclePlate'] ?? '').toString().toLowerCase();
      final query = _adminSearchQuery.toLowerCase();
      return name.contains(query) ||
          phone.contains(query) ||
          vehicle.contains(query) ||
          plate.contains(query);
    }).toList();

    return Column(
      children: [
        // Top App Bar
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.onSurfaceColor),
                      onPressed: () {
                        if (_selectedDriverForDocApproval != null) {
                          setState(() {
                            _selectedDriverForDocApproval = null;
                          });
                        } else {
                          // Go/stay on admin console only (do nothing)
                        }
                      },
                    ),
                    const SizedBox(width: 4),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.primaryColor,
                      ),
                      child: const Icon(Icons.admin_panel_settings, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Admin Console',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.onSurfaceColor,
                          ),
                        ),
                        Text(
                          'StayDriv Unified Platform',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppTheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.logout_rounded, color: AppTheme.errorColor),
                  onPressed: () async {
                    await FirebaseService().signOut();
                    if (mounted) {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (context) => const LoginScreen()),
                        (route) => false,
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),

        // Stats and Lists
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: _selectedDriverForDocApproval != null
                ? _buildDocApprovalDetailView(_selectedDriverForDocApproval!)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Stats Bento Grid
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE0E7FF), Color(0xFFC7D2FE)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x0A000000),
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            )
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PILOTS REGISTERED',
                              style: GoogleFonts.robotoMono(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$activeDrivers',
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x0A000000),
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            )
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SEARCHING RIDES',
                              style: GoogleFonts.robotoMono(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.safetyYellowText,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$searchingBookings',
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.safetyYellowText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Search Bar for Quick Search
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _adminSearchController,
                    onChanged: (value) {
                      setState(() {
                        _adminSearchQuery = value;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search bookings (pickup, dropoff, pilot, status)...',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppTheme.onSurfaceVariant.withOpacity(0.6),
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppTheme.primaryColor,
                        size: 20,
                      ),
                      suffixIcon: _adminSearchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _adminSearchController.clear();
                                setState(() {
                                  _adminSearchQuery = '';
                                });
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppTheme.outlineVariant.withOpacity(0.4),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppTheme.outlineVariant.withOpacity(0.3),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppTheme.primaryColor,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Section 1: Recent Bookings
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recent Bookings',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.onSurfaceColor,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'REAL-TIME',
                        style: GoogleFonts.robotoMono(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (filteredBookings.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    alignment: Alignment.center,
                    child: Text(
                      _adminSearchQuery.isEmpty ? 'No bookings found' : 'No matching bookings found',
                      style: GoogleFonts.inter(color: AppTheme.onSurfaceVariant),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredBookings.length,
                    itemBuilder: (context, index) {
                      final data = filteredBookings[index];
                      final status = data['status'] ?? 'searching';

                      Color statusColor = Colors.orange;
                      if (status == 'accepted' || status == 'started') {
                        statusColor = AppTheme.primaryColor;
                      } else if (status == 'completed') {
                        statusColor = Colors.green;
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    data['title'] ?? 'Ride Booking',
                                    style: GoogleFonts.hankenGrotesk(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      status.toString().toUpperCase(),
                                      style: GoogleFonts.robotoMono(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: statusColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'From: ${data['pickup'] ?? ""}',
                                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'To: ${data['drop'] ?? ""}',
                                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Fare: ${data['price'] ?? "₹150"}',
                                    style: GoogleFonts.robotoMono(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.onSurfaceColor,
                                    ),
                                  ),
                                  if (data['driverName'] != null)
                                    Text(
                                      'Driver: ${data['driverName']}',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: AppTheme.primaryColor,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 24),

                // Section 2: Pilot Verification & Approvals List
                Text(
                  'Pilot Verification & Approvals',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.onSurfaceColor,
                  ),
                ),
                const SizedBox(height: 12),
                if (isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (filteredDrivers.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    alignment: Alignment.center,
                    child: Text(
                      _adminSearchQuery.isEmpty ? 'No registered pilots found' : 'No matching pilots found',
                      style: GoogleFonts.inter(color: AppTheme.onSurfaceVariant),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredDrivers.length,
                    itemBuilder: (context, index) {
                      final data = filteredDrivers[index];
                      final uid = data['uid'] ?? '';
                      final name = data['name'] ?? 'Driver';
                      final phone = data['phone'] ?? '';
                      final isApproved = data['approved'] == true;
                      final isOnline = data['online'] == true;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: AppTheme.primaryAccent.withOpacity(0.2),
                                    child: Icon(
                                      _getVehicleIcon(data['vehicleType'] ?? 'Bike'),
                                      color: AppTheme.primaryColor,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: GoogleFonts.hankenGrotesk(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Phone: +91 $phone',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: AppTheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isApproved 
                                              ? Colors.green.withOpacity(0.1) 
                                              : Colors.orange.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          isApproved ? 'APPROVED' : 'PENDING APPROVAL',
                                          style: GoogleFonts.robotoMono(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isApproved ? Colors.green : Colors.orange,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              color: isOnline ? Colors.green : Colors.grey,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            isOnline ? 'Online' : 'Offline',
                                            style: GoogleFonts.inter(
                                              fontSize: 10,
                                              color: AppTheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Vehicle: ${data['vehiclePlate'] ?? "Plate"} (${data['vehicleType'] ?? "Bike"})',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppTheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Divider(height: 1),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if ((data['vehicleType'] as String? ?? '').toLowerCase().contains('heavy truck')) ...[
                                    Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.red, width: 1.5),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: TextButton.icon(
                                        onPressed: () => _showAdvanceTruckRidesHistoryDialog(uid, name),
                                        icon: const Icon(Icons.pending_actions_rounded, size: 16, color: Colors.red),
                                        label: Text(
                                          'Advance booking history for heavy truck',
                                          style: GoogleFonts.hankenGrotesk(
                                            color: Colors.red.shade800,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  TextButton.icon(
                                    onPressed: () => _showRidesHistoryDialog(uid, name, todayOnly: true),
                                    icon: const Icon(Icons.today_rounded, size: 16, color: Colors.orange),
                                    label: Text(
                                      'Today Rides History',
                                      style: GoogleFonts.hankenGrotesk(
                                        color: Colors.orange.shade800,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton.icon(
                                    onPressed: () => _showRidesHistoryDialog(uid, name, todayOnly: false),
                                    icon: const Icon(Icons.history_rounded, size: 16, color: Colors.purple),
                                    label: Text(
                                      'Total Rides History',
                                      style: GoogleFonts.hankenGrotesk(
                                        color: Colors.purple.shade700,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        _selectedDriverForDocApproval = data;
                                      });
                                    },
                                    icon: const Icon(Icons.description_outlined, size: 16, color: AppTheme.primaryColor),
                                    label: Text(
                                      'View Docs',
                                      style: GoogleFonts.hankenGrotesk(
                                        color: AppTheme.primaryColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton.icon(
                                    onPressed: () => _updateDriverApproval(uid, name, phone, false),
                                    icon: const Icon(Icons.close, size: 16, color: Colors.red),
                                    label: Text(
                                      'Not Approve',
                                      style: GoogleFonts.hankenGrotesk(
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: () => _updateDriverApproval(uid, name, phone, true),
                                    icon: const Icon(Icons.check, size: 16, color: Colors.white),
                                    label: Text(
                                      'Approve',
                                      style: GoogleFonts.hankenGrotesk(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDriverDashboardView() {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 600;

    return Stack(
      children: [
        Positioned.fill(
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _driverMapCenter!,
              zoom: 14.0,
            ),
            onMapCreated: (controller) {
              _driverMapController = controller;
              if (_activeBooking != null) {
                final pickup = _activeBooking!['pickupLatLng'] as LatLng?;
                final drop = _activeBooking!['dropLatLng'] as LatLng?;
                if (pickup != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_driverStatus == 'heading_to_pickup' || _driverStatus == 'arrived_pickup') {
                      _zoomToRoute(_driverMapCenter!, pickup);
                    } else if (_driverStatus == 'on_trip' && drop != null) {
                      _zoomToRoute(pickup, drop);
                    }
                  });
                }
              }
            },
            markers: _getDriverMarkers(),
            polylines: _getDriverPolylines(),
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
          ),
        ),

        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              constraints: BoxConstraints(
                maxWidth: isDesktop ? 500 : double.infinity,
              ),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isOnline ? Colors.green.withOpacity(0.5) : AppTheme.outlineVariant.withOpacity(0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _isOnline ? Colors.green.withOpacity(0.15) : Colors.black.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Driver Console',
                            style: GoogleFonts.hankenGrotesk(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _isOnline ? Colors.green : Colors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _isOnline ? 'ONLINE • RECEIVING JOBS' : 'OFFLINE • GO ONLINE TO WORK',
                                style: GoogleFonts.robotoMono(
                                  fontSize: 10,
                                  color: _isOnline ? Colors.green : AppTheme.onSurfaceVariant,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Switch(
                        value: _isOnline,
                        onChanged: _driverStatus == 'heading_to_pickup' || 
                                   _driverStatus == 'arrived_pickup' || 
                                   _driverStatus == 'on_trip' || 
                                   _driverStatus == 'payment_pending' 
                                   ? null 
                                   : _toggleDuty,
                        activeColor: Colors.green,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        Positioned(
          bottom: 270,
          right: 16,
          child: GestureDetector(
            onTap: () {
              if (_driverMapController != null && _driverMapCenter != null) {
                _driverMapController!.animateCamera(
                  CameraUpdate.newLatLng(_driverMapCenter!),
                );
              }
            },
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(
                  color: AppTheme.outlineVariant.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.my_location_rounded,
                color: AppTheme.primaryColor,
                size: 24,
              ),
            ),
          ),
        ),

        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 500 : double.infinity,
            ),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: _buildBottomPanel(),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomPanel() {
    if (_driverStatus == 'offline' || _driverStatus == 'online') {
      return _buildVehicleSelectionPanel();
    } else if (_driverStatus == 'incoming_request') {
      return _buildIncomingRequestPanel();
    } else if (_driverStatus == 'heading_to_pickup') {
      return _buildHeadingToPickupPanel();
    } else if (_driverStatus == 'arrived_pickup') {
      return _buildArrivedPickupPanel();
    } else if (_driverStatus == 'on_trip') {
      return _buildOnTripPanel();
    } else if (_driverStatus == 'payment_pending') {
      return _buildPaymentPendingPanel();
    }
    return const SizedBox();
  }

  Widget _buildVehicleSelectionPanel() {
    IconData vIcon = _getVehicleIcon(_selectedVehicle);
    String vDesc = '';
    if (_selectedVehicle == 'Bike') vDesc = 'Bike Taxi / small parcels';
    else if (_selectedVehicle == 'Auto') vDesc = 'Fast passenger / medium weight';
    else if (_selectedVehicle == 'Car') vDesc = 'Comfort rides / passenger cab';
    else if (_selectedVehicle == 'Mini Truck') vDesc = 'Large transport / cargo delivery';
    else vDesc = 'Retail & heavy goods transport';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.5)),
        boxShadow: const [
          BoxShadow(color: Color(0x1F000000), blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Active Vehicle Status',
            style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 4),
                    ],
                  ),
                  child: Icon(vIcon, color: AppTheme.primaryColor, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedVehicle,
                        style: GoogleFonts.hankenGrotesk(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        vDesc,
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'ACTIVE',
                    style: GoogleFonts.robotoMono(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _isOnline ? Colors.green.withOpacity(0.08) : AppTheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isOnline ? Colors.green.withOpacity(0.2) : AppTheme.outlineVariant.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isOnline ? Icons.radar_rounded : Icons.power_settings_new_rounded,
                  color: _isOnline ? Colors.green : AppTheme.onSurfaceVariant,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isOnline 
                        ? 'Online • Waiting for $_selectedVehicle bookings...' 
                        : 'Offline • Toggle switch above to receive bookings.',
                    style: GoogleFonts.robotoMono(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _isOnline ? Colors.green : AppTheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncomingRequestPanel() {
    if (_activeBooking == null) return const SizedBox();
    
    final bool isParcel = _activeBooking!['serviceType'] == 'parcel';
    final pickupHouse = _activeBooking!['pickupHouse'] as String?;
    final pickupName = _activeBooking!['pickupContactName'] as String?;
    final pickupPhone = _activeBooking!['pickupContactPhone'] as String?;
    final dropHouse = _activeBooking!['dropHouse'] as String?;
    final dropName = _activeBooking!['dropContactName'] as String?;
    final dropPhone = _activeBooking!['dropContactPhone'] as String?;
    final paymentOption = _activeBooking!['paymentOption'] as String?;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.primaryColor, width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0x2B000000), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: const BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                child: Text(
                  isParcel ? 'NEW PARCEL REQUEST' : 'NEW BOOKING REQUEST',
                  style: GoogleFonts.robotoMono(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: _incomingRequestCountdown / 10.0,
                    backgroundColor: Colors.grey[200],
                    color: AppTheme.primaryColor,
                  ),
                  Text(
                    '$_incomingRequestCountdown',
                    style: GoogleFonts.robotoMono(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            isParcel ? 'Parcel Delivery (${_activeBooking!['vehicle']})' : (_activeBooking!['title'] as String? ?? ''),
            style: GoogleFonts.hankenGrotesk(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
          ),
          if (!isParcel) ...[
            const SizedBox(height: 4),
            Text(
              'Customer: ${_activeBooking!['passengerName'] ?? 'Customer'}',
              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.onSurfaceVariant, fontWeight: FontWeight.w500),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Distance: ${_activeBooking!['distance'] ?? 'Calculating...'}  •  Fare: ${_activeBooking!['price']}',
            style: GoogleFonts.robotoMono(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green),
          ),
          if (_activeBooking!['serviceType'] == 'heavy_truck' || (_activeBooking!['title'] as String? ?? '').toLowerCase().contains('heavy truck')) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_month, size: 14, color: AppTheme.onSurfaceVariant.withOpacity(0.8)),
                const SizedBox(width: 6),
                Builder(
                  builder: (context) {
                    String dateFormatted = '';
                    try {
                      final schedDate = _activeBooking!['scheduledDate'] as String?;
                      final schedTime = _activeBooking!['scheduledTimeSlot'] as String?;
                      if (schedDate != null && schedDate.isNotEmpty) {
                        dateFormatted = _formatDateToCustomString(schedDate) + (schedTime != null && schedTime.isNotEmpty ? ' $schedTime' : '');
                      } else {
                        final dateStr = _activeBooking!['createdAt'] as String?;
                        if (dateStr != null) {
                          final dt = DateTime.parse(dateStr).toLocal();
                          final datePart = "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
                          final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
                          final period = dt.hour >= 12 ? 'PM' : 'AM';
                          final timePart = "${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $period";
                          dateFormatted = "${_formatDateToCustomString(datePart)} $timePart";
                        } else {
                          final dt = DateTime.now().toLocal();
                          final datePart = "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
                          final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
                          final period = dt.hour >= 12 ? 'PM' : 'AM';
                          final timePart = "${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $period";
                          dateFormatted = "${_formatDateToCustomString(datePart)} $timePart";
                        }
                      }
                    } catch (_) {
                      final dt = DateTime.now().toLocal();
                      final datePart = "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
                      final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
                      final period = dt.hour >= 12 ? 'PM' : 'AM';
                      final timePart = "${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $period";
                      dateFormatted = "${_formatDateToCustomString(datePart)} $timePart";
                    }
                    return Text(
                      'Booking Date/Time: $dateFormatted',
                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant, fontWeight: FontWeight.bold),
                    );
                  }
                ),
              ],
            ),
          ],
          if (isParcel && paymentOption != null) ...[
            const SizedBox(height: 4),
            Text(
              'Payment Mode: $paymentOption',
              style: GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
            ),
          ],
          const SizedBox(height: 16),
          // Pickup Location
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 3.0),
                child: Icon(Icons.circle, color: Colors.green, size: 10),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _activeBooking!['pickup'] as String? ?? '',
                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.onSurfaceColor, fontWeight: FontWeight.w600),
                    ),
                    if (isParcel) ...[
                      if (pickupHouse != null && pickupHouse.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'House/Bldg: $pickupHouse',
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant),
                        ),
                      ],
                      if (pickupName != null && pickupName.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Sender: $pickupName ($pickupPhone)',
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Drop Location
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 3.0),
                child: Icon(Icons.circle, color: Colors.red, size: 10),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _activeBooking!['drop'] as String? ?? '',
                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.onSurfaceColor, fontWeight: FontWeight.w600),
                    ),
                    if (isParcel) ...[
                      if (dropHouse != null && dropHouse.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'House/Bldg: $dropHouse',
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant),
                        ),
                      ],
                      if (dropName != null && dropName.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Recipient: $dropName ($dropPhone)',
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _declineBooking,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.errorColor,
                    side: const BorderSide(color: AppTheme.errorColor),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(
                    'Decline',
                    style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _acceptBooking,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(
                    'Accept',
                    style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeadingToPickupPanel() {
    if (_activeBooking == null) return const SizedBox();

    final bool isParcel = _activeBooking!['serviceType'] == 'parcel';
    final pickupHouse = _activeBooking!['pickupHouse'] as String?;
    final pickupName = _activeBooking!['pickupContactName'] as String?;
    final pickupPhone = _activeBooking!['pickupContactPhone'] as String?;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.outlineVariant),
        boxShadow: const [
          BoxShadow(color: Color(0x1F000000), blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(isParcel ? Icons.inventory_2_rounded : Icons.directions_car_rounded, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  Text(
                    isParcel ? 'Heading to collect Parcel' : 'Heading to Pickup',
                    style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.call, color: Colors.green),
                onPressed: () {
                  final phone = isParcel ? pickupPhone : (_activeBooking!['passengerPhone'] as String?);
                  final name = isParcel ? (pickupName ?? 'Sender') : (_activeBooking!['passengerName'] as String? ?? 'Customer');
                  _callContact(phone, name);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Pickup Address:',
            style: GoogleFonts.robotoMono(fontSize: 10, color: AppTheme.onSurfaceVariant, fontWeight: FontWeight.w600),
          ),
          Text(
            _activeBooking!['pickup'] as String? ?? '',
            style: GoogleFonts.inter(fontSize: 14, color: AppTheme.onSurfaceColor, fontWeight: FontWeight.w500),
          ),
          if (isParcel) ...[
            if (pickupHouse != null && pickupHouse.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'House/Bldg: $pickupHouse',
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.onSurfaceVariant),
              ),
            ],
            if (pickupName != null && pickupName.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Sender: $pickupName ($pickupPhone)',
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.onSurfaceColor, fontWeight: FontWeight.w600),
              ),
            ],
          ] else ...[
            const SizedBox(height: 6),
            Text(
              'Customer: ${_activeBooking!['passengerName'] ?? 'Customer'}',
              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.onSurfaceColor, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 16),
          SlidingButton(
            text: 'Slide to Arrive',
            onSlideComplete: () {
              BookingManager().driverArrived();
              setState(() {
                _driverStatus = 'arrived_pickup';
                _otpError = '';
                _otpTextController.clear();
              });
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => _showPilotCancelDialog('accepted'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
              child: const Text('Cancel Ride', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArrivedPickupPanel() {
    if (_activeBooking == null) return const SizedBox();

    final bool isParcel = _activeBooking!['serviceType'] == 'parcel';
    final pickupName = _activeBooking!['pickupContactName'] as String?;
    final pickupPhone = _activeBooking!['pickupContactPhone'] as String?;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.primaryColor),
        boxShadow: const [
          BoxShadow(color: Color(0x1F000000), blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.pin_rounded, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  Text(
                    isParcel ? 'Enter Sender OTP' : 'Enter Customer OTP',
                    style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.call, color: Colors.green),
                onPressed: () {
                  final phone = isParcel ? pickupPhone : (_activeBooking!['passengerPhone'] as String?);
                  final name = isParcel ? (pickupName ?? 'Sender') : (_activeBooking!['passengerName'] as String? ?? 'Customer');
                  _callContact(phone, name);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isParcel
                ? 'Ask the sender ($pickupName) for the 4-digit code: ${_activeBooking?['otp'] ?? '4921'}'
                : 'Ask the customer (${_activeBooking?['passengerName'] ?? 'Customer'}) for the 4-digit start code: ${_activeBooking?['otp'] ?? '4921'} (Backdoor is 4921)',
            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _otpTextController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            decoration: InputDecoration(
              hintText: 'Enter 4-digit OTP',
              errorText: _otpError.isNotEmpty ? _otpError : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              counterText: '',
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _verifyPickupOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(
                isParcel ? 'Start Delivery' : 'Start Trip',
                style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => _showPilotCancelDialog('arrived'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
              child: const Text('Cancel Ride', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOnTripPanel() {
    if (_activeBooking == null) return const SizedBox();

    final bool isParcel = _activeBooking!['serviceType'] == 'parcel';
    final dropHouse = _activeBooking!['dropHouse'] as String?;
    final dropName = _activeBooking!['dropContactName'] as String?;
    final dropPhone = _activeBooking!['dropContactPhone'] as String?;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.outlineVariant.withValues()),
        boxShadow: const [
          BoxShadow(color: Color(0x1F000000), blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(isParcel ? Icons.local_shipping_rounded : Icons.navigation_rounded, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  Text(
                    isParcel ? 'Delivering Parcel' : 'Ongoing Trip',
                    style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.call, color: Colors.green),
                onPressed: () {
                  final phone = isParcel ? dropPhone : (_activeBooking!['passengerPhone'] as String?);
                  final name = isParcel ? (dropName ?? 'Recipient') : (_activeBooking!['passengerName'] as String? ?? 'Customer');
                  _callContact(phone, name);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Drop Location:',
            style: GoogleFonts.robotoMono(fontSize: 10, color: AppTheme.onSurfaceVariant, fontWeight: FontWeight.w600),
          ),
          Text(
            _activeBooking!['drop'] as String? ?? '',
            style: GoogleFonts.inter(fontSize: 14, color: AppTheme.onSurfaceColor, fontWeight: FontWeight.w500),
          ),
          if (isParcel) ...[
            if (dropHouse != null && dropHouse.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'House/Bldg: $dropHouse',
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.onSurfaceVariant),
              ),
            ],
            if (dropName != null && dropName.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Recipient: $dropName ($dropPhone)',
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.onSurfaceColor, fontWeight: FontWeight.w600),
              ),
            ],
          ],
          const SizedBox(height: 16),
          SlidingButton(
            text: isParcel ? 'Slide to Complete Delivery' : 'Slide to Complete Ride',
            onSlideComplete: () {
              BookingManager().completeRide();
              setState(() {
                _driverStatus = 'payment_pending';
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentPendingPanel() {
    if (_activeBooking == null) return const SizedBox();

    final bool isParcel = _activeBooking!['serviceType'] == 'parcel';
    final paymentOption = _activeBooking!['paymentOption'] as String?;
    final priceStr = _activeBooking!['price'] as String;

    String paymentPrompt = 'Collect payment from customer: $priceStr';
    if (isParcel) {
      if (paymentOption == 'Pay at Pickup') {
        final pickupName = _activeBooking!['pickupContactName'] as String? ?? 'Sender';
        paymentPrompt = 'Collect payment from $pickupName at Pickup: $priceStr';
      } else if (paymentOption == 'Pay at Drop') {
        final dropName = _activeBooking!['dropContactName'] as String? ?? 'Recipient';
        paymentPrompt = 'Collect payment from $dropName at Drop: $priceStr';
      } else {
        paymentPrompt = 'Collect payment: $priceStr ($paymentOption)';
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.primaryColor, width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0x2B000000), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isParcel ? 'Delivery Completed' : 'Ride Completed',
            style: GoogleFonts.hankenGrotesk(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
          ),
          const SizedBox(height: 4),
          Text(
            paymentPrompt,
            style: GoogleFonts.inter(fontSize: 13, color: AppTheme.onSurfaceVariant, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Text(
            'SELECT PAYMENT MODE',
            style: GoogleFonts.robotoMono(fontSize: 10, color: AppTheme.primaryColor, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          
          _buildPaymentOptionTile(
            title: 'Cash Payment',
            icon: Icons.money_rounded,
            color: Colors.green,
            onTap: () => _confirmPayment('Cash'),
          ),
          const SizedBox(height: 8),
          _buildPaymentOptionTile(
            title: 'UPI Transfer',
            icon: Icons.qr_code_scanner_rounded,
            color: Colors.blue,
            onTap: () => _confirmPayment('UPI'),
          ),
          const SizedBox(height: 8),
          _buildPaymentOptionTile(
            title: 'Razorpay UPI Payment',
            icon: Icons.payment_rounded,
            color: Colors.indigo,
            badge: 'ONLINE',
            onTap: () {
              if (_activeBooking != null) {
                final priceStr = _activeBooking!['price'] as String;
                final cleanStr = priceStr.replaceAll(RegExp(r'[^0-9.]'), '');
                final double fareVal = double.tryParse(cleanStr) ?? 150.0;
                RazorpayGateway.show(
                  context,
                  amount: fareVal,
                  description: 'StayDriv Ride Payment (Razorpay Collect)',
                  onSuccess: () => _confirmPayment('UPI via Razorpay'),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentOptionTile({
    required String title,
    required IconData icon,
    required Color color,
    String? badge,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.outlineVariant.withValues()),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.onSurfaceColor),
              ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge,
                  style: GoogleFonts.robotoMono(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios, size: 12, color: AppTheme.outlineColor),
          ],
        ),
      ),
    );
  }
}

// Vector city map grid painter
class MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final roadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    final outlinePaint = Paint()
      ..color = AppTheme.outlineVariant.withOpacity(0.4)
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()..color = AppTheme.primaryColor;
    
    // Draw some stylized roads (straight lines representing a city grid)
    final roads = [
      [Offset(0, size.height * 0.3), Offset(size.width, size.height * 0.3)],
      [Offset(0, size.height * 0.75), Offset(size.width, size.height * 0.75)],
      [Offset(size.width * 0.3, 0), Offset(size.width * 0.3, size.height)],
      [Offset(size.width * 0.75, 0), Offset(size.width * 0.75, size.height)],
      [Offset(0, size.height * 0.1), Offset(size.width, size.height * 0.9)], // diagonal road
    ];

    // Draw outline and then road surface to look like real vector map
    for (var r in roads) {
      canvas.drawLine(r[0], r[1], outlinePaint);
    }
    for (var r in roads) {
      canvas.drawLine(r[0], r[1], roadPaint);
    }

    // Draw active drivers as small blue dots
    final drivers = [
      Offset(size.width * 0.3, size.height * 0.3),
      Offset(size.width * 0.3, size.height * 0.6),
      Offset(size.width * 0.75, size.height * 0.2),
      Offset(size.width * 0.5, size.height * 0.5),
      Offset(size.width * 0.2, size.height * 0.75),
    ];

    for (var d in drivers) {
      canvas.drawCircle(d, 6, dotPaint);
      canvas.drawCircle(d, 12, Paint()..color = AppTheme.primaryAccent.withOpacity(0.2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SlidingButton extends StatefulWidget {
  final String text;
  final VoidCallback onSlideComplete;
  final Color? trackColor;
  final Color? handleColor;
  final Color? textColor;

  const SlidingButton({
    super.key,
    required this.text,
    required this.onSlideComplete,
    this.trackColor,
    this.handleColor,
    this.textColor,
  });

  @override
  State<SlidingButton> createState() => _SlidingButtonState();
}

class _SlidingButtonState extends State<SlidingButton> with SingleTickerProviderStateMixin {
  double _position = 0.0;
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _isCompleted = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _animation = Tween<double>(begin: 0.0, end: 0.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details, double maxDistance) {
    if (_isCompleted) return;
    setState(() {
      _position += details.primaryDelta!;
      if (_position < 0.0) _position = 0.0;
      if (_position > maxDistance) _position = maxDistance;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details, double maxDistance) {
    if (_isCompleted) return;
    if (_position > maxDistance * 0.85) {
      setState(() {
        _position = maxDistance;
        _isCompleted = true;
      });
      widget.onSlideComplete();
    } else {
      _animation = Tween<double>(begin: _position, end: 0.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOut),
      )..addListener(() {
          setState(() {
            _position = _animation.value;
          });
        });
      _controller.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double trackWidth = constraints.maxWidth;
        const double handleSize = 56.0;
        final double maxDistance = trackWidth - handleSize - 4.0;

        return Container(
          width: trackWidth,
          height: 60,
          decoration: BoxDecoration(
            color: widget.trackColor ?? AppTheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.3)),
          ),
          child: Stack(
            children: [
              Center(
                child: Opacity(
                  opacity: (1.0 - (_position / maxDistance)).clamp(0.2, 1.0),
                  child: Text(
                    widget.text,
                    style: GoogleFonts.hankenGrotesk(
                      color: widget.textColor ?? AppTheme.onSurfaceColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: _position + 2,
                top: 2,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) => _onHorizontalDragUpdate(details, maxDistance),
                  onHorizontalDragEnd: (details) => _onHorizontalDragEnd(details, maxDistance),
                  child: Container(
                    width: handleSize,
                    height: handleSize,
                    decoration: BoxDecoration(
                      color: widget.handleColor ?? AppTheme.primaryColor,
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.double_arrow_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InAppCallOverlay extends StatefulWidget {
  final String phoneNumber;
  final String contactName;

  const _InAppCallOverlay({
    required this.phoneNumber,
    required this.contactName,
  });

  @override
  State<_InAppCallOverlay> createState() => _InAppCallOverlayState();
}

class _InAppCallOverlayState extends State<_InAppCallOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  Timer? _durationTimer;
  int _elapsedSeconds = 0;
  bool _isConnected = false;
  Timer? _connectTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // Simulate connection after 3 seconds
    _connectTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _isConnected = true;
        });
        _startDurationTimer();
      }
    });
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _elapsedSeconds++;
        });
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _connectTimer?.cancel();
    _durationTimer?.cancel();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final int minutes = seconds ~/ 60;
    final int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: const Color(0xFF111422), // Sleek premium dark mode card
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isConnected ? 'ONGOING CALL' : 'CALLING CUSTOMER',
              style: GoogleFonts.robotoMono(
                color: _isConnected ? Colors.green : AppTheme.primaryColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            // Pulsing Call Avatar
            Stack(
              alignment: Alignment.center,
              children: [
                ...List.generate(3, (index) {
                  return AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final double progress = (_pulseController.value + (index / 3)) % 1.0;
                      return Container(
                        width: 90 + (progress * 70),
                        height: 90 + (progress * 70),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (_isConnected ? Colors.green : AppTheme.primaryColor)
                              .withOpacity((1.0 - progress) * 0.24),
                        ),
                      );
                    },
                  );
                }),
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: _isConnected
                          ? [Colors.green.shade600, Colors.green.shade400]
                          : [AppTheme.primaryColor, AppTheme.primaryAccent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Icon(
                    Icons.call,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              widget.contactName,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isConnected
                  ? _formatDuration(_elapsedSeconds)
                  : widget.phoneNumber,
              style: GoogleFonts.robotoMono(
                fontSize: 14,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 36),
            // End Call Button
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.errorColor,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x4DBA1A1A),
                      blurRadius: 16,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.call_end,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
