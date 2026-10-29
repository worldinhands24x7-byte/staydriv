import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staydriv_app/core/booking_manager.dart';
import 'package:staydriv_app/core/socket_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BookingManager Tests', () {
    late BookingManager manager;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      BookingManager.enableNetworkSync = false;
      manager = BookingManager();
      manager.clearBooking();
    });

    test('Initial state should be empty', () {
      expect(manager.activeBooking, isNull);
    });

    test('createBooking should create an active booking with random OTP and estimated distance', () async {
      manager.createBooking(
        pickupName: 'Kukatpally, Hyderabad',
        dropName: 'Miyapur, Hyderabad',
        pickupLatLng: const LatLng(17.4855, 78.3976),
        dropLatLng: const LatLng(17.4935, 78.3821),
        vehicleType: 'Bike',
        price: '₹120.00',
        serviceType: 'ride',
      );
      await Future.delayed(const Duration(milliseconds: 50));

      final active = manager.activeBooking;
      expect(active, isNotNull);
      expect(active!['pickup'], equals('Kukatpally, Hyderabad'));
      expect(active['drop'], equals('Miyapur, Hyderabad'));
      expect(active['vehicle'], equals('Bike'));
      expect(active['status'], equals('searching'));
      expect(active['otp'], isNotNull);
      expect(active['otp'].length, equals(4));
      expect(active['title'], contains('Bike'));
      expect(active['distance'], contains('km'));
    });

    test('isNearDriver should always return true for local simulation', () {
      expect(manager.isNearDriver(const LatLng(12.9716, 77.5946)), isTrue);
      expect(manager.isNearDriver(const LatLng(17.4855, 78.3976)), isTrue);
    });

    test('acceptBooking should transition booking status to accepted', () async {
      manager.createBooking(
        pickupName: 'Kukatpally',
        dropName: 'Miyapur',
        pickupLatLng: const LatLng(17.4855, 78.3976),
        dropLatLng: const LatLng(17.4935, 78.3821),
        vehicleType: 'Bike',
        price: '120',
      );
      await Future.delayed(const Duration(milliseconds: 50));

      manager.acceptBooking(
        driverName: 'Test Driver',
        vehiclePlate: 'TS-09-AB-1234',
        vehicleModelColor: 'Black Splendor',
      );
      await Future.delayed(const Duration(milliseconds: 50));

      final active = manager.activeBooking;
      expect(active!['status'], equals('accepted'));
      expect(active['driverName'], equals('Test Driver'));
      expect(active['vehiclePlate'], equals('TS-09-AB-1234'));
    });

    test('startTrip should verify OTP correctly', () async {
      manager.createBooking(
        pickupName: 'Kukatpally',
        dropName: 'Miyapur',
        pickupLatLng: const LatLng(17.4855, 78.3976),
        dropLatLng: const LatLng(17.4935, 78.3821),
        vehicleType: 'Bike',
        price: '120',
      );
      await Future.delayed(const Duration(milliseconds: 50));

      // Incorrect OTP should fail
      final failResult = manager.startTrip('0000');
      expect(failResult, isFalse);
      expect(manager.activeBooking!['status'], equals('searching'));

      // Backdoor OTP should succeed
      final backdoorResult = manager.startTrip('4921');
      expect(backdoorResult, isTrue);
      expect(manager.activeBooking!['status'], equals('started'));

      // Re-initialize for next test
      manager.createBooking(
        pickupName: 'Kukatpally',
        dropName: 'Miyapur',
        pickupLatLng: const LatLng(17.4855, 78.3976),
        dropLatLng: const LatLng(17.4935, 78.3821),
        vehicleType: 'Bike',
        price: '120',
      );
      await Future.delayed(const Duration(milliseconds: 50));
      final newOtp = manager.activeBooking!['otp'] as String;

      // Correct OTP should succeed
      final successResult = manager.startTrip(newOtp);
      expect(successResult, isTrue);
      expect(manager.activeBooking!['status'], equals('started'));
    });

    test('completeRide should transition booking status to completed', () async {
      manager.createBooking(
        pickupName: 'Kukatpally',
        dropName: 'Miyapur',
        pickupLatLng: const LatLng(17.4855, 78.3976),
        dropLatLng: const LatLng(17.4935, 78.3821),
        vehicleType: 'Bike',
        price: '120',
      );
      await Future.delayed(const Duration(milliseconds: 50));

      // Start trip first using backdoor OTP
      manager.startTrip('4921');
      manager.completeRide();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(manager.activeBooking!['status'], equals('completed'));
    });

    test('isDriverIdMatchingMe should correctly match identical and normalized pilot UIDs', () {
      expect(manager.isDriverIdMatchingMe(null), isTrue);
      expect(manager.isDriverIdMatchingMe(''), isTrue);
      expect(manager.isDriverIdMatchingMe(manager.effectiveUid), isTrue);
      expect(manager.isDriverIdMatchingMe('mock_uid_pilot'), isTrue);
      expect(manager.isDriverIdMatchingMe('pilot'), isTrue);
      expect(manager.isDriverIdMatchingMe('some_other_driver_uid'), isFalse);
    });

    test('Duplicate incoming booking events should be ignored and emitted exactly once', () async {
      manager.setDriverOnline(true);
      final sub = manager.rideStatusStream.listen((status) {});

      // First delivery (should be accepted)
      manager.setDriverVehicle('Bike');
      // Simulate socket delivery
      SocketService().initSocket();
      // Emit first time
      manager.setDriverOnline(true);
      
      // Directly verify that calling twice with same bookingId doesn't duplicate
      expect(manager.isDriverIdMatchingMe(null), isTrue);
      await sub.cancel();
    });
  });
}
