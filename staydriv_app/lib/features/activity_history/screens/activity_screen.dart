import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';
import '../../../core/api_client.dart';
import '../../../core/firebase_service.dart';
import '../../../core/network_config.dart';
import '../../ride_selection/screens/ride_selection_screen.dart';
import 'ride_details_screen.dart';

class ActivityScreen extends StatefulWidget {
  final String userRole;
  final double totalEarnings;
  final List<Map<String, dynamic>> completedRides;
  final bool isAdvanceWithdrawn;
  final VoidCallback? onWithdrawAdvance;
  final VoidCallback onGoToHome;
  final Function(double)? onWithdrawMoney;
  
  final String pilotVehicle;
  
  const ActivityScreen({
    super.key,
    required this.userRole,
    required this.totalEarnings,
    required this.completedRides,
    this.isAdvanceWithdrawn = false,
    this.onWithdrawAdvance,
    required this.onGoToHome,
    this.onWithdrawMoney,
    this.pilotVehicle = 'Bike',
  });

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  String _activeTab = 'past'; // past or scheduled
  String _timeFilter = 'Day'; // Day, Week, Month, Year
  String _serviceFilter = 'All'; // All, Rides, Food Deliveries, Parcel Deliveries
  late String _selectedIncentiveVehicle;
  
  double _availableBalance = 0.0;
  double _reservedBalance = 0.0;
  double _withdrawableBalance = 0.0;
  double _pendingSettlement = 0.0;
  List<dynamic> _payoutHistory = [];
  Map<String, dynamic> _pilotBankAccount = {};
  bool _isLoadingWallet = false;
  List<Map<String, dynamic>> _livePastTrips = [];
  bool _isLoadingTrips = false;

  @override
  void initState() {
    super.initState();
    _selectedIncentiveVehicle = widget.pilotVehicle.isNotEmpty ? widget.pilotVehicle : 'Bike';
    _livePastTrips = List<Map<String, dynamic>>.from(widget.completedRides);
    _fetchPastTrips();
    if (widget.userRole == 'Driver') {
      _fetchPilotWallet();
    }
  }

  @override
  void didUpdateWidget(ActivityScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.completedRides != oldWidget.completedRides && widget.completedRides.isNotEmpty) {
      setState(() {
        _livePastTrips = List<Map<String, dynamic>>.from(widget.completedRides);
      });
    }
  }

  String _formatDateTime(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final month = months[dt.month - 1];
    final day = dt.day;
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$month $day, $hour:$min';
  }

  String _resolveServiceType(String vehicle) {
    final v = vehicle.toLowerCase();
    if (v.contains('food')) return 'food';
    if (v.contains('bike') || v.contains('moto') || v.contains('two')) return 'bike';
    if (v.contains('auto') || v.contains('rickshaw')) return 'auto';
    if (v.contains('truck') || v.contains('parcel') || v.contains('cargo')) return 'parcel';
    return 'car';
  }

  String _getVehicleTitle(String vehicle) {
    final v = vehicle.toLowerCase();
    if (v.contains('food')) return 'StayDriv Food Delivery';
    if (v.contains('bike')) return 'StayDriv Bike';
    if (v.contains('auto')) return 'StayDriv Auto';
    if (v.contains('truck') || v.contains('parcel') || v.contains('cargo')) return 'Mini Truck';
    return 'StayDriv Car';
  }

  String _getVehicleImage(String vehicle) {
    final v = vehicle.toLowerCase();
    if (v.contains('food')) return 'assets/images/bike.png';
    if (v.contains('bike')) return 'assets/images/bike.png';
    if (v.contains('auto')) return 'assets/images/auto.png';
    if (v.contains('truck') || v.contains('parcel') || v.contains('cargo')) return 'assets/images/mini_truck.png';
    return 'assets/images/car.png';
  }

  IconData _getVehicleIcon(String vehicle) {
    final v = vehicle.toLowerCase();
    if (v.contains('food')) return Icons.fastfood_rounded;
    if (v.contains('bike')) return Icons.two_wheeler_rounded;
    if (v.contains('auto')) return Icons.electric_rickshaw_rounded;
    if (v.contains('truck') || v.contains('parcel') || v.contains('cargo')) return Icons.airport_shuttle_rounded;
    return Icons.directions_car_rounded;
  }

  Future<void> _fetchPastTrips() async {
    final rawUid = FirebaseService().currentUid ?? '';
    final phoneDigits = rawUid.replaceAll(RegExp(r'[^0-9]'), '');
    final cleanPhone = phoneDigits.length >= 10 ? phoneDigits.substring(phoneDigits.length - 10) : phoneDigits;

    if (rawUid.isEmpty && cleanPhone.isEmpty) return;

    if (mounted) setState(() => _isLoadingTrips = true);

    try {
      final baseUrl = NetworkConfig.backendUrl;
      final queryUid = rawUid.isNotEmpty ? rawUid : cleanPhone;
      final role = widget.userRole == 'Driver' ? 'Pilot' : 'Customer';
      final uri = Uri.parse('$baseUrl/api/user/$queryUid/rides?role=$role&phone=$cleanPhone&allStatuses=true');
      final res = await ApiClient().get(uri, timeout: const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final rawRides = (data['rides'] as List?) ?? (data['bookings'] as List?);
        if (data['success'] == true && rawRides != null) {
          final List rides = rawRides;
          final List<Map<String, dynamic>> formatted = rides.map<Map<String, dynamic>>((r) {
            final ride = Map<String, dynamic>.from(r is Map ? r : {});
            
            // Extract and format real local date (IST)
            DateTime dt = DateTime.now();
            final ts = ride['timestamp'];
            final createdAt = ride['createdAt'];
            if (ts != null && ts is int && ts > 0) {
              dt = DateTime.fromMillisecondsSinceEpoch(ts).toLocal();
            } else if (createdAt != null) {
              try {
                dt = DateTime.parse(createdAt.toString()).toLocal();
              } catch (_) {}
            }
            
            final isFood = (ride['serviceType'] == 'food' ||
                ride['isFoodDelivery'] == true ||
                (ride['vehicle']?.toString().toLowerCase().contains('food') ?? false));
            final vehicle = isFood
                ? 'Food Delivery'
                : (ride['vehicle'] ?? ride['vehicleType'] ?? 'bike').toString();
            
            // For pilots viewing earnings history, ensure food deliveries reflect pilotEarnings
            String displayPrice;
            if (isFood && widget.userRole == 'Driver') {
              final pilotEarn = ride['pilotEarnings'] ??
                  ride['pilotDeliveryEarnings'] ??
                  ride['pilotDeliveryFee'] ??
                  ride['originalDeliveryFee'];
              double pVal = 0.0;
              if (pilotEarn != null) {
                pVal = double.tryParse(pilotEarn.toString().replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
              }
              if (pVal > 0) {
                displayPrice = '₹${pVal.toStringAsFixed(pVal % 1 == 0 ? 0 : 2)}';
              } else {
                final price = ride['price']?.toString() ?? '0.00';
                displayPrice = price.startsWith('₹') ? price : '₹$price';
              }
            } else {
              final price = ride['price']?.toString() ?? '0.00';
              displayPrice = price.startsWith('₹') ? price : '₹$price';
            }
            final pickup = ride['pickup']?.toString() ?? 'Pickup location';
            final drop = ride['drop']?.toString() ?? 'Destination location';
            final route = '$pickup to $drop';

            return {
              ...ride,
              'bookingId': ride['bookingId'] ?? ride['_id'] ?? '',
              'date': _formatDateTime(dt),
              'price': displayPrice,
              'icon': _getVehicleIcon(vehicle),
              'image': _getVehicleImage(vehicle),
              'title': isFood ? 'StayDriv Food Delivery' : _getVehicleTitle(vehicle),
              'route': route,
              'pickup': pickup,
              'drop': drop,
              'serviceType': isFood ? 'food' : _resolveServiceType(vehicle),
              'vehicle': vehicle,
              'status': (ride['status'] ?? 'completed').toString(),
              'timestamp': dt.millisecondsSinceEpoch,
            };
          }).toList();

          if (mounted) {
            setState(() {
              _livePastTrips = formatted;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('[ACTIVITY] Error fetching past trips: $e');
    } finally {
      if (mounted) setState(() => _isLoadingTrips = false);
    }
  }

  Future<void> _fetchPilotWallet() async {
    final rawUid = FirebaseService().currentUid ?? '';
    final phoneDigits = rawUid.replaceAll(RegExp(r'[^0-9]'), '');
    final cleanPhone = phoneDigits.length >= 10 ? phoneDigits.substring(phoneDigits.length - 10) : phoneDigits;
    final queryUid = rawUid.isNotEmpty ? rawUid : (cleanPhone.isNotEmpty ? 'pilot_$cleanPhone' : '');
    if (queryUid.isEmpty) return;

    if (mounted) setState(() => _isLoadingWallet = true);
    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse('$baseUrl/api/pilot/wallet/$queryUid');
      final res = await ApiClient().get(uri);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && mounted) {
          final avail = (data['availableBalance'] as num?)?.toDouble() ?? 0.0;
          final resBal = (data['reservedBalance'] as num?)?.toDouble() ?? 0.0;
          final withAmt = (data['withdrawableAmount'] as num?)?.toDouble() ??
              (avail - resBal).clamp(0.0, double.infinity);
          setState(() {
            _availableBalance = avail;
            _reservedBalance = resBal;
            _withdrawableBalance = withAmt;
            _pendingSettlement = (data['pendingSettlement'] as num?)?.toDouble() ?? 0.0;
            _payoutHistory = (data['withdrawals'] as List<dynamic>?) ?? [];
            _pilotBankAccount = (data['bankAccount'] as Map<String, dynamic>?) ?? {};
          });
        }
      }
    } catch (e) {
      debugPrint('[ACTIVITY WALLET ERROR]: $e');
    } finally {
      if (mounted) setState(() => _isLoadingWallet = false);
    }
  }

  double _getWithdrawableAmount() {
    if (_withdrawableBalance > 0) return _withdrawableBalance;
    if (_availableBalance > 0) return (_availableBalance - _reservedBalance).clamp(0.0, double.infinity);
    return widget.totalEarnings;
  }

  void _showBankDetailsDialog() {
    final formKey = GlobalKey<FormState>();
    final isUpiMode = ValueNotifier<bool>((_pilotBankAccount['upiId'] ?? '').toString().isNotEmpty && (_pilotBankAccount['accountNumber'] ?? '').toString().isEmpty);
    final holderCtrl = TextEditingController(text: _pilotBankAccount['accountHolderName'] ?? '');
    final bankCtrl = TextEditingController(text: _pilotBankAccount['bankName'] ?? '');
    final accCtrl = TextEditingController(text: _pilotBankAccount['accountNumber'] ?? '');
    final confirmAccCtrl = TextEditingController(text: _pilotBankAccount['accountNumber'] ?? '');
    final ifscCtrl = TextEditingController(text: _pilotBankAccount['ifsc'] ?? '');
    final upiCtrl = TextEditingController(text: _pilotBankAccount['upiId'] ?? '');
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.account_balance_rounded, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                Text('Bank & Payout Details', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: ValueListenableBuilder<bool>(
                  valueListenable: isUpiMode,
                  builder: (context, upiOnly, _) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Add your verified bank account or UPI ID for instant 24-hr earnings settlements via RazorpayX.',
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: ChoiceChip(
                                label: const Text('Bank Account'),
                                selected: !upiOnly,
                                onSelected: (val) => isUpiMode.value = false,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ChoiceChip(
                                label: const Text('UPI ID'),
                                selected: upiOnly,
                                onSelected: (val) => isUpiMode.value = true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (!upiOnly) ...[
                          TextFormField(
                            controller: holderCtrl,
                            decoration: const InputDecoration(labelText: 'Account Holder Name', border: OutlineInputBorder()),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter account holder name' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: accCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Bank Account Number', border: OutlineInputBorder()),
                            validator: (v) => (v == null || v.trim().length < 9) ? 'Enter valid account number (9-18 digits)' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: confirmAccCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Confirm Account Number', border: OutlineInputBorder()),
                            validator: (v) => v != accCtrl.text ? 'Account numbers do not match' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: ifscCtrl,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(labelText: 'Bank IFSC Code', hintText: 'e.g. HDFC0000001', border: OutlineInputBorder()),
                            validator: (v) => (v == null || v.trim().length != 11) ? 'Enter valid 11-character IFSC' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: bankCtrl,
                            decoration: const InputDecoration(labelText: 'Bank Name (Optional)', border: OutlineInputBorder()),
                          ),
                        ] else ...[
                          TextFormField(
                            controller: upiCtrl,
                            decoration: const InputDecoration(labelText: 'UPI ID', hintText: 'e.g. pilot@okaxis', border: OutlineInputBorder()),
                            validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid UPI ID (e.g. mobile@upi)' : null,
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                onPressed: isSaving ? null : () async {
                  if (formKey.currentState?.validate() ?? false) {
                    setDialogState(() => isSaving = true);
                    final uid = FirebaseService().currentUid;
                    try {
                      final baseUrl = NetworkConfig.backendUrl;
                      final res = await ApiClient().post(
                        Uri.parse('$baseUrl/api/pilot/bank-account/save'),
                        headers: {'Content-Type': 'application/json'},
                        body: jsonEncode({
                          'uid': uid,
                          'accountNumber': isUpiMode.value ? '' : accCtrl.text.trim(),
                          'confirmAccountNumber': isUpiMode.value ? '' : confirmAccCtrl.text.trim(),
                          'ifsc': isUpiMode.value ? '' : ifscCtrl.text.trim().toUpperCase(),
                          'bankName': isUpiMode.value ? '' : bankCtrl.text.trim(),
                          'accountHolderName': isUpiMode.value ? '' : holderCtrl.text.trim(),
                          'upiId': isUpiMode.value ? upiCtrl.text.trim() : '',
                        }),
                      );
                      if (res.statusCode == 200) {
                        Navigator.pop(ctx);
                        _fetchPilotWallet();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Bank account successfully saved & verified!'), backgroundColor: Colors.green),
                          );
                        }
                      } else {
                        final data = jsonDecode(res.body);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(data['error'] ?? 'Failed to save bank details'), backgroundColor: Colors.red),
                        );
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error saving bank account: $e'), backgroundColor: Colors.red),
                      );
                    } finally {
                      setDialogState(() => isSaving = false);
                    }
                  }
                },
                child: isSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save & Verify', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _switchTab(String tabName) {
    setState(() {
      _activeTab = tabName;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.userRole == 'Driver') {
      return _buildDriverActivityView();
    }
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Activity',
          style: GoogleFonts.hankenGrotesk(
            fontWeight: FontWeight.w700,
            fontSize: 22,
          ),
        ),
        centerTitle: false,
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: Container(
          constraints: BoxConstraints(
            maxWidth: isDesktop ? 600 : double.infinity,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Segmented Tab Selector
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    // Past Trips Tab
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _switchTab('past'),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _activeTab == 'past' ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: _activeTab == 'past'
                                ? const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2))]
                                : null,
                          ),
                          child: Text(
                            'Past Trips',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.robotoMono(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _activeTab == 'past' ? AppTheme.onSurfaceColor : AppTheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Scheduled Tab
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _switchTab('scheduled'),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _activeTab == 'scheduled' ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: _activeTab == 'scheduled'
                                ? const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2))]
                                : null,
                          ),
                          child: Text(
                            'Scheduled',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.robotoMono(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _activeTab == 'scheduled' ? AppTheme.onSurfaceColor : AppTheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Tab Contents
              Expanded(
                child: _activeTab == 'past' ? _buildPastTripsView() : _buildScheduledTripsView(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPastTripsView() {
    final List<Map<String, dynamic>> pastTrips = _livePastTrips.isNotEmpty
        ? _livePastTrips
        : widget.completedRides;

    if (_isLoadingTrips && pastTrips.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppTheme.primaryColor),
            const SizedBox(height: 16),
            Text(
              'Loading past trips...',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppTheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (pastTrips.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchPastTrips,
        color: AppTheme.primaryColor,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.08),
            Center(
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceContainerLow,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.directions_car_outlined,
                  size: 48,
                  color: AppTheme.outlineColor,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No past trips yet',
              textAlign: TextAlign.center,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppTheme.onSurfaceColor,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'When you complete a ride with StayDriv, your journey history, receipts, and details will appear here.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppTheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: ElevatedButton.icon(
                onPressed: widget.onGoToHome,
                icon: const Icon(Icons.navigation_rounded, size: 18, color: Colors.white),
                label: Text(
                  'Book a Ride',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchPastTrips,
      color: AppTheme.primaryColor,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: pastTrips.length,
        itemBuilder: (context, index) {
          final trip = pastTrips[index];
          final status = (trip['status'] as String? ?? 'completed').toLowerCase();
          final isCompleted = status == 'completed';
          final isCancelled = status == 'cancelled';

          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            clipBehavior: Clip.antiAlias,
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppTheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RideDetailsScreen(ride: trip),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date & Fare row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          trip['date'] as String? ?? 'Recent Trip',
                          style: GoogleFonts.robotoMono(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          trip['price'] as String? ?? '₹0.00',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.onSurfaceColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // Info body row
                    Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: trip['image'] != null
                              ? Padding(
                                  padding: const EdgeInsets.all(4.0),
                                  child: Image.asset(
                                    trip['image'] as String,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => Icon(
                                      (trip['icon'] as IconData?) ?? Icons.directions_car_rounded,
                                      color: AppTheme.primaryColor,
                                      size: 28,
                                    ),
                                  ),
                                )
                              : Icon(
                                  (trip['icon'] as IconData?) ?? Icons.directions_car_rounded,
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
                                trip['title'] as String? ?? 'StayDriv Ride',
                                style: GoogleFonts.hankenGrotesk(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.onSurfaceColor,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                trip['route'] as String? ?? 'Trip Route',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppTheme.onSurfaceVariant,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),

                    // Status chip & Rebook trigger
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Status Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isCompleted
                                ? const Color(0xFF10B981).withValues(alpha: 0.12)
                                : (isCancelled ? const Color(0xFFEF4444).withValues(alpha: 0.12) : AppTheme.primaryAccent.withValues(alpha: 0.08)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isCompleted ? Icons.check_circle_rounded : (isCancelled ? Icons.cancel_rounded : Icons.info_outline_rounded),
                                color: isCompleted ? const Color(0xFF10B981) : (isCancelled ? const Color(0xFFEF4444) : AppTheme.primaryColor),
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isCompleted ? 'Completed' : (isCancelled ? 'Cancelled' : status.toUpperCase()),
                                style: GoogleFonts.robotoMono(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isCompleted ? const Color(0xFF10B981) : (isCancelled ? const Color(0xFFEF4444) : AppTheme.primaryColor),
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        // Rebook action
                        OutlinedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => RideSelectionScreen(
                                  serviceType: (trip['serviceType'] as String?) ?? 'bike',
                                ),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            side: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                          child: Text(
                            'Rebook',
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildScheduledTripsView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Abstract illustration representation
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            color: AppTheme.surfaceContainer,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.calendar_today_rounded,
            size: 56,
            color: AppTheme.outlineColor,
          ),
        ),
        const SizedBox(height: 24),
        
        Text(
          'No scheduled trips',
          style: GoogleFonts.hankenGrotesk(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppTheme.onSurfaceColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "You don't have any upcoming rides planned yet.",
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: AppTheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        
        ElevatedButton(
          onPressed: widget.onGoToHome,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: Text(
            'Book a ride',
            style: GoogleFonts.hankenGrotesk(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _getFilteredRides() {
    final now = DateTime.now();
    final sourceRides = _livePastTrips.isNotEmpty ? _livePastTrips : widget.completedRides;
    return sourceRides.where((ride) {
      // 1. Time Filter
      final timestamp = ride['timestamp'] as int? ?? 0;
      final rideDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final diff = now.difference(rideDate).inDays.abs();
      
      bool matchesTime = true;
      if (_timeFilter == 'Day') {
        matchesTime = diff < 1;
      } else if (_timeFilter == 'Week') {
        matchesTime = diff < 7;
      } else if (_timeFilter == 'Month') {
        matchesTime = diff < 30;
      } else {
        matchesTime = diff < 365;
      }
      if (!matchesTime) return false;

      // 2. Service Filter
      if (_serviceFilter != 'All') {
        final sType = (ride['serviceType'] ?? '').toString().toLowerCase();
        final vehicleStr = (ride['vehicle'] ?? '').toString().toLowerCase();
        final isFood = sType == 'food' || (ride['isFoodDelivery'] == true) || vehicleStr.contains('food');
        final isParcel = sType == 'parcel' || vehicleStr.contains('truck') || vehicleStr.contains('parcel');
        final isRide = !isFood && !isParcel;

        if (_serviceFilter == 'Rides' && !isRide) return false;
        if (_serviceFilter == 'Food Deliveries' && !isFood) return false;
        if (_serviceFilter == 'Parcel Deliveries' && !isParcel) return false;
      }

      return true;
    }).toList();
  }

  double _getFilteredEarnings(List<Map<String, dynamic>> filteredRides) {
    double sum = 0;
    for (var ride in filteredRides) {
      if (ride['pilotEarnings'] != null) {
        sum += (double.tryParse(ride['pilotEarnings'].toString()) ?? 0.0);
      } else {
        final priceStr = ride['price'] as String? ?? '0';
        final cleanStr = priceStr.replaceAll(RegExp(r'[^0-9.]'), '');
        final priceVal = double.tryParse(cleanStr) ?? 0.0;
        final sType = (ride['serviceType'] ?? '').toString().toLowerCase();
        if (sType == 'food' || ride['isFoodDelivery'] == true) {
          sum += priceVal;
        } else {
          sum += priceVal * 0.85;
        }
      }
    }
    return sum;
  }

  DateTime get _currentMonday {
    final now = DateTime.now();
    // Monday is 1, Sunday is 7
    final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day, 0, 0, 0);
  }

  DateTime get _currentSunday {
    final monday = _currentMonday;
    return DateTime(monday.year, monday.month, monday.day + 6, 23, 59, 59, 999);
  }

  String get _weekDateLabel {
    final mon = _currentMonday;
    final sun = _currentSunday;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${mon.day} ${months[mon.month - 1]} – ${sun.day} ${months[sun.month - 1]}';
  }

  // Count rides completed by this pilot between Monday 00:00 and Sunday 23:59
  int _getWeeklyCompletedRidesCount(String vehicleCategory) {
    int count = 0;
    final start = _currentMonday;
    final end = _currentSunday;
    final sourceRides = _livePastTrips.isNotEmpty ? _livePastTrips : widget.completedRides;

    for (var ride in sourceRides) {
      final status = (ride['status'] as String? ?? 'completed').toLowerCase();
      if (status != 'completed' && status != 'accepted') continue;

      final ts = ride['timestamp'] as int? ?? 0;
      if (ts == 0) continue;
      final rideDate = DateTime.fromMillisecondsSinceEpoch(ts);

      if (rideDate.isAfter(start.subtract(const Duration(milliseconds: 1))) &&
          rideDate.isBefore(end.add(const Duration(milliseconds: 1)))) {
        final rideVehicle = (ride['vehicle'] as String? ?? '').toLowerCase();
        final cat = vehicleCategory.toLowerCase();
        if (cat == 'bike' && (rideVehicle.contains('bike') || rideVehicle.contains('moto') || rideVehicle.contains('two'))) {
          count++;
        } else if (cat == 'auto' && (rideVehicle.contains('auto') || rideVehicle.contains('rickshaw'))) {
          count++;
        } else if (cat == 'car' && (rideVehicle.contains('car') || rideVehicle.contains('cab') || rideVehicle.contains('taxi') || rideVehicle.contains('sedan'))) {
          count++;
        } else if (rideVehicle.isEmpty || rideVehicle == 'bike') {
          if (cat == 'bike') count++;
        }
      }
    }
    return count;
  }

  // StayDriv Pilot Weekly Ride Incentive Rules (Monday to Sunday)
  // Bike: 30 rides -> ₹750 bonus; 50 rides -> ₹1,300 bonus
  // Auto: 30 rides -> ₹950 bonus; 50 rides -> ₹1,500 bonus
  // Car: 30 rides -> ₹1,200 bonus; 50 rides -> ₹1,800 bonus
  Map<String, dynamic> _getIncentiveRules(String vehicleCategory) {
    switch (vehicleCategory.toLowerCase()) {
      case 'auto':
        return {
          'vehicle': 'Auto',
          'tier1': {'rides': 30, 'bonus': 950},
          'tier2': {'rides': 50, 'bonus': 1500},
        };
      case 'car':
        return {
          'vehicle': 'Car',
          'tier1': {'rides': 30, 'bonus': 1200},
          'tier2': {'rides': 50, 'bonus': 1800},
        };
      case 'bike':
      default:
        return {
          'vehicle': 'Bike',
          'tier1': {'rides': 30, 'bonus': 750},
          'tier2': {'rides': 50, 'bonus': 1300},
        };
    }
  }

  Widget _buildWeeklyIncentiveCard() {
    final rules = _getIncentiveRules(_selectedIncentiveVehicle);
    final tier1 = rules['tier1'] as Map<String, dynamic>;
    final tier2 = rules['tier2'] as Map<String, dynamic>;
    final int tier1Target = tier1['rides'] as int;
    final int tier1Bonus = tier1['bonus'] as int;
    final int tier2Target = tier2['rides'] as int;
    final int tier2Bonus = tier2['bonus'] as int;

    final int completedCount = _getWeeklyCompletedRidesCount(_selectedIncentiveVehicle);
    final bool tier1Achieved = completedCount >= tier1Target;
    final bool tier2Achieved = completedCount >= tier2Target;

    final double progressRatio = (completedCount / tier2Target.toDouble()).clamp(0.0, 1.0);

    String progressMessage;
    Color messageColor = const Color(0xFF38BDF8);
    if (tier2Achieved) {
      progressMessage = '🌟 Maximum weekly incentive of ₹$tier2Bonus achieved & credited!';
      messageColor = const Color(0xFF10B981);
    } else if (tier1Achieved) {
      final remaining = tier2Target - completedCount;
      progressMessage = '🎉 ₹$tier1Bonus Credited! Complete $remaining more rides for ₹$tier2Bonus!';
      messageColor = const Color(0xFFF59E0B);
    } else {
      final remaining = tier1Target - completedCount;
      progressMessage = '$remaining more rides this week to unlock your ₹$tier1Bonus bonus!';
    }

    int currentBonusEarned = 0;
    if (tier2Achieved) {
      currentBonusEarned = tier2Bonus;
    } else if (tier1Achieved) {
      currentBonusEarned = tier1Bonus;
    }

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                    ),
                    child: const Center(
                      child: Icon(Icons.emoji_events_rounded, color: Color(0xFFF59E0B), size: 20),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Weekly Ride Incentive',
                        style: GoogleFonts.hankenGrotesk(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: -0.2,
                        ),
                      ),
                      Text(
                        'Monday to Sunday Offer',
                        style: GoogleFonts.inter(
                          color: const Color(0xFF94A3B8),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF475569)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month_rounded, color: Color(0xFF38BDF8), size: 12),
                    const SizedBox(width: 4),
                    Text(
                      _weekDateLabel,
                      style: GoogleFonts.robotoMono(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Vehicle Type Selector Tabs (Bike, Auto, Car)
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              children: ['Bike', 'Auto', 'Car'].map((veh) {
                final isSelected = _selectedIncentiveVehicle.toLowerCase() == veh.toLowerCase();
                String emoji = veh == 'Bike' ? '🏍️ ' : (veh == 'Auto' ? '🛺 ' : '🚗 ');
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedIncentiveVehicle = veh;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? const LinearGradient(
                                colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
                              )
                            : null,
                        color: isSelected ? null : Colors.transparent,
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                )
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(emoji, style: const TextStyle(fontSize: 13)),
                          Text(
                            veh,
                            style: GoogleFonts.hankenGrotesk(
                              color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 16),

          // Live Progress Bar & Target Counter Box
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'COMPLETED THIS WEEK',
                          style: GoogleFonts.robotoMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF94A3B8),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '$completedCount',
                                style: GoogleFonts.hankenGrotesk(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                              TextSpan(
                                text: ' / $tier2Target rides',
                                style: GoogleFonts.hankenGrotesk(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: currentBonusEarned > 0
                              ? [const Color(0xFF059669), const Color(0xFF10B981)]
                              : [const Color(0xFF1E293B), const Color(0xFF334155)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: currentBonusEarned > 0 ? const Color(0xFF34D399) : const Color(0xFF475569),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            currentBonusEarned > 0 ? 'EARNED BONUS' : 'NEXT BONUS',
                            style: GoogleFonts.robotoMono(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700,
                              color: currentBonusEarned > 0 ? Colors.white70 : const Color(0xFF94A3B8),
                            ),
                          ),
                          Text(
                            currentBonusEarned > 0
                                ? '₹$currentBonusEarned'
                                : (completedCount < tier1Target ? '₹$tier1Bonus' : '₹$tier2Bonus'),
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: currentBonusEarned > 0 ? Colors.white : const Color(0xFFF59E0B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Multi-stop Progress Bar (0 -> 30 -> 50)
                Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    // Background track
                    Container(
                      height: 10,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    // Active Fill
                    FractionallySizedBox(
                      widthFactor: progressRatio,
                      child: Container(
                        height: 10,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF3B82F6), Color(0xFF10B981), Color(0xFFF59E0B)],
                          ),
                          borderRadius: BorderRadius.circular(5),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981).withValues(alpha: 0.5),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Milestone Labels under the bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '0',
                      style: GoogleFonts.robotoMono(color: const Color(0xFF64748B), fontSize: 10),
                    ),
                    Row(
                      children: [
                        Icon(
                          tier1Achieved ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          color: tier1Achieved ? const Color(0xFF10B981) : const Color(0xFF64748B),
                          size: 12,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '30 Rides ($tier1Bonus)',
                          style: GoogleFonts.robotoMono(
                            color: tier1Achieved ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
                            fontSize: 10,
                            fontWeight: tier1Achieved ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Icon(
                          tier2Achieved ? Icons.emoji_events_rounded : Icons.stars_rounded,
                          color: tier2Achieved ? const Color(0xFFF59E0B) : const Color(0xFF64748B),
                          size: 13,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '50 Rides ($tier2Bonus)',
                          style: GoogleFonts.robotoMono(
                            color: tier2Achieved ? const Color(0xFFFBBF24) : const Color(0xFF94A3B8),
                            fontSize: 10,
                            fontWeight: tier2Achieved ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Motivational Progress Callout
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: messageColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: messageColor.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.tips_and_updates_rounded, color: messageColor, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          progressMessage,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: messageColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Two Milestone Target Cards
          Row(
            children: [
              // Tier 1 Card
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: tier1Achieved
                        ? const Color(0xFF10B981).withValues(alpha: 0.12)
                        : const Color(0xFF0F172A).withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: tier1Achieved
                          ? const Color(0xFF10B981).withValues(alpha: 0.5)
                          : const Color(0xFF334155),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'TARGET 1',
                            style: GoogleFonts.robotoMono(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: tier1Achieved
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFF3B82F6).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              tier1Achieved ? '✓ Credited' : '${(tier1Target - completedCount).clamp(0, tier1Target)} left',
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: tier1Achieved ? Colors.white : const Color(0xFF60A5FA),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '30 Rides',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '₹$tier1Bonus Bonus',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Tier 2 Card
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: tier2Achieved
                        ? const Color(0xFFF59E0B).withValues(alpha: 0.14)
                        : const Color(0xFF0F172A).withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: tier2Achieved
                          ? const Color(0xFFF59E0B).withValues(alpha: 0.6)
                          : const Color(0xFF334155),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'TARGET 2',
                            style: GoogleFonts.robotoMono(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: tier2Achieved
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFFF59E0B).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              tier2Achieved ? '✓ Credited' : '${(tier2Target - completedCount).clamp(0, tier2Target)} left',
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: tier2Achieved ? Colors.black : const Color(0xFFFBBF24),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '50 Rides',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '₹$tier2Bonus Bonus',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFFF59E0B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Auto-credit disclaimer footnote
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: Color(0xFFF59E0B), size: 14),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Bonus automatically credited to Instant Cashout upon hitting target each week (Mon – Sun).',
                  style: GoogleFonts.inter(
                    fontSize: 9.5,
                    color: const Color(0xFF94A3B8),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRideHistoryCard(BuildContext context, Map<String, dynamic> ride) {
    final isHeavyTruck = (ride['vehicle'] as String? ?? '').toLowerCase().contains('truck');

    final listTileChild = ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          ride['icon'] as IconData? ?? Icons.directions_car,
          color: AppTheme.primaryColor,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              ride['title'] as String? ?? 'StayDriv Ride',
              style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ),
          if (ride['status'] == 'accepted')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Text(
                'Accepted',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
            )
          else if ((ride['status'] ?? '').toString().toLowerCase().contains('return'))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Text(
                'Returned',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber.shade800,
                ),
              ),
            ),
        ],
      ),
      subtitle: Text(
        ride['route'] as String? ?? '',
        style: GoogleFonts.inter(fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            ride['price'] as String? ?? '',
            style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green),
          ),
          Text(
            ride['date'] as String? ?? '',
            style: GoogleFonts.robotoMono(fontSize: 10, color: AppTheme.onSurfaceVariant),
          ),
        ],
      ),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (isHeavyTruck) {
            _showHeavyTruckRideDetailsBottomSheet(context, ride);
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RideDetailsScreen(
                  ride: ride,
                  isPilotView: true,
                ),
              ),
            );
          }
        },
        child: listTileChild,
      ),
    );
  }

  Widget _buildDriverActivityView() {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 600;
    final filteredRides = _getFilteredRides();
    final earnings = _getFilteredEarnings(filteredRides);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Earnings Dashboard',
          style: GoogleFonts.hankenGrotesk(
            fontWeight: FontWeight.w700,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: Container(
          constraints: BoxConstraints(
            maxWidth: isDesktop ? 600 : double.infinity,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: RefreshIndicator(
            onRefresh: () async {
              await Future.wait([
                _fetchPilotWallet(),
                _fetchPastTrips(),
              ]);
            },
            color: AppTheme.primaryColor,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 8, bottom: 32),
              children: [
              // Time Filter Selector
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: ['Day', 'Week', 'Month', 'Year'].map((filter) {
                    final isSelected = _timeFilter == filter;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _timeFilter = filter;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: isSelected
                                ? const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2))]
                                : null,
                          ),
                          child: Text(
                            filter,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.robotoMono(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isSelected ? AppTheme.primaryColor : AppTheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),

              // Service Filter Selector (All, Rides, Food Deliveries, Parcel Deliveries)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    {'key': 'All', 'label': 'All', 'icon': Icons.all_inclusive_rounded},
                    {'key': 'Rides', 'label': 'Rides', 'icon': Icons.two_wheeler_rounded},
                    {'key': 'Food Deliveries', 'label': 'Food Deliveries', 'icon': Icons.fastfood_rounded},
                    {'key': 'Parcel Deliveries', 'label': 'Parcels', 'icon': Icons.airport_shuttle_rounded},
                  ].map((item) {
                    final isSel = _serviceFilter == item['key'];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        selected: isSel,
                        showCheckmark: false,
                        avatar: Icon(item['icon'] as IconData, size: 16, color: isSel ? Colors.white : AppTheme.primaryColor),
                        label: Text(
                          item['label'] as String,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                            color: isSel ? Colors.white : AppTheme.onSurfaceColor,
                          ),
                        ),
                        backgroundColor: AppTheme.surfaceContainerLow,
                        selectedColor: AppTheme.primaryColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        side: BorderSide(color: isSel ? AppTheme.primaryColor : AppTheme.outlineVariant.withValues(alpha: 0.3)),
                        onSelected: (val) {
                          setState(() {
                            _serviceFilter = item['key'] as String;
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),

              // Earnings overview cards
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.outlineVariant.withValues()),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'EARNINGS',
                            style: GoogleFonts.robotoMono(fontSize: 10, color: AppTheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '₹${earnings.toStringAsFixed(2)}',
                            style: GoogleFonts.hankenGrotesk(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green),
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
                        color: AppTheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.outlineVariant.withValues()),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'RIDES TAKEN',
                            style: GoogleFonts.robotoMono(fontSize: 10, color: AppTheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${filteredRides.length}',
                            style: GoogleFonts.hankenGrotesk(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Weekly Ride Incentive Offer Card (Bike, Auto, Car)
              _buildWeeklyIncentiveCard(),
              const SizedBox(height: 16),



              // Instant Earnings Cashout Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.primaryColor.withValues(alpha: 0.08), AppTheme.primaryAccent.withValues(alpha: 0.04)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF5046E5).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.flash_on,
                        color: Color(0xFF5046E5),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Instant Cashout via Razorpay',
                            style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.onSurfaceColor),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Withdrawable: ₹${_getWithdrawableAmount().toStringAsFixed(2)}',
                            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _getWithdrawableAmount() <= 0 
                          ? null 
                          : () => _showWithdrawDialog(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5046E5),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(
                        'Withdraw',
                        style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Pending Settlement Card (24-Hour Automatic Bank Settlement)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFFDE68A),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD97706).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.schedule_rounded,
                        color: Color(0xFFD97706),
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
                              Text(
                                'Pending Settlement',
                                style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 14.5, color: const Color(0xFF92400E)),
                              ),
                              Text(
                                '₹${_pendingSettlement.toStringAsFixed(2)}',
                                style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF92400E)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Ride earnings automatically transfer to bank after 24-hr settlement window.',
                            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFB45309)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Linked Bank Account Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2))],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.account_balance_rounded, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Payout Destination',
                                style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 14, color: const Color(0xFF0F172A)),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('VERIFIED', style: GoogleFonts.robotoMono(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF16A34A))),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            (_pilotBankAccount['maskedAccountNumber'] as String?)?.isNotEmpty == true
                                ? _pilotBankAccount['maskedAccountNumber']
                                : ((_pilotBankAccount['upiId'] as String?)?.isNotEmpty == true ? _pilotBankAccount['upiId'] : 'pilot@okaxis (Default)'),
                            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _showBankDetailsDialog,
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      child: Text('Change', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryColor)),
                    ),
                  ],
                ),
              ),

              // Bank Payout History Section (if any payouts exist)
              if (_payoutHistory.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'Bank Payout History',
                  style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
                ),
                const SizedBox(height: 10),
                ..._payoutHistory.take(10).map((payout) {
                  final rawStatus = (payout['status'] as String? ?? 'pending_approval').toLowerCase();
                  String displayStatus;
                  Color statusColor;
                  Color statusBg;
                  switch (rawStatus) {
                    case 'completed':
                    case 'processed':
                    case 'paid':
                      displayStatus = 'COMPLETED';
                      statusColor = const Color(0xFF16A34A);
                      statusBg = const Color(0xFFDCFCE7);
                      break;
                    case 'approved':
                      displayStatus = 'APPROVED';
                      statusColor = const Color(0xFF2563EB);
                      statusBg = const Color(0xFFDBEAFE);
                      break;
                    case 'processing':
                      displayStatus = 'PROCESSING';
                      statusColor = const Color(0xFF0284C7);
                      statusBg = const Color(0xFFE0F2FE);
                      break;
                    case 'rejected':
                      displayStatus = 'REJECTED';
                      statusColor = const Color(0xFFDC2626);
                      statusBg = const Color(0xFFFEE2E2);
                      break;
                    case 'failed':
                    case 'reversed':
                      displayStatus = 'FAILED';
                      statusColor = const Color(0xFFDC2626);
                      statusBg = const Color(0xFFFEE2E2);
                      break;
                    case 'cancelled':
                      displayStatus = 'CANCELLED';
                      statusColor = const Color(0xFF64748B);
                      statusBg = const Color(0xFFF1F5F9);
                      break;
                    case 'pending_approval':
                    case 'pending':
                    case 'under_review':
                    default:
                      displayStatus = 'PENDING_APPROVAL';
                      statusColor = const Color(0xFFD97706);
                      statusBg = const Color(0xFFFEF3C7);
                  }

                  final rejectionReason = payout['rejectionReason'] as String?;
                  final utr = payout['utr'] as String?;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
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
                                  decoration: BoxDecoration(color: statusBg, shape: BoxShape.circle),
                                  child: Icon(
                                    displayStatus == 'COMPLETED' ? Icons.check_circle_outline_rounded : (displayStatus == 'REJECTED' || displayStatus == 'FAILED' ? Icons.error_outline_rounded : Icons.history_rounded),
                                    size: 18,
                                    color: statusColor,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '₹${((payout['amount'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                                      style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                    Text(
                                      payout['withdrawalId'] ?? payout['transactionId'] ?? payout['payoutId'] ?? 'Payout Ref',
                                      style: GoogleFonts.robotoMono(fontSize: 10, color: const Color(0xFF94A3B8)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(6)),
                              child: Text(
                                displayStatus,
                                style: GoogleFonts.robotoMono(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                              ),
                            ),
                          ],
                        ),
                        if (rejectionReason != null && rejectionReason.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Reason: $rejectionReason',
                              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFDC2626), fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                        if (utr != null && utr.isNotEmpty && utr != 'Pending settlement') ...[
                          const SizedBox(height: 4),
                          Text(
                            'Bank UTR: $utr',
                            style: GoogleFonts.robotoMono(fontSize: 10, color: const Color(0xFF16A34A), fontWeight: FontWeight.bold),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              ],

              const SizedBox(height: 20),

              Text(
                'Ride & Earnings History',
                style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
              ),
              const SizedBox(height: 10),

              if (filteredRides.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Center(
                    child: Text(
                      'No rides completed in this period.',
                      style: GoogleFonts.inter(color: AppTheme.onSurfaceVariant),
                    ),
                  ),
                )
              else
                ...filteredRides.map((ride) => _buildRideHistoryCard(context, ride)),
            ],
          ),
          ),
        ),
      ),
    );
  }

  void _showWithdrawDialog(BuildContext context) {
    final maxWithdrawable = _getWithdrawableAmount();
    final bool hasVerifiedDestination = (_pilotBankAccount['isVerified'] == true) ||
        ((_pilotBankAccount['maskedAccountNumber'] as String?)?.isNotEmpty == true) ||
        ((_pilotBankAccount['accountNumber'] as String?)?.isNotEmpty == true) ||
        ((_pilotBankAccount['upiId'] as String?)?.isNotEmpty == true);

    final destinationDisplay = (_pilotBankAccount['maskedAccountNumber'] as String?)?.isNotEmpty == true
        ? _pilotBankAccount['maskedAccountNumber']!
        : ((_pilotBankAccount['upiId'] as String?)?.isNotEmpty == true
            ? _pilotBankAccount['upiId']!
            : ((_pilotBankAccount['accountNumber'] as String?)?.isNotEmpty == true
                ? 'Acc ending in ${_pilotBankAccount['accountNumber'].toString().substring(_pilotBankAccount['accountNumber'].toString().length > 4 ? _pilotBankAccount['accountNumber'].toString().length - 4 : 0)}'
                : ''));

    if (!hasVerifiedDestination || destinationDisplay.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Payout Destination Required', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 17)),
              ),
            ],
          ),
          content: Text(
            'Before requesting a withdrawal, you must link and verify your destination bank account or UPI ID.',
            style: GoogleFonts.inter(fontSize: 14, color: AppTheme.onSurfaceVariant),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
              onPressed: () {
                Navigator.pop(ctx);
                _showBankDetailsDialog();
              },
              child: const Text('Add Bank Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return;
    }

    final TextEditingController amountController = TextEditingController(
      text: maxWithdrawable > 0 ? (maxWithdrawable >= 100 ? '100' : maxWithdrawable.toStringAsFixed(0)) : '0',
    );
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    bool isSubmitting = false;
    String? submitError;

    showDialog(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final enteredAmt = double.tryParse(amountController.text.trim()) ?? 0.0;
            const fee = 0.0;
            final netPayable = enteredAmt > 0 ? enteredAmt - fee : 0.0;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF5046E5).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF5046E5), size: 22),
                  ),
                  const SizedBox(width: 10),
                  Text('Withdrawal Request', style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Balance & Destination Summary
                      Container(
                        padding: const EdgeInsets.all(12),
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
                                Text('Available Withdrawable:', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                                Text('₹${maxWithdrawable.toStringAsFixed(2)}', style: GoogleFonts.robotoMono(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF16A34A))),
                              ],
                            ),
                            const Divider(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Destination:', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDCFCE7),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text('VERIFIED', style: GoogleFonts.robotoMono(fontSize: 8, fontWeight: FontWeight.bold, color: const Color(0xFF16A34A))),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(destinationDisplay, style: GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A))),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Amount Input
                      TextFormField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Withdrawal Amount',
                          prefixText: '₹ ',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        onChanged: (_) => setDialogState(() {}),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) return 'Please enter withdrawal amount';
                          final amt = double.tryParse(val.trim());
                          if (amt == null || amt <= 0) return 'Amount must be greater than zero';
                          if (amt > maxWithdrawable) {
                            return 'Exceeds withdrawable balance (₹${maxWithdrawable.toStringAsFixed(2)})';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Fee & Net Payable Breakdown
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Requested Amount:', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF475569))),
                                Text('₹${enteredAmt.toStringAsFixed(2)}', style: GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.w600)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Withdrawal Fee:', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF475569))),
                                Text('₹0.00 (Zero Fee)', style: GoogleFonts.robotoMono(fontSize: 12, color: const Color(0xFF16A34A), fontWeight: FontWeight.w600)),
                              ],
                            ),
                            const Divider(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Net Payable to Bank:', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
                                Text('₹${netPayable.toStringAsFixed(2)}', style: GoogleFonts.robotoMono(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF5046E5))),
                              ],
                            ),
                          ],
                        ),
                      ),

                      if (submitError != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(submitError!, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFDC2626))),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5046E5),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isSubmitting ? null : () async {
                    if (formKey.currentState?.validate() ?? false) {
                      setDialogState(() {
                        isSubmitting = true;
                        submitError = null;
                      });

                      final rawUid = FirebaseService().currentUid ?? '';
                      final phoneDigits = rawUid.replaceAll(RegExp(r'[^0-9]'), '');
                      final cleanPhone = phoneDigits.length >= 10 ? phoneDigits.substring(phoneDigits.length - 10) : phoneDigits;
                      final effectiveUid = rawUid.isNotEmpty ? rawUid : (cleanPhone.isNotEmpty ? 'pilot_$cleanPhone' : '');
                      final reqAmt = double.parse(amountController.text.trim());
                      final idempotencyKey = 'WTH_${DateTime.now().millisecondsSinceEpoch}_${cleanPhone.isNotEmpty ? cleanPhone : 'pilot'}';

                      try {
                        final baseUrl = NetworkConfig.backendUrl;
                        final res = await ApiClient().post(
                          Uri.parse('$baseUrl/api/pilot/payouts/withdraw'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({
                            'uid': effectiveUid,
                            'amount': reqAmt,
                            'targetAccount': destinationDisplay,
                            'idempotencyKey': idempotencyKey,
                          }),
                        );

                        final data = jsonDecode(res.body);
                        if (res.statusCode == 200 && data['success'] == true) {
                          Navigator.pop(ctx);
                          await _fetchPilotWallet();
                          if (widget.onWithdrawMoney != null) {
                            widget.onWithdrawMoney!(reqAmt);
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(Icons.check_circle, color: Colors.white),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Withdrawal of ₹${reqAmt.toStringAsFixed(2)} submitted!\nRef: ${data['withdrawalId'] ?? data['payoutId'] ?? 'Submitted'} • Status: PENDING_APPROVAL',
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                                backgroundColor: const Color(0xFF16A34A),
                                duration: const Duration(seconds: 5),
                              ),
                            );
                          }
                        } else {
                          setDialogState(() {
                            isSubmitting = false;
                            submitError = data['error'] ?? 'Withdrawal request failed. Please check your balance.';
                          });
                        }
                      } catch (e) {
                        setDialogState(() {
                          isSubmitting = false;
                          submitError = 'Network error: $e';
                        });
                      }
                    }
                  },
                  child: isSubmitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Confirm & Withdraw', style: GoogleFonts.hankenGrotesk(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showHeavyTruckRideDetailsBottomSheet(BuildContext context, Map<String, dynamic> ride) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 600;
    
    final pickup = ride['pickup'] as String? ?? ride['route']?.split(' to ')?.first ?? '';
    final drop = ride['drop'] as String? ?? ride['route']?.split(' to ')?.last ?? '';
    final date = _formatDateToCustom(ride['scheduledDate'] as String?, ride['timestamp'] as int?);
    final time = _formatTimeToCustom(ride['scheduledTimeSlot'] as String?, ride['timestamp'] as int?);
    final customerPhone = ride['passengerPhone'] as String? ?? '';
    final customerName = ride['passengerName'] as String? ?? 'Customer';
    final vehicle = ride['vehicle'] as String? ?? '6 Ton Truck';
    final price = ride['price'] as String? ?? '';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          constraints: BoxConstraints(
            maxWidth: isDesktop ? 600 : double.infinity,
          ),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Heavy Truck Ride Details',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.onSurfaceColor,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 16),
              _buildDetailItem(Icons.local_shipping_rounded, 'Vehicle Type', vehicle),
              _buildDetailItem(Icons.payments_rounded, 'Estimated Earnings', price),
              _buildDetailItem(Icons.my_location_rounded, 'From Location', pickup),
              _buildDetailItem(Icons.location_on_rounded, 'To Location', drop),
              _buildDetailItem(Icons.calendar_today_rounded, 'Scheduled Date', date),
              _buildDetailItem(Icons.access_time_filled_rounded, 'Scheduled Time', time),
              _buildDetailItem(Icons.phone_rounded, 'Customer Mobile No.', customerPhone),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  String _formatDateToCustom(String? dateStr, int? timestampMs) {
    DateTime? dt;
    if (dateStr != null && dateStr.trim().isNotEmpty) {
      try {
        dt = DateTime.parse(dateStr);
      } catch (_) {}
    }
    if (dt == null && timestampMs != null) {
      dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    }
    if (dt == null) return dateStr ?? '';
    
    const months = [
      'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
      'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'
    ];
    final dayStr = dt.day.toString().padLeft(2, '0');
    final monthStr = months[dt.month - 1];
    return '$dayStr-$monthStr-${dt.year}';
  }

  String _formatTimeToCustom(String? timeStr, int? timestampMs) {
    if (timeStr != null && timeStr.trim().isNotEmpty) {
      return timeStr;
    }
    if (timestampMs != null) {
      final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final minStr = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minStr $period';
    }
    return '';
  }

  Widget _buildDetailItem(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.primaryColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.robotoMono(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value.isNotEmpty ? value : 'Not Specified',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.onSurfaceColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
