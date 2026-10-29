import 'package:flutter_test/flutter_test.dart';
import 'package:staydriv_app/core/booking_manager.dart';

void main() {
  group('StayDriv Vehicle & Booking Matching Tests', () {
    test('Two-wheelers match each other seamlessly (Bike, Scooty, Motorcycle, Parcel)', () {
      // Customer wants Bike, Pilot has Scooty
      expect(areVehiclesCompatible('Bike', 'Scooty'), isTrue);
      expect(areVehiclesCompatible('Scooty', 'Bike'), isTrue);
      expect(areVehiclesCompatible('bike', 'scooty'), isTrue);

      // Customer wants Bike, Pilot has Motorcycle
      expect(areVehiclesCompatible('Bike', 'Motorcycle'), isTrue);
      expect(areVehiclesCompatible('Bike', 'Two Wheeler'), isTrue);
      expect(areVehiclesCompatible('Bike', 'Activa'), isTrue);

      // Parcel delivery can be fulfilled by Bike/Scooty pilots
      expect(areVehiclesCompatible('Parcel', 'Bike'), isTrue);
      expect(areVehiclesCompatible('Parcel', 'Scooty'), isTrue);
      expect(areVehiclesCompatible('Parcel Bike', 'Scooty'), isTrue);
    });

    test('Cars/Cabs match each other seamlessly (Cab, Car, Sedan, Mini, SUV, Hatchback)', () {
      expect(areVehiclesCompatible('Sedan', 'Cab'), isTrue);
      expect(areVehiclesCompatible('Mini', 'Car'), isTrue);
      expect(areVehiclesCompatible('SUV', 'Cab'), isTrue);
      expect(areVehiclesCompatible('Hatchback', 'Car'), isTrue);
      expect(areVehiclesCompatible('Prime Sedan', 'Cab'), isTrue);
    });

    test('Autos match each other (Auto, Auto Rickshaw, Electric Auto)', () {
      expect(areVehiclesCompatible('Auto', 'Auto Rickshaw'), isTrue);
      expect(areVehiclesCompatible('Auto Rickshaw', 'Auto'), isTrue);
      expect(areVehiclesCompatible('Electric Auto', 'Auto'), isTrue);
    });

    test('Incompatible vehicle categories do not match', () {
      // Bike pilot should not get Car or Auto requests (unless authoritative server assignment)
      expect(areVehiclesCompatible('Car', 'Bike'), isFalse);
      expect(areVehiclesCompatible('Auto', 'Bike'), isFalse);
      expect(areVehiclesCompatible('Heavy Truck', 'Auto'), isFalse);
    });

    test('BookingManager matches booking if assigned specifically to this pilot', () {
      final bm = BookingManager();
      final myUid = bm.effectiveUid;
      
      // Even if vehicle differs, if server assigned it to me, it MUST match!
      final assignedBooking = {
        'bookingId': 'BK_ASSIGNED_TEST',
        'vehicle': 'Special Vehicle',
        'driverId': myUid,
        'status': 'searching',
      };
      expect(bm.isBookingMatching(assignedBooking), isTrue);
    });
  });
}
