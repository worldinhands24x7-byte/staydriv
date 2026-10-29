import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'network_config.dart';

typedef SocketEventCallback = void Function(Map<String, dynamic> data);

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  static bool disableForTesting = false;

  IO.Socket? _socket;
  IO.Socket? get socket => _socket;
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  String? _lastJoinedRestaurantId;
  String? _lastJoinedPilotId;
  String? _lastJoinedFoodOrderId;

  final Set<SocketEventCallback> _incomingRequestListeners = {};
  final Set<SocketEventCallback> _bookingUpdateListeners = {};
  final Set<SocketEventCallback> _rideCancelledListeners = {};
  final Set<SocketEventCallback> _paymentSuccessListeners = {};
  final Set<SocketEventCallback> _rideLocationListeners = {};
  final Set<SocketEventCallback> _rideMessageListeners = {};
  final Set<SocketEventCallback> _customerMessageListeners = {};
  final Set<SocketEventCallback> _messageDeliveredListeners = {};
  final Set<SocketEventCallback> _messageReadListeners = {};
  final Set<SocketEventCallback> _rideChatHistoryListeners = {};
  final Set<SocketEventCallback> _pilotVerificationListeners = {};
  final Set<SocketEventCallback> _adminPilotsUpdatedListeners = {};
  final Set<SocketEventCallback> _foodOrderIncomingListeners = {};
  final Set<SocketEventCallback> _foodOrderStatusListeners = {};
  final Set<SocketEventCallback> _foodDeliveryRequestListeners = {};
  final Set<SocketEventCallback> _foodMenuUpdatedListeners = {};
  final Set<SocketEventCallback> _restaurantUpdatedListeners = {};
  final Set<SocketEventCallback> _promotionsUpdatedListeners = {};
  final Set<SocketEventCallback> _inAppNotificationListeners = {};
  final Set<SocketEventCallback> _pilotBookingAccessListeners = {};
  final Set<SocketEventCallback> _pilotDailyPlanListeners = {};

  void addPilotBookingAccessListener(SocketEventCallback callback) {
    _pilotBookingAccessListeners.add(callback);
  }

  void removePilotBookingAccessListener(SocketEventCallback callback) {
    _pilotBookingAccessListeners.remove(callback);
  }

  void addPilotDailyPlanListener(SocketEventCallback callback) {
    _pilotDailyPlanListeners.add(callback);
  }

  void removePilotDailyPlanListener(SocketEventCallback callback) {
    _pilotDailyPlanListeners.remove(callback);
  }

  void addInAppNotificationListener(SocketEventCallback callback) {
    _inAppNotificationListeners.add(callback);
  }

  void removeInAppNotificationListener(SocketEventCallback callback) {
    _inAppNotificationListeners.remove(callback);
  }

  void addPromotionsUpdatedListener(SocketEventCallback callback) {
    _promotionsUpdatedListeners.add(callback);
  }

  void removePromotionsUpdatedListener(SocketEventCallback callback) {
    _promotionsUpdatedListeners.remove(callback);
  }

  void addFoodOrderIncomingListener(SocketEventCallback callback) {
    _foodOrderIncomingListeners.add(callback);
  }

  void removeFoodOrderIncomingListener(SocketEventCallback callback) {
    _foodOrderIncomingListeners.remove(callback);
  }

  void addFoodOrderStatusListener(SocketEventCallback callback) {
    _foodOrderStatusListeners.add(callback);
  }

  void removeFoodOrderStatusListener(SocketEventCallback callback) {
    _foodOrderStatusListeners.remove(callback);
  }

  void addFoodDeliveryRequestListener(SocketEventCallback callback) {
    _foodDeliveryRequestListeners.add(callback);
  }

  void removeFoodDeliveryRequestListener(SocketEventCallback callback) {
    _foodDeliveryRequestListeners.remove(callback);
  }

  void addFoodMenuUpdatedListener(SocketEventCallback callback) {
    _foodMenuUpdatedListeners.add(callback);
  }

  void removeFoodMenuUpdatedListener(SocketEventCallback callback) {
    _foodMenuUpdatedListeners.remove(callback);
  }

  void addRestaurantUpdatedListener(SocketEventCallback callback) {
    _restaurantUpdatedListeners.add(callback);
  }

  void removeRestaurantUpdatedListener(SocketEventCallback callback) {
    _restaurantUpdatedListeners.remove(callback);
  }

  void joinRestaurant(String restaurantId) {
    _lastJoinedRestaurantId = restaurantId;
    if (_socket != null && restaurantId.isNotEmpty) {
      _socket!.emit('join_restaurant', {'restaurantId': restaurantId});
      debugPrint('[SocketService] Emitted join_restaurant: $restaurantId');
    }
  }

  void leaveRestaurant(String restaurantId) {
    if (_lastJoinedRestaurantId == restaurantId) {
      _lastJoinedRestaurantId = null;
    }
    if (_socket != null && restaurantId.isNotEmpty) {
      _socket!.emit('leave_restaurant', {'restaurantId': restaurantId});
      debugPrint('[SocketService] Emitted leave_restaurant: $restaurantId');
    }
  }

  void joinPilotFood(String pilotId) {
    _lastJoinedPilotId = pilotId;
    if (_socket != null) {
      _socket!.emit('join_pilot_food', {'pilotId': pilotId});
      debugPrint('[SocketService] Emitted join_pilot_food: $pilotId');
    }
  }

  void joinFoodOrder(String orderId) {
    _lastJoinedFoodOrderId = orderId;
    if (_socket != null && orderId.isNotEmpty) {
      _socket!.emit('join_food_order', {'orderId': orderId});
      debugPrint('[SocketService] Emitted join_food_order: $orderId');
    }
  }

  void addPilotVerificationListener(SocketEventCallback callback) {
    _pilotVerificationListeners.add(callback);
  }

  void removePilotVerificationListener(SocketEventCallback callback) {
    _pilotVerificationListeners.remove(callback);
  }

  void addAdminPilotsUpdatedListener(SocketEventCallback callback) {
    _adminPilotsUpdatedListeners.add(callback);
  }

  void removeAdminPilotsUpdatedListener(SocketEventCallback callback) {
    _adminPilotsUpdatedListeners.remove(callback);
  }

  void addIncomingRequestListener(SocketEventCallback callback) {
    _incomingRequestListeners.add(callback);
  }

  void removeIncomingRequestListener(SocketEventCallback callback) {
    _incomingRequestListeners.remove(callback);
  }

  void addBookingUpdateListener(SocketEventCallback callback) {
    _bookingUpdateListeners.add(callback);
  }

  void removeBookingUpdateListener(SocketEventCallback callback) {
    _bookingUpdateListeners.remove(callback);
  }

  void addRideCancelledListener(SocketEventCallback callback) {
    _rideCancelledListeners.add(callback);
  }

  void removeRideCancelledListener(SocketEventCallback callback) {
    _rideCancelledListeners.remove(callback);
  }

  void addPaymentSuccessListener(SocketEventCallback callback) {
    _paymentSuccessListeners.add(callback);
  }

  void removePaymentSuccessListener(SocketEventCallback callback) {
    _paymentSuccessListeners.remove(callback);
  }

  void addRideLocationListener(SocketEventCallback callback) {
    _rideLocationListeners.add(callback);
  }

  void removeRideLocationListener(SocketEventCallback callback) {
    _rideLocationListeners.remove(callback);
  }

  void addRideMessageListener(SocketEventCallback callback) {
    _rideMessageListeners.add(callback);
  }

  void removeRideMessageListener(SocketEventCallback callback) {
    _rideMessageListeners.remove(callback);
  }

  void addCustomerMessageListener(SocketEventCallback callback) {
    _customerMessageListeners.add(callback);
  }

  void removeCustomerMessageListener(SocketEventCallback callback) {
    _customerMessageListeners.remove(callback);
  }

  void addMessageDeliveredListener(SocketEventCallback callback) {
    _messageDeliveredListeners.add(callback);
  }

  void removeMessageDeliveredListener(SocketEventCallback callback) {
    _messageDeliveredListeners.remove(callback);
  }

  void addMessageReadListener(SocketEventCallback callback) {
    _messageReadListeners.add(callback);
  }

  void removeMessageReadListener(SocketEventCallback callback) {
    _messageReadListeners.remove(callback);
  }

  void addRideChatHistoryListener(SocketEventCallback callback) {
    _rideChatHistoryListeners.add(callback);
  }

  void removeRideChatHistoryListener(SocketEventCallback callback) {
    _rideChatHistoryListeners.remove(callback);
  }

  final Set<SocketEventCallback> _roundTripLegListeners = {};

  void addRoundTripLegListener(SocketEventCallback callback) {
    _roundTripLegListeners.add(callback);
  }

  void removeRoundTripLegListener(SocketEventCallback callback) {
    _roundTripLegListeners.remove(callback);
  }

  void emitRoundTripLegUpdate(Map<String, dynamic> data) {
    _socket?.emit('round_trip_leg_update', data);
  }

  void clearAllListeners() {
    _incomingRequestListeners.clear();
    _bookingUpdateListeners.clear();
    _rideCancelledListeners.clear();
    _paymentSuccessListeners.clear();
    _rideLocationListeners.clear();
    _rideMessageListeners.clear();
    _customerMessageListeners.clear();
    _messageDeliveredListeners.clear();
    _messageReadListeners.clear();
    _rideChatHistoryListeners.clear();
    _pilotVerificationListeners.clear();
    _foodOrderIncomingListeners.clear();
    _foodOrderStatusListeners.clear();
    _foodDeliveryRequestListeners.clear();
    _foodMenuUpdatedListeners.clear();
    _restaurantUpdatedListeners.clear();
    _pilotBookingAccessListeners.clear();
    _pilotDailyPlanListeners.clear();
  }

  void initSocket() {
    if (disableForTesting) return;
    // If socket already exists, do not recreate multiple connections
    if (_socket != null) {
      if (_socket!.connected) return;
      try {
        debugPrint('[SocketService] Re-connecting existing socket instance...');
        _socket!.connect();
      } catch (e) {
        debugPrint('[SocketService] Error reconnecting existing socket: $e');
      }
      return;
    }

    try {
      final backend = NetworkConfig.backendUrl;
      debugPrint('[SocketService] Connecting to Socket.IO at $backend...');

      _socket = IO.io(
        backend,
        IO.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .enableAutoConnect()
            .enableReconnection()
            .setReconnectionDelay(1000)
            .setReconnectionDelayMax(5000)
            .setReconnectionAttempts(99999)
            .build(),
      );

      _socket!.onConnect((_) {
        _isConnected = true;
        debugPrint('[SocketService] Connected to backend Socket.IO: ${_socket?.id}');
        if (_lastJoinedRestaurantId != null && _lastJoinedRestaurantId!.isNotEmpty) {
          _socket!.emit('join_restaurant', {'restaurantId': _lastJoinedRestaurantId});
          debugPrint('[SocketService] Re-joined restaurant: $_lastJoinedRestaurantId');
        }
        if (_lastJoinedPilotId != null && _lastJoinedPilotId!.isNotEmpty) {
          _socket!.emit('join_pilot_food', {'pilotId': _lastJoinedPilotId});
          debugPrint('[SocketService] Re-joined pilot food: $_lastJoinedPilotId');
        }
        if (_lastJoinedFoodOrderId != null && _lastJoinedFoodOrderId!.isNotEmpty) {
          _socket!.emit('join_food_order', {'orderId': _lastJoinedFoodOrderId});
          debugPrint('[SocketService] Re-joined food order: $_lastJoinedFoodOrderId');
        }
      });

      _socket!.onDisconnect((_) {
        _isConnected = false;
        debugPrint('[SocketService] Disconnected from backend Socket.IO');
      });

      _socket!.onConnectError((err) {
        _isConnected = false;
        debugPrint('[SocketService] Socket connection error: $err');
      });

      // Clear any prior socket-level handlers to guarantee no duplicate executions
      _socket!.off('incoming_request');
      _socket!.off('booking_update');
      _socket!.off('ride_cancelled');
      _socket!.off('booking_cancelled');
      _socket!.off('payment_success');
      _socket!.off('ride_location_update');
      _socket!.off('ride_message');
      _socket!.off('customer_message');
      _socket!.off('message_delivered');
      _socket!.off('message_read');
      _socket!.off('ride_chat_history');

      _socket!.on('customer_message', (data) {
        debugPrint('[SocketService] Received customer_message: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          for (var listener in List.of(_customerMessageListeners)) {
            try {
              listener(map);
            } catch (e) {
              debugPrint('[SocketService] Error dispatching customer_message: $e');
            }
          }
          // Also invoke rideMessageListeners for backward compatibility
          for (var listener in List.of(_rideMessageListeners)) {
            try {
              listener(map);
            } catch (e) {
              debugPrint('[SocketService] Error dispatching to rideMessageListener: $e');
            }
          }
        }
      });

      _socket!.on('message_delivered', (data) {
        debugPrint('[SocketService] Received message_delivered: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          for (var listener in List.of(_messageDeliveredListeners)) {
            try {
              listener(map);
            } catch (e) {
              debugPrint('[SocketService] Error dispatching message_delivered: $e');
            }
          }
        }
      });

      _socket!.on('message_read', (data) {
        debugPrint('[SocketService] Received message_read: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          for (var listener in List.of(_messageReadListeners)) {
            try {
              listener(map);
            } catch (e) {
              debugPrint('[SocketService] Error dispatching message_read: $e');
            }
          }
        }
      });

      _socket!.on('ride_message', (data) {
        debugPrint('[SocketService] Received ride_message: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          for (var listener in List.of(_rideMessageListeners)) {
            try {
              listener(map);
            } catch (e) {
              debugPrint('[SocketService] Error dispatching ride_message: $e');
            }
          }
        }
      });

      _socket!.on('ride_chat_history', (data) {
        debugPrint('[SocketService] Received ride_chat_history');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          for (var listener in List.of(_rideChatHistoryListeners)) {
            try {
              listener(map);
            } catch (e) {
              debugPrint('[SocketService] Error dispatching ride_chat_history: $e');
            }
          }
        }
      });

      _socket!.on('ride_location_update', (data) {
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          for (var listener in List.of(_rideLocationListeners)) {
            try {
              listener(map);
            } catch (e) {
              debugPrint('[SocketService] Error dispatching ride_location_update: $e');
            }
          }
        }
      });

      _socket!.on('round_trip_leg_update', (data) {
        debugPrint('[SocketService] Received round_trip_leg_update: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          for (var listener in List.of(_roundTripLegListeners)) {
            try {
              listener(map);
            } catch (e) {
              debugPrint('[SocketService] Error dispatching round_trip_leg_update: $e');
            }
          }
        }
      });

      _socket!.on('incoming_request', (data) {
        debugPrint('[SocketService] Received incoming_request: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          for (var listener in List.of(_incomingRequestListeners)) {
            try {
              listener(map);
            } catch (e) {
              debugPrint('[SocketService] Error dispatching incoming_request: $e');
            }
          }
        }
      });

      _socket!.on('booking_update', (data) {
        debugPrint('[SocketService] Received booking_update: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          for (var listener in List.of(_bookingUpdateListeners)) {
            try {
              listener(map);
            } catch (e) {
              debugPrint('[SocketService] Error dispatching booking_update: $e');
            }
          }
        }
      });

      _socket!.on('booking_accepted', (data) {
        debugPrint('[SocketService] Received booking_accepted: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          for (var listener in List.of(_bookingUpdateListeners)) {
            try {
              listener(map);
            } catch (e) {
              debugPrint('[SocketService] Error dispatching booking_accepted: $e');
            }
          }
        }
      });

      _socket!.on('payment_success', (data) {
        debugPrint('[SocketService] Received payment_success: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          for (var listener in List.of(_paymentSuccessListeners)) {
            try {
              listener(map);
            } catch (e) {
              debugPrint('[SocketService] Error dispatching payment_success: $e');
            }
          }
        }
      });

      _socket!.on('ride_cancelled', (data) {
        debugPrint('[SocketService] Received ride_cancelled: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          for (var listener in List.of(_rideCancelledListeners)) {
            try {
              listener(map);
            } catch (e) {
              debugPrint('[SocketService] Error dispatching ride_cancelled: $e');
            }
          }
        }
      });

      _socket!.on('booking_cancelled', (data) {
        debugPrint('[SocketService] Received booking_cancelled: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          for (var listener in List.of(_rideCancelledListeners)) {
            try {
              listener(map);
            } catch (e) {
              debugPrint('[SocketService] Error dispatching booking_cancelled: $e');
            }
          }
        }
      });

      _socket!.on('pilot_approval_updated', (data) {
        debugPrint('[SocketService] Received pilot_approval_updated: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          for (var listener in List.of(_pilotVerificationListeners)) {
            try {
              listener(map);
            } catch (e) {
              debugPrint('[SocketService] Error dispatching pilot_approval_updated: $e');
            }
          }
        }
      });

      _socket!.on('pilot_status_updated', (data) {
        debugPrint('[SocketService] Received pilot_status_updated: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          for (var listener in List.of(_pilotVerificationListeners)) {
            try {
              listener(map);
            } catch (e) {
              debugPrint('[SocketService] Error dispatching pilot_status_updated: $e');
            }
          }
        }
      });

      _socket!.on('admin_pilots_updated', (data) {
        debugPrint('[SocketService] Received admin_pilots_updated: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          for (var listener in List.of(_adminPilotsUpdatedListeners)) {
            try {
              listener(map);
            } catch (e) {
              debugPrint('[SocketService] Error dispatching admin_pilots_updated: $e');
            }
          }
        }
      });

      // --- STAYDRIV FOOD ORDER NOW & RESTAURANT PARTNER REAL-TIME SOCKET EVENTS ---
      void dispatchFoodIncoming(dynamic data) {
        debugPrint('[SocketService] Received food incoming order event: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          for (var listener in List.of(_foodOrderIncomingListeners)) {
            try {
              listener(map);
            } catch (e) {
              debugPrint('[SocketService] Error food incoming listener: $e');
            }
          }
        }
      }

      void dispatchFoodStatus(dynamic data) {
        debugPrint('[SocketService] Received food order status update: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          for (var listener in List.of(_foodOrderStatusListeners)) {
            try {
              listener(map);
            } catch (e) {
              debugPrint('[SocketService] Error food status listener: $e');
            }
          }
        }
      }

      void dispatchFoodDeliveryRequest(dynamic data) {
        debugPrint('[SocketService] Received food delivery request event: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          for (var listener in List.of(_foodDeliveryRequestListeners)) {
            try {
              listener(map);
            } catch (e) {
              debugPrint('[SocketService] Error food delivery req listener: $e');
            }
          }
        }
      }

      void dispatchFoodMenuUpdated(dynamic data) {
        debugPrint('[SocketService] Received food_menu_updated / food_item_updated: $data');
        final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
        for (var listener in List.of(_foodMenuUpdatedListeners)) {
          try {
            listener(map);
          } catch (e) {
            debugPrint('[SocketService] Error food menu updated listener: $e');
          }
        }
      }

      void dispatchRestaurantUpdated(dynamic data) {
        debugPrint('[SocketService] Received restaurant_updated: $data');
        final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
        for (var listener in List.of(_restaurantUpdatedListeners)) {
          try {
            listener(map);
          } catch (e) {
            debugPrint('[SocketService] Error restaurant updated listener: $e');
          }
        }
      }

      void dispatchPromotionsUpdated(dynamic data) {
        debugPrint('[SocketService] Received promotions_updated: $data');
        final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
        for (var listener in List.of(_promotionsUpdatedListeners)) {
          try {
            listener(map);
          } catch (e) {
            debugPrint('[SocketService] Error promotions updated listener: $e');
          }
        }
      }

      _socket!.off('promotions_updated');
      _socket!.on('promotions_updated', dispatchPromotionsUpdated);

      _socket!.off('restaurant_order_incoming');
      _socket!.off('food_order_created');
      _socket!.off('food_order.created');
      _socket!.off('food_order_status_update');
      _socket!.off('food_order.accepted');
      _socket!.off('food_order.preparing');
      _socket!.off('food_order.ready_for_pickup');
      _socket!.off('food_order.delivered');
      _socket!.off('food_order.rejected');
      _socket!.off('food_order.cancelled');
      _socket!.off('food_delivery_request');
      _socket!.off('food_delivery.assigned');
      _socket!.off('food_delivery_available');
      _socket!.off('food_menu_updated');
      _socket!.off('food_item_updated');
      _socket!.off('food_item_added');
      _socket!.off('food_item_deleted');
      _socket!.off('restaurant_updated');
      _socket!.off('admin_restaurant_approval_changed');
      _socket!.off('restaurant_application_status_changed');

      _socket!.on('restaurant_order_incoming', dispatchFoodIncoming);
      _socket!.on('food_order_created', dispatchFoodIncoming);
      _socket!.on('food_order.created', dispatchFoodIncoming);

      _socket!.on('food_order_status_update', dispatchFoodStatus);
      _socket!.on('food_order.accepted', dispatchFoodStatus);
      _socket!.on('food_order.preparing', dispatchFoodStatus);
      _socket!.on('food_order.ready_for_pickup', dispatchFoodStatus);
      _socket!.on('food_order.delivered', dispatchFoodStatus);
      _socket!.on('food_order.rejected', dispatchFoodStatus);
      _socket!.on('food_order.cancelled', dispatchFoodStatus);
      _socket!.on('food_delivery.assigned', dispatchFoodStatus);

      _socket!.on('food_delivery_request', dispatchFoodDeliveryRequest);
      _socket!.on('food_delivery_available', dispatchFoodDeliveryRequest);

      _socket!.on('food_menu_updated', dispatchFoodMenuUpdated);
      _socket!.on('food_item_updated', dispatchFoodMenuUpdated);
      _socket!.on('food_item_added', dispatchFoodMenuUpdated);
      _socket!.on('food_item_deleted', dispatchFoodMenuUpdated);
      _socket!.on('restaurant_updated', dispatchRestaurantUpdated);
      _socket!.on('admin_restaurant_approval_changed', dispatchRestaurantUpdated);
      _socket!.on('restaurant_application_status_changed', dispatchRestaurantUpdated);

      void dispatchInAppNotification(dynamic data) {
        debugPrint('[SocketService] Received in-app notification event: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          for (var listener in List.of(_inAppNotificationListeners)) {
            try {
              listener(map);
            } catch (e) {
              debugPrint('[SocketService] Error in-app notification listener: $e');
            }
          }
        }
      }

      _socket!.off('new_in_app_notification');
      _socket!.off('push_notification_broadcast');
      _socket!.off('push_notification_customers');
      _socket!.off('push_notification_partners');

      _socket!.on('new_in_app_notification', dispatchInAppNotification);
      _socket!.on('push_notification_broadcast', dispatchInAppNotification);
      _socket!.on('push_notification_customers', dispatchInAppNotification);
      _socket!.on('push_notification_partners', dispatchInAppNotification);

      // --- PILOT ₹20 DAILY PLAN & ADMIN BOOKING ACCESS CONTROL ---
      void dispatchPilotBookingAccess(dynamic data) {
        debugPrint('[SocketService] Received pilot booking access event: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          for (var listener in List.of(_pilotBookingAccessListeners)) {
            try {
              listener(map);
            } catch (e) {
              debugPrint('[SocketService] Error pilot booking access listener: $e');
            }
          }
        }
      }

      void dispatchPilotDailyPlan(dynamic data) {
        debugPrint('[SocketService] Received pilot daily plan event: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          for (var listener in List.of(_pilotDailyPlanListeners)) {
            try {
              listener(map);
            } catch (e) {
              debugPrint('[SocketService] Error pilot daily plan listener: $e');
            }
          }
        }
      }

      _socket!.off('pilot_booking_access_changed');
      _socket!.off('pilot_booking_access_status');
      _socket!.off('pilot_duty_status_changed');
      _socket!.off('driver_status_changed');
      _socket!.off('pilot_daily_plan_updated');

      _socket!.on('pilot_booking_access_changed', dispatchPilotBookingAccess);
      _socket!.on('pilot_booking_access_status', dispatchPilotBookingAccess);
      _socket!.on('pilot_duty_status_changed', dispatchPilotBookingAccess);
      _socket!.on('driver_status_changed', (dynamic data) {
        if (data is Map &&
            (data.containsKey('bookingAccessEnabled') ||
                data.containsKey('bookingAccessStatus') ||
                data.containsKey('bookingAccess'))) {
          dispatchPilotBookingAccess(data);
        }
      });
      _socket!.on('pilot_daily_plan_updated', dispatchPilotDailyPlan);
    } catch (e) {
      debugPrint('[SocketService] Initialization error: $e');
    }
  }

  void emitDriverUpdate({
    required String uid,
    required bool online,
    required double lat,
    required double lng,
    required String vehicle,
    bool? rideServiceEnabled,
    bool? foodServiceEnabled,
  }) {
    if (_socket == null || !_isConnected) {
      initSocket();
    }
    try {
      final payload = {
        'uid': uid,
        'online': online,
        'lat': lat,
        'lng': lng,
        'vehicle': vehicle,
        if (rideServiceEnabled != null) 'rideServiceEnabled': rideServiceEnabled,
        if (foodServiceEnabled != null) 'foodServiceEnabled': foodServiceEnabled,
      };
      _socket?.emit('driver_update', payload);
      _socket?.emit('driver_online', payload);
      debugPrint('[SocketService] Emitted driver_update: $payload');
    } catch (e) {
      debugPrint('[SocketService] Error emitting driver_update: $e');
    }
  }

  void emitServicePreferencesUpdate({
    required String uid,
    required bool rideServiceEnabled,
    required bool foodServiceEnabled,
  }) {
    if (_socket == null || !_isConnected) {
      initSocket();
    }
    try {
      final payload = {
        'uid': uid,
        'rideServiceEnabled': rideServiceEnabled,
        'foodServiceEnabled': foodServiceEnabled,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      _socket?.emit('pilot_service_preferences_update', payload);
      debugPrint('[SocketService] Emitted pilot_service_preferences_update: $payload');
    } catch (e) {
      debugPrint('[SocketService] Error emitting pilot_service_preferences_update: $e');
    }
  }

  void emitRideLocation({
    required String rideId,
    required String pilotId,
    String vehicleType = 'Bike',
    required double latitude,
    required double longitude,
    required double heading,
    required double speed,
    double accuracy = 5.0,
    required int timestamp,
    required String remainingDistance,
    required String eta,
    required String navigationStatus,
  }) {
    if (_socket == null || !_isConnected) {
      initSocket();
    }
    try {
      final payload = {
        'rideId': rideId,
        'pilotId': pilotId,
        'vehicleType': vehicleType,
        'latitude': latitude,
        'longitude': longitude,
        'heading': heading,
        'speed': speed,
        'accuracy': accuracy,
        'timestamp': timestamp,
        'remainingDistance': remainingDistance,
        'eta': eta,
        'navigationStatus': navigationStatus,
      };
      _socket?.emit('ride_location_update', payload);
    } catch (e) {
      debugPrint('[SocketService] Error emitting ride_location_update: $e');
    }
  }

  void joinRide(String rideId) {
    if (rideId.isEmpty) return;
    if (_socket == null || !_isConnected) {
      initSocket();
    }
    try {
      _socket?.emit('join_ride', {'rideId': rideId, 'bookingId': rideId});
      _socket?.emit('join_booking', {'bookingId': rideId, 'rideId': rideId});
      debugPrint('[SocketService] Emitted join_ride & join_booking for rideId: $rideId');
    } catch (e) {
      debugPrint('[SocketService] Error joining ride room: $e');
    }
  }

  void leaveRide(String rideId) {
    if (rideId.isEmpty) return;
    try {
      _socket?.emit('leave_ride', {'rideId': rideId, 'bookingId': rideId});
      debugPrint('[SocketService] Emitted leave_ride for rideId: $rideId');
    } catch (e) {
      debugPrint('[SocketService] Error leaving ride room: $e');
    }
  }

  void sendRideMessage({
    required String rideId,
    required String senderRole,
    required String text,
    String? messageId,
    String? senderName,
    String? customerId,
    String? pilotId,
  }) {
    if (rideId.isEmpty || text.trim().isEmpty) return;
    if (_socket == null || !_isConnected) {
      initSocket();
    }
    final mId = messageId ?? 'msg_${DateTime.now().millisecondsSinceEpoch}_${rideId.hashCode.abs() % 10000}';
    final payload = {
      'messageId': mId,
      'rideId': rideId,
      'bookingId': rideId,
      'customerId': customerId ?? '',
      'pilotId': pilotId ?? '',
      'senderRole': senderRole,
      'senderName': senderName ?? (senderRole.toLowerCase() == 'pilot' ? 'Pilot Partner' : 'Customer'),
      'text': text.trim(),
      'message': text.trim(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    try {
      _socket?.emit('send_ride_message', payload);
      _socket?.emit('send_customer_message', payload);
      debugPrint('[SocketService] Emitted send_ride_message & send_customer_message for rideId: $rideId by $senderRole');
    } catch (e) {
      debugPrint('[SocketService] Error emitting send_ride_message: $e');
    }
  }

  void sendCustomerMessage({
    required String bookingId,
    required String text,
    String? messageId,
    String? customerId,
    String? pilotId,
    String? senderName,
  }) {
    sendRideMessage(
      rideId: bookingId,
      senderRole: 'CUSTOMER',
      text: text,
      messageId: messageId,
      customerId: customerId,
      pilotId: pilotId,
      senderName: senderName ?? 'Customer',
    );
  }

  void acknowledgeDelivery({
    required String bookingId,
    required String messageId,
  }) {
    if (bookingId.isEmpty || messageId.isEmpty) return;
    if (_socket == null || !_isConnected) {
      initSocket();
    }
    try {
      final payload = {
        'messageId': messageId,
        'bookingId': bookingId,
        'rideId': bookingId,
      };
      _socket?.emit('message_delivered', payload);
      debugPrint('[SocketService] Emitted message_delivered for messageId: $messageId in bookingId: $bookingId');
    } catch (e) {
      debugPrint('[SocketService] Error emitting message_delivered: $e');
    }
  }

  void markMessagesRead({
    required String bookingId,
    String? messageId,
  }) {
    if (bookingId.isEmpty) return;
    if (_socket == null || !_isConnected) {
      initSocket();
    }
    try {
      final payload = {
        'bookingId': bookingId,
        'rideId': bookingId,
        'messageId': messageId ?? 'all',
      };
      _socket?.emit('message_read', payload);
      debugPrint('[SocketService] Emitted message_read for bookingId: $bookingId');
    } catch (e) {
      debugPrint('[SocketService] Error emitting message_read: $e');
    }
  }

  void joinTrack(String token) {
    if (token.isEmpty) return;
    if (_socket == null || !_isConnected) {
      initSocket();
    }
    try {
      _socket?.emit('join_track', {'token': token});
      debugPrint('[SocketService] Emitted join_track for token: $token');
    } catch (e) {
      debugPrint('[SocketService] Error joining track: $e');
    }
  }

  void emitRideCancelled({
    required String bookingId,
    String? reason,
    String cancelledBy = 'customer',
  }) {
    if (bookingId.isEmpty) return;
    if (_socket == null || !_isConnected) {
      initSocket();
    }
    try {
      final payload = {
        'bookingId': bookingId,
        'rideId': bookingId,
        'status': 'cancelled',
        'cancelledBy': cancelledBy,
        'reason': reason ?? 'Customer cancelled the ride request',
        'cancelReason': reason ?? 'Customer cancelled the ride request',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      _socket?.emit('ride_cancelled', payload);
      _socket?.emit('booking_cancelled', payload);
      _socket?.emit('state_update', payload);
      debugPrint('[SocketService] Emitted ride_cancelled for bookingId: $bookingId');
    } catch (e) {
      debugPrint('[SocketService] Error emitting ride_cancelled: $e');
    }
  }

  void emitAcceptBooking(Map<String, dynamic> data) {
    if (data.isEmpty) return;
    if (_socket == null || !_isConnected) {
      initSocket();
    }
    try {
      _socket?.emit('accept_booking', data);
      debugPrint('[SocketService] Emitted accept_booking: ${data['bookingId']}');
    } catch (e) {
      debugPrint('[SocketService] Error emitting accept_booking: $e');
    }
  }

  void emitDeclineBooking(Map<String, dynamic> data) {
    if (data.isEmpty) return;
    if (_socket == null || !_isConnected) {
      initSocket();
    }
    try {
      _socket?.emit('decline_booking', data);
      debugPrint('[SocketService] Emitted decline_booking: ${data['bookingId']}');
    } catch (e) {
      debugPrint('[SocketService] Error emitting decline_booking: $e');
    }
  }

  void disconnect() {
    try {
      _socket?.disconnect();
      _socket?.dispose();
      _socket = null;
      _isConnected = false;
    } catch (_) {}
  }
}
