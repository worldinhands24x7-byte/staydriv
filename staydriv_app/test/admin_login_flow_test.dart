import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:staydriv_app/core/api_client.dart';
import 'package:staydriv_app/core/socket_service.dart';
import 'package:staydriv_app/features/dashboard/screens/home_screen.dart';
import 'package:staydriv_app/services/api_service.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _RealHttpOverrides();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('Admin Authentication Flow Tests', () {
    test('Master admin credentials authenticate successfully with Admin role', () async {
      final res = await ApiService.adminLogin('admin@staydriv.com', 'bhavi@123');
      expect(res['success'], isTrue);
      expect(res['user']['role'], equals('Admin'));
      expect(res['token'], isNotNull);
      expect((res['token'] as String).isNotEmpty, isTrue);
    });

    test('Staff credentials authenticate successfully with Staff role', () async {
      final res = await ApiService.adminLogin('staff@staydriv.com', 'admin@123');
      expect(res['success'], isTrue);
      expect(res['user']['role'], equals('Staff'));
      expect(res['token'], isNotNull);
      expect((res['token'] as String).isNotEmpty, isTrue);
    });

    test('Invalid password fails authentication with clear error message', () async {
      final res = await ApiService.adminLogin('admin@staydriv.com', 'wrongpassword');
      expect(res['success'], isFalse);
      expect(res['message'].toString().toLowerCase(), contains('invalid admin'));
    });

    test('ApiClient attaches and remembers auth token correctly', () {
      const mockToken = 'jwt_test_token_admin_abc123';
      ApiClient.setAuthToken(mockToken);
      expect(ApiClient.authToken, equals(mockToken));
    });
  });

  group('Admin Portal Navigation and Dashboard Parameters Tests', () {
    test('HomeScreen properly initializes with Admin role and credentials', () {
      const homeScreen = HomeScreen(
        userName: 'Admin User',
        userRole: 'Admin',
        phoneNumber: '9010922111',
      );
      expect(homeScreen.userRole, equals('Admin'));
      expect(homeScreen.userName, equals('Admin User'));
      expect(homeScreen.phoneNumber, equals('9010922111'));
    });
  });

  group('OTP Authentication Flow Tests', () {
    test('sendOtp returns success without network error block', () async {
      final res = await ApiService.sendOtp('9010922111', role: 'ADMIN');
      expect(res['success'], isTrue);
      expect(res['message'], isNotNull);
    });

    test('verifyOtp with generated in-app code verifies successfully and sets token', () async {
      final sendRes = await ApiService.sendOtp('9010922112', role: 'ADMIN');
      expect(sendRes['success'], isTrue);
      final code = (sendRes['verificationCode'] ?? sendRes['code'])?.toString();
      expect(code, isNotNull);
      final res = await ApiService.verifyOtp('9010922112', code!, role: 'ADMIN');
      expect(res['success'], isTrue);
      expect(res['user']['role'], equals('Admin'));
      expect(res['token'], isNotNull);
      expect(ApiClient.authToken, equals(res['token']));
    });

    test('verifyOtp with invalid OTP fails gracefully', () async {
      final res = await ApiService.verifyOtp('9010922111', '888888', role: 'ADMIN');
      expect(res['success'], isFalse);
      expect(res['message'].toString().toLowerCase(), contains('invalid'));
    });
  });
}
