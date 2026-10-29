import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staydriv_app/core/network_monitor.dart';
import 'package:staydriv_app/features/dashboard/screens/home_screen.dart';

void main() {
  testWidgets('Pilot Console displays both responsive header toggle switch and on-duty card switch', (WidgetTester tester) async {
    // Compact mobile screen size (360x740)
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(
          userRole: 'Driver',
          userName: 'Ramesh Pilot',
          phoneNumber: '9010922111',
        ),
      ),
    );

    // Initial frame
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify 'Driver Console' header is present
    expect(find.text('Driver Console'), findsOneWidget);

    // Verify 'Active Vehicle Status' is present
    expect(find.text('Active Vehicle Status'), findsOneWidget);

    // Verify 'PILOT IS OFFLINE' or 'PILOT IS ONLINE' card is present
    expect(find.textContaining('PILOT IS'), findsOneWidget);
    expect(find.text('Switch ON to receive bookings'), findsOneWidget);

    // Verify switches are found (at least the header switch, the 2 preference switches, and the duty card switch)
    final switches = find.byType(Switch);
    expect(switches, findsWidgets);
    expect(switches.evaluate().length, greaterThanOrEqualTo(3));

    final ex = tester.takeException();
    NetworkMonitor().dispose();
    expect(ex, isNull);
  });
}
