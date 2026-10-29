import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staydriv_app/core/socket_service.dart';
import 'package:staydriv_app/features/food_ordering/models/food_models.dart';
import 'package:staydriv_app/features/food_ordering/screens/pilot_food_delivery_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SocketService.disableForTesting = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_ringtone_player'), (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/url_launcher'), (call) async => true);
  });

  testWidgets('Pilot Food Delivery Card - Idle state shows listening & Test Buzzer button', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PilotFoodDeliveryCard(
            pilotId: 'pilot-123',
            pilotName: 'Pilot Tester',
            pilotPhone: '9876543210',
            vehicleType: 'Bike',
            isOnline: true,
            autoStartPolling: false, // Prevents background socket & timer loops in unit test
          ),
        ),
      ),
    );
    await tester.pump();

    // 1. Verify idle listening label and Test Buzzer button are rendered
    expect(find.text('Food Delivery: Ready & Listening'), findsOneWidget);
    expect(find.text('Test Buzzer'), findsOneWidget);

    // 2. Tap Test Buzzer
    await tester.tap(find.text('Test Buzzer'));
    await tester.pump();

    // 3. Verify state changes to Buzzer Playing...
    expect(find.text('Buzzer Playing...'), findsOneWidget);

    // 4. Tap again to cancel test buzzer
    await tester.tap(find.text('Buzzer Playing...'));
    await tester.pump();

    expect(find.text('Test Buzzer'), findsOneWidget);
  });

  testWidgets('Pilot Food Delivery Card - Incoming order triggers loud buzzer & countdown & mute & pass', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PilotFoodDeliveryCard(
            pilotId: 'pilot-123',
            pilotName: 'Pilot Tester',
            pilotPhone: '9876543210',
            vehicleType: 'Bike',
            isOnline: true,
            autoStartPolling: false,
          ),
        ),
      ),
    );
    await tester.pump();

    final state = tester.state(find.byType(PilotFoodDeliveryCard)) as dynamic;

    // Simulate incoming order
    final testOrder = FoodOrder.fromJson({
      'orderId': 'ORD-FOOD-8899',
      'restaurantId': 'REST-1',
      'restaurantName': 'Hill Stone Restaurant',
      'restaurantAddress': 'Miyapur, Hyderabad',
      'restaurantPhone': '9111222333',
      'customerName': 'Rishi P',
      'customerPhone': '9988776655',
      'deliveryAddress': 'Plot No - 84, Balaji Layout, Gajularamaram, Hyderabad',
      'deliveryFee': 40.0,
      'subtotal': 320.0,
      'platformFee': 15.0,
      'taxes': 16.0,
      'orderStatus': 'accepted',
      'items': [
        {'name': 'Chicken Biryani', 'price': 320, 'quantity': 1}
      ]
    });

    state.addAvailableTaskForTest(testOrder);
    await tester.pump();

    // 1. Verify card appears
    expect(find.text('Food Delivery Available'), findsOneWidget);
    expect(find.textContaining('Hill Stone Restaurant'), findsOneWidget);
    expect(find.textContaining('Plot No - 84'), findsOneWidget);

    // 2. Verify loud buzzer banner, countdown, and Mute button
    expect(find.text('🚨 LOUD BUZZER RINGING'), findsOneWidget);
    expect(find.text('⏱️ 45s'), findsOneWidget);
    expect(find.text('Mute 🔕'), findsOneWidget);
    expect(state.isRinging, isTrue);

    // 3. Test Mute toggle
    await tester.tap(find.text('Mute 🔕'));
    await tester.pump();

    expect(find.text('🔔 Food Delivery Alert (Muted)'), findsOneWidget);
    expect(find.text('Unmute 🔔'), findsOneWidget);
    expect(state.isRinging, isFalse);

    // 4. Test Unmute toggle
    await tester.tap(find.text('Unmute 🔔'));
    await tester.pump();

    expect(find.text('🚨 LOUD BUZZER RINGING'), findsOneWidget);
    expect(find.text('Mute 🔕'), findsOneWidget);
    expect(state.isRinging, isTrue);

    // 5. Test Pass button
    expect(find.text('Pass'), findsOneWidget);
    await tester.tap(find.text('Pass'));
    await tester.pump();

    // Buzzer must be stopped and order dismissed back to listening
    expect(state.isRinging, isFalse);
    expect(find.text('Food Delivery: Ready & Listening'), findsOneWidget);
  });

  testWidgets('Pilot Food Delivery Card - Ready for Pickup banner and Navigate to Customer location button', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PilotFoodDeliveryCard(
            pilotId: 'pilot-123',
            pilotName: 'Pilot Tester',
            pilotPhone: '9876543210',
            vehicleType: 'Bike',
            isOnline: true,
            autoStartPolling: false,
          ),
        ),
      ),
    );
    await tester.pump();

    final state = tester.state(find.byType(PilotFoodDeliveryCard)) as dynamic;

    // Simulate active order where restaurant marked Ready for Pickup
    final activeOrder = FoodOrder.fromJson({
      'orderId': 'FD_1792556382268_DE7DF3',
      'restaurantId': 'REST-1',
      'restaurantName': 'Hill Stone Restaurant',
      'restaurantAddress': 'Miyapur, Hyderabad',
      'restaurantPhone': '9111222333',
      'customerName': 'StayDriv Customer',
      'customerPhone': '9247535068',
      'deliveryAddress': 'Plot No 84, Rishipranavam Resideancy, Balaji Layout, Gajulramaram, Hyderabad-500055',
      'deliveryLat': 17.52600,
      'deliveryLng': 78.42407,
      'deliveryFee': 40.0,
      'pilotEarnings': 40.0,
      'orderStatus': 'ready_for_pickup',
      'items': [
        {'name': 'Idlie', 'price': 89, 'quantity': 1}
      ]
    });

    state.setActiveDeliveryOrderForTest(activeOrder);
    await tester.pump();

    // 1. Verify Active Card renders with restaurant and customer details
    expect(find.textContaining('FD_1792556382268_DE7DF3'), findsOneWidget);
    expect(find.textContaining('Hill Stone Restaurant'), findsWidgets);
    expect(find.textContaining('StayDriv Customer'), findsOneWidget);

    // 2. Verify Ready for Pickup notification banner
    expect(find.text('FOOD READY FOR PICKUP!'), findsOneWidget);
    expect(find.textContaining('Go to kitchen counter & tap Confirm Pickup'), findsOneWidget);

    // 3. Verify Confirm Pickup and Complete (OTP) buttons
    expect(find.text('Confirm Pickup'), findsOneWidget);
    expect(find.text('Complete (OTP)'), findsOneWidget);

    // 4. Verify Navigate to Customer Location button is inserted with consistent styling
    expect(find.text('Navigate to Customer Location'), findsOneWidget);

    // 5. Tap Navigate to Customer Location
    await tester.tap(find.text('Navigate to Customer Location'));
    await tester.pump();
  });
}
