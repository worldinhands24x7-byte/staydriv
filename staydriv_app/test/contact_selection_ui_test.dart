import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:staydriv_app/features/ride_selection/screens/ride_selection_screen.dart';

void main() {
  group('Pickup Details Contact Selection UI Flow Tests', () {
    testWidgets('1. Renders customer details, Select Contact button and Use My Details toggle', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RideSelectionScreen(
            serviceType: 'parcel',
            userName: 'Vivek Sharma',
            phoneNumber: '9247535068',
            initialPickupAddress: 'Golden Palm URC, Tirumalagiri',
            initialPickupLatLng: LatLng(17.4834, 78.3871),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify header and labels
      expect(find.text('Add contact details'), findsOneWidget);
      expect(find.text('Customer Name'), findsOneWidget);
      expect(find.text('Mobile Number'), findsOneWidget);
      expect(find.text('+91'), findsOneWidget);

      // Verify compact action buttons
      expect(find.text('Select Contact'), findsOneWidget);
      expect(find.text('Use My Details'), findsOneWidget);
      expect(find.byIcon(Icons.contact_phone_rounded), findsOneWidget);

      // Pre-filled with logged-in user details
      expect(find.text('Vivek Sharma'), findsOneWidget);
      expect(find.text('9247535068'), findsOneWidget);

      // Confirm button is enabled with valid 10-digit number
      final confirmBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Confirm pickup details'));
      expect(confirmBtn.onPressed, isNotNull);
    });

    testWidgets('2. Toggling Use My Details unchecks and clears fields for manual entry', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RideSelectionScreen(
            serviceType: 'parcel',
            userName: 'Vivek Sharma',
            phoneNumber: '9247535068',
            initialPickupAddress: 'Golden Palm URC, Tirumalagiri',
            initialPickupLatLng: LatLng(17.4834, 78.3871),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Use My Details" to uncheck
      await tester.tap(find.text('Use My Details'));
      await tester.pumpAndSettle();

      // Fields should be cleared
      expect(find.text('Vivek Sharma'), findsNothing);
      expect(find.text('9247535068'), findsNothing);

      // Confirm button should be disabled when fields are empty
      var confirmBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Confirm pickup details'));
      expect(confirmBtn.onPressed, isNull);

      // Find by hint
      final nameField = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.hintText == 'Enter name',
      );
      final phoneField = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.hintText == 'Enter 10-digit mobile number',
      );

      // Enter manual recipient name & invalid mobile number
      await tester.enterText(nameField, 'Rahul Verma');
      await tester.enterText(phoneField, '12345');
      await tester.pumpAndSettle();

      // Should show validation error message
      expect(find.text('Please enter a valid 10-digit mobile number'), findsOneWidget);
      confirmBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Confirm pickup details'));
      expect(confirmBtn.onPressed, isNull);

      // Enter valid Indian mobile number starting with 9
      await tester.enterText(phoneField, '9876543210');
      await tester.pumpAndSettle();

      // Validation error disappears and button becomes enabled
      expect(find.text('Please enter a valid 10-digit mobile number'), findsNothing);
      confirmBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Confirm pickup details'));
      expect(confirmBtn.onPressed, isNotNull);
    });

    testWidgets('3. Tapping Use My Details again restores user profile credentials', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RideSelectionScreen(
            serviceType: 'parcel',
            userName: 'Vivek Sharma',
            phoneNumber: '9247535068',
            initialPickupAddress: 'Golden Palm URC, Tirumalagiri',
            initialPickupLatLng: LatLng(17.4834, 78.3871),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Uncheck
      await tester.tap(find.text('Use My Details'));
      await tester.pumpAndSettle();
      expect(find.text('Vivek Sharma'), findsNothing);

      // Check again
      await tester.tap(find.text('Use My Details'));
      await tester.pumpAndSettle();

      // Credentials restored
      expect(find.text('Vivek Sharma'), findsOneWidget);
      expect(find.text('9247535068'), findsOneWidget);
    });
  });
}
