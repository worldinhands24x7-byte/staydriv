import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:staydriv_app/core/js_stub.dart'
    if (dart.library.js) 'dart:js' as js;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
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
import '../../../core/pilot_ride_ringtone_service.dart';
import '../../../core/twilio_service.dart';
import '../../../core/socket_service.dart';
import '../../ride_selection/screens/ride_selection_screen.dart';
import '../../activity_history/screens/activity_screen.dart';
import '../../food_ordering/screens/food_home_screen.dart';
import '../../food_ordering/screens/pilot_food_delivery_card.dart';
import '../../activity_history/screens/ride_details_screen.dart';
import '../../onboarding/screens/login_screen.dart';
import '../../onboarding/screens/register_screen.dart';
import '../../live_tracking/screens/live_tracking_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/wake_lock_service.dart';
import '../../../core/location_share_service.dart';
import 'admin_pilot_registration_screen.dart';
import '../../wallet/screens/payment_wallet_screen.dart';
import '../../wallet/screens/pilot_earnings_screen.dart';
import '../../live_tracking/widgets/ride_completed_payment_panel.dart';
import '../widgets/pilot_payment_pending_panel.dart';
import '../widgets/share_staydriv_sheet.dart';
import '../widgets/console_switcher_sheet.dart';
import '../../navigation/screens/pilot_navigation_screen.dart';
import '../../promotions/widgets/promotional_banner_carousel.dart';
import '../../navigation/services/navigation_engine.dart';
import '../../support/screens/support_category_screen.dart';
import '../../support/screens/my_support_tickets_screen.dart';
import '../../support/services/support_service.dart';
import '../../../core/call_masking_service.dart';
import '../../../core/floating_widget_service.dart';
import '../../notifications/widgets/home_notification_bar.dart';
import '../../notifications/screens/notifications_center_sheet.dart';
import '../../notifications/services/notification_inbox_service.dart';

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
  late String _activeUserRole;
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
  double _pilotSalary = 0.0;
  double _customerCancellationCharge = 0.0;
  double _customerWalletBalance = 0.0;

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
  bool _rideServiceEnabled = true;
  bool _foodServiceEnabled = true;
  String _driverStatus = 'offline'; // 'offline', 'online', 'incoming_request', 'heading_to_pickup', 'arrived_pickup', 'on_trip', 'payment_pending'
  bool _isPilotApproved = false;
  bool _isApprovalDialogShowing = false;
  String _pilotStatus = 'pending';
  bool _bookingAccessEnabled = false;
  String _bookingAccessStatus = 'disabled';
  String _bookingAccessReason = '';
  String _dailyPlanStatus = 'none';
  String? _dailyPlanExpiresAt;
  double _dailyPlanTodayEarnings = 0.0;
  bool _isDutyToggling = false;
  int _lastDutyToggleTimestamp = 0;

  void _logDutyAudit({
    required String source,
    required bool prevOnline,
    required bool newOnline,
    required bool isUserAction,
    String reason = '',
  }) {
    debugPrint('[DUTY_AUDIT] source=$source | prevOnline=$prevOnline -> newOnline=$newOnline | isUserAction=$isUserAction | reason=$reason | timestamp=${DateTime.now().toIso8601String()}');
  }
  String _pilotApplicationId = '';
  String _pilotRejectionReason = '';
  String _pilotCorrectionNotes = '';
  String _pilotVehiclePlate = '';
  String _pilotVehicleColor = '';
  bool _isEditingVehicle = false;
  final TextEditingController _vehiclePlateController = TextEditingController();
  final TextEditingController _vehicleColorController = TextEditingController();
  String _driverPhone = '';
  String? _newDriverLicenseFront;
  String? _newDriverLicenseFrontName;
  String? _newDriverLicenseFrontSize;
  String? _newDriverLicenseBack;
  String? _newDriverLicenseBackName;
  String? _newDriverLicenseBackSize;
  final TextEditingController _newDriverPhoneController = TextEditingController();
  final List<TextEditingController> _newDriverOtpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _newDriverOtpFocusNodes = List.generate(6, (_) => FocusNode());
  bool _isSendingDriverOtp = false;
  bool _isDriverOtpSent = false;
  int _driverOtpCountdown = 0;
  Timer? _driverOtpTimer;
  bool _isVerifyingDriverOtp = false;
  Map<String, dynamic>? _activeBooking;
  bool _isPilotNavigationOpen = false;
  double _totalEarnings = 1250.0;
  bool _isAdvanceWithdrawn = false;
  List<Map<String, dynamic>> _completedRides = [];
  Timer? _bookingTimer;

  // Pilot Partner Chat state
  final List<Map<String, String>> _pilotChatMessages = [];
  final TextEditingController _pilotChatController = TextEditingController();
  bool _isPilotChatSheetOpen = false;
  int _pilotUnreadChatCount = 0;
  void Function(void Function())? _pilotModalSetState;
  
  // Incoming Request logic
  bool _isAppInForeground = true;
  int _incomingRequestCountdown = 30;
  Timer? _countdownTimer;
  String? _currentIncomingBookingId;

  LatLng? _driverMapCenter = const LatLng(17.4834, 78.3871); // Default: Hyderabad
  GoogleMapController? _driverMapController;
  GoogleMapController? _customerMapController;
  final TextEditingController _otpTextController = TextEditingController();
  final TextEditingController _adminSearchController = TextEditingController();
  String _otpError = '';
  List<LatLng> _driverRoutePoints = [];

  StreamSubscription<Map<String, dynamic>?>? _bookingSub;
  StreamSubscription<LatLng>? _driverLocationSub;
  StreamSubscription<String>? _rideStatusSub;
  StreamSubscription<Position>? _gpsSub;

  // Admin & Staff state
  Stream<QuerySnapshot>? _adminBookingsStream;
  Stream<QuerySnapshot>? _adminDriversStream;

  Timer? _adminMongoPollTimer;
  List<Map<String, dynamic>> _mongoAdminBookings = [];
  List<Map<String, dynamic>> _mongoAdminDrivers = [];
  List<Map<String, dynamic>> _mongoAdminCustomers = [];
  List<Map<String, dynamic>> _adminComplaints = [];
  List<Map<String, dynamic>> _adminRefunds = [];
  List<Map<String, dynamic>> _adminPayments = [];
  bool _isAdminLoading = false;
  String _bookingStatusFilter = 'all'; // 'all', 'completed', 'cancelled', 'active'
  int _adminSelectedTab = 0; // 0: Overview/Bookings, 1: Pending Pilot Approvals, 2: Blocked Pilots, 3: Blocked Customers, 4: Misbehave Pilot, 5: Misbehave Customer, 6: Customer Refunds, 7: Pilot Refunds, 8: Complaints, 9: All Customers, 10: All Pilots, 11: Payments & Invoices
  String _complaintFilterStatus = 'all'; // 'all', 'pending', 'resolved'
  Map<String, dynamic>? _selectedDriverForDocApproval;
  String _adminSearchQuery = '';
  final Set<String> _approvingUids = {};
  final Set<String> _rejectingUids = {};

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
    WakeLockService.setBookingActionListener(_handleBookingNotificationAction);
    NotificationInboxService().init(
      role: widget.userRole,
      phone: widget.phoneNumber,
    );
    _activeUserRole = widget.userRole;
    _editableUserName = widget.userName;
    if (_activeUserRole == 'Customer' && _editableUserName.toLowerCase().contains('pilot')) {
      _editableUserName = 'StayDriv Customer';
    }
    _driverMapCenter = BookingManager().driverLatLng;
    if (widget.selectedVehicle != null) {
      _selectedVehicle = widget.selectedVehicle!;
    }
    if (_activeUserRole == 'Driver' || _activeUserRole == 'Customer') {
      _loadCompletedRides();
      _loadProfileData();
    }
    if (_activeUserRole == 'Driver') {
      _initPilotApprovalState();
      _initServicePreferences();
      _startGpsTracking();
      _subscribeToBookingManager();
    }
    if (_activeUserRole == 'Customer') {
      _startCustomerGpsTracking();
      _subscribeToCustomerBookingManager();
      BookingManager().restoreAndSyncActiveBooking();
    }
    _initLocationSharing();
    if (widget.userRole == 'Admin' || widget.userRole == 'Staff') {
      if (_isFirebaseInitialized) {
        _adminBookingsStream = FirebaseFirestore.instance
            .collection('bookings')
            .orderBy('createdAt', descending: true)
            .limit(50)
            .snapshots();
        _adminDriversStream = FirebaseFirestore.instance
            .collection('partners')
            .snapshots();
      } else {
        _fetchAdminDataOnce();
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

    // Initialize Socket and real-time chat message listeners
    SocketService().initSocket();
    SocketService().addCustomerMessageListener(_handlePilotIncomingRideMessage);
    SocketService().addRideMessageListener(_handlePilotIncomingRideMessage);
    SocketService().addRideChatHistoryListener(_handlePilotRideChatHistory);
    SocketService().addPilotVerificationListener(_handleRealtimePilotApproval);
    SocketService().addPilotBookingAccessListener(_handlePilotBookingAccessChanged);
    SocketService().addPilotDailyPlanListener(_handlePilotDailyPlanUpdated);
    _fetchDailyPlanAndBookingAccess();
    if (widget.userRole == 'Admin' || widget.userRole == 'Staff') {
      SocketService().addAdminPilotsUpdatedListener(_handleAdminPilotsUpdated);
    }
    final initialBId = _activeBooking?['bookingId']?.toString() ??
        _activeBooking?['id']?.toString() ??
        _activeBooking?['_id']?.toString();
    if (initialBId != null && initialBId.isNotEmpty) {
      SocketService().joinRide(initialBId);
      _fetchPilotRideChatHistory(initialBId);
    }
  }

  void _handleAdminPilotsUpdated(Map<String, dynamic> data) {
    if (!mounted) return;
    debugPrint('[Admin] Received real-time admin_pilots_updated event: $data');
    _fetchAdminDataOnce();
  }

  void _initPilotApprovalState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedApproved = prefs.getBool('is_pilot_approved') ?? 
          (prefs.getString('pilot_application_status') == 'APPROVED');
      final cachedStatus = prefs.getString('pilot_application_status')?.toLowerCase() ?? 
          (cachedApproved ? 'approved' : 'pending');
      final cachedBookingAccess = prefs.getBool('pilot_booking_access_enabled') ?? false;
      final rawCachedReason = prefs.getString('pilot_booking_access_reason') ?? '';
      final cachedDutyOnline = prefs.getBool('pilot_duty_online') ?? false;
      if (mounted) {
        setState(() {
          _isPilotApproved = cachedApproved;
          _bookingAccessEnabled = cachedBookingAccess;
          _bookingAccessStatus = cachedBookingAccess ? 'enabled' : 'disabled';
          _bookingAccessReason = (cachedBookingAccess || rawCachedReason.toLowerCase().contains('eligible for 100% earnings')) ? '' : rawCachedReason;
          if (rawCachedReason.toLowerCase().contains('eligible for 100% earnings')) {
            prefs.remove('pilot_booking_access_reason');
          }
          _pilotStatus = cachedStatus;
          if (cachedBookingAccess && cachedApproved && cachedDutyOnline) {
            _isOnline = true;
            _driverStatus = 'online';
            BookingManager().setDriverOnline(true);
            _logDutyAudit(source: 'APP_STARTUP_CACHE_RESTORE', prevOnline: false, newOnline: true, isUserAction: false);
          }
        });
      }
    } catch (_) {}
  }

  void _initServicePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ridePref = prefs.getBool('pilot_ride_service_enabled') ?? true;
      final foodPref = prefs.getBool('pilot_food_service_enabled') ?? true;
      if (mounted) {
        setState(() {
          _rideServiceEnabled = ridePref;
          _foodServiceEnabled = foodPref;
        });
      }
      BookingManager().setServicePreferences(
        ride: ridePref,
        food: foodPref,
      );
    } catch (_) {}
  }

  void _updateServicePreference({bool? ride, bool? food}) {
    HapticFeedback.mediumImpact();
    setState(() {
      if (ride != null) _rideServiceEnabled = ride;
      if (food != null) _foodServiceEnabled = food;
    });
    BookingManager().setServicePreferences(ride: ride, food: food);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final updatedRide = ride ?? _rideServiceEnabled;
    final updatedFood = food ?? _foodServiceEnabled;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Service Preferences Updated:\n• Ride Booking: ${updatedRide ? "ACTIVE (ON)" : "PAUSED (OFF)"}\n• Food Delivery: ${updatedFood ? "ACTIVE (ON)" : "PAUSED (OFF)"}',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12),
        ),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _handleRealtimePilotApproval(Map<String, dynamic> data) async {
    if (!mounted) return;

    if (widget.userRole == 'Admin' || widget.userRole == 'Staff') {
      final dataUid = (data['uid'] ?? data['pilotId'] ?? '').toString();
      final dataPhone = (data['phone'] ?? '').toString();
      final isAppr = data['approved'] == true || data['isApproved'] == true || (data['status']?.toString().toUpperCase() == 'APPROVED');
      setState(() {
        final idx = _mongoAdminDrivers.indexWhere((d) => (d['uid'] == dataUid || (d['phone'] != null && dataPhone.isNotEmpty && d['phone'].toString().contains(dataPhone))));
        if (idx != -1) {
          _mongoAdminDrivers[idx]['approved'] = isAppr;
          _mongoAdminDrivers[idx]['isApproved'] = isAppr;
          _mongoAdminDrivers[idx]['status'] = isAppr ? 'approved' : 'rejected';
          _mongoAdminDrivers[idx]['applicationStatus'] = isAppr ? 'APPROVED' : 'REJECTED';
          if (data['reason'] != null || data['rejectionReason'] != null) {
            _mongoAdminDrivers[idx]['rejectionReason'] = data['reason'] ?? data['rejectionReason'];
          }
        }
      });
      _fetchAdminDataOnce();
      return;
    }

    final currentPhone = widget.phoneNumber.replaceAll(RegExp(r'\D'), '').trim();
    final dataPhone = (data['phone'] ?? '').toString().replaceAll(RegExp(r'\D'), '').trim();
    final currentUid = FirebaseService().currentUid ?? '';
    final dataUid = (data['uid'] ?? data['pilotId'] ?? '').toString();

    // Check if event belongs to this pilot (or matches current phone / UID)
    final isMe = (currentPhone.isNotEmpty && dataPhone.isNotEmpty && (currentPhone.endsWith(dataPhone) || dataPhone.endsWith(currentPhone))) ||
        (currentUid.isNotEmpty && dataUid.isNotEmpty && currentUid == dataUid);

    // Strictly ignore if this event is not for the current pilot
    if (!isMe) return;

    final isApproved = data['approved'] == true || data['isApproved'] == true || (data['status']?.toString().toUpperCase() == 'APPROVED');
    final newStatus = data['status']?.toString().toLowerCase() ?? (isApproved ? 'approved' : 'pending');

    final wasAlreadyApproved = _isPilotApproved;

    final prefs = await SharedPreferences.getInstance();
    final hasSeenDialog = prefs.getBool('has_seen_pilot_approval_dialog') ?? false;

    if (mounted) {
      setState(() {
        _isPilotApproved = isApproved;
        _pilotStatus = newStatus;
        if (data['rejectionReason'] != null) {
          _pilotRejectionReason = data['rejectionReason'].toString();
        }
        if (data['correctionNotes'] != null) {
          _pilotCorrectionNotes = data['correctionNotes'].toString();
        }
      });
    }

    if (isApproved) {
      prefs.setBool('is_pilot_approved', true);
      prefs.setString('pilot_application_status', 'APPROVED');

      // Only show popup celebration if pilot was NOT previously approved, has NOT seen it yet, and no dialog is currently showing
      if (!wasAlreadyApproved && !hasSeenDialog && !_isApprovalDialogShowing) {
        _isApprovalDialogShowing = true;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.verified, color: Colors.white, size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Registration Approved ✓ You can now go online and accept bookings.',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              backgroundColor: Color(0xFF16A34A),
              duration: Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );

          showDialog(
            context: context,
            barrierDismissible: true,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(color: Color(0xFFDCFCE7), shape: BoxShape.circle),
                    child: const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 40),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Registration Approved ✓',
                    style: GoogleFonts.hankenGrotesk(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Your Pilot account has been approved.\nYou can now go online and accept bookings.',
                    style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF475569), height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        prefs.setBool('has_seen_pilot_approval_dialog', true);
                        _isApprovalDialogShowing = false;
                        if (Navigator.canPop(ctx)) {
                          Navigator.pop(ctx);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Start Driving / Go Online', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ).then((_) {
            prefs.setBool('has_seen_pilot_approval_dialog', true);
            _isApprovalDialogShowing = false;
          });
        }
      }
    } else if (!isApproved && newStatus == 'rejected') {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(color: Color(0xFFFEE2E2), shape: BoxShape.circle),
                child: const Icon(Icons.cancel_outlined, color: Color(0xFFDC2626), size: 40),
              ),
              const SizedBox(height: 16),
              Text(
                'Application Rejected ✕',
                style: GoogleFonts.hankenGrotesk(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Reason: ${_pilotRejectionReason.isNotEmpty ? _pilotRejectionReason : "Documents could not be verified."}',
                style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFFDC2626), fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  // ==========================================
  // PILOT ₹20 DAILY PLAN & ADMIN BOOKING ACCESS CONTROL
  // ==========================================

  Future<void> _fetchDailyPlanAndBookingAccess() async {
    if (_activeUserRole != 'Driver') return;
    final uid = FirebaseService().currentUid ?? widget.phoneNumber;
    if (uid.isEmpty) return;
    try {
      final baseUrl = NetworkConfig.backendUrl;
      final cleanPhone = widget.phoneNumber.replaceAll(RegExp(r'\D'), '');
      final last10 = cleanPhone.length >= 10 ? cleanPhone.substring(cleanPhone.length - 10) : cleanPhone;
      final effectiveUid = (uid.isNotEmpty && !uid.startsWith('+')) ? uid : (last10.isNotEmpty ? last10 : uid);
      BookingManager().setDriverCustomUid(effectiveUid);

      final uri = Uri.parse('$baseUrl/api/pilot/daily-plan/${Uri.encodeComponent(effectiveUid)}');
      final res = await ApiClient().get(uri);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && mounted) {
          final isEnabled = data['bookingAccessStatus']?.toString().toLowerCase() == 'enabled' || data['bookingAccessEnabled'] == true || data['adminBookingEnabled'] == true || (data['bookingAccess'] is Map && (data['bookingAccess']['enabled'] == true || data['bookingAccess']['status']?.toString().toLowerCase() == 'enabled'));
          final rawBookingReason = (data['bookingAccessReason'] ?? '').toString();
          final cleanBookingReason = (isEnabled || rawBookingReason.toLowerCase().contains('eligible for 100% earnings')) ? '' : rawBookingReason;
          final planStatus = (data['planStatus'] ?? 'none').toString().toLowerCase();

          setState(() {
            _bookingAccessStatus = isEnabled ? 'enabled' : 'disabled';
            _bookingAccessEnabled = isEnabled;
            _bookingAccessReason = cleanBookingReason;
            _dailyPlanStatus = planStatus;
            _dailyPlanExpiresAt = data['expiresAt']?.toString();
            _dailyPlanTodayEarnings = (data['totalEarningsToday'] as num?)?.toDouble() ?? 0.0;
          });

          SharedPreferences.getInstance().then((prefs) {
            prefs.setBool('pilot_booking_access_enabled', isEnabled);
            prefs.setString('pilot_booking_access_reason', cleanBookingReason);
          });

          // Reconcile duty state with authoritative safety & permission rules.
          // Explicit human toggle is the authoritative source of Duty ON/OFF.
          // Background fetches only enforce legitimate restrictions (Admin disabled, unpaid plan, unapproved).
          // If the pilot is eligible, preserve the pilot's human-selected choice!
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          final isRecentlyToggled = _isDutyToggling || (nowMs - _lastDutyToggleTimestamp < 5000);

          if (!isRecentlyToggled) {
            final isEligible = isEnabled && planStatus == 'paid' && _isPilotApproved;
            if (!isEligible && _isOnline) {
              final reason = !isEnabled
                  ? (cleanBookingReason.isNotEmpty ? cleanBookingReason : 'Admin disabled booking access')
                  : (planStatus != 'paid' ? 'Daily ₹20 plan unpaid/expired' : 'Account verification pending');
              _logDutyAudit(source: 'PERIODIC_REFRESH_RESTRICTION', prevOnline: _isOnline, newOnline: false, isUserAction: false, reason: reason);
              setState(() {
                _isOnline = false;
                _driverStatus = 'offline';
              });
              BookingManager().setDriverOnline(false);
              SharedPreferences.getInstance().then((prefs) => prefs.setBool('pilot_duty_online', false));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[HomeScreen] Error fetching daily plan status: $e');
    }
  }

  void _handlePilotBookingAccessChanged(Map<String, dynamic> data) {
    if (_activeUserRole != 'Driver') return;
    if (!mounted) return;
    final uid = FirebaseService().currentUid ?? widget.phoneNumber;
    final targetUid = (data['pilotId'] ?? data['uid'])?.toString();
    final targetPhone = (data['phone'] ?? data['pilotPhone'])?.toString().replaceAll(RegExp(r'\D'), '');
    final cleanPhone = widget.phoneNumber.replaceAll(RegExp(r'\D'), '');
    final last10 = cleanPhone.length >= 10 ? cleanPhone.substring(cleanPhone.length - 10) : cleanPhone;

    bool isTargetMatch = false;
    if (targetUid != null && targetUid.isNotEmpty) {
      if (targetUid == uid || targetUid.contains(uid) || uid.contains(targetUid)) {
        isTargetMatch = true;
      }
      if (last10.isNotEmpty && targetUid.contains(last10)) {
        isTargetMatch = true;
      }
    }
    if (!isTargetMatch && targetPhone != null && targetPhone.isNotEmpty && last10.isNotEmpty) {
      if (targetPhone.contains(last10) || last10.contains(targetPhone)) {
        isTargetMatch = true;
      }
    }
    if (!isTargetMatch) return;

    final hasAccessField = data.containsKey('bookingAccessEnabled') || data.containsKey('bookingAccessStatus') || data.containsKey('status') || data.containsKey('enabled') || data.containsKey('bookingAccess');
    final isEnabled = hasAccessField ? (data['bookingAccessEnabled'] == true || data['bookingAccessStatus']?.toString().toLowerCase() == 'enabled' || data['status']?.toString().toLowerCase() == 'enabled' || data['enabled'] == true || (data['bookingAccess'] is Map && (data['bookingAccess']['enabled'] == true || data['bookingAccess']['status']?.toString().toLowerCase() == 'enabled'))) : _bookingAccessEnabled;
    final rawReason = data['bookingAccessReason']?.toString() ?? data['disabledReason']?.toString() ?? data['reason']?.toString() ?? '';
    final reason = (isEnabled || rawReason.toLowerCase().contains('eligible for 100% earnings')) ? '' : rawReason;

    setState(() {
      _bookingAccessEnabled = isEnabled;
      _bookingAccessStatus = isEnabled ? 'enabled' : 'disabled';
      _bookingAccessReason = isEnabled ? '' : reason;
      SharedPreferences.getInstance().then((prefs) {
        prefs.setBool('pilot_booking_access_enabled', isEnabled);
        prefs.setString('pilot_booking_access_reason', isEnabled ? '' : reason);
      });

      // Administrator permission handling:
      // If Admin disables booking access, enforce offline to prevent new assignments.
      // If Admin enables booking access, allow pilot to toggle ON, but do NOT force Duty ON.
      if (!isEnabled && _isOnline) {
        _logDutyAudit(source: 'ADMIN_ACCESS_DISABLED_EVENT', prevOnline: _isOnline, newOnline: false, isUserAction: false, reason: reason);
        _isOnline = false;
        _driverStatus = 'offline';
        BookingManager().setDriverOnline(false);
        SharedPreferences.getInstance().then((prefs) => prefs.setBool('pilot_duty_online', false));
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEnabled
                ? 'Booking Enabled by Admin ✓'
                : 'Your booking access is currently disabled by Admin${reason.isNotEmpty ? ": $reason" : "."}',
          ),
          backgroundColor: isEnabled ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _handlePilotDailyPlanUpdated(Map<String, dynamic> data) {
    if (!mounted) return;
    final uid = FirebaseService().currentUid ?? widget.phoneNumber;
    final targetUid = (data['pilotId'] ?? data['uid'])?.toString();
    final targetPhone = (data['phone'] ?? data['pilotPhone'])?.toString().replaceAll(RegExp(r'\D'), '');
    final cleanPhone = widget.phoneNumber.replaceAll(RegExp(r'\D'), '');
    final last10 = cleanPhone.length >= 10 ? cleanPhone.substring(cleanPhone.length - 10) : cleanPhone;

    bool isTargetMatch = false;
    if (targetUid != null && targetUid.isNotEmpty) {
      if (targetUid == uid || targetUid.contains(uid) || uid.contains(targetUid)) {
        isTargetMatch = true;
      }
      if (last10.isNotEmpty && targetUid.contains(last10)) {
        isTargetMatch = true;
      }
    }
    if (!isTargetMatch && targetPhone != null && targetPhone.isNotEmpty && last10.isNotEmpty) {
      if (targetPhone.contains(last10) || last10.contains(targetPhone)) {
        isTargetMatch = true;
      }
    }
    if (!isTargetMatch) return;
    _fetchDailyPlanAndBookingAccess();
  }

  void _handlePilotIncomingRideMessage(Map<String, dynamic> data) {
    if (!mounted) return;
    final bId = _activeBooking?['bookingId']?.toString() ??
        _activeBooking?['id']?.toString() ??
        _activeBooking?['_id']?.toString() ?? '';
    final msgRideId = (data['bookingId'] ?? data['rideId'])?.toString();

    // Verify message belongs to current active booking
    if (bId.isNotEmpty && msgRideId != null && msgRideId != bId) return;

    final rawRole = data['senderRole']?.toString() ?? 'customer';
    final senderRole = rawRole.toLowerCase() == 'pilot' ? 'pilot' : 'customer';
    final text = (data['message'] ?? data['text'])?.toString() ?? '';
    final messageId = data['messageId']?.toString() ?? '';
    if (text.trim().isEmpty) return;

    // Pilot confirms delivery to customer
    if (senderRole == 'customer' && messageId.isNotEmpty && bId.isNotEmpty) {
      SocketService().acknowledgeDelivery(bookingId: bId, messageId: messageId);
    }

    final timestamp = data['timestamp']?.toString();
    final alreadyExists = _pilotChatMessages.any((m) =>
        (messageId.isNotEmpty && m['messageId'] == messageId) ||
        (m['text'] == text && m['sender'] == senderRole && (timestamp == null || m['timestamp'] == timestamp)));
    if (alreadyExists) return;

    setState(() {
      _pilotChatMessages.add({
        'messageId': messageId,
        'sender': senderRole,
        'text': text,
        'timestamp': timestamp ?? '',
      });
      if (senderRole == 'customer' && !_isPilotChatSheetOpen) {
        _pilotUnreadChatCount++;
      }
    });

    if (_pilotModalSetState != null) {
      _pilotModalSetState!(() {});
    }

    // Display floating in-app notification banner for the pilot
    if (senderRole == 'customer' && !_isPilotChatSheetOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.chat_bubble_rounded, color: Colors.yellowAccent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Customer Message',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.yellowAccent),
                    ),
                    Text(
                      text,
                      style: GoogleFonts.inter(fontSize: 14, color: Colors.white),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'REPLY',
            textColor: Colors.greenAccent,
            onPressed: () {
              final name = _activeBooking?['passengerName'] as String? ?? 'Customer';
              _showPilotChatBottomSheet(name);
            },
          ),
        ),
      );
    }
  }

  void _handlePilotRideChatHistory(Map<String, dynamic> data) {
    if (!mounted) return;
    final messages = data['messages'];
    if (messages is List && messages.isNotEmpty) {
      setState(() {
        _pilotChatMessages.clear();
        for (var item in messages) {
          _pilotChatMessages.add({
            'sender': item['senderRole']?.toString() ?? 'customer',
            'text': item['text']?.toString() ?? '',
            'timestamp': item['timestamp']?.toString() ?? '',
          });
        }
      });
      if (_pilotModalSetState != null) {
        _pilotModalSetState!(() {});
      }
    }
  }

  Future<void> _fetchPilotRideChatHistory(String? rideId) async {
    if (rideId == null || rideId.isEmpty) return;
    try {
      final response = await ApiClient().get(Uri.parse('/api/rides/$rideId/messages'));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true && decoded['messages'] is List) {
          final List list = decoded['messages'];
          if (mounted && list.isNotEmpty) {
            setState(() {
              _pilotChatMessages.clear();
              for (var item in list) {
                _pilotChatMessages.add({
                  'sender': item['senderRole']?.toString() ?? 'customer',
                  'text': item['text']?.toString() ?? '',
                  'timestamp': item['timestamp']?.toString() ?? '',
                });
              }
            });
            if (_pilotModalSetState != null) {
              _pilotModalSetState!(() {});
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[PilotChat] Error fetching chat history: $e');
    }
  }

  void _sendPilotChatMessage(String text) {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;

    final bId = _activeBooking?['bookingId']?.toString() ??
        _activeBooking?['id']?.toString() ??
        _activeBooking?['_id']?.toString() ?? '';

    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    setState(() {
      _pilotChatMessages.add({
        'sender': 'pilot',
        'text': cleanText,
        'timestamp': timestamp,
      });
    });
    _pilotChatController.clear();

    if (bId.isNotEmpty) {
      SocketService().sendRideMessage(
        rideId: bId,
        senderRole: 'pilot',
        text: cleanText,
        senderName: widget.userName,
      );
    }
  }

  void _showPilotChatBottomSheet([String? customerName]) {
    final effectiveCustomerName = customerName ?? (_activeBooking?['passengerName'] as String?) ?? 'Customer';
    setState(() {
      _isPilotChatSheetOpen = true;
      _pilotUnreadChatCount = 0;
    });

    final bId = _activeBooking?['bookingId']?.toString() ??
        _activeBooking?['id']?.toString() ??
        _activeBooking?['_id']?.toString();
    if (bId != null && bId.isNotEmpty) {
      _fetchPilotRideChatHistory(bId);
      SocketService().markMessagesRead(bookingId: bId);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            _pilotModalSetState = setModalState;
            void sendMsg(String text) {
              if (text.trim().isEmpty) return;
              _sendPilotChatMessage(text);
              setModalState(() {});
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: SizedBox(
                height: 480,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.green.shade700,
                              radius: 18,
                              child: const Icon(Icons.person, color: Colors.white, size: 20),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Chat with $effectiveCustomerName',
                                  style: GoogleFonts.hankenGrotesk(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  'Customer • Active Ride',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: Colors.green,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Divider(),
                    Expanded(
                      child: _pilotChatMessages.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.chat_bubble_outline_rounded, size: 40, color: Colors.grey.shade400),
                                  const SizedBox(height: 8),
                                  Text(
                                    'No messages yet. Send a quick update!',
                                    style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: _pilotChatMessages.length,
                              itemBuilder: (context, index) {
                                final msg = _pilotChatMessages[index];
                                final isMe = msg['sender'] == 'pilot';
                                return Align(
                                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(vertical: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isMe ? AppTheme.primaryColor : const Color(0xFFF0F2FF),
                                      borderRadius: BorderRadius.circular(16).copyWith(
                                        bottomRight: isMe ? const Radius.circular(0) : null,
                                        bottomLeft: !isMe ? const Radius.circular(0) : null,
                                      ),
                                    ),
                                    child: Text(
                                      msg['text'] ?? '',
                                      style: GoogleFonts.inter(
                                        color: isMe ? Colors.white : Colors.black87,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              label: Text("🚗 On my way!", style: GoogleFonts.inter(fontSize: 12)),
                              backgroundColor: const Color(0xFFF3F5FF),
                              onPressed: () => sendMsg("🚗 On my way!"),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              label: Text("📍 I've arrived at pickup", style: GoogleFonts.inter(fontSize: 12)),
                              backgroundColor: const Color(0xFFF3F5FF),
                              onPressed: () => sendMsg("📍 I've arrived at pickup"),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              label: Text("⏳ Reaching in 2 mins", style: GoogleFonts.inter(fontSize: 12)),
                              backgroundColor: const Color(0xFFF3F5FF),
                              onPressed: () => sendMsg("⏳ Reaching in 2 mins"),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              label: Text("👍 Okay, got it!", style: GoogleFonts.inter(fontSize: 12)),
                              backgroundColor: const Color(0xFFF3F5FF),
                              onPressed: () => sendMsg("👍 Okay, got it!"),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _pilotChatController,
                            decoration: InputDecoration(
                              hintText: 'Message customer...',
                              hintStyle: GoogleFonts.inter(fontSize: 14),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: const BorderSide(color: AppTheme.outlineVariant),
                              ),
                            ),
                            onSubmitted: (text) => sendMsg(text),
                          ),
                        ),
                        const SizedBox(width: 8),
                        CircleAvatar(
                          backgroundColor: AppTheme.primaryColor,
                          radius: 22,
                          child: IconButton(
                            icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                            onPressed: () => sendMsg(_pilotChatController.text),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      if (mounted) {
        setState(() {
          _isPilotChatSheetOpen = false;
          _pilotModalSetState = null;
        });
      }
    });
  }

  void _initLocationSharing() {
    LocationShareService.instance.init(
      onLocationReceived: (SharedLocationResult loc) {
        if (!mounted) return;
        _handleIncomingSharedLocation(loc);
      },
    );
  }

  Future<void> _switchAppRole(String newRole) async {
    if (_activeUserRole == newRole) return;
    setState(() {
      _activeUserRole = newRole;
      if (newRole == 'Driver') {
        _selectedVehicle = widget.selectedVehicle ?? _selectedVehicle;
      }
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_role', newRole);
    } catch (_) {}

    if (newRole == 'Driver') {
      _loadProfileData();
    } else if (newRole == 'Customer') {
      _startCustomerGpsTracking();
      _subscribeToCustomerBookingManager();
      BookingManager().restoreAndSyncActiveBooking();
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(newRole == 'Driver' ? Icons.two_wheeler_rounded : Icons.person, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                newRole == 'Driver' ? 'Switched to Pilot Partner Mode!' : 'Switched to Customer Mode!',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          backgroundColor: newRole == 'Driver' ? const Color(0xFF1B7C3E) : const Color(0xFF1D4ED8),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _handleIncomingSharedLocation(SharedLocationResult loc) async {
    if (!mounted) return;

    // 1. If currently in Pilot/Driver mode, automatically switch to Customer mode for booking
    if (_activeUserRole != 'Customer') {
      await _switchAppRole('Customer');
    }

    // 2. If it's a StayDriv ride deep link (from WhatsApp or web with pickup/drop pre-populated)
    if (loc.isStayDrivRideLink) {
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => RideSelectionScreen(
              serviceType: loc.serviceType,
              userName: widget.userName,
              phoneNumber: widget.phoneNumber,
              initialPickupAddress: loc.pickupAddress,
              initialPickupLatLng: loc.pickupLatLng,
              initialDropAddress: loc.dropAddress,
              initialDropLatLng: loc.dropLatLng,
            ),
          ),
        );
      }
      return;
    }

    // 3. Otherwise, it is a Google Maps pin, geo: URI, or generic location share
    LocationShareService.showSharedLocationPrompt(
      context: context,
      location: loc,
      onLocationSelected: ({required bool isDrop}) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => RideSelectionScreen(
              serviceType: 'bike',
              userName: widget.userName,
              phoneNumber: widget.phoneNumber,
              initialDropAddress: isDrop ? loc.title : null,
              initialDropLatLng: isDrop ? loc.coordinates : null,
              initialPickupAddress: !isDrop ? loc.title : null,
              initialPickupLatLng: !isDrop ? loc.coordinates : null,
            ),
          ),
        );
      },
    );
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

  Future<void> _fetchAdminDataOnce() async {
    if (_mongoAdminBookings.isEmpty && _mongoAdminDrivers.isEmpty) {
      if (mounted) {
        setState(() {
          _isAdminLoading = true;
        });
      }
    }
    try {
      final baseUrl = NetworkConfig.backendUrl;

      final bResponse = await ApiClient().get(Uri.parse('$baseUrl/api/admin/bookings?limit=200'), retry: false);
      if (bResponse.statusCode == 200) {
        final bData = jsonDecode(bResponse.body);
        if (bData['success'] == true && bData['bookings'] != null) {
          _mongoAdminBookings = List<Map<String, dynamic>>.from(bData['bookings']);
        }
      }

      final dResponse = await ApiClient().get(Uri.parse('$baseUrl/api/admin/drivers'), retry: false);
      if (dResponse.statusCode == 200) {
        final dData = jsonDecode(dResponse.body);
        if (dData['success'] == true && dData['drivers'] != null) {
          _mongoAdminDrivers = List<Map<String, dynamic>>.from(dData['drivers']);
        }
      }

      final cResponse = await ApiClient().get(Uri.parse('$baseUrl/api/admin/customers'), retry: false);
      if (cResponse.statusCode == 200) {
        final cData = jsonDecode(cResponse.body);
        if (cData['success'] == true && cData['customers'] != null) {
          _mongoAdminCustomers = List<Map<String, dynamic>>.from(cData['customers']);
        }
      }

      final cmpResponse = await ApiClient().get(Uri.parse('$baseUrl/api/admin/complaints'), retry: false);
      if (cmpResponse.statusCode == 200) {
        final cmpData = jsonDecode(cmpResponse.body);
        if (cmpData['success'] == true && cmpData['complaints'] != null) {
          _adminComplaints = List<Map<String, dynamic>>.from(cmpData['complaints']);
        }
      }

      final rResponse = await ApiClient().get(Uri.parse('$baseUrl/api/admin/refunds'), retry: false);
      if (rResponse.statusCode == 200) {
        final rData = jsonDecode(rResponse.body);
        if (rData['success'] == true && rData['refunds'] != null) {
          _adminRefunds = List<Map<String, dynamic>>.from(rData['refunds']);
        }
      }

      final pResponse = await ApiClient().get(Uri.parse('$baseUrl/api/admin/payments'), retry: false);
      if (pResponse.statusCode == 200) {
        final pData = jsonDecode(pResponse.body);
        if (pData['success'] == true && pData['payments'] != null) {
          _adminPayments = List<Map<String, dynamic>>.from(pData['payments']);
        }
      }
    } catch (e) {
      debugPrint("Error fetching Admin data: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isAdminLoading = false;
        });
      }
    }
  }

  void _startAdminMongoPolling() {
    _adminMongoPollTimer?.cancel();
    _adminMongoPollTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
      if (!mounted) return;
      await _fetchAdminDataOnce();
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
              final status = (booking['status'] as String? ?? 'completed').toLowerCase();
              if (status != 'completed' && status != 'accepted' && status != 'delivered') {
                continue;
              }
              final isFood = (booking['serviceType'] == 'food' ||
                  booking['isFoodDelivery'] == true ||
                  (booking['vehicle']?.toString().toLowerCase().contains('food') ?? false));

              final priceStr = booking['price'] as String? ?? '₹0';
              final cleanStr = priceStr.replaceAll(RegExp(r'[^0-9.]'), '');
              final priceVal = double.tryParse(cleanStr) ?? 0.0;

              double pEarnings = 0.0;
              if (isFood) {
                pEarnings = booking['pilotEarnings'] != null
                    ? (double.tryParse(booking['pilotEarnings'].toString()) ?? priceVal)
                    : priceVal;
                if (pEarnings <= 0 && booking['originalDeliveryFee'] != null) {
                  pEarnings = double.tryParse(booking['originalDeliveryFee'].toString()) ?? 0.0;
                }
                earnings += (pEarnings > 0 ? pEarnings : (priceVal > 0 ? priceVal : 30.0));
              } else {
                earnings += priceVal * 0.85; // 85% goes to driver, 15% is commission
              }
              
              final vehicle = isFood ? 'Food Delivery' : (booking['vehicle'] as String? ?? 'Bike');
              
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

              final serviceType = isFood
                  ? 'food'
                  : ((vehicle == 'Bike')
                      ? 'bike'
                      : (vehicle == 'Auto'
                          ? 'auto'
                          : (vehicle == 'Car' ? 'car' : 'parcel')));
              
              final title = isFood ? 'StayDriv Food Delivery' : 'StayDriv $vehicle Ride';
              
              final effectivePriceStr = (isFood && widget.userRole == 'Driver' && pEarnings > 0)
                  ? '₹${pEarnings.toStringAsFixed(pEarnings % 1 == 0 ? 0 : 2)}'
                  : priceStr;

              rides.add({
                ...booking,
                'bookingId': booking['bookingId'] ?? booking['id'] ?? booking['_id'] ?? '',
                'date': _formatTimestamp(timestampMs),
                'price': effectivePriceStr,
                'fare': effectivePriceStr,
                'icon': _getVehicleIcon(vehicle),
                'title': title,
                'route': '${booking['pickup'] ?? ''} to ${booking['drop'] ?? ''}',
                'pickup': booking['pickup'] ?? '',
                'drop': booking['drop'] ?? '',
                'distance': booking['distance'] ?? booking['distanceText'] ?? '',
                'duration': booking['duration'] ?? booking['durationText'] ?? '',
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
          ...data,
          'bookingId': doc.id,
          'date': _formatTimestamp(timestamp),
          'price': priceStr,
          'fare': priceStr,
          'icon': _getVehicleIcon(vehicle),
          'title': 'StayDriv $vehicle Ride',
          'route': '${data['pickup'] ?? ''} to ${data['drop'] ?? ''}',
          'pickup': data['pickup'] ?? '',
          'drop': data['drop'] ?? '',
          'distance': data['distance'] ?? data['distanceText'] ?? '',
          'duration': data['duration'] ?? data['durationText'] ?? '',
          'timestamp': timestamp,
          'vehicle': vehicle,
          'serviceType': serviceType,
          'status': 'completed',
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

    // Instantly restore cached documents from local storage for seamless persistence
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _profilePhotoPath ??= prefs.getString('doc_url_photo');
          _photoName ??= prefs.getString('doc_name_photo');
          _photoSize ??= prefs.getString('doc_size_photo');

          _aadhaarFront ??= prefs.getString('doc_url_aadhaarFront');
          _aadhaarFrontName ??= prefs.getString('doc_name_aadhaarFront');
          _aadhaarFrontSize ??= prefs.getString('doc_size_aadhaarFront');

          _aadhaarBack ??= prefs.getString('doc_url_aadhaarBack');
          _aadhaarBackName ??= prefs.getString('doc_name_aadhaarBack');
          _aadhaarBackSize ??= prefs.getString('doc_size_aadhaarBack');

          _licenseFront ??= prefs.getString('doc_url_licenseFront');
          _licenseFrontName ??= prefs.getString('doc_name_licenseFront');
          _licenseFrontSize ??= prefs.getString('doc_size_licenseFront');

          _licenseBack ??= prefs.getString('doc_url_licenseBack');
          _licenseBackName ??= prefs.getString('doc_name_licenseBack');
          _licenseBackSize ??= prefs.getString('doc_size_licenseBack');

          _rcFront ??= prefs.getString('doc_url_rcFront');
          _rcFrontName ??= prefs.getString('doc_name_rcFront');
          _rcFrontSize ??= prefs.getString('doc_size_rcFront');

          _rcBack ??= prefs.getString('doc_url_rcBack');
          _rcBackName ??= prefs.getString('doc_name_rcBack');
          _rcBackSize ??= prefs.getString('doc_size_rcBack');

          _fitness ??= prefs.getString('doc_url_fitness');
          _fitnessName ??= prefs.getString('doc_name_fitness');
          _fitnessSize ??= prefs.getString('doc_size_fitness');

          _permit ??= prefs.getString('doc_url_permit');
          _permitName ??= prefs.getString('doc_name_permit');
          _permitSize ??= prefs.getString('doc_size_permit');
          final cachedPlate = prefs.getString('vehicle_plate') ?? prefs.getString('pilot_reg_vehicle_number');
          if (cachedPlate != null && cachedPlate.isNotEmpty && cachedPlate != 'TS 09 SD 1234') {
            _pilotVehiclePlate = cachedPlate;
            _vehiclePlateController.text = cachedPlate;
            BookingManager().setDriverVehiclePlate(cachedPlate);
          }
          final cachedColor = prefs.getString('vehicle_color') ?? prefs.getString('pilot_reg_vehicle_color');
          if (cachedColor != null && cachedColor.isNotEmpty) {
            _pilotVehicleColor = cachedColor;
            _vehicleColorController.text = cachedColor;
            BookingManager().setDriverVehicleModelColor(cachedColor);
          }
        });
      }
    } catch (prefErr) {
      debugPrint("Error loading cached documents: $prefErr");
    }

    setState(() {
      _isLoadingProfile = true;
    });
    try {
      final role = widget.userRole == 'Driver' ? 'partner' : 'customer';
      final doc = await FirebaseService().getProfile(role, uid);
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null) {
          final prefs = await SharedPreferences.getInstance();
          setState(() {
            if (data['photo'] != null || data['photoUrl'] != null) {
              _profilePhotoPath = data['photo'] ?? data['photoUrl'];
              prefs.setString('doc_url_photo', _profilePhotoPath!);
            }
            if (data['aadhaarFront'] != null) {
              _aadhaarFront = data['aadhaarFront'];
              prefs.setString('doc_url_aadhaarFront', _aadhaarFront!);
            }
            if (data['aadhaarBack'] != null) {
              _aadhaarBack = data['aadhaarBack'];
              prefs.setString('doc_url_aadhaarBack', _aadhaarBack!);
            }
            if (data['licenseFront'] != null) {
              _licenseFront = data['licenseFront'];
              prefs.setString('doc_url_licenseFront', _licenseFront!);
            }
            if (data['licenseBack'] != null) {
              _licenseBack = data['licenseBack'];
              prefs.setString('doc_url_licenseBack', _licenseBack!);
            }
            if (data['rcFront'] != null) {
              _rcFront = data['rcFront'];
              prefs.setString('doc_url_rcFront', _rcFront!);
            }
            if (data['rcBack'] != null) {
              _rcBack = data['rcBack'];
              prefs.setString('doc_url_rcBack', _rcBack!);
            }
            if (data['fitness'] != null) {
              _fitness = data['fitness'];
              prefs.setString('doc_url_fitness', _fitness!);
            }
            if (data['permit'] != null) {
              _permit = data['permit'];
              prefs.setString('doc_url_permit', _permit!);
            }
            if (data['salary'] != null) {
              _pilotSalary = (data['salary'] as num).toDouble();
            }
            if (data['pendingCancellationCharge'] != null) {
              _customerCancellationCharge = (data['pendingCancellationCharge'] as num).toDouble();
            }
            if (data['name'] != null && data['name'].toString().isNotEmpty) {
              final loadedName = data['name'].toString();
              if (_activeUserRole == 'Customer' && loadedName.toLowerCase().contains('pilot')) {
                _editableUserName = 'StayDriv Customer';
              } else {
                _editableUserName = loadedName;
              }
            }
            if (data['email'] != null && data['email'].toString().isNotEmpty) {
              _emailAddress = data['email'];
            }
            if (data['dob'] != null && data['dob'].toString().isNotEmpty) {
              _dateOfBirth = data['dob'];
            }
            if (data['status'] != null) {
              _pilotStatus = data['status'].toString().toLowerCase();
            }
            if (data['applicationId'] != null) {
              _pilotApplicationId = data['applicationId'].toString();
            }
            final isAppr = (data['approved'] == true || data['isApproved'] == true || _pilotStatus == 'approved');
            _isPilotApproved = isAppr;
            if (isAppr) {
              _pilotStatus = 'approved';
              prefs.setString('pilot_application_status', 'APPROVED');
              prefs.setBool('is_pilot_approved', true);
            }
            if (data['rejectionReason'] != null) {
              _pilotRejectionReason = data['rejectionReason'].toString();
            }
            if (data['correctionNotes'] != null) {
              _pilotCorrectionNotes = data['correctionNotes'].toString();
            }
            final rawPlt = data['vehiclePlate']?.toString() ?? data['vehicleNumber']?.toString();
            if (rawPlt != null && rawPlt.isNotEmpty && rawPlt != 'TS 09 SD 1234') {
              _pilotVehiclePlate = rawPlt.trim().toUpperCase();
              _vehiclePlateController.text = _pilotVehiclePlate;
              prefs.setString('vehicle_plate', _pilotVehiclePlate);
              BookingManager().setDriverVehiclePlate(_pilotVehiclePlate);
            }
            final rawColor = data['vehicleColor']?.toString() ?? data['vehicleModelColor']?.toString();
            if (rawColor != null && rawColor.isNotEmpty) {
              _pilotVehicleColor = rawColor.trim();
              _vehicleColorController.text = _pilotVehicleColor;
              prefs.setString('vehicle_color', _pilotVehicleColor);
              BookingManager().setDriverVehicleModelColor(_pilotVehicleColor);
            }
            final rawVType = data['vehicleType']?.toString();
            if (rawVType != null && rawVType.isNotEmpty) {
              _selectedVehicle = rawVType;
              prefs.setString('selected_vehicle', rawVType);
              BookingManager().setDriverVehicle(rawVType);
            }
          });
        }
      }
      if (widget.userRole == 'Driver' && !_isPilotApproved) {
        final cleanPhone = widget.phoneNumber.replaceAll(RegExp(r'\D'), '').trim();
        if (cleanPhone.length >= 10) {
          try {
            final baseUrl = NetworkConfig.backendUrl;
            final sRes = await ApiClient().get(Uri.parse('$baseUrl/api/pilot/application-status?phone=$cleanPhone'), retry: false).timeout(const Duration(seconds: 4));
            if (sRes.statusCode == 200) {
              final sData = jsonDecode(sRes.body);
              if (sData is Map && sData['success'] == true && sData['found'] == true) {
                final st = (sData['status'] ?? '').toString().toUpperCase();
                final appr = sData['approved'] == true || sData['isApproved'] == true || st == 'APPROVED';
                final prefs = await SharedPreferences.getInstance();
                setState(() {
                  _pilotApplicationId = (sData['applicationId'] ?? _pilotApplicationId).toString();
                  if (appr) {
                    _isPilotApproved = true;
                    _pilotStatus = 'approved';
                    prefs.setBool('is_pilot_approved', true);
                    prefs.setString('pilot_application_status', 'APPROVED');
                  } else {
                    _pilotStatus = st.toLowerCase();
                    if (sData['pilot'] is Map) {
                      _pilotRejectionReason = sData['pilot']['rejectionReason']?.toString() ?? '';
                      _pilotCorrectionNotes = sData['pilot']['correctionNotes']?.toString() ?? '';
                    }
                  }
                });
              }
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint("Error loading profile: $e");
    } finally {
      setState(() {
        _isLoadingProfile = false;
      });
      _loadCustomerWallet();
      _loadPilotEarnings();
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

  bool _isUploadingDocument = false;

  Future<void> _pickAndUploadImage(String type) async {
    if (_isUploadingDocument) return;
    _isUploadingDocument = true;
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.first;
      final ext = (file.extension ?? '').toLowerCase();
      final isPdf = (ext == 'pdf');

      if (ext != 'jpg' && ext != 'jpeg' && ext != 'png' && ext != 'pdf') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid format. Please select a JPG, JPEG, PNG, or PDF file.'),
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

      // Max 10 MB limit
      if (bytes.length > 10 * 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File exceeds 10 MB limit. Please select a smaller document.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final sizeKb = bytes.length / 1024;
      final sizeStr = sizeKb >= 1024
          ? '${(sizeKb / 1024).toStringAsFixed(2)} MB'
          : '${sizeKb.toStringAsFixed(1)} KB';
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
                    color: isPdf ? Colors.red.shade50 : AppTheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.outlineVariant),
                  ),
                  child: isPdf
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.picture_as_pdf_rounded, size: 58, color: Colors.red.shade700),
                            const SizedBox(height: 8),
                            Text('PDF Document', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red.shade900)),
                            const SizedBox(height: 4),
                            Text('Portable Document Format (PDF)', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600)),
                          ],
                        )
                      : ClipRRect(
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
                  Text('Uploading document to MongoDB storage...', style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      );

      final uid = FirebaseService().currentUid ?? 'pilot_user';
      final docUrl = await FirebaseService().uploadProfilePictureToMongo(
        uid,
        bytes,
        ext,
        documentType: type,
        originalFileName: fileName,
      );

      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      // Persist locally for instant availability across app sessions
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('doc_url_$type', docUrl);
        await prefs.setString('doc_name_$type', fileName);
        await prefs.setString('doc_size_$type', sizeStr);
      } catch (prefErr) {
        debugPrint("Error caching document locally: $prefErr");
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
      } else if (type == 'driverLicenseFront') {
        setState(() {
          _newDriverLicenseFront = docUrl;
          _newDriverLicenseFrontName = fileName;
          _newDriverLicenseFrontSize = sizeStr;
        });
      } else if (type == 'driverLicenseBack') {
        setState(() {
          _newDriverLicenseBack = docUrl;
          _newDriverLicenseBackName = fileName;
          _newDriverLicenseBackSize = sizeStr;
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
      final rawErr = e.toString();
      final isHtmlOrFormatError = e is FormatException || rawErr.contains('FormatException') || rawErr.contains('Unexpected character') || rawErr.contains('<html>');
      final cleanMsg = isHtmlOrFormatError ? 'Server returned an unexpected response. Please check your connection and try again.' : rawErr.replaceAll('Exception: ', '').replaceAll('Exception', '').trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(cleanMsg.isNotEmpty ? cleanMsg : 'Upload could not be completed. Please try again.'),
          backgroundColor: Colors.red.shade800,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () => _pickAndUploadImage(type),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingDocument = false;
        });
      } else {
        _isUploadingDocument = false;
      }
    }
  }

  void _handleBookingNotificationAction(String action, String? bookingId) {
    debugPrint('[HomeScreen] Received booking notification action: $action (bookingId: $bookingId)');
    if (!mounted) return;

    if (_currentTabIndex != 0) {
      setState(() {
        _currentTabIndex = 0;
      });
    }

    if (action == 'accept') {
      _acceptBooking();
    } else if (action == 'decline') {
      _directDeclineBooking(reason: 'Declined via notification');
    } else if (action == 'view') {
      WakeLockService.bringAppToForeground();
      final current = BookingManager().activeBooking;
      if (current != null) {
        _handleBookingUpdate(current);
      }
    }
  }

  void _directDeclineBooking({String reason = 'Declined by pilot'}) {
    _stopRinging();
    WakeLockService.dismissIncomingAlert();
    BookingManager().declineBooking();
    if (mounted) {
      setState(() {
        _activeBooking = null;
        _driverStatus = _isOnline ? 'online' : 'offline';
        _currentIncomingBookingId = null;
        _driverRoutePoints = [];
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakeLockService.setBookingActionListener(null);
    _adminMongoPollTimer?.cancel();
    _bookingTimer?.cancel();
    _countdownTimer?.cancel();
    _driverOtpTimer?.cancel();
    _otpTextController.dispose();
    _adminSearchController.dispose();
    _newDriverPhoneController.dispose();
    for (final c in _newDriverOtpControllers) {
      c.dispose();
    }
    for (final f in _newDriverOtpFocusNodes) {
      f.dispose();
    }
    _gpsSub?.cancel();
    _bookingSub?.cancel();
    _driverLocationSub?.cancel();
    _rideStatusSub?.cancel();
    _networkSub?.cancel();
    _successBannerTimer?.cancel();
    _customerFeedbackController.dispose();
    SocketService().removeCustomerMessageListener(_handlePilotIncomingRideMessage);
    SocketService().removeRideMessageListener(_handlePilotIncomingRideMessage);
    SocketService().removeRideChatHistoryListener(_handlePilotRideChatHistory);
    SocketService().removePilotVerificationListener(_handleRealtimePilotApproval);
    SocketService().removePilotBookingAccessListener(_handlePilotBookingAccessChanged);
    SocketService().removePilotDailyPlanListener(_handlePilotDailyPlanUpdated);
    if (widget.userRole == 'Admin' || widget.userRole == 'Staff') {
      SocketService().removeAdminPilotsUpdatedListener(_handleAdminPilotsUpdated);
    }
    _pilotChatController.dispose();
    SocketService().disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isAppInForeground = true;
      WakeLockService.dismissIncomingAlert();
      debugPrint("HomeScreen: App resumed! Force syncing partner status & restoring active booking immediately.");
      // Automatically hide the floating mini-window when user reopens the app
      FloatingWidgetService.hide();
      BookingManager().forceSync();
      SocketService().initSocket();
      if (_activeUserRole == 'Driver') {
        _fetchDailyPlanAndBookingAccess();
      }
      if (widget.userRole == 'Customer') {
        BookingManager().restoreAndSyncActiveBooking();
      } else {
        // Pilot mode: Sync authoritative active booking from backend & local cache on resume
        final effectiveUid = FirebaseService().currentUid ?? widget.userName;
        BookingManager().fetchActivePilotBooking(effectiveUid).then((active) {
          if (mounted && active != null) {
            _handleBookingUpdate(active);
          } else if (mounted) {
            final currentActive = BookingManager().activeBooking;
            if (currentActive != null && (currentActive['status'] == 'searching' || currentActive['status'] == 'incoming' || currentActive['status'] == 'accepted' || currentActive['status'] == 'arrived' || currentActive['status'] == 'started')) {
              _handleBookingUpdate(currentActive);
            }
          }
        });
      }
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      _isAppInForeground = false;
      // 1. Show StayDriv Floating Mini Screen (movable logo & live booking bubble like Rapido/Ola) when minimized
      _syncFloatingMiniScreen(isMinimizing: true);

      // 2. Keep background CPU active and native foreground service running so Android OS doesn't throttle sockets
      if (_isOnline || _activeBooking != null) {
        WakeLockService.acquireWakeLock();
        WakeLockService.startForegroundService(
          title: 'StayDriv Pilot Online',
          message: 'Running in background. Ready for ride requests.',
        );
        SocketService().initSocket();
        BookingManager().forceSync();
      }
    }
  }

  /// Synchronizes live booking data & role info to the StayDriv movable floating widget
  void _syncFloatingMiniScreen({bool isMinimizing = false}) {
    if (kIsWeb) return;

    final isCustomer = widget.userRole == 'Customer';
    final active = _activeBooking ?? BookingManager().activeBooking;

    if (active != null) {
      final status = (active['status'] ?? '').toString().toLowerCase();
      final bookingId = (active['bookingId'] ?? active['id'] ?? active['_id'] ?? '').toString();

      if (status == 'completed' || status == 'cancelled') {
        FloatingWidgetService.hide();
        return;
      }

      String title;
      String subtitle;
      String eta = '';

      if (isCustomer) {
        final pilotName = (active['driverName'] ?? active['pilotName'] ?? 'Pilot Partner').toString();
        final vehicle = (active['vehicleType'] ?? 'Ride').toString();
        final plate = (active['vehiclePlate'] ?? active['vehicleNumber'] ?? '').toString();

        if (status == 'searching') {
          title = 'Finding Pilot...';
          subtitle = 'Connecting with nearby pilots';
        } else if (status == 'accepted') {
          title = 'Pilot Assigned';
          subtitle = '$pilotName • $vehicle ${plate.isNotEmpty ? "($plate)" : ""}';
        } else if (status == 'arrived') {
          title = 'Pilot Arrived!';
          subtitle = '$pilotName is at pickup point';
        } else if (status == 'started' || status == 'in_progress') {
          title = 'Trip in Progress';
          subtitle = 'Heading to destination';
        } else if (status == 'payment_pending') {
          title = 'Ride Ended';
          subtitle = 'Complete payment to finish';
        } else {
          title = 'StayDriv Ride';
          subtitle = 'Active trip in progress';
        }

        if (active['eta'] != null) {
          eta = active['eta'].toString();
        }
      } else {
        // Pilot mode
        final custName = (active['passengerName'] ?? 'Customer').toString();
        final drop = (active['dropAddress'] ?? active['drop'] ?? '').toString();
        final otp = (active['startOtp'] ?? active['otp'] ?? '').toString();

        if (status == 'incoming') {
          title = 'New Booking Alert!';
          subtitle = 'Tap to review & accept request';
        } else if (status == 'accepted') {
          title = 'Pickup Assigned';
          subtitle = custName.isNotEmpty ? 'Customer: $custName' : 'Navigate to pickup point';
        } else if (status == 'arrived') {
          title = 'At Pickup Point';
          subtitle = otp.isNotEmpty ? 'Ask Customer OTP: $otp' : 'Waiting for customer';
        } else if (status == 'started' || status == 'in_progress') {
          title = 'Trip in Progress';
          subtitle = drop.isNotEmpty ? 'Drop: $drop' : 'Heading to destination';
        } else if (status == 'payment_pending') {
          title = 'Payment Pending';
          subtitle = 'Collect fare from customer';
        } else {
          title = 'StayDriv Pilot';
          subtitle = 'Trip active';
        }
      }

      if (isMinimizing) {
        FloatingWidgetService.show(
          role: widget.userRole,
          status: status,
          title: title,
          subtitle: subtitle,
          eta: eta,
          bookingId: bookingId,
          isPilot: !isCustomer,
        );
      } else if (FloatingWidgetService.isFloatingVisible) {
        FloatingWidgetService.update(
          status: status,
          title: title,
          subtitle: subtitle,
          eta: eta,
        );
      }
    } else if (!isCustomer && _isOnline) {
      // Pilot is online waiting for rides
      if (isMinimizing) {
        FloatingWidgetService.show(
          role: 'Pilot',
          status: 'online',
          title: 'StayDriv Pilot Online',
          subtitle: 'Ready to receive ride requests',
          isPilot: true,
        );
      } else if (FloatingWidgetService.isFloatingVisible) {
        FloatingWidgetService.update(
          status: 'online',
          title: 'StayDriv Pilot Online',
          subtitle: 'Ready to receive ride requests',
        );
      }
    } else {
      FloatingWidgetService.hide();
    }
  }

  /// Prompts the user once to enable "Display over other apps" (Floating Mini Screen)
  Future<void> _checkOverlayPermissionPrompt() async {
    if (kIsWeb) return;
    try {
      final canDraw = await FloatingWidgetService.canDrawOverlays();
      if (!canDraw && mounted) {
        final prefs = await SharedPreferences.getInstance();
        final hasPrompted = prefs.getBool('overlay_prompt_shown_v1') ?? false;
        if (!hasPrompted) {
          await prefs.setBool('overlay_prompt_shown_v1', true);
          if (mounted) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.picture_in_picture_alt_rounded, color: AppTheme.primaryColor, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'StayDriv Floating Screen',
                        style: GoogleFonts.hankenGrotesk(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                content: Text(
                  'Keep a movable StayDriv floating logo on screen (similar to Rapido / Ola) to monitor your ride while using other apps.',
                  style: GoogleFonts.inter(fontSize: 13, color: AppTheme.onSurfaceVariant),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('Maybe Later', style: GoogleFonts.inter(color: Colors.grey.shade600)),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      FloatingWidgetService.requestOverlayPermission();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Enable Now'),
                  ),
                ],
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking overlay permission: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDriver = _activeUserRole == 'Driver';

    // We use an IndexedStack to manage the top-level app tabs.
    // For Driver (4 tabs):
    // Index 0: Main Home Dashboard View
    // Index 1: Activity View
    // Index 2: Profile View (Mock)
    // Index 3: Help View (Mock)
    //
    // For Customer (5 tabs):
    // Index 0: Main Home Dashboard View
    // Index 1: Food Order Now View
    // Index 2: Activity View
    // Index 3: Profile View (Mock)
    // Index 4: Help View (Mock)
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _currentTabIndex,
            children: isDriver
                ? [
                    _buildDashboardView(),
                    ActivityScreen(
                      userRole: widget.userRole,
                      totalEarnings: _totalEarnings,
                      completedRides: _completedRides,
                      isAdvanceWithdrawn: _isAdvanceWithdrawn,
                      pilotVehicle: _selectedVehicle,
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
                  ]
                : [
                    _buildDashboardView(),
                    FoodHomeScreen(
                      onBackToHome: () {
                        setState(() {
                          _currentTabIndex = 0;
                        });
                      },
                    ),
                    ActivityScreen(
                      userRole: widget.userRole,
                      totalEarnings: _totalEarnings,
                      completedRides: _completedRides,
                      isAdvanceWithdrawn: _isAdvanceWithdrawn,
                      pilotVehicle: _selectedVehicle,
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
          color: AppTheme.surfaceColor.withOpacity(0.95),
          border: const Border(
            top: BorderSide(color: Color(0x1FC3C6D7), width: 1),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 6.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: isDriver
                  ? [
                      _buildNavItem(0, Icons.home_rounded, 'Home'),
                      _buildNavItem(1, Icons.explore_rounded, 'Activity'),
                      _buildNavItem(2, Icons.person_rounded, 'Profile'),
                      _buildNavItem(3, Icons.help_outline_rounded, 'Help'),
                    ]
                  : [
                      _buildNavItem(0, Icons.home_rounded, 'Home'),
                      _buildNavItem(1, Icons.restaurant_rounded, 'Food Order\nNow', isFood: true),
                      _buildNavItem(2, Icons.explore_rounded, 'Activity'),
                      _buildNavItem(3, Icons.person_rounded, 'Profile'),
                      _buildNavItem(4, Icons.help_outline_rounded, 'Help'),
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

  Widget _buildNavItem(int index, IconData icon, String label, {bool isFood = false}) {
    final isDriver = _activeUserRole == 'Driver';
    final isActive = _currentTabIndex == index;
    final activeColor = isFood ? const Color(0xFFEA580C) : AppTheme.primaryColor;
    final activeBg = isFood ? const Color(0xFFEA580C).withOpacity(0.12) : AppTheme.primaryAccent.withOpacity(0.12);
    final inactiveColor = isFood ? const Color(0xFFEA580C).withOpacity(0.85) : AppTheme.onSurfaceVariant;
    final activityTabIndex = isDriver ? 1 : 2;

    return Expanded(
      child: Semantics(
        label: label.replaceAll('\n', ' '),
        selected: isActive,
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              _currentTabIndex = index;
            });
            if (index == activityTabIndex) {
              _loadCompletedRides();
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            decoration: BoxDecoration(
              color: isActive ? activeBg : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: isActive ? activeColor : inactiveColor,
                  size: isFood ? 25 : 24,
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.robotoMono(
                    fontSize: 10.5,
                    fontWeight: isActive ? FontWeight.w700 : (isFood ? FontWeight.w600 : FontWeight.w500),
                    color: isActive ? activeColor : inactiveColor,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardView() {
    if (_activeUserRole == 'Driver') {
      return _buildDriverDashboardView();
    } else if (_activeUserRole == 'Admin' || _activeUserRole == 'Staff') {
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
                      onTap: () => setState(() => _currentTabIndex = 3),
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
                    
                    // Share StayDriv App & Notifications Trailing
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.hub_outlined, color: AppTheme.primaryColor),
                          tooltip: 'Switch Console (Customer, Pilot, Restaurant, Admin)',
                          onPressed: () => ConsoleSwitcherSheet.show(
                            context,
                            currentRole: _activeUserRole,
                            userPhone: widget.phoneNumber,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.share_rounded, color: AppTheme.primaryColor),
                          tooltip: 'Share StayDriv App',
                          onPressed: () => ShareStayDrivSheet.show(context, isPilot: false),
                        ),
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.notifications_none_rounded, color: AppTheme.onSurfaceColor),
                              tooltip: 'Notifications',
                              onPressed: () {
                                NotificationsCenterSheet.show(context);
                              },
                            ),
                            ValueListenableBuilder<int>(
                              valueListenable: NotificationInboxService().unreadCountNotifier,
                              builder: (context, unreadCount, _) {
                                if (unreadCount == 0) return const SizedBox.shrink();
                                return Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    decoration: const BoxDecoration(
                                      color: AppTheme.errorColor,
                                      shape: BoxShape.circle,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 16,
                                      minHeight: 16,
                                    ),
                                    child: Center(
                                      child: Text(
                                        unreadCount > 9 ? '9+' : '$unreadCount',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
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
                    const SizedBox(height: 12),
                    // 1. Dynamic Promotional Banner, Routine Poster & Advertisement Carousel
                    const PromotionalBannerCarousel(
                      screen: 'home',
                      padding: EdgeInsets.only(bottom: 12.0),
                      height: 168.0,
                    ),
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
            // Persistent / Dynamic In-App Notification Bar in the red-box area above bottom nav
            const HomeNotificationBar(),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 15,
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
                  fontSize: 11,
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Update Profile Photo',
                  style: GoogleFonts.hankenGrotesk(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.camera_alt_rounded, color: AppTheme.primaryColor),
                  ),
                  title: Text('Take Photo / Choose File', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Select photo from Camera or Device (JPG, PNG)'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndUploadImage('photo');
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.account_circle, color: Colors.purple),
                  ),
                  title: Text('Set Official StayDriv Avatar', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Use verified official profile avatar'),
                  onTap: () {
                    setState(() {
                      _profilePhotoPath = 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150';
                    });
                    _updatePartnerProfileOnBackend(photo: _profilePhotoPath);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Profile photo updated successfully!'), backgroundColor: Colors.green),
                    );
                  },
                ),
                if (_profilePhotoPath != null)
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.delete_outline, color: Colors.red),
                    ),
                    title: Text('Remove Photo', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.red)),
                    onTap: () {
                      setState(() {
                        _profilePhotoPath = null;
                      });
                      _updatePartnerProfileOnBackend(photo: '');
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Photo removed'), backgroundColor: Colors.orange),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSingleFieldEditDialog(String label, String initialValue, Function(String) onSave) {
    final controller = TextEditingController(text: initialValue);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Edit $label', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold)),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: label,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final val = controller.text.trim();
                if (val.isNotEmpty) {
                  onSave(val);
                  final prefs = await SharedPreferences.getInstance();
                  if (label == 'Full Name') {
                    await prefs.setString('user_name', val);
                    _updatePartnerProfileOnBackend(name: val);
                  }
                }
                Navigator.pop(context);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$label updated!'), backgroundColor: Colors.green),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Save'),
            ),
          ],
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Edit Personal Details', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dobController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Date of Birth',
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  onTap: () async {
                    DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime(2000, 1, 1),
                      firstDate: DateTime(1940),
                      lastDate: DateTime.now().subtract(const Duration(days: 365 * 16)),
                    );
                    if (picked != null) {
                      dobController.text = "${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}";
                    }
                  },
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
              onPressed: () async {
                final newName = nameController.text.trim().isNotEmpty ? nameController.text.trim() : _editableUserName;
                final newEmail = emailController.text.trim().isNotEmpty ? emailController.text.trim() : 'Not Provided';
                final newDob = dobController.text.trim().isNotEmpty ? dobController.text.trim() : 'Not Provided';
                setState(() {
                  _editableUserName = newName;
                  _emailAddress = newEmail;
                  _dateOfBirth = newDob;
                });
                Navigator.pop(context);

                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('user_name', newName);
                _updatePartnerProfileOnBackend(name: newName);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Profile updated successfully!'), backgroundColor: Colors.green),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showMobileNumberInfoDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
                  child: Icon(Icons.verified_user_rounded, color: Colors.green.shade700, size: 28),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Registered Mobile', style: GoogleFonts.hankenGrotesk(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('+91 ${widget.phoneNumber}', style: GoogleFonts.robotoMono(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, color: Color(0xFF1D4ED8), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This number is OTP-verified. OTP notifications, driver live updates & trip receipts are linked to this mobile.',
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF475569)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E60FF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadCustomerWallet() async {
    final uid = FirebaseService().currentUid;
    if (uid == null) return;
    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/customer/wallet/$uid');
      final res = await ApiClient().get(uri);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && mounted) {
          setState(() {
            _customerWalletBalance = (data['walletBalance'] as num?)?.toDouble() ?? 0.0;
          });
        }
      }
    } catch (e) {
      debugPrint('[WALLET] Error loading customer wallet balance: $e');
    }
  }

  void _openPaymentWalletScreen() async {
    final newBalance = await Navigator.push<double>(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentWalletScreen(initialBalance: _customerWalletBalance),
      ),
    );
    if (newBalance != null && mounted) {
      setState(() {
        _customerWalletBalance = newBalance;
      });
    } else {
      _loadCustomerWallet();
    }
  }

  Future<void> _loadPilotEarnings() async {
    final uid = FirebaseService().currentUid;
    if (uid == null) return;
    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/pilot/wallet/$uid');
      final res = await ApiClient().get(uri);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && mounted) {
          setState(() {
            _pilotSalary = (data['availableBalance'] as num?)?.toDouble() ?? _pilotSalary;
            _totalEarnings = (data['availableBalance'] as num?)?.toDouble() ?? _totalEarnings;
          });
        }
      }
    } catch (e) {
      debugPrint('[PILOT EARNINGS] Error loading pilot salary balance: $e');
    }
  }

  void _openPilotEarningsScreen() async {
    final updatedBal = await Navigator.push<double>(
      context,
      MaterialPageRoute(
        builder: (_) => PilotEarningsScreen(initialBalance: _pilotSalary),
      ),
    );
    if (updatedBal != null && mounted) {
      setState(() {
        _pilotSalary = updatedBal;
      });
    } else {
      _loadPilotEarnings();
    }
    _fetchDailyPlanAndBookingAccess();
  }

  void _showSavedPlacesSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 18),
            Text('Saved Places', style: GoogleFonts.hankenGrotesk(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.home_rounded, color: Color(0xFF1E60FF)),
              title: Text('Home Address', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
              subtitle: const Text('Add your home address for 1-tap booking'),
              trailing: const Icon(Icons.add_circle_outline, color: Color(0xFF1E60FF)),
              onTap: () {
                Navigator.pop(ctx);
                _showSingleFieldEditDialog('Home Address', '', (val) {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.work_rounded, color: Colors.orange),
              title: Text('Work / Office', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
              subtitle: const Text('Add your workplace address'),
              trailing: const Icon(Icons.add_circle_outline, color: Colors.orange),
              onTap: () {
                Navigator.pop(ctx);
                _showSingleFieldEditDialog('Workplace Address', '', (val) {});
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAppSettingsSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 18),
              Text('App Preferences & Settings', style: GoogleFonts.hankenGrotesk(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.notifications_active_outlined, color: Color(0xFF1E60FF)),
                title: Text('Push Notifications', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
                subtitle: const Text('Receive ride arrival & trip alerts'),
                value: true,
                onChanged: (val) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(val ? 'Notifications enabled' : 'Notifications muted'), duration: const Duration(seconds: 1)),
                  );
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.near_me_outlined, color: Colors.green),
                title: Text('Precise GPS High-Accuracy', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
                subtitle: const Text('Ensures closest driver matching'),
                value: true,
                onChanged: (val) {},
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.wifi_tethering, color: Colors.purple),
                title: Text('Backend Server & Network', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
                subtitle: const Text('Configure IP or Cloudflare tunnel'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  _showNetworkSettingsDialog();
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.privacy_tip_outlined, color: Colors.blueAccent),
                title: Text('Account Deletion & Data Privacy', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
                subtitle: const Text('Request account closure & data erasure'),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () {
                  Navigator.pop(ctx);
                  _openAccountDeletionPage();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openAccountDeletionPage() async {
    const url = 'https://dk60tgl9yds4p.cloudfront.net/delete-account';
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Error launching account deletion page: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not open browser. Link copied to clipboard.'),
            action: SnackBarAction(
              label: 'OK',
              onPressed: () {},
            ),
          ),
        );
        Clipboard.setData(const ClipboardData(text: url));
      }
    }
  }

  Future<void> _handleLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.logout_rounded, color: Color(0xFFDC2626)),
            const SizedBox(width: 8),
            Text('Confirm Logout', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text('Are you sure you want to log out of StayDriv?', style: GoogleFonts.inter(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Logout'),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('is_logged_in');
      await prefs.remove('mock_uid');
      await prefs.remove('saved_active_booking');
      BookingManager().clearBooking();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  Future<void> _savePilotVehicleDetails() async {
    final plate = _vehiclePlateController.text.trim().toUpperCase();
    final color = _vehicleColorController.text.trim();

    if (plate.isEmpty && color.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter Vehicle Number or Color/Model')),
      );
      return;
    }

    setState(() {
      if (plate.isNotEmpty) _pilotVehiclePlate = plate;
      if (color.isNotEmpty) _pilotVehicleColor = color;
      _isEditingVehicle = false;
    });

    final prefs = await SharedPreferences.getInstance();
    if (plate.isNotEmpty) {
      await prefs.setString('vehicle_plate', plate);
      BookingManager().setDriverVehiclePlate(plate);
    }
    if (color.isNotEmpty) {
      await prefs.setString('vehicle_color', color);
      BookingManager().setDriverVehicleModelColor(color);
    }

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uid = FirebaseService().currentUid ?? prefs.getString('mock_uid') ?? widget.phoneNumber;
      final updateUrl = Uri.parse('$baseUrl/api/partner/update');

      await ApiClient().post(
        updateUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': uid,
          'vehiclePlate': _pilotVehiclePlate,
          'vehicleNumber': _pilotVehiclePlate,
          'vehicleColor': _pilotVehicleColor,
          'vehicleModelColor': _pilotVehicleColor,
          'vehicleType': _selectedVehicle,
          'phone': widget.phoneNumber,
        }),
        retry: true,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(child: Text('Vehicle details saved & synced to Admin Console & Customers!')),
              ],
            ),
            backgroundColor: const Color(0xFF1B7C3E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error syncing vehicle update: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Vehicle saved locally. Network sync will retry: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _switchRole(String targetRole) async {
    if (_activeUserRole == targetRole) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Already in $targetRole mode'),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', targetRole);
    if (targetRole == 'Driver') {
      await prefs.setBool('is_driver', true);
    }
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HomeScreen(
            userName: targetRole == 'Customer' ? 'StayDriv Customer' : 'Pilot Partner',
            userRole: targetRole,
            phoneNumber: widget.phoneNumber,
            selectedVehicle: _selectedVehicle,
          ),
        ),
      );
    }
  }

  Future<void> _openAdminConsole() async {
    final urls = [
      'http://localhost:5173/',
      'http://localhost:3000/admin',
    ];
    for (final u in urls) {
      try {
        final uri = Uri.parse(u);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {}
    }
    if (kIsWeb) {
      try {
        js.context.callMethod('open', ['http://localhost:5173/', '_blank']);
      } catch (_) {}
    }
  }

  Future<void> _openDualSplitScreen() async {
    const url = 'http://localhost:3000/split.html';
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}
    if (kIsWeb) {
      try {
        js.context.callMethod('open', [url, '_blank']);
      } catch (_) {}
    }
  }

  void _startDriverOtpTimer() {
    _driverOtpTimer?.cancel();
    setState(() => _driverOtpCountdown = 30);
    _driverOtpTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_driverOtpCountdown > 1) {
          _driverOtpCountdown--;
        } else {
          _driverOtpCountdown = 0;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _handleGetDriverOtp() async {
    final phone = _newDriverPhoneController.text.trim();
    if (phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid 10-digit mobile number')),
      );
      return;
    }

    setState(() => _isSendingDriverOtp = true);
    try {
      final baseUrl = NetworkConfig.backendUrl;
      final res = await ApiClient().post(
        Uri.parse('$baseUrl/api/auth/send-driver-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        setState(() {
          _isDriverOtpSent = true;
          _isSendingDriverOtp = false;
        });
        _startDriverOtpTimer();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'] ?? 'OTP sent successfully to +91 $phone'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() => _isSendingDriverOtp = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'] ?? 'Failed to send OTP. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isSendingDriverOtp = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Network error sending OTP: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleSaveDriverDetails() async {
    final phone = _newDriverPhoneController.text.trim();
    if (phone.isEmpty || phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid 10-digit mobile number')),
      );
      return;
    }

    if (_newDriverLicenseFront == null || _newDriverLicenseBack == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload both Driving License - Front and Back')),
      );
      return;
    }

    final otp = _newDriverOtpControllers.map((c) => c.text.trim()).join();
    if (otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the 6-digit OTP received on driver mobile')),
      );
      return;
    }

    setState(() => _isVerifyingDriverOtp = true);

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final prefs = await SharedPreferences.getInstance();
      final uid = FirebaseService().currentUid ?? prefs.getString('mock_uid') ?? widget.phoneNumber;

      final res = await ApiClient().post(
        Uri.parse('$baseUrl/api/partner/update-driver'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': uid,
          'phone': widget.phoneNumber,
          'driverPhone': phone,
          'otp': otp,
          'driverLicenseFront': _newDriverLicenseFront,
          'driverLicenseBack': _newDriverLicenseBack,
        }),
      );

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        setState(() {
          _driverPhone = phone;
          _isVerifyingDriverOtp = false;
        });
        await prefs.setString('driver_phone', phone);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('New driver verified and details updated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() => _isVerifyingDriverOtp = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'] ?? 'Failed to verify driver OTP. Please check code.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isVerifyingDriverOtp = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating driver: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  bool _isCategorySelected(String category) {
    final cur = _selectedVehicle.toLowerCase();
    switch (category) {
      case 'Bike':
        return cur.contains('bike') || cur.contains('scooty') || cur.contains('motorcycle');
      case 'Auto':
        return cur.contains('auto') || cur.contains('rickshaw');
      case 'Car':
        return cur.contains('car') || cur.contains('sedan') || cur.contains('suv') || cur.contains('hatchback');
      case 'Mini Truck':
        return cur.contains('mini truck') || cur.contains('parcel');
      case 'Heavy Truck':
        return cur.contains('heavy truck');
      default:
        return false;
    }
  }

  void _onSelectVehicleCategory(String category) async {
    String actual = 'Bike';
    switch (category) {
      case 'Bike':
        actual = 'Bike';
        break;
      case 'Auto':
        actual = 'Auto Rickshaw';
        break;
      case 'Car':
        actual = 'Hatchback Car';
        break;
      case 'Mini Truck':
        actual = 'Mini Truck';
        break;
      case 'Heavy Truck':
        actual = 'Heavy Truck';
        break;
    }
    setState(() => _selectedVehicle = actual);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_vehicle', actual);
    BookingManager().setDriverVehicle(actual);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Vehicle Category selected: $category ($actual)'),
          backgroundColor: const Color(0xFF1B7C3E),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildVehicleCard(String title, IconData icon, String subtitle) {
    final bool isSelected = _isCategorySelected(title);

    return InkWell(
      onTap: () => _onSelectVehicleCategory(title),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 95,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF1D4ED8) : const Color(0xFFE2E8F0),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected ? const Color(0xFF1D4ED8).withOpacity(0.12) : Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF1D4ED8) : const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 22,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? const Color(0xFF1D4ED8) : AppTheme.onSurfaceColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: GoogleFonts.inter(
                fontSize: 9,
                color: isSelected ? const Color(0xFF2563EB) : Colors.grey.shade500,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Select Vehicle Type',
              style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Text(
                '5 Categories',
                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF1D4ED8)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              _buildVehicleCard('Bike', Icons.two_wheeler_rounded, '2-Wheeler'),
              const SizedBox(width: 10),
              _buildVehicleCard('Auto', Icons.electric_rickshaw_rounded, '3-Wheeler'),
              const SizedBox(width: 10),
              _buildVehicleCard('Car', Icons.directions_car_rounded, '4-Wheeler'),
              const SizedBox(width: 10),
              _buildVehicleCard('Mini Truck', Icons.local_shipping_rounded, 'Goods'),
              const SizedBox(width: 10),
              _buildVehicleCard('Heavy Truck', Icons.fire_truck_rounded, 'Heavy'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVehicleIdentificationCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isEditingVehicle ? const Color(0xFFDC2626) : const Color(0xFFE2E8F0),
          width: _isEditingVehicle ? 2.0 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.badge_outlined,
                size: 16,
                color: _isEditingVehicle ? const Color(0xFFDC2626) : AppTheme.primaryColor,
              ),
              const SizedBox(width: 6),
              Text(
                'VEHICLE IDENTIFICATION',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: _isEditingVehicle ? const Color(0xFFDC2626) : Colors.grey.shade700,
                ),
              ),
              const Spacer(),
              if (_isEditingVehicle)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'EDITING',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFDC2626),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (!_isEditingVehicle) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFDC2626).withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Row(
                      children: [
                        Text(
                          'VEH NO: ',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFFDC2626),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _pilotVehiclePlate.isNotEmpty ? _pilotVehiclePlate : 'Not Set',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _pilotVehiclePlate.isNotEmpty ? AppTheme.onSurfaceColor : Colors.grey.shade500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1.5,
                    height: 24,
                    color: const Color(0xFFDC2626).withOpacity(0.5),
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  Expanded(
                    flex: 5,
                    child: Row(
                      children: [
                        Text(
                          'COLOR: ',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFFDC2626),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _pilotVehicleColor.isNotEmpty ? _pilotVehicleColor : 'Not Set',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _pilotVehicleColor.isNotEmpty ? AppTheme.onSurfaceColor : Colors.grey.shade500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  flex: 5,
                  child: TextFormField(
                    controller: _vehiclePlateController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'VEH NO (Plate)',
                      labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFDC2626)),
                      hintText: 'TS 09 EA 1234',
                      hintStyle: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
                      ),
                    ),
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 5,
                  child: TextFormField(
                    controller: _vehicleColorController,
                    decoration: InputDecoration(
                      labelText: 'COLOR / MODEL',
                      labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFDC2626)),
                      hintText: 'Black / Red / White',
                      hintStyle: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
                      ),
                    ),
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDriverReplacementConsole() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_add_alt_1_rounded, size: 18, color: Color(0xFFDC2626)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'REPLACE / UPDATE/MODIFY NEW DRIVER DETAILS',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: const Color(0xFFDC2626),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Upload new driver license and verify mobile number via OTP to update active driver assigned to vehicle.',
            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600),
          ),
          const Divider(height: 20),

          _buildDocUploadTile(
            'Driving License - Front',
            _newDriverLicenseFront,
            'driverLicenseFront',
            _newDriverLicenseFrontName,
            _newDriverLicenseFrontSize,
          ),
          _buildDocUploadTile(
            'Driving License - Back',
            _newDriverLicenseBack,
            'driverLicenseBack',
            _newDriverLicenseBackName,
            _newDriverLicenseBackSize,
          ),
          const SizedBox(height: 8),

          Text(
            'Mobile Number',
            style: GoogleFonts.hankenGrotesk(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _newDriverPhoneController,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  decoration: InputDecoration(
                    counterText: '',
                    prefixText: '+91 ',
                    prefixStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.black87),
                    hintText: 'Driver Mobile Number',
                    hintStyle: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade400),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 42,
                child: ElevatedButton(
                  onPressed: (_isSendingDriverOtp || _driverOtpCountdown > 0) ? null : _handleGetDriverOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: _isSendingDriverOtp
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(
                          _driverOtpCountdown > 0 ? '${_driverOtpCountdown}s' : 'GET OTP',
                          style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Text(
            'Enter 6-Digit OTP',
            style: GoogleFonts.hankenGrotesk(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (index) {
              return SizedBox(
                width: 44,
                height: 48,
                child: TextFormField(
                  controller: _newDriverOtpControllers[index],
                  focusNode: _newDriverOtpFocusNodes[index],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  style: GoogleFonts.robotoMono(fontSize: 18, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    counterText: '',
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFDC2626), width: 2),
                    ),
                  ),
                  onChanged: (val) {
                    if (val.isNotEmpty && index < 5) {
                      _newDriverOtpFocusNodes[index + 1].requestFocus();
                    } else if (val.isEmpty && index > 0) {
                      _newDriverOtpFocusNodes[index - 1].requestFocus();
                    }
                  },
                ),
              );
            }),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _newDriverPhoneController.clear();
                      for (final c in _newDriverOtpControllers) {
                        c.clear();
                      }
                      setState(() {
                        _newDriverLicenseFront = null;
                        _newDriverLicenseBack = null;
                        _isDriverOtpSent = false;
                      });
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 18, color: Color(0xFFDC2626)),
                    label: Text(
                      'EDIT',
                      style: GoogleFonts.hankenGrotesk(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 0.8,
                        color: const Color(0xFFDC2626),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFDC2626), width: 1.8),
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: _isVerifyingDriverOtp ? null : _handleSaveDriverDetails,
                    icon: _isVerifyingDriverOtp
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle_rounded, size: 18, color: Colors.white),
                    label: Text(
                      'SAVE',
                      style: GoogleFonts.hankenGrotesk(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 0.8,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfileView() {
    final bool isPilotMode = (_activeUserRole == 'Driver');

    return Scaffold(
      appBar: AppBar(
        title: Text('My Profile', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          if (isPilotMode || _activeUserRole == 'Admin')
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: AppTheme.primaryColor),
              onPressed: _showNetworkSettingsDialog,
            ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 130),
        child: Column(
          children: [
            // Circular Avatar with Camera Badge
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
            const SizedBox(height: 14),

            // User Name
            Text(
              (!isPilotMode && _editableUserName.toLowerCase().contains('pilot'))
                  ? 'StayDriv Customer'
                  : _editableUserName,
              style: GoogleFonts.hankenGrotesk(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            // Dedicated Role Badge
            if (!isPilotMode)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF5FF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person, size: 15, color: Color(0xFF1D4ED8)),
                    const SizedBox(width: 6),
                    Text(
                      'Customer',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1D4ED8),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFA5D6A7)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.two_wheeler_rounded, size: 15, color: Color(0xFF1B7C3E)),
                    const SizedBox(width: 6),
                    Text(
                      'StayDriv Pilot Partner',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1B7C3E),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            // Personal Information Heading
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Personal Information',
                style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
              ),
            ),
            const SizedBox(height: 12),

            // Tappable Profile Information Fields
            _buildProfileTile(
              Icons.person_outline,
              'Full Name',
              (!isPilotMode && _editableUserName.toLowerCase().contains('pilot'))
                  ? 'StayDriv Customer'
                  : _editableUserName,
              onTap: () => _showSingleFieldEditDialog(
                'Full Name',
                (!isPilotMode && _editableUserName.toLowerCase().contains('pilot')) ? 'StayDriv Customer' : _editableUserName,
                (val) => setState(() => _editableUserName = val),
              ),
            ),
            _buildProfileTile(
              Icons.phone_outlined,
              'Mobile Number',
              '+91 ${widget.phoneNumber}',
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Text(
                  'VERIFIED',
                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade700),
                ),
              ),
              onTap: _showMobileNumberInfoDialog,
            ),
            _buildProfileTile(
              Icons.email_outlined,
              'Email Address',
              _emailAddress,
              onTap: () => _showSingleFieldEditDialog(
                'Email Address',
                _emailAddress == 'Not Provided' ? '' : _emailAddress,
                (val) => setState(() => _emailAddress = val.isNotEmpty ? val : 'Not Provided'),
              ),
            ),
            _buildProfileTile(
              Icons.calendar_today_outlined,
              'Date of Birth',
              _dateOfBirth,
              onTap: () async {
                DateTime? picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime(2000, 1, 1),
                  firstDate: DateTime(1940),
                  lastDate: DateTime.now().subtract(const Duration(days: 365 * 16)),
                );
                if (picked != null) {
                  setState(() {
                    _dateOfBirth = "${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}";
                  });
                }
              },
            ),

            // Pilot Specific Console (Visible when Pilot Partner mode is active)
            if (isPilotMode) ...[
              const Divider(height: 24),

              // SENIORITY 2: 5 VEHICLE CATEGORIES, VEHICLE IDENTIFICATION & AADHAAR
              _buildVehicleTypeSelector(),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Vehicle & Duty Console',
                      style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (_bookingAccessEnabled && _dailyPlanStatus == 'paid') ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      (_bookingAccessEnabled && _dailyPlanStatus == 'paid') ? 'DUTY ON' : 'DUTY OFF',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: (_bookingAccessEnabled && _dailyPlanStatus == 'paid') ? const Color(0xFF166534) : const Color(0xFF991B1B),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildProfileTile(
                Icons.directions_car_rounded,
                'Assigned Vehicle Type',
                _pilotVehiclePlate.isNotEmpty ? '$_selectedVehicle ($_pilotVehiclePlate)' : '$_selectedVehicle',
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (ctx) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          'Scooty',
                          'Motorcycle/Bike',
                          'Auto Rickshaw',
                          'Hatchback Car',
                          'Sedan',
                          'SUV',
                          'Car XL',
                          'Mini Truck',
                          'Heavy Truck'
                        ].map((v) {
                          return ListTile(
                            leading: Icon(
                              _getVehicleIcon(v),
                              color: AppTheme.primaryColor,
                            ),
                            title: Text(v, style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                            trailing: _selectedVehicle == v ? const Icon(Icons.check, color: Colors.green) : null,
                            onTap: () async {
                              setState(() => _selectedVehicle = v);
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setString('selected_vehicle', v);
                              BookingManager().setDriverVehicle(v);
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Vehicle updated to $v'), backgroundColor: Colors.green),
                                );
                              }
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  );
                },
              ),

              // VEH NO: and COLOR: Card
              _buildVehicleIdentificationCard(),
              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Pilot Documents',
                    style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_isLoadingProfile)
                const Center(child: CircularProgressIndicator())
              else ...[
                // Seniority 2 ends with Aadhaar Front & Back
                _buildDocUploadTile('Aadhaar Card - Front', _aadhaarFront, 'aadhaarFront', _aadhaarFrontName, _aadhaarFrontSize),
                _buildDocUploadTile('Aadhaar Card - Back', _aadhaarBack, 'aadhaarBack', _aadhaarBackName, _aadhaarBackSize),

                // SENIORITY 3: DL & RC & ACTION BUTTONS [EDIT] & [SAVE]
                _buildDocUploadTile('Driving License - Front', _licenseFront, 'licenseFront', _licenseFrontName, _licenseFrontSize),
                _buildDocUploadTile('Driving License - Back', _licenseBack, 'licenseBack', _licenseBackName, _licenseBackSize),
                _buildDocUploadTile('Vehicle RC - Front', _rcFront, 'rcFront', _rcFrontName, _rcFrontSize),
                _buildDocUploadTile('Vehicle RC - Back', _rcBack, 'rcBack', _rcBackName, _rcBackSize),
                if (_selectedVehicle == 'Car' || _selectedVehicle == 'Car XL' || _selectedVehicle == 'Mini Truck' || _selectedVehicle == 'Heavy Truck') ...[
                  _buildDocUploadTile('Fitness Certificate', _fitness, 'fitness', _fitnessName, _fitnessSize),
                  _buildDocUploadTile('Vehicle Permit', _permit, 'permit', _permitName, _permitSize),
                ],

                // [ EDIT ] and [ SAVE ] Buttons for Vehicle & Documents
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _isEditingVehicle = true;
                                if (_pilotVehiclePlate.isNotEmpty) {
                                  _vehiclePlateController.text = _pilotVehiclePlate;
                                }
                                if (_pilotVehicleColor.isNotEmpty) {
                                  _vehicleColorController.text = _pilotVehicleColor;
                                }
                              });
                            },
                            icon: const Icon(Icons.edit_note_rounded, size: 20, color: Color(0xFFDC2626)),
                            label: Text(
                              'EDIT',
                              style: GoogleFonts.hankenGrotesk(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                letterSpacing: 0.8,
                                color: const Color(0xFFDC2626),
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFDC2626), width: 1.8),
                              backgroundColor: _isEditingVehicle ? const Color(0xFFFEF2F2) : Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: _savePilotVehicleDetails,
                            icon: const Icon(Icons.save_rounded, size: 20, color: Colors.white),
                            label: Text(
                              'SAVE',
                              style: GoogleFonts.hankenGrotesk(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                letterSpacing: 0.8,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFDC2626),
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // SENIORITY 4: DRIVER REPLACEMENT CONSOLE & SALARY / EARNINGS
              _buildDriverReplacementConsole(),
              const SizedBox(height: 16),

              _buildProfileTile(
                Icons.account_balance_wallet_outlined,
                'Pilot Salary & Earnings',
                '₹${_pilotSalary.toStringAsFixed(2)} | Tap to view & withdraw',
                onTap: _openPilotEarningsScreen,
              ),
            ] else ...[
              // Customer Specific Console: Payment Wallet Only
              const Divider(height: 32),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Payments',
                  style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
                ),
              ),
              const SizedBox(height: 12),
              _buildProfileTile(
                Icons.account_balance_wallet_outlined,
                'Payment Wallet',
                _customerWalletBalance > 0
                    ? 'Balance: ₹${_customerWalletBalance.toStringAsFixed(2)} • Tap to manage'
                    : 'Tap to add money & manage wallet',
                onTap: _openPaymentWalletScreen,
              ),
            ],

            if (isPilotMode) ...[
              const Divider(height: 32),
              _buildProfileTile(
                Icons.settings_outlined,
                'App Settings',
                'Preferences, Map Style & Notifications',
                onTap: _showAppSettingsSheet,
              ),
            ],
            const Divider(height: 32),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'StayDriv Consoles & Portals',
                style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
              ),
            ),
            const SizedBox(height: 12),
            _buildProfileTile(
              Icons.hub_rounded,
              'Switch Console / Portal',
              'Customer, Pilot, Restaurant Partner & Admin',
              onTap: () => ConsoleSwitcherSheet.show(
                context,
                currentRole: _activeUserRole,
                userPhone: widget.phoneNumber,
              ),
              trailing: const Icon(Icons.swap_horiz_rounded, color: AppTheme.primaryColor),
            ),
            const Divider(height: 32),
            _buildProfileTile(
              Icons.share_rounded,
              isPilotMode ? 'Share StayDriv Pilot App' : 'Share StayDriv App',
              'Invite friends & family with instant download link',
              onTap: () => ShareStayDrivSheet.show(context, isPilot: isPilotMode),
            ),
            _buildProfileTile(
              Icons.delete_forever_outlined,
              'Delete Account & Personal Data',
              'Manage account closure, data safety & privacy rights',
              onTap: _openAccountDeletionPage,
              trailing: const Icon(Icons.open_in_new, color: Color(0xFFEF4444), size: 20),
            ),
            const SizedBox(height: 24),

            // Logout Button - Elevated, high-visibility, 100% accessible above nav bar
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _handleLogout,
                icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 20),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                label: Text(
                  'LOGOUT',
                  style: GoogleFonts.hankenGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileTile(IconData icon, String title, String subtitle, {VoidCallback? onTap, Widget? trailing}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: ListTile(
            leading: Icon(icon, color: AppTheme.primaryColor),
            title: Text(title, style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
            subtitle: Text(subtitle, style: GoogleFonts.inter()),
            trailing: trailing ?? const Icon(Icons.chevron_right, color: AppTheme.outlineColor),
          ),
        ),
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
      displayFileSize = displayFileName.toLowerCase().endsWith('.pdf') ? 'PDF Document' : 'Image File';
    }

    final isPdf = displayFileName.toLowerCase().endsWith('.pdf') || (url != null && url.toLowerCase().contains('.pdf'));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasUploaded ? Colors.green.withOpacity(0.4) : AppTheme.outlineVariant.withOpacity(0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasUploaded ? Icons.verified_rounded : Icons.upload_file_rounded,
                  color: hasUploaded ? Colors.green.shade700 : AppTheme.primaryColor,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
                if (hasUploaded)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 12, color: Colors.green.shade700),
                        const SizedBox(width: 4),
                        Text(
                          'Uploaded ✓',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              hasUploaded
                  ? '$displayFileName ($displayFileSize)'
                  : 'Upload JPG, JPEG, PNG, or PDF document (max 10 MB)',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: hasUploaded ? AppTheme.onSurfaceColor : AppTheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (hasUploaded) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.visibility_outlined, size: 14),
                    label: const Text('View', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryColor,
                      side: const BorderSide(color: AppTheme.primaryColor),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
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
                                    color: isPdf ? Colors.red.shade50 : AppTheme.surfaceContainer,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppTheme.outlineVariant),
                                  ),
                                  child: isPdf
                                      ? Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.picture_as_pdf_rounded, size: 64, color: Colors.red.shade700),
                                            const SizedBox(height: 12),
                                            Text(
                                              'PDF Document Verified',
                                              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red.shade900),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Stored securely in MongoDB GridFS',
                                              style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade700),
                                            ),
                                          ],
                                        )
                                      : ClipRRect(
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
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.refresh_rounded, size: 14),
                    label: const Text('Replace', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.onSurfaceVariant,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _pickAndUploadImage(type),
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    icon: const Icon(Icons.file_upload_outlined, size: 14),
                    label: const Text('Upload', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _pickAndUploadImage(type),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpView() {
    final isPilot = _activeUserRole.toLowerCase().contains('driver') || _activeUserRole.toLowerCase().contains('pilot');
    final userType = isPilot ? 'pilot' : 'customer';

    return Scaffold(
      appBar: AppBar(
        title: Text('StayDriv Support', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MySupportTicketsScreen()),
              );
            },
            icon: const Icon(Icons.receipt_long, size: 18),
            label: const Text('My Requests'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primaryColor),
          ),
        ],
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
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.hub_outlined, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'StayDriv Consoles & Portals',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Switch between Customer, Pilot, Restaurant, and Admin consoles',
                                style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF1E3A8A),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            minimumSize: Size.zero,
                          ),
                          onPressed: () => ConsoleSwitcherSheet.show(
                            context,
                            currentRole: _activeUserRole,
                            userPhone: widget.phoneNumber,
                          ),
                          child: const Text('Switch', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                  _buildHelpTile(
                    'Booking issue',
                    'Problems making a ride request, cancellations, or driver arrival',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SupportCategoryScreen(category: 'booking', userType: userType),
                        ),
                      );
                    },
                  ),
                  _buildHelpTile(
                    'Payment and refund',
                    'Questions about wallet, online transactions, or fare disputes',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SupportCategoryScreen(category: 'payment', userType: userType),
                        ),
                      );
                    },
                  ),
                  _buildHelpTile(
                    'Safety concerns',
                    'Emergency report, suspicious detours, or accident protocol',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SupportCategoryScreen(category: 'safety', userType: userType),
                        ),
                      );
                    },
                  ),
                  _buildHelpTile(
                    isPilot ? 'Customer complaints' : 'Driver complaints',
                    isPilot
                        ? 'Feedback on passenger behavior, fare refusal, or vehicle issues'
                        : 'Feedback on ride quality, driver conduct, or vehicle cleanliness',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SupportCategoryScreen(category: 'complaint', userType: userType),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            // Call emergency helpline
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => SupportService().callEmergencyHelpline(context),
                child: Container(
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
                            Text('24/7 dedicated support desk (+91 9490440281)', style: GoogleFonts.inter(fontSize: 12)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.call, color: AppTheme.primaryColor),
                        onPressed: () => SupportService().callEmergencyHelpline(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // WhatsApp support button
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => SupportService().openWhatsAppSupport(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF25D366).withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.chat_bubble_outline, color: Color(0xFF1EBE5D), size: 26),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Chat on WhatsApp', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, color: const Color(0xFF128C7E))),
                            Text('Instant support chat on official WhatsApp desk', style: GoogleFonts.inter(fontSize: 12)),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF128C7E)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpTile(String title, String desc, {VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppTheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppTheme.outlineVariant.withOpacity(0.3)),
        ),
        child: ListTile(
          title: Text(title, style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
          subtitle: Text(desc, style: GoogleFonts.inter(fontSize: 12)),
          trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.outlineColor),
          onTap: onTap,
        ),
      ),
    );
  }

  // ==========================================
  // DRIVER PARTNER CONSOLE AND STATE METHODS
  // ==========================================

  void _toggleDuty(bool value) async {
    // 1. Debounce duplicate requests
    if (_isDutyToggling) {
      debugPrint('[HomeScreen] _toggleDuty ignored: already toggling duty.');
      return;
    }
    _isDutyToggling = true;
    _lastDutyToggleTimestamp = DateTime.now().millisecondsSinceEpoch;

    try {
      if (value && !_isPilotApproved) {
        setState(() {
          _isOnline = false;
          _driverStatus = 'offline';
        });
        _showPilotApplicationStatusModal();
        return;
      }

      if (value && !_bookingAccessEnabled) {
        setState(() {
          _isOnline = false;
          _driverStatus = 'offline';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text((_bookingAccessReason.isNotEmpty && !_bookingAccessReason.toLowerCase().contains('eligible for 100% earnings'))
                ? 'Your booking access is currently disabled by Admin: $_bookingAccessReason'
                : 'Your booking access is currently disabled by Admin. Please contact Admin to restore access.'),
            backgroundColor: const Color(0xFFDC2626),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'View Status',
              textColor: Colors.white,
              onPressed: _openPilotEarningsScreen,
            ),
          ),
        );
        return;
      }

      if (value && _dailyPlanStatus != 'paid') {
        setState(() {
          _isOnline = false;
          _driverStatus = 'offline';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_dailyPlanStatus == 'expired'
                ? 'Daily ₹20 plan has expired. Please pay ₹20 to activate bookings.'
                : 'Pay ₹20 Daily Plan to activate bookings & 100% earnings.'),
            backgroundColor: const Color(0xFFD97706),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Pay ₹20',
              textColor: Colors.white,
              onPressed: _openPilotEarningsScreen,
            ),
          ),
        );
        return;
      }

      final prevOnline = _isOnline;
      final prevStatus = _driverStatus;

      // Immediate optimistic UI update
      setState(() {
        _isOnline = value;
        _driverStatus = value ? 'online' : 'offline';
      });

      // Authoritative backend persistence with rollback on failure
      try {
        final uid = FirebaseService().currentUid ?? widget.phoneNumber;
        final cleanPhone = widget.phoneNumber.replaceAll(RegExp(r'\D'), '');
        final last10 = cleanPhone.length >= 10 ? cleanPhone.substring(cleanPhone.length - 10) : cleanPhone;
        final effectiveUid = (uid.isNotEmpty && !uid.startsWith('+')) ? uid : (last10.isNotEmpty ? last10 : uid);
        BookingManager().setDriverCustomUid(effectiveUid);

        if (effectiveUid.isNotEmpty) {
          final baseUrl = NetworkConfig.backendUrl;
          final res = await ApiClient().post(
            Uri.parse('$baseUrl/api/pilot/duty'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'uid': effectiveUid,
              'dutyStatus': value ? 'ON' : 'OFF',
            }),
          ).timeout(const Duration(seconds: 6));

          if (res.statusCode != 200) {
            final errorBody = jsonDecode(res.body);
            final errorMsg = errorBody['error'] ?? errorBody['message'] ?? 'Failed to update duty status';
            if (mounted) {
              _logDutyAudit(source: 'USER_TOGGLE_SERVER_REJECTED', prevOnline: value, newOnline: prevOnline, isUserAction: true, reason: errorMsg);
              setState(() {
                _isOnline = prevOnline;
                _driverStatus = prevStatus;
              });
              BookingManager().setDriverOnline(prevOnline);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Duty update rejected: $errorMsg'),
                  backgroundColor: const Color(0xFFDC2626),
                ),
              );
            }
            return;
          }
        }
      } catch (e) {
        debugPrint('[HomeScreen] Network error updating duty status: $e');
        if (mounted) {
          _logDutyAudit(source: 'USER_TOGGLE_NETWORK_ERROR', prevOnline: value, newOnline: prevOnline, isUserAction: true, reason: e.toString());
          setState(() {
            _isOnline = prevOnline;
            _driverStatus = prevStatus;
          });
          BookingManager().setDriverOnline(prevOnline);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Network error: Could not reach server to update duty status.'),
              backgroundColor: Color(0xFFDC2626),
            ),
          );
        }
        return;
      }

      // Confirmed server state
      SharedPreferences.getInstance().then((prefs) {
        prefs.setBool('pilot_duty_online', value);
      });
      _logDutyAudit(source: 'USER_TOGGLE_SUCCESS', prevOnline: prevOnline, newOnline: value, isUserAction: true);

      _bookingTimer?.cancel();
      if (value) {
        WakeLockService.acquireWakeLock();
        WakeLockService.requestIgnoreBatteryOptimizations();
        WakeLockService.startForegroundService(
          title: 'StayDriv Pilot Online',
          message: 'Searching for nearby ride requests...',
        );
        BookingManager().setDriverOnline(true);
        BookingManager().setDriverVehicle(_selectedVehicle);
        _startGpsTracking();
        _subscribeToBookingManager();
        if (_driverMapController != null && _driverMapCenter != null) {
          _driverMapController!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: _driverMapCenter!,
                zoom: 16.5,
                bearing: BookingManager().driverHeading,
              ),
            ),
          );
        }
        _checkOverlayPermissionPrompt();
      } else {
        FloatingWidgetService.hide();
        WakeLockService.stopForegroundService();
        WakeLockService.releaseWakeLock();
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
    } finally {
      _isDutyToggling = false;
    }
  }

  void _showPilotApplicationStatusModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: _pilotStatus == 'action_required' 
                    ? const Color(0xFFFEE2E2) 
                    : const Color(0xFFFEF3C7),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _pilotStatus == 'action_required' 
                      ? const Color(0xFFEF4444) 
                      : const Color(0xFFF59E0B),
                  width: 2,
                ),
              ),
              child: Icon(
                _pilotStatus == 'action_required' 
                    ? Icons.warning_amber_rounded 
                    : Icons.hourglass_top_rounded,
                color: _pilotStatus == 'action_required' 
                    ? const Color(0xFFDC2626) 
                    : const Color(0xFFD97706),
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _pilotStatus == 'action_required' 
                  ? 'Correction Required' 
                  : 'Verification Under Review',
              style: GoogleFonts.hankenGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _pilotStatus == 'action_required' 
                    ? const Color(0xFFFEE2E2) 
                    : const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Status: ${_pilotStatus.toUpperCase().replaceAll('_', ' ')}',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _pilotStatus == 'action_required' 
                      ? const Color(0xFFDC2626) 
                      : const Color(0xFFB45309),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Application ID', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                      Text(
                        _pilotApplicationId.isNotEmpty ? _pilotApplicationId : 'SD-PLT-PENDING',
                        style: GoogleFonts.hankenGrotesk(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF0284C7)),
                      ),
                    ],
                  ),
                  if (_pilotCorrectionNotes.isNotEmpty || _pilotRejectionReason.isNotEmpty) ...[
                    const Divider(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Admin Note: ${_pilotCorrectionNotes.isNotEmpty ? _pilotCorrectionNotes : _pilotRejectionReason}',
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFDC2626), fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _pilotStatus == 'action_required'
                  ? 'StayDriv Admin requested you to correct or re-upload specific documents before your account can be activated.'
                  : 'Your registration documents are currently pending verification by StayDriv Admin. You will be able to go online and accept rides as soon as your account is approved.',
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B), height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final cleanPhone = widget.phoneNumber.replaceAll(RegExp(r'\D'), '').trim();
                      try {
                        final baseUrl = NetworkConfig.backendUrl;
                        final sRes = await ApiClient().get(Uri.parse('$baseUrl/api/pilot/application-status?phone=$cleanPhone'), retry: false).timeout(const Duration(seconds: 4));
                        if (sRes.statusCode == 200) {
                          final sData = jsonDecode(sRes.body);
                          if (sData is Map && sData['success'] == true && sData['found'] == true) {
                            final st = (sData['status'] ?? '').toString().toUpperCase();
                            final isAppr = sData['approved'] == true || sData['isApproved'] == true || st == 'APPROVED';
                            if (isAppr) {
                              Navigator.pop(ctx);
                              setState(() {
                                _isPilotApproved = true;
                                _pilotStatus = 'approved';
                              });
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setBool('is_pilot_approved', true);
                              await prefs.setString('pilot_application_status', 'APPROVED');
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('🎉 Congratulations! Your Pilot account is APPROVED! You can now go online to accept rides.'),
                                    backgroundColor: Color(0xFF16A34A),
                                    duration: Duration(seconds: 4),
                                  ),
                                );
                              }
                              return;
                            }
                          }
                        }
                      } catch (_) {}
                      Navigator.pop(ctx);
                      _loadProfileData();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Application is still pending admin review. Please check back shortly.'), duration: Duration(seconds: 3)),
                        );
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Refresh Status', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w700)),
                  ),
                ),
                if (_pilotStatus == 'action_required') ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => RegisterScreen(phoneNumber: widget.phoneNumber, initialRole: 'Driver'),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1D4ED8),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Update Docs', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _startRinging() {
    try {
      WakeLockService.wakeUpScreen(); // Turn on display backlight and show incoming request over lock screen!
      WakeLockService.bringAppToForeground(); // Bring app to top
      final bId = _currentIncomingBookingId ?? _activeBooking?['bookingId']?.toString() ?? 'incoming_ride';
      final price = _activeBooking?['price']?.toString() ?? '';
      final vehicle = _activeBooking?['vehicle']?.toString() ?? _selectedVehicle;
      final pickupName = _activeBooking?['pickup']?.toString() ?? 'Customer Pickup';
      PilotRideRingtoneService().startRideAlert(
        bookingId: bId,
        title: 'New $vehicle Request: $price',
        pickup: pickupName,
      );
    } catch (e) {
      debugPrint('Error starting ring: $e');
    }
  }

  void _stopRinging() {
    _countdownTimer?.cancel();
    _currentIncomingBookingId = null;
    PilotRideRingtoneService().stopRideAlert();
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
        BookingManager().updateDriverLocation(
          latLng,
          heading: pos.heading,
          speed: pos.speed,
          accuracy: pos.accuracy,
        );
        if (mounted) {
          setState(() {
            _driverMapCenter = latLng;
          });
          if (_driverMapController != null) {
            _driverMapController!.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: latLng,
                  zoom: 16.5,
                  bearing: pos.heading > 0 ? pos.heading : 0.0,
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting initial GPS position: $e');
    }

    try {
      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 2,
        ),
      ).listen((Position pos) {
        if (_isOnline) {
          final latLng = LatLng(pos.latitude, pos.longitude);
          BookingManager().updateDriverLocation(
            latLng,
            heading: pos.heading,
            speed: pos.speed,
            accuracy: pos.accuracy,
          );
          if (mounted) {
            setState(() {
              _driverMapCenter = latLng;
            });
            if (_driverMapController != null && (_driverStatus == 'online' || _driverStatus == 'offline')) {
              _driverMapController!.animateCamera(
                CameraUpdate.newCameraPosition(
                  CameraPosition(
                    target: latLng,
                    zoom: 16.5,
                    bearing: pos.heading > 0 ? pos.heading : 0.0,
                  ),
                ),
              );
            }
          }
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
    
    // 1. Authoritative Server Assignment:
    // If the server assigned this booking specifically to THIS pilot, ALWAYS MATCH!
    final driverId = active['driverId'] as String?;
    if (driverId != null && driverId.isNotEmpty && BookingManager().isDriverIdMatchingMe(driverId)) {
      debugPrint('StayDriv Match Success: Booking is assigned to this pilot ($driverId)!');
      return true;
    }

    // 2. Check if the booking has been accepted by another driver
    final status = active['status'] as String? ?? 'searching';
    if (status != 'searching' && status != 'incoming') {
      if (!BookingManager().isDriverIdMatchingMe(driverId)) {
        debugPrint('StayDriv Match Failed: Booking is in status $status and belongs to another driver ($driverId)');
        return false;
      }
    }
    
    // 3. Vehicle Compatibility Check
    final vehicle = active['vehicle'] as String?;
    if (vehicle != null && !areVehiclesCompatible(vehicle, _selectedVehicle)) {
      debugPrint('StayDriv Match Failed: Vehicle mismatch (Customer wants $vehicle, Driver is $_selectedVehicle)');
      return false;
    }

    // 4. Bypass distance check for Heavy Truck matching (can match anywhere in India)
    final bool isHeavyTruck = active['serviceType'] == 'heavy_truck' ||
        (active['title'] as String? ?? '').toLowerCase().contains('heavy truck') ||
        (active['vehicle'] as String? ?? '').toLowerCase().contains('heavy truck');
    if (isHeavyTruck) {
      debugPrint('StayDriv Match Success: Driver is matching Heavy Truck anywhere in India!');
      return true;
    }

    // 5. Bypass distance check for local MongoDB/Mock mode
    if (!_isFirebaseInitialized) {
      debugPrint('StayDriv Match Success: Driver is near and matching (Bypassed distance check in Mock/MongoDB mode)!');
      return true;
    }

    final pickup = NavigationEngine.extractPickupLatLng(active);
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
      // If pilot is currently busy on an active ride, do NOT wipe active booking on null broadcast
      if (_driverStatus == 'heading_to_pickup' ||
          _driverStatus == 'arrived_pickup' ||
          _driverStatus == 'on_trip' ||
          _driverStatus == 'payment_pending') {
        debugPrint('[HomeScreen] Retaining active booking during null broadcast.');
        return;
      }
      _currentIncomingBookingId = null;
      _stopRinging();
      setState(() {
        _activeBooking = null;
        _driverStatus = _isOnline ? 'online' : 'offline';
        _driverRoutePoints = [];
      });
      return;
    }

    final status = active['status'] as String? ?? 'searching';
    final bookingId = active['bookingId']?.toString();

    // Prioritize cancellation notification so pilot always receives the popup when customer cancels
    if (status == 'cancelled') {
      final cancelledId = active['bookingId']?.toString() ?? active['id']?.toString() ?? active['_id']?.toString();
      final currentActiveId = _activeBooking?['bookingId']?.toString() ?? _activeBooking?['id']?.toString() ?? _activeBooking?['_id']?.toString();

      // If driver has an active booking and this cancelled event is for a different booking, ignore it!
      if (currentActiveId != null && cancelledId != null && currentActiveId != cancelledId) {
        debugPrint('[HomeScreen] Ignoring cancellation for booking $cancelledId because it does not match active booking $currentActiveId');
        return;
      }

      _currentIncomingBookingId = null;
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
        _currentIncomingBookingId = null;
        _stopRinging();
        setState(() {
          _activeBooking = null;
          _driverStatus = _isOnline ? 'online' : 'offline';
          _driverRoutePoints = [];
        });
        return;
      }

      final prevStatus = _driverStatus;
      final prevIncomingId = _currentIncomingBookingId;
      
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
          _currentIncomingBookingId = null;
        } else if (status == 'arrived') {
          _driverStatus = 'arrived_pickup';
          _currentIncomingBookingId = null;
        } else if (status == 'started') {
          _driverStatus = 'on_trip';
          _currentIncomingBookingId = null;
        } else if (status == 'completed') {
          _driverStatus = 'payment_pending';
          _currentIncomingBookingId = null;
        }
      });
      _syncFloatingMiniScreen(isMinimizing: false);
      
      if (_driverStatus == 'heading_to_pickup' || _driverStatus == 'arrived_pickup' || _driverStatus == 'on_trip') {
        final bId = normalizedActive['bookingId']?.toString() ??
            normalizedActive['id']?.toString() ??
            normalizedActive['_id']?.toString() ??
            '';
        if (bId.isNotEmpty) {
          SocketService().joinRide(bId);
        }
      }
      
      if (_driverStatus == 'incoming_request') {
        // Unique bookingId check: If this exact booking is ALREADY received and displaying countdown, do NOT duplicate or restart!
        if (prevStatus == 'incoming_request' && prevIncomingId == bookingId && _countdownTimer != null && _countdownTimer!.isActive) {
          debugPrint('[HomeScreen] Duplicate incoming request ignored: booking $bookingId is already active.');
          return;
        }

        _currentIncomingBookingId = bookingId;
        _startRinging();
        final price = normalizedActive['price']?.toString() ?? '';
        final vehicle = normalizedActive['vehicle']?.toString() ?? _selectedVehicle;
        final pickupName = normalizedActive['pickup']?.toString() ?? 'Customer Pickup';
        // Only trigger system heads-up notification alert if the pilot app is NOT in the foreground
        if (!_isAppInForeground) {
          WakeLockService.wakeUpScreen();
          WakeLockService.showIncomingAlert(
            title: '🚗 New $vehicle Request: $price',
            message: 'Pickup: $pickupName. Tap to accept.',
            bookingId: bookingId,
            role: 'pilot',
          );
        }
        _incomingRequestCountdown = 30;
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
            debugPrint('[HomeScreen] Incoming request countdown expired (30s). Auto-declining and resetting state.');
            _directDeclineBooking(reason: 'Request timed out');
          }
        });
      } else if (prevStatus == 'incoming_request' && _driverStatus != 'incoming_request') {
        _currentIncomingBookingId = null;
        _stopRinging();
      }
    } else {
      // If driver is currently busy on an active ride, ignore non-matching broadcast for another booking!
      if (_driverStatus == 'heading_to_pickup' ||
          _driverStatus == 'arrived_pickup' ||
          _driverStatus == 'on_trip' ||
          _driverStatus == 'payment_pending') {
        debugPrint('[HomeScreen] Retaining active booking despite non-matching broadcast.');
        return;
      }
      _currentIncomingBookingId = null;
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

    final prevStatus = _activeBooking?['status'] as String?;

    setState(() {
      _activeBooking = normalizedActive;
    });
    _syncFloatingMiniScreen(isMinimizing: false);

    final status = normalizedActive['status'] as String? ?? 'searching';
    final cancelledBy = normalizedActive['cancelledBy'] as String?;

    if (status == 'cancelled' && (cancelledBy == 'pilot' || cancelledBy == 'driver')) {
      FloatingWidgetService.hide();
      _showPilotCancelledNotificationToCustomer(normalizedActive);
      return;
    }

    if (status == 'accepted' && prevStatus == 'searching') {
      if (!_isAppInForeground) {
        WakeLockService.wakeUpScreen();
        WakeLockService.showIncomingAlert(
          title: 'StayDriv: Pilot Found!',
          message: 'Your pilot is on the way to pick you up.',
          bookingId: normalizedActive['bookingId']?.toString(),
          role: 'customer',
        );
      }
    } else if (status == 'arrived' && prevStatus != 'arrived') {
      if (!_isAppInForeground) {
        WakeLockService.wakeUpScreen();
        WakeLockService.showIncomingAlert(
          title: 'StayDriv: Pilot Arrived!',
          message: 'Your pilot has arrived at your pickup location.',
          bookingId: normalizedActive['bookingId']?.toString(),
          role: 'customer',
        );
      }
    }

    if (status == 'completed') {
      FloatingWidgetService.hide();
      final isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? true;
      if (isCurrentRoute) {
        BookingManager().clearBooking();
        if (mounted) {
          setState(() {
            _activeBooking = null;
          });
        }
      } else {
        debugPrint("[HomeScreen] Completed ride received but LiveTrackingScreen is active. Retaining activeBooking for payment.");
      }
      return;
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
    final bId = booking['bookingId']?.toString() ?? booking['id']?.toString() ?? booking['_id']?.toString() ?? '';
    bool isPaid = (booking['paymentStatus'] == 'paid') || (bId.isNotEmpty && BookingManager().isBookingPaid(bId));

    showModalBottomSheet(
      context: context,
      isDismissible: true,
      enableDrag: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final closeBtn = Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, right: 8),
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, size: 28, color: Colors.grey),
                  onPressed: () {
                    BookingManager().clearBooking();
                    _isRatingSheetShowing = false;
                    Navigator.of(context).pop();
                  },
                ),
              ),
            );

            if (!isPaid) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  closeBtn,
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 24),
                    child: RideCompletedPaymentPanel(
                      booking: booking,
                      onPaymentCompleted: () {
                        setSheetState(() {
                          isPaid = true;
                        });
                        if (bId.isNotEmpty) {
                          BookingManager().markBookingAsPaid(bookingId: bId, paymentOption: 'Paid');
                        }
                      },
                    ),
                  ),
                ],
              );
            }

            final driverName = booking['driverName'] as String? ?? 'StayDriv Partner';
            final price = booking['price'] as String? ?? '₹0';
            final waitingCharge = booking['waitingCharge'] as int? ?? 0;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                closeBtn,
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 32),
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
                        if (bId.isNotEmpty) {
                          SharedPreferences.getInstance().then((prefs) {
                            prefs.setBool('rated_booking_$bId', true);
                          });
                        }
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
            ),
          ],
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
              _driverMapController!.animateCamera(
                CameraUpdate.newCameraPosition(
                  CameraPosition(
                    target: pos,
                    zoom: 16.5,
                    bearing: BookingManager().driverHeading > 0 ? BookingManager().driverHeading : 0.0,
                  ),
                ),
              );
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
              _driverMapController!.animateCamera(
                CameraUpdate.newCameraPosition(
                  CameraPosition(
                    target: pos,
                    zoom: 16.5,
                    bearing: BookingManager().driverHeading > 0 ? BookingManager().driverHeading : 0.0,
                  ),
                ),
              );
            }
          } else {
            _driverMapController!.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: pos,
                  zoom: 16.5,
                  bearing: BookingManager().driverHeading > 0 ? BookingManager().driverHeading : 0.0,
                ),
              ),
            );
          }
        }
      }
    });

    _rideStatusSub = BookingManager().rideStatusStream.listen((String status) {
      if (!mounted || !_isOnline) return;
      
      final active = BookingManager().activeBooking;
      _handleBookingUpdate(active);
      
      if (_activeBooking != null && _isNearAndMatching(_activeBooking!)) {
        final pickup = NavigationEngine.extractPickupLatLng(_activeBooking);
        final drop = NavigationEngine.extractDropLatLng(_activeBooking);
        if ((status == 'accepted' || status == 'heading_to_pickup') && pickup != null) {
          _driverRoutePoints = [];
          if (_driverMapCenter != null) {
            _fetchDriverRouteDirections(_driverMapCenter!, pickup);
            _zoomToRoute(_driverMapCenter!, pickup);
          }
        } else if ((status == 'started' || status == 'on_trip') && pickup != null && drop != null) {
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
        final pickup = NavigationEngine.extractPickupLatLng(initialActive);
        final drop = NavigationEngine.extractDropLatLng(initialActive);
        if ((status == 'accepted' || status == 'heading_to_pickup') && pickup != null && _driverMapCenter != null) {
          _fetchDriverRouteDirections(_driverMapCenter!, pickup);
        } else if ((status == 'started' || status == 'on_trip') && pickup != null && drop != null) {
          _fetchDriverRouteDirections(pickup, drop);
        }
      }
    }
  }

  void _acceptBooking() {
    _stopRinging();
    WakeLockService.dismissIncomingAlert();
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

    final plateToUse = _pilotVehiclePlate.isNotEmpty
        ? _pilotVehiclePlate
        : (BookingManager().driverVehiclePlate.isNotEmpty
            ? BookingManager().driverVehiclePlate
            : '');
    final colorToUse = _pilotVehicleColor.isNotEmpty
        ? _pilotVehicleColor
        : (BookingManager().driverVehicleModelColor.isNotEmpty
            ? BookingManager().driverVehicleModelColor
            : 'Black ' + _selectedVehicle);

    BookingManager().acceptBooking(
      driverName: widget.userName,
      vehiclePlate: plateToUse,
      vehicleModelColor: colorToUse,
    );

    _loadCompletedRides();

    final bId = _activeBooking?['bookingId']?.toString() ??
        _activeBooking?['id']?.toString() ??
        _activeBooking?['_id']?.toString() ??
        '';
    if (bId.isNotEmpty) {
      SocketService().joinRide(bId);
      _fetchPilotRideChatHistory(bId);
    }

    if (isHeavyTruck) {
      setState(() {
        _activeBooking = null;
        _driverStatus = _isOnline ? 'online' : 'offline';
        _driverRoutePoints = [];
      });
      BookingManager().clearBooking();
      return;
    }

    final pickup = NavigationEngine.extractPickupLatLng(_activeBooking);
    final drop = NavigationEngine.extractDropLatLng(_activeBooking);
    if (pickup != null) {
      _activeBooking!['pickupLatLng'] = pickup;
    }
    if (drop != null) {
      _activeBooking!['dropLatLng'] = drop;
    }

    setState(() {
      _driverStatus = 'heading_to_pickup';
    });

    if (pickup != null && _driverMapCenter != null) {
      _fetchDriverRouteDirections(_driverMapCenter!, pickup);
      _zoomToRoute(_driverMapCenter!, pickup);
    }
    if (!BookingManager.enableNetworkSync && pickup != null) {
      BookingManager().startSimulatedMovement(pickup);
    }

    // Automatically initialize navigation for passenger rides (Food delivery uses manual navigation only)
    final bool isFood = _activeBooking!['isFoodOrder'] == true ||
        _activeBooking!['serviceType'] == 'food' ||
        _activeBooking!['type'] == 'food';
    if (!isFood) {
      _openPilotNavigationScreen();
    }
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

  void _openPilotNavigationScreen() {
    if (_activeBooking == null || !mounted || _isPilotNavigationOpen) return;
    final bool isFood = _activeBooking!['isFoodOrder'] == true ||
        _activeBooking!['serviceType'] == 'food' ||
        _activeBooking!['type'] == 'food';
    if (isFood) {
      debugPrint('[HomeScreen] Suppressed automatic navigation for food delivery order');
      return;
    }
    _isPilotNavigationOpen = true;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PilotNavigationScreen(
          booking: _activeBooking!,
          onRideCompleted: () {
            setState(() {
              _driverStatus = 'payment_pending';
            });
          },
        ),
      ),
    ).then((_) {
      if (mounted) {
        setState(() {
          _isPilotNavigationOpen = false;
        });
      } else {
        _isPilotNavigationOpen = false;
      }
    });
  }

  void _verifyPickupOtp() async {
    final otp = _otpTextController.text.trim();
    if (otp.length != 4) {
      setState(() {
        _otpError = 'Please enter a valid 4-digit OTP';
      });
      return;
    }

    final bookingId = _activeBooking?['bookingId']?.toString() ??
        _activeBooking?['id']?.toString() ??
        _activeBooking?['_id']?.toString();

    final res = await BookingManager().verifyStartOtp(otp: otp, bookingId: bookingId);
    if (res['success'] == true) {
      setState(() {
        _otpError = '';
        _otpTextController.clear();
        _driverStatus = 'on_trip';
      });
      final drop = NavigationEngine.extractDropLatLng(_activeBooking);
      if (drop != null) {
        _activeBooking!['dropLatLng'] = drop;
        if (!BookingManager.enableNetworkSync) {
          BookingManager().startSimulatedMovement(drop);
        }
      }
      final bool isFood = _activeBooking!['isFoodOrder'] == true ||
          _activeBooking!['serviceType'] == 'food' ||
          _activeBooking!['type'] == 'food';
      if (!isFood) {
        _openPilotNavigationScreen();
      }
    } else {
      setState(() {
        _otpError = res['error'] ?? 'Invalid OTP. Ask customer again.';
      });
    }
  }

  void _callContact(String? phone, String name) async {
    final bId = _activeBooking?['bookingId']?.toString() ??
        _activeBooking?['id']?.toString() ??
        _activeBooking?['_id']?.toString() ??
        '';

    if (bId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot initiate call: active booking not found.'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    await CallMaskingService().callCustomer(
      bookingId: bId,
      customerName: name,
      context: context,
    );
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
      ..._activeBooking!,
      'date': 'Today, ' + TimeOfDay.now().format(context),
      'price': priceStr,
      'fare': priceStr,
      'icon': _getVehicleIcon(_selectedVehicle),
      'title': 'StayDriv $_selectedVehicle Ride',
      'route': '${_activeBooking!['pickup']} to ${_activeBooking!['drop']}',
      'pickup': _activeBooking!['pickup'] ?? '',
      'drop': _activeBooking!['drop'] ?? '',
      'distance': _activeBooking!['distance'] ?? _activeBooking!['distanceText'] ?? '',
      'duration': _activeBooking!['duration'] ?? _activeBooking!['durationText'] ?? '',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'vehicle': _selectedVehicle,
      'status': 'completed',
    };

    final double netEarnings = fareVal * 0.85;
    final double commission = fareVal * 0.15;

    // --- AUTOMATIC WEEKLY INCENTIVE EVALUATION (Mon - Sun) ---
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final sunday = DateTime(monday.year, monday.month, monday.day + 6, 23, 59, 59, 999);

    int weeklyCompletedCount = 1; // including this new completed ride
    for (var r in _completedRides) {
      final st = (r['status'] as String? ?? 'completed').toLowerCase();
      if (st != 'completed' && st != 'accepted') continue;
      final ts = r['timestamp'] as int? ?? 0;
      if (ts == 0) continue;
      final dt = DateTime.fromMillisecondsSinceEpoch(ts);
      if (dt.isAfter(monday.subtract(const Duration(milliseconds: 1))) &&
          dt.isBefore(sunday.add(const Duration(milliseconds: 1)))) {
        weeklyCompletedCount++;
      }
    }

    double incentiveBonusEarned = 0.0;
    String celebrationTitle = '';
    String celebrationDesc = '';

    int t1Target = 30;
    int t2Target = 50;
    int t1Bonus = 750;
    int t2Total = 1300;
    int t2Incremental = 550;

    final veh = _selectedVehicle.toLowerCase();
    if (veh.contains('auto')) {
      t1Bonus = 950;
      t2Total = 1500;
      t2Incremental = 550;
    } else if (veh.contains('car')) {
      t1Bonus = 1200;
      t2Total = 1800;
      t2Incremental = 600;
    }

    if (weeklyCompletedCount == t1Target) {
      incentiveBonusEarned = t1Bonus.toDouble();
      celebrationTitle = '🎉 30 Rides Completed! ₹$t1Bonus Bonus Credited!';
      celebrationDesc = 'Outstanding effort! You reached Target 1 ($t1Target rides) for this week! ₹$t1Bonus has been automatically credited to your Instant Cashout balance. Complete ${t2Target - t1Target} more rides for the ₹$t2Total mega bonus!';
    } else if (weeklyCompletedCount == t2Target) {
      incentiveBonusEarned = t2Incremental.toDouble();
      celebrationTitle = '🌟 50 Rides Completed! ₹$t2Incremental Bonus Credited!';
      celebrationDesc = 'Incredible dedication! You unlocked Target 2 ($t2Target rides) and achieved the ₹$t2Total weekly grand bonus! ₹$t2Incremental has been automatically credited to your Instant Cashout balance!';
    }

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }

    setState(() {
      _totalEarnings += (netEarnings + incentiveBonusEarned);
      _completedRides.insert(0, newRide);
      _activeBooking = null;
      _currentIncomingBookingId = null;
      _driverStatus = 'online';
      _isOnline = true;
      _driverRoutePoints = [];
      _otpError = '';
      _otpTextController.clear();
      _isPilotNavigationOpen = false;
    });

    BookingManager().clearBooking();
    BookingManager().setDriverOnline(true);
    _loadProfileData();

    if (celebrationTitle.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFF59E0B), width: 1.5),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.emoji_events_rounded, color: Color(0xFFF59E0B), size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  celebrationTitle,
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            celebrationDesc,
            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFFCBD5E1), height: 1.4),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Claim & Awesome!', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
  }

  IconData _getVehicleIcon(String vehicle) {
    final v = vehicle.toLowerCase();
    if (v.contains('food')) {
      return Icons.fastfood_rounded;
    }
    if (v.contains('scooty') || v.contains('bike') || v.contains('motorcycle')) {
      return Icons.two_wheeler_rounded;
    }
    if (v.contains('auto') || v.contains('rickshaw')) {
      return Icons.electric_rickshaw_rounded;
    }
    if (v.contains('mini truck')) {
      return Icons.airport_shuttle_rounded;
    }
    if (v.contains('heavy truck') || v.contains('truck')) {
      return Icons.local_shipping_rounded;
    }
    if (v.contains('xl')) {
      return Icons.directions_car_filled_rounded;
    }
    return Icons.directions_car_rounded;
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
          rotation: BookingManager().driverHeading,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(title: 'You (Pilot)', snippet: 'Vehicle: $_selectedVehicle • Online'),
        ),
      };
    }
    
    final pickup = NavigationEngine.extractPickupLatLng(_activeBooking);
    final drop = NavigationEngine.extractDropLatLng(_activeBooking);

    final Set<Marker> markers = {
      Marker(
        markerId: const MarkerId('driver_pos'),
        position: _driverMapCenter!,
        rotation: BookingManager().driverHeading,
        anchor: const Offset(0.5, 0.5),
        flat: true,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'You (Pilot)'),
      ),
    };
    
    if (_driverStatus == 'heading_to_pickup' || _driverStatus == 'accepted' || _driverStatus == 'arrived_pickup') {
      if (pickup != null) {
        markers.add(
          Marker(
            markerId: const MarkerId('pickup_pos'),
            position: pickup,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            infoWindow: InfoWindow(title: 'Customer Pickup', snippet: _activeBooking!['pickup'] ?? 'Pickup Location'),
          ),
        );
      }
    } else if (_driverStatus == 'on_trip' || _driverStatus == 'started') {
      if (drop != null) {
        markers.add(
          Marker(
            markerId: const MarkerId('drop_pos'),
            position: drop,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(title: 'Customer Destination', snippet: _activeBooking!['drop'] ?? 'Dropoff Location'),
          ),
        );
      }
    }
    
    return markers;
  }

  Set<Polyline> _getDriverPolylines() {
    if (_activeBooking == null || _driverMapCenter == null) return {};
    
    final pickup = NavigationEngine.extractPickupLatLng(_activeBooking);
    final drop = NavigationEngine.extractDropLatLng(_activeBooking);

    if (_driverStatus == 'heading_to_pickup' || _driverStatus == 'accepted' || _driverStatus == 'arrived_pickup') {
      if (pickup == null) return {};
      return {
        Polyline(
          polylineId: const PolylineId('to_pickup'),
          color: const Color(0xFF1A73E8), // Google Maps Blue
          points: _driverRoutePoints.isNotEmpty ? _driverRoutePoints : [_driverMapCenter!, pickup],
          width: 5,
        ),
      };
    } else if (_driverStatus == 'on_trip' || _driverStatus == 'started') {
      if (drop == null) return {};
      return {
        Polyline(
          polylineId: const PolylineId('to_drop'),
          color: const Color(0xFF1A73E8), // Google Maps Blue
          points: _driverRoutePoints.isNotEmpty ? _driverRoutePoints : [_driverMapCenter!, drop],
          width: 5,
        ),
      };
    }
    return {};
  }

  Future<void> _updateDriverApproval(String uid, String name, String phone, bool approved, {String reason = ''}) async {
    final driverData = {
      'uid': uid,
      'name': name,
      'phone': phone,
    };
    if (approved) {
      await _confirmAndApprovePilot(driverData);
    } else {
      if (reason.isNotEmpty) {
        try {
          final baseUrl = NetworkConfig.backendUrl;
          final rejectUrl = Uri.parse('$baseUrl/api/admin/driver/reject');
          await ApiClient().post(
            rejectUrl,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'uid': uid,
              'pilotId': uid,
              'phone': phone,
              'adminId': FirebaseService().currentUid ?? 'admin',
              'adminName': widget.userName.isNotEmpty ? widget.userName : 'StayDriv Admin',
              'reason': reason,
            }),
          );
          await _fetchAdminDataOnce();
        } catch (_) {}
      } else {
        await _confirmAndRejectPilot(driverData);
      }
    }
  }

  Future<void> _confirmAndApprovePilot(Map<String, dynamic> driverData) async {
    final uid = (driverData['uid'] ?? driverData['pilotId'] ?? '').toString();
    final name = (driverData['name'] ?? driverData['driverName'] ?? 'Pilot Partner').toString();
    final phone = (driverData['phone'] ?? driverData['driverPhone'] ?? '').toString();
    final vehicle = (driverData['vehicleType'] ?? 'Vehicle').toString();
    final plate = (driverData['vehiclePlate'] ?? driverData['vehicleNumber'] ?? '').toString();

    if (_approvingUids.contains(uid)) return; // Prevent duplicate tap

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.verified_user_rounded, color: Color(0xFF16A34A), size: 24),
            const SizedBox(width: 8),
            Text('Approve Pilot?', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Text(
          'Are you sure you want to approve $name (${plate.isNotEmpty ? plate : vehicle})?\n\nAfter approval, the pilot will receive an instant notification, can go online, and start accepting customer bookings.',
          style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: AppTheme.onSurfaceColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Approve', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (_approvingUids.contains(uid)) return;
    setState(() {
      _approvingUids.add(uid);
    });

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final approveUrl = Uri.parse('$baseUrl/api/admin/driver/approve');
      final response = await ApiClient().post(
        approveUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': uid,
          'pilotId': uid,
          'phone': phone,
          'adminId': FirebaseService().currentUid ?? 'admin',
          'adminName': widget.userName.isNotEmpty ? widget.userName : 'StayDriv Admin',
          'reason': 'Application and all KYC documents verified by Admin',
        }),
      );

      if (response.statusCode == 200) {
        setState(() {
          final idx = _mongoAdminDrivers.indexWhere((d) => (d['uid'] == uid || (d['phone'] != null && phone.isNotEmpty && d['phone'].toString().contains(phone))));
          if (idx != -1) {
            _mongoAdminDrivers[idx]['approved'] = true;
            _mongoAdminDrivers[idx]['isApproved'] = true;
            _mongoAdminDrivers[idx]['status'] = 'approved';
            _mongoAdminDrivers[idx]['applicationStatus'] = 'APPROVED';
          }
          _approvingUids.remove(uid);
          if (_selectedDriverForDocApproval != null && (_selectedDriverForDocApproval!['uid'] == uid || _selectedDriverForDocApproval!['phone'] == phone)) {
            _selectedDriverForDocApproval = null;
          }
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ Pilot $name has been APPROVED. Real-time update sent.'),
              backgroundColor: const Color(0xFF16A34A),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        await _fetchAdminDataOnce();
      } else {
        setState(() {
          _approvingUids.remove(uid);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to approve pilot. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error approving pilot: $e");
      setState(() {
        _approvingUids.remove(uid);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to approve pilot. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _confirmAndRejectPilot(Map<String, dynamic> driverData) async {
    final uid = (driverData['uid'] ?? driverData['pilotId'] ?? '').toString();
    final name = (driverData['name'] ?? driverData['driverName'] ?? 'Pilot Partner').toString();
    final phone = (driverData['phone'] ?? driverData['driverPhone'] ?? '').toString();

    if (_rejectingUids.contains(uid)) return;

    final reasonCtrl = TextEditingController();
    final confirmedReason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.cancel_outlined, color: Color(0xFFDC2626), size: 24),
            const SizedBox(width: 8),
            Text('Reject Pilot Application', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Specify rejection reason for $name. The pilot will see this reason in their app.',
              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'e.g. Blurry driving license, RC plate mismatch, expired insurance',
                hintStyle: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade400),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () {
              final r = reasonCtrl.text.trim();
              if (r.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Please enter a rejection reason')),
                );
                return;
              }
              Navigator.pop(ctx, r);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Reject Application', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmedReason == null || confirmedReason.trim().isEmpty) return;

    if (_rejectingUids.contains(uid)) return;
    setState(() {
      _rejectingUids.add(uid);
    });

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final rejectUrl = Uri.parse('$baseUrl/api/admin/driver/reject');
      final response = await ApiClient().post(
        rejectUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': uid,
          'pilotId': uid,
          'phone': phone,
          'adminId': FirebaseService().currentUid ?? 'admin',
          'adminName': widget.userName.isNotEmpty ? widget.userName : 'StayDriv Admin',
          'reason': confirmedReason.trim(),
        }),
      );

      if (response.statusCode == 200) {
        setState(() {
          final idx = _mongoAdminDrivers.indexWhere((d) => (d['uid'] == uid || (d['phone'] != null && phone.isNotEmpty && d['phone'].toString().contains(phone))));
          if (idx != -1) {
            _mongoAdminDrivers[idx]['approved'] = false;
            _mongoAdminDrivers[idx]['isApproved'] = false;
            _mongoAdminDrivers[idx]['status'] = 'rejected';
            _mongoAdminDrivers[idx]['applicationStatus'] = 'REJECTED';
            _mongoAdminDrivers[idx]['rejectionReason'] = confirmedReason.trim();
          }
          _rejectingUids.remove(uid);
          if (_selectedDriverForDocApproval != null && (_selectedDriverForDocApproval!['uid'] == uid || _selectedDriverForDocApproval!['phone'] == phone)) {
            _selectedDriverForDocApproval = null;
          }
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✕ Pilot application rejected. Real-time alert dispatched to Pilot.'),
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        await _fetchAdminDataOnce();
      } else {
        setState(() {
          _rejectingUids.remove(uid);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to reject pilot. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error rejecting pilot: $e");
      setState(() {
        _rejectingUids.remove(uid);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to reject pilot. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showPilotDetailsDialog(Map<String, dynamic> driverData) {
    final uid = (driverData['uid'] ?? driverData['pilotId'] ?? '').toString();
    final name = (driverData['name'] ?? driverData['driverName'] ?? 'Pilot Partner').toString();
    final phone = (driverData['phone'] ?? driverData['driverPhone'] ?? '').toString();
    final vehicle = (driverData['vehicleType'] ?? 'Bike').toString();
    final plate = (driverData['vehiclePlate'] ?? driverData['vehicleNumber'] ?? 'Unassigned').toString();
    final modelColor = (driverData['vehicleModelColor'] ?? driverData['vehicleModel'] ?? 'Standard').toString();
    final appId = (driverData['applicationId'] ?? 'SD-PLT-PENDING').toString();
    final status = (driverData['status'] ?? driverData['applicationStatus'] ?? 'PENDING').toString().toUpperCase();
    final dor = (driverData['dor'] ?? driverData['submittedAt'] ?? driverData['createdAt'] ?? 'Recent').toString();
    final rejectionReason = (driverData['rejectionReason'] ?? '').toString();

    final photo = (driverData['photo'] ?? driverData['documents']?['photo']?['url']) as String?;
    final aadhaarFront = (driverData['aadhaarFront'] ?? driverData['documents']?['aadhaarFront']?['url']) as String?;
    final licenseFront = (driverData['licenseFront'] ?? driverData['documents']?['licenseFront']?['url']) as String?;
    final rcFront = (driverData['rcFront'] ?? driverData['documents']?['rcFront']?['url']) as String?;
    final insurance = (driverData['insuranceDocumentUrl'] ?? driverData['insuranceDocument'] ?? driverData['documents']?['insurance']?['url']) as String?;

    final isApproved = driverData['approved'] == true || status == 'APPROVED';
    final isApproving = _approvingUids.contains(uid);
    final isRejecting = _rejectingUids.contains(uid);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 44,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.orange.withOpacity(0.15),
                      radius: 22,
                      child: Icon(_getVehicleIcon(vehicle), color: Colors.orange.shade800, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: GoogleFonts.hankenGrotesk(fontSize: 18, fontWeight: FontWeight.bold)),
                          Text('App ID: $appId', style: GoogleFonts.robotoMono(fontSize: 11, color: AppTheme.primaryColor, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isApproved ? Colors.green.withOpacity(0.12) : (status == 'REJECTED' ? Colors.red.withOpacity(0.12) : Colors.orange.withOpacity(0.12)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status,
                        style: GoogleFonts.robotoMono(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isApproved ? Colors.green.shade800 : (status == 'REJECTED' ? Colors.red.shade800 : Colors.orange.shade900),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildDetailsSectionHeader('Personal Information', Icons.person_outline_rounded),
                    const SizedBox(height: 8),
                    _buildDetailsInfoRow('Full Name', name),
                    _buildDetailsInfoRow('Mobile Number', '+91 $phone'),
                    _buildDetailsInfoRow('Pilot UID', uid),
                    _buildDetailsInfoRow('Registration Date', dor.length > 10 ? dor.substring(0, 10) : dor),

                    const SizedBox(height: 18),

                    _buildDetailsSectionHeader('Vehicle Information', Icons.two_wheeler_rounded),
                    const SizedBox(height: 8),
                    _buildDetailsInfoRow('Vehicle Type', vehicle),
                    _buildDetailsInfoRow('License Plate', plate),
                    _buildDetailsInfoRow('Model & Color', modelColor),

                    const SizedBox(height: 18),

                    _buildDetailsSectionHeader('Submitted KYC Documents', Icons.description_outlined),
                    const SizedBox(height: 8),
                    _buildDocCheckRow('Aadhaar Card', aadhaarFront != null && aadhaarFront.isNotEmpty),
                    _buildDocCheckRow('Driving License', licenseFront != null && licenseFront.isNotEmpty),
                    _buildDocCheckRow('Vehicle RC', rcFront != null && rcFront.isNotEmpty),
                    _buildDocCheckRow('Driver Photo', photo != null && photo.isNotEmpty),
                    _buildDocCheckRow('Vehicle Insurance', insurance != null && insurance.isNotEmpty),

                    if (rejectionReason.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _buildDetailsSectionHeader('Rejection Notes', Icons.report_problem_outlined),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(
                          rejectionReason,
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.red.shade800),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, -4)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _callUser(phone),
                            icon: const Icon(Icons.call, size: 16, color: AppTheme.primaryColor),
                            label: const Text('Call Pilot'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              setState(() {
                                _selectedDriverForDocApproval = driverData;
                              });
                            },
                            icon: const Icon(Icons.document_scanner_outlined, size: 16, color: AppTheme.primaryColor),
                            label: const Text('View Docs'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!isApproved) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: isApproving || isRejecting
                                  ? null
                                  : () async {
                                      Navigator.pop(ctx);
                                      await _confirmAndApprovePilot(driverData);
                                    },
                              icon: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                              label: const Text('Approve Pilot', style: TextStyle(fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF16A34A),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: isApproving || isRejecting
                                  ? null
                                  : () async {
                                      Navigator.pop(ctx);
                                      await _confirmAndRejectPilot(driverData);
                                    },
                              icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFFDC2626)),
                              label: const Text('✕ Reject', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFDC2626)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
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

  Widget _buildDetailsSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.primaryColor),
        const SizedBox(width: 6),
        Text(
          title,
          style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
        ),
      ],
    );
  }

  Widget _buildDetailsInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant)),
          Text(value, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.onSurfaceColor)),
        ],
      ),
    );
  }

  Widget _buildDocCheckRow(String docTitle, bool isUploaded) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(docTitle, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant)),
          Row(
            children: [
              Icon(isUploaded ? Icons.check_circle_rounded : Icons.cancel_outlined,
                  size: 14, color: isUploaded ? const Color(0xFF16A34A) : Colors.red.shade400),
              const SizedBox(width: 4),
              Text(
                isUploaded ? 'Uploaded' : 'Missing',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isUploaded ? const Color(0xFF16A34A) : Colors.red.shade400,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDocApprovalDetailView(Map<String, dynamic> driverData) {
    final uid = (driverData['uid'] ?? driverData['pilotId'] ?? '').toString();
    final name = (driverData['name'] ?? driverData['driverName'] ?? 'Pilot Partner').toString();
    final phone = (driverData['phone'] ?? driverData['driverPhone'] ?? '').toString();
    final vehicleType = (driverData['vehicleType'] ?? 'Bike').toString();
    final vehiclePlate = (driverData['vehiclePlate'] ?? driverData['vehicleNumber'] ?? 'Unassigned').toString();
    final isApproved = driverData['approved'] == true || (driverData['status']?.toString().toLowerCase() == 'approved');

    final photo = (driverData['photo'] ?? driverData['documents']?['photo']?['url']) as String?;
    final aadhaarFront = (driverData['aadhaarFront'] ?? driverData['documents']?['aadhaarFront']?['url']) as String?;
    final aadhaarBack = (driverData['aadhaarBack'] ?? driverData['documents']?['aadhaarBack']?['url']) as String?;
    final licenseFront = (driverData['licenseFront'] ?? driverData['documents']?['licenseFront']?['url']) as String?;
    final licenseBack = (driverData['licenseBack'] ?? driverData['documents']?['licenseBack']?['url']) as String?;
    final rcFront = (driverData['rcFront'] ?? driverData['documents']?['rcFront']?['url']) as String?;
    final rcBack = (driverData['rcBack'] ?? driverData['documents']?['rcBack']?['url']) as String?;
    final insurance = (driverData['insuranceDocumentUrl'] ?? driverData['insuranceDocument'] ?? driverData['documents']?['insurance']?['url']) as String?;
    final vehiclePhoto = (driverData['vehiclePhoto'] ?? driverData['documents']?['vehiclePhoto']?['url']) as String?;
    final fitness = (driverData['fitness'] ?? driverData['documents']?['fitness']?['url']) as String?;
    final permit = (driverData['permit'] ?? driverData['documents']?['permit']?['url']) as String?;

    final showExtraDocs = vehicleType == 'Car' || vehicleType == 'Mini Truck' || vehicleType == 'Heavy Truck';
    final isApproving = _approvingUids.contains(uid);
    final isRejecting = _rejectingUids.contains(uid);

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
            _buildDocPreviewCard('Vehicle Insurance', Icons.security_rounded, insurance),
            if (vehiclePhoto != null && vehiclePhoto.isNotEmpty)
              _buildDocPreviewCard('Vehicle Photo', Icons.directions_car_filled_outlined, vehiclePhoto),
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
              child: OutlinedButton.icon(
                onPressed: isApproving || isRejecting ? null : () => _confirmAndRejectPilot(driverData),
                icon: isRejecting
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.red, strokeWidth: 2))
                    : const Icon(Icons.close_rounded, color: Colors.red),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                label: Text(
                  isRejecting ? 'Rejecting...' : 'Reject Application',
                  style: GoogleFonts.hankenGrotesk(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: isApproving || isRejecting ? null : () => _confirmAndApprovePilot(driverData),
                icon: isApproving
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check_rounded, color: Colors.white),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                label: Text(
                  isApproving ? 'Approving...' : 'Approve Pilot',
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
    final hasUploaded = docUrl != null && docUrl.trim().isNotEmpty;
    final String resolvedUrl = (docUrl != null && docUrl.startsWith('/'))
        ? '${NetworkConfig.backendUrl}$docUrl'
        : (docUrl ?? '');

    return InkWell(
      onTap: () {
        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      docName,
                      style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasUploaded)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.green.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                      child: Text('VERIFIED', style: GoogleFonts.robotoMono(fontSize: 10, color: Colors.green.shade800, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 280,
                child: hasUploaded
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: InteractiveViewer(
                          panEnabled: true,
                          boundaryMargin: const EdgeInsets.all(20),
                          minScale: 0.8,
                          maxScale: 4.0,
                          child: Image.network(
                            resolvedUrl,
                            fit: BoxFit.contain,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const Center(child: CircularProgressIndicator());
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey),
                                    const SizedBox(height: 8),
                                    Text('Unable to load document image', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, size: 48, color: AppTheme.outlineColor),
                          const SizedBox(height: 12),
                          Text(
                            'No Document Uploaded',
                            style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Pilot has not submitted this file yet.',
                            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant),
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
        customers: _mongoAdminCustomers,
        complaints: _adminComplaints,
        refunds: _adminRefunds,
        isLoading: _isAdminLoading && _mongoAdminBookings.isEmpty,
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
                : _mongoAdminBookings;
            final List<Map<String, dynamic>> driversList = driversSnapshot.hasData
                ? driversSnapshot.data!.docs.map((doc) => doc.data() as Map<String, dynamic>).toList()
                : _mongoAdminDrivers;

            return _buildAdminDashboardContent(
              bookings: bookingsList,
              drivers: driversList,
              customers: _mongoAdminCustomers,
              complaints: _adminComplaints,
              refunds: _adminRefunds,
              isLoading: (_isAdminLoading || !bookingsSnapshot.hasData) && _mongoAdminBookings.isEmpty,
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

  // Admin & Staff Operations
  Future<void> _callUser(String phone) async {
    if (phone.isEmpty) return;
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not launch phone dialer for +91 $cleanPhone')),
          );
        }
      }
    } catch (e) {
      debugPrint("Error launching call: $e");
    }
  }

  Future<void> _toggleBlockUser({
    required String uid,
    required String phone,
    required String role,
    required bool isBlocked,
    String? reason,
  }) async {
    try {
      final baseUrl = NetworkConfig.backendUrl;
      final url = Uri.parse('$baseUrl/api/admin/user/block');
      final resp = await ApiClient().post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': uid,
          'phone': phone,
          'role': role,
          'isBlocked': isBlocked,
          'reason': reason ?? (isBlocked ? 'Blocked by Admin/Staff' : ''),
        }),
      );
      if (resp.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isBlocked ? 'User blocked successfully' : 'User unblocked successfully'),
              backgroundColor: isBlocked ? Colors.red : Colors.green,
            ),
          );
        }
        await _fetchAdminDataOnce();
      }
    } catch (e) {
      debugPrint("Error updating block status: $e");
    }
  }

  Future<void> _resolveComplaint({
    required String complaintId,
    String? notes,
  }) async {
    try {
      final baseUrl = NetworkConfig.backendUrl;
      final url = Uri.parse('$baseUrl/api/admin/complaint/resolve');
      final resp = await ApiClient().post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'complaintId': complaintId,
          'resolutionNotes': notes ?? 'Resolved by ${widget.userRole}',
        }),
      );
      if (resp.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Complaint marked as resolved'),
              backgroundColor: Colors.green,
            ),
          );
        }
        await _fetchAdminDataOnce();
      }
    } catch (e) {
      debugPrint("Error resolving complaint: $e");
    }
  }

  Future<void> _resolveRefund({
    required String refundId,
    required String status, // 'processed' or 'rejected'
  }) async {
    try {
      final baseUrl = NetworkConfig.backendUrl;
      final url = Uri.parse('$baseUrl/api/admin/refund/resolve');
      final resp = await ApiClient().post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'refundId': refundId,
          'status': status,
          'processedBy': widget.userRole,
        }),
      );
      if (resp.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Refund $status successfully'),
              backgroundColor: status == 'processed' ? Colors.green : Colors.red,
            ),
          );
        }
        await _fetchAdminDataOnce();
      }
    } catch (e) {
      debugPrint("Error resolving refund: $e");
    }
  }

  void _showBlockUserDialog({
    required String role, // 'partner' or 'customer'
    String? presetUid,
    String? presetPhone,
    String? presetName,
  }) {
    final phoneCtrl = TextEditingController(text: presetPhone ?? '');
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.block_rounded, color: Colors.red),
            const SizedBox(width: 8),
            Text(
              role == 'partner' ? 'Block Pilot' : 'Block Customer',
              style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (presetName != null) ...[
              Text(
                'Name: $presetName',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Phone Number',
                hintText: '10-digit phone',
                prefixText: '+91 ',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Reason for Blocking',
                hintText: 'e.g. Abusive behaviour, fraud, non-compliance',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              if (phoneCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              await _toggleBlockUser(
                uid: presetUid ?? '',
                phone: phoneCtrl.text.trim(),
                role: role,
                isBlocked: true,
                reason: reasonCtrl.text.trim().isNotEmpty ? reasonCtrl.text.trim() : 'Blocked by Admin/Staff',
              );
            },
            child: const Text('Confirm Block'),
          ),
        ],
      ),
    );
  }

  void _showCreateComplaintDialog({String? defaultType}) {
    String selectedType = defaultType ?? 'miss_behave_with_pilot';
    final repNameCtrl = TextEditingController();
    final repPhoneCtrl = TextEditingController();
    final targetNameCtrl = TextEditingController();
    final targetPhoneCtrl = TextEditingController();
    final bookingIdCtrl = TextEditingController();
    final subjectCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Log Incident / Complaint',
            style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'miss_behave_with_pilot', child: Text('Miss Behave with Pilot')),
                    DropdownMenuItem(value: 'miss_behave_with_customer', child: Text('Miss Behave with Customer')),
                    DropdownMenuItem(value: 'general_complaint', child: Text('General Complaint / Issue')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedType = val);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: repNameCtrl,
                  decoration: InputDecoration(
                    labelText: selectedType == 'miss_behave_with_pilot' ? 'Pilot Name' : 'Complainant / Customer Name',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: repPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Complainant Phone',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: targetNameCtrl,
                  decoration: InputDecoration(
                    labelText: selectedType == 'miss_behave_with_pilot' ? 'Customer Name (Offender)' : 'Pilot Name (Offender)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: bookingIdCtrl,
                  decoration: InputDecoration(
                    labelText: 'Booking ID (Optional)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: subjectCtrl,
                  decoration: InputDecoration(
                    labelText: 'Subject / Title',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Incident Description',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (descCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                try {
                  final baseUrl = NetworkConfig.backendUrl;
                  await ApiClient().post(
                    Uri.parse('$baseUrl/api/admin/complaint'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode({
                      'type': selectedType,
                      'reportedByRole': selectedType == 'miss_behave_with_pilot' ? 'partner' : 'customer',
                      'reportedByName': repNameCtrl.text.trim().isNotEmpty ? repNameCtrl.text.trim() : 'User',
                      'reportedByPhone': repPhoneCtrl.text.trim(),
                      'targetName': targetNameCtrl.text.trim(),
                      'targetPhone': targetPhoneCtrl.text.trim(),
                      'bookingId': bookingIdCtrl.text.trim(),
                      'subject': subjectCtrl.text.trim().isNotEmpty ? subjectCtrl.text.trim() : 'Incident Report',
                      'description': descCtrl.text.trim(),
                    }),
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Incident logged successfully'), backgroundColor: Colors.green),
                    );
                  }
                  await _fetchAdminDataOnce();
                } catch (e) {
                  debugPrint("Error creating complaint: $e");
                }
              },
              child: const Text('Save Incident'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateRefundDialog({String defaultType = 'customer'}) {
    String refundType = defaultType;
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final bookingIdCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Add Pending Refund Request',
            style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: refundType,
                  decoration: InputDecoration(
                    labelText: 'Refund Beneficiary',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'customer', child: Text('Customer Refund')),
                    DropdownMenuItem(value: 'pilot', child: Text('Pilot Payout / Refund')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => refundType = val);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: bookingIdCtrl,
                  decoration: InputDecoration(
                    labelText: 'Booking ID',
                    hintText: 'e.g. BK-10822',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: refundType == 'customer' ? 'Customer Name' : 'Pilot Name',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Amount (₹)',
                    hintText: 'e.g. 150',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: reasonCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Reason for Refund',
                    hintText: 'e.g. Cancelled ride prepaid, route dispute',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (amountCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                try {
                  final baseUrl = NetworkConfig.backendUrl;
                  await ApiClient().post(
                    Uri.parse('$baseUrl/api/admin/refund'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode({
                      'refundType': refundType,
                      'bookingId': bookingIdCtrl.text.trim(),
                      'userName': nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : 'User',
                      'userPhone': phoneCtrl.text.trim(),
                      'amount': '₹${amountCtrl.text.trim().replaceAll('₹', '').trim()}',
                      'reason': reasonCtrl.text.trim().isNotEmpty ? reasonCtrl.text.trim() : 'Booking cancellation adjustment',
                    }),
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Refund request added successfully'), backgroundColor: Colors.green),
                    );
                  }
                  await _fetchAdminDataOnce();
                } catch (e) {
                  debugPrint("Error creating refund: $e");
                }
              },
              child: const Text('Submit Refund'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminDashboardContent({
    required List<Map<String, dynamic>> bookings,
    required List<Map<String, dynamic>> drivers,
    List<Map<String, dynamic>>? customers,
    List<Map<String, dynamic>>? complaints,
    List<Map<String, dynamic>>? refunds,
    required bool isLoading,
  }) {
    final allCustomers = customers ?? _mongoAdminCustomers;
    final allComplaints = complaints ?? _adminComplaints;
    final allRefunds = refunds ?? _adminRefunds;

    final activeDrivers = drivers.length;
    final searchingBookings = bookings.where((b) => b['status'] == 'searching').length;
    final pendingApprovalDrivers = drivers.where((d) => d['approved'] != true).length;
    final blockedPilotsCount = drivers.where((d) => d['isBlocked'] == true).length;
    final blockedCustomersCount = allCustomers.where((c) => c['isBlocked'] == true).length;
    final missBehaveWithPilotCount = allComplaints.where((c) => c['type'] == 'miss_behave_with_pilot').length;
    final missBehaveWithCustomerCount = allComplaints.where((c) => c['type'] == 'miss_behave_with_customer').length;
    final customerRefundsCount = allRefunds.where((r) => r['refundType'] == 'customer' && r['status'] == 'pending').length;
    final pilotRefundsCount = allRefunds.where((r) => r['refundType'] == 'pilot' && r['status'] == 'pending').length;
    final anyComplaintsCount = allComplaints.where((c) => c['status'] == 'pending').length;

    // Filtered collections by search query
    final query = _adminSearchQuery.toLowerCase().trim();

    final filteredBookings = bookings.where((b) {
      if (query.isEmpty) return true;
      final title = (b['title'] ?? '').toString().toLowerCase();
      final pickup = (b['pickup'] ?? '').toString().toLowerCase();
      final drop = (b['drop'] ?? '').toString().toLowerCase();
      final driver = (b['driverName'] ?? '').toString().toLowerCase();
      final status = (b['status'] ?? '').toString().toLowerCase();
      return title.contains(query) || pickup.contains(query) || drop.contains(query) || driver.contains(query) || status.contains(query);
    }).toList();

    final filteredPendingDrivers = drivers.where((d) => d['approved'] != true).where((d) {
      if (query.isEmpty) return true;
      final name = (d['name'] ?? '').toString().toLowerCase();
      final phone = (d['phone'] ?? '').toString().toLowerCase();
      final vehicle = (d['vehicleType'] ?? '').toString().toLowerCase();
      final plate = (d['vehiclePlate'] ?? '').toString().toLowerCase();
      return name.contains(query) || phone.contains(query) || vehicle.contains(query) || plate.contains(query);
    }).toList();

    final filteredBlockedPilots = drivers.where((d) => d['isBlocked'] == true).where((d) {
      if (query.isEmpty) return true;
      final name = (d['name'] ?? '').toString().toLowerCase();
      final phone = (d['phone'] ?? '').toString().toLowerCase();
      final reason = (d['blockReason'] ?? '').toString().toLowerCase();
      return name.contains(query) || phone.contains(query) || reason.contains(query);
    }).toList();

    final filteredBlockedCustomers = allCustomers.where((c) => c['isBlocked'] == true).where((c) {
      if (query.isEmpty) return true;
      final name = (c['name'] ?? '').toString().toLowerCase();
      final phone = (c['phone'] ?? '').toString().toLowerCase();
      final reason = (c['blockReason'] ?? '').toString().toLowerCase();
      return name.contains(query) || phone.contains(query) || reason.contains(query);
    }).toList();

    final filteredMissBehavePilot = allComplaints.where((c) => c['type'] == 'miss_behave_with_pilot').where((c) {
      if (query.isEmpty) return true;
      final text = "${c['reportedByName']} ${c['reportedByPhone']} ${c['targetName']} ${c['subject']} ${c['description']}".toLowerCase();
      return text.contains(query);
    }).toList();

    final filteredMissBehaveCustomer = allComplaints.where((c) => c['type'] == 'miss_behave_with_customer').where((c) {
      if (query.isEmpty) return true;
      final text = "${c['reportedByName']} ${c['reportedByPhone']} ${c['targetName']} ${c['subject']} ${c['description']}".toLowerCase();
      return text.contains(query);
    }).toList();

    final filteredCustomerRefunds = allRefunds.where((r) => r['refundType'] == 'customer').where((r) {
      if (query.isEmpty) return true;
      final text = "${r['userName']} ${r['userPhone']} ${r['bookingId']} ${r['amount']} ${r['reason']}".toLowerCase();
      return text.contains(query);
    }).toList();

    final filteredPilotRefunds = allRefunds.where((r) => r['refundType'] == 'pilot').where((r) {
      if (query.isEmpty) return true;
      final text = "${r['userName']} ${r['userPhone']} ${r['bookingId']} ${r['amount']} ${r['reason']}".toLowerCase();
      return text.contains(query);
    }).toList();

    final filteredAllComplaints = allComplaints.where((c) {
      if (_complaintFilterStatus != 'all' && c['status'] != _complaintFilterStatus) return false;
      if (query.isEmpty) return true;
      final text = "${c['complaintId']} ${c['reportedByName']} ${c['reportedByPhone']} ${c['subject']} ${c['description']}".toLowerCase();
      return text.contains(query);
    }).toList();

    final filteredAllCustomers = allCustomers.where((c) {
      if (query.isEmpty) return true;
      final text = "${c['name']} ${c['phone']} ${c['email']} ${c['uid']}".toLowerCase();
      return text.contains(query);
    }).toList();

    final filteredAllPilots = drivers.where((d) {
      if (query.isEmpty) return true;
      final text = "${d['name']} ${d['phone']} ${d['vehicleType']} ${d['vehiclePlate']} ${d['uid']}".toLowerCase();
      return text.contains(query);
    }).toList();

    final filteredPayments = _adminPayments.where((p) {
      if (query.isEmpty) return true;
      final text = "${p['orderId']} ${p['paymentId']} ${p['bookingId']} ${p['phone']} ${p['status']} ${p['method']}".toLowerCase();
      return text.contains(query);
    }).toList();

    final isStaff = widget.userRole == 'Staff';

    return Column(
      children: [
        // Top App Bar
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
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
                        } else if (_adminSelectedTab != 0) {
                          setState(() {
                            _adminSelectedTab = 0;
                          });
                        }
                      },
                    ),
                    const SizedBox(width: 4),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isStaff ? Colors.indigo.shade700 : AppTheme.primaryColor,
                      ),
                      child: Icon(
                        isStaff ? Icons.badge_outlined : Icons.admin_panel_settings,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isStaff ? 'Staff Console' : 'Admin Console',
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
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.sync_rounded, color: AppTheme.primaryColor),
                      tooltip: 'Refresh Data',
                      onPressed: () async {
                        await _fetchAdminDataOnce();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Console data refreshed'), duration: Duration(seconds: 1)),
                          );
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout_rounded, color: AppTheme.errorColor),
                      tooltip: 'Logout',
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
              ],
            ),
          ),
        ),

        // Horizontal Scrollable Tabs
        Container(
          height: 44,
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _buildTabPill(0, 'All Bookings', bookings.length, Icons.receipt_long_rounded),
              _buildTabPill(1, 'Pilot Pending Approval', pendingApprovalDrivers, Icons.how_to_reg_rounded),
              _buildTabPill(2, 'Blocked Pilot', blockedPilotsCount, Icons.block_rounded),
              _buildTabPill(3, 'Blocked Customer', blockedCustomersCount, Icons.person_off_rounded),
              _buildTabPill(4, 'Miss Behave with Pilot', missBehaveWithPilotCount, Icons.report_problem_rounded),
              _buildTabPill(5, 'Miss Behave with Customer', missBehaveWithCustomerCount, Icons.warning_amber_rounded),
              _buildTabPill(6, 'Refund Payments Pending for Customers', customerRefundsCount, Icons.currency_rupee_rounded),
              _buildTabPill(7, 'Refund Payments Pending for Pilots', pilotRefundsCount, Icons.account_balance_wallet_rounded),
              _buildTabPill(8, 'Any Complaints', anyComplaintsCount, Icons.support_agent_rounded),
              _buildTabPill(9, 'All Customers', allCustomers.length, Icons.people_alt_rounded),
              _buildTabPill(10, 'All Pilots', drivers.length, Icons.badge_rounded),
              _buildTabPill(11, 'Payments & Invoices', _adminPayments.length, Icons.payments_rounded),
            ],
          ),
        ),

        // Stats and Dynamic Tab Content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: _selectedDriverForDocApproval != null
                ? _buildDocApprovalDetailView(_selectedDriverForDocApproval!)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Row Stats (Pilots Registered & Searching Rides)
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
                                  BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 4))
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
                                  BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 4))
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

                      const SizedBox(height: 16),

                      // "New Registration" Button matching Image 1
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AdminPilotRegistrationScreen(
                                  isStaff: isStaff,
                                  onSuccess: () async {
                                    await _fetchAdminDataOnce();
                                  },
                                ),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppTheme.onSurfaceColor,
                            elevation: 0,
                            side: BorderSide(
                              color: AppTheme.outlineVariant.withOpacity(0.5),
                              width: 1.2,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.person_add_alt_1_rounded,
                                color: AppTheme.primaryColor,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'New Registration',
                                style: GoogleFonts.hankenGrotesk(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.onSurfaceColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // 8 Bento Action Cards with red border indicator matching user image
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.35,
                        children: [
                          _buildAdminBentoCard(
                            tabIndex: 1,
                            title: 'New Registration of Pilot pending for Approval',
                            count: pendingApprovalDrivers,
                            icon: Icons.how_to_reg_rounded,
                            badgeColor: Colors.orange,
                          ),
                          _buildAdminBentoCard(
                            tabIndex: 2,
                            title: 'Blocked Pilot',
                            count: blockedPilotsCount,
                            icon: Icons.block_rounded,
                            badgeColor: Colors.red.shade700,
                          ),
                          _buildAdminBentoCard(
                            tabIndex: 3,
                            title: 'Blocked Customer',
                            count: blockedCustomersCount,
                            icon: Icons.person_off_rounded,
                            badgeColor: Colors.red.shade800,
                          ),
                          _buildAdminBentoCard(
                            tabIndex: 4,
                            title: 'Miss Behave with Pilot',
                            count: missBehaveWithPilotCount,
                            icon: Icons.report_problem_rounded,
                            badgeColor: Colors.deepOrange,
                          ),
                          _buildAdminBentoCard(
                            tabIndex: 5,
                            title: 'Miss Behave with Customer',
                            count: missBehaveWithCustomerCount,
                            icon: Icons.warning_amber_rounded,
                            badgeColor: Colors.purple.shade700,
                          ),
                          _buildAdminBentoCard(
                            tabIndex: 6,
                            title: 'Refund Payments Pending for Customers',
                            count: customerRefundsCount,
                            icon: Icons.currency_rupee_rounded,
                            badgeColor: Colors.green.shade700,
                          ),
                          _buildAdminBentoCard(
                            tabIndex: 7,
                            title: 'Refund Payments Pending for Pilots',
                            count: pilotRefundsCount,
                            icon: Icons.account_balance_wallet_rounded,
                            badgeColor: Colors.blue.shade700,
                          ),
                          _buildAdminBentoCard(
                            tabIndex: 8,
                            title: 'Any Complaints',
                            count: anyComplaintsCount,
                            icon: Icons.support_agent_rounded,
                            badgeColor: Colors.teal.shade700,
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Search Bar adapted to active tab
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
                            hintText: _getAdminSearchHintText(_adminSelectedTab),
                            hintStyle: GoogleFonts.inter(
                              fontSize: 13,
                              color: AppTheme.onSurfaceVariant.withOpacity(0.6),
                            ),
                            prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.primaryColor, size: 20),
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
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Dynamic Content Switcher Based on Tab
                      if (_adminSelectedTab == 0)
                        _buildAdminOverviewTab(filteredBookings, drivers, isLoading)
                      else if (_adminSelectedTab == 1)
                        _buildAdminPendingPilotsTab(filteredPendingDrivers)
                      else if (_adminSelectedTab == 2)
                        _buildAdminBlockedPilotsTab(filteredBlockedPilots)
                      else if (_adminSelectedTab == 3)
                        _buildAdminBlockedCustomersTab(filteredBlockedCustomers)
                      else if (_adminSelectedTab == 4)
                        _buildAdminMissBehaveTab(filteredMissBehavePilot, isWithPilot: true)
                      else if (_adminSelectedTab == 5)
                        _buildAdminMissBehaveTab(filteredMissBehaveCustomer, isWithPilot: false)
                      else if (_adminSelectedTab == 6)
                        _buildAdminRefundsTab(filteredCustomerRefunds, isCustomer: true)
                      else if (_adminSelectedTab == 7)
                        _buildAdminRefundsTab(filteredPilotRefunds, isCustomer: false)
                      else if (_adminSelectedTab == 8)
                        _buildAdminComplaintsTab(filteredAllComplaints)
                      else if (_adminSelectedTab == 9)
                        _buildAdminAllCustomersTab(filteredAllCustomers)
                      else if (_adminSelectedTab == 10)
                        _buildAdminAllPilotsTab(filteredAllPilots)
                      else if (_adminSelectedTab == 11)
                        _buildAdminPaymentsTab(filteredPayments),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabPill(int index, String label, int count, IconData icon) {
    final isSelected = _adminSelectedTab == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _adminSelectedTab = index;
          _adminSearchQuery = '';
          _adminSearchController.clear();
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : AppTheme.outlineVariant.withOpacity(0.5),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: AppTheme.primaryColor.withOpacity(0.25), blurRadius: 6, offset: const Offset(0, 2))]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : AppTheme.primaryColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? Colors.white : AppTheme.onSurfaceColor,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withOpacity(0.25) : AppTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.robotoMono(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : AppTheme.primaryColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminBentoCard({
    required int tabIndex,
    required String title,
    required int count,
    required IconData icon,
    required Color badgeColor,
  }) {
    final isSelected = _adminSelectedTab == tabIndex;

    return GestureDetector(
      onTap: () {
        setState(() {
          _adminSelectedTab = tabIndex;
          _adminSearchQuery = '';
          _adminSearchController.clear();
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          // RED BORDER IF ACTIVE / MATCHING USER'S RED BORDER SPECIFICATION
          border: Border.all(
            color: isSelected ? Colors.red : AppTheme.outlineVariant.withOpacity(0.4),
            width: isSelected ? 2.5 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected ? Colors.red.withOpacity(0.15) : Colors.black.withOpacity(0.03),
              blurRadius: isSelected ? 10 : 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: badgeColor, size: 20),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: GoogleFonts.robotoMono(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              title,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                color: isSelected ? Colors.red.shade900 : AppTheme.onSurfaceColor,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  String _getAdminSearchHintText(int tab) {
    switch (tab) {
      case 1:
        return 'Search pending pilots by name, phone, vehicle...';
      case 2:
        return 'Search blocked pilots by name, phone, reason...';
      case 3:
        return 'Search blocked customers by name, phone...';
      case 4:
        return 'Search misbehaviour incidents with pilots...';
      case 5:
        return 'Search misbehaviour incidents with customers...';
      case 6:
        return 'Search customer refunds by booking ID, phone...';
      case 7:
        return 'Search pilot refunds by pilot name, booking ID...';
      case 8:
        return 'Search complaints by ticket ID, subject...';
      case 9:
        return 'Search customers by name, phone, email...';
      case 10:
        return 'Search pilots by name, phone, vehicle plate...';
      case 11:
        return 'Search payments by payment ID, order ID, phone...';
      default:
        return 'Search bookings (pickup, dropoff, pilot, status)...';
    }
  }

  // View: Tab 0 Overview / Recent Bookings
  Widget _buildAdminOverviewTab(List<Map<String, dynamic>> filteredBookings, List<Map<String, dynamic>> drivers, bool isLoading) {
    final displayedBookings = filteredBookings.where((b) {
      final s = (b['status'] ?? '').toString().toLowerCase();
      if (_bookingStatusFilter == 'completed') return s == 'completed';
      if (_bookingStatusFilter == 'cancelled') return s == 'cancelled' || s == 'timed_out';
      if (_bookingStatusFilter == 'active') return s == 'searching' || s == 'accepted' || s == 'started' || s == 'incoming';
      return true;
    }).toList();

    final completedCount = filteredBookings.where((b) => (b['status'] ?? '').toString().toLowerCase() == 'completed').length;
    final cancelledCount = filteredBookings.where((b) {
      final s = (b['status'] ?? '').toString().toLowerCase();
      return s == 'cancelled' || s == 'timed_out';
    }).length;
    final activeCount = filteredBookings.where((b) {
      final s = (b['status'] ?? '').toString().toLowerCase();
      return s == 'searching' || s == 'accepted' || s == 'started' || s == 'incoming';
    }).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Bookings',
              style: GoogleFonts.hankenGrotesk(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.onSurfaceColor),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Text(
                'REAL-TIME',
                style: GoogleFonts.robotoMono(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.green),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Booking Status Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                label: Text('All (${filteredBookings.length})'),
                selected: _bookingStatusFilter == 'all',
                onSelected: (val) => setState(() => _bookingStatusFilter = 'all'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text('Completed ($completedCount)'),
                selected: _bookingStatusFilter == 'completed',
                onSelected: (val) => setState(() => _bookingStatusFilter = 'completed'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text('Cancelled ($cancelledCount)'),
                selected: _bookingStatusFilter == 'cancelled',
                onSelected: (val) => setState(() => _bookingStatusFilter = 'cancelled'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text('Active ($activeCount)'),
                selected: _bookingStatusFilter == 'active',
                onSelected: (val) => setState(() => _bookingStatusFilter = 'active'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (isLoading)
          const Center(child: CircularProgressIndicator())
        else if (displayedBookings.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            child: Text('No bookings found for selected filter', style: GoogleFonts.inter(color: AppTheme.onSurfaceVariant)),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: displayedBookings.length,
            itemBuilder: (context, index) {
              final data = displayedBookings[index];
              final status = data['status'] ?? 'searching';
              Color statusColor = Colors.orange;
              if (status == 'accepted' || status == 'started') statusColor = AppTheme.primaryColor;
              if (status == 'completed') statusColor = Colors.green;
              if (status == 'cancelled') statusColor = Colors.red;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RideDetailsScreen(ride: data),
                      ),
                    );
                  },
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
                              style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                              child: Text(
                                status.toString().toUpperCase(),
                                style: GoogleFonts.robotoMono(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('From: ${data['pickup'] ?? ""}', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text('To: ${data['drop'] ?? ""}', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Fare: ${data['price'] ?? "₹150"}', style: GoogleFonts.robotoMono(fontSize: 13, fontWeight: FontWeight.bold)),
                            if (data['driverName'] != null)
                              Text('Pilot: ${data['driverName']}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.primaryColor)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Icon(Icons.receipt_long_rounded, size: 14, color: AppTheme.primaryColor),
                            const SizedBox(width: 4),
                            Text(
                              'Tap to view invoice & journey details',
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primaryColor),
                            ),
                            const SizedBox(width: 2),
                            Icon(Icons.chevron_right_rounded, size: 16, color: AppTheme.primaryColor),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  // View: Tab 1 Pilot Pending Approvals
  Widget _buildAdminPendingPilotsTab(List<Map<String, dynamic>> pendingDrivers) {
    return Column(
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
                    'New Registration of Pilot pending for Approval',
                    style: GoogleFonts.hankenGrotesk(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.orange.shade900),
                  ),
                  Text('${pendingDrivers.length} pilots awaiting verification', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (pendingDrivers.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            alignment: Alignment.center,
            child: Column(
              children: [
                Icon(Icons.check_circle_outline_rounded, size: 48, color: Colors.green.shade600),
                const SizedBox(height: 8),
                Text('All registered pilots are approved!', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: pendingDrivers.length,
            itemBuilder: (context, index) {
              final data = pendingDrivers[index];
              final uid = (data['uid'] ?? data['pilotId'] ?? '').toString();
              final name = (data['name'] ?? data['driverName'] ?? 'Pilot Partner').toString();
              final phone = (data['phone'] ?? data['driverPhone'] ?? '').toString();
              final vehicle = (data['vehicleType'] ?? 'Bike').toString();
              final plate = (data['vehiclePlate'] ?? data['vehicleNumber'] ?? 'Pending Plate').toString();
              final isApproving = _approvingUids.contains(uid);
              final isRejecting = _rejectingUids.contains(uid);

              return Card(
                margin: const EdgeInsets.only(bottom: 14),
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.orange.withOpacity(0.4), width: 1.2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: Icon + Info + PENDING Badge
                      InkWell(
                        onTap: () => _showPilotDetailsDialog(data),
                        borderRadius: BorderRadius.circular(8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.orange.withOpacity(0.15),
                              child: Icon(_getVehicleIcon(vehicle), color: Colors.orange.shade800, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.onSurfaceColor),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Phone: +91 $phone',
                                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    plate.isNotEmpty && plate != 'Pending Plate'
                                        ? 'Vehicle: $plate ($vehicle)'
                                        : 'Vehicle: ($vehicle)',
                                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'PENDING',
                                style: GoogleFonts.robotoMono(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade900),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1, thickness: 0.8),
                      const SizedBox(height: 8),

                      // Action Buttons Row: Call, View Docs, Reject, Approve (All 4 visible on mobile portrait & landscape)
                      Align(
                        alignment: Alignment.centerRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // 1. Call Button
                              TextButton.icon(
                                onPressed: () => _callUser(phone),
                                icon: const Icon(Icons.call, size: 14, color: AppTheme.primaryColor),
                                label: Text(
                                  'Call',
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryColor),
                                ),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                              const SizedBox(width: 4),

                              // 2. View Docs Button
                              TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _selectedDriverForDocApproval = data;
                                  });
                                },
                                icon: const Icon(Icons.description_outlined, size: 14, color: AppTheme.primaryColor),
                                label: Text(
                                  'View Docs',
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryColor),
                                ),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                              const SizedBox(width: 4),

                              // 3. Reject Button
                              TextButton.icon(
                                onPressed: isApproving || isRejecting ? null : () => _confirmAndRejectPilot(data),
                                icon: isRejecting
                                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(color: Color(0xFFDC2626), strokeWidth: 1.5))
                                    : const Icon(Icons.close_rounded, size: 14, color: Color(0xFFDC2626)),
                                label: Text(
                                  isRejecting ? 'Rejecting...' : 'Reject',
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFDC2626)),
                                ),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                              const SizedBox(width: 6),

                              // 4. Approve Button
                              ElevatedButton.icon(
                                onPressed: isApproving || isRejecting ? null : () => _confirmAndApprovePilot(data),
                                icon: isApproving
                                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 1.5))
                                    : const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                                label: Text(
                                  isApproving ? 'Approving...' : 'Approve',
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF16A34A),
                                  disabledBackgroundColor: const Color(0xFF86EFAC),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  minimumSize: const Size(0, 32),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
            },
          ),
      ],
    );
  }

  // View: Tab 2 Blocked Pilots
  Widget _buildAdminBlockedPilotsTab(List<Map<String, dynamic>> blockedPilots) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Blocked Pilot', style: GoogleFonts.hankenGrotesk(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.red.shade900)),
                Text('${blockedPilots.length} pilots currently blocked', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant)),
              ],
            ),
            ElevatedButton.icon(
              onPressed: () => _showBlockUserDialog(role: 'partner'),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Block a Pilot'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (blockedPilots.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            alignment: Alignment.center,
            child: Column(
              children: [
                Icon(Icons.verified_user_rounded, size: 48, color: Colors.green.shade600),
                const SizedBox(height: 8),
                Text('No pilots are currently blocked', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: blockedPilots.length,
            itemBuilder: (context, index) {
              final data = blockedPilots[index];
              final uid = data['uid'] ?? '';
              final name = data['name'] ?? 'Pilot';
              final phone = data['phone'] ?? '';
              final reason = data['blockReason'] ?? 'Blocked by Administrator';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.red.withOpacity(0.4), width: 1.2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(backgroundColor: Colors.red.withOpacity(0.15), child: const Icon(Icons.block, color: Colors.red)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 16)),
                                Text('Phone: +91 $phone', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant)),
                                Text('Vehicle: ${data['vehiclePlate'] ?? "Plate"} (${data['vehicleType'] ?? "Vehicle"})', style: GoogleFonts.inter(fontSize: 12)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            child: Text('BLOCKED', style: GoogleFonts.robotoMono(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.red.withOpacity(0.06), borderRadius: BorderRadius.circular(8)),
                        child: Text('Reason: $reason', style: GoogleFonts.inter(fontSize: 12, color: Colors.red.shade900)),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed: () => _callUser(phone),
                                icon: const Icon(Icons.call, size: 16),
                                label: const Text('Call'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: () => _toggleBlockUser(uid: uid, phone: phone, role: 'partner', isBlocked: false),
                                icon: const Icon(Icons.lock_open_rounded, size: 16),
                                label: const Text('Unblock Pilot'),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  // View: Tab 3 Blocked Customers
  Widget _buildAdminBlockedCustomersTab(List<Map<String, dynamic>> blockedCustomers) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Blocked Customer', style: GoogleFonts.hankenGrotesk(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.red.shade900)),
                Text('${blockedCustomers.length} customers blocked', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant)),
              ],
            ),
            ElevatedButton.icon(
              onPressed: () => _showBlockUserDialog(role: 'customer'),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Block Customer'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (blockedCustomers.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            alignment: Alignment.center,
            child: Column(
              children: [
                Icon(Icons.verified_user_rounded, size: 48, color: Colors.green.shade600),
                const SizedBox(height: 8),
                Text('No customers are currently blocked', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: blockedCustomers.length,
            itemBuilder: (context, index) {
              final data = blockedCustomers[index];
              final uid = data['uid'] ?? '';
              final name = data['name'] ?? 'Customer';
              final phone = data['phone'] ?? '';
              final reason = data['blockReason'] ?? 'Blocked by Administrator';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.red.withOpacity(0.4), width: 1.2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(backgroundColor: Colors.red.withOpacity(0.15), child: const Icon(Icons.person_off, color: Colors.red)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 16)),
                                Text('Phone: +91 $phone', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            child: Text('BLOCKED', style: GoogleFonts.robotoMono(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.red.withOpacity(0.06), borderRadius: BorderRadius.circular(8)),
                        child: Text('Reason: $reason', style: GoogleFonts.inter(fontSize: 12, color: Colors.red.shade900)),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed: () => _callUser(phone),
                                icon: const Icon(Icons.call, size: 16),
                                label: const Text('Call'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: () => _toggleBlockUser(uid: uid, phone: phone, role: 'customer', isBlocked: false),
                                icon: const Icon(Icons.lock_open_rounded, size: 16),
                                label: const Text('Unblock Customer'),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  // View: Tab 4 & 5 Misbehaviour Incidents
  Widget _buildAdminMissBehaveTab(List<Map<String, dynamic>> items, {required bool isWithPilot}) {
    final title = isWithPilot ? 'Miss Behave with Pilot' : 'Miss Behave with Customer';
    final themeColor = isWithPilot ? Colors.deepOrange : Colors.purple.shade700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.hankenGrotesk(fontSize: 18, fontWeight: FontWeight.w700, color: themeColor)),
                  Text('${items.length} incidents reported', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant)),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => _showCreateComplaintDialog(defaultType: isWithPilot ? 'miss_behave_with_pilot' : 'miss_behave_with_customer'),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Log Incident'),
              style: ElevatedButton.styleFrom(backgroundColor: themeColor, foregroundColor: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            alignment: Alignment.center,
            child: Column(
              children: [
                Icon(Icons.shield_outlined, size: 48, color: Colors.green.shade600),
                const SizedBox(height: 8),
                Text('No misbehaviour incidents reported!', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final data = items[index];
              final complaintId = data['complaintId'] ?? '';
              final repName = data['reportedByName'] ?? 'Reporter';
              final repPhone = data['reportedByPhone'] ?? '';
              final targetName = data['targetName'] ?? 'Offender';
              final targetPhone = data['targetPhone'] ?? '';
              final bookingId = data['bookingId'] ?? '';
              final subject = data['subject'] ?? 'Incident';
              final desc = data['description'] ?? '';
              final status = data['status'] ?? 'pending';
              final isResolved = status == 'resolved';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: themeColor.withOpacity(0.3), width: 1),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.warning_rounded, color: themeColor, size: 20),
                              const SizedBox(width: 8),
                              Text(complaintId, style: GoogleFonts.robotoMono(fontWeight: FontWeight.bold, fontSize: 13)),
                              if (bookingId.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
                                  child: Text(bookingId, style: GoogleFonts.robotoMono(fontSize: 11)),
                                ),
                              ],
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isResolved ? Colors.green.withOpacity(0.12) : Colors.orange.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isResolved ? 'RESOLVED' : 'PENDING REVIEW',
                              style: GoogleFonts.robotoMono(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isResolved ? Colors.green : Colors.orange.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(subject, style: GoogleFonts.hankenGrotesk(fontSize: 15, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(desc, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.onSurfaceVariant)),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: themeColor.withOpacity(0.06), borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(isWithPilot ? 'Pilot (Victim):' : 'Customer (Victim):', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold)),
                                Text('$repName (+91 $repPhone)', style: GoogleFonts.inter(fontSize: 12)),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(isWithPilot ? 'Customer (Offender):' : 'Pilot (Offender):', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                                Text('$targetName ${targetPhone.isNotEmpty ? "(+91 $targetPhone)" : ""}', style: GoogleFonts.inter(fontSize: 12, color: Colors.red.shade900)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (repPhone.isNotEmpty)
                            TextButton.icon(
                              onPressed: () => _callUser(repPhone),
                              icon: const Icon(Icons.call, size: 16),
                              label: Text('Call ${isWithPilot ? "Pilot" : "Customer"}'),
                            ),
                          if (targetPhone.isNotEmpty)
                            TextButton.icon(
                              onPressed: () => _callUser(targetPhone),
                              icon: const Icon(Icons.call, size: 16, color: Colors.red),
                              label: Text('Call Offender', style: GoogleFonts.inter(color: Colors.red)),
                            ),
                          if (!isResolved) ...[
                            const SizedBox(width: 4),
                            ElevatedButton.icon(
                              onPressed: () => _resolveComplaint(complaintId: complaintId),
                              icon: const Icon(Icons.check, size: 16),
                              label: const Text('Resolve'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  // View: Tab 6 & 7 Refund Payments
  Widget _buildAdminRefundsTab(List<Map<String, dynamic>> refunds, {required bool isCustomer}) {
    final title = isCustomer ? 'Refund Payments Pending for Customers' : 'Refund Payments Pending for Pilots';
    final themeColor = isCustomer ? Colors.green.shade800 : Colors.blue.shade800;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.hankenGrotesk(fontSize: 17, fontWeight: FontWeight.w700, color: themeColor)),
                  Text('${refunds.length} refunds recorded', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant)),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => _showCreateRefundDialog(defaultType: isCustomer ? 'customer' : 'pilot'),
              icon: const Icon(Icons.add, size: 16),
              label: Text(isCustomer ? 'Add Refund' : 'Add Pilot Payout'),
              style: ElevatedButton.styleFrom(backgroundColor: themeColor, foregroundColor: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (refunds.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            alignment: Alignment.center,
            child: Column(
              children: [
                Icon(Icons.check_circle_outline, size: 48, color: Colors.green.shade600),
                const SizedBox(height: 8),
                Text('No pending refund payments!', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: refunds.length,
            itemBuilder: (context, index) {
              final data = refunds[index];
              final refundId = data['refundId'] ?? '';
              final bookingId = data['bookingId'] ?? '';
              final userName = data['userName'] ?? 'User';
              final userPhone = data['userPhone'] ?? '';
              final amount = data['amount'] ?? '₹0';
              final reason = data['reason'] ?? 'Cancellation refund';
              final paymentMethod = data['paymentMethod'] ?? 'Online';
              final status = data['status'] ?? 'pending';
              final isPending = status == 'pending';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: isPending ? Colors.orange.withOpacity(0.5) : Colors.green.withOpacity(0.4), width: 1.2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(refundId, style: GoogleFonts.robotoMono(fontWeight: FontWeight.bold, fontSize: 13)),
                              if (bookingId.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
                                  child: Text(bookingId, style: GoogleFonts.robotoMono(fontSize: 11)),
                                ),
                              ],
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isPending ? Colors.orange.withOpacity(0.12) : Colors.green.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              status.toString().toUpperCase(),
                              style: GoogleFonts.robotoMono(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isPending ? Colors.orange.shade900 : Colors.green,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Beneficiary: $userName', style: GoogleFonts.hankenGrotesk(fontSize: 15, fontWeight: FontWeight.bold)),
                          Text(amount, style: GoogleFonts.robotoMono(fontSize: 18, fontWeight: FontWeight.w800, color: themeColor)),
                        ],
                      ),
                      Text('Phone: +91 $userPhone', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant)),
                      Text('Payment Mode: $paymentMethod', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: themeColor.withOpacity(0.06), borderRadius: BorderRadius.circular(8)),
                        child: Text('Reason: $reason', style: GoogleFonts.inter(fontSize: 12)),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (userPhone.isNotEmpty)
                            TextButton.icon(
                              onPressed: () => _callUser(userPhone),
                              icon: const Icon(Icons.call, size: 16),
                              label: const Text('Call'),
                            ),
                          if (isPending) ...[
                            TextButton.icon(
                              onPressed: () => _resolveRefund(refundId: refundId, status: 'rejected'),
                              icon: const Icon(Icons.close, size: 16, color: Colors.red),
                              label: Text('Reject', style: GoogleFonts.hankenGrotesk(color: Colors.red, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 6),
                            ElevatedButton.icon(
                              onPressed: () => _resolveRefund(refundId: refundId, status: 'processed'),
                              icon: const Icon(Icons.check, size: 16),
                              label: Text(isCustomer ? 'Process Refund' : 'Approve Payout'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  // View: Tab 8 Any Complaints
  Widget _buildAdminComplaintsTab(List<Map<String, dynamic>> complaints) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Any Complaints', style: GoogleFonts.hankenGrotesk(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.teal.shade900)),
                Text('${complaints.length} tickets recorded', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant)),
              ],
            ),
            ElevatedButton.icon(
              onPressed: () => _showCreateComplaintDialog(defaultType: 'general_complaint'),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Register Complaint'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Filter Sub-Chips
        Row(
          children: [
            ChoiceChip(
              label: const Text('All'),
              selected: _complaintFilterStatus == 'all',
              onSelected: (val) => setState(() => _complaintFilterStatus = 'all'),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Pending'),
              selected: _complaintFilterStatus == 'pending',
              onSelected: (val) => setState(() => _complaintFilterStatus = 'pending'),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Resolved'),
              selected: _complaintFilterStatus == 'resolved',
              onSelected: (val) => setState(() => _complaintFilterStatus = 'resolved'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (complaints.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            alignment: Alignment.center,
            child: Column(
              children: [
                Icon(Icons.support_agent_rounded, size: 48, color: Colors.teal.shade600),
                const SizedBox(height: 8),
                Text('No complaints in this category!', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: complaints.length,
            itemBuilder: (context, index) {
              final data = complaints[index];
              final complaintId = data['complaintId'] ?? '';
              final repName = data['reportedByName'] ?? 'User';
              final repPhone = data['reportedByPhone'] ?? '';
              final role = data['reportedByRole'] ?? 'customer';
              final subject = data['subject'] ?? 'Complaint';
              final desc = data['description'] ?? '';
              final status = data['status'] ?? 'pending';
              final isResolved = status == 'resolved';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(complaintId, style: GoogleFonts.robotoMono(fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.teal.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                                child: Text(role.toUpperCase(), style: GoogleFonts.robotoMono(fontSize: 10, color: Colors.teal.shade800, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isResolved ? Colors.green.withOpacity(0.12) : Colors.orange.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              status.toString().toUpperCase(),
                              style: GoogleFonts.robotoMono(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isResolved ? Colors.green : Colors.orange.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(subject, style: GoogleFonts.hankenGrotesk(fontSize: 15, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(desc, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      Text('Reported By: $repName (+91 $repPhone)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (repPhone.isNotEmpty)
                            TextButton.icon(
                              onPressed: () => _callUser(repPhone),
                              icon: const Icon(Icons.call, size: 16),
                              label: const Text('Call Complainant'),
                            ),
                          if (!isResolved) ...[
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () => _resolveComplaint(complaintId: complaintId),
                              icon: const Icon(Icons.check, size: 16),
                              label: const Text('Mark as Resolved'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  // View: Tab 9 All Customers
  Widget _buildAdminAllCustomersTab(List<Map<String, dynamic>> customers) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('All Customers', style: GoogleFonts.hankenGrotesk(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.onSurfaceColor)),
                Text('${customers.length} registered customers', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant)),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.people_alt_rounded, size: 16, color: Colors.blue),
                  const SizedBox(width: 4),
                  Text('${customers.length}', style: GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (customers.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            alignment: Alignment.center,
            child: Text('No customers found', style: GoogleFonts.inter(color: AppTheme.onSurfaceVariant)),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: customers.length,
            itemBuilder: (context, index) {
              final c = customers[index];
              final name = c['name'] ?? 'StayDriv Customer';
              final phone = (c['phone'] ?? '').toString();
              final email = c['email'] ?? 'Not provided';
              final isBlocked = c['isBlocked'] == true;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: isBlocked ? Colors.red.shade100 : AppTheme.primaryColor.withOpacity(0.12),
                        child: Icon(
                          isBlocked ? Icons.person_off_rounded : Icons.person_rounded,
                          color: isBlocked ? Colors.red : AppTheme.primaryColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    name,
                                    style: GoogleFonts.hankenGrotesk(fontSize: 15, fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isBlocked ? Colors.red.withOpacity(0.12) : Colors.green.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    isBlocked ? 'BLOCKED' : 'ACTIVE',
                                    style: GoogleFonts.robotoMono(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isBlocked ? Colors.red : Colors.green,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              phone.isNotEmpty ? '+91 $phone' : 'No Phone Number',
                              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.onSurfaceVariant),
                            ),
                            if (email != 'Not provided') ...[
                              const SizedBox(height: 2),
                              Text(email, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.onSurfaceVariant)),
                            ],
                            if (isBlocked && c['blockReason'] != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Reason: ${c['blockReason']}',
                                style: GoogleFonts.inter(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.red.shade700),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.call, color: AppTheme.primaryColor),
                          tooltip: 'Call Customer',
                          onPressed: () => _callUser(phone),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  // View: Tab 10 All Pilots
  Widget _buildAdminAllPilotsTab(List<Map<String, dynamic>> pilots) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('All Pilots', style: GoogleFonts.hankenGrotesk(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.onSurfaceColor)),
                Text('${pilots.length} registered pilots', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant)),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.amber.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.two_wheeler_rounded, size: 16, color: Colors.orange),
                  const SizedBox(width: 4),
                  Text('${pilots.length}', style: GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (pilots.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            alignment: Alignment.center,
            child: Text('No pilots found', style: GoogleFonts.inter(color: AppTheme.onSurfaceVariant)),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: pilots.length,
            itemBuilder: (context, index) {
              final d = pilots[index];
              final name = d['name'] ?? 'StayDriv Pilot';
              final phone = (d['phone'] ?? '').toString();
              final vehicle = d['vehicleType'] ?? 'Bike';
              final plate = d['vehiclePlate'] ?? 'Plate Pending';
              final isApproved = d['approved'] == true;
              final isBlocked = d['isBlocked'] == true;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: isBlocked
                                    ? Colors.red.shade100
                                    : (isApproved ? Colors.green.shade100 : Colors.amber.shade100),
                                child: Icon(
                                  Icons.badge_rounded,
                                  size: 20,
                                  color: isBlocked
                                      ? Colors.red
                                      : (isApproved ? Colors.green.shade800 : Colors.amber.shade800),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: GoogleFonts.hankenGrotesk(fontSize: 15, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    phone.isNotEmpty ? '+91 $phone' : 'No Phone Number',
                                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isApproved ? Colors.green.withOpacity(0.12) : Colors.orange.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  isApproved ? 'VERIFIED' : 'PENDING',
                                  style: GoogleFonts.robotoMono(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isApproved ? Colors.green.shade800 : Colors.orange.shade800,
                                  ),
                                ),
                              ),
                              if (isBlocked) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'BLOCKED',
                                    style: GoogleFonts.robotoMono(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Vehicle: $vehicle', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500)),
                            Text('Reg: $plate', style: GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (phone.isNotEmpty)
                            TextButton.icon(
                              onPressed: () => _callUser(phone),
                              icon: const Icon(Icons.call, size: 16),
                              label: const Text('Call Pilot'),
                            ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _selectedDriverForDocApproval = d;
                              });
                            },
                            icon: const Icon(Icons.description_outlined, size: 16),
                            label: const Text('View Documents'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
    );
  }

  // View: Tab 11 Payments & Invoices
  Widget _buildAdminPaymentsTab(List<Map<String, dynamic>> payments) {
    double totalCollection = 0.0;
    for (final p in payments) {
      if (p['status'] == 'captured' || p['status'] == 'success') {
        final amt = (p['amount'] is num) ? (p['amount'] as num).toDouble() : (double.tryParse('${p['amount']}') ?? 0.0);
        totalCollection += amt;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Payments & Transactions', style: GoogleFonts.hankenGrotesk(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.onSurfaceColor)),
                Text('${payments.length} transactions recorded', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant)),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.green.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Total Captured', style: GoogleFonts.inter(fontSize: 9, color: Colors.green.shade800)),
                  Text(
                    '₹${totalCollection.toStringAsFixed(2)}',
                    style: GoogleFonts.robotoMono(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (payments.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            alignment: Alignment.center,
            child: Text('No payments recorded yet', style: GoogleFonts.inter(color: AppTheme.onSurfaceVariant)),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: payments.length,
            itemBuilder: (context, index) {
              final p = payments[index];
              final amount = p['amount'] ?? 0;
              final status = (p['status'] ?? 'pending').toString().toLowerCase();
              final orderId = p['orderId'] ?? 'N/A';
              final paymentId = p['paymentId'] ?? 'N/A';
              final method = p['method'] ?? 'UPI / Gateway';
              final phone = p['phone'] ?? '';
              final bookingId = p['bookingId'] ?? '';
              final createdAt = p['createdAt'] ?? '';

              final isSuccess = status == 'captured' || status == 'success';
              final isFailed = status == 'failed';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: (isSuccess ? Colors.green : (isFailed ? Colors.red : Colors.orange)).withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isSuccess ? Icons.check_circle_outline : (isFailed ? Icons.error_outline : Icons.pending_outlined),
                                  color: isSuccess ? Colors.green : (isFailed ? Colors.red : Colors.orange),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '₹$amount',
                                    style: GoogleFonts.robotoMono(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    method.toString().toUpperCase(),
                                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: (isSuccess ? Colors.green : (isFailed ? Colors.red : Colors.orange)).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: GoogleFonts.robotoMono(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isSuccess ? Colors.green : (isFailed ? Colors.red : Colors.orange),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Divider(height: 1),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Payment ID:', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.onSurfaceVariant)),
                          Text(paymentId, style: GoogleFonts.robotoMono(fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Order ID:', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.onSurfaceVariant)),
                          Text(orderId, style: GoogleFonts.robotoMono(fontSize: 11, color: AppTheme.onSurfaceVariant)),
                        ],
                      ),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Customer Phone:', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.onSurfaceVariant)),
                            Text('+91 $phone', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ],
                      if (bookingId.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Booking Ref:', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.onSurfaceVariant)),
                            Text(bookingId, style: GoogleFonts.robotoMono(fontSize: 11, color: AppTheme.primaryColor)),
                          ],
                        ),
                      ],
                      if (createdAt.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Date/Time:', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.onSurfaceVariant)),
                            Text(createdAt, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.onSurfaceVariant)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
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
              zoom: 16.5,
            ),
            onMapCreated: (controller) {
              _driverMapController = controller;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_driverMapCenter != null) {
                  controller.animateCamera(
                    CameraUpdate.newCameraPosition(
                      CameraPosition(
                        target: _driverMapCenter!,
                        zoom: 16.5,
                        bearing: BookingManager().driverHeading,
                      ),
                    ),
                  );
                }
                if (_activeBooking != null) {
                  final pickup = _activeBooking!['pickupLatLng'] as LatLng?;
                  final drop = _activeBooking!['dropLatLng'] as LatLng?;
                  if (pickup != null) {
                    if (_driverStatus == 'heading_to_pickup' || _driverStatus == 'arrived_pickup') {
                      _zoomToRoute(_driverMapCenter!, pickup);
                    } else if (_driverStatus == 'on_trip' && drop != null) {
                      _zoomToRoute(pickup, drop);
                    }
                  }
                }
              });
            },
            markers: _getDriverMarkers(),
            polylines: _getDriverPolylines(),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.88),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isOnline ? Colors.green.withOpacity(0.6) : AppTheme.outlineVariant.withOpacity(0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _isOnline ? Colors.green.withOpacity(0.18) : Colors.black.withOpacity(0.3),
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
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    'Driver Console',
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.hankenGrotesk(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  icon: const Icon(Icons.hub_outlined, color: Colors.white70, size: 18),
                                  tooltip: 'Switch Console (Customer, Pilot, Restaurant, Admin)',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => ConsoleSwitcherSheet.show(
                                    context,
                                    currentRole: 'Driver',
                                    userPhone: widget.phoneNumber,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                IconButton(
                                  icon: const Icon(Icons.share_rounded, color: Colors.white70, size: 18),
                                  tooltip: 'Share StayDriv Pilot App',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => ShareStayDrivSheet.show(context, isPilot: true),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: (_isOnline && _bookingAccessEnabled && _dailyPlanStatus == 'paid') 
                                        ? const Color(0xFF10B981) 
                                        : const Color(0xFFEF4444),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    (_bookingAccessEnabled && _dailyPlanStatus == 'paid')
                                        ? (_isOnline ? 'ONLINE • RECEIVING JOBS' : 'OFFLINE • DUTY READY')
                                        : (!_bookingAccessEnabled ? 'ACCESS DISABLED BY ADMIN' : 'DAILY PLAN REQUIRED'),
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.robotoMono(
                                      fontSize: 10,
                                      color: (_isOnline && _bookingAccessEnabled && _dailyPlanStatus == 'paid') 
                                          ? const Color(0xFF34D399) 
                                          : const Color(0xFFF87171),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Admin-controlled booking permission indicator & interactive Pilot Duty toggle
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // 1. Authoritative Admin Booking Permission Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: _bookingAccessEnabled
                                  ? const Color(0xFF065F46)
                                  : const Color(0xFF7F1D1D),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _bookingAccessEnabled
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFEF4444),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _bookingAccessEnabled
                                      ? Icons.check_circle_rounded
                                      : Icons.lock_rounded,
                                  size: 11,
                                  color: _bookingAccessEnabled
                                      ? const Color(0xFF6EE7B7)
                                      : const Color(0xFFFCA5A5),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _bookingAccessEnabled
                                      ? 'Booking Enabled by Admin'
                                      : 'Booking Disabled by Admin',
                                  style: GoogleFonts.robotoMono(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: _bookingAccessEnabled
                                        ? const Color(0xFF6EE7B7)
                                        : const Color(0xFFFCA5A5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 5),
                          // 2. Clearly visible interactive DUTY ON / DUTY OFF Toggle Switch & Badge
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: _isOnline
                                      ? const Color(0xFF065F46)
                                      : const Color(0xFF450A0A),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: _isOnline
                                        ? const Color(0xFF10B981)
                                        : const Color(0xFFEF4444),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  _isOnline ? 'DUTY ON' : 'DUTY OFF',
                                  style: GoogleFonts.robotoMono(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: _isOnline
                                        ? const Color(0xFF6EE7B7)
                                        : const Color(0xFFFCA5A5),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Transform.scale(
                                scale: 0.80,
                                child: CupertinoSwitch(
                                  value: _isOnline,
                                  activeTrackColor: const Color(0xFF10B981),
                                  inactiveTrackColor: const Color(0xFF334155),
                                  onChanged: (val) {
                                    _toggleDuty(val);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Prominent non-dismissible duty & booking status banner
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () {
                      if (!_bookingAccessEnabled || _dailyPlanStatus != 'paid') {
                        _openPilotEarningsScreen();
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: !_bookingAccessEnabled
                            ? const Color(0xFFFEF2F2)
                            : (_isOnline
                                ? const Color(0xFFF0FDF4)
                                : const Color(0xFFFFFBEB)),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: !_bookingAccessEnabled
                              ? const Color(0xFFF87171)
                              : (_isOnline
                                  ? const Color(0xFF86EFAC)
                                  : const Color(0xFFFCD34D)),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            !_bookingAccessEnabled
                                ? Icons.lock_person_rounded
                                : (_isOnline
                                    ? Icons.verified_rounded
                                    : Icons.power_settings_new_rounded),
                            color: !_bookingAccessEnabled
                                ? const Color(0xFFDC2626)
                                : (_isOnline
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFFD97706)),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  !_bookingAccessEnabled
                                      ? 'Booking Disabled by Admin'
                                      : (_isOnline
                                          ? 'Duty ON — eligible to receive bookings if all other requirements are satisfied.'
                                          : 'Duty OFF — not eligible to receive new bookings.'),
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: !_bookingAccessEnabled
                                        ? const Color(0xFF991B1B)
                                        : (_isOnline
                                            ? const Color(0xFF166534)
                                            : const Color(0xFF92400E)),
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  !_bookingAccessEnabled
                                      ? ((_bookingAccessReason.isNotEmpty && !_bookingAccessReason.toLowerCase().contains('eligible for 100% earnings'))
                                          ? 'Reason: $_bookingAccessReason. Contact Admin to restore access.'
                                          : 'Please contact the StayDriv Admin to enable booking access.')
                                      : (_isOnline
                                          ? '100% booking earnings – no StayDriv commission deduction.'
                                          : 'Toggle Duty ON to start receiving ride and food delivery assignments.'),
                                  style: GoogleFonts.inter(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: !_bookingAccessEnabled
                                        ? const Color(0xFFB91C1C)
                                        : (_isOnline
                                            ? const Color(0xFF15803D)
                                            : const Color(0xFFB45309)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!_bookingAccessEnabled || _dailyPlanStatus != 'paid')
                            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 12),
                        ],
                      ),
                    ),
                  ),

                  // Quick ₹20 Daily Plan Status Pill
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _openPilotEarningsScreen,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _dailyPlanStatus == 'paid' 
                              ? const Color(0xFF10B981).withValues(alpha: 0.4) 
                              : const Color(0xFFF59E0B).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _dailyPlanStatus == 'paid' ? Icons.verified_rounded : Icons.pending_actions_rounded,
                            size: 15,
                            color: _dailyPlanStatus == 'paid' ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _dailyPlanStatus == 'paid' 
                                  ? 'Daily ₹20 Plan: ACTIVE (100% Earnings • 0% Commission)'
                                  : 'Daily ₹20 Plan: ${_dailyPlanStatus == "expired" ? "EXPIRED" : "NOT ACTIVE"} (Tap to activate)',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.robotoMono(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: _dailyPlanStatus == 'paid' ? const Color(0xFF6EE7B7) : const Color(0xFFFDE68A),
                              ),
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.white70),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Pilot Registration / Action Required Status Banner (Only visible when NOT yet approved)
                  if (!_isPilotApproved) ...[
                    GestureDetector(
                      onTap: _showPilotApplicationStatusModal,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: _pilotStatus == 'rejected' || _pilotStatus == 'action_required'
                              ? const Color(0xFFDC2626).withValues(alpha: 0.12)
                              : const Color(0xFFD97706).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _pilotStatus == 'rejected' || _pilotStatus == 'action_required'
                                ? const Color(0xFFDC2626).withValues(alpha: 0.4)
                                : const Color(0xFFD97706).withValues(alpha: 0.4),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _pilotStatus == 'rejected' || _pilotStatus == 'action_required'
                                  ? Icons.cancel_rounded
                                  : Icons.hourglass_top_rounded,
                              size: 18,
                              color: _pilotStatus == 'rejected' || _pilotStatus == 'action_required'
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFFD97706),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _pilotStatus == 'rejected' || _pilotStatus == 'action_required'
                                    ? 'Application ${_pilotStatus == 'rejected' ? 'Rejected' : 'Requires Action'}. Tap to view notes & re-submit.'
                                    : 'Pending Approval • Documents under review. Tap to check status.',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _pilotStatus == 'rejected' || _pilotStatus == 'action_required'
                                      ? const Color(0xFF991B1B)
                                      : const Color(0xFF92400E),
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: _pilotStatus == 'rejected' || _pilotStatus == 'action_required'
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFFD97706),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Compact Weekly Incentive Tracker
                  Builder(builder: (context) {
                    final now = DateTime.now();
                    final mon = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
                    final sun = DateTime(mon.year, mon.month, mon.day + 6, 23, 59, 59, 999);
                    int weekRides = 0;
                    for (var r in _completedRides) {
                      final st = (r['status'] as String? ?? 'completed').toLowerCase();
                      if (st != 'completed' && st != 'accepted') continue;
                      final ts = r['timestamp'] as int? ?? 0;
                      if (ts == 0) continue;
                      final dt = DateTime.fromMillisecondsSinceEpoch(ts);
                      if (dt.isAfter(mon.subtract(const Duration(milliseconds: 1))) &&
                          dt.isBefore(sun.add(const Duration(milliseconds: 1)))) {
                        weekRides++;
                      }
                    }

                    int t1 = 30;
                    int t2 = 50;
                    int t1B = 750;
                    int t2B = 1300;
                    final v = _selectedVehicle.toLowerCase();
                    if (v.contains('auto')) {
                      t1B = 950;
                      t2B = 1500;
                    } else if (v.contains('car')) {
                      t1B = 1200;
                      t2B = 1800;
                    }

                    final nextTarget = weekRides < t1 ? t1 : t2;
                    final nextBonus = weekRides < t1 ? t1B : t2B;
                    final progress = (weekRides / t2.toDouble()).clamp(0.0, 1.0);

                    return Column(
                      children: [
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _currentTabIndex = 1; // Open Earnings & Activity Dashboard for Pilot
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.emoji_events_rounded, color: Color(0xFFF59E0B), size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              'Weekly Incentive ($_selectedVehicle)',
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.hankenGrotesk(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '$weekRides/$nextTarget Rides (₹$nextBonus Goal)',
                                            style: GoogleFonts.robotoMono(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFFFBBF24),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 5),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(3),
                                        child: LinearProgressIndicator(
                                          value: progress,
                                          backgroundColor: const Color(0xFF0F172A),
                                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
                                          minHeight: 4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF94A3B8), size: 11),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
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
              if (_driverMapCenter != null) {
                if (_driverMapController != null) {
                  _driverMapController!.animateCamera(
                    CameraUpdate.newCameraPosition(
                      CameraPosition(
                        target: _driverMapCenter!,
                        zoom: 16.5,
                        bearing: BookingManager().driverHeading,
                      ),
                    ),
                  );
                }
                _startGpsTracking();
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
              maxHeight: MediaQuery.of(context).size.height * 0.74,
            ),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: _buildBottomPanel(),
            ),
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
    final String vLower = _selectedVehicle.toLowerCase();
    
    // STRICT FOOD DELIVERY VEHICLE RULE: Bike & Scooty only. Auto Rickshaw and Car are strictly excluded!
    final bool isEligibleForFood = (vLower.contains('bike') || 
                                    vLower.contains('scoot') || 
                                    vLower.contains('moto') || 
                                    vLower.contains('2-wheel')) &&
                                   !vLower.contains('auto') &&
                                   !vLower.contains('rickshaw') &&
                                   !vLower.contains('car') &&
                                   !vLower.contains('truck') &&
                                   !vLower.contains('van');

    String vDesc = '';
    if (isEligibleForFood) {
      vDesc = 'Bike Taxi / Food Delivery / small parcels';
    } else if (vLower.contains('auto') || vLower.contains('rickshaw')) {
      vDesc = 'Passenger rides / standard auto rickshaw';
    } else if (_selectedVehicle == 'Car' || _selectedVehicle == 'Mini' || _selectedVehicle == 'Sedan') {
      vDesc = 'Comfort rides / passenger cab';
    } else if (_selectedVehicle == 'Car XL') {
      vDesc = 'Spacious and comfortable XL ride';
    } else if (_selectedVehicle == 'Mini Truck') {
      vDesc = 'Large transport / cargo delivery';
    } else {
      vDesc = 'Passenger & transport rides';
    }

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
          // Service Preferences Toggles (Ride Booking & Food Delivery ON/OFF)
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.tune_rounded, size: 16, color: Color(0xFF475569)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Service Preferences',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'PILOT CONTROLS',
                        style: GoogleFonts.robotoMono(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 1. Ride Booking Switch
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _rideServiceEnabled ? const Color(0xFF3B82F6).withOpacity(0.3) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _rideServiceEnabled ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          vIcon,
                          size: 20,
                          color: _rideServiceEnabled ? const Color(0xFF2563EB) : const Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'Ride Booking',
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: _rideServiceEnabled ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _rideServiceEnabled ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _rideServiceEnabled ? 'ACTIVE' : 'PAUSED',
                                    style: GoogleFonts.robotoMono(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: _rideServiceEnabled ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              'Receive customer trip & parcel requests',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _rideServiceEnabled,
                        activeColor: const Color(0xFF2563EB),
                        activeTrackColor: const Color(0xFFBFDBFE),
                        onChanged: (val) {
                          _updateServicePreference(ride: val);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // 2. Food Delivery Switch
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isEligibleForFood
                          ? (_foodServiceEnabled ? const Color(0xFF10B981).withOpacity(0.3) : const Color(0xFFE2E8F0))
                          : const Color(0xFFF1F5F9),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isEligibleForFood
                              ? (_foodServiceEnabled ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9))
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.restaurant_rounded,
                          size: 20,
                          color: isEligibleForFood
                              ? (_foodServiceEnabled ? const Color(0xFF059669) : const Color(0xFF94A3B8))
                              : const Color(0xFFCBD5E1),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'Food Delivery',
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: isEligibleForFood
                                          ? (_foodServiceEnabled ? const Color(0xFF0F172A) : const Color(0xFF64748B))
                                          : const Color(0xFF94A3B8),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isEligibleForFood
                                        ? (_foodServiceEnabled ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9))
                                        : const Color(0xFFFEE2E2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isEligibleForFood
                                        ? (_foodServiceEnabled ? 'ACTIVE' : 'PAUSED')
                                        : 'BIKE ONLY',
                                    style: GoogleFonts.robotoMono(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: isEligibleForFood
                                          ? (_foodServiceEnabled ? const Color(0xFF16A34A) : const Color(0xFF64748B))
                                          : const Color(0xFFDC2626),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              isEligibleForFood
                                  ? 'Receive restaurant food pickup orders & loud buzzer alert'
                                  : 'Available for Bike & Scooty pilots only',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: isEligibleForFood && _foodServiceEnabled,
                        activeColor: const Color(0xFF059669),
                        activeTrackColor: const Color(0xFFA7F3D0),
                        onChanged: isEligibleForFood
                            ? (val) {
                                _updateServicePreference(food: val);
                              }
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Dedicated Food Delivery Task Integration ONLY for approved Bike & Scooty pilots
          if (isEligibleForFood)
            PilotFoodDeliveryCard(
              pilotId: widget.phoneNumber,
              pilotName: widget.userName,
              pilotPhone: widget.phoneNumber,
              vehicleType: _selectedVehicle,
              isOnline: _isOnline,
              foodServiceEnabled: _foodServiceEnabled,
            ),
        ],
      ),
    );
  }

  Widget _buildIncomingRequestPanel() {
    if (_activeBooking == null) return const SizedBox();
    
    final bool isParcel = _activeBooking!['serviceType'] == 'parcel';
    final bool isRoundTrip = _activeBooking!['tripType'] == 'ROUND_TRIP' || _activeBooking!['isRoundTrip'] == true;
    final bool isSharedRide = _activeBooking!['tripType'] == 'SHARE_AUTO' || _activeBooking!['tripType'] == 'SHARE_CAR' || _activeBooking!['vehicle'] == 'Share Auto' || _activeBooking!['vehicle'] == 'Share Car';
    final int sharedSeats = _activeBooking!['sharedSeats'] ?? 1;
    final String? returnDate = _activeBooking!['returnDate'] as String?;
    final String? returnTime = _activeBooking!['returnTime'] as String?;
    final int waitingDurationMinutes = _activeBooking!['waitingDurationMinutes'] ?? 0;
    final String pilotWaitOption = _activeBooking!['pilotWaitOption'] ?? 'wait';
    final num outwardFare = _activeBooking!['outwardFare'] ?? 0;
    final num returnFare = _activeBooking!['returnFare'] ?? 0;
    final num waitingCharge = _activeBooking!['waitingCharge'] ?? 0;
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
        border: Border.all(
          color: isRoundTrip ? const Color(0xFF7E22CE) : (isSharedRide ? const Color(0xFF0F766E) : AppTheme.primaryColor),
          width: 2,
        ),
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
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isRoundTrip ? const Color(0xFF7E22CE) : (isSharedRide ? const Color(0xFF0F766E) : AppTheme.primaryColor),
                      borderRadius: const BorderRadius.all(Radius.circular(12)),
                    ),
                    child: Text(
                      isParcel
                          ? 'NEW PARCEL REQUEST'
                          : (isRoundTrip
                              ? 'ROUND TRIP (2 LEGS)'
                              : (isSharedRide ? 'SHARED RIDE ($sharedSeats SEAT${sharedSeats > 1 ? 'S' : ''})' : 'NEW BOOKING REQUEST')),
                      style: GoogleFonts.robotoMono(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  if (isRoundTrip)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3E8FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFD8B4FE)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.sync_alt_rounded, size: 12, color: Color(0xFF6B21A8)),
                          const SizedBox(width: 4),
                          Text(
                            pilotWaitOption == 'return_later' ? 'Return: $returnDate $returnTime' : 'Wait: ~$waitingDurationMinutes mins',
                            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF6B21A8)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: _incomingRequestCountdown / 30.0,
                    backgroundColor: Colors.grey[200],
                    color: isRoundTrip ? const Color(0xFF7E22CE) : AppTheme.primaryColor,
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
          if (isRoundTrip) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFAF5FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE9D5FF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.sync_alt_rounded, size: 16, color: Color(0xFF7E22CE)),
                      const SizedBox(width: 6),
                      Text(
                        'Leg 2 (Return Journey)',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF7E22CE)),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7E22CE),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '10% OFF',
                          style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Return Drop: ${_activeBooking!['pickup'] ?? 'Original Pickup'}',
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF581C87), fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    pilotWaitOption == 'return_later'
                        ? 'Schedule: Return on $returnDate at $returnTime'
                        : 'Pilot waiting at destination: ~$waitingDurationMinutes mins',
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade700),
                  ),
                  if (outwardFare > 0 || returnFare > 0 || waitingCharge > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Outward: ₹${outwardFare.toStringAsFixed(0)}  •  Return: ₹${returnFare.toStringAsFixed(0)}  •  Wait: ₹${waitingCharge.toStringAsFixed(0)}',
                      style: GoogleFonts.robotoMono(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF6B21A8)),
                    ),
                  ],
                ],
              ),
            ),
          ],
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

  void _showParcelDeliveryOtpDialog() {
    final otpController = TextEditingController();
    String error = '';
    bool isVerifying = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final enteredDigits = otpController.text.trim();
          final isOtpComplete = enteredDigits.length == 4;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.inventory_2_rounded, color: Color(0xFF16A34A), size: 24),
                const SizedBox(width: 8),
                Text(
                  'Verify Delivery OTP',
                  style: GoogleFonts.hankenGrotesk(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ask the customer for the 4-digit delivery OTP shown on their screen to complete delivery.',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.robotoMono(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 12),
                  onChanged: (val) {
                    setDialogState(() {
                      if (error.isNotEmpty) error = '';
                    });
                  },
                  decoration: InputDecoration(
                    hintText: '• • • •',
                    hintStyle: const TextStyle(letterSpacing: 10),
                    errorText: error.isNotEmpty ? error : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    counterText: '',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isVerifying ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF16A34A).withOpacity(0.5),
                  disabledForegroundColor: Colors.white70,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
                onPressed: (isVerifying || !isOtpComplete)
                    ? null
                    : () async {
                        final entered = otpController.text.trim();
                        if (entered.length != 4) {
                          setDialogState(() {
                            error = 'Please enter all 4 digits of the OTP';
                          });
                          return;
                        }
                        setDialogState(() {
                          isVerifying = true;
                          error = '';
                        });

                        final bookingId = _activeBooking?['bookingId']?.toString() ??
                            _activeBooking?['id']?.toString() ??
                            _activeBooking?['_id']?.toString() ?? '';

                        final result = await BookingManager().verifyParcelDeliveryOtp(
                          bookingId: bookingId,
                          otp: entered,
                        );

                        if (result['success'] == true) {
                          Navigator.pop(ctx);
                          BookingManager().completeRide();
                          setState(() {
                            _driverStatus = 'payment_pending';
                          });
                        } else {
                          setDialogState(() {
                            isVerifying = false;
                            error = result['error'] ?? 'Invalid OTP. Please try again.';
                          });
                        }
                      },
                child: isVerifying
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Verify & Complete'),
              ),
            ],
          );
        },
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chat_bubble_outline_rounded, color: AppTheme.primaryColor),
                        tooltip: 'Chat with Customer',
                        onPressed: _showPilotChatBottomSheet,
                      ),
                      if (_pilotUnreadChatCount > 0)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                            child: Text(
                              '$_pilotUnreadChatCount',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.call, color: Colors.green),
                    tooltip: 'Call Customer',
                    onPressed: () {
                      final phone = isParcel ? pickupPhone : (_activeBooking!['passengerPhone'] as String?);
                      final name = isParcel ? (pickupName ?? 'Sender') : (_activeBooking!['passengerName'] as String? ?? 'Customer');
                      _callContact(phone, name);
                    },
                  ),
                ],
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
                'Sender: $pickupName (${CallMaskingService.maskPhone(pickupPhone)})',
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
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _openPilotNavigationScreen,
              icon: const Icon(Icons.navigation_rounded, color: Colors.white, size: 20),
              label: Text(
                'Open Turn-by-Turn Navigation to Pickup',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F5132),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 2,
              ),
            ),
          ),
          const SizedBox(height: 12),
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chat_bubble_outline_rounded, color: AppTheme.primaryColor),
                        tooltip: 'Chat with Customer',
                        onPressed: _showPilotChatBottomSheet,
                      ),
                      if (_pilotUnreadChatCount > 0)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                            child: Text(
                              '$_pilotUnreadChatCount',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.call, color: Colors.green),
                    tooltip: 'Call Customer',
                    onPressed: () {
                      final phone = isParcel ? pickupPhone : (_activeBooking!['passengerPhone'] as String?);
                      final name = isParcel ? (pickupName ?? 'Sender') : (_activeBooking!['passengerName'] as String? ?? 'Customer');
                      _callContact(phone, name);
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isParcel
                ? 'Ask the sender ($pickupName) for the 4-digit pickup OTP'
                : 'Ask the customer (${_activeBooking?['passengerName'] ?? 'Customer'}) for the 4-digit ride start OTP',
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
                isParcel ? 'Verify & Start Delivery' : 'Verify & Start Ride',
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chat_bubble_outline_rounded, color: AppTheme.primaryColor),
                        tooltip: 'Chat with Customer',
                        onPressed: _showPilotChatBottomSheet,
                      ),
                      if (_pilotUnreadChatCount > 0)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                            child: Text(
                              '$_pilotUnreadChatCount',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.call, color: Colors.green),
                    tooltip: 'Call Customer',
                    onPressed: () {
                      final phone = isParcel ? dropPhone : (_activeBooking!['passengerPhone'] as String?);
                      final name = isParcel ? (dropName ?? 'Recipient') : (_activeBooking!['passengerName'] as String? ?? 'Customer');
                      _callContact(phone, name);
                    },
                  ),
                ],
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
                'Recipient: $dropName (${CallMaskingService.maskPhone(dropPhone)})',
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.onSurfaceColor, fontWeight: FontWeight.w600),
              ),
            ],
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _openPilotNavigationScreen,
              icon: const Icon(Icons.navigation_rounded, color: Colors.white, size: 20),
              label: Text(
                'Open Turn-by-Turn Navigation',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F5132),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 2,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (isParcel) ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _showParcelDeliveryOtpDialog,
                icon: const Icon(Icons.verified_user_rounded, color: Colors.white, size: 20),
                label: Text(
                  'Verify Delivery OTP',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          SlidingButton(
            text: isParcel ? 'Slide to Verify & Complete Delivery' : 'Slide to Complete Ride',
            onSlideComplete: () {
              if (isParcel) {
                _showParcelDeliveryOtpDialog();
              } else {
                BookingManager().completeRide();
                setState(() {
                  _driverStatus = 'payment_pending';
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentPendingPanel() {
    if (_activeBooking == null) return const SizedBox();

    final panelBookingId = _activeBooking!['bookingId'] ?? _activeBooking!['id'] ?? _activeBooking!['_id'] ?? 'active_trip';
    return PilotPaymentPendingPanel(
      key: ValueKey('pilot_payment_panel_$panelBookingId'),
      booking: _activeBooking!,
      onPaymentCompleted: (method) {
        _confirmPayment(method);
      },
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
                  : CallMaskingService.maskPhone(widget.phoneNumber),
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
