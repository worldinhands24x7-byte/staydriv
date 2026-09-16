import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'api_client.dart';

class TwilioService {
  static const String _accountSid = 'AC00000000000000000000000000000000';
  static const String _authToken = '00000000000000000000000000000000';
  
  // IMPORTANT: Replace this with your actual Twilio phone number
  static const String _fromNumber = '+10000000000'; 
  
  static String? _currentOtp;

  static Future<String?> sendOtp(String phoneNumber) async {
    // For testing purposes, default OTP is 1234 and bypass network call
    _currentOtp = '1234';
    return null;
  }

  static bool verifyOtp(String enteredOtp) {
    if (enteredOtp == '1234') {
      return true;
    }
    if (_currentOtp != null && _currentOtp == enteredOtp) {
      _currentOtp = null; // Clear it to prevent reuse
      return true;
    }
    return false;
  }

  static Future<String?> sendMessage(String phoneNumber, String message) async {
    final formattedNumber = phoneNumber.startsWith('+') ? phoneNumber : '+91$phoneNumber';

    final String urlString = 'https://api.twilio.com/2010-04-01/Accounts/$_accountSid/Messages.json';
    final url = kIsWeb 
        ? Uri.parse('https://corsproxy.io/?' + Uri.encodeComponent(urlString))
        : Uri.parse(urlString);

    final String basicAuth = 'Basic ${base64Encode(utf8.encode('$_accountSid:$_authToken'))}';

    try {
      final response = await ApiClient().post(
        url,
        headers: {
          'Authorization': basicAuth,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'To': formattedNumber,
          'From': _fromNumber,
          'Body': message,
        },
      );

      if (response.statusCode == 201) {
        return null; // success
      } else {
        debugPrint('Twilio Error: ${response.body}');
        try {
          final errorData = jsonDecode(response.body);
          return errorData['message'] ?? 'Twilio API Error: ${response.statusCode}';
        } catch (_) {
          return 'Twilio API Error: ${response.statusCode}';
        }
      }
    } catch (e) {
      debugPrint('Twilio Exception: $e');
      return e.toString();
    }
  }
}
