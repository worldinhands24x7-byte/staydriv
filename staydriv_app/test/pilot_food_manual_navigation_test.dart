import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staydriv_app/core/socket_service.dart';
import 'package:staydriv_app/features/food_ordering/models/food_models.dart';
import 'package:staydriv_app/features/food_ordering/screens/pilot_food_delivery_card.dart';
import 'package:staydriv_app/features/navigation/screens/pilot_navigation_screen.dart';

class TestNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushedRoutes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
    super.didPush(route, previousRoute);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SocketService.disableForTesting = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_ringtone_player'), (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/url_launcher'), (call) async => true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/geolocator'), (call) async => null);
  });

  final sampleAcceptedOrder = FoodOrder.fromJson({
    'orderId': 'ORD-FOOD-MANUAL-001',
    'restaurantId': 'REST-HYD-01',
    'restaurantName': 'Bawarchi Grand',
    'restaurantAddress': 'Main Road, RTC X Roads, Hyderabad',
    'restaurantPhone': '9876500001',
    'restaurantLat': 17.4065,
    'restaurantLng': 78.4983,
    'customerName': 'Suresh Kumar',
    'customerPhone': '9876500002',
    'deliveryAddress': 'Flat 302, Sri Balaji Layout, Gajularamaram, Hyderabad',
    'deliveryLat': 17.5186,
    'deliveryLng': 78.4112,
    'deliveryFee': 65.0,
    'pilotEarnings': 65.0,
    'subtotal': 450.0,
    'platformFee': 20.0,
    'taxes': 22.5,
    'orderStatus': 'accepted',
    'items': [
      {'name': 'Special Mutton Biryani', 'price': 450, 'quantity': 1}
    ]
  });

  testWidgets('Pilot Food Delivery: Accepting order and viewing order details does NOT automatically open navigation', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final navObserver = TestNavigatorObserver();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [navObserver],
        home: const Scaffold(
          body: PilotFoodDeliveryCard(
            pilotId: 'pilot-test-456',
            pilotName: 'Pilot Manual Test',
            pilotPhone: '9000000001',
            vehicleType: 'Bike',
            isOnline: true,
            autoStartPolling: false,
          ),
        ),
      ),
    );
    await tester.pump();

    final state = tester.state(find.byType(PilotFoodDeliveryCard)) as dynamic;

    // Simulate active accepted order directly
    state.setActiveDeliveryOrderForTest(sampleAcceptedOrder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Verify Pilot is on the Order Details screen
    expect(find.textContaining('Active Food Delivery'), findsOneWidget);
    expect(find.text('Restaurant: Bawarchi Grand'), findsOneWidget);
    expect(find.text('Navigate to Restaurant Pickup'), findsOneWidget);

    // 2. CRITICAL VERIFICATION: No navigation route was pushed automatically
    // The initial route is the only route in the navigator stack
    expect(navObserver.pushedRoutes.length, 1); // Only root route
    expect(find.byType(PilotNavigationScreen), findsNothing);

    // 3. Rebuild / re-pump multiple times (e.g. lifecycle resume / socket tick simulation)
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));

    // Must still NOT open navigation automatically
    expect(navObserver.pushedRoutes.length, 1);
    expect(find.byType(PilotNavigationScreen), findsNothing);
    expect(find.text('Navigate to Restaurant Pickup'), findsOneWidget);

    ScaffoldMessenger.of(tester.element(find.byType(PilotFoodDeliveryCard))).clearSnackBars();
  });

  testWidgets('Pilot Food Delivery: Manual click on Navigate to Restaurant launches navigation with restaurant coordinates', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final navObserver = TestNavigatorObserver();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [navObserver],
        home: const Scaffold(
          body: PilotFoodDeliveryCard(
            pilotId: 'pilot-test-456',
            pilotName: 'Pilot Manual Test',
            pilotPhone: '9000000001',
            vehicleType: 'Bike',
            isOnline: true,
            autoStartPolling: false,
          ),
        ),
      ),
    );
    await tester.pump();

    final state = tester.state(find.byType(PilotFoodDeliveryCard)) as dynamic;
    state.setActiveDeliveryOrderForTest(sampleAcceptedOrder);
    await tester.pump();

    // Verify restaurant navigation button exists
    final navRestaurantBtn = find.text('Navigate to Restaurant Pickup');
    expect(navRestaurantBtn, findsOneWidget);
    expect(navObserver.pushedRoutes.length, 1);

    // Tap Navigate to Restaurant explicitly
    await tester.tap(navRestaurantBtn);
    await tester.pump();

    // Verify exactly one navigation route was pushed upon explicit manual click
    expect(navObserver.pushedRoutes.length, 2);
    final pushedRoute = navObserver.pushedRoutes.last;
    expect(pushedRoute is MaterialPageRoute, true);

    // Build the pushed route to inspect the PilotNavigationScreen parameters
    final cardContext = tester.element(find.byType(PilotFoodDeliveryCard));
    final widgetBuilt = (pushedRoute as MaterialPageRoute).builder(cardContext);
    expect(widgetBuilt is PilotNavigationScreen, true);

    final navScreen = widgetBuilt as PilotNavigationScreen;
    expect(navScreen.booking['status'], 'heading_to_pickup');
    expect(navScreen.booking['restaurantLat'], 17.4065);
    expect(navScreen.booking['restaurantLng'], 78.4983);
    expect(navScreen.booking['isFoodOrder'], true);
    expect(navScreen.booking['pickup'], 'Main Road, RTC X Roads, Hyderabad');

    ScaffoldMessenger.of(tester.element(find.byType(PilotFoodDeliveryCard))).clearSnackBars();
  });

  testWidgets('Pilot Food Delivery: Order picked up does NOT open navigation; manual click on Navigate to Customer launches navigation with customer coordinates', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final navObserver = TestNavigatorObserver();
    final pickedUpOrder = sampleAcceptedOrder.copyWith(orderStatus: 'out_for_delivery');

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [navObserver],
        home: const Scaffold(
          body: PilotFoodDeliveryCard(
            pilotId: 'pilot-test-456',
            pilotName: 'Pilot Manual Test',
            pilotPhone: '9000000001',
            vehicleType: 'Bike',
            isOnline: true,
            autoStartPolling: false,
          ),
        ),
      ),
    );
    await tester.pump();

    final state = tester.state(find.byType(PilotFoodDeliveryCard)) as dynamic;
    state.setActiveDeliveryOrderForTest(pickedUpOrder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Navigation must NOT be opened automatically after pickup
    expect(navObserver.pushedRoutes.length, 1);
    expect(find.byType(PilotNavigationScreen), findsNothing);

    // 2. Both Customer Navigation button and Complete button must be visible
    final navCustomerBtn = find.text('Navigate to Customer Location');
    expect(navCustomerBtn, findsOneWidget);
    expect(find.text('Complete (OTP)'), findsOneWidget);

    // 3. Tap Navigate to Customer explicitly
    await tester.tap(navCustomerBtn);
    await tester.pump();

    // 4. Verify route pushed upon explicit click
    expect(navObserver.pushedRoutes.length, 2);
    final pushedRoute = navObserver.pushedRoutes.last;
    expect(pushedRoute is MaterialPageRoute, true);

    final cardContext = tester.element(find.byType(PilotFoodDeliveryCard));
    final widgetBuilt = (pushedRoute as MaterialPageRoute).builder(cardContext);
    expect(widgetBuilt is PilotNavigationScreen, true);

    final navScreen = widgetBuilt as PilotNavigationScreen;
    expect(navScreen.booking['status'], 'heading_to_drop');
    expect(navScreen.booking['deliveryLat'], 17.5186);
    expect(navScreen.booking['deliveryLng'], 78.4112);
    expect(navScreen.booking['isFoodOrder'], true);
    expect(navScreen.booking['drop'], 'Flat 302, Sri Balaji Layout, Gajularamaram, Hyderabad');

    ScaffoldMessenger.of(tester.element(find.byType(PilotFoodDeliveryCard))).clearSnackBars();
  });
}
