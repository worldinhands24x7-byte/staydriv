import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Welcome Screen displays all 4 role options including Restaurant Partner', (WidgetTester tester) async {
    String selectedRole = 'Customer';

    Widget buildCustomerRoleTab(void Function(void Function()) setState) {
      final isSelected = selectedRole == 'Customer';
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => selectedRole = 'Customer'),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFEFF5FF) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? const Color(0xFF1E60FF) : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 22, child: Icon(Icons.directions_car_rounded, size: 18)),
                const SizedBox(height: 5),
                const SizedBox(height: 26, child: Center(child: Text('Customer'))),
              ],
            ),
          ),
        ),
      );
    }

    Widget buildPilotRoleTab(void Function(void Function()) setState) {
      final isSelected = selectedRole == 'Pilot';
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => selectedRole = 'Pilot'),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFEFF5FF) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? const Color(0xFF1E60FF) : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 22, child: Icon(Icons.handshake_rounded, size: 20)),
                const SizedBox(height: 5),
                const SizedBox(height: 26, child: Center(child: Text('Pilot'))),
              ],
            ),
          ),
        ),
      );
    }

    Widget buildRestaurantPartnerRoleTab(void Function(void Function()) setState) {
      final isSelected = selectedRole == 'Restaurant Partner';
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => selectedRole = 'Restaurant Partner'),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFEFF5FF) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? const Color(0xFF1E60FF) : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 22, child: Icon(Icons.restaurant_rounded, size: 20)),
                const SizedBox(height: 5),
                const SizedBox(height: 26, child: Center(child: Text('Restaurant\nPartner', textAlign: TextAlign.center))),
              ],
            ),
          ),
        ),
      );
    }

    Widget buildAdminRoleTab(void Function(void Function()) setState) {
      final isSelected = selectedRole == 'Admin';
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => selectedRole = 'Admin'),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFEFF5FF) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? const Color(0xFF1E60FF) : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 22, child: Icon(Icons.admin_panel_settings_rounded, size: 20)),
                const SizedBox(height: 5),
                const SizedBox(height: 26, child: Center(child: Text('Admin'))),
              ],
            ),
          ),
        ),
      );
    }

    Widget testWidget = StatefulBuilder(
      builder: (context, setState) {
        return MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Row(
                    children: [
                      buildCustomerRoleTab(setState),
                      const SizedBox(width: 4),
                      buildPilotRoleTab(setState),
                      const SizedBox(width: 4),
                      buildRestaurantPartnerRoleTab(setState),
                      const SizedBox(width: 4),
                      buildAdminRoleTab(setState),
                    ],
                  ),
                ),
                Text(
                  selectedRole == 'Restaurant Partner'
                      ? 'Restaurant Partner Portal'
                      : (selectedRole == 'Admin' ? 'Admin Portal' : 'Welcome to StayDriv'),
                ),
              ],
            ),
          ),
        );
      },
    );

    await tester.pumpWidget(testWidget);
    await tester.pumpAndSettle();

    // 1. Verify all 4 role options exist
    expect(find.text('Customer'), findsOneWidget);
    expect(find.text('Pilot'), findsOneWidget);
    expect(find.text('Restaurant\nPartner'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);

    // 2. Verify restaurant icon exists
    expect(find.byIcon(Icons.restaurant_rounded), findsOneWidget);

    // 3. Tap Restaurant Partner
    await tester.tap(find.text('Restaurant\nPartner'));
    await tester.pumpAndSettle();

    // 4. Verify title updates to Restaurant Partner Portal
    expect(selectedRole, 'Restaurant Partner');
    expect(find.text('Restaurant Partner Portal'), findsOneWidget);
  });
}
