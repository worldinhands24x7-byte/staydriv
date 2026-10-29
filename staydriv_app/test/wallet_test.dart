import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Payment Wallet Tests', () {
    test('Minimum top-up validation', () {
      double testAmountLow = 0.5;
      double testAmountValid = 1.0;
      double testAmountStandard = 100.0;

      expect(testAmountLow < 1.0, isTrue);
      expect(testAmountValid >= 1.0, isTrue);
      expect(testAmountStandard >= 1.0, isTrue);
    });

    test('Paise conversion for Razorpay API', () {
      double amount = 100.0;
      int paise = (amount * 100).round();
      expect(paise, 10000);

      double decimalAmount = 15.50;
      int decimalPaise = (decimalAmount * 100).round();
      expect(decimalPaise, 1550);
    });

    test('Wallet balance formatted correctly', () {
      double balance = 125.5;
      expect(balance.toStringAsFixed(2), '125.50');

      double zeroBalance = 0.0;
      expect(zeroBalance.toStringAsFixed(2), '0.00');
    });
  });
}
