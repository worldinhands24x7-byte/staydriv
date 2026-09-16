import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:staydriv_app/core/network_monitor.dart';
import 'package:staydriv_app/core/firebase_service.dart';
import 'package:staydriv_app/core/booking_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StayDriv QA Test Harness - Core Systems Audit', () {
    
    // --- 1. Network Monitor Auditing ---
    test('NetworkMonitor should initialize with Connected status and bypass Localhost latency warnings', () {
      final monitor = NetworkMonitor();
      expect(monitor.currentStatus, equals(NetworkStatus.connected));
      expect(monitor.isBackendReachable, isTrue);
      expect(monitor.connectionType, isNotNull);
      expect(monitor.cellularGeneration, isNotNull);
    });

    // --- 2. Mock Document Snapshot Null Safety Auditing ---
    test('MockDocumentSnapshot should initialize cleanly without throwing Null Safety runtime TypeErrors', () {
      final snapshot = MockDocumentSnapshot({
        'name': 'StayDriv Tester',
        'role': 'customer',
        'phone': '1234567890',
      });

      expect(snapshot.exists, isTrue);
      expect(snapshot.data(), isNotNull);
      expect(snapshot.data()!['name'], equals('StayDriv Tester'));
      expect(snapshot.data()!['role'], equals('customer'));
      expect(snapshot.id, isEmpty);
      
      // Verification of unimplemented property getters (should throw instead of casting null as dynamic)
      expect(() => snapshot.reference, throwsUnimplementedError);
      expect(() => snapshot.metadata, throwsUnimplementedError);
    });

    // --- 3. Firebase Service Fallback Configuration Auditing ---
    test('FirebaseService Mock Auth overrides and role routing checks', () async {
      final service = FirebaseService();
      
      // Set mock UID
      FirebaseService.setMockUid('mock_uid_1234567890');
      expect(service.currentUid, equals('mock_uid_1234567890'));

      // Check role routing for mock user
      final role = await service.getUserRole('mock_uid_staydriv');
      expect(role, equals('admin'));

      // Clear mock UID
      FirebaseService.setMockUid(null);
    });

    // --- 4. Booking Manager State Transitions ---
    test('BookingManager lifecycle from searching to accept, start, and complete', () async {
      BookingManager.enableNetworkSync = false;
      final manager = BookingManager();
      manager.clearBooking();

      expect(manager.activeBooking, isNull);

      // Create Booking
      manager.createBooking(
        pickupName: 'Origin Location',
        dropName: 'Destination Location',
        pickupLatLng: const LatLng(17.4855, 78.3976),
        dropLatLng: const LatLng(17.4935, 78.3821),
        vehicleType: 'Heavy Truck',
        price: '₹12000.00',
        serviceType: 'heavy_truck',
      );
      await Future.delayed(const Duration(milliseconds: 50));

      var active = manager.activeBooking;
      expect(active, isNotNull);
      expect(active!['status'], equals('searching'));
      expect(active['vehicle'], equals('Heavy Truck'));
      expect(active['serviceType'], equals('heavy_truck'));

      // Accept Booking
      manager.acceptBooking(
        driverName: 'Pilot Partner',
        vehiclePlate: 'TS-09-XX-9999',
        vehicleModelColor: 'Blue Truck',
      );
      await Future.delayed(const Duration(milliseconds: 50));
      
      active = manager.activeBooking;
      expect(active!['status'], equals('accepted'));
      expect(active['driverName'], equals('Pilot Partner'));
      expect(active['vehiclePlate'], equals('TS-09-XX-9999'));

      // Start Trip with backdoor OTP
      final isStarted = manager.startTrip('4921');
      expect(isStarted, isTrue);
      expect(manager.activeBooking!['status'], equals('started'));

      // Complete trip
      manager.completeRide();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(manager.activeBooking!['status'], equals('completed'));
    });
  });
}
