import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../../core/firebase_service.dart';

import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

import '../../../core/theme.dart';
import '../../../core/booking_manager.dart';
import '../../../core/network_config.dart';
import '../../../core/api_client.dart';
import '../../../core/wake_lock_service.dart';

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

class _LiveTrackingScreenState extends State<LiveTrackingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _progressAnimation;
  
  bool _rideCompleted = false;
  double _userRating = 5.0;
  final TextEditingController _feedbackController = TextEditingController();

  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  List<LatLng> _points = [];
  String? _etaText;
  String _rideStatus = 'searching'; // 'searching', 'accepted', 'arrived', 'started', 'completed'

  Timer? _waitingTimer;
  int _waitingSeconds = 0;

  final List<Map<String, String>> _chatMessages = [
    {'sender': 'pilot', 'text': 'Hello! I am heading to your pickup location.'},
  ];
  final TextEditingController _chatController = TextEditingController();

  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;
    setState(() {
      _chatMessages.add({'sender': 'customer', 'text': text.trim()});
    });
    _chatController.clear();

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _chatMessages.add({
            'sender': 'pilot',
            'text': 'Got it! Reaching your location shortly.'
          });
        });
      }
    });
  }

  void _showChatBottomSheet(String driverName) {
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
    );
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
    final cleanPhone = (driverPhone ?? '9121440281').replaceAll(RegExp(r'\D'), '');
    
    try {
      final active = BookingManager().activeBooking;
      final myPhone = (active?['passengerPhone'] as String? ?? '9876543210').replaceAll(RegExp(r'\D'), '');
      await ApiClient().post(
        Uri.parse('${NetworkConfig.backendUrl}/api/call/mask'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'fromPhone': myPhone,
          'toPhone': cleanPhone,
        }),
        timeout: const Duration(seconds: 15),
      );
    } catch (e) {
      debugPrint('Call masking call note: $e');
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.phone_in_talk, color: AppTheme.primaryColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Calling $driverName',
                style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Initiating Tata Smartflo Call Masking between Customer and Pilot ($driverName).',
              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F5FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, color: AppTheme.primaryColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your personal phone number is kept private & masked.',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primaryColor),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              final Uri launchUri = Uri(scheme: 'tel', path: cleanPhone);
              if (await canLaunchUrl(launchUri)) {
                await launchUrl(launchUri);
              }
            },
            icon: const Icon(Icons.call, color: Colors.white, size: 18),
            label: const Text('Dial Call', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
          ),
        ],
      ),
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

  StreamSubscription<LatLng>? _driverLocationSub;
  StreamSubscription<String>? _statusSub;
  StreamSubscription<Map<String, dynamic>?>? _bookingSub;
  bool _isPilotCancelledHandled = false;
  bool get _isFirebaseInitialized => false;

  @override
  void initState() {
    super.initState();
    WakeLockService.acquireWakeLock(); // Keep device active during ride session
    
    final active = BookingManager().activeBooking;
    LatLng? pickupPos;
    LatLng? dropPos;
    if (active != null) {
      _rideStatus = active['status'] as String? ?? 'searching';
      if (_rideStatus == 'completed') {
        _rideCompleted = true;
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
    
    if (widget.routePoints != null && widget.routePoints!.isNotEmpty) {
      _points = widget.routePoints!;
      _setupRoute();
    } else if (pickupPos != null && dropPos != null) {
      _points = [pickupPos, dropPos];
      _setupRoute();
    } else {
      _points = [
        const LatLng(17.4834, 78.3871),
        const LatLng(17.4854, 78.3891),
      ];
      _setupRoute();
    }

    if (active != null && _rideStatus == 'cancelled') {
      final cancelledBy = active['cancelledBy'] as String?;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleCancellationNotification(active['cancelReason'] as String?, cancelledBy);
      });
    }

    _bookingSub = BookingManager().bookingStream.listen((booking) {
      if (mounted && booking != null) {
        final status = booking['status'] as String?;
        final cancelledBy = booking['cancelledBy'] as String?;
        if (status == 'cancelled') {
          _handleCancellationNotification(booking['cancelReason'] as String? ?? booking['reason'] as String?, cancelledBy);
        }
      }
    });

    _driverLocationSub = BookingManager().driverLocationStream.listen((LatLng newPos) {
      if (mounted) {
        setState(() {
          _markers = _markers.map((m) {
            if (m.markerId.value == 'driver') {
              return m.copyWith(positionParam: newPos);
            }
            return m;
          }).toSet();
        });

        // Fetch new route and ETA whenever driver moves!
        _updateCustomerRoutes();
        _recenterMap();
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
          _showActionSnackbar('Pilot declined the ride. Searching for another pilot...');
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
    _polylines = {
      Polyline(
        polylineId: const PolylineId('tracking_line'),
        points: _points,
        color: AppTheme.primaryColor,
        width: 5,
      ),
    };

    final LatLng driverPos = BookingManager().driverLatLng;
    final showDriverMarker = (_rideStatus != 'searching' && _rideStatus != 'declined');

    _markers = {
      Marker(
        markerId: const MarkerId('start'),
        position: _points.first,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Pickup Location'),
      ),
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
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
          infoWindow: InfoWindow(title: '${widget.vehicleType} Driver'),
        ),
    };
  }

  void _updateCustomerRoutes() {
    final active = BookingManager().activeBooking;
    if (active == null) return;

    final LatLng driverPos = BookingManager().driverLatLng;
    
    LatLng? pickupPos;
    if (active['pickupLatLng'] != null) {
      if (active['pickupLatLng'] is LatLng) {
        pickupPos = active['pickupLatLng'] as LatLng;
      } else if (active['pickupLatLng'] is Map) {
        final map = active['pickupLatLng'] as Map;
        pickupPos = LatLng((map['lat'] as num).toDouble(), (map['lng'] as num).toDouble());
      }
    }
    
    LatLng? dropPos;
    if (active['dropLatLng'] != null) {
      if (active['dropLatLng'] is LatLng) {
        dropPos = active['dropLatLng'] as LatLng;
      } else if (active['dropLatLng'] is Map) {
        final map = active['dropLatLng'] as Map;
        dropPos = LatLng((map['lat'] as num).toDouble(), (map['lng'] as num).toDouble());
      }
    }

    if (pickupPos == null || dropPos == null) return;

    if (_rideStatus == 'searching' || _rideStatus == 'declined') {
      _fetchRouteFromDirections(pickupPos, dropPos, AppTheme.primaryColor, 'route_to_drop', pickupPos, dropPos);
    } else if (_rideStatus == 'accepted' || _rideStatus == 'arrived') {
      _fetchRouteFromDirections(driverPos, pickupPos, Colors.green, 'route_to_pickup', pickupPos, dropPos);
    } else if (_rideStatus == 'started') {
      _fetchRouteFromDirections(driverPos, dropPos, AppTheme.primaryColor, 'route_to_drop', pickupPos, dropPos);
    }
  }

  Future<void> _fetchRouteFromDirections(LatLng origin, LatLng destination, Color color, String polylineId, LatLng pickupPos, LatLng dropPos) async {
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
              if (durationText != null) {
                if (durationText.contains('hour') || durationText.contains('day') || durationText.contains('hr')) {
                  final int mockMins = 3 + (durationText.hashCode % 6);
                  _etaText = '$mockMins mins';
                } else {
                  _etaText = durationText;
                }
              }
              _polylines = {
                Polyline(
                  polylineId: PolylineId(polylineId),
                  points: polylineCoordinates,
                  color: color,
                  width: 5,
                ),
              };
              
              final showDriverMarker = (_rideStatus != 'searching' && _rideStatus != 'declined');
              _markers = {
                Marker(
                  markerId: const MarkerId('start'),
                  position: pickupPos,
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                  infoWindow: const InfoWindow(title: 'Pickup Location'),
                ),
                Marker(
                  markerId: const MarkerId('end'),
                  position: dropPos,
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                  infoWindow: const InfoWindow(title: 'Dropoff Location'),
                ),
                if (showDriverMarker)
                  Marker(
                    markerId: const MarkerId('driver'),
                    position: origin,
                    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
                    infoWindow: InfoWindow(title: '${widget.vehicleType} Driver'),
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

  void _setFallbackRoute(LatLng origin, LatLng destination, Color color, String polylineId, LatLng pickupPos, LatLng dropPos) {
    if (!mounted) return;
    
    final double distanceMeters = Geolocator.distanceBetween(
      origin.latitude,
      origin.longitude,
      destination.latitude,
      destination.longitude,
    );
    
    final double timeSeconds = distanceMeters / 8.3;
    int minutes = (timeSeconds / 60).round();
    
    if (minutes > 15) {
      minutes = 3 + (minutes % 6);
    }
    
    final String eta = minutes > 0 ? '$minutes mins' : '1 min';
    
    setState(() {
      _points = [origin, destination];
      _etaText = eta;
      _polylines = {
        Polyline(
          polylineId: PolylineId(polylineId),
          points: [origin, destination],
          color: color,
          width: 5,
        ),
      };
      
      final showDriverMarker = (_rideStatus != 'searching' && _rideStatus != 'declined');
      _markers = {
        Marker(
          markerId: const MarkerId('start'),
          position: pickupPos,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: 'Pickup Location'),
        ),
        Marker(
          markerId: const MarkerId('end'),
          position: dropPos,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Dropoff Location'),
        ),
        if (showDriverMarker)
          Marker(
            markerId: const MarkerId('driver'),
            position: origin,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
            infoWindow: InfoWindow(title: '${widget.vehicleType} Driver'),
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
      _recenterMap();
    });
  }

  @override
  void dispose() {
    _driverLocationSub?.cancel();
    _statusSub?.cancel();
    _bookingSub?.cancel();
    _waitingTimer?.cancel();
    _feedbackController.dispose();
    
    // Clear booking if it is in terminal status to avoid stale states
    final active = BookingManager().activeBooking;
    if (active != null) {
      final status = active['status'] as String?;
      if (status == 'completed' || status == 'cancelled' || status == 'declined') {
        BookingManager().clearBooking();
      }
    }
    WakeLockService.releaseWakeLock();
    super.dispose();
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
    BookingManager().clearBooking();
    Navigator.of(context).popUntil((route) => route.isFirst);
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
                onTap: () {
                  Navigator.pop(context); // Close sheet
                  BookingManager().cancelBooking(reason, 'customer');
                  Navigator.pop(context); // Go back to home
                },
              )),
            ],
          ),
        );
      },
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
                      Text(active['otp'] ?? '1234', style: GoogleFonts.robotoMono(fontWeight: FontWeight.bold)),
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
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _points.first,
                zoom: 14.0,
              ),
              onMapCreated: _onMapCreated,
              polylines: _polylines,
              markers: _markers,
              zoomControlsEnabled: false,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
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
                        _recenterMap();
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
                        _rideStatus == 'declined'
                            ? 'Pilot declined the ride. Searching another pilot...'
                            : 'Finding your StayDriv ride...',
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
                      const SizedBox(height: 16),
                    ] else ...[
                      // Real driver details from booking manager
                      Builder(
                        builder: (context) {
                          final active = BookingManager().activeBooking;
                          final driverName = active != null ? (active['driverName'] as String? ?? 'StayDriv Partner') : 'StayDriv Partner';
                          final plate = active != null ? (active['vehiclePlate'] as String? ?? 'TS-08-EX-4921') : 'TS-08-EX-4921';
                          final desc = active != null ? (active['vehicleModelColor'] as String? ?? widget.vehicleType) : widget.vehicleType;
                          
                          String statusTitle = 'Arriving';
                          String statusDesc = 'Driver is on the way';
                          bool showOtp = false;

                          if (_rideStatus == 'accepted') {
                            statusTitle = 'Driver is coming';
                            statusDesc = _etaText != null ? 'Arriving in $_etaText' : 'Heading to your pickup point';
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
                            statusTitle = 'On the way';
                            statusDesc = _etaText != null ? 'Reaching destination in $_etaText' : 'Cruising toward destination';
                            showOtp = false;
                          }

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
                                        color: AppTheme.surfaceContainerLow,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.4)),
                                      ),
                                      child: Column(
                                        children: [
                                          Text(
                                            'START OTP',
                                            style: GoogleFonts.robotoMono(
                                              fontSize: 9,
                                              color: AppTheme.onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            active?['otp'] ?? '4921',
                                            style: GoogleFonts.robotoMono(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.primaryColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              const Divider(height: 28),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const CircleAvatar(
                                        radius: 28,
                                        backgroundColor: AppTheme.surfaceContainer,
                                        child: Icon(Icons.person, color: AppTheme.primaryColor),
                                      ),
                                      const SizedBox(width: 16),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            driverName,
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
                                              Text(
                                                '4.9 (active partner)',
                                                style: GoogleFonts.robotoMono(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                  color: AppTheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppTheme.surfaceContainerHigh,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          plate,
                                          style: GoogleFonts.robotoMono(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.onSurfaceColor,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        desc,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: AppTheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _showChatBottomSheet(driverName),
                                      icon: const Icon(Icons.chat_bubble_outline, color: AppTheme.onSurfaceColor),
                                      label: Text(
                                        'Message',
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
                
                // --- RIDE COMPLETED & RATING BOTTOM SHEET ---
                secondChild: Column(
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
