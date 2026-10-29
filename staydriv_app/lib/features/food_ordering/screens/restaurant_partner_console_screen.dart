import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/api_client.dart';
import '../../../core/firebase_service.dart';
import '../../../core/socket_service.dart';
import '../../../core/call_masking_service.dart';
import '../../../services/api_service.dart';
import '../../onboarding/screens/login_screen.dart';
import '../models/food_models.dart';
import '../services/food_service.dart';
import '../services/restaurant_order_ringtone_service.dart';
import '../widgets/incoming_order_alert_sheet.dart';
import '../widgets/location_pin_picker_dialog.dart';
import '../../dashboard/widgets/console_switcher_sheet.dart';

class RestaurantPartnerConsoleScreen extends StatefulWidget {
  final Map<String, dynamic> restaurantData;

  const RestaurantPartnerConsoleScreen({
    super.key,
    required this.restaurantData,
  });

  @override
  State<RestaurantPartnerConsoleScreen> createState() => _RestaurantPartnerConsoleScreenState();
}

class _RestaurantPartnerConsoleScreenState extends State<RestaurantPartnerConsoleScreen> with SingleTickerProviderStateMixin {
  final FoodService _foodService = FoodService();
  final RestaurantOrderRingtoneService _ringtoneService = RestaurantOrderRingtoneService();

  late TabController _tabController;
  late Map<String, dynamic> _restaurant;
  late bool _isOpen;
  String _restaurantId = '';
  String _restaurantName = '';

  List<FoodOrder> _orders = [];
  List<MenuItem> _menuItems = [];
  bool _isLoadingOrders = false;
  bool _isLoadingMenu = false;
  bool _isTogglingStatus = false;
  bool _isLoggingOut = false;
  Timer? _autoRefreshTimer;

  // Sales, Payment Details & Settlement States
  Map<String, dynamic>? _paymentDetails;
  Map<String, dynamic>? _settlementSummary;
  List<Map<String, dynamic>> _settlements = [];
  List<Map<String, dynamic>> _salesBreakdown = [];
  bool _isLoadingSettlements = false;
  int _salesSubTab = 0; // 0: Settlement History, 1: Orders Breakdown

  // Real-time Incoming Order Alert & Queue States
  final Set<String> _acknowledgedOrderIds = {};
  final List<FoodOrder> _pendingNewOrders = [];
  bool _isAlertModalOpen = false;

  // Filter & Search state for Menu Management
  String _selectedCategory = 'All';
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  // Store Profile Controllers
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _hoursCtrl;
  late TextEditingController _deliveryTimeCtrl;
  late bool _isVegOnly;
  String _coverImageUrl = '';
  bool _isSavingProfile = false;
  bool _isUploadingCover = false;
  double _restaurantLat = 0.0;
  double _restaurantLng = 0.0;
  String _restaurantLocationDetails = '';

  List<String> get _categories {
    final set = <String>{'All'};
    for (final item in _menuItems) {
      if (item.category.trim().isNotEmpty) set.add(item.category.trim());
    }
    return set.toList();
  }

  List<MenuItem> get _filteredMenuItems {
    return _menuItems.where((item) {
      final matchesCat = _selectedCategory == 'All' || item.category.toLowerCase() == _selectedCategory.toLowerCase();
      final matchesQuery = _searchQuery.isEmpty ||
          item.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          item.category.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          item.description.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesCat && matchesQuery;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _restaurant = Map<String, dynamic>.from(widget.restaurantData);
    _restaurantId = (_restaurant['restaurantId'] ?? _restaurant['id'] ?? _restaurant['phone'] ?? _restaurant['_id'] ?? '').toString();
    _restaurantName = _restaurant['name'] as String? ?? 'Restaurant Partner';
    _isOpen = _restaurant['isOpen'] as bool? ?? true;

    // Initialize Store Profile Fields
    _nameCtrl = TextEditingController(text: _restaurantName);
    _phoneCtrl = TextEditingController(text: _restaurant['phone']?.toString() ?? '');
    _emailCtrl = TextEditingController(text: _restaurant['email']?.toString() ?? '');
    _addressCtrl = TextEditingController(text: _restaurant['address']?.toString() ?? '');
    _hoursCtrl = TextEditingController(text: _restaurant['openingHours']?.toString() ?? '07:00 AM - 10:30 PM');
    _deliveryTimeCtrl = TextEditingController(text: _restaurant['deliveryTime']?.toString() ?? '25-35 mins');
    _isVegOnly = _restaurant['isVegOnly'] as bool? ?? false;
    _coverImageUrl = _restaurant['imageUrl']?.toString() ?? '';
    _restaurantLat = (_restaurant['lat'] as num?)?.toDouble() ?? 0.0;
    _restaurantLng = (_restaurant['lng'] as num?)?.toDouble() ?? 0.0;
    _restaurantLocationDetails = _restaurant['locationDetails']?.toString() ?? '';

    // 4 Tabs: Live Orders, Menu Management, Store Profile, Sales & Payouts
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });

    _ringtoneService.init();
    _loadAllData();

    // Setup periodic background refresh every 3 seconds
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        _loadOrdersSilently();
      }
    });

    // Connect to real-time Socket.IO
    try {
      SocketService().initSocket();
      if (_restaurantId.isNotEmpty) {
        SocketService().joinRestaurant(_restaurantId);
      }
      SocketService().addFoodOrderIncomingListener(_handleIncomingOrderEvent);
      SocketService().addFoodOrderStatusListener(_handleFoodOrderStatusEvent);
      SocketService().addFoodMenuUpdatedListener(_handleFoodMenuUpdatedEvent);
      SocketService().addRestaurantUpdatedListener(_handleRestaurantUpdatedEvent);
    } catch (e) {
      debugPrint('[RestaurantPartnerConsole] Socket init error: $e');
    }
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _ringtoneService.stopOrderAlert(forceAll: true);
    SocketService().removeFoodOrderIncomingListener(_handleIncomingOrderEvent);
    SocketService().removeFoodOrderStatusListener(_handleFoodOrderStatusEvent);
    SocketService().removeFoodMenuUpdatedListener(_handleFoodMenuUpdatedEvent);
    SocketService().removeRestaurantUpdatedListener(_handleRestaurantUpdatedEvent);
    SocketService().disconnect();
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _hoursCtrl.dispose();
    _deliveryTimeCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _handleFoodMenuUpdatedEvent(Map<String, dynamic> data) {
    if (!mounted) return;
    final rId = data['restaurantId'] as String? ?? '';
    if (rId.isEmpty || rId == _restaurantId) {
      _loadMenuSilently();
    }
  }

  void _handleRestaurantUpdatedEvent(Map<String, dynamic> data) {
    if (!mounted) return;
    final rId = data['restaurantId'] as String? ?? '';
    if (rId.isEmpty || rId == _restaurantId) {
      setState(() {
        if (data['restaurant'] is Map) {
          _restaurant = Map<String, dynamic>.from(data['restaurant']);
          _restaurantName = _restaurant['name'] as String? ?? _restaurantName;
          _coverImageUrl = _restaurant['imageUrl']?.toString() ?? _coverImageUrl;
        }
        if (data['isOpen'] != null) _isOpen = data['isOpen'] as bool;
      });
    }
  }

  void _checkAndShowIncomingOrderModal() {
    if (!mounted || _isAlertModalOpen) return;
    if (_pendingNewOrders.isEmpty) return;

    final currentOrder = _pendingNewOrders.first;
    _isAlertModalOpen = true;

    // Start loud incoming order ringtone
    _ringtoneService.startOrderAlert(
      currentOrder.orderId,
      summary: 'New order #${currentOrder.orderId} for ₹${currentOrder.totalAmount.toStringAsFixed(0)}',
    );

    IncomingOrderAlertSheet.show(
      context: context,
      order: currentOrder,
      currentQueueIndex: 1,
      totalQueueCount: _pendingNewOrders.length,
      onAccept: (order, prepTime) async {
        Navigator.of(context, rootNavigator: true).pop();
        _isAlertModalOpen = false;
        _acknowledgedOrderIds.add(order.orderId);
        _pendingNewOrders.removeWhere((o) => o.orderId == order.orderId);
        _ringtoneService.stopOrderAlert(orderId: order.orderId);

        await _handleOrderStatusChange(order, 'accepted', prepTime: prepTime);
        _loadOrdersSilently();

        // Advance to next unacknowledged order in the queue if multiple arrived
        if (_pendingNewOrders.isNotEmpty && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _checkAndShowIncomingOrderModal();
          });
        }
      },
      onReject: (order, reason) async {
        Navigator.of(context, rootNavigator: true).pop();
        _isAlertModalOpen = false;
        _acknowledgedOrderIds.add(order.orderId);
        _pendingNewOrders.removeWhere((o) => o.orderId == order.orderId);
        _ringtoneService.stopOrderAlert(orderId: order.orderId);

        await _handleOrderStatusChange(order, 'rejected', reason: reason);
        _loadOrdersSilently();

        // Advance to next unacknowledged order in the queue if multiple arrived
        if (_pendingNewOrders.isNotEmpty && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _checkAndShowIncomingOrderModal();
          });
        }
      },
      onMute: () {
        _ringtoneService.stopOrderAlert(orderId: currentOrder.orderId);
      },
      onClose: () {
        Navigator.of(context, rootNavigator: true).pop();
        _isAlertModalOpen = false;
      },
    ).then((_) {
      _isAlertModalOpen = false;
    });
  }

  void _handleIncomingOrderEvent(Map<String, dynamic> data) {
    if (!mounted) return;
    try {
      final order = FoodOrder.fromJson(data);
      if (order.restaurantId == _restaurantId || _restaurantId.isEmpty) {
        setState(() {
          final exists = _orders.any((o) => o.orderId == order.orderId);
          if (!exists) {
            _orders.insert(0, order);
          }
        });

        // Trigger ringtone and queue alert modal exclusively for newly placed orders
        if (order.orderStatus == 'placed' && !_acknowledgedOrderIds.contains(order.orderId)) {
          final alreadyQueued = _pendingNewOrders.any((o) => o.orderId == order.orderId);
          if (!alreadyQueued) {
            _pendingNewOrders.add(order);
          }
          _checkAndShowIncomingOrderModal();
        }
      }
    } catch (e) {
      debugPrint('[RestaurantPartnerConsole] Incoming order parse error: $e');
    }
    _loadOrdersSilently();
  }

  void _handleFoodOrderStatusEvent(Map<String, dynamic> data) {
    if (!mounted) return;
    try {
      final orderId = data['orderId'] as String? ?? '';
      final status = data['orderStatus'] as String? ?? data['status'] as String? ?? '';

      // If order was cancelled, rejected, or accepted elsewhere, stop ringtone and dismiss
      if (orderId.isNotEmpty && ['accepted', 'preparing', 'ready_for_pickup', 'delivered', 'cancelled', 'rejected'].contains(status)) {
        _acknowledgedOrderIds.add(orderId);
        _pendingNewOrders.removeWhere((o) => o.orderId == orderId);
        _ringtoneService.stopOrderAlert(orderId: orderId);
        if (_pendingNewOrders.isEmpty && _isAlertModalOpen) {
          Navigator.of(context, rootNavigator: true).pop();
          _isAlertModalOpen = false;
        }
      }
    } catch (e) {
      debugPrint('[RestaurantPartnerConsole] Status update event error: $e');
    }
    _loadOrdersSilently();
  }

  Future<void> _loadOrdersSilently() async {
    if (_restaurantId.isEmpty) return;
    try {
      final orders = await _foodService.fetchPartnerOrders(_restaurantId);
      if (mounted) {
        setState(() {
          _orders = orders;
        });

        // Sync & check for unacknowledged 'placed' orders (reconnect / periodic sync)
        final unacknowledgedPlaced = orders.where((o) =>
          o.orderStatus == 'placed' && !_acknowledgedOrderIds.contains(o.orderId)
        ).toList();

        for (final p in unacknowledgedPlaced) {
          if (!_pendingNewOrders.any((o) => o.orderId == p.orderId)) {
            _pendingNewOrders.add(p);
          }
        }

        // Clean up any pending orders that transitioned away from 'placed'
        _pendingNewOrders.removeWhere((p) {
          final current = orders.firstWhere(
            (o) => o.orderId == p.orderId,
            orElse: () => p,
          );
          return current.orderStatus != 'placed';
        });

        if (_pendingNewOrders.isNotEmpty) {
          _checkAndShowIncomingOrderModal();
        } else if (_ringtoneService.isRinging && !_ringtoneService.isTesting) {
          _ringtoneService.stopOrderAlert(forceAll: true);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadMenuSilently() async {
    if (_restaurantId.isEmpty) return;
    try {
      final res = await _foodService.fetchRestaurantDetail(_restaurantId);
      if (mounted) {
        final items = (res['menuItems'] as List<dynamic>? ?? []).whereType<MenuItem>().toList();
        setState(() {
          _menuItems = items;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadAllData() async {
    _loadOrders();
    _loadMenu();
    _loadSalesAndPaymentData();
  }

  Future<void> _handleLogout() async {
    if (_isLoggingOut) return;

    setState(() {
      _isLoggingOut = true;
    });

    try {
      // 1. Cancel background timers and stop order audio ringtones immediately
      _autoRefreshTimer?.cancel();
      _ringtoneService.stopOrderAlert(forceAll: true);

      // 2. Disconnect socket and remove listeners immediately
      try {
        if (_restaurantId.isNotEmpty) {
          SocketService().leaveRestaurant(_restaurantId);
        }
        SocketService().removeFoodOrderIncomingListener(_handleIncomingOrderEvent);
        SocketService().removeFoodOrderStatusListener(_handleFoodOrderStatusEvent);
        SocketService().removeFoodMenuUpdatedListener(_handleFoodMenuUpdatedEvent);
        SocketService().removeRestaurantUpdatedListener(_handleRestaurantUpdatedEvent);
        SocketService().disconnect();
      } catch (sockErr) {
        debugPrint('[RestaurantPartnerConsole] Socket cleanup note: $sockErr');
      }

      final phone = _phoneCtrl.text.trim().isNotEmpty
          ? _phoneCtrl.text.trim()
          : (_restaurant['phone']?.toString() ?? '');

      // 3. Clear local session data and singletons immediately to guarantee consistent auth state
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', false);
      await prefs.remove('is_logged_in');
      await prefs.remove('user_role');
      await prefs.remove('user_name');
      await prefs.remove('phone_number');
      await prefs.remove('jwt_token');
      await prefs.remove('auth_token');
      await prefs.remove('mock_uid');
      await prefs.remove('selected_vehicle');
      await prefs.remove('saved_active_booking');
      await prefs.remove('restaurant_data');
      await prefs.remove('partner_phone');

      ApiClient.setAuthToken(null);
      FirebaseService.setMockUid(null);

      // 4. Invalidate server session with tight timeout so offline/slow backend never traps the partner
      try {
        await ApiService.logout(
          mobile: phone,
          role: 'Restaurant Partner',
        ).timeout(const Duration(seconds: 2));
      } catch (apiErr) {
        debugPrint('[RestaurantPartnerConsole] ApiService.logout note (non-fatal): $apiErr');
      }

      try {
        await _foodService.logoutPartner(
          restaurantId: _restaurantId,
          phone: phone,
        ).timeout(const Duration(seconds: 2));
      } catch (foodErr) {
        debugPrint('[RestaurantPartnerConsole] FoodService.logoutPartner note (non-fatal): $foodErr');
      }

      if (!mounted) return;

      // 5. Provide clear user feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                'Logged out successfully.',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF0F1E4A),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );

      // 6. Navigate to Login screen and completely clear the root navigation stack
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const LoginScreen(initialRole: 'Restaurant Partner'),
        ),
        (route) => false,
      );
    } catch (e) {
      debugPrint('[RestaurantPartnerConsole] Logout error: $e');
      if (mounted) {
        // Fallback: Ensure local session is cleared regardless of error and redirect
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('is_logged_in', false);
          await prefs.remove('is_logged_in');
          await prefs.remove('user_role');
          await prefs.remove('restaurant_data');
          ApiClient.setAuthToken(null);
          FirebaseService.setMockUid(null);
          Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => const LoginScreen(initialRole: 'Restaurant Partner'),
            ),
            (route) => false,
          );
        } catch (_) {
          setState(() {
            _isLoggingOut = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to logout: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _loadSalesAndPaymentData() async {
    if (_restaurantId.isEmpty) return;
    setState(() => _isLoadingSettlements = true);
    try {
      final paymentDetailsFuture = _foodService.fetchRestaurantPaymentDetails(_restaurantId);
      final settlementSummaryFuture = _foodService.fetchRestaurantSettlementSummary(_restaurantId);
      final settlementsFuture = _foodService.fetchRestaurantSettlements(_restaurantId);
      final salesBreakdownFuture = _foodService.fetchRestaurantSalesBreakdown(_restaurantId);

      final results = await Future.wait([
        paymentDetailsFuture,
        settlementSummaryFuture,
        settlementsFuture,
        salesBreakdownFuture,
      ]);

      if (mounted) {
        setState(() {
          _paymentDetails = results[0] as Map<String, dynamic>?;
          _settlementSummary = results[1] as Map<String, dynamic>?;
          _settlements = results[2] as List<Map<String, dynamic>>;
          _salesBreakdown = results[3] as List<Map<String, dynamic>>;
          _isLoadingSettlements = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingSettlements = false);
    }
  }

  Future<void> _loadOrders() async {
    if (_restaurantId.isEmpty) return;
    setState(() => _isLoadingOrders = true);
    try {
      final orders = await _foodService.fetchPartnerOrders(_restaurantId);
      if (mounted) {
        setState(() {
          _orders = orders;
          _isLoadingOrders = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingOrders = false);
    }
  }

  Future<void> _loadMenu() async {
    if (_restaurantId.isEmpty) return;
    setState(() => _isLoadingMenu = true);
    try {
      final res = await _foodService.fetchRestaurantDetail(_restaurantId);
      if (mounted) {
        final items = (res['menuItems'] as List<dynamic>? ?? []).whereType<MenuItem>().toList();
        setState(() {
          _menuItems = items;
          _isLoadingMenu = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMenu = false);
    }
  }

  Future<void> _toggleOpenStatus(bool value) async {
    setState(() => _isTogglingStatus = true);
    final success = await _foodService.updateRestaurantOpenStatus(_restaurantId, value);
    if (!mounted) return;
    setState(() {
      _isTogglingStatus = false;
      if (success) _isOpen = value;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isOpen ? 'Restaurant is now ONLINE and receiving orders' : 'Restaurant is now OFFLINE (Orders Paused)'),
        backgroundColor: _isOpen ? Colors.green : Colors.orange,
      ),
    );
  }

  Future<void> _handleOrderStatusChange(FoodOrder order, String nextStatus, {String? prepTime, String? reason}) async {
    // Immediately stop ringtone alert for this acknowledged order
    if (['accepted', 'rejected', 'cancelled', 'preparing'].contains(nextStatus)) {
      _acknowledgedOrderIds.add(order.orderId);
      _pendingNewOrders.removeWhere((o) => o.orderId == order.orderId);
      _ringtoneService.stopOrderAlert(orderId: order.orderId);
    }

    final success = await _foodService.updatePartnerOrderStatus(
      order.orderId,
      nextStatus,
      prepTime: prepTime,
      reason: reason,
    );

    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order ${order.orderId} updated to ${nextStatus.toUpperCase()}'),
          backgroundColor: Colors.green,
        ),
      );
      _loadOrders();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update order status'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showAcceptOrderDialog(FoodOrder order) {
    String selectedPrepTime = '25 mins';
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('Accept Order', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Estimated Food Preparation Time:', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B))),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: ['15 mins', '25 mins', '35 mins', '45 mins'].map((time) {
                      final isSel = selectedPrepTime == time;
                      return ChoiceChip(
                        label: Text(time),
                        selected: isSel,
                        onSelected: (val) {
                          if (val) setDlgState(() => selectedPrepTime = time);
                        },
                        selectedColor: const Color(0xFF1E60FF),
                        labelStyle: GoogleFonts.inter(
                          color: isSel ? Colors.white : const Color(0xFF334155),
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  onPressed: () {
                    Navigator.pop(context);
                    _handleOrderStatusChange(order, 'accepted', prepTime: selectedPrepTime);
                  },
                  child: const Text('Confirm & Accept', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showRejectOrderDialog(FoodOrder order) {
    final reasonController = TextEditingController(text: 'Kitchen at full capacity');
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Reject Order', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.red)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Specify reason for rejecting this order:', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B))),
              const SizedBox(height: 10),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                Navigator.pop(context);
                _handleOrderStatusChange(order, 'rejected', reason: reasonController.text.trim());
              },
              child: const Text('Confirm Rejection', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showReceiveReturnDialog(FoodOrder order) {
    final staffCtrl = TextEditingController();
    bool sealIntact = true;
    bool allItemsPresent = true;
    bool isSubmitting = false;
    String error = '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.inventory_2_rounded, color: Color(0xFFDC2626)),
                  const SizedBox(width: 8),
                  Text('Confirm Return Handover', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order #${order.orderId} could not be delivered (${order.returnReason}). Inspect the returned food package before accepting:',
                      style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: sealIntact,
                      title: Text('Food package seal & condition verified', style: GoogleFonts.inter(fontSize: 12.5)),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (v) => setDlgState(() => sealIntact = v ?? false),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: allItemsPresent,
                      title: Text('All ${order.items.length} items present and intact', style: GoogleFonts.inter(fontSize: 12.5)),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (v) => setDlgState(() => allItemsPresent = v ?? false),
                    ),
                    const SizedBox(height: 10),
                    Text('Kitchen Staff Receiver Name:', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF334155))),
                    const SizedBox(height: 4),
                    TextField(
                      controller: staffCtrl,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Ramesh (Chef / Manager)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (error.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(error, style: GoogleFonts.inter(fontSize: 12, color: Colors.red)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (!sealIntact || !allItemsPresent) {
                            setDlgState(() => error = 'Please check both inspection verification checkboxes.');
                            return;
                          }
                          setDlgState(() {
                            isSubmitting = true;
                            error = '';
                          });

                          final res = await _foodService.restaurantReceiveReturn(
                            orderId: order.orderId,
                            restaurantId: _restaurantId,
                            staffName: staffCtrl.text.trim(),
                          );

                          if (!mounted) return;

                          if (res['success'] == true) {
                            if (ctx.mounted) Navigator.pop(ctx);
                            _loadOrders();
                            final otp = res['returnOtp']?.toString() ?? '';
                            if (mounted) {
                              _showReturnOtpDialog(order, otp);
                            }
                          } else {
                            setDlgState(() {
                              isSubmitting = false;
                              error = res['message'] ?? 'Failed to receive return';
                            });
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Confirm Handover & Reveal OTP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showReturnOtpDialog(FoodOrder order, String returnOtp) {
    final displayOtp = returnOtp.isNotEmpty ? returnOtp : (order.returnOtp.isNotEmpty ? order.returnOtp : '----');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 24),
            const SizedBox(width: 8),
            Text('Return Handover Verified', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Share this 4-digit Return Verification OTP with Pilot ${order.deliveryPartnerName.isNotEmpty ? order.deliveryPartnerName : ""} to finalize order return:',
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF10B981), width: 1.5),
              ),
              child: Text(
                displayOtp,
                style: GoogleFonts.robotoMono(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 8, color: const Color(0xFF065F46)),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Once the pilot enters this OTP in their console, this return is officially marked complete.',
              style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF94A3B8)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _callCustomer(FoodOrder order) async {
    await CallMaskingService().callFoodOrder(
      orderId: order.orderId,
      callerRole: 'restaurant',
      targetRole: 'customer',
      contactName: order.customerName.isNotEmpty ? order.customerName : 'Customer',
      context: context,
    );
  }

  Future<void> _callPilot(FoodOrder order) async {
    if (order.deliveryPartnerId.isEmpty && order.deliveryPartnerPhone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Delivery pilot has not been assigned to this order yet.'), backgroundColor: Color(0xFFDC2626)),
        );
      }
      return;
    }

    await CallMaskingService().callFoodOrder(
      orderId: order.orderId,
      callerRole: 'restaurant',
      targetRole: 'pilot',
      contactName: order.deliveryPartnerName.isNotEmpty ? order.deliveryPartnerName : 'StayDriv Pilot',
      context: context,
    );
  }

  // ---------------------------------------------------------------------------
  // PRICE MANAGEMENT HANDLERS (Picture 2 reference)
  // ---------------------------------------------------------------------------

  Future<void> _adjustItemPrice(MenuItem item, double delta) async {
    final oldPrice = item.price;
    final newPrice = (oldPrice + delta).clamp(0.0, 99999.0);
    setState(() {
      item.price = newPrice;
    });

    final success = await _foodService.updateMenuItemPrice(_restaurantId, item.itemId, priceDelta: delta);
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${item.name} price updated to ₹${newPrice.toStringAsFixed(0)}'),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF1E60FF),
        ),
      );
    } else {
      setState(() {
        item.price = oldPrice;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update price on server'), backgroundColor: Colors.red),
      );
    }
  }

  void _showManualPriceDialog(MenuItem item) {
    final ctrl = TextEditingController(text: item.price.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Update Price: ${item.name}', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter new item price in ₹:', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B))),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: const InputDecoration(
                prefixText: '₹ ',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E60FF)),
            onPressed: () async {
              final newP = double.tryParse(ctrl.text.trim());
              if (newP == null || newP < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid non-negative price'), backgroundColor: Colors.red),
                );
                return;
              }
              Navigator.pop(ctx);
              setState(() => item.price = newP);
              final ok = await _foodService.updateMenuItemPrice(_restaurantId, item.itemId, newPrice: newP);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ok ? '${item.name} saved at ₹${newP.toStringAsFixed(0)}' : 'Failed to save price'),
                  backgroundColor: ok ? Colors.green : Colors.red,
                ),
              );
            },
            child: const Text('Save Price', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _adjustBulkPrices(double delta) async {
    final catLabel = _selectedCategory == 'All' ? 'all menu items' : 'items in "$_selectedCategory"';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Confirm Bulk Price Adjustment', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(
          'Apply ${delta > 0 ? "+₹" : "-₹"}${delta.abs().toStringAsFixed(0)} across $catLabel?',
          style: GoogleFonts.inter(fontSize: 14),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: delta > 0 ? Colors.green : Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apply Adjustment', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      for (final item in _filteredMenuItems) {
        item.price = (item.price + delta).clamp(0.0, 99999.0);
      }
    });

    final success = await _foodService.adjustBulkPrices(
      _restaurantId,
      priceDelta: delta,
      category: _selectedCategory,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Bulk price adjustment applied successfully!' : 'Failed to apply bulk adjustment'),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
    _loadMenuSilently();
  }

  Future<void> _adjustBulkPricesPercent(double percentDelta) async {
    final catLabel = _selectedCategory == 'All' ? 'all menu items' : 'items in "$_selectedCategory"';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Confirm Bulk Price Adjustment', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(
          'Apply ${percentDelta > 0 ? "+" : ""}${percentDelta.toStringAsFixed(0)}% across $catLabel?',
          style: GoogleFonts.inter(fontSize: 14),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: percentDelta > 0 ? Colors.green : Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apply Adjustment', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      for (final item in _filteredMenuItems) {
        item.price = (item.price * (1 + percentDelta / 100)).clamp(0.0, 99999.0).roundToDouble();
      }
    });

    final success = await _foodService.adjustBulkPricesPercent(
      _restaurantId,
      percentDelta: percentDelta,
      category: _selectedCategory,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Bulk price adjustment applied successfully!' : 'Failed to apply bulk adjustment'),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
    _loadMenuSilently();
  }

  Future<void> _confirmDeleteItem(MenuItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline_rounded, color: Colors.red),
            const SizedBox(width: 8),
            Text('Remove Food Item?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.red)),
          ],
        ),
        content: Text(
          'Are you sure you want to remove "${item.name}" from your active restaurant menu? Historical orders and financial records will remain completely intact.',
          style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF334155)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove Item', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final res = await _foodService.deleteMenuItemResult(_restaurantId, item.itemId);
    if (!mounted) return;
    if (res['success'] == true) {
      setState(() {
        _menuItems.removeWhere((i) => i.itemId == item.itemId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message'] ?? 'Food item "${item.name}" removed successfully.'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message'] ?? 'Failed to delete food item'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // ADD & EDIT MENU ITEM DIALOG (Fully Validated with Photo Upload & Discount)
  // ---------------------------------------------------------------------------

  void _showAddOrEditItemDialog([MenuItem? existingItem]) {
    final isEdit = existingItem != null;
    final nameCtrl = TextEditingController(text: existingItem?.name ?? '');
    final priceCtrl = TextEditingController(text: existingItem != null ? existingItem.price.toStringAsFixed(0) : '');
    final discountCtrl = TextEditingController(
      text: (existingItem != null && existingItem.discountPrice > 0) ? existingItem.discountPrice.toStringAsFixed(0) : '',
    );
    final catCtrl = TextEditingController(
      text: existingItem?.category ?? (_selectedCategory != 'All' ? _selectedCategory : 'Biryani'),
    );
    final descCtrl = TextEditingController(text: existingItem?.description ?? '');
    final prepTimeCtrl = TextEditingController(text: existingItem?.prepTime ?? '20 mins');
    bool isVeg = existingItem?.isVeg ?? false;
    bool isAvailable = existingItem?.isAvailable ?? true;
    String itemImageUrl = existingItem?.imageUrl ?? '';
    bool isUploadingImage = false;
    bool isSaving = false;
    String? errorMessage;

    final commonCategories = [
      'Biryani',
      'Starters',
      'Meals',
      'Snacks',
      'Beverages',
      'Desserts',
      'Pizza',
      'Chinese',
      'South Indian',
      'North Indian',
    ];

    final commonPrepTimes = ['10 mins', '15 mins', '20 mins', '25 mins', '30 mins', '45 mins'];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 16, 8),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              title: Row(
                children: [
                  Icon(
                    isEdit ? Icons.edit_note_rounded : Icons.add_circle_outline_rounded,
                    color: const Color(0xFF1E60FF),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isEdit ? 'Edit Food Item' : 'Add New Food Item',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17, color: const Color(0xFF0F1E4A)),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                    onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, size: 16, color: Colors.red),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  errorMessage!,
                                  style: GoogleFonts.inter(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Photo Upload & Preview
                      Center(
                        child: Column(
                          children: [
                            Stack(
                              children: [
                                Container(
                                  width: 140,
                                  height: 95,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFCBD5E1)),
                                    image: itemImageUrl.isNotEmpty
                                        ? DecorationImage(
                                            image: NetworkImage(itemImageUrl),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  child: itemImageUrl.isEmpty
                                      ? const Center(
                                          child: Icon(Icons.fastfood_rounded, size: 36, color: Color(0xFF94A3B8)),
                                        )
                                      : null,
                                ),
                                Positioned(
                                  top: 6,
                                  left: 6,
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: isVeg ? Colors.green : Colors.red, width: 1.5),
                                    ),
                                    child: Center(
                                      child: Icon(Icons.circle, size: 8, color: isVeg ? Colors.green : Colors.red),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            isUploadingImage
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextButton.icon(
                                        onPressed: () async {
                                          try {
                                            final result = await FilePicker.platform.pickFiles(
                                              type: FileType.image,
                                              withData: true,
                                            );
                                            if (result != null && result.files.isNotEmpty) {
                                              final file = result.files.first;
                                              if (file.bytes != null) {
                                                setDlgState(() => isUploadingImage = true);
                                                final ext = file.extension?.toLowerCase() ?? 'jpg';
                                                final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
                                                final base64String = 'data:$mime;base64,${base64Encode(file.bytes!)}';
                                                final uploadedUrl = await _foodService.uploadImage(
                                                  base64Data: base64String,
                                                  fileName: file.name,
                                                  type: 'food',
                                                );
                                                setDlgState(() {
                                                  isUploadingImage = false;
                                                  if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
                                                    itemImageUrl = uploadedUrl;
                                                  }
                                                });
                                              }
                                            }
                                          } catch (e) {
                                            setDlgState(() => isUploadingImage = false);
                                            debugPrint('[Upload Image Error]: $e');
                                          }
                                        },
                                        icon: const Icon(Icons.upload_file_rounded, size: 16),
                                        label: Text(
                                          itemImageUrl.isEmpty ? 'Upload Photo' : 'Change Photo',
                                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                  ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Food Item Name
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Food Item Name *',
                          hintText: 'e.g. Special Hyderabadi Dum Biryani',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Category Selector & Text Field
                      TextField(
                        controller: catCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Food Category *',
                          hintText: 'e.g. Biryani, Starters, Meals',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Quick Category Chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: commonCategories.map((c) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 6.0),
                              child: ActionChip(
                                label: Text(c, style: const TextStyle(fontSize: 11)),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: catCtrl.text == c ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                                side: BorderSide(color: catCtrl.text == c ? const Color(0xFF1E60FF) : const Color(0xFFE2E8F0)),
                                onPressed: () {
                                  setDlgState(() => catCtrl.text = c);
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Price & Discount Price in ₹
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: priceCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Price in ₹ *',
                                prefixText: '₹ ',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: discountCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Discount Price (₹)',
                                hintText: 'Optional',
                                prefixText: '₹ ',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Preparation Time
                      TextField(
                        controller: prepTimeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Preparation Time *',
                          hintText: 'e.g. 20 mins',
                          prefixIcon: Icon(Icons.timer_outlined, size: 18),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: commonPrepTimes.map((t) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 6.0),
                              child: ActionChip(
                                label: Text(t, style: const TextStyle(fontSize: 11)),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: prepTimeCtrl.text == t ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                                side: BorderSide(color: prepTimeCtrl.text == t ? const Color(0xFF1E60FF) : const Color(0xFFE2E8F0)),
                                onPressed: () {
                                  setDlgState(() => prepTimeCtrl.text = t);
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Description
                      TextField(
                        controller: descCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Food Description',
                          hintText: 'Ingredients, spice level, portion size...',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Veg / Non-Veg Toggle
                      SwitchListTile(
                        title: Text(
                          isVeg ? 'Vegetarian (Pure Veg 🟢)' : 'Non-Vegetarian (🔴)',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        secondary: Icon(Icons.circle, size: 16, color: isVeg ? Colors.green : Colors.red),
                        value: isVeg,
                        onChanged: (v) => setDlgState(() => isVeg = v),
                        activeColor: Colors.green,
                        contentPadding: EdgeInsets.zero,
                      ),

                      // Availability Toggle
                      SwitchListTile(
                        title: Text(
                          isAvailable ? 'In Stock (Available for ordering)' : 'Out of Stock (Hidden from ordering)',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        secondary: Icon(
                          isAvailable ? Icons.check_circle_outline : Icons.block,
                          size: 16,
                          color: isAvailable ? Colors.green : Colors.red,
                        ),
                        value: isAvailable,
                        onChanged: (v) => setDlgState(() => isAvailable = v),
                        activeColor: Colors.green,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E60FF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  onPressed: isSaving
                      ? null
                      : () async {
                          final name = nameCtrl.text.trim();
                          final price = double.tryParse(priceCtrl.text.trim()) ?? -1;
                          final discount = discountCtrl.text.trim().isNotEmpty
                              ? (double.tryParse(discountCtrl.text.trim()) ?? 0.0)
                              : 0.0;
                          final category = catCtrl.text.trim();
                          final description = descCtrl.text.trim();
                          final prepTime = prepTimeCtrl.text.trim().isNotEmpty ? prepTimeCtrl.text.trim() : '20 mins';

                          if (name.isEmpty) {
                            setDlgState(() => errorMessage = 'Please enter food item name.');
                            return;
                          }
                          if (price <= 0) {
                            setDlgState(() => errorMessage = 'Please enter a valid price in ₹ greater than 0.');
                            return;
                          }
                          if (category.isEmpty) {
                            setDlgState(() => errorMessage = 'Please select or enter a food category.');
                            return;
                          }

                          setDlgState(() {
                            isSaving = true;
                            errorMessage = null;
                          });

                          final defaultImg = isVeg
                              ? 'https://images.unsplash.com/photo-1546833999-b9f581a1996d?w=800&auto=format&fit=crop&q=80'
                              : 'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=800&auto=format&fit=crop&q=80';
                          final finalImg = itemImageUrl.isNotEmpty ? itemImageUrl : defaultImg;

                          final payload = {
                            'name': name,
                            'price': price,
                            'discountPrice': discount,
                            'category': category,
                            'description': description,
                            'isVeg': isVeg,
                            'isAvailable': isAvailable,
                            'imageUrl': finalImg,
                            'prepTime': prepTime,
                          };

                          if (isEdit) {
                            final res = await _foodService.updateMenuItemDetailsResult(_restaurantId, existingItem.itemId, payload);
                            if (!mounted) return;
                            if (res['success'] == true) {
                              Navigator.pop(dialogCtx);
                              setState(() {
                                existingItem.name = name;
                                existingItem.price = price;
                                existingItem.discountPrice = discount;
                                existingItem.category = category;
                                existingItem.description = description;
                                existingItem.isVeg = isVeg;
                                existingItem.isAvailable = isAvailable;
                                existingItem.imageUrl = finalImg;
                                existingItem.prepTime = prepTime;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Item "$name" updated successfully!'), backgroundColor: Colors.green),
                              );
                              _loadMenuSilently();
                            } else {
                              setDlgState(() {
                                isSaving = false;
                                errorMessage = res['message'] ?? 'Failed to update item';
                              });
                            }
                          } else {
                            final res = await _foodService.addMenuItemResult(_restaurantId, payload);
                            if (!mounted) return;
                            if (res['success'] == true) {
                              Navigator.pop(dialogCtx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Item "$name" added successfully!'), backgroundColor: Colors.green),
                              );
                              _loadMenu();
                            } else {
                              setDlgState(() {
                                isSaving = false;
                                errorMessage = res['message'] ?? 'Failed to add item';
                              });
                            }
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          isEdit ? 'Save Changes' : 'Save Item',
                          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // VIEW DETAILS DIALOG (Complete food item info, photo, price, prep time)
  // ---------------------------------------------------------------------------

  void _showViewDetailsDialog(MenuItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Food Image (Full Width Banner)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        children: [
                          Image.network(
                            item.imageUrl,
                            width: double.infinity,
                            height: 180,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: double.infinity,
                              height: 180,
                              color: const Color(0xFFF1F5F9),
                              child: const Icon(Icons.fastfood_rounded, size: 48, color: Colors.grey),
                            ),
                          ),
                          Positioned(
                            top: 12,
                            left: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 4)],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.circle, size: 10, color: item.isVeg ? Colors.green : Colors.red),
                                  const SizedBox(width: 5),
                                  Text(
                                    item.isVeg ? 'PURE VEG' : 'NON-VEG',
                                    style: GoogleFonts.robotoMono(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: item.isVeg ? Colors.green : Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            top: 12,
                            right: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: item.isAvailable ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: item.isAvailable ? Colors.green : Colors.red, width: 1.5),
                              ),
                              child: Text(
                                item.isAvailable ? 'IN STOCK' : 'OUT OF STOCK',
                                style: GoogleFonts.robotoMono(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: item.isAvailable ? Colors.green : Colors.red,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Title & Category & Price
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF0F1E4A)),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  item.category,
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF475569)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '₹${item.price.toStringAsFixed(0)}',
                              style: GoogleFonts.robotoMono(fontSize: 22, fontWeight: FontWeight.w800, color: const Color(0xFF0F1E4A)),
                            ),
                            if (item.discountPrice > 0)
                              Text(
                                'Discount: ₹${item.discountPrice.toStringAsFixed(0)}',
                                style: GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green),
                              ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 8),

                    // Meta Details (Prep time & Live In-Stock Toggle)
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              const Icon(Icons.timer_outlined, size: 18, color: Color(0xFF1E60FF)),
                              const SizedBox(width: 6),
                              Text(
                                'Prep Time: ${item.prepTime}',
                                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              item.isAvailable ? 'In Stock' : 'Out of Stock',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: item.isAvailable ? Colors.green : Colors.red,
                              ),
                            ),
                            Switch.adaptive(
                              value: item.isAvailable,
                              activeColor: Colors.green,
                              onChanged: (val) async {
                                setSheetState(() => item.isAvailable = val);
                                setState(() => item.isAvailable = val);
                                await _foodService.updateMenuItemAvailability(_restaurantId, item.itemId, val);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),

                    if (item.description.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('Description', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF0F1E4A))),
                      const SizedBox(height: 4),
                      Text(item.description, style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B), height: 1.4)),
                    ],

                    const SizedBox(height: 24),

                    // Quick Actions Row
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF1E60FF),
                              side: const BorderSide(color: Color(0xFF1E60FF)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () {
                              Navigator.pop(sheetCtx);
                              _showAddOrEditItemDialog(item);
                            },
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: Text('Edit Item', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () {
                              Navigator.pop(sheetCtx);
                              _confirmDeleteItem(item);
                            },
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 18),
                            label: Text('Remove Item', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // MANAGE MENU SHEET (Full Menu Operations & Quick Actions Hub)
  // ---------------------------------------------------------------------------

  void _showManageMenuSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Manage Restaurant Menu', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A))),
                      Text('Partner ID: $_restaurantId', style: GoogleFonts.robotoMono(fontSize: 11, color: const Color(0xFF64748B))),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(sheetCtx),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // + Add Food Item Primary Blue Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E60FF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                  ),
                  onPressed: () {
                    Navigator.pop(sheetCtx);
                    _showAddOrEditItemDialog();
                  },
                  icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 20),
                  label: Text(
                    '+ Add New Food Item',
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Menu Health Summary
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatCol('Total Dishes', '${_menuItems.length}', const Color(0xFF0F1E4A)),
                    _buildStatCol('In Stock', '${_menuItems.where((i) => i.isAvailable).length}', Colors.green),
                    _buildStatCol('Out of Stock', '${_menuItems.where((i) => !i.isAvailable).length}', Colors.red),
                    _buildStatCol('Categories', '${_categories.length - 1}', const Color(0xFF1E60FF)),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Quick Bulk Price Adjustments shortcut
              Text('Bulk Price Adjustments', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildBulkButton('+10% All', const Color(0xFF059669), () {
                    Navigator.pop(sheetCtx);
                    _adjustBulkPricesPercent(10);
                  }),
                  _buildBulkButton('-10% All', Colors.red, () {
                    Navigator.pop(sheetCtx);
                    _adjustBulkPricesPercent(-10);
                  }),
                  _buildBulkButton('+₹20 All', const Color(0xFF1E60FF), () {
                    Navigator.pop(sheetCtx);
                    _adjustBulkPrices(20);
                  }),
                  _buildBulkButton('↺ Refresh', const Color(0xFF64748B), () {
                    Navigator.pop(sheetCtx);
                    _loadMenu();
                  }),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCol(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // STORE PROFILE & INFO HANDLERS
  // ---------------------------------------------------------------------------

  Future<void> _pickAndUploadCoverPhoto() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes != null) {
          setState(() => _isUploadingCover = true);
          final ext = file.extension?.toLowerCase() ?? 'jpg';
          final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
          final base64String = 'data:$mime;base64,${base64Encode(file.bytes!)}';
          final uploadedUrl = await _foodService.uploadImage(
            base64Data: base64String,
            fileName: file.name,
            type: 'restaurant',
          );
          if (mounted) {
            setState(() {
              _isUploadingCover = false;
              if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
                _coverImageUrl = uploadedUrl;
              }
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Cover image uploaded. Tap "Save Store Details" to persist.'), backgroundColor: Colors.green),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isUploadingCover = false);
      debugPrint('[Upload Cover Photo Error]: $e');
    }
  }

  Future<void> _saveStoreProfile() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restaurant Name is required'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSavingProfile = true);
    final updates = {
      'name': name,
      'phone': _phoneCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'openingHours': _hoursCtrl.text.trim(),
      'deliveryTime': _deliveryTimeCtrl.text.trim(),
      'isVegOnly': _isVegOnly,
      'imageUrl': _coverImageUrl,
      'lat': _restaurantLat,
      'lng': _restaurantLng,
      'locationDetails': _restaurantLocationDetails,
    };

    final success = await _foodService.updatePartnerInfo(_restaurantId, updates);
    if (!mounted) return;
    setState(() {
      _isSavingProfile = false;
      if (success) {
        _restaurantName = name;
        _restaurant['name'] = name;
        _restaurant['phone'] = _phoneCtrl.text.trim();
        _restaurant['email'] = _emailCtrl.text.trim();
        _restaurant['address'] = _addressCtrl.text.trim();
        _restaurant['openingHours'] = _hoursCtrl.text.trim();
        _restaurant['deliveryTime'] = _deliveryTimeCtrl.text.trim();
        _restaurant['isVegOnly'] = _isVegOnly;
        _restaurant['imageUrl'] = _coverImageUrl;
        _restaurant['lat'] = _restaurantLat;
        _restaurant['lng'] = _restaurantLng;
        _restaurant['locationDetails'] = _restaurantLocationDetails;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Restaurant details saved successfully!' : 'Failed to update store details'),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  Future<void> _openLocationPinPicker() async {
    final result = await LocationPinPickerDialog.show(
      context,
      initialLat: _restaurantLat != 0.0 ? _restaurantLat : null,
      initialLng: _restaurantLng != 0.0 ? _restaurantLng : null,
      initialAddress: _addressCtrl.text.trim(),
      initialDetails: _restaurantLocationDetails,
      title: 'Set Restaurant Location on Map',
      confirmButtonText: 'Save Exact Restaurant Location',
      detailsHint: 'Restaurant entrance / delivery pickup counter / floor...',
    );

    if (result == null || !mounted) return;

    setState(() {
      _restaurantLat = result.latitude;
      _restaurantLng = result.longitude;
      _addressCtrl.text = result.address;
      _restaurantLocationDetails = result.locationDetails;
      _restaurant['lat'] = result.latitude;
      _restaurant['lng'] = result.longitude;
      _restaurant['address'] = result.address;
      _restaurant['locationDetails'] = result.locationDetails;
    });

    // Authoritatively save to backend immediately
    final success = await _foodService.updatePartnerLocation(
      _restaurantId,
      lat: result.latitude,
      lng: result.longitude,
      address: result.address,
      locationDetails: result.locationDetails,
    );

    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '✅ Exact restaurant location saved! (${result.latitude.toStringAsFixed(4)}, ${result.longitude.toStringAsFixed(4)})',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF16A34A),
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save location to server. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeOrders = _orders.where((o) => [
      'placed',
      'accepted',
      'preparing',
      'ready_for_pickup',
      'pilot_assigned',
      'picked_up',
      'out_for_delivery',
      'delivery_failed_reported',
      'return_to_restaurant',
      'return_arrived_at_restaurant',
      'return_otp_pending',
    ].contains(o.orderStatus)).toList();
    final returnOrdersCount = _orders.where((o) => o.isReturnActive).length;
    final completedOrders = _orders.where((o) => o.orderStatus == 'delivered').toList();
    final double todayGross = completedOrders.fold(0.0, (acc, o) => acc + o.totalAmount);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 0.5,
        titleSpacing: 12,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _restaurantName,
              style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: const Color(0xFF0F1E4A), fontSize: 16),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            Text(
              'Partner ID: $_restaurantId',
              style: GoogleFonts.robotoMono(fontSize: 10.5, color: const Color(0xFF64748B)),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
        actions: [
          // Open / Closed Toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isOpen ? 'ONLINE' : 'OFFLINE',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _isOpen ? Colors.green : Colors.red,
                  ),
                ),
                Transform.scale(
                  scale: 0.85,
                  child: Switch.adaptive(
                    value: _isOpen,
                    activeColor: Colors.green,
                    onChanged: (_isTogglingStatus || _isLoggingOut) ? null : _toggleOpenStatus,
                  ),
                ),
              ],
            ),
          ),
          // Order Alert Sound & Settings Action
          ValueListenableBuilder<bool>(
            valueListenable: _ringtoneService.isRingingNotifier,
            builder: (context, isRinging, _) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                    padding: const EdgeInsets.all(6),
                    icon: Icon(
                      isRinging ? Icons.notifications_active_rounded : Icons.volume_up_rounded,
                      color: isRinging ? const Color(0xFFEF4444) : const Color(0xFF1E60FF),
                      size: 22,
                    ),
                    tooltip: 'Order Alert Settings',
                    onPressed: _isLoggingOut ? null : () => OrderAlertSettingsDialog.show(context),
                  ),
                  if (isRinging)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
            padding: const EdgeInsets.all(6),
            icon: const Icon(Icons.hub_outlined, color: Color(0xFF1E60FF), size: 22),
            tooltip: 'Switch Console (Customer, Pilot, Restaurant, Admin)',
            onPressed: _isLoggingOut
                ? null
                : () => ConsoleSwitcherSheet.show(
                      context,
                      currentRole: 'Restaurant Partner',
                      userPhone: _phoneCtrl.text.trim().isNotEmpty ? _phoneCtrl.text.trim() : null,
                    ),
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
            padding: const EdgeInsets.all(6),
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF1E60FF), size: 22),
            tooltip: 'Refresh',
            onPressed: _isLoggingOut ? null : _loadAllData,
          ),
          _isLoggingOut
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10.0),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                  ),
                )
              : IconButton(
                  key: const Key('restaurant_partner_logout_button'),
                  constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                  padding: const EdgeInsets.all(6),
                  icon: const Icon(Icons.logout_rounded, color: Color(0xFFDC2626), size: 22),
                  tooltip: 'Log Out',
                  onPressed: _isLoggingOut ? null : _handleLogout,
                ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF1E60FF),
          unselectedLabelColor: const Color(0xFF64748B),
          indicatorColor: const Color(0xFF1E60FF),
          indicatorWeight: 3,
          labelStyle: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700),
          tabs: [
            Tab(text: returnOrdersCount > 0 ? 'Orders (${activeOrders.length}) ⚠️$returnOrdersCount' : 'Orders (${activeOrders.length})'),
            Tab(text: 'Menu (${_menuItems.length})'),
            const Tab(text: 'Store Info'),
            const Tab(text: 'Sales'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 1. LIVE ORDERS TAB
          _buildLiveOrdersTab(activeOrders),

          // 2. MENU MANAGEMENT TAB (Picture 2 Reference)
          _buildMenuTab(),

          // 3. STORE PROFILE & INFO TAB
          _buildStoreInfoTab(),

          // 4. SALES & PAYOUTS TAB
          _buildSalesTab(completedOrders, todayGross),
        ],
      ),
      floatingActionButton: _tabController.index == 1
          ? FloatingActionButton.extended(
              onPressed: () => _showAddOrEditItemDialog(),
              backgroundColor: const Color(0xFF1E60FF),
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: Text('Add Item', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white)),
            )
          : null,
    );
  }

  // ---------------------------------------------------------------------------
  // 1. LIVE ORDERS TAB
  // ---------------------------------------------------------------------------

  Widget _buildOrderAlertBanner() {
    final bool isLocationMissing = (_restaurantLat == 0.0 || _restaurantLng == 0.0);

    return Column(
      children: [
        if (isLocationMissing)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_off_rounded, color: Color(0xFFDC2626), size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Exact Restaurant Location Not Set',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFFB91C1C)),
                      ),
                      Text(
                        'Pilots need your exact entrance / pickup pin to navigate directly to your restaurant.',
                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF7F1D1D)),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _openLocationPinPicker,
                  icon: const Icon(Icons.place_rounded, size: 14),
                  label: Text('Set Pin on Map', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: _ringtoneService.isRingingNotifier,
                builder: (context, isRinging, _) {
                  return Icon(
                    isRinging ? Icons.notifications_active_rounded : Icons.volume_up_rounded,
                    color: isRinging ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                    size: 20,
                  );
                },
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ValueListenableBuilder<bool>(
                  valueListenable: _ringtoneService.soundEnabledNotifier,
                  builder: (context, soundEnabled, _) {
                    return ValueListenableBuilder<double>(
                      valueListenable: _ringtoneService.volumeNotifier,
                      builder: (context, volume, _) {
                        return Text(
                          soundEnabled
                              ? 'Order Ringtone: ACTIVE (${(volume * 100).toInt()}% Vol)'
                              : 'Order Ringtone: MUTED',
                          style: GoogleFonts.inter(
                            color: soundEnabled ? Colors.white : const Color(0xFF94A3B8),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF38BDF8),
                  side: const BorderSide(color: Color(0xFF38BDF8), width: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.tune_rounded, size: 14),
                label: Text('Sound Settings', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: () => OrderAlertSettingsDialog.show(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLiveOrdersTab(List<FoodOrder> activeOrders) {
    if (_isLoadingOrders) {
      return const Center(child: CircularProgressIndicator());
    }

    if (activeOrders.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildOrderAlertBanner(),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.room_service_outlined, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'No Active Orders Right Now',
                        style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF0F1E4A)),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'New incoming orders from customers will appear here in real time with high-volume ringtone alerts.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
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

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      itemCount: activeOrders.length + 1,
      itemBuilder: (context, idx) {
        if (idx == 0) return _buildOrderAlertBanner();
        final order = activeOrders[idx - 1];
        return _buildPartnerOrderCard(order);
      },
    );
  }

  Widget _buildPartnerOrderCard(FoodOrder order) {
    Color statusColor = const Color(0xFF3B82F6);
    if (order.orderStatus == 'placed') statusColor = const Color(0xFFF59E0B);
    if (order.orderStatus == 'preparing') statusColor = const Color(0xFF8B5CF6);
    if (order.orderStatus == 'ready_for_pickup') statusColor = const Color(0xFF10B981);
    if (order.orderStatus == 'picked_up' || order.orderStatus == 'out_for_delivery') statusColor = const Color(0xFF2563EB);
    if (order.isReturnActive) statusColor = const Color(0xFFEF4444);
    if (order.orderStatus == 'returned_to_restaurant') statusColor = const Color(0xFF6B7280);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Order ID & Status Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                order.orderId,
                style: GoogleFonts.robotoMono(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF0F1E4A)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withOpacity(0.3)),
                ),
                child: Text(
                  order.orderStatus.replaceAll('_', ' ').toUpperCase(),
                  style: GoogleFonts.robotoMono(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Customer Info with Call Customer button
          Row(
            children: [
              const Icon(Icons.person_outline_rounded, size: 16, color: Color(0xFF64748B)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  order.customerName,
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => _callCustomer(order),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.phone_in_talk_rounded, size: 13, color: Color(0xFF059669)),
                      const SizedBox(width: 5),
                      Text(
                        'Call Customer',
                        style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF059669)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (order.deliveryAddress.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFFEA580C)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Deliver to: ${order.deliveryAddress}',
                    style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],

          const Divider(height: 16),

          // Items List
          ...order.items.map((i) => Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i.item.isVeg ? Colors.green : Colors.red,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${i.quantity}x ${i.item.name}',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                      ),
                    ),
                    Text(
                      '₹${(i.item.price * i.quantity).toStringAsFixed(0)}',
                      style: GoogleFonts.robotoMono(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              )),

          if (order.deliveryInstructions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.note_alt_outlined, size: 14, color: Color(0xFFB45309)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Note: ${order.deliveryInstructions}',
                      style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFFB45309), fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const Divider(height: 20),

          // Bill Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total Bill Amount:', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B))),
              Text(
                '₹${order.totalAmount.toStringAsFixed(0)}',
                style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: const Color(0xFF1E60FF)),
              ),
            ],
          ),

          if (order.restaurantOtp.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.pin_outlined, size: 18, color: Color(0xFFD97706)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pilot Pickup Handover OTP',
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF92400E)),
                        ),
                        Text(
                          'Share with pilot upon pickup verification',
                          style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFFB45309)),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: Text(
                      order.restaurantOtp,
                      style: GoogleFonts.robotoMono(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2, color: const Color(0xFFB45309)),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Action Stepper Buttons
          if (order.orderStatus == 'placed') ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _showRejectOrderDialog(order),
                    child: const Text('Reject Order'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _showAcceptOrderDialog(order),
                    child: const Text('Accept Order', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ] else if (order.orderStatus == 'accepted') ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _handleOrderStatusChange(order, 'preparing'),
                icon: const Icon(Icons.soup_kitchen_rounded, color: Colors.white, size: 18),
                label: const Text('Start Preparing Food', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ] else if (order.orderStatus == 'preparing') ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _handleOrderStatusChange(order, 'ready_for_pickup'),
                icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 18),
                label: const Text('Mark Ready for Pickup', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ] else if (order.orderStatus == 'pilot_assigned') ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.two_wheeler_rounded, color: Color(0xFF2563EB), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pilot Assigned: ${order.deliveryPartnerName.isNotEmpty ? order.deliveryPartnerName : "StayDriv Pilot"}',
                          style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF1E40AF)),
                        ),
                        if (order.deliveryPartnerPhone.isNotEmpty)
                          Text(
                            'Contact: StayDriv Masked Line',
                            style: GoogleFonts.robotoMono(fontSize: 11, color: const Color(0xFF3B82F6)),
                          ),
                      ],
                    ),
                  ),
                  if (order.deliveryPartnerPhone.isNotEmpty)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF2563EB),
                        side: const BorderSide(color: Color(0xFF3B82F6)),
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: () => _callPilot(order),
                      icon: const Icon(Icons.phone_in_talk_rounded, size: 13, color: Color(0xFF2563EB)),
                      label: Text('Call Pilot', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _handleOrderStatusChange(order, 'ready_for_pickup'),
                icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 18),
                label: const Text('Mark Ready for Pickup', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ] else if (order.orderStatus == 'ready_for_pickup') ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.delivery_dining_rounded, color: Color(0xFF059669), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      order.deliveryPartnerName.isNotEmpty 
                          ? 'Ready for Pickup! Pilot ${order.deliveryPartnerName} is arriving.' 
                          : 'Ready! Waiting for Pilot to arrive & pick up.',
                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: const Color(0xFF065F46)),
                    ),
                  ),
                  if (order.deliveryPartnerPhone.isNotEmpty)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF059669),
                        side: const BorderSide(color: Color(0xFF10B981)),
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: () => _callPilot(order),
                      icon: const Icon(Icons.phone_in_talk_rounded, size: 13, color: Color(0xFF059669)),
                      label: Text('Call Pilot', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),
          ] else if (order.orderStatus == 'picked_up' || order.orderStatus == 'out_for_delivery') ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.two_wheeler_rounded, color: Color(0xFF2563EB), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Out for Delivery with Pilot ${order.deliveryPartnerName.isNotEmpty ? order.deliveryPartnerName : "StayDriv Pilot"}',
                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: const Color(0xFF1E40AF)),
                    ),
                  ),
                  if (order.deliveryPartnerPhone.isNotEmpty)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF2563EB),
                        side: const BorderSide(color: Color(0xFF3B82F6)),
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: () => _callPilot(order),
                      icon: const Icon(Icons.phone_in_talk_rounded, size: 13, color: Color(0xFF2563EB)),
                      label: Text('Call Delivery Pilot', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),
          ] else if (order.isReturnActive || order.orderStatus == 'returned_to_restaurant') ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          order.orderStatus == 'returned_to_restaurant' ? 'Return Handover Completed' : 'RETURN ORDER IN TRANSIT',
                          style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF991B1B)),
                        ),
                      ),
                      if (order.deliveryPartnerPhone.isNotEmpty)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFDC2626),
                            side: const BorderSide(color: Color(0xFFEF4444)),
                            backgroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onPressed: () => _callPilot(order),
                          icon: const Icon(Icons.phone_in_talk_rounded, size: 13, color: Color(0xFFDC2626)),
                          label: Text('Call Pilot', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Failed Reason: ${order.returnReason}',
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFB91C1C), fontWeight: FontWeight.w600),
                  ),
                  if (order.returnNotes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: Text(
                        'Notes: ${order.returnNotes}',
                        style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF7F1D1D)),
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    'Pilot: ${order.deliveryPartnerName.isNotEmpty ? order.deliveryPartnerName : "Assigned Pilot"} (Masked Line)',
                    style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF4B5563)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            if (order.returnOtp.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF10B981)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.pin_outlined, color: Color(0xFF059669), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Return Verification OTP', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF065F46))),
                          Text('Share with Pilot upon handover verification', style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF047857))),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF10B981)),
                      ),
                      child: Text(
                        order.returnOtp,
                        style: GoogleFonts.robotoMono(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2, color: const Color(0xFF065F46)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            if (order.orderStatus != 'returned_to_restaurant') ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  onPressed: () => _showReceiveReturnDialog(order),
                  icon: const Icon(Icons.inventory_2_rounded, color: Colors.white, size: 18),
                  label: const Text('Inspect & Confirm Return Handover', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. MENU MANAGEMENT TAB (Matching Picture 2 Reference)
  // ---------------------------------------------------------------------------

  Widget _buildMenuTab() {
    if (_isLoadingMenu) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _filteredMenuItems;
    final inStockCount = _menuItems.where((i) => i.isAvailable).length;
    final outOfStockCount = _menuItems.where((i) => !i.isAvailable).length;

    return Column(
      children: [
        // Top Action Bar: Primary Blue [+ Add Food Item] & [Manage Menu]
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E60FF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 1,
                      ),
                      onPressed: () => _showAddOrEditItemDialog(),
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 18, color: Colors.white),
                      label: Text(
                        '+ Add Food Item',
                        style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF15803D),
                      backgroundColor: const Color(0xFFE8F5E9),
                      side: const BorderSide(color: Color(0xFFA5D6A7)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onPressed: _showManageMenuSheet,
                    icon: const Icon(Icons.menu_rounded, size: 16, color: Color(0xFF15803D)),
                    label: Text(
                      'Manage Menu',
                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Live Inventory Stats Summary Bar
              Row(
                children: [
                  Text(
                    '${_menuItems.length} Dishes on Menu',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF0F1E4A)),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Text(
                      '$inStockCount In Stock',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF059669)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Text(
                      '$outOfStockCount Out of Stock',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFFDC2626)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Search Field
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search dish name or description...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
              ),
              const SizedBox(height: 8),

              // Categories Chips Bar
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _categories.map((cat) {
                    final isSel = _selectedCategory == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: FilterChip(
                        label: Text(cat),
                        selected: isSel,
                        onSelected: (val) => setState(() => _selectedCategory = cat),
                        backgroundColor: const Color(0xFFF1F5F9),
                        selectedColor: const Color(0xFF1E60FF),
                        labelStyle: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isSel ? Colors.white : const Color(0xFF475569),
                        ),
                        showCheckmark: false,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),

        // Quick Bulk Rate Adjustments Bar
        Container(
          margin: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'QUICK BULK RATE ADJUSTMENTS',
                    style: GoogleFonts.robotoMono(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF1E40AF)),
                  ),
                  Text(
                    'Scope: ${_selectedCategory == 'All' ? 'All Dishes' : _selectedCategory}',
                    style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF3B82F6), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildBulkButton('+10% All', const Color(0xFF059669), () => _adjustBulkPricesPercent(10)),
                  _buildBulkButton('-10% All', Colors.red, () => _adjustBulkPricesPercent(-10)),
                  _buildBulkButton('+₹20 All', const Color(0xFF1E60FF), () => _adjustBulkPrices(20)),
                  _buildBulkButton('↺ Reset', const Color(0xFF64748B), () => _loadMenuSilently()),
                ],
              ),
            ],
          ),
        ),

        // Dishes List
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.restaurant_menu_rounded, size: 48, color: Colors.grey),
                      const SizedBox(height: 10),
                      Text('No menu items found', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('Tap "+ Add Food Item" above to create a new dish.', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  itemCount: filtered.length,
                  itemBuilder: (context, idx) {
                    final item = filtered[idx];
                    return _buildPicture2MenuItemCard(item);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildBulkButton(String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Text(
          label,
          style: GoogleFonts.robotoMono(fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
        ),
      ),
    );
  }

  // Food Item Card matching user screenshot layout with dark action block
  Widget _buildPicture2MenuItemCard(MenuItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top section of card: Photo, Diet Dot, Item Name, Price • Category, In Stock Switch
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Dish Photo with diet badge
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        item.imageUrl,
                        width: 62,
                        height: 62,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 62,
                          height: 62,
                          color: const Color(0xFFF1F5F9),
                          child: const Icon(Icons.fastfood, color: Colors.grey, size: 28),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: item.isVeg ? Colors.green : Colors.red, width: 1.5),
                        ),
                        child: Center(
                          child: Icon(Icons.circle, size: 7, color: item.isVeg ? Colors.green : Colors.red),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),

                // Name & Subtitle (Price • Category)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.circle, size: 9, color: item.isVeg ? Colors.green : Colors.red),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              item.name,
                              style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 14.5, color: const Color(0xFF0F1E4A)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            '₹${item.price.toStringAsFixed(0)}',
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF475569)),
                          ),
                          Text(
                            ' • ${item.category}',
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: const Color(0xFF64748B)),
                          ),
                          if (item.discountPrice > 0) ...[
                            const SizedBox(width: 6),
                            Text(
                              '(₹${item.discountPrice.toStringAsFixed(0)})',
                              style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.green),
                            ),
                          ],
                        ],
                      ),
                      if (item.description.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          item.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                        ),
                      ],
                    ],
                  ),
                ),

                // In Stock / Out of Stock status & toggle switch
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      item.isAvailable ? 'In Stock' : 'Out of Stock',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: item.isAvailable ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Switch.adaptive(
                      value: item.isAvailable,
                      activeColor: const Color(0xFF16A34A),
                      onChanged: (val) async {
                        setState(() => item.isAvailable = val);
                        await _foodService.updateMenuItemAvailability(_restaurantId, item.itemId, val);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Bottom highlighted container (Matching Screenshot Red Box)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0F1E4A), // Deep navy
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Button 1: [ ≡ Manage Menu ]
                InkWell(
                  onTap: _showManageMenuSheet,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9), // Pale mint green
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFA5D6A7)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.menu_rounded, size: 16, color: Color(0xFF1B5E20)),
                        const SizedBox(width: 6),
                        Text(
                          'Manage Menu',
                          style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: const Color(0xFF1B5E20)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Row 2: [ 👁 View Details ]  [ ✏ Edit ]
                Row(
                  children: [
                    // View Details Button
                    InkWell(
                      onTap: () => _showViewDetailsDialog(item),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.visibility_outlined, size: 15, color: Color(0xFF0F1E4A)),
                            const SizedBox(width: 6),
                            Text(
                              'View Details',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF0F1E4A)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Edit Button
                    InkWell(
                      onTap: () => _showAddOrEditItemDialog(item),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.edit_outlined, size: 15, color: Color(0xFF1E60FF)),
                            const SizedBox(width: 6),
                            Text(
                              'Edit',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF1E60FF)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Row 3: 🗑 Red Delete Trash Icon & Quick Price Adjustments
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      onTap: () => _confirmDeleteItem(item),
                      borderRadius: BorderRadius.circular(6),
                      child: const Padding(
                        padding: EdgeInsets.all(4.0),
                        child: Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 22),
                      ),
                    ),

                    // Price adjustment shortcuts directly inside card
                    Row(
                      children: [
                        _buildPriceAdjustBtnDark('-10', const Color(0xFFF87171), () => _adjustItemPrice(item, -10)),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => _showManualPriceDialog(item),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF475569)),
                            ),
                            child: Text(
                              '₹${item.price.toStringAsFixed(0)}',
                              style: GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        _buildPriceAdjustBtnDark('+10', const Color(0xFF4ADE80), () => _adjustItemPrice(item, 10)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceAdjustBtnDark(String text, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.6)),
        ),
        child: Text(
          text,
          style: GoogleFonts.robotoMono(fontSize: 10.5, fontWeight: FontWeight.w800, color: color),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. STORE PROFILE & INFO TAB
  // ---------------------------------------------------------------------------

  Widget _buildStoreInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Order Alert Settings Section
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.volume_up_rounded, color: Color(0xFF1E60FF), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order Ringtone & Alerts',
                          style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A)),
                        ),
                        Text(
                          'High-volume alerts for incoming orders',
                          style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ],
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E60FF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => OrderAlertSettingsDialog.show(context),
                  child: Text('Configure', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
          ),

          // Cover Photo Card
          Container(
            width: double.infinity,
            height: 160,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(16),
              image: _coverImageUrl.isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(_coverImageUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: Stack(
              children: [
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black.withOpacity(0.75),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: _isUploadingCover ? null : _pickAndUploadCoverPhoto,
                    icon: _isUploadingCover
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.camera_alt_rounded, size: 16),
                    label: Text(
                      _isUploadingCover ? 'Uploading...' : 'Change Cover Photo',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          Text('Restaurant Information', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A))),
          Text('Edit your restaurant details, contact info, and business hours.', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),

          const SizedBox(height: 14),

          // Restaurant Name
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Restaurant Name *',
              prefixIcon: Icon(Icons.storefront_rounded),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),

          const SizedBox(height: 12),

          // Phone & Email
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Contact Phone *',
                    prefixIcon: Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Contact Email',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Address
          TextField(
            controller: _addressCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Physical Address / Location *',
              prefixIcon: Icon(Icons.location_on_outlined),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),

          const SizedBox(height: 12),

          // Exact Map Location & Delivery Pickup Pin Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (_restaurantLat != 0.0 && _restaurantLng != 0.0)
                  ? const Color(0xFF10B981).withOpacity(0.08)
                  : const Color(0xFFEF4444).withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (_restaurantLat != 0.0 && _restaurantLng != 0.0)
                    ? const Color(0xFF10B981).withOpacity(0.4)
                    : const Color(0xFFEF4444).withOpacity(0.4),
                width: 1.2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      (_restaurantLat != 0.0 && _restaurantLng != 0.0)
                          ? Icons.location_on_rounded
                          : Icons.location_off_rounded,
                      color: (_restaurantLat != 0.0 && _restaurantLng != 0.0)
                          ? const Color(0xFF10B981)
                          : const Color(0xFFEF4444),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Exact Map Location & Delivery Pickup Pin',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: (_restaurantLat != 0.0 && _restaurantLng != 0.0)
                                  ? const Color(0xFF047857)
                                  : const Color(0xFFB91C1C),
                            ),
                          ),
                          Text(
                            (_restaurantLat != 0.0 && _restaurantLng != 0.0)
                                ? 'GPS: ${_restaurantLat.toStringAsFixed(6)}, ${_restaurantLng.toStringAsFixed(6)} (Confirmed)'
                                : '⚠️ Location pin not set! Pilots need this exact pin to navigate to your restaurant.',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: (_restaurantLat != 0.0 && _restaurantLng != 0.0)
                                  ? const Color(0xFF065F46)
                                  : const Color(0xFFDC2626),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_restaurantLocationDetails.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      'Pickup Instructions: $_restaurantLocationDetails',
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.black87),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (_restaurantLat != 0.0 && _restaurantLng != 0.0)
                          ? const Color(0xFF2563EB)
                          : const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _openLocationPinPicker,
                    icon: const Icon(Icons.map_rounded, size: 16),
                    label: Text(
                      (_restaurantLat != 0.0 && _restaurantLng != 0.0)
                          ? 'Edit Restaurant Location on Map'
                          : 'Set Restaurant Location on Map *',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12.5),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Hours & Delivery Time
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _hoursCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Opening Hours',
                    hintText: '07:00 AM - 10:30 PM',
                    prefixIcon: Icon(Icons.schedule_rounded),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _deliveryTimeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Avg Delivery Time',
                    hintText: '25-35 mins',
                    prefixIcon: Icon(Icons.timer_outlined),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Pure Veg Switch
          SwitchListTile(
            tileColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Color(0xFFE2E8F0))),
            title: Text('Pure Vegetarian Restaurant', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
            subtitle: Text('Enable if all dishes served are 100% vegetarian', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey)),
            value: _isVegOnly,
            activeColor: Colors.green,
            onChanged: (v) => setState(() => _isVegOnly = v),
          ),

          const SizedBox(height: 16),

          // Read-only Administrator Controls (Role Security)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shield_outlined, size: 18, color: Color(0xFF475569)),
                    const SizedBox(width: 8),
                    Text('Platform Governance & Permissions', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Platform Commission Rate:', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                    Text('15.0% (Managed by Admin)', style: GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Approval Status:', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                    const Row(
                      children: [
                        Icon(Icons.check_circle, size: 14, color: Colors.green),
                        SizedBox(width: 4),
                        Text('Approved & Active', style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Food Membership Program:', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 14, color: Color(0xFFEA580C)),
                        const SizedBox(width: 4),
                        Text(
                          _restaurant['isMembershipEnrolled'] != false ? 'Enrolled (Verified Partner)' : 'Not Enrolled',
                          style: TextStyle(fontSize: 12, color: _restaurant['isMembershipEnrolled'] != false ? const Color(0xFFEA580C) : Colors.grey, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Member Discount Funding:', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                    Text(
                      _restaurant['membershipFundingType'] == 'restaurant' ? 'Restaurant Funded' : 'StayDriv Funded (Platform)',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF10B981)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Note: Global membership subscription pricing & eligibility are centrally managed by StayDriv Admin.',
                  style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8), fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Save Store Profile Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E60FF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isSavingProfile ? null : _saveStoreProfile,
              icon: _isSavingProfile
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.save_rounded, color: Colors.white),
              label: Text(
                _isSavingProfile ? 'Saving Details...' : 'Save Store Details',
                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. SALES & PAYOUTS TAB
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // 4. SALES, PAYMENT DETAILS & PAYOUT SETTLEMENTS TAB
  // ---------------------------------------------------------------------------

  Widget _buildSalesTab(List<FoodOrder> completedOrders, double todayGross) {
    final summary = _settlementSummary;
    final payment = _paymentDetails;

    // Use authoritative summary if available, fallback to completed orders
    final double totalSales = summary != null
        ? (summary['totalSales'] as num? ?? 0).toDouble()
        : todayGross;
    final int completedCount = summary != null
        ? (summary['completedOrdersCount'] as num? ?? 0).toInt()
        : completedOrders.length;
    final double commRate = summary != null
        ? (summary['commissionRate'] as num? ?? 15.0).toDouble()
        : 15.0;
    final double totalCommission = summary != null
        ? (summary['platformCommissionAmount'] as num? ?? 0).toDouble()
        : (todayGross * 0.15).roundToDouble();
    final double netEarnings = summary != null
        ? (summary['netEarnings'] as num? ?? 0).toDouble()
        : (todayGross - totalCommission);
    final double amountPaid = summary != null
        ? (summary['amountPaid'] as num? ?? 0).toDouble()
        : 0.0;
    final double pendingSettlement = summary != null
        ? (summary['pendingSettlement'] as num? ?? 0).toDouble()
        : netEarnings;
    final double adjustments = summary != null
        ? (summary['totalAdjustments'] as num? ?? 0).toDouble()
        : 0.0;

    final String verificationStatus = payment?['bankVerificationStatus']?.toString() ?? 'unverified';
    final bool hasBank = payment?['hasBankAccount'] == true || (payment?['bankAccountMasked'] != null && payment!['bankAccountMasked'].toString().isNotEmpty);

    return RefreshIndicator(
      onRefresh: _loadSalesAndPaymentData,
      color: const Color(0xFF1E60FF),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // TOP HEADER WITH TITLE & ACTION BUTTON
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sales & Settlements', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A))),
                      const SizedBox(height: 2),
                      Text('Completed orders, commission & bank payouts', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                    ],
                  ),
                ),
                // Clearly visible Payment Details Button
                ElevatedButton.icon(
                  onPressed: () => _showPaymentDetailsDialog(),
                  icon: const Icon(Icons.account_balance_rounded, size: 16, color: Colors.white),
                  label: Text(
                    hasBank ? 'Payment Details / Bank Account' : 'Payment Details / Bank Account Details',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E60FF),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // BENEFICIARY PAYMENT ACCOUNT CARD
            _buildBeneficiaryPaymentCard(payment, hasBank, verificationStatus),
            const SizedBox(height: 18),

            // 6 FINANCIAL METRICS GRID
            Text('Financial Overview', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A))),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _buildMetricCard('Total Gross Sales', '₹${totalSales.toStringAsFixed(0)}', Icons.payments_rounded, const Color(0xFF1E60FF)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricCard('Delivered Orders', '$completedCount Orders', Icons.check_circle_rounded, const Color(0xFF10B981)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _buildMetricCard('Platform Fee (${commRate.toStringAsFixed(0)}%)', '₹${totalCommission.toStringAsFixed(0)}', Icons.percent_rounded, const Color(0xFFF59E0B)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricCard('Net Earnings', '₹${netEarnings.toStringAsFixed(0)}', Icons.account_balance_wallet_rounded, const Color(0xFF0F1E4A)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _buildMetricCard('Amount Paid (Settled)', '₹${amountPaid.toStringAsFixed(0)}', Icons.verified_rounded, const Color(0xFF059669)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricCard('Pending Settlement', '₹${pendingSettlement.toStringAsFixed(0)}', Icons.hourglass_top_rounded, const Color(0xFFDC2626)),
                ),
              ],
            ),
            if (adjustments > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.remove_circle_outline_rounded, size: 16, color: Color(0xFFDC2626)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Authorized Adjustments & Deductions: -₹${adjustments.toStringAsFixed(0)} (Deducted from Net Earnings)',
                        style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF991B1B), fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),

            // PLATFORM SUBSIDY REASSURANCE
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_rounded, size: 16, color: Color(0xFF059669)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'StayDriv Food Membership discounts are subsidized 100% by the platform and do not reduce your food sales payout.',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF065F46), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // SUB-TAB SELECTOR (Settlement History vs Order Sales Breakdown)
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _salesSubTab = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _salesSubTab == 0 ? const Color(0xFF0F1E4A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          'Settlement History (${_settlements.length})',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: _salesSubTab == 0 ? Colors.white : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _salesSubTab = 1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _salesSubTab == 1 ? const Color(0xFF0F1E4A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          'Order-Wise Breakdown (${_salesBreakdown.length})',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: _salesSubTab == 1 ? Colors.white : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // TAB 0: SETTLEMENTS LIST
            if (_salesSubTab == 0) ...[
              if (_settlements.isEmpty)
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.receipt_long_rounded, size: 40, color: Color(0xFFCBD5E1)),
                      const SizedBox(height: 10),
                      Text('No Settlement Transactions Yet', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A))),
                      const SizedBox(height: 4),
                      Text(
                        'Once your completed orders reach settlement processing, bank transfer records and UTR reference details will appear here.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                )
              else
                ..._settlements.map((s) => _buildSettlementCard(s)),
            ]
            // TAB 1: ORDER-WISE SALES BREAKDOWN
            else ...[
              if (_salesBreakdown.isEmpty)
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.lunch_dining_rounded, size: 40, color: Color(0xFFCBD5E1)),
                      const SizedBox(height: 10),
                      Text('No Delivered Orders Found', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A))),
                      const SizedBox(height: 4),
                      Text(
                        'Orders only qualify as completed sales after successful customer delivery and payment confirmation.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                )
              else
                ..._salesBreakdown.map((item) => _buildOrderSalesCard(item)),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // Beneficiary Payment Details Card
  Widget _buildBeneficiaryPaymentCard(Map<String, dynamic>? payment, bool hasBank, String status) {
    Color badgeBg;
    Color badgeColor;
    String badgeText;
    IconData badgeIcon;

    if (status == 'verified') {
      badgeBg = const Color(0xFFDCFCE7);
      badgeColor = const Color(0xFF166534);
      badgeText = 'VERIFIED ACCOUNT';
      badgeIcon = Icons.verified_rounded;
    } else if (status == 'pending_verification') {
      badgeBg = const Color(0xFFFEF3C7);
      badgeColor = const Color(0xFF92400E);
      badgeText = 'UNDER VERIFICATION';
      badgeIcon = Icons.hourglass_top_rounded;
    } else if (status == 'rejected') {
      badgeBg = const Color(0xFFFEE2E2);
      badgeColor = const Color(0xFF991B1B);
      badgeText = 'ACTION REQUIRED';
      badgeIcon = Icons.error_outline_rounded;
    } else {
      badgeBg = const Color(0xFFF1F5F9);
      badgeColor = const Color(0xFF475569);
      badgeText = 'NOT CONFIGURED';
      badgeIcon = Icons.info_outline_rounded;
    }

    if (!hasBank) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(
          children: [
            const Icon(Icons.account_balance_outlined, color: Color(0xFFD97706), size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bank Account Details Required', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF92400E))),
                  const SizedBox(height: 2),
                  Text('Add your verified account where food sales payouts should be credited.', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFB45309))),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _showPaymentDetailsDialog(),
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('Add Now', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    final maskedAcc = payment?['bankAccountMasked']?.toString() ?? '•••• •••• ••••';
    final bankName = payment?['bankName']?.toString() ?? 'Bank';
    final holderName = payment?['accountHolderName']?.toString() ?? 'N/A';
    final ifsc = payment?['bankIfsc']?.toString() ?? 'N/A';
    final upi = payment?['upiId']?.toString() ?? '';
    final accType = payment?['accountType']?.toString() ?? 'Current';
    final mobile = payment?['registeredMobile']?.toString() ?? '';
    final pref = payment?['paymentPreference']?.toString() == 'upi' ? 'UPI Payout' : 'Bank Transfer';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
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
                    decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.account_balance_rounded, size: 18, color: Color(0xFF1E60FF)),
                  ),
                  const SizedBox(width: 10),
                  Text('BENEFICIARY ACCOUNT', style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F1E4A), letterSpacing: 0.5)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(6)),
                child: Row(
                  children: [
                    Icon(badgeIcon, size: 12, color: badgeColor),
                    const SizedBox(width: 4),
                    Text(badgeText, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: badgeColor)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Details Grid
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bank Name & Type', style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF94A3B8))),
                    const SizedBox(height: 2),
                    Text('$bankName ($accType)', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: const Color(0xFF0F1E4A))),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Account Number', style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF94A3B8))),
                    const SizedBox(height: 2),
                    Text(maskedAcc, style: GoogleFonts.robotoMono(fontSize: 12.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F1E4A))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Account Holder', style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF94A3B8))),
                    const SizedBox(height: 2),
                    Text(holderName, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF334155))),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('IFSC Code', style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF94A3B8))),
                    const SizedBox(height: 2),
                    Text(ifsc, style: GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF334155))),
                  ],
                ),
              ),
            ],
          ),

          if (upi.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Settlement UPI ID', style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF94A3B8))),
                      const SizedBox(height: 2),
                      Text(upi, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF2563EB))),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Preference', style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF94A3B8))),
                      const SizedBox(height: 2),
                      Text(pref, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF334155))),
                    ],
                  ),
                ),
              ],
            ),
          ],

          if (payment?['bankRejectionReason'] != null && payment!['bankRejectionReason'].toString().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Rejection reason: ${payment['bankRejectionReason']}',
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.red[800], fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 8),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                mobile.isNotEmpty ? 'Registered: +91 $mobile' : 'Authorized Payout Account',
                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
              ),
              TextButton.icon(
                onPressed: () => _showPaymentDetailsDialog(),
                icon: const Icon(Icons.edit_outlined, size: 14, color: Color(0xFF1E60FF)),
                label: Text('Update Account', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFF1E60FF))),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Format timestamp helper
  String _formatDateTime(dynamic dtStr) {
    if (dtStr == null) return 'N/A';
    try {
      final dt = DateTime.parse(dtStr.toString()).toLocal();
      String pad(int n) => n.toString().padLeft(2, '0');
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final monthName = months[dt.month - 1];
      return '${pad(dt.day)} $monthName ${dt.year}, ${pad(hour)}:${pad(dt.minute)} $ampm';
    } catch (_) {
      return dtStr.toString();
    }
  }

  // Copy helper
  void _copyToClipboard(String text, String label) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF0F1E4A),
      ),
    );
  }

  // Settlement Card
  Widget _buildSettlementCard(Map<String, dynamic> s) {
    final status = (s['status']?.toString() ?? 'pending').toLowerCase();
    final netPayable = (s['netPayable'] as num? ?? 0).toDouble();
    final grossSales = (s['grossSales'] as num? ?? 0).toDouble();
    final comm = (s['totalCommission'] as num? ?? 0).toDouble();
    final ordersCount = s['ordersCount'] ?? (s['orderIds'] as List?)?.length ?? 0;
    final utr = s['payoutReference']?.toString() ?? '';
    final failure = s['failureReason']?.toString() ?? '';
    final createdAt = s['settledAt'] ?? s['createdAt'];

    Color statusBg;
    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (status == 'paid') {
      statusBg = const Color(0xFFDCFCE7);
      statusColor = const Color(0xFF166534);
      statusLabel = 'PAID';
      statusIcon = Icons.check_circle_rounded;
    } else if (status == 'processing') {
      statusBg = const Color(0xFFEFF6FF);
      statusColor = const Color(0xFF1D4ED8);
      statusLabel = 'PROCESSING';
      statusIcon = Icons.sync_rounded;
    } else if (status == 'failed') {
      statusBg = const Color(0xFFFEE2E2);
      statusColor = const Color(0xFF991B1B);
      statusLabel = 'FAILED';
      statusIcon = Icons.error_outline_rounded;
    } else {
      statusBg = const Color(0xFFFEF3C7);
      statusColor = const Color(0xFF92400E);
      statusLabel = 'PENDING';
      statusIcon = Icons.hourglass_top_rounded;
    }

    return InkWell(
      onTap: () => _showSettlementDetailsModal(s),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '#${s['settlementId'] ?? 'SETTLEMENT'}',
                    style: GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(6)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 12, color: statusColor),
                      const SizedBox(width: 4),
                      Text(statusLabel, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Net Paid Amount', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                    const SizedBox(height: 2),
                    Text('₹${netPayable.toStringAsFixed(0)}', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF0F1E4A))),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Gross: ₹${grossSales.toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                    Text('Fee: -₹${comm.toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFF59E0B), fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                Icon(Icons.inventory_2_outlined, size: 13, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text('$ordersCount Completed Orders', style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B))),
                const Spacer(),
                if (createdAt != null)
                  Text(
                    _formatDateTime(createdAt),
                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                  ),
              ],
            ),

            if (utr.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFE2E8F0))),
                child: Row(
                  children: [
                    const Icon(Icons.tag_rounded, size: 13, color: Color(0xFF1E60FF)),
                    const SizedBox(width: 6),
                    Text('Bank UTR: ', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
                    Expanded(
                      child: Text(utr, style: GoogleFonts.robotoMono(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A))),
                    ),
                  ],
                ),
              ),
            ],

            if (failure.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(6)),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 14, color: Colors.red),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Failure reason: $failure. Retained in pending balance for re-processing.',
                        style: GoogleFonts.inter(fontSize: 10.5, color: Colors.red[800], fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'View Settlement Details →',
                  style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: const Color(0xFF1E60FF)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Order-wise Sales Breakdown Card
  Widget _buildOrderSalesCard(Map<String, dynamic> item) {
    final orderId = item['orderId']?.toString() ?? '';
    final custName = item['customerName']?.toString() ?? 'StayDriv Customer';
    final itemsCount = item['itemsCount'] ?? (item['items'] as List?)?.length ?? 1;
    final subtotal = (item['subtotal'] as num? ?? 0).toDouble();
    final pack = (item['packagingFee'] as num? ?? 0).toDouble();
    final gross = (item['grossAmount'] as num? ?? (subtotal + pack)).toDouble();
    final comm = (item['commission'] as num? ?? 0).toDouble();
    final net = (item['netAmount'] as num? ?? 0).toDouble();

    final bool isReturned = item['isReturned'] == true ||
        (item['rawOrderStatus']?.toString().toLowerCase().contains('return') == true) ||
        (item['rawOrderStatus']?.toString().toLowerCase().contains('failed') == true) ||
        (item['orderStatus']?.toString().toLowerCase().contains('return') == true);

    final String settlementStatus = (item['settlementStatus']?.toString() ?? 'pending').toLowerCase();
    final bool isPayable = item['isPayable'] != false && settlementStatus != 'not_payable';
    final bool isSettled = settlementStatus == 'paid' || settlementStatus == 'settled';
    final bool isProcessing = settlementStatus == 'processing';

    final String returnReason = item['returnReason']?.toString() ?? '';

    Color settleBadgeBg;
    Color settleBadgeTextColor;
    String settleBadgeText;

    if (!isPayable) {
      settleBadgeBg = const Color(0xFFFEE2E2);
      settleBadgeTextColor = const Color(0xFFB91C1C);
      settleBadgeText = 'NOT PAYABLE';
    } else if (isSettled) {
      settleBadgeBg = const Color(0xFFDCFCE7);
      settleBadgeTextColor = const Color(0xFF166534);
      settleBadgeText = 'SETTLED';
    } else if (isProcessing) {
      settleBadgeBg = const Color(0xFFEFF6FF);
      settleBadgeTextColor = const Color(0xFF1D4ED8);
      settleBadgeText = 'PROCESSING';
    } else {
      settleBadgeBg = const Color(0xFFFEF3C7);
      settleBadgeTextColor = const Color(0xFF92400E);
      settleBadgeText = 'PENDING SETTLEMENT';
    }

    return InkWell(
      onTap: () => _showOrderSalesDetailsModal(item),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isReturned ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0),
            width: isReturned ? 1.2 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isReturned ? const Color(0xFFFEF2F2) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isReturned ? Icons.assignment_return_rounded : Icons.dinner_dining_rounded,
                    size: 20,
                    color: isReturned ? const Color(0xFFDC2626) : const Color(0xFF1E60FF),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              orderId,
                              style: GoogleFonts.robotoMono(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                                color: const Color(0xFF0F1E4A),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: settleBadgeBg,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              settleBadgeText,
                              style: GoogleFonts.inter(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                color: settleBadgeTextColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$itemsCount items • $custName',
                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      isPayable ? '₹${net.toStringAsFixed(0)}' : '₹0',
                      style: GoogleFonts.robotoMono(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: isPayable ? const Color(0xFF059669) : const Color(0xFF64748B),
                      ),
                    ),
                    Text(
                      'Gross: ₹${gross.toStringAsFixed(0)} | Fee: -₹${comm.toStringAsFixed(0)}',
                      style: GoogleFonts.inter(fontSize: 9.5, color: const Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ],
            ),
            if (isReturned) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFECDD3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.assignment_return_rounded, size: 13, color: Color(0xFFE11D48)),
                    const SizedBox(width: 5),
                    Text(
                      'Returned to Restaurant',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFBE123C),
                      ),
                    ),
                    if (returnReason.isNotEmpty) ...[
                      Expanded(
                        child: Text(
                          ' • $returnReason',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF881337),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ] else
                      const Spacer(),
                    Text(
                      ' Details →',
                      style: GoogleFonts.inter(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFE11D48),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // ORDER SALES DETAILS MODAL (FULL FINANCIAL BREAKDOWN)
  // -------------------------------------------------------------
  void _showOrderSalesDetailsModal(Map<String, dynamic> item) {
    final orderId = item['orderId']?.toString() ?? '';
    final bookingRef = item['bookingReference']?.toString() ?? orderId;
    final custName = item['customerName']?.toString() ?? 'StayDriv Customer';
    final custPhone = item['customerPhone']?.toString() ?? '';
    final orderDate = item['orderDate'] ?? item['deliveredAt'] ?? item['returnedAt'];
    final deliveredAt = item['deliveredAt'];
    final returnedAt = item['returnedAt'];

    final subtotal = (item['subtotal'] as num? ?? 0).toDouble();
    final packagingFee = (item['packagingFee'] as num? ?? 0).toDouble();
    final gross = (item['grossAmount'] as num? ?? (subtotal + packagingFee)).toDouble();
    final commRate = (item['commissionRate'] as num? ?? 15.0).toDouble();
    final comm = (item['commission'] as num? ?? 0).toDouble();
    final deductions = (item['deductions'] as num? ?? 0).toDouble();
    final membershipDiscount = (item['membershipDiscount'] as num? ?? 0).toDouble();
    final net = (item['netAmount'] as num? ?? 0).toDouble();

    final bool isReturned = item['isReturned'] == true ||
        (item['rawOrderStatus']?.toString().toLowerCase().contains('return') == true) ||
        (item['rawOrderStatus']?.toString().toLowerCase().contains('failed') == true) ||
        (item['orderStatus']?.toString().toLowerCase().contains('return') == true);

    final String returnReason = item['returnReason']?.toString() ?? '';
    final String returnNotes = item['returnNotes']?.toString() ?? '';
    final bool returnOtpVerified = item['returnOtpVerified'] == true;

    final String pilotName = item['pilotName']?.toString() ?? '';
    final String pilotId = item['pilotId']?.toString() ?? '';
    final String pilotPhone = item['pilotPhone']?.toString() ?? '';

    final String settlementStatus = (item['settlementStatus']?.toString() ?? 'pending').toLowerCase();
    final bool isPayable = item['isPayable'] != false && settlementStatus != 'not_payable';
    final String payableReason = item['payableReason']?.toString() ?? (isPayable ? 'Order qualified for restaurant payout.' : 'Non-payable under return policy.');

    final String settlementId = item['settlementId']?.toString() ?? '';
    final String payoutRef = item['payoutReference']?.toString() ?? '';
    final settledAt = item['settledAt'];

    final customerPaid = (item['customerTotalPaid'] as num? ?? 0).toDouble();
    final paymentMethod = (item['customerPaymentMethod']?.toString() ?? 'online').toUpperCase();
    final paymentStatus = (item['customerPaymentStatus']?.toString() ?? 'paid').toUpperCase();

    final List<dynamic> itemsList = (item['items'] as List<dynamic>?) ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.88,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Modal Handle & Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order Financial Breakdown',
                          style: GoogleFonts.outfit(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0F1E4A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '#$orderId',
                                style: GoogleFonts.robotoMono(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF64748B),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, size: 14, color: Color(0xFF1E60FF)),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _copyToClipboard(orderId, 'Order ID'),
                              tooltip: 'Copy Order ID',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ORDER STATUS BANNER
                    if (isReturned)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1F2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFECDD3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.assignment_return_rounded, color: Color(0xFFDC2626), size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'RETURNED TO RESTAURANT',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF991B1B),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const Spacer(),
                                if (returnOtpVerified)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDCFCE7),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.verified_rounded, size: 11, color: Color(0xFF166534)),
                                        const SizedBox(width: 3),
                                        Text(
                                          'Return OTP Verified',
                                          style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.bold, color: const Color(0xFF166534)),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (returnReason.isNotEmpty) ...[
                              Text('Return Reason:', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF881337))),
                              const SizedBox(height: 2),
                              Text(returnReason, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF9F1239), fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                            ],
                            if (returnNotes.isNotEmpty) ...[
                              Text('Pilot Notes: $returnNotes', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF9F1239), fontStyle: FontStyle.italic)),
                              const SizedBox(height: 6),
                            ],
                            if (returnedAt != null) ...[
                              Text('Returned at: ${_formatDateTime(returnedAt)}', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF881337))),
                              const SizedBox(height: 6),
                            ],
                            const Divider(height: 12, color: Color(0xFFFECDD3)),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  isPayable ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                  size: 15,
                                  color: isPayable ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    payableReason,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isPayable ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFA7F3D0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'DELIVERED TO CUSTOMER',
                                    style: GoogleFonts.outfit(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF065F46),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    deliveredAt != null ? 'Completed on ${_formatDateTime(deliveredAt)}' : 'Order successfully completed',
                                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF047857)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 18),

                    // ORDER TIMELINE & REFERENCES
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          _buildDetailRow('Booking Reference', bookingRef, isMono: true),
                          const SizedBox(height: 8),
                          _buildDetailRow('Order Placed', _formatDateTime(orderDate)),
                          const SizedBox(height: 8),
                          _buildDetailRow('Customer', custName + (custPhone.isNotEmpty ? ' (+91 $custPhone)' : '')),
                          if (pilotName.isNotEmpty || pilotId.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _buildDetailRow(
                              isReturned ? 'Returned By Pilot' : 'Delivered By Pilot',
                              '$pilotName ${pilotId.isNotEmpty ? "($pilotId)" : ""}${pilotPhone.isNotEmpty ? " • +91 $pilotPhone" : ""}',
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // FOOD ITEMS LIST
                    Text(
                      'Food Items Ordered (${itemsList.length})',
                      style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A)),
                    ),
                    const SizedBox(height: 10),

                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: itemsList.isNotEmpty ? itemsList.length : 1,
                        separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        itemBuilder: (ctx, idx) {
                          if (itemsList.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text('1x Food Order Items', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF334155))),
                            );
                          }
                          final it = itemsList[idx];
                          final name = it['name']?.toString() ?? 'Food Item';
                          final qty = it['quantity'] ?? 1;
                          final price = (it['price'] as num? ?? 0).toDouble();
                          final isVeg = it['isVeg'] == true;
                          final custom = it['customization']?.toString() ?? '';

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Row(
                              children: [
                                Icon(
                                  isVeg ? Icons.eco_rounded : Icons.restaurant_rounded,
                                  size: 15,
                                  color: isVeg ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '$qty x $name',
                                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: const Color(0xFF0F1E4A)),
                                      ),
                                      if (custom.isNotEmpty)
                                        Text(custom, style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B))),
                                    ],
                                  ),
                                ),
                                Text(
                                  '₹${(price * (qty as num)).toStringAsFixed(0)}',
                                  style: GoogleFonts.robotoMono(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 18),

                    // FINANCIAL CALCULATION LEDGER
                    Text(
                      'Financial Settlement Calculation',
                      style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A)),
                    ),
                    const SizedBox(height: 10),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          _buildFinancialRow('Food Items Subtotal', '₹${subtotal.toStringAsFixed(0)}'),
                          const SizedBox(height: 8),
                          _buildFinancialRow('Packaging Charges', '₹${packagingFee.toStringAsFixed(0)}'),
                          const Divider(height: 16, color: Color(0xFFE2E8F0)),
                          _buildFinancialRow(
                            'Original Gross Order Amount',
                            '₹${gross.toStringAsFixed(0)}',
                            isBold: true,
                          ),
                          const SizedBox(height: 8),
                          _buildFinancialRow(
                            'Platform Commission Fee (${commRate.toStringAsFixed(0)}%)',
                            '-₹${comm.toStringAsFixed(0)}',
                            color: const Color(0xFFD97706),
                          ),
                          if (deductions > 0) ...[
                            const SizedBox(height: 8),
                            _buildFinancialRow(
                              'Authorized Deductions',
                              '-₹${deductions.toStringAsFixed(0)}',
                              color: const Color(0xFFDC2626),
                            ),
                          ],
                          if (membershipDiscount > 0) ...[
                            const SizedBox(height: 8),
                            _buildFinancialRow(
                              'StayDriv Membership Discount',
                              '₹${membershipDiscount.toStringAsFixed(0)}',
                              subtitle: '100% Platform Subsidized (₹0 deducted from restaurant)',
                              color: const Color(0xFF059669),
                            ),
                          ],
                          const SizedBox(height: 8),
                          _buildFinancialRow(
                            'Customer Payment',
                            '₹${customerPaid.toStringAsFixed(0)} via $paymentMethod ($paymentStatus)',
                            subtitle: 'Handled via StayDriv Platform Gateway',
                          ),
                          const Divider(height: 20, color: Color(0xFFCBD5E1), thickness: 1.2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Restaurant's Final Payable",
                                    style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A)),
                                  ),
                                  Text(
                                    isPayable ? 'Net eligible earnings' : 'Non-payable under policy',
                                    style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                              Text(
                                isPayable ? '₹${net.toStringAsFixed(0)}' : '₹0',
                                style: GoogleFonts.robotoMono(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: isPayable ? const Color(0xFF059669) : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // SETTLEMENT STATUS BOX
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: settlementStatus == 'paid' || settlementStatus == 'settled'
                            ? const Color(0xFFDCFCE7)
                            : (settlementStatus == 'processing'
                                ? const Color(0xFFEFF6FF)
                                : (settlementStatus == 'not_payable'
                                    ? const Color(0xFFFEE2E2)
                                    : const Color(0xFFFEF3C7))),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                settlementStatus == 'paid' || settlementStatus == 'settled'
                                    ? Icons.check_circle_rounded
                                    : (settlementStatus == 'not_payable'
                                        ? Icons.cancel_rounded
                                        : Icons.hourglass_top_rounded),
                                size: 16,
                                color: settlementStatus == 'paid' || settlementStatus == 'settled'
                                    ? const Color(0xFF166534)
                                    : (settlementStatus == 'not_payable'
                                        ? const Color(0xFF991B1B)
                                        : const Color(0xFF92400E)),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                settlementStatus == 'paid' || settlementStatus == 'settled'
                                    ? 'SETTLEMENT: SETTLED & PAID'
                                    : (settlementStatus == 'processing'
                                        ? 'SETTLEMENT: PROCESSING PAYOUT'
                                        : (settlementStatus == 'not_payable'
                                            ? 'SETTLEMENT: NOT PAYABLE'
                                            : 'SETTLEMENT: PENDING IN BALANCE')),
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: settlementStatus == 'paid' || settlementStatus == 'settled'
                                      ? const Color(0xFF166534)
                                      : (settlementStatus == 'not_payable'
                                          ? const Color(0xFF991B1B)
                                          : const Color(0xFF92400E)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (settlementStatus == 'paid' || settlementStatus == 'settled') ...[
                            if (payoutRef.isNotEmpty)
                              Text('Bank UTR: $payoutRef', style: GoogleFonts.robotoMono(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF166534))),
                            if (settledAt != null)
                              Text('Paid on: ${_formatDateTime(settledAt)}', style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF14532D))),
                            if (settlementId.isNotEmpty)
                              Text('Settlement Batch: $settlementId', style: GoogleFonts.robotoMono(fontSize: 10.5, color: const Color(0xFF14532D))),
                          ] else if (settlementStatus == 'not_payable') ...[
                            Text(
                              'This order was not payable: $payableReason',
                              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF991B1B)),
                            ),
                          ] else ...[
                            Text(
                              'This order earnings (₹${net.toStringAsFixed(0)}) are currently accumulated in your Pending Settlement balance and will be transferred to your verified beneficiary bank account.',
                              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF78350F)),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // SETTLEMENT DETAILS MODAL
  // -------------------------------------------------------------
  void _showSettlementDetailsModal(Map<String, dynamic> s) {
    final settlementId = s['settlementId']?.toString() ?? 'SETTLEMENT';
    final status = (s['status']?.toString() ?? 'pending').toLowerCase();
    final netPayable = (s['netPayable'] as num? ?? 0).toDouble();
    final grossSales = (s['grossSales'] as num? ?? 0).toDouble();
    final comm = (s['totalCommission'] as num? ?? 0).toDouble();
    final adj = (s['totalAdjustments'] as num? ?? 0).toDouble();
    final ordersCount = s['ordersCount'] ?? (s['orderIds'] as List?)?.length ?? 0;
    final List<dynamic> orderIds = (s['orderIds'] as List<dynamic>?) ?? [];
    final utr = s['payoutReference']?.toString() ?? '';
    final failure = s['failureReason']?.toString() ?? '';
    final createdAt = s['settledAt'] ?? s['createdAt'];
    final initiatedAt = s['initiatedAt'] ?? s['createdAt'];
    final Map<String, dynamic>? bank = s['bankDetails'] as Map<String, dynamic>?;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Modal Handle & Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Settlement Transaction Details',
                          style: GoogleFonts.outfit(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0F1E4A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '#$settlementId',
                                style: GoogleFonts.robotoMono(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF64748B),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, size: 14, color: Color(0xFF1E60FF)),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _copyToClipboard(settlementId, 'Settlement ID'),
                              tooltip: 'Copy Settlement ID',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // AMOUNT & STATUS HEADER
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: status == 'paid'
                            ? const Color(0xFFDCFCE7)
                            : (status == 'processing'
                                ? const Color(0xFFEFF6FF)
                                : (status == 'failed'
                                    ? const Color(0xFFFEE2E2)
                                    : const Color(0xFFFEF3C7))),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                status == 'paid'
                                    ? 'SETTLED & PAID'
                                    : (status == 'processing'
                                        ? 'PROCESSING TRANSFER'
                                        : (status == 'failed' ? 'PAYMENT FAILED' : 'PENDING')),
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: status == 'paid'
                                      ? const Color(0xFF166534)
                                      : (status == 'processing'
                                          ? const Color(0xFF1D4ED8)
                                          : (status == 'failed' ? const Color(0xFF991B1B) : const Color(0xFF92400E))),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              if (createdAt != null)
                                Text(
                                  _formatDateTime(createdAt),
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: status == 'paid' ? const Color(0xFF166534) : const Color(0xFF64748B),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '₹${netPayable.toStringAsFixed(0)}',
                            style: GoogleFonts.outfit(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF0F1E4A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Net amount credited to your bank account for $ordersCount orders',
                            style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF334155)),
                          ),
                        ],
                      ),
                    ),

                    if (utr.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.tag_rounded, size: 16, color: Color(0xFF1E60FF)),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Bank UTR / Transaction Reference', style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B))),
                                Text(utr, style: GoogleFonts.robotoMono(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A))),
                              ],
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, size: 16, color: Color(0xFF1E60FF)),
                              onPressed: () => _copyToClipboard(utr, 'Bank UTR'),
                              tooltip: 'Copy UTR',
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (failure.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Settlement Failed Reason', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF991B1B))),
                                  const SizedBox(height: 2),
                                  Text(failure, style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF7F1D1D))),
                                  const SizedBox(height: 4),
                                  Text('Note: Amount has been safely retained in your pending balance.', style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF991B1B), fontStyle: FontStyle.italic)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // BENEFICIARY BANK ACCOUNT INFO
                    Text(
                      'Beneficiary Account Details',
                      style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A)),
                    ),
                    const SizedBox(height: 10),

                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          _buildDetailRow('Account Number', bank?['accountNumberMasked']?.toString() ?? '•••• •••• ••••', isMono: true),
                          const SizedBox(height: 8),
                          _buildDetailRow('Bank Name', bank?['bankName']?.toString() ?? 'N/A'),
                          const SizedBox(height: 8),
                          _buildDetailRow('Account Holder', bank?['accountHolderName']?.toString() ?? 'N/A'),
                          const SizedBox(height: 8),
                          _buildDetailRow('IFSC Code', bank?['ifscCode']?.toString() ?? 'N/A', isMono: true),
                          if (bank?['upiId'] != null && bank!['upiId'].toString().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _buildDetailRow('UPI ID', bank['upiId'].toString()),
                          ],
                          if (initiatedAt != null) ...[
                            const SizedBox(height: 8),
                            _buildDetailRow('Initiated On', _formatDateTime(initiatedAt)),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // FINANCIAL AUDIT
                    Text(
                      'Financial Audit Breakdown',
                      style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A)),
                    ),
                    const SizedBox(height: 10),

                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          _buildFinancialRow('Gross Order Sales', '₹${grossSales.toStringAsFixed(0)}'),
                          const SizedBox(height: 8),
                          _buildFinancialRow('Platform Commission Deducted', '-₹${comm.toStringAsFixed(0)}', color: const Color(0xFFD97706)),
                          if (adj > 0) ...[
                            const SizedBox(height: 8),
                            _buildFinancialRow('Adjustments & Deductions', '-₹${adj.toStringAsFixed(0)}', color: const Color(0xFFDC2626)),
                          ],
                          const Divider(height: 16, color: Color(0xFFE2E8F0)),
                          _buildFinancialRow('Final Net Settlement Paid', '₹${netPayable.toStringAsFixed(0)}', isBold: true, color: const Color(0xFF059669)),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ASSOCIATED ORDERS
                    Text(
                      'Orders Included in Settlement ($ordersCount)',
                      style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A)),
                    ),
                    const SizedBox(height: 10),

                    if (orderIds.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text('No discrete order IDs recorded.', style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B))),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: orderIds.map((oId) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFCBD5E1)),
                              ),
                              child: Text(
                                oId.toString(),
                                style: GoogleFonts.robotoMono(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF0F1E4A)),
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Reusable detail row
  Widget _buildDetailRow(String label, String value, {bool isMono = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B))),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: isMono
                ? GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A))
                : GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF0F1E4A)),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // Reusable financial row
  Widget _buildFinancialRow(String label, String value, {bool isBold = false, Color? color, String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: isBold ? 12.5 : 12,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                  color: isBold ? const Color(0xFF0F1E4A) : const Color(0xFF475569),
                ),
              ),
            ),
            Text(
              value,
              style: GoogleFonts.robotoMono(
                fontSize: isBold ? 14 : 12.5,
                fontWeight: isBold ? FontWeight.w800 : FontWeight.w700,
                color: color ?? (isBold ? const Color(0xFF0F1E4A) : const Color(0xFF1E293B)),
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF059669), fontStyle: FontStyle.italic),
          ),
        ],
      ],
    );
  }

  // -------------------------------------------------------------
  // PAYMENT DETAILS MODAL DIALOG
  // -------------------------------------------------------------
  void _showPaymentDetailsDialog() {
    final formKey = GlobalKey<FormState>();
    final payment = _paymentDetails;

    final holderCtrl = TextEditingController(text: payment?['accountHolderName']?.toString() ?? '');
    final bankCtrl = TextEditingController(text: payment?['bankName']?.toString() ?? '');
    final accCtrl = TextEditingController();
    final confirmAccCtrl = TextEditingController();
    final ifscCtrl = TextEditingController(text: payment?['bankIfsc']?.toString() ?? '');
    final upiCtrl = TextEditingController(text: payment?['upiId']?.toString() ?? '');
    final mobileCtrl = TextEditingController(text: payment?['registeredMobile']?.toString() ?? _restaurant['phone']?.toString() ?? '');
    
    String accType = payment?['accountType']?.toString() == 'Savings' ? 'Savings' : 'Current';
    String paymentPref = payment?['paymentPreference']?.toString() == 'upi' ? 'upi' : 'bank_transfer';
    bool isSubmitting = false;
    String? submitError;

    final hasExistingAcc = payment?['hasBankAccount'] == true || (payment?['bankAccountMasked'] != null && payment!['bankAccountMasked'].toString().isNotEmpty);
    final maskedExisting = payment?['bankAccountMasked']?.toString() ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.90,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Modal Handle & Header
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0)))),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Beneficiary Bank Details', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A))),
                          Text('Account where restaurant sales payouts are credited', style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B))),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),

                // Form body
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (hasExistingAcc)
                            Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.lock_outline_rounded, size: 16, color: Color(0xFF64748B)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Current account on file: $maskedExisting. Leave account fields blank to keep current account number.',
                                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF475569)),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          if (submitError != null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(10)),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline, size: 18, color: Colors.red),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(submitError!, style: GoogleFonts.inter(fontSize: 12, color: Colors.red[800], fontWeight: FontWeight.w600))),
                                ],
                              ),
                            ),

                          // 1. Account Holder Name
                          Text('Account Holder Name *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A))),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: holderCtrl,
                            decoration: _inputDec('Full legal name as per bank records'),
                            validator: (v) => (v == null || v.trim().length < 3) ? 'Minimum 3 characters required' : null,
                          ),
                          const SizedBox(height: 14),

                          // 2. Bank Name & Account Type
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Bank Name *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A))),
                                    const SizedBox(height: 6),
                                    TextFormField(
                                      controller: bankCtrl,
                                      decoration: _inputDec('e.g. HDFC Bank, SBI'),
                                      validator: (v) => (v == null || v.trim().length < 2) ? 'Bank name is required' : null,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Account Type *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A))),
                                    const SizedBox(height: 6),
                                    DropdownButtonFormField<String>(
                                      value: accType,
                                      decoration: _inputDec(''),
                                      items: const [
                                        DropdownMenuItem(value: 'Current', child: Text('Current')),
                                        DropdownMenuItem(value: 'Savings', child: Text('Savings')),
                                      ],
                                      onChanged: (v) {
                                        if (v != null) setModalState(() => accType = v);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // 3. Bank Account Number
                          Text(hasExistingAcc ? 'Bank Account Number (Leave empty to keep existing)' : 'Bank Account Number *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A))),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: accCtrl,
                            keyboardType: TextInputType.number,
                            obscureText: true,
                            decoration: _inputDec(hasExistingAcc ? '•••• •••• $maskedExisting' : 'Enter 9 to 18 digit account number'),
                            validator: (v) {
                              if (!hasExistingAcc && (v == null || v.trim().isEmpty)) return 'Account number is required';
                              if (v != null && v.trim().isNotEmpty) {
                                if (!RegExp(r'^\d{9,18}$').hasMatch(v.trim())) return 'Must be between 9 and 18 digits';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          // 4. Confirm Account Number
                          Text(hasExistingAcc ? 'Confirm Bank Account Number (If changing account)' : 'Confirm Bank Account Number *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A))),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: confirmAccCtrl,
                            keyboardType: TextInputType.number,
                            obscureText: true,
                            decoration: _inputDec('Re-enter account number'),
                            validator: (v) {
                              if (!hasExistingAcc && (v == null || v.trim().isEmpty)) {
                                return 'Confirm bank account number is required';
                              }
                              if (accCtrl.text.isNotEmpty && (v == null || v.trim().isEmpty)) {
                                return 'Please confirm your bank account number';
                              }
                              if (accCtrl.text.isNotEmpty && v != null && v.trim() != accCtrl.text.trim()) {
                                return 'Account numbers do not match';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          // 5. IFSC Code
                          Text('Bank IFSC Code *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A))),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: ifscCtrl,
                            textCapitalization: TextCapitalization.characters,
                            decoration: _inputDec('e.g. HDFC0001234, SBIN0004567'),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'IFSC code is required';
                              if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(v.trim().toUpperCase())) {
                                return 'Invalid IFSC (e.g. HDFC0001234)';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          // 6. Registered Mobile Number
                          Text('Registered Mobile Number (for Payout SMS) *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A))),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: mobileCtrl,
                            keyboardType: TextInputType.phone,
                            decoration: _inputDec('10-digit mobile number'),
                            validator: (v) {
                              final clean = (v ?? '').replaceAll(RegExp(r'\D'), '');
                              if (clean.length != 10) return '10-digit mobile number required';
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          // 7. UPI ID (Optional / Mandatory if UPI preference)
                          Text('Settlement UPI ID ${paymentPref == 'upi' ? '*' : '(Optional)'}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A))),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: upiCtrl,
                            decoration: _inputDec('e.g. restaurant@okhdfcbank, name@upi'),
                            validator: (v) {
                              if (paymentPref == 'upi' && (v == null || v.trim().isEmpty)) {
                                return 'UPI ID is required when preferred payout method is UPI';
                              }
                              if (v != null && v.trim().isNotEmpty) {
                                if (!RegExp(r'^[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z]{2,64}$').hasMatch(v.trim())) {
                                  return 'Invalid UPI ID format (e.g. restaurant@okhdfcbank)';
                                }
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          // 8. Payout Preference
                          Text('Preferred Payout Method *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F1E4A))),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () => setModalState(() => paymentPref = 'bank_transfer'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                                    decoration: BoxDecoration(
                                      color: paymentPref == 'bank_transfer' ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: paymentPref == 'bank_transfer' ? const Color(0xFF1E60FF) : const Color(0xFFE2E8F0), width: 1.5),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          paymentPref == 'bank_transfer' ? Icons.radio_button_checked : Icons.radio_button_off,
                                          size: 16,
                                          color: paymentPref == 'bank_transfer' ? const Color(0xFF1E60FF) : const Color(0xFF94A3B8),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text('Bank Transfer (NEFT/RTGS)', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: const Color(0xFF0F1E4A))),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: InkWell(
                                  onTap: () => setModalState(() => paymentPref = 'upi'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                                    decoration: BoxDecoration(
                                      color: paymentPref == 'upi' ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: paymentPref == 'upi' ? const Color(0xFF1E60FF) : const Color(0xFFE2E8F0), width: 1.5),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          paymentPref == 'upi' ? Icons.radio_button_checked : Icons.radio_button_off,
                                          size: 16,
                                          color: paymentPref == 'upi' ? const Color(0xFF1E60FF) : const Color(0xFF94A3B8),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text('UPI Direct', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: const Color(0xFF0F1E4A))),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // SUBMIT BUTTON
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: isSubmitting
                                  ? null
                                  : () async {
                                      if (!formKey.currentState!.validate()) return;
                                      setModalState(() {
                                        isSubmitting = true;
                                        submitError = null;
                                      });

                                      final res = await _foodService.updateRestaurantPaymentDetails(_restaurantId, {
                                        'accountHolderName': holderCtrl.text.trim(),
                                        'bankName': bankCtrl.text.trim(),
                                        'bankAccount': accCtrl.text.trim(),
                                        'confirmBankAccount': confirmAccCtrl.text.trim(),
                                        'bankIfsc': ifscCtrl.text.trim().toUpperCase(),
                                        'accountType': accType,
                                        'registeredMobile': mobileCtrl.text.replaceAll(RegExp(r'\D'), ''),
                                        'upiId': upiCtrl.text.trim(),
                                        'paymentPreference': paymentPref,
                                        'updatedBy': _restaurantName,
                                      });

                                      if (res['success'] == true) {
                                        if (ctx.mounted) Navigator.pop(ctx);
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(res['message'] ?? 'Payment details updated successfully!'),
                                              backgroundColor: const Color(0xFF16A34A),
                                            ),
                                          );
                                          _loadSalesAndPaymentData();
                                        }
                                      } else {
                                        setModalState(() {
                                          isSubmitting = false;
                                          submitError = res['message'] ?? 'Failed to update payment details';
                                        });
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1E60FF),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 0,
                              ),
                              child: isSubmitting
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : Text(
                                      hasExistingAcc ? 'Save & Update Payment Account' : 'Verify & Link Payment Account',
                                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  InputDecoration _inputDec(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF1E60FF), width: 1.5)),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 10),
          Text(value, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF0F1E4A))),
          const SizedBox(height: 2),
          Text(title, style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B))),
        ],
      ),
    );
  }
}

