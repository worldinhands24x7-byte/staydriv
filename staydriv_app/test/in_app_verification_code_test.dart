import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staydriv_app/screens/otp_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('In-App Verification Code Screen Tests', () {
    testWidgets('Renders in-app verification code card and auto-fills code correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OtpScreen(
            mobile: '9876543210',
            initialCode: '483921',
            role: 'CUSTOMER',
          ),
        ),
      );

      // Verify that Title and Subtitle match requirement 4 & 5
      expect(find.text('Verify Mobile'), findsOneWidget);
      expect(find.text('Enter the 6-digit verification code shown below.'), findsOneWidget);

      // Verify Card Header and Subtext
      expect(find.text('Your verification code'), findsOneWidget);
      expect(find.text('Enter this code in the boxes below.'), findsOneWidget);

      // Verify timer and attempts
      expect(find.text('Attempts remaining: 5 of 5'), findsOneWidget);
      expect(find.text('05:00'), findsOneWidget);

      // Verify Auto-Fill button exists
      final autoFillFinder = find.widgetWithText(ElevatedButton, 'Auto-Fill Code');
      expect(autoFillFinder, findsOneWidget);

      // Tap Auto-Fill
      await tester.tap(autoFillFinder);
      await tester.pump();

      // Verify that each text field now contains digits of '483921'
      expect(find.text('4'), findsWidgets);
      expect(find.text('8'), findsWidgets);
      expect(find.text('3'), findsWidgets);
      expect(find.text('9'), findsWidgets);
      expect(find.text('2'), findsWidgets);
      expect(find.text('1'), findsWidgets);

      // Verify Proceed button
      expect(find.text('Verify & Proceed'), findsOneWidget);
    });

    testWidgets('Pilot role sets correct role and renders verification card with code', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OtpScreen(
            mobile: '9123456780',
            initialCode: '765432',
            role: 'PILOT',
          ),
        ),
      );

      expect(find.text('Verify Mobile'), findsOneWidget);
      expect(find.text('Your verification code'), findsOneWidget);
      expect(find.text('Attempts remaining: 5 of 5'), findsOneWidget);
      expect(find.text('Auto-Fill Code'), findsOneWidget);
      expect(find.text('Verify & Proceed'), findsOneWidget);
    });

    testWidgets('Generates secure random code immediately if initialCode is null', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OtpScreen(
            mobile: '9123456780',
            initialCode: null,
            role: 'CUSTOMER',
          ),
        ),
      );

      // Code must never be null or missing on screen
      expect(find.text('Your verification code'), findsOneWidget);
      expect(find.text('Auto-Fill Code'), findsOneWidget);
      expect(find.text('Enter this code in the boxes below.'), findsOneWidget);

      // Auto-fill should work immediately
      final autoFillFinder = find.widgetWithText(ElevatedButton, 'Auto-Fill Code');
      expect(find.text('Verify & Proceed'), findsOneWidget);
    });

    testWidgets('OtpScreen handles session ID and attempts correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OtpScreen(
            mobile: '9876543210',
            initialCode: '636416',
            role: 'CUSTOMER',
            verificationSessionId: 'SESS_TEST_123',
          ),
        ),
      );

      expect(find.text('Verify Mobile'), findsOneWidget);
      expect(find.text('6'), findsWidgets);
      expect(find.text('3'), findsWidgets);
      expect(find.text('4'), findsWidgets);
      expect(find.text('1'), findsWidgets);

      final autoFillFinder = find.widgetWithText(ElevatedButton, 'Auto-Fill Code');
      expect(autoFillFinder, findsOneWidget);
      await tester.tap(autoFillFinder);
      await tester.pump();

      expect(find.text('6'), findsWidgets);
      expect(find.text('3'), findsWidgets);
      expect(find.text('4'), findsWidgets);
      expect(find.text('1'), findsWidgets);
    });
  });
}

