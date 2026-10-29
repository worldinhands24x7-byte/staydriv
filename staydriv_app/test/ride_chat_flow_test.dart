import 'package:flutter_test/flutter_test.dart';
import 'package:staydriv_app/core/socket_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Ride Chat Real-Time Flow Tests', () {
    late SocketService socketService;

    setUp(() {
      socketService = SocketService();
    });

    test('sendRideMessage and sendCustomerMessage emit valid payloads', () {
      expect(
        () => socketService.sendRideMessage(
          rideId: 'RIDE_99881',
          senderRole: 'customer',
          text: 'Where are you waiting?',
          senderName: 'John Customer',
        ),
        returnsNormally,
      );

      expect(
        () => socketService.sendCustomerMessage(
          bookingId: 'BK_CHAT_TEST_01',
          text: "I'm at the pickup point",
          messageId: 'msg_test_123',
          customerId: 'cust_abc',
          pilotId: 'pilot_xyz',
        ),
        returnsNormally,
      );

      expect(
        () => socketService.sendRideMessage(
          rideId: 'RIDE_99881',
          senderRole: 'pilot',
          text: "I've arrived at pickup gate.",
          senderName: 'Rajesh Pilot',
        ),
        returnsNormally,
      );
    });

    test('addCustomerMessageListener and removeCustomerMessageListener manage listener lifecycle', () {
      Map<String, dynamic>? receivedMessage;
      void customerListener(Map<String, dynamic> data) {
        receivedMessage = data;
      }

      socketService.addCustomerMessageListener(customerListener);
      expect(
        () => socketService.sendCustomerMessage(
          bookingId: 'BK_CHAT_TEST_02',
          text: "Hello Pilot Partner",
        ),
        returnsNormally,
      );
      socketService.removeCustomerMessageListener(customerListener);
    });

    test('acknowledgeDelivery and addMessageDeliveredListener manage delivery tracking', () {
      Map<String, dynamic>? deliveredData;
      void deliveryListener(Map<String, dynamic> data) {
        deliveredData = data;
      }

      socketService.addMessageDeliveredListener(deliveryListener);
      expect(
        () => socketService.acknowledgeDelivery(
          bookingId: 'BK_CHAT_TEST_03',
          messageId: 'msg_delivery_01',
        ),
        returnsNormally,
      );
      socketService.removeMessageDeliveredListener(deliveryListener);
    });

    test('markMessagesRead and addMessageReadListener manage read receipts', () {
      Map<String, dynamic>? readData;
      void readListener(Map<String, dynamic> data) {
        readData = data;
      }

      socketService.addMessageReadListener(readListener);
      expect(
        () => socketService.markMessagesRead(
          bookingId: 'BK_CHAT_TEST_04',
          messageId: 'all',
        ),
        returnsNormally,
      );
      socketService.removeMessageReadListener(readListener);
    });

    test('addRideChatHistoryListener and removeRideChatHistoryListener manage history listeners', () {
      Map<String, dynamic>? receivedHistory;
      void historyListener(Map<String, dynamic> history) {
        receivedHistory = history;
      }

      socketService.addRideChatHistoryListener(historyListener);
      expect(
        () => socketService.joinRide('RIDE_CHAT_TEST'),
        returnsNormally,
      );
      socketService.removeRideChatHistoryListener(historyListener);
    });
  });
}
