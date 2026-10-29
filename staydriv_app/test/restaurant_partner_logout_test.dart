import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staydriv_app/core/api_client.dart';
import 'package:staydriv_app/core/firebase_service.dart';
import 'package:staydriv_app/features/food_ordering/screens/restaurant_partner_console_screen.dart';
import 'package:staydriv_app/features/onboarding/screens/login_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_ringtone_player'), (call) async => null);
  });

  group('Restaurant Partner Console Logout Tests', () {
    testWidgets('1. Logout icon button is functional, immediately responds, clears session, and redirects to LoginScreen', (tester) async {
      SharedPreferences.setMockInitialValues({
        'is_logged_in': true,
        'user_role': 'Restaurant Partner',
        'user_name': 'Test Biryani House',
        'phone_number': '9010922111',
        'jwt_token': 'jwt_test_token_123',
        'auth_token': 'auth_test_token_123',
        'mock_uid': 'uid_partner_123',
        'restaurant_data': '{"id":"REST_100","name":"Test Biryani House"}',
        'partner_phone': '9010922111',
      });
      ApiClient.setAuthToken('auth_test_token_123');
      FirebaseService.setMockUid('uid_partner_123');

      final restaurantData = {
        'restaurantId': 'REST_100',
        'name': 'Test Biryani House',
        'phone': '9010922111',
        'isOpen': true,
      };

      await tester.pumpWidget(
        MaterialApp(
          home: RestaurantPartnerConsoleScreen(restaurantData: restaurantData),
        ),
      );
      await tester.pump();

      // Verify logout icon button exists in top-right AppBar
      final logoutBtn = find.byKey(const Key('restaurant_partner_logout_button'));
      expect(logoutBtn, findsOneWidget);

      // Tap logout icon
      await tester.tap(logoutBtn);
      await tester.pump();

      // Verify loading indicator is displayed while logout is processing
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      // Complete async logout tasks
      await tester.pumpAndSettle();

      // Verify redirect to LoginScreen with Restaurant Partner role
      expect(find.byType(LoginScreen), findsOneWidget);

      // Verify session and token data are cleared
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('is_logged_in'), isNot(true));
      expect(prefs.getString('jwt_token'), isNull);
      expect(prefs.getString('auth_token'), isNull);
      expect(prefs.getString('restaurant_data'), isNull);
      expect(prefs.getString('partner_phone'), isNull);
      expect(prefs.getString('mock_uid'), isNull);
      expect(ApiClient.authToken, isNull);
    });

    testWidgets('2. Logout button prevents duplicate taps and debounce works', (tester) async {
      SharedPreferences.setMockInitialValues({
        'is_logged_in': true,
        'user_role': 'Restaurant Partner',
      });

      final restaurantData = {
        'restaurantId': 'REST_200',
        'name': 'Paradise Biryani',
        'phone': '9010922222',
        'isOpen': true,
      };

      await tester.pumpWidget(
        MaterialApp(
          home: RestaurantPartnerConsoleScreen(restaurantData: restaurantData),
        ),
      );
      await tester.pump();

      final logoutBtn = find.byKey(const Key('restaurant_partner_logout_button'));
      expect(logoutBtn, findsOneWidget);

      // Double-tap rapidly
      await tester.tap(logoutBtn);
      await tester.pump();

      // Once logging out, IconButton is replaced by CircularProgressIndicator, preventing repeated taps
      expect(find.byKey(const Key('restaurant_partner_logout_button')), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('3. Clears navigation stack so previous routes cannot be restored via back navigation', (tester) async {
      SharedPreferences.setMockInitialValues({
        'is_logged_in': true,
        'user_role': 'Restaurant Partner',
      });

      final restaurantData = {
        'restaurantId': 'REST_300',
        'name': 'Biryani Express',
        'phone': '9010922333',
        'isOpen': true,
      };

      // Wrap in a Navigator stack with an initial dummy route
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RestaurantPartnerConsoleScreen(restaurantData: restaurantData),
                  ),
                );
              },
              child: const Text('Open Console'),
            ),
          ),
        ),
      );

      // Navigate into console
      await tester.tap(find.text('Open Console'));
      await tester.pumpAndSettle();
      expect(find.byType(RestaurantPartnerConsoleScreen), findsOneWidget);

      // Tap logout
      await tester.tap(find.byKey(const Key('restaurant_partner_logout_button')));
      await tester.pumpAndSettle();

      // Should be at LoginScreen
      expect(find.byType(LoginScreen), findsOneWidget);

      // Verify that canPop is false (cannot pop back to console or dummy route)
      final NavigatorState navigator = tester.state(find.byType(Navigator));
      expect(navigator.canPop(), isFalse);
    });
  });
}
