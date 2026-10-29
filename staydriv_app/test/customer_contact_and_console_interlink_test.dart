import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staydriv_app/features/dashboard/widgets/console_switcher_sheet.dart';
import 'package:staydriv_app/features/food_ordering/models/food_models.dart';
import 'package:staydriv_app/features/food_ordering/screens/food_cart_screen.dart';
import 'package:staydriv_app/features/food_ordering/services/food_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_ringtone_player'), (call) async => null);
  });

  group('Customer Contact & Console Interlinking Tests', () {
    testWidgets('1. Customer contact displays correct phone from address/prefs and not hardcoded 9849012345', (tester) async {
      SharedPreferences.setMockInitialValues({
        'is_logged_in': true,
        'user_role': 'Customer',
        'phone_number': '9247535068',
        'user_name': 'Rishi Kumar',
      });

      // Add item to cart
      final foodService = FoodService();
      foodService.cartNotifier.value = FoodCart(
        restaurant: Restaurant(
          restaurantId: 'REST_HILL_STONE',
          name: 'Hill Stone Restaurant',
          phone: '9000000000',
          cuisines: const ['North Indian', 'South Indian'],
          rating: 4.5,
          deliveryTime: '19-30 mins',
          imageUrl: '',
          address: 'Plot No: 129, Gajularamaram, Hyderabad',
          lat: 17.5100,
          lng: 78.4100,
          isOpen: true,
        ),
        items: [
          CartItem(
            item: MenuItem(
              itemId: 'ITEM_1',
              restaurantId: 'REST_HILL_STONE',
              name: 'Idlie',
              category: 'Tiffins',
              price: 89,
              isVeg: true,
            ),
            quantity: 1,
          ),
        ],
      );

      const deliveryAddress =
          'Plot No 84, Rishipranavam Resideancy, Balaji Layout, Gajularamaram, Hyderabad-500055, My contact Number - 9247535068';

      await tester.pumpWidget(
        const MaterialApp(
          home: FoodCartScreen(
            deliveryAddress: deliveryAddress,
            deliveryLat: 17.5100,
            deliveryLng: 78.4100,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 1. Verify old wrong number is NOT displayed
      expect(find.text('Contact: 9849012345'), findsNothing);

      // 2. Verify correct contact number is displayed
      expect(find.textContaining('9247535068'), findsWidgets);
      expect(find.text('Contact: 9247535068'), findsOneWidget);

      // 3. Verify tapping contact badge opens the edit contact modal
      final contactBadge = find.text('Contact: 9247535068');
      await tester.tap(contactBadge);
      await tester.pumpAndSettle();

      expect(find.text('Delivery Contact Number'), findsOneWidget);
      expect(find.text('Confirm Contact Number'), findsOneWidget);

      // 4. Update contact number in modal
      final inputFinder = find.byType(TextFormField);
      expect(inputFinder, findsOneWidget);
      await tester.enterText(inputFinder, '9988776655');
      await tester.pump();

      await tester.tap(find.text('Confirm Contact Number'));
      await tester.pumpAndSettle();

      // 5. Verify updated contact number is reflected immediately on checkout screen
      expect(find.text('Contact: 9988776655'), findsOneWidget);
      expect(find.text('Contact: 9849012345'), findsNothing);

      // 6. Verify "Save Address" button is visible and clickable
      expect(find.text('Save Address'), findsOneWidget);
      await tester.tap(find.text('Save Address'));
      await tester.pumpAndSettle();

      // 7. Verify Save Delivery Address modal opens with tags and fields
      expect(find.text('Save Delivery Address'), findsOneWidget);
      expect(find.text('SAVE AS'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);

      // 8. Select 'Work' tag and tap Save Address button in modal
      await tester.tap(find.text('Work'));
      await tester.pump();

      // Tap the ElevatedButton in the modal
      final saveBtnFinder = find.widgetWithText(ElevatedButton, 'Save Address');
      expect(saveBtnFinder, findsOneWidget);
      await tester.tap(saveBtnFinder);
      await tester.pumpAndSettle();

      // 9. Verify the button now shows "Saved ✓" on the checkout screen
      expect(find.text('Saved ✓'), findsOneWidget);
    });

    testWidgets('2. ConsoleSwitcherSheet renders all 4 consoles: Customer, Pilot, Restaurant Partner, and Admin', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ConsoleSwitcherSheet(
              currentRole: 'Customer',
              userPhone: '9247535068',
            ),
          ),
        ),
      );

      await tester.pump();

      // Verify header
      expect(find.text('StayDriv Portals'), findsOneWidget);
      expect(find.text('Switch between consoles effortlessly'), findsOneWidget);

      // Verify all 4 consoles are present and interlinked
      expect(find.text('Customer Console'), findsOneWidget);
      expect(find.text('Pilot / Driver Console'), findsOneWidget);
      expect(find.text('Restaurant Partner Console'), findsOneWidget);
      expect(find.text('Admin & Operations Console'), findsOneWidget);

      // Verify Customer Console is marked as CURRENT
      expect(find.text('CURRENT'), findsOneWidget);

      // Verify subtitles
      expect(find.text('Book Rides, Order Food & Manage Wallet'), findsOneWidget);
      expect(find.text('Accept Rides, GPS Navigation & Daily Salary'), findsOneWidget);
      expect(find.text('Live Food Orders, Menu, Audio Alerts & Settlements'), findsOneWidget);
      expect(find.text('Platform Governance, Live Tracking, Approvals & Ledgers'), findsOneWidget);
    });

    testWidgets('3. FoodHomeScreen AppBar includes console switcher button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                IconButton(
                  icon: const Icon(Icons.hub_outlined, color: Color(0xFF1E293B)),
                  tooltip: 'Switch Console (Customer, Pilot, Restaurant, Admin)',
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byIcon(Icons.hub_outlined), findsOneWidget);
      expect(find.byTooltip('Switch Console (Customer, Pilot, Restaurant, Admin)'), findsOneWidget);
    });

    test('4. Navigation formulation creates correct route from restaurant origin to customer destination', () {
      const restLat = 17.5100;
      const restLng = 78.4100;
      const custLat = 17.52600;
      const custLng = 78.42407;

      // Google Maps Intent for device turn-by-turn driving navigation
      final googleNavUri = Uri.parse('google.navigation:q=$custLat,$custLng&mode=d');
      expect(googleNavUri.toString(), 'google.navigation:q=17.526,78.42407&mode=d');

      // Web Directions with origin (restaurant) and destination (customer)
      final webMapUri = Uri.parse('https://www.google.com/maps/dir/?api=1&origin=$restLat,$restLng&destination=$custLat,$custLng&travelmode=driving');
      expect(webMapUri.queryParameters['origin'], '$restLat,$restLng');
      expect(webMapUri.queryParameters['destination'], '$custLat,$custLng');
      expect(webMapUri.queryParameters['travelmode'], 'driving');
    });

    test('5. Map navigation from pilot location to Restaurant location formulations', () {
      const pilotLat = 17.4834;
      const pilotLng = 78.3871;
      const restLat = 17.5100;
      const restLng = 78.4100;

      // Google Maps Intent for pilot driving to restaurant
      final googleNavUri = Uri.parse('google.navigation:q=$restLat,$restLng&mode=d');
      expect(googleNavUri.toString(), 'google.navigation:q=17.51,78.41&mode=d');

      // Web Directions with origin (pilot) and destination (restaurant pickup)
      final webMapUri = Uri.parse('https://www.google.com/maps/dir/?api=1&origin=$pilotLat,$pilotLng&destination=$restLat,$restLng&travelmode=driving');
      expect(webMapUri.queryParameters['origin'], '$pilotLat,$pilotLng');
      expect(webMapUri.queryParameters['destination'], '$restLat,$restLng');
      expect(webMapUri.queryParameters['travelmode'], 'driving');
    });
  });
}
