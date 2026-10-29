import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/socket_service.dart';
import '../models/food_models.dart';
import '../services/food_service.dart';
import 'food_cart_screen.dart';

class RestaurantMenuScreen extends StatefulWidget {
  final Restaurant restaurant;
  final String deliveryAddress;
  final double? deliveryLat;
  final double? deliveryLng;

  const RestaurantMenuScreen({
    Key? key,
    required this.restaurant,
    required this.deliveryAddress,
    this.deliveryLat,
    this.deliveryLng,
  }) : super(key: key);

  @override
  State<RestaurantMenuScreen> createState() => _RestaurantMenuScreenState();
}

class _RestaurantMenuScreenState extends State<RestaurantMenuScreen> {
  final FoodService _foodService = FoodService();

  List<MenuItem> _menuItems = [];
  List<String> _categories = [];
  String _selectedCategory = 'All';
  bool _isLoading = true;
  late bool _isOpen;
  late String _status;

  @override
  void initState() {
    super.initState();
    _isOpen = widget.restaurant.isOpen;
    _status = widget.restaurant.status;
    _loadMenu();

    try {
      SocketService().initSocket();
      SocketService().joinRestaurant(widget.restaurant.restaurantId);
      SocketService().addFoodMenuUpdatedListener(_handleSocketMenuUpdated);
      SocketService().addRestaurantUpdatedListener(_handleSocketRestaurantUpdated);
    } catch (e) {
      debugPrint('[RestaurantMenuScreen] Socket error: $e');
    }
  }

  @override
  void dispose() {
    SocketService().removeFoodMenuUpdatedListener(_handleSocketMenuUpdated);
    SocketService().removeRestaurantUpdatedListener(_handleSocketRestaurantUpdated);
    super.dispose();
  }

  void _handleSocketMenuUpdated(Map<String, dynamic> data) {
    if (!mounted) return;
    final rId = data['restaurantId'] as String? ?? '';
    if (rId.isEmpty || rId == widget.restaurant.restaurantId) {
      _loadMenuSilently();
    }
  }

  void _handleSocketRestaurantUpdated(Map<String, dynamic> data) {
    if (!mounted) return;
    final rId = data['restaurantId'] as String? ?? '';
    if (rId.isEmpty || rId == widget.restaurant.restaurantId) {
      setState(() {
        if (data['isOpen'] != null) _isOpen = data['isOpen'] as bool;
        if (data['status'] != null) _status = data['status'] as String;
      });
    }
  }

  Future<void> _loadMenuSilently() async {
    final detail = await _foodService.fetchRestaurantDetail(widget.restaurant.restaurantId);
    final items = (detail['menuItems'] as List<MenuItem>?) ?? [];
    if (mounted) {
      setState(() {
        _menuItems = items;
      });
    }
  }

  Future<void> _loadMenu() async {
    setState(() => _isLoading = true);
    final detail = await _foodService.fetchRestaurantDetail(widget.restaurant.restaurantId);
    final items = (detail['menuItems'] as List<MenuItem>?) ?? [];
    
    final catSet = <String>{'All'};
    for (final i in items) {
      if (i.category.isNotEmpty) catSet.add(i.category);
    }

    if (mounted) {
      setState(() {
        _menuItems = items;
        _categories = catSet.toList();
        _isLoading = false;
      });
    }
  }

  List<MenuItem> get _filteredItems {
    if (_selectedCategory == 'All') return _menuItems;
    return _menuItems.where((i) => i.category == _selectedCategory).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.restaurant.name,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1E293B),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                const Icon(Icons.star_rounded, size: 18, color: Color(0xFF16A34A)),
                const SizedBox(width: 4),
                Text(
                  widget.restaurant.rating.toStringAsFixed(1),
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF16A34A)),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFEA580C)))
              : CustomScrollView(
                  slivers: [
                    // Restaurant Header Card
                    SliverToBoxAdapter(
                      child: Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.restaurant.name,
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.restaurant.cuisines.join(' • '),
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: const Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.restaurant.address,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.timer_rounded, size: 16, color: Color(0xFFEA580C)),
                                    const SizedBox(width: 4),
                                    Text(
                                      widget.restaurant.deliveryTime,
                                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                                Container(width: 1, height: 16, color: const Color(0xFFE2E8F0)),
                                Row(
                                  children: [
                                    const Icon(Icons.delivery_dining_rounded, size: 18, color: Color(0xFFEA580C)),
                                    const SizedBox(width: 4),
                                    Text(
                                      '₹${widget.restaurant.deliveryFee.toStringAsFixed(0)} Delivery Fee',
                                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (!_isOpen || _status == 'suspended')
                      SliverToBoxAdapter(
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline_rounded, color: Color(0xFFDC2626), size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'This restaurant is currently OFFLINE and not accepting orders.',
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFFB91C1C),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Category Filter Pills
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 40,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          scrollDirection: Axis.horizontal,
                          itemCount: _categories.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final cat = _categories[index];
                            final isSel = _selectedCategory == cat;
                            return ChoiceChip(
                              label: Text(
                                cat,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                                  color: isSel ? Colors.white : const Color(0xFF475569),
                                ),
                              ),
                              selected: isSel,
                              selectedColor: const Color(0xFFEA580C),
                              backgroundColor: Colors.white,
                              side: BorderSide(
                                color: isSel ? const Color(0xFFEA580C) : const Color(0xFFE2E8F0),
                              ),
                              onSelected: (_) => setState(() => _selectedCategory = cat),
                            );
                          },
                        ),
                      ),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 14)),

                    // Menu Items List
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final item = _filteredItems[index];
                            return _buildMenuItemCard(item);
                          },
                          childCount: _filteredItems.length,
                        ),
                      ),
                    ),
                  ],
                ),

          // Persistent Floating Cart Summary Bar
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
                          deliveryAddress: widget.deliveryAddress,
                          deliveryLat: widget.deliveryLat,
                          deliveryLng: widget.deliveryLng,
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

  Widget _buildMenuItemCard(MenuItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: Item details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Veg / Non-Veg Indicator
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: item.isVeg ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: item.isVeg ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.name,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '₹${item.price.toStringAsFixed(0)}',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    item.description,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF64748B),
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Right: Image and Add/Quantity Stepper
          Column(
            children: [
              if (item.imageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 90,
                    height: 80,
                    child: Image.network(
                      item.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFFF1F5F9),
                        child: const Icon(Icons.fastfood_rounded, color: Color(0xFFCBD5E1), size: 28),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  width: 90,
                  height: 60,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Icon(Icons.fastfood_rounded, color: Color(0xFFCBD5E1), size: 28),
                ),

              const SizedBox(height: 8),

              // Quantity Stepper / Add button
              ValueListenableBuilder<FoodCart>(
                valueListenable: _foodService.cartNotifier,
                builder: (context, cart, _) {
                  if (!_isOpen || _status == 'suspended') {
                    return Container(
                      width: 90,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'CLOSED',
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF94A3B8)),
                      ),
                    );
                  }

                  if (!item.isAvailable) {
                    return Container(
                      width: 90,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'SOLD OUT',
                        style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: const Color(0xFFDC2626)),
                      ),
                    );
                  }

                  final qty = _foodService.getItemQuantity(item.itemId);
                  if (qty == 0) {
                    return SizedBox(
                      width: 90,
                      height: 34,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFEA580C),
                          side: const BorderSide(color: Color(0xFFEA580C), width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          backgroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: () {
                          _foodService.addToCart(widget.restaurant, item);
                        },
                        child: Text(
                          'ADD +',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800),
                        ),
                      ),
                    );
                  }

                  return Container(
                    width: 90,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEA580C),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        InkWell(
                          onTap: () => _foodService.removeFromCart(item),
                          child: const Icon(Icons.remove_rounded, color: Colors.white, size: 16),
                        ),
                        Text(
                          '$qty',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        InkWell(
                          onTap: () => _foodService.addToCart(widget.restaurant, item),
                          child: const Icon(Icons.add_rounded, color: Colors.white, size: 16),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

