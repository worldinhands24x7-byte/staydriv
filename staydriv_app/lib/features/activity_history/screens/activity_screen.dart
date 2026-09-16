import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';
import '../../../core/razorpay_gateway.dart';
import '../../ride_selection/screens/ride_selection_screen.dart';

class ActivityScreen extends StatefulWidget {
  final String userRole;
  final double totalEarnings;
  final List<Map<String, dynamic>> completedRides;
  final bool isAdvanceWithdrawn;
  final VoidCallback onWithdrawAdvance;
  final VoidCallback onGoToHome;
  final Function(double)? onWithdrawMoney;
  
  const ActivityScreen({
    super.key,
    required this.userRole,
    required this.totalEarnings,
    required this.completedRides,
    required this.isAdvanceWithdrawn,
    required this.onWithdrawAdvance,
    required this.onGoToHome,
    this.onWithdrawMoney,
  });

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  String _activeTab = 'past'; // past or scheduled
  String _timeFilter = 'Day'; // Day, Week, Month, Year

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
    final List<Map<String, dynamic>> pastTrips = widget.completedRides.isNotEmpty
        ? widget.completedRides
        : [
            {
              'date': 'Oct 24, 14:30',
              'price': '₹45.00',
              'icon': Icons.two_wheeler_rounded,
              'image': 'assets/images/bike.png',
              'title': 'StayDriv Bike',
              'route': 'Downtown Hub to Int. Airport',
              'serviceType': 'bike',
            },
            {
              'date': 'Oct 23, 11:45',
              'price': '₹85.00',
              'icon': Icons.electric_rickshaw_rounded,
              'image': 'assets/images/auto.png',
              'title': 'StayDriv Auto',
              'route': 'Hitech City to Madhapur Metro',
              'serviceType': 'auto',
            },
            {
              'date': 'Oct 22, 16:10',
              'price': '₹165.00',
              'icon': Icons.directions_car_rounded,
              'image': 'assets/images/car.png',
              'title': 'StayDriv Car',
              'route': 'Jubilee Hills to Gachibowli',
              'serviceType': 'car',
            },
            {
              'date': 'Oct 22, 09:15',
              'price': '₹320.00',
              'icon': Icons.airport_shuttle_rounded,
              'image': 'assets/images/mini_truck.png',
              'title': 'Mini Truck',
              'route': 'Westside Office to Tech Park',
              'serviceType': 'parcel',
            },
          ];

    return ListView.builder(
      itemCount: pastTrips.length,
      itemBuilder: (context, index) {
        final trip = pastTrips[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
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
                      trip['date'] as String,
                      style: GoogleFonts.robotoMono(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      trip['price'] as String,
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
                                  trip['icon'] as IconData,
                                  color: AppTheme.primaryColor,
                                  size: 28,
                                ),
                              ),
                            )
                          : Icon(
                              trip['icon'] as IconData,
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
                            trip['title'] as String,
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.onSurfaceColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            trip['route'] as String,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppTheme.onSurfaceVariant,
                            ),
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryAccent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: AppTheme.primaryColor, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            'Completed',
                            style: GoogleFonts.robotoMono(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primaryColor,
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
                            builder: (context) => RideSelectionScreen(serviceType: trip['serviceType'] as String),
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
        );
      },
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
    return widget.completedRides.where((ride) {
      final timestamp = ride['timestamp'] as int? ?? 0;
      final rideDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final diff = now.difference(rideDate).inDays.abs();
      
      if (_timeFilter == 'Day') {
        return diff < 1;
      } else if (_timeFilter == 'Week') {
        return diff < 7;
      } else if (_timeFilter == 'Month') {
        return diff < 30;
      } else {
        return diff < 365;
      }
    }).toList();
  }

  double _getFilteredEarnings(List<Map<String, dynamic>> filteredRides) {
    double sum = 0;
    for (var ride in filteredRides) {
      final priceStr = ride['price'] as String? ?? '0';
      final cleanStr = priceStr.replaceAll(RegExp(r'[^0-9.]'), '');
      sum += double.tryParse(cleanStr) ?? 0.0;
    }
    return sum;
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(height: 20),

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

              // Weekly Expense Advance Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: widget.isAdvanceWithdrawn
                        ? [AppTheme.surfaceContainerLow, AppTheme.surfaceContainerLow]
                        : [AppTheme.primaryColor.withValues(alpha: 0.08), AppTheme.primaryAccent.withValues(alpha: 0.04)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: widget.isAdvanceWithdrawn
                        ? AppTheme.outlineVariant.withValues()
                        : AppTheme.primaryColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: widget.isAdvanceWithdrawn ? AppTheme.outlineVariant.withValues() : AppTheme.primaryColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.account_balance_wallet_rounded,
                        color: widget.isAdvanceWithdrawn ? AppTheme.onSurfaceVariant : AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Weekly Expense Advance',
                            style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.onSurfaceColor),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.isAdvanceWithdrawn 
                                ? '₹200 advancedly withdrawn'
                                : 'Withdraw ₹200 advance for fuel & expenses',
                            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: widget.isAdvanceWithdrawn ? null : widget.onWithdrawAdvance,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(
                        widget.isAdvanceWithdrawn ? 'Claimed' : 'Withdraw',
                        style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
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
                            'Withdrawable: ₹${widget.totalEarnings.toStringAsFixed(2)}',
                            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: widget.totalEarnings <= 0 
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
              const SizedBox(height: 20),

              Text(
                'Ride & Earnings History',
                style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.onSurfaceColor),
              ),
              const SizedBox(height: 10),

              Expanded(
                child: filteredRides.isEmpty
                    ? Center(
                        child: Text(
                          'No rides completed in this period.',
                          style: GoogleFonts.inter(color: AppTheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredRides.length,
                        itemBuilder: (context, index) {
                          final ride = filteredRides[index];
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
                            child: isHeavyTruck
                                ? InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => _showHeavyTruckRideDetailsBottomSheet(context, ride),
                                    child: listTileChild,
                                  )
                                : listTileChild,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showWithdrawDialog(BuildContext context) {
    final TextEditingController amountController = TextEditingController(text: widget.totalEarnings.toStringAsFixed(0));
    final TextEditingController upiController = TextEditingController(text: 'driver@upi');
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Withdraw Earnings',
            style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold),
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Withdraw instant payout via Razorpay. Available: ₹${widget.totalEarnings.toStringAsFixed(2)}',
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Withdrawal Amount',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'Enter amount';
                    final amt = double.tryParse(val);
                    if (amt == null || amt <= 0) return 'Enter valid positive amount';
                    if (amt > widget.totalEarnings) return 'Exceeds available balance';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: upiController,
                  decoration: const InputDecoration(
                    labelText: 'UPI ID or Bank Account',
                    border: OutlineInputBorder(),
                    hintText: 'driver@okaxis',
                  ),
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'Enter payment address';
                    return null;
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
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5046E5)),
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  final amt = double.parse(amountController.text);
                  final upi = upiController.text;
                  Navigator.pop(context); // Close withdrawal request form

                  // Open Razorpay Payout gateway
                  RazorpayGateway.show(
                    context,
                    amount: amt,
                    description: 'Earning Withdrawal Payout',
                    isPayout: true,
                    targetAccount: upi,
                    onSuccess: () {
                      if (widget.onWithdrawMoney != null) {
                        widget.onWithdrawMoney!(amt);
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Instant Payout of ₹${amt.toStringAsFixed(2)} processed to $upi via Razorpay.'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                  );
                }
              },
              child: Text('Withdraw', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
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
