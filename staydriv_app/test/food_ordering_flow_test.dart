import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staydriv_app/features/food_ordering/models/food_models.dart';
import 'package:staydriv_app/features/food_ordering/services/food_service.dart';
import 'package:staydriv_app/features/food_ordering/services/food_location_service.dart';
import 'package:staydriv_app/features/food_ordering/screens/food_home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Food Ordering Models & Logic Tests', () {
    test('Restaurant JSON deserialization works correctly', () {
      final json = {
        'restaurantId': 'rest_123',
        'name': 'Paradise Biryani',
        'cuisines': ['Hyderabadi', 'Biryani', 'Mughlai'],
        'rating': 4.6,
        'ratingCount': 1250,
        'deliveryTime': '30-35 mins',
        'deliveryFee': 35.0,
        'imageUrl': 'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=800',
        'address': 'MG Road, Secunderabad, Hyderabad',
        'isVegOnly': false,
        'isOpen': true,
      };

      final rest = Restaurant.fromJson(json);
      expect(rest.restaurantId, 'rest_123');
      expect(rest.name, 'Paradise Biryani');
      expect(rest.rating, 4.6);
      expect(rest.deliveryFee, 35.0);
      expect(rest.isVegOnly, false);
      expect(rest.isOpen, true);
    });

    test('MenuItem JSON deserialization works correctly', () {
      final json = {
        'itemId': 'item_456',
        'restaurantId': 'rest_123',
        'name': 'Hyderabadi Mutton Biryani',
        'description': 'Fragrant basmati rice cooked with tender mutton and authentic spices',
        'price': 380.0,
        'imageUrl': 'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=800',
        'category': 'Biryani',
        'isVeg': false,
        'isAvailable': true,
      };

      final item = MenuItem.fromJson(json);
      expect(item.itemId, 'item_456');
      expect(item.name, 'Hyderabadi Mutton Biryani');
      expect(item.price, 380.0);
      expect(item.isVeg, false);
      expect(item.isAvailable, true);
    });

    test('FoodOrder JSON deserialization handles String and num prepTime safely', () {
      final jsonWithStringPrepTime = {
        'orderId': 'FD_1792335286512_8C8382',
        'customerId': 'CUST_123',
        'customerName': 'Test Customer',
        'customerPhone': '9876543210',
        'deliveryAddress': 'Madhapur, Hyderabad',
        'restaurantId': 'REST_CHUTNEYS_02',
        'restaurantName': 'Chutneys Flavours',
        'items': [
          {
            'itemId': 'ITEM_1',
            'name': 'Guntur Idli',
            'price': 75,
            'quantity': 1,
            'isVeg': true,
          }
        ],
        'subtotal': 75,
        'deliveryFee': 25,
        'platformFee': 15,
        'taxes': 4,
        'totalAmount': 119,
        'paymentMethod': 'cod',
        'paymentStatus': 'pending',
        'orderStatus': 'placed',
        'deliveryOtp': '3725',
        'prepTime': '25 mins', // Real MongoDB string value!
        'createdAt': '2026-10-18T14:54:46.514Z',
      };

      final order1 = FoodOrder.fromJson(jsonWithStringPrepTime);
      expect(order1.orderId, 'FD_1792335286512_8C8382');
      expect(order1.prepTime, '25 mins');
      expect(order1.totalAmount, 119.0);
      expect(order1.items.length, 1);
      expect(order1.items.first.item.name, 'Guntur Idli');

      // Test with numeric prepTime
      final jsonWithNumPrepTime = Map<String, dynamic>.from(jsonWithStringPrepTime);
      jsonWithNumPrepTime['prepTime'] = 20;
      final order2 = FoodOrder.fromJson(jsonWithNumPrepTime);
      expect(order2.prepTime, '20');

      // Test with missing/null prepTime
      final jsonWithNullPrepTime = Map<String, dynamic>.from(jsonWithStringPrepTime);
      jsonWithNullPrepTime.remove('prepTime');
      final order3 = FoodOrder.fromJson(jsonWithNullPrepTime);
      expect(order3.prepTime, '25 mins');
    });

    test('FoodCart correctly computes item subtotal, delivery fee, platform fee, taxes, and grand total', () {
      final rest = Restaurant(
        restaurantId: 'rest_123',
        name: 'Paradise Biryani',
        phone: '9876543210',
        address: 'MG Road, Secunderabad',
        deliveryFee: 30.0,
      );

      final item1 = MenuItem(
        itemId: 'item_1',
        restaurantId: 'rest_123',
        name: 'Mutton Biryani',
        description: 'Delicious',
        price: 380.0,
        category: 'Biryani',
        isVeg: false,
      );

      final item2 = MenuItem(
        itemId: 'item_2',
        restaurantId: 'rest_123',
        name: 'Mirchi Ka Salan',
        description: 'Spicy gravy',
        price: 120.0,
        category: 'Biryani',
        isVeg: true,
      );

      final cart = FoodCart(
        restaurant: rest,
        items: [
          CartItem(item: item1, quantity: 2), // 760
          CartItem(item: item2, quantity: 1), // 120
        ],
      );

      expect(cart.totalItemCount, 3);
      expect(cart.subtotal, 880.0);

      // Calculations:
      // Subtotal = 880.0
      // Delivery fee = 30.0
      // Platform fee = 15.0
      // GST (5% of 880) = 44.0
      // Total = 880 + 30 + 15 + 44 = 969.0
      expect(cart.deliveryFee, 30.0);
      expect(cart.platformFee, 15.0);
      expect(cart.taxes, 44.0);
      expect(cart.grandTotal, 969.0);
    });

    test('FoodService manages cart state reactively', () {
      final service = FoodService();
      service.clearCart();
      expect(service.cartNotifier.value.isEmpty, true);

      final rest = Restaurant(
        restaurantId: 'rest_test',
        name: 'Test Rest',
        phone: '9876543210',
        address: 'Hitech City',
      );

      final item = MenuItem(
        itemId: 'item_10',
        restaurantId: 'rest_test',
        name: 'Chicken 65',
        description: 'Crispy fried chicken',
        price: 260.0,
        category: 'Snacks',
        isVeg: false,
      );

      service.addToCart(rest, item);
      expect(service.cartNotifier.value.totalItemCount, 1);
      expect(service.cartNotifier.value.subtotal, 260.0);

      service.addToCart(rest, item);
      expect(service.cartNotifier.value.totalItemCount, 2);
      expect(service.cartNotifier.value.subtotal, 520.0);

      service.removeFromCart(item);
      expect(service.cartNotifier.value.totalItemCount, 1);
      expect(service.cartNotifier.value.subtotal, 260.0);

      service.clearCart();
      expect(service.cartNotifier.value.isEmpty, true);
    });
  });

  group('Food Ordering UI Widget Tests', () {
    test('DeliveryLocation model handles JSON and getters correctly', () {
      const loc = DeliveryLocation(
        address: 'Flat 402, Highrise Heights, Madhapur, Hyderabad, Telangana',
        shortAddress: 'Madhapur, Hyderabad',
        latitude: 17.4483,
        longitude: 78.3800,
        type: 'home',
        landmark: 'Near Cyber Towers',
      );

      expect(loc.displayTitle, 'Home');
      expect(loc.displaySubtitle, 'Near Cyber Towers, Flat 402, Highrise Heights, Madhapur, Hyderabad, Telangana');

      final json = loc.toJson();
      final fromJson = DeliveryLocation.fromJson(json);
      expect(fromJson.latitude, 17.4483);
      expect(fromJson.longitude, 78.3800);
      expect(fromJson.type, 'home');
      expect(fromJson.shortAddress, 'Madhapur, Hyderabad');
    });

    testWidgets('FoodHomeScreen renders search, categories, and restaurant listings', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FoodHomeScreen(),
          ),
        ),
      );

      // Initial loading state
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Advance clock past the network timeout to allow fallback data to populate
      await tester.pump(const Duration(seconds: 8));
      await tester.pump(const Duration(seconds: 2));

      // Verify delivery address bar and search bar are present
      expect(find.byIcon(Icons.location_on_rounded), findsWidgets);
      expect(find.byType(TextField), findsOneWidget);

      // Verify category headers
      expect(find.text('What would you like to eat?'), findsOneWidget);
      expect(find.text('Biryani'), findsWidgets);

      // Verify Veg toggle and Restaurant list header
      expect(find.text('VEG'), findsOneWidget);
      expect(find.text('Featured & Nearby Restaurants'), findsOneWidget);
    });
  });
}
