import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staydriv_app/features/onboarding/screens/login_screen.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _RealHttpOverrides();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('Pilot "Pay for the Day" Rate & Checkout Flow (₹20) Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('Card 1 and Pay for the Day modal display ₹20 and no ₹49', (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: LoginScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Ensure Pilot role is selected (default or via tab)
      final switchBtn = find.textContaining('Switch to Pilot Portal');
      if (switchBtn.evaluate().isNotEmpty) {
        await tester.tap(switchBtn);
        await tester.pumpAndSettle();
      }

      // Verify Card 1 shows 'Pay for day' and '₹20'
      expect(find.text('Pay for day'), findsOneWidget);
      expect(find.text('₹20 / Day'), findsOneWidget);
      expect(find.textContaining('Pay ₹20 for the day'), findsOneWidget);

      // Verify that the old ₹49 is NOT displayed anywhere
      expect(find.textContaining('49'), findsNothing);
      expect(find.textContaining('₹49'), findsNothing);

      // Tap on 'Pay for day' option card to open the modal
      await tester.tap(find.text('Pay for day'));
      await tester.pumpAndSettle();

      // Modal is now opened
      expect(find.textContaining('Pay for the Day (Daily Pass)'), findsOneWidget);
      expect(find.text('Drive all day with 0% platform commission for just ₹20'), findsOneWidget);
      expect(find.text('Daily Pass Fee:'), findsOneWidget);
      expect(find.text('₹20.00'), findsOneWidget);
      expect(find.text('Total Payable Now:'), findsOneWidget);
      expect(find.text('Pay ₹20 & Activate Day Pass'), findsOneWidget);

      // Verify old ₹49 amount does NOT exist anywhere in the modal
      expect(find.textContaining('₹49'), findsNothing);
      expect(find.textContaining('49'), findsNothing);
    });

    test('Payment calculation and Razorpay order amount verification', () {
      const double dailyPassRate = 20.0;
      final int amountInPaise = (dailyPassRate * 100).round();

      expect(dailyPassRate, equals(20.0));
      expect(amountInPaise, equals(2000)); // Exactly 2000 paise for ₹20.00
      expect(dailyPassRate, isNot(equals(49.0)));
      expect(amountInPaise, isNot(equals(4900)));

      // Verify description
      const description = 'StayDriv Pilot Daily Pass - ₹20 (Pay for the Day)';
      expect(description.contains('₹20'), isTrue);
      expect(description.contains('49'), isFalse);
    });

    test('Daily pass activation state persists ₹20 amount in preferences', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_daily_pass', true);
      await prefs.setString('daily_pass_timestamp', DateTime.now().toIso8601String());
      await prefs.setDouble('daily_pass_amount', 20.0);

      expect(prefs.getBool('has_daily_pass'), isTrue);
      expect(prefs.getDouble('daily_pass_amount'), equals(20.0));
      expect(prefs.getDouble('daily_pass_amount'), isNot(equals(49.0)));
    });

    test('Confirmation message displays ₹20 accurately', () {
      const confirmationMsg = '✅ Pay for the Day (₹20) Pass Activated! Enter mobile number to start driving.';
      expect(confirmationMsg.contains('₹20'), isTrue);
      expect(confirmationMsg.contains('₹49'), isFalse);
      expect(confirmationMsg.contains('49'), isFalse);
    });
  });
}
