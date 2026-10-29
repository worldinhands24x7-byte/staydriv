import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staydriv_app/core/network_monitor.dart';
import 'package:staydriv_app/core/booking_manager.dart';
import 'package:staydriv_app/core/socket_service.dart';
import 'package:staydriv_app/features/dashboard/screens/home_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'active_role': 'Driver',
      'user_role': 'Driver',
      'selected_vehicle': 'Bike',
      'pilot_name': 'pavan',
      'user_name': 'pavan',
      'pilot_vehicle_plate': 'TS09 5936',
      'pilot_vehicle_color': 'red',
      'pilot_earnings': 5000.0,
    });
  });

  testWidgets('Pilot Partner Console respects Seniority 1, 2, 3, and 4 order', (WidgetTester tester) async {
    // Set screen size tall enough to lay out console
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      try {
        NetworkMonitor().dispose();
      } catch (_) {}
      try {
        BookingManager().setDriverOnline(false);
      } catch (_) {}
      try {
        SocketService().disconnect();
      } catch (_) {}
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(
          userName: 'pavan',
          phoneNumber: '9490440281',
          selectedVehicle: 'Bike',
          userRole: 'Driver',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Tap Profile tab in bottom navigation bar to switch to Profile view
    final profileTab = find.byIcon(Icons.person_rounded);
    if (profileTab.evaluate().isNotEmpty) {
      await tester.tap(profileTab);
      await tester.pumpAndSettle();
    }

    // --- SENIORITY 1 VERIFICATION ---
    expect(find.text('Personal Information'), findsOneWidget);
    expect(find.text('Full Name'), findsOneWidget);
    expect(find.text('Mobile Number'), findsAtLeastNWidgets(1));
    expect(find.text('Email Address'), findsOneWidget);
    expect(find.text('Date of Birth'), findsOneWidget);

    // --- SENIORITY 2 VERIFICATION ---
    expect(find.text('Select Vehicle Type'), findsOneWidget);
    expect(find.text('Bike'), findsAtLeastNWidgets(1));
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('Car'), findsOneWidget);
    expect(find.text('Mini Truck'), findsOneWidget);
    expect(find.text('Heavy Truck'), findsOneWidget);
    expect(find.text('Vehicle & Duty Console'), findsOneWidget);
    expect(find.text('Assigned Vehicle Type'), findsOneWidget);
    expect(find.text('VEHICLE IDENTIFICATION'), findsOneWidget);
    expect(find.text('Pilot Documents'), findsOneWidget);
    expect(find.text('Aadhaar Card - Front'), findsOneWidget);
    expect(find.text('Aadhaar Card - Back'), findsOneWidget);

    // --- SENIORITY 3 VERIFICATION ---
    expect(find.text('Driving License - Front'), findsAtLeastNWidgets(1));
    expect(find.text('Driving License - Back'), findsAtLeastNWidgets(1));
    expect(find.text('Vehicle RC - Front'), findsOneWidget);
    expect(find.text('Vehicle RC - Back'), findsOneWidget);

    // --- SENIORITY 4 VERIFICATION ---
    expect(find.text('REPLACE / UPDATE/MODIFY NEW DRIVER DETAILS'), findsOneWidget);
    expect(find.text('GET OTP'), findsOneWidget);
    expect(find.text('Pilot Salary & Earnings'), findsOneWidget);
    expect(find.text('App Settings'), findsOneWidget);
    expect(find.text('Share StayDriv Pilot App'), findsOneWidget);
    expect(find.text('LOGOUT'), findsOneWidget);

    // Verify Vertical Seniority / Coordinates Order (Y positions):
    // Seniority 1 (Personal Info) < Seniority 2 (Select Vehicle Type) < Seniority 4 (Replace Driver / Salary)
    final personalInfoY = tester.getTopLeft(find.text('Personal Information')).dy;
    final selectVehicleTypeY = tester.getTopLeft(find.text('Select Vehicle Type')).dy;
    final dutyConsoleY = tester.getTopLeft(find.text('Vehicle & Duty Console')).dy;
    final pilotDocsY = tester.getTopLeft(find.text('Pilot Documents')).dy;

    expect(personalInfoY < selectVehicleTypeY, isTrue,
        reason: 'Seniority 1 Personal Information must be above Seniority 2 Select Vehicle Type');
    expect(selectVehicleTypeY < dutyConsoleY, isTrue,
        reason: 'Seniority 2 Select Vehicle Type must be above Vehicle & Duty Console');
    expect(dutyConsoleY < pilotDocsY, isTrue,
        reason: 'Vehicle & Duty Console must be above Pilot Documents');

    // Cleanly unmount HomeScreen and stop background timers
    NetworkMonitor().dispose();
    BookingManager().setDriverOnline(false);
    SocketService().disconnect();
    await tester.pumpWidget(const SizedBox());
  });
}
