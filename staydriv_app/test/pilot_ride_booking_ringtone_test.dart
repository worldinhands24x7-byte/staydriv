import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staydriv_app/core/pilot_ride_ringtone_service.dart';
import 'package:staydriv_app/core/booking_manager.dart';
import 'package:staydriv_app/core/socket_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> ringtonePlayerCalls = [];

  setUpAll(() {
    SocketService.disableForTesting = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_ringtone_player'), (call) async {
      ringtonePlayerCalls.add(call);
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.staydriv.app/wake_lock'), (call) async {
      return true;
    });
  });

  setUp(() {
    ringtonePlayerCalls.clear();
    SharedPreferences.setMockInitialValues({});
    BookingManager.enableNetworkSync = false;
    BookingManager().clearBooking();
    PilotRideRingtoneService().stopRideAlert();
  });

  tearDown(() {
    BookingManager().clearBooking();
    PilotRideRingtoneService().stopRideAlert();
  });

  group('PilotRideRingtoneService Core Lifecycle Tests', () {
    test('Initial state: not ringing and currentBookingId is null', () {
      final service = PilotRideRingtoneService();
      expect(service.isRinging, isFalse);
      expect(service.currentBookingId, isNull);
      expect(service.isRingingNotifier.value, isFalse);
    });

    test('startRideAlert triggers audio playback and updates active state', () {
      final service = PilotRideRingtoneService();
      service.startRideAlert(
        bookingId: 'BK_TEST_1001',
        title: 'New Bike Request: ₹150',
        pickup: 'Madhapur Metro',
      );

      expect(service.isRinging, isTrue);
      expect(service.currentBookingId, equals('BK_TEST_1001'));
      expect(service.isRingingNotifier.value, isTrue);
      expect(service.currentBookingIdNotifier.value, equals('BK_TEST_1001'));

      // Check method channel call
      expect(ringtonePlayerCalls.any((call) => call.method == 'play'), isTrue);
    });

    test('Duplicate startRideAlert calls for same bookingId are safely deduplicated', () {
      final service = PilotRideRingtoneService();
      service.startRideAlert(bookingId: 'BK_TEST_1001');

      final initialPlayCallCount = ringtonePlayerCalls.where((c) => c.method == 'play').length;
      expect(initialPlayCallCount, equals(1));

      // Call again with same bookingId (e.g. from socket re-emit or periodic sync)
      service.startRideAlert(bookingId: 'BK_TEST_1001');

      // Play call count must NOT increment (deduplicated)
      final afterCallCount = ringtonePlayerCalls.where((c) => c.method == 'play').length;
      expect(afterCallCount, equals(initialPlayCallCount));
      expect(service.currentBookingId, equals('BK_TEST_1001'));
    });

    test('stopRideAlert silences audio and clears active booking state', () {
      final service = PilotRideRingtoneService();
      service.startRideAlert(bookingId: 'BK_TEST_1002');
      expect(service.isRinging, isTrue);

      service.stopRideAlert(bookingId: 'BK_TEST_1002');
      expect(service.isRinging, isFalse);
      expect(service.currentBookingId, isNull);
      expect(service.isRingingNotifier.value, isFalse);
      expect(service.currentBookingIdNotifier.value, isNull);

      expect(ringtonePlayerCalls.any((call) => call.method == 'stop'), isTrue);
    });

    test('stopRideAlert ignores mismatched bookingId to prevent race condition silencing', () {
      final service = PilotRideRingtoneService();
      service.startRideAlert(bookingId: 'BK_TEST_ACTIVE');

      // Stop call with an older or different booking ID
      service.stopRideAlert(bookingId: 'BK_OLD_EXPIRED');

      // Ringtone should still be active for the current active booking
      expect(service.isRinging, isTrue);
      expect(service.currentBookingId, equals('BK_TEST_ACTIVE'));

      // Stop call with matching ID silences it
      service.stopRideAlert(bookingId: 'BK_TEST_ACTIVE');
      expect(service.isRinging, isFalse);
    });
  });

  group('BookingManager Integration with PilotRideRingtoneService', () {
    test('Incoming matching ride booking triggers PilotRideRingtoneService', () {
      final manager = BookingManager();
      manager.driverSelectedVehicle = 'Bike';
      manager.setDriverOnline(true);

      final matchingBooking = {
        'bookingId': 'BK_RIDE_9999',
        'vehicle': 'Bike',
        'price': '₹90',
        'pickup': 'Gachibowli DLF',
        'drop': 'Hitec City',
        'pickupLatLng': {'lat': 17.4435, 'lng': 78.3772},
        'dropLatLng': {'lat': 17.4485, 'lng': 78.3820},
      };

      // Call public test entry point for socket incoming request
      manager.handleSocketIncomingRequestForTest(matchingBooking);

      expect(PilotRideRingtoneService().isRinging, isTrue);
      expect(PilotRideRingtoneService().currentBookingId, equals('BK_RIDE_9999'));
    });

    test('Pilot accepting ride immediately stops the ringtone', () {
      final manager = BookingManager();
      manager.driverSelectedVehicle = 'Bike';
      manager.setDriverOnline(true);

      final matchingBooking = {
        'bookingId': 'BK_RIDE_ACCEPT_TEST',
        'vehicle': 'Bike',
        'price': '₹120',
        'pickup': 'Kondapur',
        'drop': 'Madhapur',
        'pickupLatLng': {'lat': 17.4600, 'lng': 78.3600},
        'dropLatLng': {'lat': 17.4400, 'lng': 78.3800},
      };

      manager.handleSocketIncomingRequestForTest(matchingBooking);
      expect(PilotRideRingtoneService().isRinging, isTrue);

      manager.acceptBooking(
        driverName: 'Pilot Test',
        vehiclePlate: 'TS09EA1234',
        vehicleModelColor: 'Honda Activa Black',
      );

      expect(PilotRideRingtoneService().isRinging, isFalse);
    });

    test('Pilot declining ride immediately stops the ringtone', () {
      final manager = BookingManager();
      manager.driverSelectedVehicle = 'Bike';
      manager.setDriverOnline(true);

      final matchingBooking = {
        'bookingId': 'BK_RIDE_DECLINE_TEST',
        'vehicle': 'Bike',
        'price': '₹80',
        'pickup': 'Jubilee Hills',
        'drop': 'Banjara Hills',
        'pickupLatLng': {'lat': 17.4300, 'lng': 78.4000},
        'dropLatLng': {'lat': 17.4200, 'lng': 78.4400},
      };

      manager.handleSocketIncomingRequestForTest(matchingBooking);
      expect(PilotRideRingtoneService().isRinging, isTrue);

      manager.declineBooking();
      expect(PilotRideRingtoneService().isRinging, isFalse);
    });

    test('Customer cancelling ride immediately stops the ringtone', () {
      final manager = BookingManager();
      manager.driverSelectedVehicle = 'Bike';
      manager.setDriverOnline(true);

      final matchingBooking = {
        'bookingId': 'BK_RIDE_CANCEL_TEST',
        'vehicle': 'Bike',
        'price': '₹100',
        'pickup': 'Secunderabad',
        'drop': 'Begumpet',
        'pickupLatLng': {'lat': 17.4400, 'lng': 78.5000},
        'dropLatLng': {'lat': 17.4400, 'lng': 78.4700},
      };

      manager.handleSocketIncomingRequestForTest(matchingBooking);
      expect(PilotRideRingtoneService().isRinging, isTrue);

      manager.handleSocketRideCancelledForTest({
        'bookingId': 'BK_RIDE_CANCEL_TEST',
        'cancelledBy': 'customer',
        'reason': 'Changed mind',
      });

      expect(PilotRideRingtoneService().isRinging, isFalse);
    });

    test('Pilot toggling offline immediately stops any active ringtone', () {
      PilotRideRingtoneService().startRideAlert(bookingId: 'BK_OFFLINE_TEST');
      expect(PilotRideRingtoneService().isRinging, isTrue);

      BookingManager().setDriverOnline(false);
      expect(PilotRideRingtoneService().isRinging, isFalse);
    });
  });
}
