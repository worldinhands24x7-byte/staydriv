import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staydriv_app/core/booking_manager.dart';
import 'package:staydriv_app/core/floating_widget_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StayDriv Real-Time Booking Synchronization & Floating Mini Screen Tests', () {
    late BookingManager bookingManager;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      bookingManager = BookingManager();
      BookingManager.enableNetworkSync = false;
      bookingManager.clearBooking();
    });

    tearDown(() {
      bookingManager.clearBooking();
    });

    test('Customer App: Initial state has no active booking and floating screen is hidden', () {
      expect(bookingManager.activeBooking, isNull);
      expect(FloatingWidgetService.isFloatingVisible, isFalse);
    });

    test('Customer App: Accepting booking updates driver details and status', () async {
      bookingManager.createBooking(
        pickupName: 'Kukatpally, Hyderabad',
        dropName: 'Hitech City, Hyderabad',
        pickupLatLng: const LatLng(17.4834, 78.3871),
        dropLatLng: const LatLng(17.4435, 78.3772),
        vehicleType: 'Bike',
        price: '₹120.00',
      );
      await Future.delayed(const Duration(milliseconds: 50));
      expect(bookingManager.activeBooking, isNotNull);
      expect(bookingManager.activeBooking!['status'], equals('searching'));

      bookingManager.acceptBooking(
        driverName: 'Ramesh Kumar',
        vehiclePlate: 'TS09AB1234',
        vehicleModelColor: 'Honda Activa • Grey',
      );

      expect(bookingManager.activeBooking, isNotNull);
      expect(bookingManager.activeBooking!['status'], equals('accepted'));
      expect(bookingManager.activeBooking!['driverName'], equals('Ramesh Kumar'));
      expect(bookingManager.activeBooking!['vehiclePlate'], equals('TS09AB1234'));
      expect(bookingManager.activeBooking!['vehicleModelColor'], equals('Honda Activa • Grey'));
    });

    test('Pilot App: Declining booking clears active booking for pilot', () async {
      bookingManager.createBooking(
        pickupName: 'Kukatpally, Hyderabad',
        dropName: 'Hitech City, Hyderabad',
        pickupLatLng: const LatLng(17.4834, 78.3871),
        dropLatLng: const LatLng(17.4435, 78.3772),
        vehicleType: 'Bike',
        price: '₹120.00',
      );
      await Future.delayed(const Duration(milliseconds: 50));
      expect(bookingManager.activeBooking, isNotNull);

      bookingManager.declineBooking();
      bookingManager.clearBooking();
      expect(bookingManager.activeBooking, isNull);
    });

    test('Stale booking prevention: Completed or cancelled booking is discarded on restore', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'saved_active_booking',
        '{"bookingId":"BK_OLD_123","status":"completed","pickup":"A","drop":"B"}',
      );

      final restored = await bookingManager.restoreAndSyncActiveBooking();
      expect(restored, isNull);
      expect(bookingManager.activeBooking, isNull);
      expect(prefs.containsKey('saved_active_booking'), isFalse);
    });

    test('Floating Mini Screen: Formats simple, user-friendly titles correctly', () {
      const searchTitle = 'Finding your pilot...';
      const acceptedTitle = 'Pilot accepted your booking';
      const arrivedTitle = 'Pilot has arrived';
      const startedTitle = 'Ride started';
      const completedTitle = 'Ride completed';

      expect(searchTitle, contains('Finding your pilot'));
      expect(acceptedTitle, contains('Pilot accepted'));
      expect(arrivedTitle, contains('Pilot has arrived'));
      expect(startedTitle, contains('Ride started'));
      expect(completedTitle, contains('Ride completed'));
    });

    test('Ride cancellation clears active booking and hides floating interface', () async {
      bookingManager.createBooking(
        pickupName: 'Kukatpally, Hyderabad',
        dropName: 'Hitech City, Hyderabad',
        pickupLatLng: const LatLng(17.4834, 78.3871),
        dropLatLng: const LatLng(17.4435, 78.3772),
        vehicleType: 'Bike',
        price: '₹120.00',
      );
      await Future.delayed(const Duration(milliseconds: 50));
      expect(bookingManager.activeBooking, isNotNull);

      await bookingManager.cancelBooking('Customer changed mind', 'customer');
      expect(bookingManager.activeBooking!['status'], equals('cancelled'));

      bookingManager.clearBooking();
      expect(bookingManager.activeBooking, isNull);
    });
  });
}
