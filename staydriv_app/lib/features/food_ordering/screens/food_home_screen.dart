import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import '../models/food_models.dart';
import '../services/food_service.dart';
import '../services/food_location_service.dart';
import 'restaurant_menu_screen.dart';
import 'food_cart_screen.dart';
import 'food_order_history_screen.dart';
import 'food_membership_screen.dart';
import '../../dashboard/widgets/console_switcher_sheet.dart';
import '../../promotions/widgets/promotional_banner_carousel.dart';

class FoodHomeScreen extends StatefulWidget {
  final VoidCallback? onBackToHome;
  const FoodHomeScreen({Key? key, this.onBackToHome}) : super(key: key);

  @override
  State<FoodHomeScreen> createState() => _FoodHomeScreenState();
}

class _FoodHomeScreenState extends State<FoodHomeScreen> {
  final FoodService _foodService = FoodService();
  final FoodLocationService _locationService = FoodLocationService();
  final TextEditingController _searchController = TextEditingController();

  List<String> _categories = [];
  List<Restaurant> _restaurants = [];
  String _selectedCategory = 'All';
  bool _isVegOnly = false;
  bool _isLoading = true;
  bool _isDetectingLocation = false;
  CustomerFoodMembershipModel? _membership;

  DeliveryLocation _currentLocation = const DeliveryLocation(
    address: 'Flat 402, Highrise Heights, Madhapur, Hyderabad, Telangana',
    shortAddress: 'Madhapur, Hyderabad',
    latitude: 17.4483,
    longitude: 78.3800,
    type: 'home',
  );

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);

    // 1. Read cached location first so customer sees their saved address immediately
    final savedLoc = await _locationService.getSavedLocation();
    if (mounted) {
      setState(() => _currentLocation = savedLoc);
    }

    final results = await Future.wait([
      _foodService.fetchCategories(),
      _foodService.fetchRestaurants(
        userLat: savedLoc.latitude,
        userLng: savedLoc.longitude,
      ),
      _foodService.fetchCustomerMembership('CUST_STAYDRIV_01'),
    ]);
    final cats = results[0] as List<String>;
    final rests = results[1] as List<Restaurant>;
    final mem = results[2] as CustomerFoodMembershipModel?;

    if (mounted) {
      setState(() {
        _categories = ['All', ...cats];
        _restaurants = rests;
        _membership = mem;
        _isLoading = false;
      });
    }

    // 2. Automatically request and detect live GPS location
    _detectLiveLocation(requestIfDenied: true);
  }

  Future<void> _detectLiveLocation({bool requestIfDenied = true}) async {
    if (!mounted) return;
    setState(() => _isDetectingLocation = true);

    final status = await _locationService.checkPermissionState();
    if (status == LocationPermissionState.serviceDisabled) {
      if (mounted) {
        setState(() => _isDetectingLocation = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS is turned off. Please enable device location in Settings to find nearby restaurants.'),
            backgroundColor: Color(0xFFEA580C),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    if (status == LocationPermissionState.deniedForever) {
      if (mounted) {
        setState(() => _isDetectingLocation = false);
        _showPermissionSettingsDialog();
      }
      return;
    }

    final liveLoc = await _locationService.detectLiveGpsLocation(requestIfDenied: requestIfDenied);
    if (mounted) {
      setState(() => _isDetectingLocation = false);
      if (liveLoc != null) {
        setState(() => _currentLocation = liveLoc);
        await _locationService.saveCurrentLocation(liveLoc);

        // Dynamically reload restaurants and menu based on detected live location
        final liveRestaurants = await _foodService.fetchRestaurants(
          userLat: liveLoc.latitude,
          userLng: liveLoc.longitude,
        );
        if (mounted) {
          setState(() => _restaurants = liveRestaurants);
          _filterRestaurants();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('📍 Delivery location detected: ${liveLoc.shortAddress}'),
              backgroundColor: const Color(0xFF16A34A),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not detect GPS location. You can select your address manually.'),
            backgroundColor: Color(0xFF64748B),
          ),
        );
      }
    }
  }

  void _showPermissionSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Location Permission Required', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16)),
        content: Text(
          'StayDriv uses your location to discover nearby restaurants and deliver food accurately. Please enable location permissions in app settings.',
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: const Color(0xFF64748B), fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEA580C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openAppSettings();
            },
            child: Text('Open Settings', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _filterRestaurants() async {
    setState(() => _isLoading = true);
    final rests = await _foodService.fetchRestaurants(
      query: _searchController.text,
      category: _selectedCategory,
      vegOnly: _isVegOnly,
      userLat: _currentLocation.latitude,
      userLng: _currentLocation.longitude,
    );
    if (mounted) {
      setState(() {
        _restaurants = rests;
        _isLoading = false;
      });
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'biryani':
        return Icons.rice_bowl_rounded;
      case 'south indian':
        return Icons.breakfast_dining_rounded;
      case 'north indian':
        return Icons.dinner_dining_rounded;
      case 'pizza':
        return Icons.local_pizza_rounded;
      case 'burgers':
        return Icons.lunch_dining_rounded;
      case 'chinese':
        return Icons.ramen_dining_rounded;
      case 'snacks':
        return Icons.tapas_rounded;
      case 'desserts':
        return Icons.cake_rounded;
      case 'rolls':
        return Icons.kebab_dining_rounded;
      case 'beverages':
        return Icons.local_cafe_rounded;
      default:
        return Icons.restaurant_menu_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        titleSpacing: 16,
        leading: widget.onBackToHome != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1E293B)),
                onPressed: widget.onBackToHome,
              )
            : null,
        title: InkWell(
          onTap: _showLocationSelectionBottomSheet,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on_rounded, size: 14, color: Color(0xFFEA580C)),
                    const SizedBox(width: 4),
                    Text(
                      'DELIVERING TO',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFEA580C),
                        letterSpacing: 0.6,
                      ),
                    ),
                    if (_isDetectingLocation) ...[
                      const SizedBox(width: 6),
                      const SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEA580C)),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        _isDetectingLocation
                            ? 'Detecting current GPS location...'
                            : (_currentLocation.shortAddress.isNotEmpty && _currentLocation.shortAddress != _currentLocation.address
                                ? 'Delivering to: ${_currentLocation.shortAddress}'
                                : 'Delivering to: ${_currentLocation.address}'),
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF64748B)),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: _isDetectingLocation
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEA580C)),
                    ),
                  )
                : const Icon(Icons.my_location_rounded, color: Color(0xFFEA580C), size: 20),
            tooltip: 'Detect Current Location',
            onPressed: _isDetectingLocation ? null : () => _detectLiveLocation(requestIfDenied: true),
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long_rounded, color: Color(0xFF1E293B)),
            tooltip: 'Order History',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FoodOrderHistoryScreen()),
              );
            },
          ),
          // EXACT TOP-RIGHT POSITION MARKED BY RED CIRCLE (Picture 1)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Tooltip(
              message: 'Food Membership',
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FoodMembershipScreen(
                        onOrderFoodPressed: () {},
                      ),
                    ),
                  ).then((_) => _loadInitialData());
                },
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _membership != null && _membership!.isActive
                        ? const Color(0xFF1E3A8A).withOpacity(0.10)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _membership != null && _membership!.isActive
                          ? const Color(0xFFEAB308)
                          : const Color(0xFFCBD5E1),
                      width: 1.4,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        _membership != null && _membership!.isActive
                            ? Icons.workspace_premium_rounded
                            : Icons.card_membership_rounded,
                        color: _membership != null && _membership!.isActive
                            ? const Color(0xFFD97706)
                            : const Color(0xFF1E3A8A),
                        size: 21,
                      ),
                      if (_membership != null && _membership!.isActive)
                        Positioned(
                          right: 1,
                          top: 1,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.hub_outlined, color: Color(0xFF1E293B)),
            tooltip: 'Switch Console (Customer, Pilot, Restaurant, Admin)',
            onPressed: () => ConsoleSwitcherSheet.show(
              context,
              currentRole: 'Customer',
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _loadInitialData,
            color: const Color(0xFFEA580C),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 90),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Search Bar & Filter Switch
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: TextField(
                              controller: _searchController,
                              onChanged: (_) => _filterRestaurants(),
                              style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF1E293B)),
                              decoration: InputDecoration(
                                hintText: 'Search restaurants or food dishes...',
                                hintStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13),
                                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF94A3B8), size: 20),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
                                        onPressed: () {
                                          _searchController.clear();
                                          _filterRestaurants();
                                        },
                                      )
                                    : null,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Veg Only Filter Pill
                        InkWell(
                          onTap: () {
                            setState(() => _isVegOnly = !_isVegOnly);
                            _filterRestaurants();
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            decoration: BoxDecoration(
                              color: _isVegOnly ? const Color(0xFFDCFCE7) : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _isVegOnly ? const Color(0xFF16A34A) : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.eco_rounded,
                                  size: 16,
                                  color: _isVegOnly ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'VEG',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _isVegOnly ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 1. Dynamic Promotional Banner, Routine Poster & Advertisement Carousel (Food Order Now)
                  const PromotionalBannerCarousel(
                    screen: 'food',
                    padding: EdgeInsets.fromLTRB(16, 6, 16, 6),
                    height: 168.0,
                  ),

                  // 2. Clearly Visible Food Membership Banner (Section 2 Requirements)
                  _buildFoodMembershipBanner(),

                  // 2. Categories Horizontal Scroll
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text(
                      'What would you like to eat?',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 86,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: _categories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final cat = _categories[index];
                        final isSelected = _selectedCategory == cat;
                        return GestureDetector(
                          onTap: () {
                            setState(() => _selectedCategory = cat);
                            _filterRestaurants();
                          },
                          child: Column(
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 54,
                                height: 54,
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFFEA580C) : Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? const Color(0xFFEA580C) : const Color(0xFFE2E8F0),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: isSelected
                                          ? const Color(0xFFEA580C).withOpacity(0.3)
                                          : Colors.black.withOpacity(0.04),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  _getCategoryIcon(cat),
                                  color: isSelected ? Colors.white : const Color(0xFF475569),
                                  size: 26,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                cat,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  color: isSelected ? const Color(0xFFEA580C) : const Color(0xFF475569),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  // 3. Restaurants Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Featured & Nearby Restaurants',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                        Text(
                          '${_restaurants.length} Places',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 4. Restaurant Cards List
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: CircularProgressIndicator(color: Color(0xFFEA580C)),
                      ),
                    )
                  else if (_restaurants.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
                      child: Center(
                        child: Column(
                          children: [
                            const Icon(Icons.no_meals_rounded, size: 48, color: Color(0xFFCBD5E1)),
                            const SizedBox(height: 12),
                            Text(
                              'No restaurants found',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF475569),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Try selecting another food category or clearing search filters.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      itemCount: _restaurants.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        return _buildRestaurantCard(_restaurants[index]);
                      },
                    ),
                ],
              ),
            ),
          ),

          // 5. Floating Cart Summary (if items in cart)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: ValueListenableBuilder<FoodCart>(
              valueListenable: _foodService.cartNotifier,
              builder: (context, cart, _) {
                if (cart.isEmpty) return const SizedBox.shrink();
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FoodCartScreen(
                          deliveryAddress: _currentLocation.address,
                          deliveryLat: _currentLocation.latitude,
                          deliveryLng: _currentLocation.longitude,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEA580C), Color(0xFFC2410C)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFEA580C).withOpacity(0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.shopping_bag_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${cart.totalItemCount} ITEM${cart.totalItemCount > 1 ? "S" : ""} ADDED',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white.withOpacity(0.9),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                '₹${cart.subtotal.toStringAsFixed(0)} plus taxes',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              'View Cart',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
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
  }

  Widget _buildRestaurantCard(Restaurant restaurant) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RestaurantMenuScreen(
              restaurant: restaurant,
              deliveryAddress: _currentLocation.address,
              deliveryLat: _currentLocation.latitude,
              deliveryLng: _currentLocation.longitude,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner Image & Overlay Pills
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      restaurant.imageUrl.isNotEmpty
                          ? restaurant.imageUrl
                          : 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=800',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFFF1F5F9),
                        child: const Icon(Icons.restaurant_rounded, size: 40, color: Color(0xFFCBD5E1)),
                      ),
                    ),
                  ),
                ),
                // Gradient Shadow
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.2),
                          Colors.transparent,
                          Colors.black.withOpacity(0.55),
                        ],
                      ),
                    ),
                  ),
                ),
                // Delivery Time Pill
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.timer_rounded, size: 14, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          restaurant.distanceKm != null
                              ? '${restaurant.distanceKm} km • ${restaurant.deliveryTime}'
                              : restaurant.deliveryTime,
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
                // Rating Pill
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 14, color: Colors.white),
                        const SizedBox(width: 2),
                        Text(
                          restaurant.rating.toStringAsFixed(1),
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
                // Pure Veg Badge (if applicable)
                if (restaurant.isVegOnly)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16A34A),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'PURE VEG',
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),

            // Card Body Info
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          restaurant.name,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1E293B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '₹${restaurant.deliveryFee.toStringAsFixed(0)} Delivery',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFEA580C),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    restaurant.cuisines.join(' • '),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF64748B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    restaurant.address,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: const Color(0xFF94A3B8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLocationSelectionBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LocationSelectionSheet(
        currentLocation: _currentLocation,
        locationService: _locationService,
        onLocationSelected: (newLocation) {
          setState(() {
            _currentLocation = newLocation;
          });
          _locationService.saveCurrentLocation(newLocation);
          _filterRestaurants();
        },
        onRequestLiveGps: () => _detectLiveLocation(requestIfDenied: true),
      ),
    );
  }

  Widget _buildFoodMembershipBanner() {
    final hasMembership = _membership != null && _membership!.isActive;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: hasMembership
                ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                : [const Color(0xFFFFF7ED), const Color(0xFFFFEDD5)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasMembership
                ? const Color(0xFFEA580C).withOpacity(0.5)
                : const Color(0xFFFDBA74),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEA580C),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.star_rounded, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasMembership ? 'STAYDRIV FOOD PASS • ACTIVE' : 'FOOD MEMBERSHIP PASS',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFFEA580C),
                          letterSpacing: 0.6,
                        ),
                      ),
                      Text(
                        hasMembership
                            ? '${_membership!.planName} • Member ID: ${_membership!.membershipId}'
                            : 'Save 20%-25% on Food Dishes + Free Delivery',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: hasMembership ? Colors.white : const Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasMembership)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF10B981), width: 1),
                    ),
                    child: Text(
                      'ACTIVE',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF10B981),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // Benefits & validity row
            if (hasMembership) ...[
              Text(
                'Membership Validity: Valid until ${_membership!.endDate != null ? "${_membership!.endDate!.day}/${_membership!.endDate!.month}/${_membership!.endDate!.year}" : "Active"} (${_membership!.daysRemaining} days left)',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: const Color(0xFF94A3B8),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
            ],

            // 5 Required Quick Action Chips (Section 2 Requirements)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildQuickActionChip(
                    label: 'Order Food',
                    icon: Icons.restaurant_rounded,
                    isPrimary: true,
                    onTap: () {
                      // Already on Food Order Now!
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildQuickActionChip(
                    label: 'My Food Membership',
                    icon: Icons.badge_rounded,
                    isPrimary: false,
                    hasDarkBg: hasMembership,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FoodMembershipScreen(
                            onOrderFoodPressed: () {},
                          ),
                        ),
                      ).then((_) => _loadInitialData());
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildQuickActionChip(
                    label: 'Membership Benefits',
                    icon: Icons.card_giftcard_rounded,
                    isPrimary: false,
                    hasDarkBg: hasMembership,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FoodMembershipScreen(
                            onOrderFoodPressed: () {},
                          ),
                        ),
                      ).then((_) => _loadInitialData());
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildQuickActionChip(
                    label: 'Membership Validity',
                    icon: Icons.event_available_rounded,
                    isPrimary: false,
                    hasDarkBg: hasMembership,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FoodMembershipScreen(
                            onOrderFoodPressed: () {},
                          ),
                        ),
                      ).then((_) => _loadInitialData());
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildQuickActionChip(
                    label: 'Renew Membership',
                    icon: Icons.autorenew_rounded,
                    isPrimary: false,
                    hasDarkBg: hasMembership,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FoodMembershipScreen(
                            onOrderFoodPressed: () {},
                          ),
                        ),
                      ).then((_) => _loadInitialData());
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionChip({
    required String label,
    required IconData icon,
    required bool isPrimary,
    bool hasDarkBg = false,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isPrimary
              ? const Color(0xFFEA580C)
              : (hasDarkBg ? Colors.white.withOpacity(0.1) : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: isPrimary
              ? null
              : Border.all(
                  color: hasDarkBg ? Colors.white.withOpacity(0.2) : const Color(0xFFE2E8F0),
                ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isPrimary ? Colors.white : (hasDarkBg ? Colors.white : const Color(0xFF1E293B)),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isPrimary ? Colors.white : (hasDarkBg ? Colors.white : const Color(0xFF1E293B)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationSelectionSheet extends StatefulWidget {
  final DeliveryLocation currentLocation;
  final FoodLocationService locationService;
  final ValueChanged<DeliveryLocation> onLocationSelected;
  final VoidCallback onRequestLiveGps;

  const _LocationSelectionSheet({
    Key? key,
    required this.currentLocation,
    required this.locationService,
    required this.onLocationSelected,
    required this.onRequestLiveGps,
  }) : super(key: key);

  @override
  State<_LocationSelectionSheet> createState() => _LocationSelectionSheetState();
}

class _LocationSelectionSheetState extends State<_LocationSelectionSheet> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _manualInputController = TextEditingController();
  Timer? _debounceTimer;

  List<Map<String, String>> _searchPredictions = [];
  List<DeliveryLocation> _savedAddresses = [];
  bool _isSearching = false;
  bool _showManualEntry = false;
  late DeliveryLocation _selectedLoc;

  @override
  void initState() {
    super.initState();
    _selectedLoc = widget.currentLocation;
    _manualInputController.text = widget.currentLocation.address;
    _loadSavedAddresses();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _manualInputController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedAddresses() async {
    final list = await widget.locationService.getSavedAddresses();
    if (mounted) {
      setState(() => _savedAddresses = list);
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _searchPredictions = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      final results = await widget.locationService.searchPlaces(
        query,
        userLat: widget.currentLocation.latitude,
        userLng: widget.currentLocation.longitude,
      );
      if (mounted) {
        setState(() {
          _searchPredictions = results;
          _isSearching = false;
        });
      }
    });
  }

  Future<void> _selectPrediction(Map<String, String> item) async {
    final placeId = item['place_id'] ?? '';
    final desc = item['description'] ?? '';
    setState(() => _isSearching = true);

    final resolved = await widget.locationService.geocodePlace(placeId, desc);
    if (mounted) {
      setState(() => _isSearching = false);
      if (resolved != null) {
        widget.onLocationSelected(resolved);
        Navigator.pop(context);
      }
    }
  }

  void _selectSavedPreset(DeliveryLocation preset) {
    widget.onLocationSelected(preset);
    Navigator.pop(context);
  }

  void _confirmManualAddress() {
    final text = _manualInputController.text.trim();
    if (text.isEmpty) return;

    final updated = _selectedLoc.copyWith(
      address: text,
      shortAddress: text.split(',').first.trim(),
    );
    widget.onLocationSelected(updated);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Choose Delivery Location',
                      style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Find nearby restaurants and delivery estimates',
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 22),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFF1F5F9)),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              children: [
                // Quick Action: Use Current GPS Location
                InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    widget.onRequestLiveGps();
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFDBA74).withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEA580C),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.my_location_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Use Current GPS Location',
                                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF9A3412)),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEA580C),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'FAST',
                                      style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Detect current GPS coordinates automatically',
                                style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFFC2410C)),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFFEA580C)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Search field
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF1E293B)),
                    decoration: InputDecoration(
                      hintText: 'Search area, street or landmark...',
                      hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFFEA580C), size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18, color: Color(0xFF94A3B8)),
                              onPressed: () {
                                _searchController.clear();
                                _onSearchChanged('');
                              },
                            )
                          : (_isSearching
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Center(
                                    child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEA580C))),
                                  ),
                                )
                              : null),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ),

                // Autocomplete results
                if (_searchPredictions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Search Results',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF64748B), letterSpacing: 0.6),
                  ),
                  const SizedBox(height: 6),
                  ..._searchPredictions.map((pred) {
                    final mainText = pred['main_text'] ?? '';
                    final secText = pred['secondary_text'] ?? '';
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      leading: const Icon(Icons.location_on_rounded, color: Color(0xFFEA580C), size: 20),
                      title: Text(mainText, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B))),
                      subtitle: secText.isNotEmpty ? Text(secText, style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)), maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                      onTap: () => _selectPrediction(pred),
                    );
                  }).toList(),
                ],

                const SizedBox(height: 18),

                // Saved Addresses section
                if (_savedAddresses.isNotEmpty) ...[
                  Text(
                    'SAVED ADDRESSES',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF64748B), letterSpacing: 0.6),
                  ),
                  const SizedBox(height: 8),
                  ..._savedAddresses.map((preset) {
                    final isHome = preset.type.toLowerCase() == 'home';
                    final isWork = preset.type.toLowerCase() == 'work';
                    final isSelected = widget.currentLocation.address == preset.address;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF16A34A) : const Color(0xFFE2E8F0),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isHome
                                ? const Color(0xFFDBEAFE)
                                : (isWork ? const Color(0xFFEDE9FE) : const Color(0xFFF1F5F9)),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isHome ? Icons.home_rounded : (isWork ? Icons.work_rounded : Icons.place_rounded),
                            color: isHome ? const Color(0xFF2563EB) : (isWork ? const Color(0xFF7C3AED) : const Color(0xFF64748B)),
                            size: 18,
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(
                              preset.displayTitle,
                              style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)),
                            ),
                            if (isSelected) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF16A34A),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('CURRENT', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          preset.address,
                          style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 20)
                            : const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8), size: 20),
                        onTap: () => _selectSavedPreset(preset),
                      ),
                    );
                  }).toList(),
                ],

                const SizedBox(height: 14),

                // Manual detail entry toggle
                InkWell(
                  onTap: () => setState(() => _showManualEntry = !_showManualEntry),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          _showManualEntry ? Icons.remove_circle_outline_rounded : Icons.add_circle_outline_rounded,
                          size: 18,
                          color: const Color(0xFFEA580C),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _showManualEntry ? 'Hide Manual Address Details' : 'Add Flat / Floor / Landmark Details',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFFEA580C)),
                        ),
                      ],
                    ),
                  ),
                ),

                if (_showManualEntry) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _manualInputController,
                    maxLines: 2,
                    style: GoogleFonts.inter(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Enter complete house/flat no., street, and landmark...',
                      hintStyle: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEA580C),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _confirmManualAddress,
                      child: Text(
                        'Confirm Delivery Address',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

