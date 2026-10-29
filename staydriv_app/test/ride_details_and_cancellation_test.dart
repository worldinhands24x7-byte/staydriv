import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:staydriv_app/core/booking_manager.dart';
import 'package:staydriv_app/core/socket_service.dart';
import 'package:staydriv_app/features/activity_history/screens/activity_screen.dart';
import 'package:staydriv_app/features/activity_history/screens/ride_details_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BookingManager.enableNetworkSync = false;
  });

  group('RideDetailsScreen Tests', () {
    testWidgets('renders all invoice and ride details correctly with dynamic data', (WidgetTester tester) async {
      final mockRide = {
        'bookingId': 'RD17863504656488275',
        'title': 'Parcel on Bike Ride',
        'vehicle': 'Bike',
        'date': '10 Aug 2026 • 01:57 PM',
        'price': '₹118',
        'pickup': 'APSRTC, Shop No, 22, Vengal Rao Nagar Main, Ameerpet, Hyderabad',
        'drop': '654, officers mess, Neredmet, Secunderabad',
        'distance': '12.3 kms',
        'duration': '30.7 mins',
        'status': 'completed',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: RideDetailsScreen(ride: mockRide),
        ),
      );
      await tester.pumpAndSettle();

      // Check App bar title
      expect(find.text('Details'), findsOneWidget);

      // Check Title, Date, Price
      expect(find.text('Parcel on Bike Ride'), findsOneWidget);
      expect(find.text('10 Aug 2026 • 01:57 PM'), findsOneWidget);
      expect(find.text('₹118'), findsOneWidget);
      expect(find.text('(.est)'), findsWidgets);
      expect(find.text('Completed'), findsOneWidget);

      // Check Ride ID
      expect(find.text('Ride ID #RD17863504656488275'), findsOneWidget);

      // Check Pickup and Drop addresses
      expect(find.text('APSRTC'), findsOneWidget);
      expect(find.text('654'), findsOneWidget);

      // Check duration and distance
      expect(find.text('30.7 mins • 12.3 kms (.est)'), findsOneWidget);

      // Check Need help banner
      expect(find.text('Need help?'), findsOneWidget);
      expect(find.text("We're a tap away"), findsOneWidget);

      // Check Ride Summary section
      expect(find.text('Ride Summary'), findsOneWidget);
      expect(find.text('Suggested Fare'), findsOneWidget);
      expect(find.text('Total Fare'), findsOneWidget);
      expect(find.text('₹118.0'), findsWidgets);

      // Check Send receipt via Email
      expect(find.text('Send receipt via Email'), findsOneWidget);

      // Scroll and Tap Send receipt via Email
      await tester.ensureVisible(find.text('Send receipt via Email'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send receipt via Email'));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Ride receipt sent to your registered email address.'), findsOneWidget);
    });

    testWidgets('renders gracefully when given minimal / empty ride data without crashing', (WidgetTester tester) async {
      final mockEmptyRide = <String, dynamic>{};

      await tester.pumpWidget(
        MaterialApp(
          home: RideDetailsScreen(ride: mockEmptyRide),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Suggested Fare'), findsOneWidget);
      expect(find.text('Total Fare'), findsOneWidget);
      expect(find.text('Send receipt via Email'), findsOneWidget);
    });

    testWidgets('ActivityScreen completed ride card navigates to RideDetailsScreen on tap', (WidgetTester tester) async {
      final completedRides = [
        {
          'date': 'Sep 25, 22:49',
          'price': '₹58',
          'icon': Icons.two_wheeler_rounded,
          'title': 'StayDriv Bike Ride',
          'route': 'Sri Balaji Layout, Gajularamaram, Hyderabad',
          'pickup': 'Sri Balaji Layout, Gajularamaram',
          'drop': 'KPHB Colony, Hyderabad',
          'serviceType': 'bike',
          'vehicle': 'Bike',
          'bookingId': 'RD9988776655',
          'distance': '3.2 kms',
          'duration': '12 mins',
          'status': 'completed',
        }
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: ActivityScreen(
            userRole: 'Rider',
            totalEarnings: 0.0,
            completedRides: completedRides,
            isAdvanceWithdrawn: false,
            onWithdrawAdvance: () {},
            onGoToHome: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ensure ride card is visible
      expect(find.text('StayDriv Bike Ride'), findsOneWidget);
      expect(find.text('₹58'), findsOneWidget);
      expect(find.text('Rebook'), findsOneWidget);

      // Tap on the completed ride card
      await tester.tap(find.text('StayDriv Bike Ride'));
      await tester.pumpAndSettle();

      // Must be on RideDetailsScreen
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Ride ID #RD9988776655'), findsOneWidget);
      expect(find.text('Ride Summary'), findsOneWidget);

      // Tap back button
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      // Returned back to ActivityScreen
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Past Trips'), findsOneWidget);
    });
  });

  group('Ride Cancellation Tests', () {
    test('BookingManager cancelBooking clears active booking and marks status cancelled', () async {
      final manager = BookingManager();
      manager.createBooking(
        pickupName: 'Ameerpet',
        dropName: 'Hitech City',
        pickupLatLng: const LatLng(17.4375, 78.4482),
        dropLatLng: const LatLng(17.4474, 78.3762),
        price: '₹150',
        vehicleType: 'Bike',
      );
      await Future.delayed(const Duration(milliseconds: 50));

      expect(manager.activeBooking, isNotNull);
      expect(manager.activeBooking!['status'], equals('searching'));

      manager.cancelBooking('Customer cancelled search', 'customer');
      expect(manager.activeBooking!['status'], equals('cancelled'));
      manager.clearBooking();
      expect(manager.activeBooking, isNull);
    });

    test('SocketService emitRideCancelled executes without throwing error', () {
      final socketService = SocketService();
      expect(
        () => socketService.emitRideCancelled(
          bookingId: 'RD12345678',
          reason: 'Customer cancelled ride search',
          cancelledBy: 'customer',
        ),
        returnsNormally,
      );
    });
  });
}
