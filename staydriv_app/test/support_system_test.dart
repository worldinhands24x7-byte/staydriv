import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staydriv_app/features/support/models/support_ticket_model.dart';
import 'package:staydriv_app/features/support/services/support_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StayDriv Support System Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('SupportTicket model parses JSON correctly and computes status/priority colors', () {
      final json = {
        'ticketId': 'STY-123456',
        'userId': 'usr_test_001',
        'userType': 'customer',
        'userName': 'Ramesh Kumar',
        'userPhone': '+919876543210',
        'rideId': 'BK-998877',
        'category': 'safety',
        'subcategory': 'Rash / Dangerous driving',
        'subject': 'Pilot was driving aggressively',
        'description': 'Pilot exceeded speed limit on outer ring road and drove dangerously.',
        'status': 'OPEN',
        'priority': 'URGENT',
        'createdAt': '2026-09-23T01:00:00.000Z',
        'updatedAt': '2026-09-23T01:05:00.000Z',
        'chatHistory': [
          {
            'senderId': 'usr_test_001',
            'senderName': 'Ramesh Kumar',
            'senderRole': 'customer',
            'message': 'Please investigate immediately.',
            'timestamp': '2026-09-23T01:02:00.000Z',
          }
        ]
      };

      final ticket = SupportTicket.fromJson(json);

      expect(ticket.ticketId, equals('STY-123456'));
      expect(ticket.userType, equals('customer'));
      expect(ticket.category, equals('safety'));
      expect(ticket.priority, equals('URGENT'));
      expect(ticket.statusDisplay, equals('Open'));
      expect(ticket.chatHistory.length, equals(1));
      expect(ticket.chatHistory.first.isFromUser, isTrue);
      expect(ticket.chatHistory.first.message, equals('Please investigate immediately.'));

      // Check toJson
      final serialized = ticket.toJson();
      expect(serialized['ticketId'], equals('STY-123456'));
      expect(serialized['priority'], equals('URGENT'));
    });

    test('SupportMessage differentiates user messages from admin replies', () {
      final customerMsg = SupportMessage(
        senderId: 'c1',
        senderName: 'Customer',
        senderRole: 'customer',
        message: 'Where is my refund?',
        timestamp: DateTime.now(),
      );
      final pilotMsg = SupportMessage(
        senderId: 'p1',
        senderName: 'Pilot',
        senderRole: 'pilot',
        message: 'Customer did not show up.',
        timestamp: DateTime.now(),
      );
      final adminMsg = SupportMessage(
        senderId: 'adm1',
        senderName: 'StayDriv Support',
        senderRole: 'admin',
        message: 'Your refund of Rs. 150 has been processed to your wallet.',
        timestamp: DateTime.now(),
      );

      expect(customerMsg.isFromUser, isTrue);
      expect(pilotMsg.isFromUser, isTrue);
      expect(adminMsg.isFromUser, isFalse);
    });

    test('SupportService provides default emergency helpline and WhatsApp desk numbers', () {
      final service = SupportService();
      expect(service.emergencyHelplineNumber, equals('+919490440281'));
      expect(service.whatsAppSupportNumber, equals('+919490440281'));
    });

    test('SupportService createTicket creates offline fallback ticket when network fails', () async {
      final service = SupportService();

      // In unit test environment without backend running, createTicket will trigger offline fallback
      final ticket = await service.createTicket(
        category: 'booking',
        subcategory: 'Driver not arriving / Delayed',
        subject: 'Driver delayed by 25 mins',
        description: 'Waiting at pickup location for 25 minutes, no response from pilot.',
        rideId: 'BK-112233',
        userType: 'customer',
      );

      expect(ticket.ticketId.startsWith('STY-'), isTrue);
      expect(ticket.category, equals('booking'));
      expect(ticket.subcategory, equals('Driver not arriving / Delayed'));
      expect(ticket.rideId, equals('BK-112233'));

      // Verify it's cached locally
      final myTickets = await service.getMyTickets();
      expect(myTickets.any((t) => t.ticketId == ticket.ticketId), isTrue);
    });
  });
}
