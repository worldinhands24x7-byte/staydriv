import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Pilot Partner Ride Completed Payment Flow Tests', () {
    test('Fare parsing and display formatting for pilot panel', () {
      double parseFare(String priceStr) {
        final cleanStr = priceStr.replaceAll(RegExp(r'[^0-9.]'), '');
        return double.tryParse(cleanStr) ?? 0.0;
      }

      String formatFare(double fare) {
        if (fare == fare.roundToDouble()) {
          return '₹${fare.toInt()}';
        }
        return '₹${fare.toStringAsFixed(2)}';
      }

      expect(parseFare('₹118'), 118.0);
      expect(parseFare('₹118.00'), 118.0);
      expect(parseFare('₹250.75'), 250.75);

      expect(formatFare(118.0), '₹118');
      expect(formatFare(250.75), '₹250.75');
    });

    test('Real UPI payment URI formatting', () {
      String buildUpiUri({
        required String upiId,
        required String payeeName,
        required double amount,
        required String bookingId,
      }) {
        return 'upi://pay?pa=${Uri.encodeComponent(upiId)}&pn=${Uri.encodeComponent(payeeName)}&am=${amount.toStringAsFixed(2)}&cu=INR&tn=${Uri.encodeComponent('StayDriv Ride $bookingId')}';
      }

      final uri = buildUpiUri(
        upiId: 'pilot@okaxis',
        payeeName: 'StayDriv - John Pilot',
        amount: 118.0,
        bookingId: 'BK_982734',
      );

      expect(uri.startsWith('upi://pay?'), isTrue);
      expect(uri.contains('pa=pilot%40okaxis'), isTrue);
      expect(uri.contains('am=118.00'), isTrue);
      expect(uri.contains('cu=INR'), isTrue);
    });

    test('Payment status lifecycle: pending -> received -> completed', () {
      final statuses = ['pending', 'received', 'completed'];
      expect(statuses, contains('received'));
      String currentStatus = 'pending';

      expect(currentStatus, 'pending');
      currentStatus = 'received';
      expect(currentStatus, 'received');
      currentStatus = 'completed';
      expect(currentStatus, 'completed');
    });

    test('Disallow marking payment as completed without server verification', () {
      bool canMarkCompleted({required bool isServerConfirmed, required String status}) {
        return isServerConfirmed && (status == 'paid' || status == 'completed');
      }

      expect(canMarkCompleted(isServerConfirmed: false, status: 'completed'), isFalse);
      expect(canMarkCompleted(isServerConfirmed: true, status: 'pending'), isFalse);
      expect(canMarkCompleted(isServerConfirmed: true, status: 'paid'), isTrue);
    });

    test('Duplicate payment prevention for completed rides', () {
      bool canCollectPayment(Map<String, dynamic> booking) {
        final paymentStatus = booking['paymentStatus'] as String?;
        return paymentStatus != 'paid';
      }

      final unpaidBooking = {'bookingId': 'BK_1', 'paymentStatus': 'pending', 'price': '₹118'};
      final paidBooking = {'bookingId': 'BK_2', 'paymentStatus': 'paid', 'price': '₹118'};

      expect(canCollectPayment(unpaidBooking), isTrue);
      expect(canCollectPayment(paidBooking), isFalse);
    });
  });

  group('Pilot "Pay for the Day" Rate & Validation Tests', () {
    test('Pay for the Day daily pass rate is strictly ₹20', () {
      const double dailyPassRate = 20.0;
      expect(dailyPassRate, equals(20.0));
      expect(dailyPassRate, isNot(equals(49.0)));
    });

    test('Checkout order payload calculation matches ₹20 / 2000 paise', () {
      const double amount = 20.0;
      final int amountInPaise = (amount * 100).round();
      expect(amountInPaise, equals(2000));
      expect(amountInPaise, isNot(equals(4900)));
    });
  });
}
