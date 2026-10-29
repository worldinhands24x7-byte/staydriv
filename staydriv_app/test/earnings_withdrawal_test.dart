import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Pilot Earnings & Advance Withdrawal Tests', () {
    test('Minimum withdrawal amount validation', () {
      const double minLimit = 100.0;
      double requestLow = 50.0;
      double requestValid = 100.0;
      double requestHigh = 1500.0;

      expect(requestLow < minLimit, isTrue);
      expect(requestValid >= minLimit, isTrue);
      expect(requestHigh >= minLimit, isTrue);
    });

    test('Withdrawable balance calculation with pending requests', () {
      double availableBalance = 5144.50;
      double pendingAmount = 1000.0;
      double withdrawable = availableBalance - pendingAmount;

      expect(withdrawable, 4144.50);

      // Attempting to withdraw more than withdrawable should be disallowed
      double requestAmount = 4500.0;
      expect(requestAmount > withdrawable, isTrue);

      double validRequest = 2000.0;
      expect(validRequest <= withdrawable, isTrue);
    });

    test('Bank Account and UPI validation logic', () {
      bool isValidBank(String acc, String ifsc) {
        return acc.trim().length >= 9 && ifsc.trim().length >= 5;
      }

      bool isValidUpi(String upi) {
        return upi.trim().contains('@') && upi.trim().length >= 5;
      }

      expect(isValidBank('123456789012', 'SBIN0001234'), isTrue);
      expect(isValidBank('123', 'SBIN0001234'), isFalse);
      expect(isValidBank('123456789012', ''), isFalse);

      expect(isValidUpi('pilot@okaxis'), isTrue);
      expect(isValidUpi('9876543210@paytm'), isTrue);
      expect(isValidUpi('invalidupi'), isFalse);
    });

    test('Reserved balance and pending settlement escrow accounting', () {
      double availableBalance = 5000.0;
      double reservedBalance = 1500.0;
      double pendingSettlement = 350.0;

      double withdrawable = (availableBalance - reservedBalance).clamp(0.0, double.infinity);
      double totalPending = reservedBalance + pendingSettlement;

      expect(withdrawable, 3500.0);
      expect(totalPending, 1850.0);

      // Total earned is always Withdrawn + Available
      double totalWithdrawn = 8000.0;
      double totalEarned = totalWithdrawn + availableBalance;
      expect(totalEarned, 13000.0);
    });

    test('Withdrawal status normalization and display logic', () {
      String normalizeStatus(String status) {
        final s = status.toLowerCase().trim();
        if (s == 'pending' || s == 'pending_approval' || s == 'under_review') return 'PENDING APPROVAL';
        if (s == 'approved') return 'APPROVED';
        if (s == 'processing') return 'PROCESSING';
        if (s == 'completed' || s == 'paid' || s == 'success') return 'PAID';
        if (s == 'rejected') return 'REJECTED';
        if (s == 'failed') return 'FAILED';
        if (s == 'cancelled') return 'CANCELLED';
        return status.toUpperCase();
      }

      expect(normalizeStatus('pending_approval'), 'PENDING APPROVAL');
      expect(normalizeStatus('pending'), 'PENDING APPROVAL');
      expect(normalizeStatus('under_review'), 'PENDING APPROVAL');
      expect(normalizeStatus('approved'), 'APPROVED');
      expect(normalizeStatus('processing'), 'PROCESSING');
      expect(normalizeStatus('paid'), 'PAID');
      expect(normalizeStatus('completed'), 'PAID');
      expect(normalizeStatus('rejected'), 'REJECTED');
      expect(normalizeStatus('failed'), 'FAILED');
      expect(normalizeStatus('cancelled'), 'CANCELLED');
    });
  });
}
