import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staydriv_app/features/food_ordering/models/food_models.dart';
import 'package:staydriv_app/features/food_ordering/services/restaurant_order_ringtone_service.dart';
import 'package:staydriv_app/features/food_ordering/widgets/incoming_order_alert_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_ringtone_player'), (call) async => null);
  });

  group('RestaurantOrderRingtoneService Unit Tests', () {
    late RestaurantOrderRingtoneService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = RestaurantOrderRingtoneService();
      await service.init();
      service.stopOrderAlert(forceAll: true);
    });

    tearDown(() {
      service.stopOrderAlert(forceAll: true);
    });

    test('Initializes with default sound enabled and 100% volume', () {
      expect(service.soundEnabled, isTrue);
      expect(service.volume, equals(1.0));
      expect(service.isRinging, isFalse);
      expect(service.activeOrderIds, isEmpty);
    });

    test('startOrderAlert starts ringtone and adds order to active queue', () {
      service.startOrderAlert('FD_TEST_101', summary: 'Test order');
      expect(service.isRinging, isTrue);
      expect(service.isRingingNotifier.value, isTrue);
      expect(service.activeOrderIds.contains('FD_TEST_101'), isTrue);
      expect(service.activeOrdersCountNotifier.value, equals(1));
    });

    test('Multiple concurrent orders are queued without loss or duplication', () {
      service.startOrderAlert('FD_TEST_101');
      service.startOrderAlert('FD_TEST_102');
      service.startOrderAlert('FD_TEST_103');
      // Duplicate should not increase count
      service.startOrderAlert('FD_TEST_101');

      expect(service.isRinging, isTrue);
      expect(service.activeOrderIds.length, equals(3));
      expect(service.activeOrdersCountNotifier.value, equals(3));
      expect(service.activeOrderIds.contains('FD_TEST_101'), isTrue);
      expect(service.activeOrderIds.contains('FD_TEST_102'), isTrue);
      expect(service.activeOrderIds.contains('FD_TEST_103'), isTrue);
    });

    test('Acknowledging one order keeps ringtone ringing if other orders remain', () {
      service.startOrderAlert('FD_TEST_101');
      service.startOrderAlert('FD_TEST_102');

      // Acknowledge order 1
      service.stopOrderAlert(orderId: 'FD_TEST_101');
      expect(service.isRinging, isTrue);
      expect(service.activeOrderIds.length, equals(1));
      expect(service.activeOrderIds.contains('FD_TEST_102'), isTrue);

      // Acknowledge order 2 (queue now empty)
      service.stopOrderAlert(orderId: 'FD_TEST_102');
      expect(service.isRinging, isFalse);
      expect(service.activeOrderIds, isEmpty);
    });

    test('Disabling sound mutes active ringtone and prevents new alerts', () async {
      service.startOrderAlert('FD_TEST_101');
      expect(service.isRinging, isTrue);

      await service.setSoundEnabled(false);
      expect(service.soundEnabled, isFalse);
      expect(service.isRinging, isFalse);

      // Attempting alert while muted does not start audio
      service.startOrderAlert('FD_TEST_102');
      expect(service.isRinging, isFalse);

      // Re-enabling sound restores functionality
      await service.setSoundEnabled(true);
      expect(service.soundEnabled, isTrue);
    });

    test('Volume setting persists and clamps between 0.1 and 1.0', () async {
      await service.setVolume(0.7);
      expect(service.volume, closeTo(0.7, 0.01));
      expect(service.volumeNotifier.value, closeTo(0.7, 0.01));

      // Clamp test
      await service.setVolume(1.5);
      expect(service.volume, equals(1.0));

      await service.setVolume(0.01);
      expect(service.volume, equals(0.1));
    });

    test('Test ringtone triggers audio sample and toggles off', () {
      service.testRingtone();
      expect(service.isTesting, isTrue);
      expect(service.isRinging, isTrue);

      // Tapping again stops test immediately
      service.testRingtone();
      expect(service.isTesting, isFalse);
      expect(service.isRinging, isFalse);
    });
  });

  group('IncomingOrderAlertSheet Widget Tests', () {
    late FoodOrder testOrder;

    setUp(() {
      testOrder = FoodOrder(
        orderId: 'FD_WIDGET_999',
        customerId: 'CUST_1',
        customerName: 'Aarav Patel',
        customerPhone: '9876543210',
        deliveryAddress: 'Flat 402, Green Towers, Madhapur, Hyderabad',
        deliveryLat: 17.4485,
        deliveryLng: 78.3741,
        restaurantId: 'REST_1',
        restaurantName: 'Biryani Express',
        restaurantPhone: '9000011111',
        restaurantAddress: 'Hitech City, Hyderabad',
        restaurantLat: 17.4500,
        restaurantLng: 78.3800,
        items: [
          CartItem(
            item: MenuItem(
              itemId: 'ITM_1',
              restaurantId: 'REST_1',
              name: 'Hyderabadi Chicken Dum Biryani',
              category: 'Biryani',
              price: 280,
              isVeg: false,
            ),
            quantity: 2,
          ),
          CartItem(
            item: MenuItem(
              itemId: 'ITM_2',
              restaurantId: 'REST_1',
              name: 'Mirchi Ka Salan',
              category: 'Gravy',
              price: 60,
              isVeg: true,
            ),
            quantity: 1,
          ),
        ],
        subtotal: 620,
        packagingFee: 20,
        deliveryFee: 40,
        platformFee: 15,
        taxes: 35,
        totalAmount: 730,
        finalPayable: 730,
        paymentMethod: 'online',
        paymentStatus: 'paid',
        orderStatus: 'placed',
        createdAt: DateTime.now().subtract(const Duration(seconds: 30)),
      );
    });

    testWidgets('Renders all incoming order details, order ID, items, and total amount', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IncomingOrderAlertSheet(
              order: testOrder,
              currentQueueIndex: 1,
              totalQueueCount: 2,
              onAccept: (order, prepTime) {},
              onReject: (order, reason) {},
              onMute: () {},
              onClose: () {},
            ),
          ),
        ),
      );

      // Verify header and ringing banner
      expect(find.text('🚨 NEW INCOMING ORDER (RINGING)'), findsOneWidget);
      expect(find.text('1 of 2'), findsOneWidget);
      expect(find.text('#FD_WIDGET_999'), findsOneWidget);
      expect(find.text('PAID ONLINE'), findsOneWidget);

      // Verify customer and items
      expect(find.text('Aarav Patel'), findsOneWidget);
      expect(find.textContaining('Green Towers, Madhapur'), findsOneWidget);
      expect(find.text('Hyderabadi Chicken Dum Biryani'), findsOneWidget);
      expect(find.text('TOTAL: ₹730'), findsOneWidget);

      // Verify buttons
      expect(find.text('Accept Order'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
      expect(find.text('Silence'), findsOneWidget);
    });

    testWidgets('Tapping Accept Order submits with selected prep time', (tester) async {
      String? acceptedPrepTime;
      FoodOrder? acceptedOrder;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IncomingOrderAlertSheet(
              order: testOrder,
              onAccept: (order, prepTime) {
                acceptedOrder = order;
                acceptedPrepTime = prepTime;
              },
              onReject: (order, reason) {},
              onMute: () {},
              onClose: () {},
            ),
          ),
        ),
      );

      // Select '35 mins' chip
      await tester.tap(find.text('35 mins'));
      await tester.pump(const Duration(milliseconds: 200));

      // Tap Accept Order
      await tester.tap(find.text('Accept Order'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(acceptedOrder?.orderId, equals('FD_WIDGET_999'));
      expect(acceptedPrepTime, equals('35 mins'));
    });

    testWidgets('Tapping Reject opens rejection reason dialog', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IncomingOrderAlertSheet(
              order: testOrder,
              onAccept: (order, prepTime) {},
              onReject: (order, reason) {},
              onMute: () {},
              onClose: () {},
            ),
          ),
        ),
      );

      // Tap Reject button
      await tester.tap(find.text('Reject'));
      await tester.pump(const Duration(milliseconds: 200));

      // Verify reason dialog
      expect(find.text('Specify Rejection Reason'), findsOneWidget);
      expect(find.text('Confirm Reject'), findsOneWidget);
    });

    testWidgets('OrderAlertSettingsDialog displays toggle, volume slider and test button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OrderAlertSettingsDialog(),
          ),
        ),
      );

      expect(find.text('Order Alert Settings'), findsOneWidget);
      expect(find.text('Incoming Order Ringtone'), findsOneWidget);
      expect(find.text('Alert Volume'), findsOneWidget);
      expect(find.text('Test Ringtone (4s)'), findsOneWidget);
      expect(find.text('Browser & Device Notifications'), findsOneWidget);
    });
  });
}
