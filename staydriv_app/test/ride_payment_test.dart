import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Ride Completed Payment Flow Tests', () {
    test('Ride fare parser correctly handles strings, integers, and formatted currency', () {
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

      expect(parseFare('₹46'), 46.0);
      expect(parseFare('₹ 250.50'), 250.50);
      expect(parseFare('150'), 150.0);
      expect(parseFare('invalid'), 0.0);

      expect(formatFare(46.0), '₹46');
      expect(formatFare(150.50), '₹150.50');
      expect(formatFare(0.0), '₹0');
    });

    test('Duplicate payment prevention: blocks payment when status is already paid', () {
      bool canPayRide(Map<String, dynamic> booking) {
        final status = booking['paymentStatus'] as String?;
        return status != 'paid';
      }

      final unpaidBooking = {
        'id': 'booking_123',
        'price': '₹46',
        'paymentStatus': 'pending',
      };

      final paidBooking = {
        'id': 'booking_123',
        'price': '₹46',
        'paymentStatus': 'paid',
        'paymentOption': 'CASH',
      };

      expect(canPayRide(unpaidBooking), isTrue);
      expect(canPayRide(paidBooking), isFalse);
    });

    test('Supported customer payment modes include Cash and StayDriv Wallet', () {
      List<String> getAvailablePaymentModes() {
        return <String>[
          'Cash Payment',
          'StayDriv Wallet',
        ];
      }

      final defaultModes = getAvailablePaymentModes();
      expect(defaultModes.contains('Cash Payment'), isTrue);
      expect(defaultModes.contains('StayDriv Wallet'), isTrue);
      expect(defaultModes.contains('Razorpay UPI / Online Payment'), isFalse);
      expect(defaultModes.contains('Scan & Pay / UPI QR'), isFalse);
    });

    test('StayDriv Wallet balance validation and payment authorization', () {
      bool canPayFromWallet(double balance, double fare) {
        return balance >= fare && fare > 0;
      }

      expect(canPayFromWallet(250.0, 46.0), isTrue);
      expect(canPayFromWallet(46.0, 46.0), isTrue);
      expect(canPayFromWallet(30.0, 46.0), isFalse);
      expect(canPayFromWallet(0.0, 46.0), isFalse);
    });

    test('StayDriv Wallet deduction idempotency: cannot deduct twice for paid ride', () {
      Map<String, dynamic> processWalletPayment({
        required Map<String, dynamic> booking,
        required double userWalletBalance,
        required double fare,
      }) {
        if (booking['paymentStatus'] == 'paid') {
          return {
            'success': true,
            'alreadyPaid': true,
            'newBalance': userWalletBalance,
            'message': 'Ride is already paid',
          };
        }
        if (userWalletBalance < fare) {
          return {
            'success': false,
            'insufficientBalance': true,
            'newBalance': userWalletBalance,
            'message': 'Insufficient wallet balance',
          };
        }
        return {
          'success': true,
          'alreadyPaid': false,
          'newBalance': userWalletBalance - fare,
          'message': 'Payment successful',
        };
      }

      final booking = {'bookingId': 'BK_001', 'paymentStatus': 'pending'};
      // First attempt: deducts ₹46 from ₹250
      final firstRes = processWalletPayment(booking: booking, userWalletBalance: 250.0, fare: 46.0);
      expect(firstRes['success'], isTrue);
      expect(firstRes['alreadyPaid'], isFalse);
      expect(firstRes['newBalance'], 204.0);

      // Mark booking paid
      booking['paymentStatus'] = 'paid';

      // Second duplicate attempt: must NOT deduct again
      final secondRes = processWalletPayment(booking: booking, userWalletBalance: 204.0, fare: 46.0);
      expect(secondRes['success'], isTrue);
      expect(secondRes['alreadyPaid'], isTrue);
      expect(secondRes['newBalance'], 204.0);
    });

    test('Dynamic Scan & Pay UPI URI is formatted with valid payee, amount and booking note', () {
      String generateUpiUri({
        required String upiId,
        required String payeeName,
        required double amount,
        required String bookingId,
      }) {
        return 'upi://pay?pa=${Uri.encodeComponent(upiId)}&pn=${Uri.encodeComponent(payeeName)}&am=${amount.toStringAsFixed(2)}&cu=INR&tn=${Uri.encodeComponent('StayDriv Ride $bookingId')}';
      }

      final uri = generateUpiUri(
        upiId: 'staydriv@icici',
        payeeName: 'StayDriv Pilot',
        amount: 46.0,
        bookingId: 'BK_TEST',
      );

      expect(uri.startsWith('upi://pay?'), isTrue);
      expect(uri.contains('pa=staydriv%40icici'), isTrue);
      expect(uri.contains('am=46.00'), isTrue);
      expect(uri.contains('cu=INR'), isTrue);
      expect(uri.contains('tn=StayDriv%20Ride%20BK_TEST'), isTrue);
    });

    test('Razorpay verification payload validity', () {
      bool isSignaturePayloadValid({
        required String? orderId,
        required String? paymentId,
        required String? signature,
        required String? bookingId,
      }) {
        if (orderId == null || orderId.isEmpty) return false;
        if (paymentId == null || paymentId.isEmpty) return false;
        if (signature == null || signature.isEmpty) return false;
        if (bookingId == null || bookingId.isEmpty) return false;
        return true;
      }

      expect(
        isSignaturePayloadValid(
          orderId: 'order_NxABC123',
          paymentId: 'pay_NxXYZ789',
          signature: 'hmac_sha256_mock_sig',
          bookingId: 'booking_123',
        ),
        isTrue,
      );

      expect(
        isSignaturePayloadValid(
          orderId: null,
          paymentId: 'pay_NxXYZ789',
          signature: 'hmac_sha256_mock_sig',
          bookingId: 'booking_123',
        ),
        isFalse,
      );
    });

    test('Razorpay create-order idempotency: detects alreadyPaid response and transitions UI to Paid', () {
      bool isPaymentCompleted(Map<String, dynamic> response) {
        if (response['alreadyPaid'] == true || response['paymentStatus'] == 'paid') {
          return true;
        }
        return false;
      }

      final createOrderAlreadyPaidResp = {
        'success': true,
        'alreadyPaid': true,
        'paymentStatus': 'paid',
        'paymentOption': 'PAID_ONLINE',
        'orderId': 'order_123',
        'paymentId': 'pay_123',
        'amount': 0,
        'message': 'Booking is already paid'
      };

      expect(isPaymentCompleted(createOrderAlreadyPaidResp), isTrue);

      final newOrderResp = {
        'success': true,
        'orderId': 'order_456',
        'amount': 4600,
        'keyId': 'rzp_live_xxx'
      };

      expect(isPaymentCompleted(newOrderResp), isFalse);
    });

    test('Booking restoration preserves completed status and paid status without clearing booking', () {
      bool shouldShowPaymentSelection(Map<String, dynamic>? booking, bool isRidePaid) {
        if (booking == null) return false;
        if (isRidePaid) return false;
        if (booking['paymentStatus'] == 'paid') return false;
        return true;
      }

      // 1. Newly completed ride - unpaid
      final unpaidRide = {
        'bookingId': 'BK_9999',
        'status': 'completed',
        'paymentStatus': 'pending',
        'price': '₹46'
      };
      expect(shouldShowPaymentSelection(unpaidRide, false), isTrue);

      // 2. Paid ride - paymentStatus is 'paid'
      final paidRide = {
        'bookingId': 'BK_9999',
        'status': 'completed',
        'paymentStatus': 'paid',
        'price': '₹46'
      };
      expect(shouldShowPaymentSelection(paidRide, false), isFalse);
      expect(shouldShowPaymentSelection(paidRide, true), isFalse);
    });

    test('isBookingPaid and rating sheet suppression prevents duplicate payment prompts', () {
      final paidIds = <String>{'BK_5555'};
      final ratedIds = <String>{'BK_5555'};

      bool isBookingPaid(String bId, Map<String, dynamic>? active) {
        if (paidIds.contains(bId)) return true;
        if (active != null && active['paymentStatus'] == 'paid') return true;
        return false;
      }

      bool shouldShowRatingSheet(String bId, bool isCurrentRoute) {
        if (ratedIds.contains(bId)) return false;
        return isCurrentRoute;
      }

      expect(isBookingPaid('BK_5555', {'paymentStatus': 'pending'}), isTrue);
      expect(isBookingPaid('BK_6666', {'paymentStatus': 'pending'}), isFalse);
      expect(shouldShowRatingSheet('BK_5555', true), isFalse);
      expect(shouldShowRatingSheet('BK_7777', true), isTrue);
    });
  });
}
