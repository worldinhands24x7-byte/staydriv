import 'package:flutter_test/flutter_test.dart';
import 'package:staydriv_app/core/call_masking_service.dart';

void main() {
  group('CallMaskingService Tests', () {
    test('maskPhone properly masks phone numbers in 98******21 format (STEP 12)', () {
      expect(CallMaskingService.maskPhone('9876543221'), '98******21');
      expect(CallMaskingService.maskPhone('+919876543221'), '98******21');
      expect(CallMaskingService.maskPhone('+91 94904 40281'), '94******81');
      expect(CallMaskingService.maskPhone('09876543210'), '98******10');
    });

    test('maskPhone handles invalid or short inputs safely', () {
      expect(CallMaskingService.maskPhone(null), '******');
      expect(CallMaskingService.maskPhone(''), '******');
      expect(CallMaskingService.maskPhone('   '), '******');
      expect(CallMaskingService.maskPhone('123'), '******');
    });

    test('CallMaskingResult handles CALL_INITIATED and ALREADY_IN_PROGRESS correctly', () {
      final res = CallMaskingResult(
        success: true,
        status: 'CALL_INITIATED',
        message: 'Call connected',
        callId: 'CALL-123456',
      );

      expect(res.success, isTrue);
      expect(res.status, 'CALL_INITIATED');
      expect(res.message, 'Call connected');
      expect(res.callId, 'CALL-123456');

      final duplicateRes = CallMaskingResult(
        success: true,
        status: 'ALREADY_IN_PROGRESS',
        message: 'Call already in progress',
      );
      expect(duplicateRes.success, isTrue);
      expect(duplicateRes.status, 'ALREADY_IN_PROGRESS');
      expect(duplicateRes.message, 'Call already in progress');
    });
  });
}
