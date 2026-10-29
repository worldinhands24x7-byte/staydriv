import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staydriv_app/core/location_share_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LocationShareService Deep Link & Share Parsing', () {
    test('Should parse StayDriv ride deep link with pickup, drop, and service', () async {
      const url =
          'https://staydriv.in/book?pickup=Madhapur+Metro&drop=Inorbit+Mall&plat=17.4504&plng=78.3808&dlat=17.4344&dlng=78.3866&service=cab&ref=wa_share_123';
      final result = await LocationShareService.parseSharedText(url);

      expect(result.isStayDrivRideLink, isTrue);
      expect(result.pickupAddress, equals('Madhapur Metro'));
      expect(result.dropAddress, equals('Inorbit Mall'));
      expect(result.pickupLatLng?.latitude, closeTo(17.4504, 0.0001));
      expect(result.pickupLatLng?.longitude, closeTo(78.3808, 0.0001));
      expect(result.dropLatLng?.latitude, closeTo(17.4344, 0.0001));
      expect(result.dropLatLng?.longitude, closeTo(78.3866, 0.0001));
      expect(result.serviceType, equals('car'));
      expect(result.rideRef, equals('wa_share_123'));
    });

    test('Should parse StayDriv custom scheme staydriv://book', () async {
      const url = 'staydriv://book?drop=Hitec+City&service=auto';
      final result = await LocationShareService.parseSharedText(url);

      expect(result.isStayDrivRideLink, isTrue);
      expect(result.dropAddress, equals('Hitec City'));
      expect(result.serviceType, equals('auto'));
    });

    test('Should parse geo: URI with label in query', () async {
      const geo = 'geo:17.4834,78.3871?q=17.4834,78.3871(IKEA%20Hyderabad)';
      final result = await LocationShareService.parseSharedText(geo);

      expect(result.isStayDrivRideLink, isFalse);
      expect(result.title, equals('IKEA Hyderabad'));
      expect(result.coordinates?.latitude, closeTo(17.4834, 0.0001));
      expect(result.coordinates?.longitude, closeTo(78.3871, 0.0001));
    });

    test('Should parse Google Maps URL with lat/lng', () async {
      const mapsUrl = 'https://www.google.com/maps?q=17.440081,78.348915';
      final result = await LocationShareService.parseSharedText(mapsUrl);

      expect(result.coordinates?.latitude, closeTo(17.4400, 0.001));
      expect(result.coordinates?.longitude, closeTo(78.3489, 0.001));
    });

    test('Should save and consume pending links across cold starts', () async {
      const link = 'https://staydriv.in/book?pickup=Home&drop=Airport';
      await LocationShareService.savePendingLink(link);

      final consumed = await LocationShareService.consumePendingLink();
      expect(consumed, equals(link));

      final secondConsumed = await LocationShareService.consumePendingLink();
      expect(secondConsumed, isNull);
    });
  });
}
