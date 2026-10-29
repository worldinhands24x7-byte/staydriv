import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/network_config.dart';
import '../models/food_models.dart';

class FoodService {
  static final FoodService _instance = FoodService._internal();
  factory FoodService() => _instance;
  FoodService._internal();

  String get baseUrl => NetworkConfig.defaultHttpsTunnelUrl;

  // Centralized reactive cart
  final ValueNotifier<FoodCart> cartNotifier = ValueNotifier<FoodCart>(FoodCart());

  FoodCart get currentCart => cartNotifier.value;

  void addToCart(Restaurant restaurant, MenuItem item) {
    var cart = cartNotifier.value;
    
    // If cart has items from another restaurant, reset cart for new restaurant
    if (cart.restaurant != null && cart.restaurant!.restaurantId != restaurant.restaurantId) {
      cart = FoodCart(restaurant: restaurant, items: []);
    }

    final items = List<CartItem>.from(cart.items);
    final existingIdx = items.indexWhere((i) => i.item.itemId == item.itemId);

    if (existingIdx >= 0) {
      items[existingIdx].quantity += 1;
    } else {
      items.add(CartItem(item: item, quantity: 1));
    }

    cartNotifier.value = FoodCart(restaurant: restaurant, items: items);
  }

  void removeFromCart(MenuItem item) {
    final cart = cartNotifier.value;
    final items = List<CartItem>.from(cart.items);
    final existingIdx = items.indexWhere((i) => i.item.itemId == item.itemId);

    if (existingIdx >= 0) {
      if (items[existingIdx].quantity > 1) {
        items[existingIdx].quantity -= 1;
      } else {
        items.removeAt(existingIdx);
      }
    }

    cartNotifier.value = FoodCart(
      restaurant: items.isEmpty ? null : cart.restaurant,
      items: items,
    );
  }

  int getItemQuantity(String itemId) {
    final items = cartNotifier.value.items;
    final existing = items.where((i) => i.item.itemId == itemId);
    return existing.isEmpty ? 0 : existing.first.quantity;
  }

  void clearCart() {
    cartNotifier.value = FoodCart();
  }

  // 1. Fetch categories
  Future<List<String>> fetchCategories() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/food/categories'))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['categories'] is List) {
          return (data['categories'] as List).map((c) => c.toString()).toList();
        }
      }
    } catch (e) {
      debugPrint('[FoodService] Error fetching categories: $e');
    }
    // Reliable default fallback
    return [
      'Biryani',
      'South Indian',
      'North Indian',
      'Pizza',
      'Burgers',
      'Chinese',
      'Snacks',
      'Desserts',
      'Rolls',
      'Beverages'
    ];
  }

  // 2. Fetch restaurants with real-time location proximity
  Future<List<Restaurant>> fetchRestaurants({
    String? query,
    String? category,
    bool? vegOnly,
    double? userLat,
    double? userLng,
  }) async {
    try {
      final queryParams = <String, String>{
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        if (category != null && category != 'All') 'category': category,
        if (vegOnly == true) 'vegOnly': 'true',
        if (userLat != null) 'lat': userLat.toString(),
        if (userLng != null) 'lng': userLng.toString(),
      };

      final uri = Uri.parse('$baseUrl/api/food/restaurants').replace(queryParameters: queryParams);
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['restaurants'] is List) {
          return (data['restaurants'] as List).map((r) => Restaurant.fromJson(r)).toList();
        }
      }
    } catch (e) {
      debugPrint('[FoodService] Error fetching restaurants: $e');
    }

    // Genuine restaurants only: return empty list so app shows clean empty state
    return [];
  }

  // 3. Fetch restaurant details & menu
  Future<Map<String, dynamic>> fetchRestaurantDetail(String restaurantId) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/food/restaurants/$restaurantId'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          final restaurant = Restaurant.fromJson(data['restaurant']);
          final rawItems = data['menuItems'] as List<dynamic>? ?? [];
          final items = rawItems.map((i) => MenuItem.fromJson(i)).toList();
          return {
            'restaurant': restaurant,
            'menuItems': items,
          };
        }
      }
    } catch (e) {
      debugPrint('[FoodService] Error fetching restaurant details: $e');
    }

    // Genuine menu items only: return empty state when restaurant details cannot be loaded
    return {
      'restaurant': null,
      'menuItems': <MenuItem>[],
    };
  }

  // 4. Validate Cart against backend with dynamic delivery fee
  Future<Map<String, dynamic>> validateCart({
    required String restaurantId,
    required List<CartItem> items,
    required String deliveryAddress,
    double? userLat,
    double? userLng,
  }) async {
    try {
      final payload = {
        'restaurantId': restaurantId,
        'items': items.map((i) => i.toJson()).toList(),
        'deliveryAddress': deliveryAddress,
        if (userLat != null && userLng != null)
          'deliveryLatLng': {'lat': userLat, 'lng': userLng},
      };

      final res = await http.post(
        Uri.parse('$baseUrl/api/food/validate-cart'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (e) {
      debugPrint('[FoodService] Error validating cart: $e');
    }

    // Local calculation fallback
    final subtotal = items.fold(0.0, (sum, i) => sum + i.lineTotal);
    final deliveryFee = 30.0;
    final platformFee = 15.0;
    final taxes = (subtotal * 0.05).roundToDouble();
    final totalAmount = subtotal + deliveryFee + platformFee + taxes;

    return {
      'success': true,
      'subtotal': subtotal,
      'deliveryFee': deliveryFee,
      'platformFee': platformFee,
      'taxes': taxes,
      'totalAmount': totalAmount,
    };
  }

  // Authoritative dynamic food bill calculation from server
  Future<Map<String, dynamic>?> calculateFoodBill({
    required String restaurantId,
    required List<CartItem> items,
    required String deliveryAddress,
    double? deliveryLat,
    double? deliveryLng,
    String? couponCode,
    String? customerId,
    String? customerPhone,
    String? membershipId,
    String paymentMethod = 'online',
  }) async {
    try {
      final payload = {
        'restaurantId': restaurantId,
        'items': items.map((i) => i.toJson()).toList(),
        'deliveryAddress': deliveryAddress,
        if (deliveryLat != null && deliveryLng != null)
          'deliveryLatLng': {'lat': deliveryLat, 'lng': deliveryLng},
        if (couponCode != null && couponCode.isNotEmpty) 'couponCode': couponCode,
        if (customerId != null && customerId.isNotEmpty) 'customerId': customerId,
        if (customerPhone != null && customerPhone.isNotEmpty) 'customerPhone': customerPhone,
        if (membershipId != null && membershipId.isNotEmpty) 'membershipId': membershipId,
        'paymentMethod': paymentMethod,
      };

      final res = await http.post(
        Uri.parse('$baseUrl/api/food/calculate-bill'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['bill'] is Map) {
          return Map<String, dynamic>.from(data['bill']);
        }
      }
    } catch (e) {
      debugPrint('[FoodService] Error calculating food bill: $e');
    }
    return null;
  }

  // Fetch available food coupons
  Future<List<FoodCouponModel>> fetchFoodCoupons({String? restaurantId, double? subtotal}) async {
    try {
      final qParams = <String, String>{
        if (restaurantId != null) 'restaurantId': restaurantId,
        if (subtotal != null) 'subtotal': subtotal.toString(),
      };
      final uri = Uri.parse('$baseUrl/api/food/coupons').replace(queryParameters: qParams);
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['coupons'] is List) {
          return (data['coupons'] as List)
              .map((c) => FoodCouponModel.fromJson(Map<String, dynamic>.from(c)))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[FoodService] Error fetching food coupons: $e');
    }
    return [];
  }

  // Fetch real-time customer StayDriv wallet balance
  Future<double> fetchCustomerWalletBalance(String customerId, {String? phone}) async {
    try {
      final uri = Uri.parse('$baseUrl/api/customer/wallet/$customerId')
          .replace(queryParameters: {if (phone != null) 'phone': phone});
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['walletBalance'] != null) {
          return (data['walletBalance'] as num).toDouble();
        }
      }
    } catch (e) {
      debugPrint('[FoodService] Error fetching wallet balance: $e');
    }
    return 0.0;
  }

  // Create genuine Razorpay payment order for food checkout
  Future<Map<String, dynamic>?> createFoodRazorpayOrder({
    required double amount,
    required String customerId,
    required String customerPhone,
    required String customerName,
    String? orderId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/food/razorpay/create-order'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'amount': amount,
          'customerId': customerId,
          'customerPhone': customerPhone,
          'customerName': customerName,
          'orderId': orderId ?? '',
        }),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          return Map<String, dynamic>.from(data);
        }
      }
    } catch (e) {
      debugPrint('[FoodService] Error creating Razorpay order: $e');
    }
    return null;
  }

  // Verify Razorpay payment signature
  Future<bool> verifyFoodRazorpayPayment({
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/food/razorpay/verify-payment'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'razorpayOrderId': razorpayOrderId,
          'razorpayPaymentId': razorpayPaymentId,
          'razorpaySignature': razorpaySignature,
        }),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['verified'] == true;
      }
    } catch (e) {
      debugPrint('[FoodService] Error verifying Razorpay payment: $e');
    }
    return false;
  }

  // 5. Place Food Order with authoritative live coordinates & server billing
  Future<FoodOrder?> placeOrder({
    required String customerId,
    required String customerName,
    required String customerPhone,
    required String deliveryAddress,
    String? deliveryInstructions,
    double? deliveryLat,
    double? deliveryLng,
    required Restaurant restaurant,
    required List<CartItem> items,
    required String paymentMethod,
    String? couponCode,
    String? membershipId,
    String? idempotencyKey,
    String? razorpayOrderId,
    String? razorpayPaymentId,
    String? razorpaySignature,
  }) async {
    try {
      final payload = {
        'customerId': customerId,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'deliveryAddress': deliveryAddress,
        'deliveryInstructions': deliveryInstructions ?? '',
        if (deliveryLat != null && deliveryLng != null)
          'deliveryLatLng': {'lat': deliveryLat, 'lng': deliveryLng},
        'restaurantId': restaurant.restaurantId,
        'items': items.map((i) => i.toJson()).toList(),
        'paymentMethod': paymentMethod,
        if (couponCode != null && couponCode.isNotEmpty) 'couponCode': couponCode,
        if (membershipId != null && membershipId.isNotEmpty) 'membershipId': membershipId,
        if (idempotencyKey != null && idempotencyKey.isNotEmpty) 'idempotencyKey': idempotencyKey,
        if (razorpayOrderId != null) 'razorpayOrderId': razorpayOrderId,
        if (razorpayPaymentId != null) 'razorpayPaymentId': razorpayPaymentId,
        if (razorpaySignature != null) 'razorpaySignature': razorpaySignature,
      };

      final res = await http.post(
        Uri.parse('$baseUrl/api/food/orders'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 12));

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['order'] != null) {
          clearCart();
          return FoodOrder.fromJson(Map<String, dynamic>.from(data['order']));
        } else {
          final msg = data['message'] ?? 'Failed to place order';
          throw Exception(msg);
        }
      } else {
        final data = jsonDecode(res.body);
        final msg = data['message'] ?? 'Server returned HTTP ${res.statusCode}';
        throw Exception(msg);
      }
    } catch (e) {
      debugPrint('[FoodService] Error placing order: $e');
      rethrow;
    }
  }

  // 6. Fetch single order details
  Future<FoodOrder?> fetchOrderDetails(String orderId) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/food/orders/$orderId'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['order'] != null) {
          return FoodOrder.fromJson(Map<String, dynamic>.from(data['order']));
        }
      }
    } catch (e) {
      debugPrint('[FoodService] Error fetching order details: $e');
    }
    return null;
  }

  // 7. Fetch customer orders
  Future<List<FoodOrder>> fetchCustomerOrders(String customerId) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/food/orders/customer/$customerId'))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['orders'] is List) {
          final list = <FoodOrder>[];
          for (final raw in data['orders']) {
            try {
              if (raw is Map) {
                list.add(FoodOrder.fromJson(Map<String, dynamic>.from(raw)));
              }
            } catch (err) {
              debugPrint('[FoodService] Error parsing order in customer list: $err');
            }
          }
          return list;
        }
      }
    } catch (e) {
      debugPrint('[FoodService] Error fetching customer orders: $e');
    }
    return [];
  }

  // 8. Cancel order
  Future<bool> cancelOrder(String orderId, String reason) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/food/orders/$orderId/cancel'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'reason': reason}),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('[FoodService] Error cancelling order: $e');
    }
    return false;
  }



  // ---------------------------------------------------------------------------
  // RESTAURANT PARTNER METHODS
  // ---------------------------------------------------------------------------

  // Restaurant Partner Logout Session Invalidation
  Future<void> logoutPartner({String? restaurantId, String? phone}) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/food/partner/logout'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'restaurantId': restaurantId ?? '',
          'phone': phone ?? '',
        }),
      ).timeout(const Duration(seconds: 4));
      debugPrint('[FoodService] Partner logout response: ${res.statusCode}');
    } catch (e) {
      debugPrint('[FoodService] Partner logout note (non-fatal): $e');
    }
  }

  // Fetch partner profile by phone
  Future<Map<String, dynamic>?> getPartnerByPhone(String phone) async {
    try {
      final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
      final last10 = cleanPhone.length >= 10 ? cleanPhone.substring(cleanPhone.length - 10) : cleanPhone;
      final res = await http.get(Uri.parse('$baseUrl/api/food/partner/by-phone/$last10'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          return data;
        }
      }
    } catch (e) {
      debugPrint('[FoodService] Error getting partner by phone: $e');
    }
    return null;
  }

  // Resubmit restaurant partner application after rejection/correction request
  Future<Map<String, dynamic>> resubmitPartnerApplication(String restaurantId, Map<String, dynamic> updates) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/api/food/partner/$restaurantId/resubmit'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(updates),
      ).timeout(const Duration(seconds: 8));
      final data = jsonDecode(res.body);
      return data;
    } catch (e) {
      debugPrint('[FoodService] Error resubmitting partner application: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Register restaurant partner
  Future<Map<String, dynamic>> registerPartner({
    required String name,
    required String ownerName,
    required String phone,
    required String email,
    required String address,
    required List<String> cuisines,
    required String openingHours,
    required String fssaiNumber,
    required String bankAccount,
    required String upiId,
    required bool isVegOnly,
    required double lat,
    required double lng,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/food/partner/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'ownerName': ownerName,
          'phone': phone,
          'email': email,
          'address': address,
          'cuisines': cuisines,
          'openingHours': openingHours,
          'fssaiNumber': fssaiNumber,
          'bankAccount': bankAccount,
          'upiId': upiId,
          'isVegOnly': isVegOnly,
          'lat': lat,
          'lng': lng,
        }),
      ).timeout(const Duration(seconds: 8));

      final data = jsonDecode(res.body);
      return data;
    } catch (e) {
      debugPrint('[FoodService] Error registering partner: $e');
      return {'success': false, 'message': 'Network error registering restaurant: $e'};
    }
  }

  // Fetch restaurant partner orders
  Future<List<FoodOrder>> fetchPartnerOrders(String restaurantId) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/food/partner/$restaurantId/orders'))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['orders'] is List) {
          final list = <FoodOrder>[];
          for (final raw in data['orders']) {
            try {
              if (raw is Map) {
                list.add(FoodOrder.fromJson(Map<String, dynamic>.from(raw)));
              }
            } catch (err) {
              debugPrint('[FoodService] Error parsing order in partner list: $err');
            }
          }
          return list;
        }
      }
    } catch (e) {
      debugPrint('[FoodService] Error fetching partner orders: $e');
    }
    return [];
  }

  // Update order status by partner (accept, prepare, ready_for_pickup, reject)
  Future<bool> updatePartnerOrderStatus(String orderId, String status, {String? prepTime, String? reason}) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/food/partner/orders/$orderId/status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'status': status,
          'prepTime': prepTime,
          'reason': reason,
        }),
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('[FoodService] Error updating partner order status: $e');
    }
    return false;
  }

  // Toggle restaurant open/close status
  Future<bool> updateRestaurantOpenStatus(String restaurantId, bool isOpen) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/api/food/partner/$restaurantId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'isOpen': isOpen}),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('[FoodService] Error updating open status: $e');
    }
    return false;
  }

  // Toggle menu item availability (In Stock / Out of Stock)
  Future<bool> updateMenuItemAvailability(String restaurantId, String itemId, bool isAvailable) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/api/food/partner/$restaurantId/menu/$itemId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'isAvailable': isAvailable}),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('[FoodService] Error updating item availability: $e');
    }
    return false;
  }

  // Add new menu item with detailed response
  Future<Map<String, dynamic>> addMenuItemResult(String restaurantId, Map<String, dynamic> itemData) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/food/partner/$restaurantId/menu'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(itemData),
      ).timeout(const Duration(seconds: 8));
      final data = jsonDecode(res.body);
      return {
        'success': data['success'] == true,
        'message': data['message'] ?? (data['success'] == true ? 'Item added successfully' : 'Failed to add item'),
        'item': data['item'],
      };
    } catch (e) {
      debugPrint('[FoodService] Error adding menu item: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Add new menu item (boolean shorthand)
  Future<bool> addMenuItem(String restaurantId, Map<String, dynamic> itemData) async {
    final res = await addMenuItemResult(restaurantId, itemData);
    return res['success'] == true;
  }

  // Update menu item price (explicit newPrice or priceDelta: +10, -10, +50, -50)
  Future<bool> updateMenuItemPrice(String restaurantId, String itemId, {double? newPrice, double? priceDelta}) async {
    try {
      final payload = <String, dynamic>{};
      if (newPrice != null) payload['price'] = newPrice;
      if (priceDelta != null) {
        payload['priceDelta'] = priceDelta;
        payload['delta'] = priceDelta;
      }

      final res = await http.put(
        Uri.parse('$baseUrl/api/food/partner/$restaurantId/menu/$itemId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['success'] == true;
      } else {
        debugPrint('[FoodService] Error updating item price: status ${res.statusCode}, body: ${res.body}');
      }
    } catch (e) {
      debugPrint('[FoodService] Exception updating item price: $e');
    }
    return false;
  }

  // Adjust bulk menu item prices (+/- delta across all or category)
  Future<bool> adjustBulkPrices(String restaurantId, {required double priceDelta, String? category}) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/food/partner/$restaurantId/menu/adjust-prices'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'delta': priceDelta,
          'priceDelta': priceDelta,
          if (category != null && category != 'All') 'category': category,
        }),
      ).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['success'] == true;
      } else {
        debugPrint('[FoodService] Error bulk adjusting prices: status ${res.statusCode}, body: ${res.body}');
      }
    } catch (e) {
      debugPrint('[FoodService] Exception bulk adjusting prices: $e');
    }
    return false;
  }

  // Adjust bulk menu item prices by percentage (+/- 10%, etc.)
  Future<bool> adjustBulkPricesPercent(String restaurantId, {required double percentDelta, String? category}) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/food/partner/$restaurantId/menu/adjust-prices'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'percentDelta': percentDelta,
          if (category != null && category != 'All') 'category': category,
        }),
      ).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('[FoodService] Exception bulk adjusting percent prices: $e');
    }
    return false;
  }

  // Update menu item details with detailed response
  Future<Map<String, dynamic>> updateMenuItemDetailsResult(String restaurantId, String itemId, Map<String, dynamic> updates) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/api/food/partner/$restaurantId/menu/$itemId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(updates),
      ).timeout(const Duration(seconds: 8));
      final data = jsonDecode(res.body);
      return {
        'success': data['success'] == true,
        'message': data['message'] ?? (data['success'] == true ? 'Item updated successfully' : 'Failed to update item'),
        'item': data['item'],
      };
    } catch (e) {
      debugPrint('[FoodService] Error updating item details: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Update menu item details (boolean shorthand)
  Future<bool> updateMenuItemDetails(String restaurantId, String itemId, Map<String, dynamic> updates) async {
    final res = await updateMenuItemDetailsResult(restaurantId, itemId, updates);
    return res['success'] == true;
  }

  // Delete menu item with detailed response
  Future<Map<String, dynamic>> deleteMenuItemResult(String restaurantId, String itemId) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/api/food/partner/$restaurantId/menu/$itemId'),
      ).timeout(const Duration(seconds: 8));
      final data = jsonDecode(res.body);
      return {
        'success': data['success'] == true,
        'message': data['message'] ?? (data['success'] == true ? 'Item removed successfully' : 'Failed to remove item'),
      };
    } catch (e) {
      debugPrint('[FoodService] Error deleting menu item: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Delete menu item (boolean shorthand)
  Future<bool> deleteMenuItem(String restaurantId, String itemId) async {
    final res = await deleteMenuItemResult(restaurantId, itemId);
    return res['success'] == true;
  }

  // Upload image (base64)
  Future<String?> uploadImage({required String base64Data, required String fileName, String type = 'food'}) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/food/upload-image'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'imageData': base64Data,
          'fileName': fileName,
          'type': type,
        }),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['imageUrl'] != null) {
          return data['imageUrl'] as String;
        }
      }
    } catch (e) {
      debugPrint('[FoodService] Error uploading image: $e');
    }
    return null;
  }

  // Update partner restaurant information
  Future<bool> updatePartnerInfo(String restaurantId, Map<String, dynamic> updates) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/api/food/partner/$restaurantId/info'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(updates),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('[FoodService] Error updating partner info: $e');
    }
    return false;
  }

  /// Update exact restaurant location pin coordinates and details
  Future<bool> updatePartnerLocation(String restaurantId, {
    required double lat,
    required double lng,
    required String address,
    String? locationDetails,
  }) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/api/food/partner/$restaurantId/location'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'lat': lat,
          'lng': lng,
          'address': address,
          if (locationDetails != null) 'locationDetails': locationDetails,
        }),
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('[FoodService] Error updating partner location: $e');
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // PILOT FOOD DELIVERY METHODS
  // ---------------------------------------------------------------------------

  // Fetch orders available for pilot delivery
  Future<List<FoodOrder>> fetchPilotAvailableOrders({String? pilotId, String? vehicleType}) async {
    try {
      final uri = Uri.parse('$baseUrl/api/food/pilot/available-orders').replace(queryParameters: {
        if (pilotId != null && pilotId.isNotEmpty) 'pilotId': pilotId,
        if (vehicleType != null && vehicleType.isNotEmpty) 'vehicleType': vehicleType,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['orders'] is List) {
          final list = <FoodOrder>[];
          for (final raw in data['orders']) {
            try {
              if (raw is Map) {
                list.add(FoodOrder.fromJson(Map<String, dynamic>.from(raw)));
              }
            } catch (err) {
              debugPrint('[FoodService] Error parsing order in pilot available list: $err');
            }
          }
          return list;
        }
      }
    } catch (e) {
      debugPrint('[FoodService] Error fetching available pilot orders: $e');
    }
    return [];
  }

  // Pilot accepts food delivery
  Future<bool> pilotAcceptOrder(String orderId, String pilotId, String pilotName, String pilotPhone) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/food/pilot/orders/$orderId/accept'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'pilotId': pilotId,
          'pilotName': pilotName,
          'pilotPhone': pilotPhone,
        }),
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('[FoodService] Error pilot accepting order: $e');
    }
    return false;
  }

  // Pilot marks order picked up
  Future<bool> pilotPickupOrder(String orderId, String pilotId) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/food/pilot/orders/$orderId/pickup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'pilotId': pilotId}),
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('[FoodService] Error pilot picking up order: $e');
    }
    return false;
  }

  // Pilot delivers order with OTP verification
  Future<Map<String, dynamic>> pilotDeliverOrder(String orderId, String pilotId, String deliveryOtp) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/food/pilot/orders/$orderId/deliver'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'pilotId': pilotId,
          'deliveryOtp': deliveryOtp,
        }),
      ).timeout(const Duration(seconds: 6));
      final data = jsonDecode(res.body);
      return data;
    } catch (e) {
      debugPrint('[FoodService] Error pilot delivering order: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Pilot reports delivery failure and initiates return to restaurant
  Future<Map<String, dynamic>> reportFailedDelivery({
    required String orderId,
    required String pilotId,
    String? pilotPhone,
    required String reason,
    String? notes,
    String? evidenceUrl,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/food/pilot/orders/$orderId/report-failed-delivery'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'pilotId': pilotId,
          if (pilotPhone != null && pilotPhone.trim().isNotEmpty) 'pilotPhone': pilotPhone.trim(),
          'reason': reason,
          'notes': notes ?? '',
          'evidenceUrl': evidenceUrl ?? '',
        }),
      ).timeout(const Duration(seconds: 10));
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[FoodService] Error reporting failed delivery: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Pilot records arrival at restaurant for return
  Future<bool> pilotArrivedAtRestaurantForReturn(String orderId, String pilotId, {String? pilotPhone}) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/food/pilot/orders/$orderId/return-arrived'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'pilotId': pilotId,
          if (pilotPhone != null && pilotPhone.trim().isNotEmpty) 'pilotPhone': pilotPhone.trim(),
        }),
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('[FoodService] Error recording return arrival: $e');
    }
    return false;
  }

  // Restaurant confirms physical receipt of returned food and reveals return OTP
  Future<Map<String, dynamic>> restaurantReceiveReturn({
    required String orderId,
    required String restaurantId,
    String? staffName,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/food/restaurant/orders/$orderId/receive-return'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'restaurantId': restaurantId,
          'staffName': staffName ?? '',
        }),
      ).timeout(const Duration(seconds: 8));
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[FoodService] Error receiving return: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Pilot verifies Restaurant Return OTP
  Future<Map<String, dynamic>> verifyReturnOtp({
    required String orderId,
    required String pilotId,
    String? pilotPhone,
    required String otp,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/food/pilot/orders/$orderId/verify-return-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'pilotId': pilotId,
          if (pilotPhone != null && pilotPhone.trim().isNotEmpty) 'pilotPhone': pilotPhone.trim(),
          'otp': otp,
        }),
      ).timeout(const Duration(seconds: 10));
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[FoodService] Error verifying return OTP: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }


  // Customer updates delivery address before dispatch
  Future<bool> updateDeliveryAddress({
    required String orderId,
    required String address,
    double? lat,
    double? lng,
  }) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/api/food/orders/$orderId/address'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'address': address,
          if (lat != null && lng != null) 'deliveryLatLng': {'lat': lat, 'lng': lng},
        }),
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('[FoodService] Error updating address: $e');
    }
    return false;
  }

  // Log calling event for food order audit in Admin Console
  Future<void> logCallInitiated({
    required String orderId,
    required String callerRole,
    required String targetRole,
    required String targetPhone,
  }) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/api/food/orders/$orderId/call-log'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'callerRole': callerRole,
          'targetRole': targetRole,
          'targetPhone': targetPhone,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  // -------------------------------------------------------------
  // FOOD MEMBERSHIP (FOOD ORDER NOW ONLY)
  // -------------------------------------------------------------

  // Fetch published Platinum & other membership plans
  Future<List<FoodMembershipPlanModel>> fetchMembershipPlans() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/food/membership/plans'),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['plans'] != null) {
          final rawPlans = data['plans'] as List<dynamic>;
          return rawPlans
              .whereType<Map>()
              .map((p) => FoodMembershipPlanModel.fromJson(Map<String, dynamic>.from(p)))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[FoodService] Error fetching membership plans: $e');
    }
    return [];
  }

  // Fetch participating restaurants for Platinum Food Membership ("On Delivery" section)
  Future<List<Map<String, dynamic>>> fetchParticipatingRestaurants() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/food/membership/participating-restaurants'),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['restaurants'] != null) {
          final rawList = data['restaurants'] as List<dynamic>;
          return rawList.whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList();
        }
      }
    } catch (e) {
      debugPrint('[FoodService] Error fetching participating restaurants: $e');
    }
    return [];
  }

  // Fetch customer active membership status and benefits
  Future<CustomerFoodMembershipModel?> fetchCustomerMembership(String customerId, {String? phone, String? membershipId}) async {
    try {
      final qParams = <String, String>{
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (membershipId != null && membershipId.isNotEmpty) 'membershipId': membershipId,
      };
      final uri = Uri.parse('$baseUrl/api/food/membership/my-membership/$customerId')
          .replace(queryParameters: qParams.isNotEmpty ? qParams : null);

      final res = await http.get(uri).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['hasActiveMembership'] == true && data['membership'] != null) {
          return CustomerFoodMembershipModel.fromJson(Map<String, dynamic>.from(data['membership']));
        }
      }
    } catch (e) {
      debugPrint('[FoodService] Error fetching customer membership: $e');
    }
    return null;
  }

  // Create payment order for membership subscription
  Future<Map<String, dynamic>?> createMembershipOrder({
    required String customerId,
    required String customerPhone,
    required String customerName,
    required String planId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/food/membership/order/create'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customerId': customerId,
          'customerPhone': customerPhone,
          'customerName': customerName,
          'planId': planId,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        if (data['success'] == true) {
          final orderMap = data['order'] is Map ? Map<String, dynamic>.from(data['order']) : <String, dynamic>{};
          orderMap['orderId'] = orderMap['orderId'] ?? data['orderId'] ?? data['gatewayOrderId'];
          orderMap['keyId'] = orderMap['keyId'] ?? data['keyId'] ?? 'rzp_live_Ta9cOGnIySuBCb';
          orderMap['amount'] = orderMap['amount'] ?? data['amount'] ?? data['amountInPaise'] ?? 100;
          orderMap['amountInPaise'] = data['amountInPaise'] ?? orderMap['amount'] ?? 100;
          return orderMap;
        } else if (data['alreadyActive'] == true) {
          return {
            'alreadyActive': true,
            'message': data['message'] ?? 'You already have an active StayDriv Platinum Food Membership.',
            'membership': data['membership'],
          };
        } else {
          throw Exception(data['message'] ?? 'Failed to create membership order');
        }
      } else {
        throw Exception(data['message'] ?? 'Server returned HTTP ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('[FoodService] Error creating membership order: $e');
      rethrow;
    }
  }

  // Explicitly record payment failure or cancellation for audit and clean retry
  Future<void> recordMembershipPaymentFailure({
    String? gatewayOrderId,
    String? customerId,
    String? customerPhone,
    dynamic errorCode,
    String? errorMessage,
    String? reason,
  }) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/api/food/membership/order/record-failure'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'gatewayOrderId': gatewayOrderId ?? '',
          'customerId': customerId ?? '',
          'customerPhone': customerPhone ?? '',
          'errorCode': errorCode?.toString() ?? '',
          'errorMessage': errorMessage ?? '',
          'reason': reason ?? '',
        }),
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[FoodService] Error recording failure: $e');
    }
  }

  // Verify payment and activate membership
  Future<CustomerFoodMembershipModel?> verifyMembershipPayment({
    required String customerId,
    required String customerPhone,
    required String customerName,
    required String planId,
    required String gatewayOrderId,
    required String gatewayPaymentId,
    String? gatewaySignature,
    String paymentMethod = 'online',
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/food/membership/order/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customerId': customerId,
          'customerPhone': customerPhone,
          'customerName': customerName,
          'planId': planId,
          'gatewayOrderId': gatewayOrderId,
          'gatewayPaymentId': gatewayPaymentId,
          'gatewaySignature': gatewaySignature ?? '',
          'paymentMethod': paymentMethod,
        }),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['membership'] != null) {
          return CustomerFoodMembershipModel.fromJson(Map<String, dynamic>.from(data['membership']));
        }
      }
    } catch (e) {
      debugPrint('[FoodService] Error verifying membership payment: $e');
    }
    return null;
  }

  // Calculate authoritative checkout discount for food orders
  Future<Map<String, dynamic>?> calculateFoodCheckoutDiscount({
    required String customerId,
    required String restaurantId,
    required double subtotal,
    required double deliveryFee,
    List<Map<String, dynamic>> items = const [],
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/food/membership/calculate-discount'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customerId': customerId,
          'restaurantId': restaurantId,
          'subtotal': subtotal,
          'deliveryFee': deliveryFee,
          'items': items,
          'orderType': 'food_order', // Strictly Food Order Now
        }),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint('[FoodService] Error calculating food discount: $e');
    }
    return null;
  }

  // Renew membership
  Future<bool> renewMembership({
    required String customerId,
    required String membershipId,
    String? planId,
    String? transactionId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/food/membership/renew'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customerId': customerId,
          'membershipId': membershipId,
          'planId': planId,
          'transactionId': transactionId,
        }),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('[FoodService] Error renewing membership: $e');
    }
    return false;
  }

  // -------------------------------------------------------------
  // RESTAURANT PAYMENT DETAILS & SETTLEMENTS
  // -------------------------------------------------------------

  // Fetch restaurant payment & bank details (masked)
  Future<Map<String, dynamic>?> fetchRestaurantPaymentDetails(String restaurantId) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/food/partner/$restaurantId/payment-details'),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['paymentDetails'] != null) {
          return data['paymentDetails'] as Map<String, dynamic>;
        }
      }
    } catch (e) {
      debugPrint('[FoodService] Error fetching restaurant payment details: $e');
    }
    return null;
  }

  // Update restaurant payment & bank details
  Future<Map<String, dynamic>> updateRestaurantPaymentDetails(String restaurantId, Map<String, dynamic> paymentData) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/api/food/partner/$restaurantId/payment-details'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(paymentData),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'message': data['message'] ?? 'Payment details updated', 'paymentDetails': data['paymentDetails']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to update payment details'};
      }
    } catch (e) {
      debugPrint('[FoodService] Error updating restaurant payment details: $e');
      return {'success': false, 'message': 'Network error updating payment details'};
    }
  }

  // Fetch restaurant settlement and sales summary
  Future<Map<String, dynamic>?> fetchRestaurantSettlementSummary(String restaurantId) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/food/partner/$restaurantId/settlements/summary'),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['summary'] != null) {
          return data['summary'] as Map<String, dynamic>;
        }
      }
    } catch (e) {
      debugPrint('[FoodService] Error fetching restaurant settlement summary: $e');
    }
    return null;
  }

  // Fetch restaurant settlement history
  Future<List<Map<String, dynamic>>> fetchRestaurantSettlements(String restaurantId) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/food/partner/$restaurantId/settlements'),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['settlements'] != null) {
          return List<Map<String, dynamic>>.from(data['settlements']);
        }
      }
    } catch (e) {
      debugPrint('[FoodService] Error fetching restaurant settlements: $e');
    }
    return [];
  }

  // Fetch transaction-wise delivered orders breakdown
  Future<List<Map<String, dynamic>>> fetchRestaurantSalesBreakdown(String restaurantId) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/food/partner/$restaurantId/sales-breakdown'),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['orders'] != null) {
          return List<Map<String, dynamic>>.from(data['orders']);
        }
      }
    } catch (e) {
      debugPrint('[FoodService] Error fetching sales breakdown: $e');
    }
    return [];
  }
}


