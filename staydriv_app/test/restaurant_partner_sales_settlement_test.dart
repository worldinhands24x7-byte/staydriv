import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staydriv_app/core/api_client.dart';
import 'package:staydriv_app/core/firebase_service.dart';
import 'package:staydriv_app/features/food_ordering/screens/restaurant_partner_console_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_ringtone_player'), (call) async => null);
  });

  group('Restaurant Partner Console - Sales, Returned Orders & Settlement History', () {
    testWidgets('Sales Tab displays Summary Cards, Order-Wise Breakdown & Settlement History', (tester) async {
      SharedPreferences.setMockInitialValues({
        'is_logged_in': true,
        'user_role': 'Restaurant Partner',
        'user_name': 'Hill Stone Restaurant',
        'phone_number': '9010922111',
        'jwt_token': 'jwt_test_token_123',
        'auth_token': 'auth_test_token_123',
        'mock_uid': 'uid_partner_123',
        'restaurant_data': '{"id":"REST_100","name":"Hill Stone Restaurant"}',
        'partner_phone': '9010922111',
      });
      ApiClient.setAuthToken('auth_test_token_123');
      FirebaseService.setMockUid('uid_partner_123');

      final restaurantData = {
        'restaurantId': 'REST_100',
        'name': 'Hill Stone Restaurant',
        'phone': '9010922111',
        'isOpen': true,
        'commissionRate': 15.0
      };

      await tester.pumpWidget(
        MaterialApp(
          home: RestaurantPartnerConsoleScreen(restaurantData: restaurantData),
        ),
      );
      await tester.pump();

      // Find Sales tab in top navigation
      final salesTab = find.text('Sales');
      expect(salesTab, findsOneWidget);

      // Tap on Sales tab
      await tester.tap(salesTab);
      await tester.pumpAndSettle();

      // Verify core summary cards exist
      expect(find.text('Sales & Settlements'), findsOneWidget);
      expect(find.text('Total Gross Sales'), findsOneWidget);
      expect(find.text('Delivered Orders'), findsOneWidget);
      expect(find.text('Net Earnings'), findsOneWidget);
      expect(find.text('Amount Paid (Settled)'), findsOneWidget);
      expect(find.text('Pending Settlement'), findsOneWidget);

      // Verify sub-tab selectors exist
      expect(find.textContaining('Settlement History'), findsOneWidget);
      expect(find.textContaining('Order-Wise Breakdown'), findsOneWidget);
    });
  });
}
