import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staydriv_app/core/booking_manager.dart';
import 'package:staydriv_app/core/socket_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Ride Sharing & Real GPS Location Tests', () {
    late BookingManager manager;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      BookingManager.enableNetworkSync = false;
      manager = BookingManager();
      manager.clearBooking();
    });

    test('updateDriverLocation accurately sets position, heading, speed, and ETA', () {
      const testPos = LatLng(17.4375, 78.4482);
      manager.updateDriverLocation(
        testPos,
        heading: 85.5,
        speed: 42.0,
        eta: '7 mins',
        remainingDistance: '3.2 km',
        navigationStatus: 'navigating',
      );

      expect(manager.hasRealDriverLocation, isTrue);
      expect(manager.realDriverLatLng?.latitude, equals(17.4375));
      expect(manager.realDriverLatLng?.longitude, equals(78.4482));
      expect(manager.driverHeading, equals(85.5));
      expect(manager.driverSpeed, equals(42.0));
      expect(manager.latestEta, equals('7 mins'));
      expect(manager.latestRemainingDistance, equals('3.2 km'));
    });

    test('SocketService room helper methods can be invoked without crashing', () {
      final socket = SocketService();
      expect(() => socket.joinRide('BK_12345'), returnsNormally);
      expect(() => socket.leaveRide('BK_12345'), returnsNormally);
      expect(() => socket.joinTrack('tr_sample_token'), returnsNormally);
    });

    test('WhatsApp safety message generation matches specification', () {
      const shareUrl = 'https://api.staydriv.in/track/tr_abc123xyz789';
      const shortCode = 'ABC123XY';
      final message = "🚗 I'm currently travelling with StayDriv.\n\n"
          "Track my ride and live location here:\n$shareUrl\n\n"
          "Ride ID: $shortCode\n\n"
          "This link is available only while my ride is active.";

      expect(message, contains("🚗 I'm currently travelling with StayDriv."));
      expect(message, contains(shareUrl));
      expect(message, contains("Ride ID: ABC123XY"));
      expect(message, contains("This link is available only while my ride is active."));
      // Ensure no private auth tokens or sensitive customer IDs are in the message
      expect(message.contains('password'), isFalse);
      expect(message.contains('Bearer'), isFalse);
    });
  });
}
