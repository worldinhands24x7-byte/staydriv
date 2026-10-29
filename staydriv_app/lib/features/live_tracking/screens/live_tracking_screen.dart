import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

import '../../../core/theme.dart';
import '../../../core/booking_manager.dart';
import '../../../core/network_config.dart';
import '../../../core/api_client.dart';
import '../../../core/wake_lock_service.dart';
import '../../../core/socket_service.dart';
import '../../../core/floating_widget_service.dart';
import '../../../core/vehicle_marker_helper.dart';
import '../../../core/smooth_marker_animator.dart';
import '../../../core/call_masking_service.dart';
import '../../navigation/services/navigation_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/ride_completed_payment_panel.dart';

class LiveTrackingScreen extends StatefulWidget {
  final String vehicleType;
  final String price;
  final List<LatLng>? routePoints;

  const LiveTrackingScreen({
    super.key,
    required this.vehicleType,
    required this.price,
    this.routePoints,
  });

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen> with WidgetsBindingObserver {
  bool _rideCompleted = false;
  bool _isRidePaid = false;
  bool _isSharingLiveTrip = false;
  double _userRating = 5.0;
  final TextEditingController _feedbackController = TextEditingController();

  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  List<LatLng> _points = [];
  List<LatLng> _passedRoutePoints = [];
  List<LatLng> _remainingRoutePoints = [];
  int _routeProgressIndex = 0;
  String? _etaText;
  String? _liveRemainingDistance;
  String _rideStatus = 'searching'; // 'searching', 'accepted', 'arrived', 'started', 'completed'

  Timer? _waitingTimer;
  int _waitingSeconds = 0;

  // Round Trip live leg state
  String _roundTripLeg = 'outward'; // 'outward', 'waiting', 'return', 'completed'
  String _outwardTripStatus = 'pending';
  String _returnTripStatus = 'pending';
  String? _roundTripPrice;

  final List<Map<String, String>> _chatMessages = [];
  final TextEditingController _chatController = TextEditingController();
  bool _isChatSheetOpen = false;
  int _unreadChatCount = 0;
  void Function(void Function())? _modalSetState;

  String _formatTimestamp(String? ts) {
    if (ts == null || ts.isEmpty) return '';
    try {
      final ms = int.tryParse(ts);
      if (ms != null) {
        final dt = DateTime.fromMillisecondsSinceEpoch(ms);
        final hour = dt.hour.toString().padLeft(2, '0');
        final min = dt.minute.toString().padLeft(2, '0');
        return '$hour:$min';
      }
    } catch (_) {}
    return '';
  }

  Widget _buildDeliveryStatusIcon(String? status) {
    switch (status) {
      case 'READ':
        return const Icon(Icons.done_all_rounded, size: 14, color: Colors.cyanAccent);
      case 'DELIVERED':
        return const Icon(Icons.done_all_rounded, size: 14, color: Colors.white70);
      case 'SENT':
      default:
        return const Icon(Icons.check_rounded, size: 14, color: Colors.white70);
    }
  }

  void _sendMessage(String text) {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;

    final active = BookingManager().activeBooking;
    final bId = active?['bookingId']?.toString() ?? active?['id']?.toString() ?? active?['_id']?.toString() ?? '';
    final messageId = 'msg_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(9999)}';
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();

    setState(() {
      _chatMessages.add({
        'messageId': messageId,
        'sender': 'customer',
        'text': cleanText,
        'timestamp': timestamp,
        'status': 'SENT',
      });
    });
    _chatController.clear();

    if (bId.isNotEmpty) {
      SocketService().sendCustomerMessage(
        bookingId: bId,
        text: cleanText,
        messageId: messageId,
        senderName: 'Customer',
      );
    }
  }

  void _handleIncomingRideMessage(Map<String, dynamic> data) {
    if (!mounted) return;
    final active = BookingManager().activeBooking;
    final bId = active?['bookingId']?.toString() ?? active?['id']?.toString() ?? active?['_id']?.toString() ?? '';
    final msgRideId = (data['bookingId'] ?? data['rideId'])?.toString();

    // Verify message belongs to this active ride
    if (bId.isNotEmpty && msgRideId != null && msgRideId != bId) return;

    final rawRole = data['senderRole']?.toString() ?? 'pilot';
    final senderRole = rawRole.toLowerCase() == 'pilot' ? 'pilot' : 'customer';
    final text = (data['message'] ?? data['text'])?.toString() ?? '';
    final messageId = data['messageId']?.toString() ?? '';
    if (text.trim().isEmpty) return;

    // Check if message was already added (idempotency by messageId or timestamp)
    final timestamp = data['timestamp']?.toString();
    final alreadyExists = _chatMessages.any((m) =>
        (messageId.isNotEmpty && m['messageId'] == messageId) ||
        (m['text'] == text && m['sender'] == senderRole && (timestamp == null || m['timestamp'] == timestamp)));
    if (alreadyExists) return;

    setState(() {
      _chatMessages.add({
        'messageId': messageId,
        'sender': senderRole,
        'text': text,
        'timestamp': timestamp ?? '',
        'status': data['deliveryStatus']?.toString() ?? 'SENT',
      });
      if (senderRole == 'pilot' && !_isChatSheetOpen) {
        _unreadChatCount++;
      }
    });

    if (_modalSetState != null) {
      _modalSetState!(() {});
    }

    if (senderRole == 'pilot' && !_isChatSheetOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pilot Partner: $text',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.primaryColor,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          action: SnackBarAction(
            label: 'REPLY',
            textColor: Colors.yellowAccent,
            onPressed: () {
              final active = BookingManager().activeBooking;
              final driverName = active?['driverName'] as String? ?? 'Pilot Partner';
              _showChatBottomSheet(driverName);
            },
          ),
        ),
      );
    }
  }

  void _handleMessageDelivered(Map<String, dynamic> data) {
    if (!mounted) return;
    final messageId = data['messageId']?.toString();
    if (messageId == null || messageId.isEmpty) return;

    setState(() {
      for (var msg in _chatMessages) {
        if (msg['messageId'] == messageId && msg['status'] == 'SENT') {
          msg['status'] = 'DELIVERED';
        }
      }
    });
    if (_modalSetState != null) {
      _modalSetState!(() {});
    }
  }

  void _handleMessageRead(Map<String, dynamic> data) {
    if (!mounted) return;
    final messageId = data['messageId']?.toString();

    setState(() {
      for (var msg in _chatMessages) {
        if (msg['sender'] == 'customer') {
          if (messageId == null || messageId == 'all' || msg['messageId'] == messageId) {
            msg['status'] = 'READ';
          }
        }
      }
    });
    if (_modalSetState != null) {
      _modalSetState!(() {});
    }
  }

  void _handleRideChatHistory(Map<String, dynamic> data) {
    if (!mounted) return;
    final messages = data['messages'];
    if (messages is List && messages.isNotEmpty) {
      setState(() {
        _chatMessages.clear();
        for (var item in messages) {
          final rawRole = item['senderRole']?.toString() ?? 'pilot';
          final sender = rawRole.toLowerCase() == 'pilot' ? 'pilot' : 'customer';
          final status = item['deliveryStatus']?.toString() ?? (item['readStatus'] == true ? 'READ' : 'SENT');
          _chatMessages.add({
            'messageId': item['messageId']?.toString() ?? '',
            'sender': sender,
            'text': (item['message'] ?? item['text'])?.toString() ?? '',
            'timestamp': item['timestamp']?.toString() ?? '',
            'status': status,
          });
        }
      });
      if (_modalSetState != null) {
        _modalSetState!(() {});
      }
    }
  }

  Future<void> _fetchRideChatHistory(String? rideId) async {
    if (rideId == null || rideId.isEmpty) return;
    try {
      final response = await ApiClient().get(Uri.parse('/api/rides/$rideId/messages'));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true && decoded['messages'] is List) {
          final List list = decoded['messages'];
          if (mounted && list.isNotEmpty) {
            setState(() {
              _chatMessages.clear();
              for (var item in list) {
                final rawRole = item['senderRole']?.toString() ?? 'pilot';
                final sender = rawRole.toLowerCase() == 'pilot' ? 'pilot' : 'customer';
                final status = item['deliveryStatus']?.toString() ?? (item['readStatus'] == true ? 'READ' : 'SENT');
                _chatMessages.add({
                  'messageId': item['messageId']?.toString() ?? '',
                  'sender': sender,
                  'text': (item['message'] ?? item['text'])?.toString() ?? '',
                  'timestamp': item['timestamp']?.toString() ?? '',
                  'status': status,
                });
              }
            });
            if (_modalSetState != null) {
              _modalSetState!(() {});
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[LiveTrackingScreen] Error fetching chat history: $e');
    }
  }

  void _showChatBottomSheet(String driverName) {
    setState(() {
      _isChatSheetOpen = true;
      _unreadChatCount = 0;
    });

    final active = BookingManager().activeBooking;
    final bId = active?['bookingId']?.toString() ?? active?['id']?.toString() ?? active?['_id']?.toString();
    if (bId != null && bId.isNotEmpty) {
      _fetchRideChatHistory(bId);
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
            _modalSetState = setModalState;
            void sendMsg(String text) {
              if (text.trim().isEmpty) return;
              _sendMessage(text);
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
                height: 450,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              backgroundColor: AppTheme.primaryColor,
                              radius: 18,
                              child: Icon(Icons.person, color: Colors.white, size: 20),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Chat with $driverName',
                                  style: GoogleFonts.hankenGrotesk(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  'Pilot Partner • Live Chat',
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
                      child: ListView.builder(
                        itemCount: _chatMessages.length,
                        itemBuilder: (context, index) {
                          final msg = _chatMessages[index];
                          final isMe = msg['sender'] == 'customer';
                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isMe ? AppTheme.primaryColor : const Color(0xFFF0F2FF),
                                borderRadius: BorderRadius.circular(16).copyWith(
                                  bottomRight: isMe ? const Radius.circular(0) : null,
                                  bottomLeft: !isMe ? const Radius.circular(0) : null,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    msg['text'] ?? '',
                                    style: GoogleFonts.inter(
                                      color: isMe ? Colors.white : Colors.black87,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (msg['timestamp'] != null && msg['timestamp']!.isNotEmpty)
                                        Text(
                                          _formatTimestamp(msg['timestamp']),
                                          style: GoogleFonts.inter(
                                            color: isMe ? Colors.white70 : Colors.black45,
                                            fontSize: 10,
                                          ),
                                        ),
                                      if (isMe) ...[
                                        const SizedBox(width: 4),
                                        _buildDeliveryStatusIcon(msg['status']),
                                      ],
                                    ],
                                  ),
                                ],
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
                          _buildPresetChip("📍 I'm at the pickup point", sendMsg),
                          _buildPresetChip("⏳ How long will it take?", sendMsg),
                          _buildPresetChip("👍 Okay, thanks!", sendMsg),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _chatController,
                            decoration: InputDecoration(
                              hintText: 'Type any message...',
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
                            onPressed: () => sendMsg(_chatController.text),
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
          _isChatSheetOpen = false;
          _modalSetState = null;
        });
      }
    });
  }

  Widget _buildPresetChip(String text, Function(String) onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        label: Text(text, style: GoogleFonts.inter(fontSize: 12)),
        backgroundColor: const Color(0xFFF3F5FF),
        onPressed: () => onTap(text),
      ),
    );
  }

  Future<void> _makeCustomerPilotCall(String driverName, String? driverPhone) async {
    final active = BookingManager().activeBooking;
    final bId = active?['bookingId']?.toString() ?? active?['id']?.toString() ?? active?['_id']?.toString() ?? '';

    if (bId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot initiate call: active booking not found.'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    await CallMaskingService().callPilot(
      bookingId: bId,
      pilotName: driverName,
      context: context,
    );
  }

  void _startWaitingTimer() {

    if (_waitingTimer != null) return; // Already running!
    
    final active = BookingManager().activeBooking;
    final int arrivedAtMs = active?['arrivedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    
    final initialNow = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _waitingSeconds = (initialNow - arrivedAtMs) ~/ 1000;
    });

    _waitingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      if (_rideStatus != 'arrived') {
        timer.cancel();
        return;
      }
      
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final elapsedMs = nowMs - arrivedAtMs;
      setState(() {
        _waitingSeconds = elapsedMs ~/ 1000;
      });
    });
  }

  void _stopWaitingTimer() {
    _waitingTimer?.cancel();
    _waitingTimer = null;
  }

  BitmapDescriptor? _vehicleMarkerIcon;
  DateTime? _lastGpsUpdateTime;
  Timer? _staleGpsTimer;
  bool _isFollowingDriver = true;
  bool _isUserDraggingMap = false;
  DateTime? _lastCameraUpdateTime;
  LatLng? _lastCameraUpdatePos;
  double _lastValidHeading = 0.0;
  DateTime? _lastRouteUpdateTime;
  LatLng? _lastRouteUpdateDriverPos;

  StreamSubscription<LatLng>? _driverLocationSub;
  StreamSubscription<String>? _statusSub;
  StreamSubscription<Map<String, dynamic>?>? _bookingSub;
  bool _isPilotCancelledHandled = false;

  static LatLng _computeLookahead(LatLng origin, double bearingDeg, double distanceMeters) {
    if (distanceMeters <= 0.0) return origin;
    const double earthRadius = 6371000.0;
    final double radBearing = bearingDeg * (math.pi / 180.0);
    final double radLat = origin.latitude * (math.pi / 180.0);
    final double radLng = origin.longitude * (math.pi / 180.0);
    final double distRatio = distanceMeters / earthRadius;

    final double newLat = math.asin(
      math.sin(radLat) * math.cos(distRatio) +
      math.cos(radLat) * math.sin(distRatio) * math.cos(radBearing),
    );
    final double newLng = radLng + math.atan2(
      math.sin(radBearing) * math.sin(distRatio) * math.cos(radLat),
      math.cos(distRatio) - math.sin(radLat) * math.sin(newLat),
    );
    return LatLng(newLat * (180.0 / math.pi), newLng * (180.0 / math.pi));
  }

  void _maybeUpdateCustomerCameraFollow(LatLng pos, double heading) {
    if (!_isFollowingDriver || _mapController == null) return;
    if (_isUserDraggingMap) return;

    final now = DateTime.now();
    final speed = BookingManager().driverSpeed;
    if (speed > 2.0 || _lastValidHeading == 0.0) {
      if (heading != 0.0) {
        _lastValidHeading = heading;
      }
    }

    final double effectiveHeading = _lastValidHeading != 0.0 ? _lastValidHeading : heading;

    final elapsedMs = _lastCameraUpdateTime == null
        ? 999999
        : now.difference(_lastCameraUpdateTime!).inMilliseconds;
    final distMeters = _lastCameraUpdatePos == null
        ? 999999.0
        : NavigationEngine.distanceBetweenMeters(_lastCameraUpdatePos!, pos);

    // Throttle customer camera animation updates to ~650ms or displacement >= 2.5m for smooth native motion
    if (elapsedMs >= 650 || distMeters >= 2.5) {
      _lastCameraUpdateTime = now;
      _lastCameraUpdatePos = pos;
      _updateCameraCustomerFollow(pos, effectiveHeading);
    }
  }

  void _updateCameraCustomerFollow(LatLng pos, double heading, {bool force = false}) {
    if (_mapController == null) return;
    final targetPos = _computeLookahead(pos, heading, 20.0);
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: targetPos,
          zoom: 17.0,
          tilt: 40.0,
          bearing: heading,
        ),
      ),
    );
  }

  void _updateLiveRouteProgress(LatLng driverPos) {
    if (_points.length < 2) return;
    final split = NavigationEngine.splitRouteAtPoint(
      driverPos,
      _points,
      previousProgressIndex: _routeProgressIndex,
    );
    _routeProgressIndex = split.closestSegmentIndex;
    _passedRoutePoints = split.passedPoints;
    _remainingRoutePoints = split.remainingPoints;
    _polylines = _buildGoogleNavigationPolylines(idPrefix: 'tracking_line');
  }

  // 60 FPS smooth marker animator for customer view (accuracy & drift filtering, shortest-arc rotation)
  late final SmoothMarkerAnimator _driverMarkerAnimator = SmoothMarkerAnimator(
    onUpdate: (LatLng interpolatedPos, double interpolatedHeading) {
      if (!mounted) return;
      setState(() {
        _markers = {
          ..._markers.where((m) => m.markerId.value != 'driver'),
          Marker(
            markerId: const MarkerId('driver'),
            position: interpolatedPos,
            rotation: interpolatedHeading,
            flat: true,
            anchor: const Offset(0.5, 0.5),
            zIndex: 100.0,
            icon: _vehicleMarkerIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
            infoWindow: InfoWindow(
              title: '${widget.vehicleType} Pilot',
              snippet: _etaText != null ? 'ETA: $_etaText' : null,
            ),
          ),
        };
        _updateLiveRouteProgress(interpolatedPos);
      });

      // Smoothly update camera to follow moving driver without thrashing
      _maybeUpdateCustomerCameraFollow(interpolatedPos, interpolatedHeading);
    },
  );

  void _maybeThrottleRouteUpdate(LatLng driverPos) {
    final now = DateTime.now();
    final shouldUpdateByTime = _lastRouteUpdateTime == null ||
        now.difference(_lastRouteUpdateTime!).inSeconds >= 15;
    final shouldUpdateByDist = _lastRouteUpdateDriverPos == null ||
        NavigationEngine.distanceBetweenMeters(_lastRouteUpdateDriverPos!, driverPos) >= 50.0;

    if (shouldUpdateByTime || shouldUpdateByDist) {
      _lastRouteUpdateTime = now;
      _lastRouteUpdateDriverPos = driverPos;
      _updateCustomerRoutes();
    }
  }

  void _loadVehicleMarker([String? vType]) async {
    try {
      final active = BookingManager().activeBooking;
      final type = vType ?? active?['vehicleType']?.toString() ?? widget.vehicleType;
      // Load standard Google Maps-style driving navigation avatar (size 256 for large, crisp visibility)
      final icon = await VehicleMarkerHelper.getNavigationAvatarMarker(
        vehicleType: type,
        size: 256,
      );
      if (mounted) {
        setState(() {
          _vehicleMarkerIcon = icon;
        });
      }
    } catch (e) {
      debugPrint('[LiveTracking] Error loading Google navigation avatar marker: $e');
    }
  }

  /// Builds a prominent, dual-layer Google Maps navigation route polyline
  /// with passed route in BLACK and remaining route in vibrant navigation BLUE.
  Set<Polyline> _buildGoogleNavigationPolylines({
    required String idPrefix,
    List<LatLng>? points,
    List<LatLng>? passedPoints,
    List<LatLng>? remainingPoints,
    Color coreColor = const Color(0xFF1A73E8),
  }) {
    final polylines = <Polyline>{};
    final effectivePassed = passedPoints ?? _passedRoutePoints;
    final effectiveRemaining = remainingPoints ?? _remainingRoutePoints;

    // 1. PASSED / TRAVELLED ROUTE (BLACK) - behind the pilot vehicle
    if (effectivePassed.length >= 2) {
      polylines.add(
        Polyline(
          polylineId: PolylineId('${idPrefix}_passed_casing'),
          points: effectivePassed,
          color: const Color(0xFF1E1E1E),
          width: 14,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          zIndex: 1,
        ),
      );
      polylines.add(
        Polyline(
          polylineId: PolylineId('${idPrefix}_passed_core'),
          points: effectivePassed,
          color: Colors.black,
          width: 9,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          zIndex: 2,
        ),
      );
    }

    // 2. REMAINING / UPCOMING ROUTE (BLUE) - in front of the pilot vehicle
    if (effectiveRemaining.length >= 2) {
      polylines.add(
        Polyline(
          polylineId: PolylineId('${idPrefix}_remaining_casing'),
          points: effectiveRemaining,
          color: const Color(0xFF1557B0),
          width: 14,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          zIndex: 3,
        ),
      );
      polylines.add(
        Polyline(
          polylineId: PolylineId('${idPrefix}_remaining_core'),
          points: effectiveRemaining,
          color: coreColor,
          width: 9,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          zIndex: 4,
        ),
      );
    } else {
      // Fallback: If not yet split, draw base route points in vibrant blue
      final basePoints = points ?? _points;
      if (basePoints.isNotEmpty) {
        polylines.add(
          Polyline(
            polylineId: PolylineId('${idPrefix}_casing'),
            points: basePoints,
            color: const Color(0xFF1557B0),
            width: 14,
            jointType: JointType.round,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            zIndex: 1,
          ),
        );
        polylines.add(
          Polyline(
            polylineId: PolylineId('${idPrefix}_core'),
            points: basePoints,
            color: coreColor,
            width: 9,
            jointType: JointType.round,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            zIndex: 2,
          ),
        );
      }
    }

    return polylines;
  }

  void _startStaleGpsTimer() {
    _staleGpsTimer?.cancel();
    _staleGpsTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_lastGpsUpdateTime != null) {
        final elapsed = DateTime.now().difference(_lastGpsUpdateTime!).inSeconds;
        if (elapsed > 20 && _rideStatus == 'started') {
          setState(() {
            _etaText = 'Location updating...';
          });
        }
      }
    });
  }


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakeLockService.acquireWakeLock(); // Keep device active during ride session
    _loadVehicleMarker();
    _startStaleGpsTimer();
    
    final active = BookingManager().activeBooking;
    final bId = active?['bookingId']?.toString() ?? active?['id']?.toString() ?? active?['_id']?.toString();
    LatLng? pickupPos;
    LatLng? dropPos;
    if (active != null) {
      _rideStatus = active['status'] as String? ?? 'searching';
      if (_rideStatus == 'completed') {
        _rideCompleted = true;
      }
      if (active['paymentStatus'] == 'paid' || BookingManager().isBookingPaid(bId)) {
        _isRidePaid = true;
      }
      if (_rideStatus == 'arrived') {
        _startWaitingTimer();
      }
      if (active['pickupLatLng'] != null) {
        if (active['pickupLatLng'] is LatLng) {
          pickupPos = active['pickupLatLng'] as LatLng;
        } else if (active['pickupLatLng'] is Map) {
          final map = active['pickupLatLng'] as Map;
          pickupPos = LatLng((map['lat'] as num).toDouble(), (map['lng'] as num).toDouble());
        }
      }
      if (active['dropLatLng'] != null) {
        if (active['dropLatLng'] is LatLng) {
          dropPos = active['dropLatLng'] as LatLng;
        } else if (active['dropLatLng'] is Map) {
          final map = active['dropLatLng'] as Map;
          dropPos = LatLng((map['lat'] as num).toDouble(), (map['lng'] as num).toDouble());
        }
      }
    }

    if (bId != null && bId.isNotEmpty) {
      SharedPreferences.getInstance().then((prefs) {
        if (prefs.getBool('paid_booking_$bId') == true && mounted) {
          setState(() {
            _isRidePaid = true;
          });
        }
      });
    }
    
    if (widget.routePoints != null && widget.routePoints!.isNotEmpty) {
      _points = widget.routePoints!;
      _setupRoute();
    } else if (pickupPos != null && dropPos != null) {
      _points = [pickupPos, dropPos];
      _setupRoute();
    } else {
      _points = [];
      _setupRoute();
    }

    if (active != null && _rideStatus == 'cancelled') {
      final cancelledBy = active['cancelledBy'] as String?;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleCancellationNotification(active['cancelReason'] as String?, cancelledBy);
      });
    }

    // Subscribe to real-time payment, navigation location, and chat message stream
    SocketService().initSocket();
    SocketService().addPaymentSuccessListener(_handleLivePaymentSuccess);
    SocketService().addRideLocationListener(_handleRideLocationUpdate);
    SocketService().addRideMessageListener(_handleIncomingRideMessage);
    SocketService().addMessageDeliveredListener(_handleMessageDelivered);
    SocketService().addMessageReadListener(_handleMessageRead);
    SocketService().addRideChatHistoryListener(_handleRideChatHistory);
    SocketService().addRoundTripLegListener(_handleRoundTripLegUpdate);
    if (bId != null && bId.isNotEmpty) {
      SocketService().joinRide(bId);
      _fetchLatestPilotLocation(bId);
      _fetchRideChatHistory(bId);
    }
    _verifyServerPaymentStatus();

    _bookingSub = BookingManager().bookingStream.listen((booking) {
      if (mounted && booking != null) {
        final status = booking['status'] as String?;
        final eventBId = booking['bookingId']?.toString() ?? booking['id']?.toString() ?? booking['_id']?.toString();
        if ((booking['paymentStatus'] == 'paid' || BookingManager().isBookingPaid(eventBId)) && !_isRidePaid) {
          setState(() {
            _isRidePaid = true;
          });
        }
        final cancelledBy = booking['cancelledBy'] as String?;
        if (status == 'cancelled') {
          _handleCancellationNotification(booking['cancelReason'] as String? ?? booking['reason'] as String?, cancelledBy);
        }
      }
    });

    _driverLocationSub = BookingManager().driverLocationStream.listen((LatLng newPos) {
      if (mounted) {
        // Interpolate driver marker smoothly at 60 FPS instead of instant jumps
        _driverMarkerAnimator.updateTarget(
          position: newPos,
          heading: BookingManager().driverHeading,
          speedMps: BookingManager().driverSpeed / 3.6,
          accuracyMeters: BookingManager().driverAccuracy,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          routeForSnapping: _points,
        );

        // Smoothly update camera to follow vehicle on new GPS location fix
        _maybeUpdateCustomerCameraFollow(newPos, BookingManager().driverHeading);

        // Intelligently throttle route recalculation to avoid camera jumping & API quota thrashing
        _maybeThrottleRouteUpdate(newPos);
      }
    });

    // Subscribe to ride status stream
    _statusSub = BookingManager().rideStatusStream.listen((String newStatus) {
      if (mounted) {
        final prevStatus = _rideStatus;
        setState(() {
          _rideStatus = newStatus;
          if (_rideStatus == 'completed') {
            _rideCompleted = true;
          }
        });
        
        if ((newStatus == 'searching' || newStatus == 'declined') && 
            (prevStatus == 'accepted' || prevStatus == 'arrived')) {
          _showActionSnackbar('Searching for another pilot nearby...');
        }

        if (newStatus == 'cancelled') {
          final currentBooking = BookingManager().activeBooking;
          final cancelledBy = currentBooking?['cancelledBy'] as String?;
          _handleCancellationNotification(currentBooking?['cancelReason'] as String? ?? currentBooking?['reason'] as String?, cancelledBy);
        }

        if (newStatus == 'arrived') {
          WakeLockService.wakeUpScreen(); // Turn on screen to notify customer pilot has arrived
          if (prevStatus != 'arrived') {
            _startWaitingTimer();
          }
        } else if (newStatus != 'arrived') {
          _stopWaitingTimer();
        }

        _updateCustomerRoutes();
        Future.delayed(const Duration(milliseconds: 300), () {
          _recenterMap();
        });
      }
    });

    // Run initial route setup
    _updateCustomerRoutes();
  }

  void _setupRoute() {
    _polylines = _buildGoogleNavigationPolylines(
      idPrefix: 'tracking_line',
      points: _points,
      coreColor: AppTheme.primaryColor,
    );

    final LatLng driverPos = BookingManager().driverLatLng;
    final showDriverMarker = (_rideStatus != 'searching' && _rideStatus != 'declined') && BookingManager().hasRealDriverLocation;

    _markers = {
      if (_points.isNotEmpty)
        Marker(
          markerId: const MarkerId('start'),
          position: _points.first,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: 'Pickup Location'),
        ),
      if (_points.length > 1)
        Marker(
          markerId: const MarkerId('end'),
          position: _points.last,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Destination Location'),
        ),
      if (showDriverMarker)
        Marker(
          markerId: const MarkerId('driver'),
          position: driverPos,
          icon: _vehicleMarkerIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
          rotation: BookingManager().driverHeading,
          flat: true,
          anchor: const Offset(0.5, 0.5),
          zIndex: 100.0,
          infoWindow: InfoWindow(title: '${widget.vehicleType} Pilot'),
        ),
    };
  }

  void _updateCustomerRoutes() {
    final active = BookingManager().activeBooking;
    if (active == null) return;

    final LatLng driverPos = BookingManager().driverLatLng;
    final pickupPos = NavigationEngine.extractPickupLatLng(active);
    final dropPos = NavigationEngine.extractDropLatLng(active);

    if (_rideStatus == 'searching' || _rideStatus == 'declined') {
      if (pickupPos != null && dropPos != null) {
        _fetchRouteFromDirections(pickupPos, dropPos, const Color(0xFF1A73E8), 'route_to_drop', pickupPos, dropPos);
      }
    } else if (_rideStatus == 'accepted' || _rideStatus == 'arrived' || _rideStatus == 'heading_to_pickup') {
      if (pickupPos != null) {
        _fetchRouteFromDirections(driverPos, pickupPos, const Color(0xFF1A73E8), 'route_to_pickup', pickupPos, dropPos);
      }
    } else if (_rideStatus == 'started' || _rideStatus == 'on_trip') {
      if (dropPos != null) {
        _fetchRouteFromDirections(driverPos, dropPos, const Color(0xFF1A73E8), 'route_to_drop', pickupPos, dropPos);
      }
    }
  }

  Future<void> _fetchRouteFromDirections(LatLng origin, LatLng destination, Color color, String polylineId, LatLng? pickupPos, LatLng? dropPos) async {
    final String baseUrl = NetworkConfig.backendUrl;
    final Uri url = Uri.parse('$baseUrl/api/directions?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}');
    
    try {
      final response = await ApiClient().get(url, timeout: const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final route = data['routes'][0];
          final String polylineStr = route['overview_polyline']['points'];
          final String? durationText = route['legs'] != null && route['legs'].isNotEmpty 
              ? route['legs'][0]['duration']['text'] 
              : null;
              
          final List<LatLng> polylineCoordinates = _decodePolyline(polylineStr);
          if (polylineCoordinates.isNotEmpty && mounted) {
            setState(() {
              _points = polylineCoordinates;
              _routeProgressIndex = 0;
              _passedRoutePoints = [];
              _remainingRoutePoints = List<LatLng>.from(polylineCoordinates);
              if (durationText != null) {
                _etaText = durationText;
              }
              _updateLiveRouteProgress(BookingManager().driverLatLng);
              
              final showDriverMarker = (_rideStatus != 'searching' && _rideStatus != 'declined') && BookingManager().hasRealDriverLocation;
              _markers = {
                if (pickupPos != null)
                  Marker(
                    markerId: const MarkerId('start'),
                    position: pickupPos,
                    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                    infoWindow: const InfoWindow(title: 'Pickup Location'),
                  ),
                if (dropPos != null)
                  Marker(
                    markerId: const MarkerId('end'),
                    position: dropPos,
                    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                    infoWindow: const InfoWindow(title: 'Dropoff Location'),
                  ),
                if (showDriverMarker)
                  Marker(
                    markerId: const MarkerId('driver'),
                    position: _driverMarkerAnimator.currentPosition ?? origin,
                    icon: _vehicleMarkerIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
                    rotation: _driverMarkerAnimator.currentPosition != null
                        ? _driverMarkerAnimator.currentHeading
                        : BookingManager().driverHeading,
                    flat: true,
                    anchor: const Offset(0.5, 0.5),
                    zIndex: 100.0,
                    infoWindow: InfoWindow(title: '${widget.vehicleType} Pilot'),
                  ),
              };
            });
            return;
          }
        }
      }
      _setFallbackRoute(origin, destination, color, polylineId, pickupPos, dropPos);
    } catch (e) {
      debugPrint('Error fetching driver route directions: $e');
      _setFallbackRoute(origin, destination, color, polylineId, pickupPos, dropPos);
    }
  }

  void _setFallbackRoute(LatLng origin, LatLng destination, Color color, String polylineId, LatLng? pickupPos, LatLng? dropPos) {
    if (!mounted) return;
    
    final double distanceMeters = Geolocator.distanceBetween(
      origin.latitude,
      origin.longitude,
      destination.latitude,
      destination.longitude,
    );
    
    final double timeSeconds = distanceMeters / 8.3;
    final int minutes = (timeSeconds / 60).round();
    
    final String eta = minutes > 0 ? '$minutes mins' : '1 min';
    
    setState(() {
      _points = [origin, destination];
      _etaText = eta;
      _polylines = _buildGoogleNavigationPolylines(
        idPrefix: polylineId,
        points: [origin, destination],
        coreColor: color,
      );
      
      final showDriverMarker = (_rideStatus != 'searching' && _rideStatus != 'declined') && BookingManager().hasRealDriverLocation;
      _markers = {
        if (pickupPos != null)
          Marker(
            markerId: const MarkerId('start'),
            position: pickupPos,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            infoWindow: const InfoWindow(title: 'Pickup Location'),
          ),
        if (dropPos != null)
          Marker(
            markerId: const MarkerId('end'),
            position: dropPos,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: const InfoWindow(title: 'Dropoff Location'),
          ),
        if (showDriverMarker)
          Marker(
            markerId: const MarkerId('driver'),
            position: _driverMarkerAnimator.currentPosition ?? origin,
            icon: _vehicleMarkerIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
            rotation: _driverMarkerAnimator.currentPosition != null
                ? _driverMarkerAnimator.currentHeading
                : BookingManager().driverHeading,
            flat: true,
            anchor: const Offset(0.5, 0.5),
            zIndex: 100.0,
            infoWindow: InfoWindow(title: '${widget.vehicleType} Pilot'),
          ),
      };
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

  void _recenterMap() {
    if (_mapController == null) return;
    
    final active = BookingManager().activeBooking;
    LatLng? pickupPos;
    LatLng? dropPos;
    
    if (active != null) {
      if (active['pickupLatLng'] != null) {
        if (active['pickupLatLng'] is LatLng) {
          pickupPos = active['pickupLatLng'] as LatLng;
        } else if (active['pickupLatLng'] is Map) {
          final map = active['pickupLatLng'] as Map;
          pickupPos = LatLng((map['lat'] as num).toDouble(), (map['lng'] as num).toDouble());
        }
      }
      if (active['dropLatLng'] != null) {
        if (active['dropLatLng'] is LatLng) {
          dropPos = active['dropLatLng'] as LatLng;
        } else if (active['dropLatLng'] is Map) {
          final map = active['dropLatLng'] as Map;
          dropPos = LatLng((map['lat'] as num).toDouble(), (map['lng'] as num).toDouble());
        }
      }
    }

    double minLat, maxLat, minLng, maxLng;

    if (_rideStatus == 'searching' || _rideStatus == 'declined') {
      if (pickupPos == null || dropPos == null) {
        if (_points.isNotEmpty) {
          pickupPos = _points.first;
          dropPos = _points.last;
        } else {
          return;
        }
      }
      minLat = pickupPos.latitude < dropPos.latitude ? pickupPos.latitude : dropPos.latitude;
      maxLat = pickupPos.latitude > dropPos.latitude ? pickupPos.latitude : dropPos.latitude;
      minLng = pickupPos.longitude < dropPos.longitude ? pickupPos.longitude : dropPos.longitude;
      maxLng = pickupPos.longitude > dropPos.longitude ? pickupPos.longitude : dropPos.longitude;
    } else {
      final LatLng driverPos = BookingManager().driverLatLng;
      LatLng? targetPos;
      
      if (_rideStatus == 'accepted' || _rideStatus == 'arrived') {
        targetPos = pickupPos;
      } else if (_rideStatus == 'started') {
        targetPos = dropPos;
      }
      
      if (targetPos == null) {
        if (_points.isNotEmpty) {
          targetPos = _points.last;
        } else {
          return;
        }
      }

      minLat = driverPos.latitude < targetPos.latitude ? driverPos.latitude : targetPos.latitude;
      maxLat = driverPos.latitude > targetPos.latitude ? driverPos.latitude : targetPos.latitude;
      minLng = driverPos.longitude < targetPos.longitude ? driverPos.longitude : targetPos.longitude;
      maxLng = driverPos.longitude > targetPos.longitude ? driverPos.longitude : targetPos.longitude;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80.0));
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    Future.delayed(const Duration(milliseconds: 300), () {
      if (BookingManager().hasRealDriverLocation && (_rideStatus == 'started' || _rideStatus == 'accepted')) {
        final driverPos = _driverMarkerAnimator.currentPosition ?? BookingManager().driverLatLng;
        final driverHeading = _driverMarkerAnimator.currentPosition != null
            ? _driverMarkerAnimator.currentHeading
            : BookingManager().driverHeading;
        _updateCameraCustomerFollow(driverPos, driverHeading, force: true);
      } else {
        _recenterMap();
      }
    });
  }

  void _handleRideLocationUpdate(Map<String, dynamic> data) {
    if (!mounted) return;
    final bookingId = data['rideId']?.toString();
    final active = BookingManager().activeBooking;
    final activeId = active?['bookingId']?.toString() ?? active?['id']?.toString() ?? active?['_id']?.toString();
    if (bookingId != null && activeId != null && bookingId != activeId) {
      debugPrint('[CUSTOMER LOCATION] Ignored update for different ride: $bookingId != $activeId');
      return;
    }

    final double? lat = (data['latitude'] as num?)?.toDouble() ?? (data['lat'] as num?)?.toDouble();
    final double? lng = (data['longitude'] as num?)?.toDouble() ?? (data['lng'] as num?)?.toDouble();
    final double heading = (data['heading'] as num?)?.toDouble() ?? (data['bearing'] as num?)?.toDouble() ?? 0.0;
    final String? eta = data['eta']?.toString();
    final String? remainingDist = data['remainingDistance']?.toString();
    final String? vType = data['vehicleType']?.toString();
    final double? accuracy = (data['accuracy'] as num?)?.toDouble();
    final int? timestamp = (data['timestamp'] as num?)?.toInt();
    final double? speed = (data['speed'] as num?)?.toDouble();

    if (vType != null && vType.isNotEmpty) {
      _loadVehicleMarker(vType);
    }

    _lastGpsUpdateTime = DateTime.now();

    debugPrint('[CUSTOMER LOCATION] Update: lat=$lat, lng=$lng, heading=$heading, accuracy=$accuracy, eta=$eta, dist=$remainingDist, vehicle=$vType');

    if (lat != null && lng != null) {
      final driverPos = LatLng(lat, lng);
      BookingManager().driverLatLng = driverPos;
      BookingManager().driverHeading = heading;
      if (accuracy != null) BookingManager().driverAccuracy = accuracy;
      if (speed != null) BookingManager().driverSpeed = speed;
      if (eta != null && eta.isNotEmpty) BookingManager().latestEta = eta;
      if (remainingDist != null && remainingDist.isNotEmpty) BookingManager().latestRemainingDistance = remainingDist;

      if ((eta != null && eta.isNotEmpty) || (remainingDist != null && remainingDist.isNotEmpty)) {
        setState(() {
          if (eta != null && eta.isNotEmpty) _etaText = eta;
          if (remainingDist != null && remainingDist.isNotEmpty) _liveRemainingDistance = remainingDist;
        });
      }

      // Smooth 60 FPS interpolation on the customer map
      _driverMarkerAnimator.updateTarget(
        position: driverPos,
        heading: heading,
        speedMps: (speed != null ? speed / 3.6 : null),
        accuracyMeters: accuracy,
        timestampMs: timestamp ?? DateTime.now().millisecondsSinceEpoch,
        routeForSnapping: _points,
      );

      // Smoothly update camera to follow vehicle on new GPS location fix
      _maybeUpdateCustomerCameraFollow(driverPos, heading);

      final String? navStatus = data['navigationStatus']?.toString();
      if (navStatus == 'rerouting') {
        // Pilot took another road or wrong-direction - immediately sync customer route
        _updateCustomerRoutes();
      } else {
        // Throttled route update without camera snapping
        _maybeThrottleRouteUpdate(driverPos);
      }
    }
  }

  void _handleRoundTripLegUpdate(Map<String, dynamic> data) {
    if (!mounted) return;
    final currentLeg = data['currentLeg']?.toString();
    final outwardStatus = data['outwardTripStatus']?.toString();
    final returnStatus = data['returnTripStatus']?.toString();
    final price = data['price']?.toString();
    final status = data['status']?.toString();

    setState(() {
      if (currentLeg != null && currentLeg.isNotEmpty) {
        _roundTripLeg = currentLeg;
      }
      if (outwardStatus != null && outwardStatus.isNotEmpty) {
        _outwardTripStatus = outwardStatus;
      }
      if (returnStatus != null && returnStatus.isNotEmpty) {
        _returnTripStatus = returnStatus;
      }
      if (price != null && price.isNotEmpty) {
        _roundTripPrice = price;
      }
      if (status == 'completed' || currentLeg == 'completed') {
        _rideCompleted = true;
      }
    });

    if (currentLeg == 'waiting') {
      WakeLockService.wakeUpScreen();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Leg 1 Complete! Pilot is waiting for you at the destination.'),
          backgroundColor: Color(0xFF7E22CE),
          duration: Duration(seconds: 4),
        ),
      );
    } else if (currentLeg == 'return') {
      WakeLockService.wakeUpScreen();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Return Journey Started! Heading back to origin.'),
          backgroundColor: Color(0xFF16A34A),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _fetchLatestPilotLocation(String rideId) async {
    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/ride/latest-location?rideId=$rideId');
      final res = await ApiClient().get(uri, retry: false);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['location'] != null) {
          _handleRideLocationUpdate(Map<String, dynamic>.from(data['location']));
        }
      }
    } catch (e) {
      debugPrint('[LiveTracking] Error fetching initial pilot location: $e');
    }
  }

  Future<void> _shareTripOnWhatsApp() async {
    final active = BookingManager().activeBooking;
    final rideId = active?['bookingId']?.toString() ??
        active?['id']?.toString() ??
        active?['_id']?.toString() ?? '';

    if (rideId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot share: active ride reference not found.'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    setState(() => _isSharingLiveTrip = true);

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/ride/share-token');
      final res = await ApiClient().post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'rideId': rideId}),
        retry: false,
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['shareUrl'] != null && data['shareUrl'].toString().trim().isNotEmpty) {
          String shareUrl = data['shareUrl'].toString().trim();
          // Guarantee that internal ELB hostnames are never exposed in user-facing WhatsApp messages
          if (shareUrl.contains('elb.amazonaws.com')) {
            shareUrl = shareUrl.replaceFirst(RegExp(r'https?://[^/]+'), 'https://dk60tgl9yds4p.cloudfront.net');
          }

          final String shortCode = data['rideRef']?.toString() ??
              data['shortCode']?.toString() ??
              rideId.substring(0, math.min(8, rideId.length)).toUpperCase();

          final String message = "🚗 I'm currently travelling with StayDriv.\n\n"
              "Track my ride and live location here:\n$shareUrl\n\n"
              "Ride ID: $shortCode\n\n"
              "This link is available only while my ride is active.";

          final encodedMessage = Uri.encodeComponent(message);
          final whatsappUri = Uri.parse('whatsapp://send?text=$encodedMessage');
          final webUri = Uri.parse('https://api.whatsapp.com/send?text=$encodedMessage');

          bool launched = false;
          try {
            if (await canLaunchUrl(whatsappUri)) {
              launched = await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
            }
          } catch (_) {}

          if (!launched) {
            try {
              if (await canLaunchUrl(webUri)) {
                launched = await launchUrl(webUri, mode: LaunchMode.externalApplication);
              }
            } catch (_) {}
          }

          if (!launched && mounted) {
            await Clipboard.setData(ClipboardData(text: message));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('WhatsApp not detected. Safety tracking link copied to clipboard!'),
                backgroundColor: AppTheme.primaryColor,
                duration: Duration(seconds: 4),
              ),
            );
          }
        } else {
          throw Exception(data['message'] ?? 'Unable to create live tracking link. Please try again.');
        }
      } else {
        throw Exception('Unable to create live tracking link. Please try again.');
      }
    } catch (e) {
      debugPrint('[LiveTracking] Error sharing live ride: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to create live tracking link. Please try again.'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSharingLiveTrip = false);
      }
    }
  }

  void _handleLivePaymentSuccess(Map<String, dynamic> data) {
    final active = BookingManager().activeBooking;
    final bId = active?['bookingId']?.toString() ?? active?['id']?.toString() ?? active?['_id']?.toString();
    final eventBId = data['bookingId']?.toString();
    if (bId != null && eventBId != null && bId == eventBId && mounted) {
      setState(() {
        _isRidePaid = true;
      });
      BookingManager().markBookingAsPaid(
        bookingId: bId,
        paymentOption: data['paymentOption']?.toString() ?? data['method']?.toString() ?? 'Online',
        paymentId: data['paymentId']?.toString(),
      );
    }
  }

  Future<void> _verifyServerPaymentStatus() async {
    final active = BookingManager().activeBooking;
    final bId = active?['bookingId'] ?? active?['id'] ?? active?['_id'];
    if (bId == null || bId.toString().isEmpty) return;

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/booking/$bId/payment-status');
      final res = await ApiClient().get(uri, retry: false);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['paymentStatus'] == 'paid' && mounted) {
          setState(() {
            _isRidePaid = true;
          });
          BookingManager().markBookingAsPaid(
            bookingId: bId.toString(),
            paymentOption: data['paymentOption'] ?? 'Paid',
            paymentId: data['paymentId'],
          );
        }
      }
    } catch (e) {
      debugPrint('[LiveTracking] Payment status fetch note: $e');
    }
  }


  @override
  void dispose() {
    _driverMarkerAnimator.dispose();
    _staleGpsTimer?.cancel();
    _stopWaitingTimer();
    final active = BookingManager().activeBooking;
    final bId = active?['bookingId']?.toString() ?? active?['id']?.toString() ?? active?['_id']?.toString();
    if (bId != null && bId.isNotEmpty) {
      SocketService().leaveRide(bId);
    }
    _driverLocationSub?.cancel();
    _statusSub?.cancel();
    _bookingSub?.cancel();
    _waitingTimer?.cancel();
    _feedbackController.dispose();
    SocketService().removePaymentSuccessListener(_handleLivePaymentSuccess);
    SocketService().removeRideLocationListener(_handleRideLocationUpdate);
    SocketService().removeRideMessageListener(_handleIncomingRideMessage);
    SocketService().removeMessageDeliveredListener(_handleMessageDelivered);
    SocketService().removeMessageReadListener(_handleMessageRead);
    SocketService().removeRideChatHistoryListener(_handleRideChatHistory);
    SocketService().removeRoundTripLegListener(_handleRoundTripLegUpdate);
    _chatController.dispose();
    FloatingWidgetService.hide();
    WidgetsBinding.instance.removeObserver(this);
    
    // Clear booking only if cancelled or declined. Never clear completed rides on dispose so payment state is retained.
    if (active != null) {
      final status = active['status'] as String?;
      if (status == 'cancelled' || status == 'declined') {
        BookingManager().clearBooking();
      }
    }
    WakeLockService.releaseWakeLock();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      if (!_rideCompleted) {
        final active = BookingManager().activeBooking;
        final pilotName = (active?['driverName'] ?? active?['pilotName'] ?? 'Pilot Partner').toString();
        final vType = widget.vehicleType.isNotEmpty ? widget.vehicleType : 'Ride';
        final plate = (active?['vehiclePlate'] ?? active?['vehicleNumber'] ?? '').toString();
        final plateStr = plate.isNotEmpty ? ' ($plate)' : '';
        FloatingWidgetService.show(
          role: 'Customer',
          status: _rideStatus,
          title: _rideStatus == 'searching'
              ? 'Finding Pilot...'
              : (_rideStatus == 'arrived'
                  ? 'Pilot Arrived!'
                  : (_rideStatus == 'started' ? 'Trip in Progress' : 'Pilot Assigned')),
          subtitle: _rideStatus == 'searching'
              ? 'Connecting with nearby pilots'
              : '$pilotName • $vType$plateStr',
          eta: _etaText ?? '',
          isPilot: false,
        );
      }
    } else if (state == AppLifecycleState.resumed) {
      FloatingWidgetService.hide();
    }
  }

  void _handleCancellationNotification(String? reason, String? cancelledBy) {
    if (_isPilotCancelledHandled) return;
    _isPilotCancelledHandled = true;
    WakeLockService.wakeUpScreen(); // Turn on screen and alert user

    try {
      FlutterRingtonePlayer().play(
        android: AndroidSounds.notification,
        ios: IosSounds.glass,
        looping: false,
        volume: 1.0,
      );
      HapticFeedback.vibrate();
    } catch (e) {
      debugPrint("Ringtone/Haptic error on cancellation: $e");
    }

    final isCustomerCancelled = cancelledBy == 'customer';
    final titleText = isCustomerCancelled ? 'Customer Cancelled Ride' : 'Pilot Cancelled Ride';
    final defaultReason = isCustomerCancelled ? 'Customer cancelled the ride request' : 'Pilot unable to fulfill request';
    final displayReason = (reason != null && reason.trim().isNotEmpty) ? reason : defaultReason;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🔔 RIDE CANCELLED BY ${isCustomerCancelled ? "CUSTOMER" : "PILOT"}: $displayReason'),
          backgroundColor: AppTheme.errorColor,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.cancel, color: AppTheme.errorColor, size: 28),
              const SizedBox(width: 10),
              Expanded(child: Text(titleText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
            ],
          ),
          content: Text(
            isCustomerCancelled
                ? 'The customer has cancelled this ride request.\n\nReason: "$displayReason"\n\nYou are now ready for new ride requests.'
                : 'Your pilot has cancelled this ride request.\n\nReason: "$displayReason"',
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
                _redirectToHome();
              },
              child: const Text('Return to Home', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          _redirectToHome();
        }
      });
    }
  }

  void _redirectToHome() {
    BookingManager().clearBooking();
    if (mounted && Navigator.canPop(context)) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _showActionSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.primaryColor,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _submitFeedback() {
    _showActionSnackbar('Feedback submitted! Thank you for riding with StayDriv.');
    final active = BookingManager().activeBooking;
    final bId = active?['bookingId']?.toString() ?? active?['id']?.toString() ?? active?['_id']?.toString();
    if (bId != null && bId.isNotEmpty) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setBool('rated_booking_$bId', true);
      });
    }
    BookingManager().clearBooking();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  bool _isCancelling = false;

  void _confirmCancelRide() {
    if (_isCancelling) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Cancel Ride?',
          style: GoogleFonts.hankenGrotesk(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppTheme.onSurfaceColor,
          ),
        ),
        content: Text(
          'Are you sure you want to cancel this ride?',
          style: GoogleFonts.inter(
            fontSize: 15,
            color: AppTheme.onSurfaceVariant,
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Keep Ride',
              style: GoogleFonts.hankenGrotesk(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.onSurfaceVariant,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              elevation: 0,
            ),
            onPressed: _isCancelling
                ? null
                : () async {
                    Navigator.of(ctx).pop();
                    await _executeRideCancellation();
                  },
            child: Text(
              'Cancel Ride',
              style: GoogleFonts.hankenGrotesk(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _executeRideCancellation({String reason = 'Customer cancelled ride'}) async {
    if (_isCancelling) return;
    setState(() => _isCancelling = true);

    try {
      final active = BookingManager().activeBooking;
      final bookingId = active?['bookingId']?.toString() ??
          active?['id']?.toString() ??
          active?['_id']?.toString() ??
          '';

      // 1. Cancel booking through BookingManager (updates internal state, syncs with Firestore & MongoDB)
      await BookingManager().cancelBooking(reason, 'customer');

      // 2. Also emit through SocketService so pilot app drops incoming request immediately
      if (bookingId.isNotEmpty) {
        SocketService().emitRideCancelled(bookingId: bookingId, reason: reason);
      }

      // 3. Cleanly clear local booking state
      BookingManager().clearBooking();

      if (!mounted) return;

      // 4. Return to home/booking screen
      Navigator.of(context).popUntil((route) => route.isFirst);

      // 5. Show short confirmation
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ride cancelled successfully.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white),
          ),
          backgroundColor: const Color(0xFF1E293B),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (e) {
      debugPrint('[LiveTracking] Error cancelling ride: $e');
      if (mounted) {
        BookingManager().clearBooking();
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } finally {
      if (mounted) {
        setState(() => _isCancelling = false);
      }
    }
  }

  void _showCancelDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        final reasons = [
          'Driver is too far away',
          'Driver asked me to cancel',
          'I entered the wrong pickup location',
          'I changed my mind',
          'Driver is unresponsive',
        ];
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cancel Ride',
                style: GoogleFonts.hankenGrotesk(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.onSurfaceColor),
              ),
              const SizedBox(height: 8),
              Text(
                'Please tell us why you are cancelling.',
                style: GoogleFonts.inter(fontSize: 14, color: AppTheme.onSurfaceVariant),
              ),
              if (_rideStatus == 'arrived') ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 16, color: AppTheme.errorColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'WARNING: The pilot has already arrived. Cancelling now will add a ₹10 cancellation charge to your next booking.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppTheme.errorColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ...reasons.map((reason) => ListTile(
                title: Text(reason, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500)),
                trailing: const Icon(Icons.chevron_right, color: AppTheme.onSurfaceVariant),
                onTap: () async {
                  Navigator.pop(context); // Close sheet
                  await _executeRideCancellation(reason: reason);
                },
              )),
            ],
          ),
        );
      },
    );
  }

  void _showAdminSupportSheet({
    required String driverName,
    required String plate,
    required String vehicleInfo,
    required String? bookingId,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.support_agent_rounded, color: Color(0xFF2563EB), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '24/7 Admin & Operations Desk',
                          style: GoogleFonts.hankenGrotesk(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Ride: ${bookingId ?? 'Active Booking'} • Pilot: $driverName',
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ASSIGNED PILOT VEHICLE', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
                        const SizedBox(height: 2),
                        Text(vehicleInfo, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFFDC2626))),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(plate, style: GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.phone_in_talk_rounded, color: Colors.green.shade700, size: 22),
                ),
                title: Text('Call Admin / Operations Hotline', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: Text('Direct connection to live dispatch manager', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  Navigator.pop(ctx);
                  final uri = Uri.parse('tel:+919966332211');
                  try {
                    if (await canLaunchUrl(uri)) await launchUrl(uri);
                  } catch (_) {}
                },
              ),
              const Divider(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.report_problem_rounded, color: Color(0xFFDC2626), size: 22),
                ),
                title: Text('Alert Admin Console (Priority SOS)', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14, color: const Color(0xFFDC2626))),
                subtitle: Text('Instantly alerts Admin & Operations monitoring team', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    final baseUrl = NetworkConfig.backendUrl;
                    await ApiClient().post(
                      Uri.parse('$baseUrl/api/complaints'),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode({
                        'bookingId': bookingId ?? 'LIVE_BOOKING',
                        'driverName': driverName,
                        'vehiclePlate': plate,
                        'vehicleType': vehicleInfo,
                        'type': 'customer_emergency_help',
                        'priority': 'CRITICAL',
                        'description': 'Customer requested immediate assistance from live tracking screen.',
                        'createdAt': DateTime.now().toIso8601String(),
                      }),
                      retry: false,
                    );
                  } catch (_) {}
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text('Alert transmitted to StayDriv Operations Console!'),
                          ],
                        ),
                        backgroundColor: Color(0xFF1B7C3E),
                      ),
                    );
                  }
                },
              ),
              const Divider(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.dashboard_customize_rounded, color: Color(0xFF2563EB), size: 22),
                ),
                title: Text('StayDriv Admin Console', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: Text('Direct link to open Admin Console for operations', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600)),
                trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                onTap: () async {
                  Navigator.pop(ctx);
                  final uri = Uri.parse('/admin');
                  try {
                    if (await canLaunchUrl(uri)) await launchUrl(uri);
                  } catch (_) {}
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.sports_motorsports_rounded, color: Color(0xFF9333EA), size: 22),
                ),
                title: Text('Pilot Portal (Dual View)', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: Text('Open Pilot / Driver app view', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600)),
                trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                onTap: () async {
                  Navigator.pop(ctx);
                  final uri = Uri.parse('/?role=pilot');
                  try {
                    if (await canLaunchUrl(uri)) await launchUrl(uri);
                  } catch (_) {}
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 600;

    final active = BookingManager().activeBooking;
    
    String calculateFallbackDistance(Map<String, dynamic>? active) {
      if (active == null) return '';
      final payloadDist = active['distance'] as String?;
      if (payloadDist != null && payloadDist.trim().isNotEmpty) {
        final cleanDist = payloadDist.toLowerCase().replaceAll('kms', '').replaceAll('km', '').trim();
        if (cleanDist.isNotEmpty) {
          return "$cleanDist KMS";
        }
        return payloadDist;
      }
      
      try {
        double? lat1, lng1, lat2, lng2;
        final pickupLatLng = active['pickupLatLng'];
        final dropLatLng = active['dropLatLng'];
        
        if (pickupLatLng is LatLng) {
          lat1 = pickupLatLng.latitude;
          lng1 = pickupLatLng.longitude;
        } else if (pickupLatLng is Map) {
          lat1 = double.tryParse(pickupLatLng['lat']?.toString() ?? '') ?? 
                 double.tryParse(pickupLatLng['latitude']?.toString() ?? '');
          lng1 = double.tryParse(pickupLatLng['lng']?.toString() ?? '') ?? 
                 double.tryParse(pickupLatLng['longitude']?.toString() ?? '');
        }
        
        if (dropLatLng is LatLng) {
          lat2 = dropLatLng.latitude;
          lng2 = dropLatLng.longitude;
        } else if (dropLatLng is Map) {
          lat2 = double.tryParse(dropLatLng['lat']?.toString() ?? '') ?? 
                 double.tryParse(dropLatLng['latitude']?.toString() ?? '');
          lng2 = double.tryParse(dropLatLng['lng']?.toString() ?? '') ?? 
                 double.tryParse(dropLatLng['longitude']?.toString() ?? '');
        }
        
        if (lat1 != null && lng1 != null && lat2 != null && lng2 != null) {
          final double distanceInMeters = Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
          final double roadDistanceKm = (distanceInMeters * 1.30) / 1000;
          return '${roadDistanceKm.toStringAsFixed(1)} KMS';
        }

      } catch (e) {
        debugPrint('Error calculating fallback distance: $e');
      }
      return '';
    }

    String formatDateToCustomString(dynamic input) {
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

    String formatBookingTime(dynamic createdAt) {
      if (createdAt == null) return '';
      try {
        final dt = DateTime.parse(createdAt.toString());
        final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
        final period = dt.hour >= 12 ? 'PM' : 'AM';
        return "${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $period";
      } catch (_) {
        return '';
      }
    }

    final bool isHeavyTruck = active?['serviceType'] == 'heavy_truck' ||
        (active?['title'] as String? ?? '').toLowerCase().contains('heavy truck') ||
        (active?['vehicle'] as String? ?? '').toLowerCase().contains('heavy truck');

    if (isHeavyTruck && _rideStatus != 'searching' && _rideStatus != 'declined') {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check_circle_rounded, color: Colors.green.shade600, size: 48),
                ),
                const SizedBox(height: 24),
                Text(
                  'Booking Confirmed!',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.onSurfaceColor,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.5)),
                  ),
                  child: Text(
                    "Your booking is accpeted our pilot contact with you shortly and our contact number is 9010922111",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.onSurfaceColor,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                if (active != null) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Location From', style: GoogleFonts.inter(color: AppTheme.onSurfaceVariant)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          active['pickup'] ?? '',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Location To', style: GoogleFonts.inter(color: AppTheme.onSurfaceVariant)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          active['drop'] ?? '',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Vehicle Type', style: GoogleFonts.inter(color: AppTheme.onSurfaceVariant)),
                      Text(active['vehicle'] ?? '', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Distance', style: GoogleFonts.inter(color: AppTheme.onSurfaceVariant)),
                      Text(calculateFallbackDistance(active), style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Fare Amount', style: GoogleFonts.inter(color: AppTheme.onSurfaceVariant)),
                      Text(active['price'] ?? '', style: GoogleFonts.robotoMono(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('OTP Code', style: GoogleFonts.inter(color: AppTheme.onSurfaceVariant)),
                      Text((active['otp'] ?? active['pickupOtp'] ?? '----').toString(), style: GoogleFonts.robotoMono(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Booking Date', style: GoogleFonts.inter(color: AppTheme.onSurfaceVariant)),
                      Text(
                        formatDateToCustomString(
                          (active['scheduledDate'] != null && (active['scheduledDate'] as String).isNotEmpty)
                              ? active['scheduledDate']
                              : active['createdAt']
                        ),
                        style: GoogleFonts.robotoMono(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Time', style: GoogleFonts.inter(color: AppTheme.onSurfaceVariant)),
                      Text(
                        (active['scheduledTimeSlot'] != null && (active['scheduledTimeSlot'] as String).isNotEmpty)
                            ? active['scheduledTimeSlot']
                            : formatBookingTime(active['createdAt']),
                        style: GoogleFonts.robotoMono(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      BookingManager().clearBooking();
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      'Back to Home',
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
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // 1. Google Map Layer with route and active driver marker
          Positioned.fill(
            child: Listener(
              onPointerDown: (_) {
                _isUserDraggingMap = true;
              },
              onPointerMove: (_) {
                _isUserDraggingMap = true;
                if (_isFollowingDriver) {
                  setState(() => _isFollowingDriver = false);
                }
              },
              onPointerUp: (_) {
                _isUserDraggingMap = false;
              },
              onPointerCancel: (_) {
                _isUserDraggingMap = false;
              },
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _points.isNotEmpty ? _points.first : const LatLng(17.3850, 78.4867),
                  zoom: 14.0,
                ),
                onMapCreated: _onMapCreated,
                onCameraMoveStarted: () {
                  // Only release camera lock if customer is physically touching & dragging the map
                  if (_isUserDraggingMap && _isFollowingDriver) {
                    setState(() => _isFollowingDriver = false);
                  }
                },
                polylines: _polylines,
                markers: _markers,
                zoomControlsEnabled: false,
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
              ),
            ),
          ),

          // 2. Floating Top AppBar
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: isDesktop ? 500 : double.infinity,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Back Action
                    GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Minimize Tracking?'),
                            content: const Text('The ride will continue in the background.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context); // close dialog
                                  Navigator.pop(context); // go back
                                },
                                child: const Text('Minimize'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
                          ],
                          border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.3)),
                        ),
                        child: const Icon(Icons.arrow_back, color: AppTheme.onSurfaceColor),
                      ),
                    ),
                    
                    // StayDriv Title
                    Text(
                      'Live Tracking',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    
                    // Center Location Target
                    GestureDetector(
                      onTap: () {
                        setState(() => _isFollowingDriver = true);
                        if (BookingManager().hasRealDriverLocation) {
                          final LatLng driverPos = _driverMarkerAnimator.currentPosition ?? BookingManager().driverLatLng;
                          final double driverHeading = _driverMarkerAnimator.currentPosition != null
                              ? _driverMarkerAnimator.currentHeading
                              : BookingManager().driverHeading;
                          _updateCameraCustomerFollow(driverPos, driverHeading, force: true);
                        } else {
                          _recenterMap();
                        }
                      },
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
                          ],
                          border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.3)),
                        ),
                        child: const Icon(Icons.my_location, color: AppTheme.onSurfaceColor),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. Floating SOS Button
          Positioned(
            bottom: _rideCompleted ? size.height : 260,
            right: 16,
            child: GestureDetector(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    icon: const Icon(Icons.warning_amber_rounded, color: AppTheme.errorColor, size: 48),
                    title: const Text('Emergency SOS Triggered'),
                    content: const Text(
                      'Our 24/7 safety command center has been notified of your location. A representative will call you immediately.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Dismiss Alert'),
                      ),
                    ],
                  ),
                );
              },
              child: Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: AppTheme.errorColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Color(0x4DBA1A1A), blurRadius: 16, offset: Offset(0, 4)),
                  ],
                ),
                child: const Center(
                  child: Text(
                    'SOS',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 4. Floating Re-center / Follow Vehicle Button (Shown when follow mode is temporarily off)
          if (!_isFollowingDriver)
            Positioned(
              bottom: _rideCompleted ? size.height : 260,
              left: 16,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    setState(() => _isFollowingDriver = true);
                    if (BookingManager().hasRealDriverLocation) {
                      final LatLng driverPos = _driverMarkerAnimator.currentPosition ?? BookingManager().driverLatLng;
                      final double driverHeading = _driverMarkerAnimator.currentPosition != null
                          ? _driverMarkerAnimator.currentHeading
                          : BookingManager().driverHeading;
                      _updateCameraCustomerFollow(driverPos, driverHeading, force: true);
                    } else {
                      _recenterMap();
                    }
                  },
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ],
                      border: Border.all(color: const Color(0xFF1E3A8A).withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.my_location_rounded, color: Color(0xFF1E3A8A), size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Re-center',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1E3A8A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 4. Bottom Sheets
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
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: AnimatedCrossFade(
                duration: const Duration(milliseconds: 400),
                crossFadeState: _rideCompleted
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                
                // --- ACTIVE TRACKING BOTTOM SHEET ---
                firstChild: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 48,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.outlineVariant.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    if (_rideStatus == 'searching' || _rideStatus == 'declined') ...[
                      const SizedBox(height: 12),
                      const Center(
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(color: AppTheme.primaryColor, strokeWidth: 3),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        (_rideStatus == 'declined' || _rideStatus == 'searching')
                            ? 'Finding your StayDriv ride...'
                            : 'Connecting to StayDriv pilot...',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.onSurfaceColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Searching for online drivers nearby...',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppTheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _isCancelling ? null : _confirmCancelRide,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.errorColor,
                            side: BorderSide(color: AppTheme.errorColor.withOpacity(0.6), width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: _isCancelling
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.errorColor),
                                )
                              : Text(
                                  'Cancel Ride',
                                  style: GoogleFonts.hankenGrotesk(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.errorColor,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ] else ...[
                      // Real driver details from booking manager
                      Builder(
                        builder: (context) {
                          final active = BookingManager().activeBooking;
                          final driverName = active != null ? (active['driverName'] as String? ?? 'StayDriv Partner') : 'StayDriv Partner';
                          final rawPlate = active != null ? (active['vehiclePlate'] as String? ?? active['vehicleNumber'] as String?) : null;
                          final plate = (rawPlate != null && rawPlate.trim().isNotEmpty && rawPlate.trim() != 'TS 09 SD 1234')
                              ? rawPlate.trim().toUpperCase()
                              : ((rawPlate != null && rawPlate.trim().isNotEmpty) ? rawPlate.trim().toUpperCase() : 'Verified Vehicle');
                          
                          // Vehicle Category and Red Badge resolution (SCOOTY / BIKE)
                          final rawVType = (active?['driverVehicleType'] ?? active?['vehicleType'] ?? active?['selectedVehicle'] ?? widget.vehicleType).toString().toLowerCase();
                          String vehicleCategoryLabel;
                          IconData vehicleCategoryIcon;
                          if (rawVType.contains('bike') || rawVType.contains('scooty') || rawVType.contains('motorcycle') || rawVType.contains('parcel') || rawVType.contains('two')) {
                            vehicleCategoryLabel = 'SCOOTY / BIKE';
                            vehicleCategoryIcon = Icons.two_wheeler_rounded;
                          } else if (rawVType.contains('auto')) {
                            vehicleCategoryLabel = 'AUTO RICKSHAW';
                            vehicleCategoryIcon = Icons.electric_rickshaw_rounded;
                          } else if (rawVType.contains('car') || rawVType.contains('cab') || rawVType.contains('sedan') || rawVType.contains('suv') || rawVType.contains('hatchback')) {
                            vehicleCategoryLabel = 'CAB / CAR';
                            vehicleCategoryIcon = Icons.directions_car_rounded;
                          } else if (rawVType.contains('mini')) {
                            vehicleCategoryLabel = 'MINI TRUCK';
                            vehicleCategoryIcon = Icons.local_shipping_rounded;
                          } else if (rawVType.contains('truck') || rawVType.contains('heavy')) {
                            vehicleCategoryLabel = 'HEAVY TRUCK';
                            vehicleCategoryIcon = Icons.local_shipping_rounded;
                          } else {
                            vehicleCategoryLabel = (active?['vehicleType'] ?? widget.vehicleType).toString().toUpperCase();
                            vehicleCategoryIcon = Icons.directions_car_rounded;
                          }

                          String rawColor = (active?['vehicleColor'] ?? active?['vehicleModelColor'] ?? '').toString().trim();
                          rawColor = rawColor.replaceAll(RegExp(r'\b(bike|scooty|motorcycle|car|cab|auto|truck)\b', caseSensitive: false), '').trim();

                          final String vehicleBadgeText = (rawColor.isNotEmpty && rawColor.toLowerCase() != 'not set' && rawColor.toLowerCase() != 'none')
                              ? '$vehicleCategoryLabel • ${rawColor.toUpperCase()}'
                              : vehicleCategoryLabel;
                          
                          final bool isParcel = active != null &&
                              (active['serviceType'] == 'parcel' ||
                                  active['bookingType'] == 'parcel' ||
                                  widget.vehicleType.toLowerCase().contains('parcel'));
                          String statusTitle = 'Arriving';
                          String statusDesc = 'Driver is on the way';
                          bool showOtp = false;

                          if (_rideStatus == 'accepted') {
                            statusTitle = 'Driver is coming';
                            statusDesc = !BookingManager().hasRealDriverLocation
                                ? 'Connecting to pilot\'s live GPS...'
                                : (_etaText != null ? 'Arriving in $_etaText' : 'Heading to your pickup point');
                            showOtp = true;
                          } else if (_rideStatus == 'arrived') {
                            statusTitle = 'Driver has arrived!';
                            final minutes = _waitingSeconds ~/ 60;
                            final seconds = _waitingSeconds % 60;
                            final timeStr = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
                            
                            if (_waitingSeconds > 180) {
                              final chargeableMinutes = ((_waitingSeconds - 180) / 60).ceil();
                              statusDesc = 'Waiting: $timeStr | Waiting Charge: ₹$chargeableMinutes (₹1/min)';
                            } else {
                              statusDesc = 'Waiting: $timeStr (3 mins free waiting)';
                            }
                            showOtp = true;
                          } else if (_rideStatus == 'started') {
                            final bool isRoundTripBooking = active != null &&
                                (active['isRoundTrip'] == true ||
                                    active['tripType'] == 'ROUND_TRIP' ||
                                    active['tripType'] == 'round_trip');

                            if (isRoundTripBooking && _roundTripLeg == 'waiting') {
                              statusTitle = 'Pilot Waiting at Halt';
                              statusDesc = 'Leg 1 completed • Pilot is waiting for you (free 15 mins included)';
                              showOtp = false;
                            } else if (isRoundTripBooking && _roundTripLeg == 'return') {
                              statusTitle = 'Return Journey (Leg 2)';
                              final distSuffix = (_liveRemainingDistance != null && _liveRemainingDistance!.isNotEmpty) ? ' • $_liveRemainingDistance' : '';
                              statusDesc = !BookingManager().hasRealDriverLocation
                                  ? 'Heading back to origin pickup...'
                                  : (_etaText != null ? 'Reaching origin in $_etaText$distSuffix' : 'Cruising back to pickup point');
                              showOtp = false;
                            } else {
                              final bool isParcelTrip = active != null && (active['serviceType'] == 'parcel' || active['bookingType'] == 'parcel');
                              statusTitle = isRoundTripBooking ? 'Leg 1 (Outward)' : (isParcelTrip ? 'Parcel in Transit' : 'On the way');
                              final distSuffix = (_liveRemainingDistance != null && _liveRemainingDistance!.isNotEmpty) ? ' • $_liveRemainingDistance' : '';
                              statusDesc = !BookingManager().hasRealDriverLocation
                                  ? 'Connecting to pilot\'s live GPS...'
                                  : (_etaText != null ? 'Reaching destination in $_etaText$distSuffix' : 'Cruising toward destination');
                              showOtp = isParcelTrip;
                            }
                          }

                          final bool isRoundTrip = active != null &&
                              (active['isRoundTrip'] == true ||
                                  active['tripType'] == 'ROUND_TRIP' ||
                                  active['tripType'] == 'round_trip');

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isRoundTrip) ...[
                                Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFAF5FF),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFE9D5FF)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            (_roundTripLeg == 'waiting' || _roundTripLeg == 'return' || _roundTripLeg == 'completed')
                                                ? Icons.check_circle_rounded
                                                : Icons.radio_button_checked,
                                            size: 14,
                                            color: (_roundTripLeg == 'waiting' || _roundTripLeg == 'return' || _roundTripLeg == 'completed')
                                                ? const Color(0xFF16A34A)
                                                : const Color(0xFF7E22CE),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Leg 1 Outward',
                                            style: GoogleFonts.inter(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: (_roundTripLeg == 'waiting' || _roundTripLeg == 'return' || _roundTripLeg == 'completed')
                                                  ? const Color(0xFF15803D)
                                                  : const Color(0xFF7E22CE),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Icon(Icons.arrow_forward_rounded, size: 12, color: Color(0xFFC084FC)),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            (_roundTripLeg == 'return' || _roundTripLeg == 'completed')
                                                ? Icons.check_circle_rounded
                                                : (_roundTripLeg == 'waiting' ? Icons.hourglass_top_rounded : Icons.radio_button_unchecked),
                                            size: 14,
                                            color: (_roundTripLeg == 'return' || _roundTripLeg == 'completed')
                                                ? const Color(0xFF16A34A)
                                                : (_roundTripLeg == 'waiting' ? const Color(0xFF7E22CE) : Colors.grey),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Halt Wait',
                                            style: GoogleFonts.inter(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: (_roundTripLeg == 'return' || _roundTripLeg == 'completed')
                                                  ? const Color(0xFF15803D)
                                                  : (_roundTripLeg == 'waiting' ? const Color(0xFF7E22CE) : Colors.grey.shade600),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Icon(Icons.arrow_forward_rounded, size: 12, color: Color(0xFFC084FC)),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _roundTripLeg == 'completed'
                                                ? Icons.check_circle_rounded
                                                : (_roundTripLeg == 'return' ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                                            size: 14,
                                            color: _roundTripLeg == 'completed'
                                                ? const Color(0xFF16A34A)
                                                : (_roundTripLeg == 'return' ? const Color(0xFF7E22CE) : Colors.grey),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Leg 2 Return',
                                            style: GoogleFonts.inter(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: _roundTripLeg == 'completed'
                                                  ? const Color(0xFF15803D)
                                                  : (_roundTripLeg == 'return' ? const Color(0xFF7E22CE) : Colors.grey.shade600),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          statusTitle,
                                          style: GoogleFonts.hankenGrotesk(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.onSurfaceColor,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: const BoxDecoration(
                                                color: AppTheme.safetyYellow,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                statusDesc,
                                                style: GoogleFonts.inter(
                                                  fontSize: 13,
                                                  color: AppTheme.onSurfaceVariant,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (showOtp)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: (isParcel && _rideStatus == 'started')
                                            ? const Color(0xFFF0FDF4)
                                            : AppTheme.surfaceContainerLow,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: (isParcel && _rideStatus == 'started')
                                              ? const Color(0xFF86EFAC)
                                              : AppTheme.outlineVariant.withOpacity(0.4),
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Text(
                                            isParcel
                                                ? (_rideStatus == 'started' ? 'DELIVERY OTP' : 'PICKUP OTP')
                                                : 'START OTP',
                                            style: GoogleFonts.robotoMono(
                                              fontSize: 9,
                                              color: (isParcel && _rideStatus == 'started')
                                                  ? const Color(0xFF15803D)
                                                  : AppTheme.onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            isParcel && _rideStatus == 'started'
                                                ? (active?['deliveryOtp']?.toString() ?? '----')
                                                : (active?['otp']?.toString() ?? active?['pickupOtp']?.toString() ?? '----'),
                                            style: GoogleFonts.robotoMono(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: (isParcel && _rideStatus == 'started')
                                                  ? const Color(0xFF15803D)
                                                  : AppTheme.primaryColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              const Divider(height: 28),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        const CircleAvatar(
                                          radius: 28,
                                          backgroundColor: AppTheme.surfaceContainer,
                                          child: Icon(Icons.person, color: AppTheme.primaryColor),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                driverName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.hankenGrotesk(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppTheme.onSurfaceColor,
                                                ),
                                              ),
                                              Row(
                                                children: [
                                                  const Icon(Icons.star_rounded, color: AppTheme.safetyYellow, size: 16),
                                                  const SizedBox(width: 4),
                                                  Flexible(
                                                    child: Text(
                                                      '4.9 (active partner)',
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: GoogleFonts.robotoMono(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w500,
                                                        color: AppTheme.onSurfaceVariant,
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
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: AppTheme.surfaceContainerHigh,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.5)),
                                        ),
                                        child: Text(
                                          plate,
                                          style: GoogleFonts.robotoMono(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.5,
                                            color: AppTheme.onSurfaceColor,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEF2F2),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFFDC2626), width: 1.5),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(vehicleCategoryIcon, size: 12, color: const Color(0xFFDC2626)),
                                            const SizedBox(width: 4),
                                            Text(
                                              vehicleBadgeText,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w900,
                                                color: const Color(0xFFDC2626),
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if (isParcel && active?['deliveryOtp'] != null) ...[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF0FDF4),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: const Color(0xFF86EFAC)),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFDCFCE7),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.shield_rounded, color: Color(0xFF16A34A), size: 22),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Parcel Delivery Verification OTP',
                                              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF15803D)),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Share this 4-digit OTP with the pilot when your parcel arrives',
                                              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF166534)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: const Color(0xFF4ADE80), width: 1.5),
                                        ),
                                        child: Text(
                                          active!['deliveryOtp'].toString(),
                                          style: GoogleFonts.robotoMono(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            color: const Color(0xFF15803D),
                                            letterSpacing: 2,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _showChatBottomSheet(driverName),
                                      icon: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          const Icon(Icons.chat_bubble_outline, color: AppTheme.onSurfaceColor),
                                          if (_unreadChatCount > 0)
                                            Positioned(
                                              right: -6,
                                              top: -6,
                                              child: Container(
                                                padding: const EdgeInsets.all(4),
                                                decoration: const BoxDecoration(
                                                  color: Colors.red,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Text(
                                                  '$_unreadChatCount',
                                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      label: Text(
                                        _unreadChatCount > 0 ? 'Message ($_unreadChatCount)' : 'Message',
                                        style: GoogleFonts.hankenGrotesk(
                                          fontSize: 16,
                                          color: AppTheme.onSurfaceColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                        side: const BorderSide(color: AppTheme.outlineVariant),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () => _makeCustomerPilotCall(driverName, active?['driverPhone'] as String?),
                                      icon: const Icon(Icons.phone_outlined, color: Colors.white),
                                      label: Text(
                                        'Call',
                                        style: GoogleFonts.hankenGrotesk(
                                          fontSize: 16,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.primaryColor,
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_rideStatus == 'started' || _rideStatus == 'accepted' || _rideStatus == 'arrived') ...[
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _isSharingLiveTrip ? null : _shareTripOnWhatsApp,
                                    icon: _isSharingLiveTrip
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                        : const Icon(Icons.share_location_rounded, color: Colors.white, size: 20),
                                    label: Text(
                                      _isSharingLiveTrip ? 'Preparing Safety Link...' : 'Share Trip for Safety',
                                      style: GoogleFonts.hankenGrotesk(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF25D366),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      elevation: 0,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () => _showAdminSupportSheet(
                                      driverName: driverName,
                                      plate: plate,
                                      vehicleInfo: vehicleBadgeText,
                                      bookingId: active?['bookingId']?.toString() ?? active?['id']?.toString() ?? active?['_id']?.toString(),
                                    ),
                                    icon: const Icon(Icons.support_agent_rounded, size: 20, color: AppTheme.primaryColor),
                                    label: Text(
                                      '24/7 Admin & Support Desk',
                                      style: GoogleFonts.hankenGrotesk(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.primaryColor,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
                                      backgroundColor: AppTheme.primaryColor.withOpacity(0.04),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      padding: const EdgeInsets.symmetric(vertical: 13),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: TextButton(
                                  onPressed: _showCancelDialog,
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppTheme.errorColor,
                                  ),
                                  child: Text(
                                    'Cancel Ride',
                                    style: GoogleFonts.hankenGrotesk(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }
                      ),
                    ],
                  ],
                ),
                
                // --- RIDE COMPLETED & PAYMENT / RATING BOTTOM SHEET ---
                secondChild: !_isRidePaid
                    ? RideCompletedPaymentPanel(
                        booking: BookingManager().activeBooking ?? {
                          'id': 'booking_active',
                          'price': widget.price,
                          'vehicleType': widget.vehicleType,
                        },
                        onPaymentCompleted: () {
                          if (mounted) {
                            setState(() {
                              _isRidePaid = true;
                            });
                          }
                          final active = BookingManager().activeBooking;
                          final bId = active?['bookingId']?.toString() ?? active?['id']?.toString() ?? active?['_id']?.toString();
                          if (bId != null) {
                            BookingManager().markBookingAsPaid(bookingId: bId, paymentOption: 'Paid');
                          }
                        },
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                    Builder(
                      builder: (context) {
                        final active = BookingManager().activeBooking;
                        final finalPrice = active != null ? (active['price'] as String? ?? widget.price) : widget.price;
                        final waitingCharge = active != null ? (active['waitingCharge'] as int? ?? 0) : 0;
                        return Text(
                          waitingCharge > 0
                              ? 'You have arrived safely. Fare charged: $finalPrice (includes ₹$waitingCharge Waiting Charge)'
                              : 'You have arrived safely. Fare charged: $finalPrice',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppTheme.onSurfaceVariant,
                          ),
                        );
                      }
                    ),
                    const Divider(height: 32),

                    Builder(
                      builder: (context) {
                        final active = BookingManager().activeBooking;
                        final driverName = active != null ? (active['driverName'] as String? ?? 'StayDriv Partner') : 'StayDriv Partner';
                        return Text(
                          'Rate $driverName',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.onSurfaceColor,
                          ),
                        );
                      }
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        final starVal = index + 1;
                        final isFilled = _userRating >= starVal;
                        return IconButton(
                          icon: Icon(
                            isFilled ? Icons.star_rounded : Icons.star_border_rounded,
                            color: AppTheme.safetyYellow,
                            size: 36,
                          ),
                          onPressed: () {
                            setState(() {
                              _userRating = starVal.toDouble();
                            });
                          },
                        );
                      }),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: _feedbackController,
                      decoration: const InputDecoration(
                        labelText: 'ADD MORE FEEDBACK',
                        hintText: 'Great drive, very helpful!',
                      ),
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submitFeedback,
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
            ),
          ),
        ],
      ),
    );
  }
}
