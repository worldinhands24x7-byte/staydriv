import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'booking_manager.dart';

/// StayDriv Floating Mini Screen Service (movable floating logo & live booking status)
/// Works on Android devices similar to Rapido Captain / Ola floating bubble overlays.
class FloatingWidgetService {
  static const MethodChannel _channel = MethodChannel('com.staydriv.app/wake_lock');

  static bool _isFloatingVisible = false;
  static bool get isFloatingVisible => _isFloatingVisible;

  /// Checks if Android has granted "Display over other apps" (SYSTEM_ALERT_WINDOW)
  static Future<bool> canDrawOverlays() async {
    if (kIsWeb) return false;
    try {
      final bool canDraw = await _channel.invokeMethod('canDrawOverlays') ?? false;
      return canDraw;
    } catch (e) {
      debugPrint('[FloatingWidgetService] Error checking overlay permission: $e');
      return false;
    }
  }

  /// Opens Android Settings page so user can grant "Display over other apps"
  static Future<void> requestOverlayPermission() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } catch (e) {
      debugPrint('[FloatingWidgetService] Error requesting overlay permission: $e');
    }
  }

  /// Shows the floating mini screen when the app is minimized with active booking or when pilot is online
  static Future<bool> show({
    required String role,
    required String status,
    String? title,
    String? subtitle,
    String? eta,
    String? bookingId,
    bool? isPilot,
  }) async {
    if (kIsWeb) return false;
    try {
      final bool shown = await _channel.invokeMethod('showFloatingWidget', {
        'role': role,
        'status': status,
        'title': title ?? 'StayDriv',
        'subtitle': subtitle ?? '',
        'eta': eta ?? '',
        'bookingId': bookingId ?? '',
        'isPilot': isPilot ?? (role.toLowerCase() == 'pilot' || role.toLowerCase() == 'partner'),
      }) ?? false;
      _isFloatingVisible = shown;
      return shown;
    } catch (e) {
      debugPrint('[FloatingWidgetService] Error showing floating widget: $e');
      return false;
    }
  }

  /// Updates live booking data (status, ETA, destination) on the floating mini screen in real time
  static Future<void> update({
    required String status,
    String? title,
    String? subtitle,
    String? eta,
  }) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('updateFloatingWidget', {
        'status': status,
        'title': title ?? '',
        'subtitle': subtitle ?? '',
        'eta': eta ?? '',
      });
    } catch (e) {
      debugPrint('[FloatingWidgetService] Error updating floating widget: $e');
    }
  }

  /// Hides the floating mini screen when app returns to foreground or ride completes/cancels
  static Future<void> hide() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('hideFloatingWidget');
      _isFloatingVisible = false;
    } catch (e) {
      debugPrint('[FloatingWidgetService] Error hiding floating widget: $e');
    }
  }

  /// Resets the floating window position to the default top-right screen area
  static Future<void> resetPosition() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('resetFloatingPosition');
    } catch (e) {
      debugPrint('[FloatingWidgetService] Error resetting floating position: $e');
    }
  }

  /// Universal state synchronizer that checks BookingManager and updates or displays
  /// the movable floating logo and active booking status on mobile screen
  static Future<void> syncWithCurrentState({
    bool isMinimizing = false,
    String? userRole,
  }) async {
    if (kIsWeb) return;

    final active = BookingManager().activeBooking;
    final isDriverOnline = BookingManager().isDriverOnline;
    final role = userRole ?? (isDriverOnline ? 'Pilot' : 'Customer');
    final isCustomer = role.toLowerCase() == 'customer';

    if (active != null) {
      final status = (active['status'] ?? '').toString().toLowerCase();
      final bookingId = (active['bookingId'] ?? active['id'] ?? active['_id'] ?? '').toString();

      if (status == 'completed' || status == 'cancelled') {
        hide();
        return;
      }

      String title;
      String subtitle;
      String eta = (active['eta'] ?? BookingManager().latestEta ?? '').toString().trim();
      final distance = (active['remainingDistance'] ??
              active['distance'] ??
              active['distanceKm'] ??
              BookingManager().latestRemainingDistance ??
              '')
          .toString()
          .trim();

      if (isCustomer) {
        final pilotName = (active['driverName'] ?? active['pilotName'] ?? 'Pilot Partner').toString();
        final vehicle = (active['vehicleType'] ?? active['vehicle'] ?? 'Ride').toString();
        final plate = (active['vehiclePlate'] ?? active['vehicleNumber'] ?? '').toString();

        if (status == 'searching') {
          title = 'Finding your pilot...';
          subtitle = 'Connecting with nearby pilots';
        } else if (status == 'accepted') {
          title = 'Pilot accepted your booking';
          subtitle = '$pilotName • $vehicle ${plate.isNotEmpty ? "($plate)" : ""}';
        } else if (status == 'arriving') {
          title = 'Pilot is on the way';
          final liveInfo = [
            if (eta.isNotEmpty) 'ETA: $eta',
            if (distance.isNotEmpty) distance,
          ].join(' • ');
          subtitle = liveInfo.isNotEmpty ? '$pilotName ($liveInfo)' : '$pilotName is approaching';
        } else if (status == 'arrived') {
          title = 'Pilot has arrived';
          subtitle = '$pilotName is at pickup point';
        } else if (status == 'started' || status == 'in_progress') {
          title = 'Ride in progress';
          final liveInfo = [
            if (eta.isNotEmpty) 'ETA: $eta',
            if (distance.isNotEmpty) distance,
          ].join(' • ');
          subtitle = liveInfo.isNotEmpty ? 'En route • $liveInfo' : 'Heading to destination';
        } else if (status == 'payment_pending') {
          title = 'Ride completed';
          subtitle = 'Complete payment to finish';
        } else {
          title = 'StayDriv Ride';
          subtitle = 'Ride active';
        }
      } else {
        // Pilot mode
        final custName = (active['passengerName'] ?? 'Customer').toString();
        final drop = (active['dropAddress'] ?? active['drop'] ?? '').toString();
        final otp = (active['startOtp'] ?? active['otp'] ?? '').toString();

        if (status == 'incoming') {
          title = 'New Ride Request';
          subtitle = 'Tap to view and accept';
        } else if (status == 'accepted') {
          title = 'Heading to Pickup';
          final liveInfo = [
            if (eta.isNotEmpty) 'ETA: $eta',
            if (distance.isNotEmpty) distance,
          ].join(' • ');
          subtitle = liveInfo.isNotEmpty ? 'Pickup • $liveInfo' : (custName.isNotEmpty ? 'Customer: $custName' : 'Navigate to pickup point');
        } else if (status == 'arrived') {
          title = 'Pilot has arrived';
          subtitle = otp.isNotEmpty ? 'Customer OTP: $otp' : 'Waiting for customer';
        } else if (status == 'started' || status == 'in_progress') {
          title = 'Trip in progress';
          final liveInfo = [
            if (eta.isNotEmpty) 'ETA: $eta',
            if (distance.isNotEmpty) distance,
          ].join(' • ');
          subtitle = liveInfo.isNotEmpty ? 'Drop • $liveInfo' : (drop.isNotEmpty ? 'Drop: $drop' : 'Heading to destination');
        } else if (status == 'payment_pending') {
          title = 'Ride completed';
          subtitle = 'Collect fare from customer';
        } else {
          title = 'StayDriv Pilot';
          subtitle = 'Trip active';
        }
      }

      if (isMinimizing) {
        show(
          role: role,
          status: status,
          title: title,
          subtitle: subtitle,
          eta: eta,
          bookingId: bookingId,
          isPilot: !isCustomer,
        );
      } else if (isFloatingVisible) {
        update(
          status: status,
          title: title,
          subtitle: subtitle,
          eta: eta,
        );
      }
    } else if (!isCustomer && isDriverOnline) {
      if (isMinimizing) {
        show(
          role: 'Pilot',
          status: 'online',
          title: 'StayDriv Pilot Online',
          subtitle: 'Ready to receive ride requests',
          isPilot: true,
        );
      } else if (isFloatingVisible) {
        update(
          status: 'online',
          title: 'StayDriv Pilot Online',
          subtitle: 'Ready to receive ride requests',
        );
      }
    } else {
      hide();
    }
  }
}
