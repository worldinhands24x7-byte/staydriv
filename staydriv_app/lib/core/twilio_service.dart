import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'api_client.dart';

/// Service for dispatching SMS notifications via StayDriv Backend SMS Gateway (Twilio/DLT)
class TwilioService {
  /// Send an SMS message through the secure StayDriv Backend SMS Gateway
  static Future<String?> sendMessage(String phoneNumber, String message) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'\D'), '');
    final formattedNumber = cleanPhone.length > 10 ? cleanPhone.substring(cleanPhone.length - 10) : cleanPhone;

    try {
      final response = await ApiClient().post(
        Uri.parse('/api/sms/send'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'mobileNumber': formattedNumber,
          'message': message,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return null; // success
      } else {
        debugPrint('SMS Dispatch Error: ${response.body}');
        try {
          final errorData = jsonDecode(response.body);
          return errorData['message'] ?? 'SMS Error: ${response.statusCode}';
        } catch (_) {
          return 'SMS Error: ${response.statusCode}';
        }
      }
    } catch (e) {
      debugPrint('SMS Exception: $e');
      return e.toString();
    }
  }
}
