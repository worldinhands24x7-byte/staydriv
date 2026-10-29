import 'package:flutter_test/flutter_test.dart';
import 'package:staydriv_app/core/contact_picker_service.dart';

void main() {
  group('ContactPickerService Phone Number Cleaning & Validation Tests', () {
    test('Cleans various Indian phone formats correctly to 10 digits', () {
      expect(ContactPickerService.cleanIndianPhoneNumber('+91 98765-43210'), '9876543210');
      expect(ContactPickerService.cleanIndianPhoneNumber('+919876543210'), '9876543210');
      expect(ContactPickerService.cleanIndianPhoneNumber('09876543210'), '9876543210');
      expect(ContactPickerService.cleanIndianPhoneNumber('919876543210'), '9876543210');
      expect(ContactPickerService.cleanIndianPhoneNumber('98765 43210'), '9876543210');
      expect(ContactPickerService.cleanIndianPhoneNumber('+91 (98765) 43210'), '9876543210');
      expect(ContactPickerService.cleanIndianPhoneNumber('0091 9876543210'), '9876543210');
      expect(ContactPickerService.cleanIndianPhoneNumber('9247535068'), '9247535068');
    });

    test('Validates Indian mobile numbers (must start with 6, 7, 8, 9 and have 10 digits)', () {
      expect(ContactPickerService.isValidIndianMobile('9876543210'), isTrue);
      expect(ContactPickerService.isValidIndianMobile('8876543210'), isTrue);
      expect(ContactPickerService.isValidIndianMobile('7876543210'), isTrue);
      expect(ContactPickerService.isValidIndianMobile('6876543210'), isTrue);
      expect(ContactPickerService.isValidIndianMobile('+91 92475 35068'), isTrue);
      expect(ContactPickerService.isValidIndianMobile('09247535068'), isTrue);

      // Invalid cases
      expect(ContactPickerService.isValidIndianMobile('1234567890'), isFalse);
      expect(ContactPickerService.isValidIndianMobile('5876543210'), isFalse);
      expect(ContactPickerService.isValidIndianMobile('98765'), isFalse);
      expect(ContactPickerService.isValidIndianMobile(''), isFalse);
      expect(ContactPickerService.isValidIndianMobile('abcdefghij'), isFalse);
    });

    test('Formats 10-digit number for display', () {
      expect(ContactPickerService.formatForDisplay('9876543210'), '98765 43210');
      expect(ContactPickerService.formatForDisplay('+91 9876543210'), '98765 43210');
    });
  });
}
