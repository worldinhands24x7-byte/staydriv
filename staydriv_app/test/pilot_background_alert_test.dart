import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staydriv_app/core/wake_lock_service.dart';
import 'package:staydriv_app/core/booking_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Pilot Background Booking Alert Tests', () {
    test('WakeLockService handles notification action callback routing', () async {
      String? handledAction;
      String? handledBookingId;

      WakeLockService.setBookingActionListener((action, bookingId) {
        handledAction = action;
        handledBookingId = bookingId;
      });

      const channel = MethodChannel('com.staydriv.app/wake_lock');
      final ByteData? message = channel.codec.encodeMethodCall(
        const MethodCall('onBookingActionReceived', {
          'action': 'accept',
          'bookingId': 'BK_MINIMIZE_TEST_01'
        }),
      );

      await ServicesBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        'com.staydriv.app/wake_lock',
        message,
        (ByteData? reply) {},
      );

      expect(handledAction, equals('accept'));
      expect(handledBookingId, equals('BK_MINIMIZE_TEST_01'));

      // Clear listener
      WakeLockService.setBookingActionListener(null);
    });

    test('BookingManager isBookingMatching correctly validates vehicle and bypasses distance for testing', () {
      final manager = BookingManager();
      manager.driverSelectedVehicle = 'Bike';

      final matchingBooking = {
        'bookingId': 'BK_TEST_02',
        'vehicle': 'Bike',
        'price': '₹85',
        'pickup': 'KPHB Colony',
        'drop': 'Hitec City',
      };

      expect(manager.isBookingMatching(matchingBooking), isTrue);

      final nonMatchingBooking = {
        'bookingId': 'BK_TEST_03',
        'vehicle': 'Auto',
        'price': '₹120',
        'pickup': 'KPHB Colony',
        'drop': 'Gachibowli',
      };

      expect(manager.isBookingMatching(nonMatchingBooking), isFalse);
    });

    test('BookingManager driver online duty state management', () {
      final manager = BookingManager();
      
      manager.setDriverOnline(true);
      expect(manager.isDriverOnline, isTrue);

      manager.setDriverOnline(false);
      expect(manager.isDriverOnline, isFalse);
    });
  });
}
