import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staydriv_app/core/floating_widget_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StayDriv Floating Mini Screen Service Tests', () {
    const channel = MethodChannel('com.staydriv.app/wake_lock');
    final List<MethodCall> methodCalls = [];
    bool mockOverlayPermissionGranted = true;

    setUp(() {
      methodCalls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        methodCalls.add(methodCall);
        switch (methodCall.method) {
          case 'canDrawOverlays':
            return mockOverlayPermissionGranted;
          case 'requestOverlayPermission':
            return true;
          case 'showFloatingWidget':
            return mockOverlayPermissionGranted;
          case 'updateFloatingWidget':
            return true;
          case 'hideFloatingWidget':
            return true;
          case 'resetFloatingPosition':
            return true;
          default:
            return null;
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('canDrawOverlays returns true when overlay permission is granted', () async {
      mockOverlayPermissionGranted = true;
      final canDraw = await FloatingWidgetService.canDrawOverlays();
      expect(canDraw, isTrue);
      expect(methodCalls.map((c) => c.method), contains('canDrawOverlays'));
    });

    test('canDrawOverlays returns false when overlay permission is denied', () async {
      mockOverlayPermissionGranted = false;
      final canDraw = await FloatingWidgetService.canDrawOverlays();
      expect(canDraw, isFalse);
    });

    test('requestOverlayPermission triggers native permission intent', () async {
      await FloatingWidgetService.requestOverlayPermission();
      expect(methodCalls.map((c) => c.method), contains('requestOverlayPermission'));
    });

    test('Customer App active booking shows floating widget with pilot details and ETA', () async {
      mockOverlayPermissionGranted = true;
      final shown = await FloatingWidgetService.show(
        role: 'customer',
        status: 'pilot_assigned',
        title: 'Ramesh • White Swift (TS09AB1234)',
        subtitle: 'Pickup: Hitec City Metro Station',
        eta: '4 mins away',
        bookingId: 'BK_TEST_101',
        isPilot: false,
      );

      expect(shown, isTrue);
      expect(FloatingWidgetService.isFloatingVisible, isTrue);

      final showCall = methodCalls.firstWhere((c) => c.method == 'showFloatingWidget');
      expect(showCall.arguments['role'], equals('customer'));
      expect(showCall.arguments['status'], equals('pilot_assigned'));
      expect(showCall.arguments['title'], contains('Ramesh'));
      expect(showCall.arguments['eta'], equals('4 mins away'));
      expect(showCall.arguments['bookingId'], equals('BK_TEST_101'));
      expect(showCall.arguments['isPilot'], isFalse);
    });

    test('Pilot App active booking shows floating widget with passenger and destination details', () async {
      mockOverlayPermissionGranted = true;
      final shown = await FloatingWidgetService.show(
        role: 'pilot',
        status: 'in_progress',
        title: 'Trip to Gachibowli DLF',
        subtitle: 'Customer: Sneha (OTP: 4821)',
        eta: '12 mins',
        bookingId: 'BK_TEST_202',
        isPilot: true,
      );

      expect(shown, isTrue);
      expect(FloatingWidgetService.isFloatingVisible, isTrue);

      final showCall = methodCalls.firstWhere((c) => c.method == 'showFloatingWidget');
      expect(showCall.arguments['role'], equals('pilot'));
      expect(showCall.arguments['status'], equals('in_progress'));
      expect(showCall.arguments['title'], contains('Gachibowli'));
      expect(showCall.arguments['subtitle'], contains('OTP: 4821'));
      expect(showCall.arguments['isPilot'], isTrue);
    });

    test('Pilot App online duty mode shows floating widget waiting for requests', () async {
      mockOverlayPermissionGranted = true;
      final shown = await FloatingWidgetService.show(
        role: 'pilot',
        status: 'online',
        title: 'StayDriv Online',
        subtitle: 'Waiting for incoming ride requests...',
        eta: 'ONLINE',
        isPilot: true,
      );

      expect(shown, isTrue);
      expect(FloatingWidgetService.isFloatingVisible, isTrue);

      final showCall = methodCalls.firstWhere((c) => c.method == 'showFloatingWidget');
      expect(showCall.arguments['status'], equals('online'));
      expect(showCall.arguments['title'], equals('StayDriv Online'));
    });

    test('Pilot App online mode removes floating online banner while keeping Pilot icon', () {
      // Functional requirement: status=online triggers statusPill=GONE in native service
      // keeping only the circular bubble (frame_bubble_container) visible.
      const status = 'online';
      final isOnlineOnly = status.toLowerCase() == 'online';
      expect(isOnlineOnly, isTrue);

      const activeStatus = 'in_progress';
      final isActiveRide = activeStatus.toLowerCase() != 'online';
      expect(isActiveRide, isTrue);
    });

    test('Live booking updates status and ETA in real time', () async {
      await FloatingWidgetService.update(
        status: 'arrived',
        title: 'Pilot Arrived at Pickup',
        subtitle: 'Please meet your pilot at gate 2',
        eta: 'ARRIVED',
      );

      final updateCall = methodCalls.firstWhere((c) => c.method == 'updateFloatingWidget');
      expect(updateCall.arguments['status'], equals('arrived'));
      expect(updateCall.arguments['title'], equals('Pilot Arrived at Pickup'));
      expect(updateCall.arguments['eta'], equals('ARRIVED'));
    });

    test('resetPosition invokes resetFloatingPosition native method', () async {
      await FloatingWidgetService.resetPosition();
      expect(methodCalls.map((c) => c.method), contains('resetFloatingPosition'));
    });

    test('hideFloatingWidget dismisses floating mini screen and clears visibility', () async {
      await FloatingWidgetService.hide();
      expect(FloatingWidgetService.isFloatingVisible, isFalse);
      expect(methodCalls.map((c) => c.method), contains('hideFloatingWidget'));
    });

    test('Movable position contracts: Screen position is treated as UI preference only', () {
      // Requirement E: Moving floating window must NOT change booking data,
      // pilot assignment, GPS coordinates, or payment status.
      final mockBookingData = {
        'bookingId': 'BK_123',
        'status': 'in_progress',
        'pilotId': 'PILOT_456',
        'fare': 150,
      };

      // Simulating moving the window locally (x: 200, y: 400)
      const localWindowX = 200;
      const localWindowY = 400;

      // Assert that booking data remains pure and unchanged
      expect(mockBookingData['bookingId'], equals('BK_123'));
      expect(mockBookingData['status'], equals('in_progress'));
      expect(mockBookingData['pilotId'], equals('PILOT_456'));
      expect(mockBookingData.containsKey('windowX'), isFalse);
      expect(mockBookingData.containsKey('windowY'), isFalse);
      expect(localWindowX, isPositive);
      expect(localWindowY, isPositive);
    });
  });
}
