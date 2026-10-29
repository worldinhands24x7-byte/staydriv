import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestNavBar({required bool isDriver, required ValueChanged<int> onTabSelected, int currentTab = 0}) {
    Widget buildNavItem(int index, IconData icon, String label, {bool isFood = false}) {
      final isActive = currentTab == index;
      final activeColor = isFood ? const Color(0xFFEA580C) : const Color(0xFF1E3A8A);
      final activeBg = isFood ? const Color(0xFFEA580C).withOpacity(0.12) : const Color(0xFF2563EB).withOpacity(0.12);
      final inactiveColor = isFood ? const Color(0xFFEA580C).withOpacity(0.85) : const Color(0xFF64748B);

      return Expanded(
        child: Semantics(
          label: label.replaceAll('\n', ' '),
          selected: isActive,
          button: true,
          child: InkWell(
            onTap: () => onTabSelected(index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
              decoration: BoxDecoration(
                color: isActive ? activeBg : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    color: isActive ? activeColor : inactiveColor,
                    size: isFood ? 25 : 24,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: isActive ? FontWeight.w700 : (isFood ? FontWeight.w600 : FontWeight.w500),
                      color: isActive ? activeColor : inactiveColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return MaterialApp(
      home: Scaffold(
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0x1FC3C6D7), width: 1)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 6.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: isDriver
                    ? [
                        buildNavItem(0, Icons.home_rounded, 'Home'),
                        buildNavItem(1, Icons.explore_rounded, 'Activity'),
                        buildNavItem(2, Icons.person_rounded, 'Profile'),
                        buildNavItem(3, Icons.help_outline_rounded, 'Help'),
                      ]
                    : [
                        buildNavItem(0, Icons.home_rounded, 'Home'),
                        buildNavItem(1, Icons.restaurant_rounded, 'Food Order\nNow', isFood: true),
                        buildNavItem(2, Icons.explore_rounded, 'Activity'),
                        buildNavItem(3, Icons.person_rounded, 'Profile'),
                        buildNavItem(4, Icons.help_outline_rounded, 'Help'),
                      ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('Customer App displays 5 items with Food Order Now at position 2', (WidgetTester tester) async {
    int currentTab = 0;
    await tester.pumpWidget(
      buildTestNavBar(
        isDriver: false,
        onTabSelected: (idx) => currentTab = idx,
        currentTab: currentTab,
      ),
    );
    await tester.pumpAndSettle();

    // Verify all 5 navigation tabs exist
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Food Order\nNow'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Help'), findsOneWidget);

    // Verify Food Order Now icon is present
    expect(find.byIcon(Icons.restaurant_rounded), findsOneWidget);

    // Tap Food Order Now
    await tester.tap(find.text('Food Order\nNow'));
    expect(currentTab, 1);
  });

  testWidgets('Pilot / Driver Console removes Food Order Now completely and displays only 4 items', (WidgetTester tester) async {
    int currentTab = 0;
    await tester.pumpWidget(
      buildTestNavBar(
        isDriver: true,
        onTabSelected: (idx) => currentTab = idx,
        currentTab: currentTab,
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify exact 4 items in Pilot Console
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Help'), findsOneWidget);

    // 2. CRITICAL: Verify Food Order Now is completely ABSENT from Pilot Console
    expect(find.text('Food Order\nNow'), findsNothing);
    expect(find.byIcon(Icons.restaurant_rounded), findsNothing);

    // 3. Test tapping Activity (now index 1 for Driver)
    await tester.tap(find.text('Activity'));
    expect(currentTab, 1);
  });
}
