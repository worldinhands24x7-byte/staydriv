double _safeDouble(dynamic val, [double def = 0.0]) {
  if (val == null) return def;
  if (val is num) return val.toDouble();
  return double.tryParse(val.toString()) ?? def;
}

int _safeInt(dynamic val, [int def = 0]) {
  if (val == null) return def;
  if (val is num) return val.toInt();
  return int.tryParse(val.toString()) ?? def;
}

String _safeString(dynamic val, [String def = '']) {
  if (val == null) return def;
  return val.toString();
}

class FoodCategory {
  final String name;
  final String icon;

  const FoodCategory({required this.name, required this.icon});
}

class Restaurant {
  final String restaurantId;
  final String name;
  final String ownerName;
  final String phone;
  final String email;
  final String address;
  final double lat;
  final double lng;
  final List<String> cuisines;
  final List<String> categories;
  final double rating;
  final int ratingCount;
  final String deliveryTime;
  final double deliveryFee;
  final double minimumOrder;
  final bool isVegOnly;
  final bool isOpen;
  final String openingHours;
  final String imageUrl;
  final String fssaiNumber;
  final String status;
  final double commissionRate;
  final double? distanceKm;
  final bool isDeliverable;
  final bool isMembershipEnrolled;

  Restaurant({
    required this.restaurantId,
    required this.name,
    this.ownerName = '',
    required this.phone,
    this.email = '',
    required this.address,
    this.lat = 0.0,
    this.lng = 0.0,
    this.cuisines = const [],
    this.categories = const [],
    this.rating = 4.5,
    this.ratingCount = 100,
    this.deliveryTime = '25-35 mins',
    this.deliveryFee = 30.0,
    this.minimumOrder = 100.0,
    this.isVegOnly = false,
    this.isOpen = true,
    this.openingHours = '10:00 AM - 11:30 PM',
    this.imageUrl = '',
    this.fssaiNumber = '',
    this.status = 'approved',
    this.commissionRate = 15.0,
    this.distanceKm,
    this.isDeliverable = true,
    this.isMembershipEnrolled = true,
  });

  factory Restaurant.fromJson(Map<String, dynamic> json) {
    return Restaurant(
      restaurantId: _safeString(json['restaurantId']),
      name: _safeString(json['name'], 'StayDriv Partner'),
      ownerName: _safeString(json['ownerName']),
      phone: _safeString(json['phone']),
      email: _safeString(json['email']),
      address: _safeString(json['address']),
      lat: () {
        final l = _safeDouble(json['lat'], 0.0);
        final g = _safeDouble(json['lng'], 0.0);
        if (l > 50 && g < 40) return g;
        return l;
      }(),
      lng: () {
        final l = _safeDouble(json['lat'], 0.0);
        final g = _safeDouble(json['lng'], 0.0);
        if (l > 50 && g < 40) return l;
        return g;
      }(),
      cuisines: (json['cuisines'] as List<dynamic>?)?.map((c) => c.toString()).toList() ?? [],
      categories: (json['categories'] as List<dynamic>?)?.map((c) => c.toString()).toList() ?? [],
      rating: _safeDouble(json['rating'], 4.5),
      ratingCount: _safeInt(json['ratingCount'], 100),
      deliveryTime: _safeString(json['deliveryTime'], '25-35 mins'),
      deliveryFee: _safeDouble(json['deliveryFee'], 30.0),
      minimumOrder: _safeDouble(json['minimumOrder'], 100.0),
      isVegOnly: json['isVegOnly'] == true,
      isOpen: json['isOpen'] != false,
      openingHours: _safeString(json['openingHours'], '10:00 AM - 11:30 PM'),
      imageUrl: _safeString(json['imageUrl']),
      fssaiNumber: _safeString(json['fssaiNumber']),
      status: _safeString(json['status'], 'approved'),
      commissionRate: _safeDouble(json['commissionRate'], 15.0),
      distanceKm: json['distanceKm'] != null ? _safeDouble(json['distanceKm']) : null,
      isDeliverable: json['isDeliverable'] != null ? json['isDeliverable'] == true : true,
      isMembershipEnrolled: json['isMembershipEnrolled'] != false,
    );
  }
}

class MenuItem {
  final String itemId;
  final String restaurantId;
  String name;
  String category;
  String description;
  double price;
  double discountPrice;
  bool isVeg;
  bool isAvailable;
  String imageUrl;
  final double rating;
  String prepTime;
  bool isDeleted;

  MenuItem({
    required this.itemId,
    required this.restaurantId,
    required this.name,
    required this.category,
    this.description = '',
    required this.price,
    this.discountPrice = 0.0,
    this.isVeg = false,
    this.isAvailable = true,
    this.imageUrl = '',
    this.rating = 4.5,
    this.prepTime = '20 mins',
    this.isDeleted = false,
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      itemId: _safeString(json['itemId']),
      restaurantId: _safeString(json['restaurantId']),
      name: _safeString(json['name']),
      category: _safeString(json['category'], 'General'),
      description: _safeString(json['description']),
      price: _safeDouble(json['price'], 0.0),
      discountPrice: _safeDouble(json['discountPrice'], 0.0),
      isVeg: json['isVeg'] == true,
      isAvailable: json['isAvailable'] != false,
      imageUrl: _safeString(json['imageUrl']),
      rating: _safeDouble(json['rating'], 4.5),
      prepTime: _safeString(json['prepTime'], '20 mins'),
      isDeleted: json['isDeleted'] == true,
    );
  }
}

class CartItem {
  final MenuItem item;
  int quantity;
  String customization;

  CartItem({
    required this.item,
    this.quantity = 1,
    this.customization = '',
  });

  double get lineTotal => item.price * quantity;

  Map<String, dynamic> toJson() => {
    'itemId': item.itemId,
    'name': item.name,
    'price': item.price,
    'quantity': quantity,
    'isVeg': item.isVeg,
    'customization': customization,
  };
}

class FoodCart {
  final Restaurant? restaurant;
  final List<CartItem> items;
  final double membershipDiscount;

  FoodCart({
    this.restaurant,
    this.items = const [],
    this.membershipDiscount = 0.0,
  });

  bool get isEmpty => items.isEmpty;
  int get totalItemCount => items.fold(0, (sum, i) => sum + i.quantity);
  double get subtotal => items.fold(0.0, (sum, i) => sum + i.lineTotal);
  double get deliveryFee => restaurant?.deliveryFee ?? 30.0;
  double get platformFee => 15.0;
  double get taxes => (subtotal * 0.05).roundToDouble();
  double get grandTotal => (subtotal + deliveryFee + platformFee + taxes - membershipDiscount).clamp(0.0, double.infinity);

  FoodCart copyWith({
    Restaurant? restaurant,
    List<CartItem>? items,
    double? membershipDiscount,
  }) {
    return FoodCart(
      restaurant: restaurant ?? this.restaurant,
      items: items ?? this.items,
      membershipDiscount: membershipDiscount ?? this.membershipDiscount,
    );
  }
}

class FoodOrder {
  final String orderId;
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String deliveryAddress;
  final String deliveryInstructions;
  final String restaurantId;
  final String restaurantName;
  final String restaurantPhone;
  final String restaurantAddress;
  final List<CartItem> items;
  final double subtotal;
  final double deliveryFee;
  final double platformFee;
  final double taxes;
  final double totalAmount;
  final String paymentMethod;
  final String paymentStatus;
  final String orderStatus;
  final String deliveryOtp;
  final String customerOtp;
  final bool customerOtpVerified;
  final String restaurantOtp;
  final bool restaurantOtpVerified;
  final String rejectReason;
  final String cancelReason;
  final String deliveryPartnerId;
  final String deliveryPartnerName;
  final String deliveryPartnerPhone;
  final String deliveryPartnerVehicle;
  final String deliveryPartnerPlate;
  final String prepTime;
  final double? deliveryLat;
  final double? deliveryLng;
  final double? restaurantLat;
  final double? restaurantLng;
  final String returnOtp;
  final bool returnOtpVerified;
  final String returnReason;
  final String returnNotes;
  final String returnEvidenceUrl;
  final DateTime? returnDeadline;
  final String walletDebitStatus;
  final double proposedWalletDebitAmount;
  final double actualWalletDebitAmount;
  final List<Map<String, dynamic>> statusHistory;
  final List<Map<String, dynamic>> callHistory;
  final DateTime? createdAt;

  final double packagingFee;
  final double deliveryDiscount;
  final double originalDeliveryFee;
  final double customerDeliveryFee;
  final double staydrivFundedDeliveryAmount;
  final bool isPlatinumDelivery;
  final String platinumBenefitMessage;
  final double pilotEarnings;
  final double? distanceKm;
  final String fundingSource;
  final String couponCode;
  final double couponDiscount;
  final double membershipDiscount;
  final double cashRoundOff;
  final double finalPayable;
  final double totalSavings;

  bool get isReturnActive =>
      orderStatus == 'delivery_failed_reported' ||
      orderStatus == 'return_to_restaurant' ||
      orderStatus == 'return_arrived_at_restaurant' ||
      orderStatus == 'return_otp_pending';

  bool get isReturned => orderStatus == 'returned_to_restaurant';
  DateTime get placedAt => createdAt ?? DateTime.now();

  FoodOrder({
    required this.orderId,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.deliveryAddress,
    this.deliveryInstructions = '',
    required this.restaurantId,
    required this.restaurantName,
    this.restaurantPhone = '',
    this.restaurantAddress = '',
    required this.items,
    required this.subtotal,
    this.packagingFee = 0.0,
    required this.deliveryFee,
    this.originalDeliveryFee = 0.0,
    this.customerDeliveryFee = 0.0,
    this.deliveryDiscount = 0.0,
    this.staydrivFundedDeliveryAmount = 0.0,
    this.isPlatinumDelivery = false,
    this.platinumBenefitMessage = '',
    this.pilotEarnings = 0.0,
    this.distanceKm,
    this.fundingSource = 'customer',
    required this.platformFee,
    required this.taxes,
    this.couponCode = '',
    this.couponDiscount = 0.0,
    this.membershipDiscount = 0.0,
    this.cashRoundOff = 0.0,
    required this.totalAmount,
    this.finalPayable = 0.0,
    this.totalSavings = 0.0,
    this.paymentMethod = 'online',
    this.paymentStatus = 'paid',
    this.orderStatus = 'placed',
    this.deliveryOtp = '',
    this.customerOtp = '',
    this.customerOtpVerified = false,
    this.restaurantOtp = '',
    this.restaurantOtpVerified = false,
    this.rejectReason = '',
    this.cancelReason = '',
    this.deliveryPartnerId = '',
    this.deliveryPartnerName = '',
    this.deliveryPartnerPhone = '',
    this.deliveryPartnerVehicle = '',
    this.deliveryPartnerPlate = '',
    this.prepTime = '25 mins',
    this.deliveryLat,
    this.deliveryLng,
    this.restaurantLat,
    this.restaurantLng,
    this.returnOtp = '',
    this.returnOtpVerified = false,
    this.returnReason = '',
    this.returnNotes = '',
    this.returnEvidenceUrl = '',
    this.returnDeadline,
    this.walletDebitStatus = 'none',
    this.proposedWalletDebitAmount = 0.0,
    this.actualWalletDebitAmount = 0.0,
    this.createdAt,
    this.statusHistory = const [],
    this.callHistory = const [],
  });

  FoodOrder copyWith({
    String? orderStatus,
    String? deliveryPartnerId,
    String? deliveryPartnerName,
    String? deliveryPartnerPhone,
    String? deliveryPartnerVehicle,
    String? deliveryPartnerPlate,
    DateTime? createdAt,
    List<Map<String, dynamic>>? statusHistory,
  }) {
    return FoodOrder(
      orderId: orderId,
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
      deliveryAddress: deliveryAddress,
      deliveryInstructions: deliveryInstructions,
      restaurantId: restaurantId,
      restaurantName: restaurantName,
      restaurantPhone: restaurantPhone,
      restaurantAddress: restaurantAddress,
      items: items,
      subtotal: subtotal,
      packagingFee: packagingFee,
      deliveryFee: deliveryFee,
      originalDeliveryFee: originalDeliveryFee,
      customerDeliveryFee: customerDeliveryFee,
      deliveryDiscount: deliveryDiscount,
      staydrivFundedDeliveryAmount: staydrivFundedDeliveryAmount,
      isPlatinumDelivery: isPlatinumDelivery,
      platinumBenefitMessage: platinumBenefitMessage,
      pilotEarnings: pilotEarnings,
      distanceKm: distanceKm,
      fundingSource: fundingSource,
      platformFee: platformFee,
      taxes: taxes,
      couponCode: couponCode,
      couponDiscount: couponDiscount,
      membershipDiscount: membershipDiscount,
      cashRoundOff: cashRoundOff,
      totalAmount: totalAmount,
      finalPayable: finalPayable,
      totalSavings: totalSavings,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
      orderStatus: orderStatus ?? this.orderStatus,
      deliveryOtp: deliveryOtp,
      customerOtp: customerOtp,
      customerOtpVerified: customerOtpVerified,
      restaurantOtp: restaurantOtp,
      restaurantOtpVerified: restaurantOtpVerified,
      rejectReason: rejectReason,
      cancelReason: cancelReason,
      deliveryPartnerId: deliveryPartnerId ?? this.deliveryPartnerId,
      deliveryPartnerName: deliveryPartnerName ?? this.deliveryPartnerName,
      deliveryPartnerPhone: deliveryPartnerPhone ?? this.deliveryPartnerPhone,
      deliveryPartnerVehicle: deliveryPartnerVehicle ?? this.deliveryPartnerVehicle,
      deliveryPartnerPlate: deliveryPartnerPlate ?? this.deliveryPartnerPlate,
      prepTime: prepTime,
      deliveryLat: deliveryLat,
      deliveryLng: deliveryLng,
      restaurantLat: restaurantLat,
      restaurantLng: restaurantLng,
      returnOtp: returnOtp,
      returnOtpVerified: returnOtpVerified,
      returnReason: returnReason,
      returnNotes: returnNotes,
      returnEvidenceUrl: returnEvidenceUrl,
      returnDeadline: returnDeadline,
      walletDebitStatus: walletDebitStatus,
      proposedWalletDebitAmount: proposedWalletDebitAmount,
      actualWalletDebitAmount: actualWalletDebitAmount,
      createdAt: createdAt ?? this.createdAt,
      statusHistory: statusHistory ?? this.statusHistory,
      callHistory: callHistory,
    );
  }

  factory FoodOrder.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    final items = rawItems.map((raw) {
      if (raw is! Map) return null;
      final rawMap = Map<String, dynamic>.from(raw);
      return CartItem(
        item: MenuItem(
          itemId: _safeString(rawMap['itemId']),
          restaurantId: _safeString(json['restaurantId']),
          name: _safeString(rawMap['name']),
          category: _safeString(rawMap['category'], 'General'),
          price: _safeDouble(rawMap['price']),
          isVeg: rawMap['isVeg'] == true,
        ),
        quantity: _safeInt(rawMap['quantity'], 1),
        customization: _safeString(rawMap['customization']),
      );
    }).whereType<CartItem>().toList();

    final totAmount = _safeDouble(json['totalAmount']);
    final finPayable = _safeDouble(json['finalPayable'], totAmount);

    return FoodOrder(
      orderId: _safeString(json['orderId']),
      customerId: _safeString(json['customerId']),
      customerName: _safeString(json['customerName'], 'Customer'),
      customerPhone: _safeString(json['customerPhone']),
      deliveryAddress: _safeString(json['deliveryAddress']),
      deliveryInstructions: _safeString(json['deliveryInstructions']),
      restaurantId: _safeString(json['restaurantId']),
      restaurantName: _safeString(json['restaurantName'], 'Restaurant'),
      restaurantPhone: _safeString(json['restaurantPhone']),
      restaurantAddress: _safeString(json['restaurantAddress']),
      items: items,
      subtotal: _safeDouble(json['subtotal']),
      packagingFee: _safeDouble(json['packagingFee']),
      deliveryFee: _safeDouble(json['deliveryFee'], 30.0),
      originalDeliveryFee: _safeDouble(json['originalDeliveryFee'], _safeDouble(json['deliveryFee'], 30.0)),
      customerDeliveryFee: _safeDouble(json['customerDeliveryFee'], _safeDouble(json['deliveryFee'], 30.0)),
      deliveryDiscount: _safeDouble(json['deliveryDiscount']),
      staydrivFundedDeliveryAmount: _safeDouble(json['staydrivFundedDeliveryAmount']),
      isPlatinumDelivery: json['isPlatinumDelivery'] == true,
      platinumBenefitMessage: _safeString(json['platinumBenefitMessage']),
      pilotEarnings: _safeDouble(json['pilotEarnings'], _safeDouble(json['originalDeliveryFee'], _safeDouble(json['deliveryFee'], 30.0))),
      distanceKm: json['deliveryDistanceKm'] != null ? _safeDouble(json['deliveryDistanceKm']) : (json['distanceKm'] != null ? _safeDouble(json['distanceKm']) : null),
      fundingSource: _safeString(json['fundingSource'], 'customer'),
      platformFee: _safeDouble(json['platformFee'], 15.0),
      taxes: _safeDouble(json['taxes']),
      couponCode: _safeString(json['couponCode']),
      couponDiscount: _safeDouble(json['couponDiscount']),
      membershipDiscount: _safeDouble(json['membershipDiscount']),
      cashRoundOff: _safeDouble(json['cashRoundOff']),
      totalAmount: totAmount,
      finalPayable: finPayable,
      totalSavings: _safeDouble(json['totalSavings']),
      paymentMethod: _safeString(json['paymentMethod'], 'online'),
      paymentStatus: _safeString(json['paymentStatus'], 'paid'),
      orderStatus: _safeString(json['orderStatus'], 'placed'),
      deliveryOtp: _safeString(json['deliveryOtp'], _safeString(json['customerOtp'])),
      customerOtp: _safeString(json['customerOtp'], _safeString(json['deliveryOtp'])),
      customerOtpVerified: json['customerOtpVerified'] == true,
      restaurantOtp: _safeString(json['restaurantOtp']),
      restaurantOtpVerified: json['restaurantOtpVerified'] == true,
      rejectReason: _safeString(json['rejectReason']),
      cancelReason: _safeString(json['cancelReason']),
      deliveryPartnerId: _safeString(json['deliveryPartnerId']),
      deliveryPartnerName: _safeString(json['deliveryPartnerName']),
      deliveryPartnerPhone: _safeString(json['deliveryPartnerPhone']),
      deliveryPartnerVehicle: _safeString(json['deliveryPartnerVehicle']),
      deliveryPartnerPlate: _safeString(json['deliveryPartnerPlate']),
      prepTime: _safeString(json['prepTime'], '25 mins'),
      deliveryLat: () {
        double? dLat = json['deliveryLatLng'] != null && json['deliveryLatLng']['lat'] != null
            ? _safeDouble(json['deliveryLatLng']['lat'])
            : (json['dropLatLng'] != null && json['dropLatLng']['lat'] != null
                ? _safeDouble(json['dropLatLng']['lat'])
                : (json['deliveryLat'] != null ? _safeDouble(json['deliveryLat']) : (json['dropLat'] != null ? _safeDouble(json['dropLat']) : null)));
        double? dLng = json['deliveryLatLng'] != null && json['deliveryLatLng']['lng'] != null
            ? _safeDouble(json['deliveryLatLng']['lng'])
            : (json['dropLatLng'] != null && json['dropLatLng']['lng'] != null
                ? _safeDouble(json['dropLatLng']['lng'])
                : (json['deliveryLng'] != null ? _safeDouble(json['deliveryLng']) : (json['dropLng'] != null ? _safeDouble(json['dropLng']) : null)));
        if (dLat != null && dLng != null && dLat > 50 && dLng < 40) return dLng;
        return dLat;
      }(),
      deliveryLng: () {
        double? dLat = json['deliveryLatLng'] != null && json['deliveryLatLng']['lat'] != null
            ? _safeDouble(json['deliveryLatLng']['lat'])
            : (json['dropLatLng'] != null && json['dropLatLng']['lat'] != null
                ? _safeDouble(json['dropLatLng']['lat'])
                : (json['deliveryLat'] != null ? _safeDouble(json['deliveryLat']) : (json['dropLat'] != null ? _safeDouble(json['dropLat']) : null)));
        double? dLng = json['deliveryLatLng'] != null && json['deliveryLatLng']['lng'] != null
            ? _safeDouble(json['deliveryLatLng']['lng'])
            : (json['dropLatLng'] != null && json['dropLatLng']['lng'] != null
                ? _safeDouble(json['dropLatLng']['lng'])
                : (json['deliveryLng'] != null ? _safeDouble(json['deliveryLng']) : (json['dropLng'] != null ? _safeDouble(json['dropLng']) : null)));
        if (dLat != null && dLng != null && dLat > 50 && dLng < 40) return dLat;
        return dLng;
      }(),
      restaurantLat: () {
        double? rLat = json['restaurantLatLng'] != null && json['restaurantLatLng']['lat'] != null
            ? _safeDouble(json['restaurantLatLng']['lat'])
            : (json['pickupLatLng'] != null && json['pickupLatLng']['lat'] != null
                ? _safeDouble(json['pickupLatLng']['lat'])
                : (json['restaurantLat'] != null ? _safeDouble(json['restaurantLat']) : (json['pickupLat'] != null ? _safeDouble(json['pickupLat']) : null)));
        double? rLng = json['restaurantLatLng'] != null && json['restaurantLatLng']['lng'] != null
            ? _safeDouble(json['restaurantLatLng']['lng'])
            : (json['pickupLatLng'] != null && json['pickupLatLng']['lng'] != null
                ? _safeDouble(json['pickupLatLng']['lng'])
                : (json['restaurantLng'] != null ? _safeDouble(json['restaurantLng']) : (json['pickupLng'] != null ? _safeDouble(json['pickupLng']) : null)));
        if (rLat != null && rLng != null && rLat > 50 && rLng < 40) return rLng;
        return rLat;
      }(),
      restaurantLng: () {
        double? rLat = json['restaurantLatLng'] != null && json['restaurantLatLng']['lat'] != null
            ? _safeDouble(json['restaurantLatLng']['lat'])
            : (json['pickupLatLng'] != null && json['pickupLatLng']['lat'] != null
                ? _safeDouble(json['pickupLatLng']['lat'])
                : (json['restaurantLat'] != null ? _safeDouble(json['restaurantLat']) : (json['pickupLat'] != null ? _safeDouble(json['pickupLat']) : null)));
        double? rLng = json['restaurantLatLng'] != null && json['restaurantLatLng']['lng'] != null
            ? _safeDouble(json['restaurantLatLng']['lng'])
            : (json['pickupLatLng'] != null && json['pickupLatLng']['lng'] != null
                ? _safeDouble(json['pickupLatLng']['lng'])
                : (json['restaurantLng'] != null ? _safeDouble(json['restaurantLng']) : (json['pickupLng'] != null ? _safeDouble(json['pickupLng']) : null)));
        if (rLat != null && rLng != null && rLat > 50 && rLng < 40) return rLat;
        return rLng;
      }(),
      returnOtp: _safeString(json['returnOtp']),
      returnOtpVerified: json['returnOtpVerified'] == true,
      returnReason: _safeString(json['returnReason']),
      returnNotes: _safeString(json['returnNotes']),
      returnEvidenceUrl: _safeString(json['returnEvidenceUrl']),
      returnDeadline: json['returnDeadline'] != null ? DateTime.tryParse(json['returnDeadline'].toString()) : null,
      walletDebitStatus: _safeString(json['walletDebitStatus'], 'none'),
      proposedWalletDebitAmount: _safeDouble(json['proposedWalletDebitAmount']),
      actualWalletDebitAmount: _safeDouble(json['actualWalletDebitAmount']),
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now() : DateTime.now(),
      statusHistory: (json['statusHistory'] as List<dynamic>?)
              ?.whereType<Map>()
              .map((h) => Map<String, dynamic>.from(h))
              .toList() ??
          [],
      callHistory: (json['callHistory'] as List<dynamic>?)
              ?.whereType<Map>()
              .map((h) => Map<String, dynamic>.from(h))
              .toList() ??
          [],
    );
  }
}

class FoodCouponModel {
  final String code;
  final String title;
  final String description;
  final String discountType; // 'percentage', 'flat', 'free_delivery'
  final double discountValue;
  final double minOrderAmount;
  final double maxDiscountAmount;
  final bool freeDelivery;
  final bool isEligible;
  final String ineligibleReason;

  FoodCouponModel({
    required this.code,
    required this.title,
    this.description = '',
    required this.discountType,
    required this.discountValue,
    this.minOrderAmount = 0.0,
    this.maxDiscountAmount = 0.0,
    this.freeDelivery = false,
    this.isEligible = true,
    this.ineligibleReason = '',
  });

  factory FoodCouponModel.fromJson(Map<String, dynamic> json) {
    return FoodCouponModel(
      code: json['code']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      discountType: json['discountType']?.toString() ?? 'percentage',
      discountValue: (json['discountValue'] as num?)?.toDouble() ?? 0.0,
      minOrderAmount: (json['minOrderAmount'] as num?)?.toDouble() ?? 0.0,
      maxDiscountAmount: (json['maxDiscountAmount'] as num?)?.toDouble() ?? 0.0,
      freeDelivery: json['freeDelivery'] == true || json['discountType'] == 'free_delivery',
      isEligible: json['isEligible'] != false,
      ineligibleReason: json['ineligibleReason']?.toString() ?? '',
    );
  }
}

class FoodMembershipBenefitModel {
  final String benefitId;
  final String title;
  final String description;
  final String icon;
  final String type;
  final double value;
  final double minimumOrderValue;
  final double maxDiscountLimit;
  final String fundedBy;
  final bool isEnabled;

  FoodMembershipBenefitModel({
    required this.benefitId,
    required this.title,
    this.description = '',
    this.icon = 'percent',
    required this.type,
    required this.value,
    this.minimumOrderValue = 0.0,
    this.maxDiscountLimit = 0.0,
    this.fundedBy = 'staydriv',
    this.isEnabled = true,
  });

  factory FoodMembershipBenefitModel.fromJson(Map<String, dynamic> json) {
    return FoodMembershipBenefitModel(
      benefitId: _safeString(json['benefitId']),
      title: _safeString(json['title']),
      description: _safeString(json['description']),
      icon: _safeString(json['icon'], 'percent'),
      type: _safeString(json['type'], 'discount_percentage'),
      value: _safeDouble(json['value']),
      minimumOrderValue: _safeDouble(json['minimumOrderValue']),
      maxDiscountLimit: _safeDouble(json['maxDiscountLimit']),
      fundedBy: _safeString(json['fundedBy'], 'staydriv'),
      isEnabled: json['isEnabled'] != false,
    );
  }
}

class FoodMembershipPlanModel {
  final String planId;
  final String planType; // 'platinum', 'monthly', or 'quarterly'
  final String name;
  final String tagline;
  final String description;
  final double price;
  final double originalPrice;
  final int validityDays;
  final int validityMonths;
  final double minOrderAmount;
  final double deliveryRadiusKm;
  final double maxDiscountPercent;
  final int version;
  final List<FoodMembershipBenefitModel> benefits;
  final List<String> termsAndConditions;

  FoodMembershipPlanModel({
    required this.planId,
    required this.planType,
    required this.name,
    this.tagline = '',
    this.description = '',
    required this.price,
    this.originalPrice = 0.0,
    required this.validityDays,
    required this.validityMonths,
    this.minOrderAmount = 99.0,
    this.deliveryRadiusKm = 7.0,
    this.maxDiscountPercent = 30.0,
    this.version = 1,
    this.benefits = const [],
    this.termsAndConditions = const [],
  });

  factory FoodMembershipPlanModel.fromJson(Map<String, dynamic> json) {
    final rawBenefits = json['benefits'] as List<dynamic>? ?? [];
    final benefits = rawBenefits
        .whereType<Map>()
        .map((b) => FoodMembershipBenefitModel.fromJson(Map<String, dynamic>.from(b)))
        .toList();

    final rawTerms = json['termsAndConditions'] as List<dynamic>? ?? [];
    final terms = rawTerms.map((t) => t.toString()).toList();

    return FoodMembershipPlanModel(
      planId: _safeString(json['planId']),
      planType: _safeString(json['planType'], 'platinum'),
      name: _safeString(json['name']),
      tagline: _safeString(json['tagline']),
      description: _safeString(json['description']),
      price: _safeDouble(json['price']),
      originalPrice: _safeDouble(json['originalPrice']),
      validityDays: _safeInt(json['validityDays'], 90),
      validityMonths: _safeInt(json['validityMonths'], 3),
      minOrderAmount: _safeDouble(json['minOrderAmount'], 99.0),
      deliveryRadiusKm: _safeDouble(json['deliveryRadiusKm'], 7.0),
      maxDiscountPercent: _safeDouble(json['maxDiscountPercent'], 30.0),
      version: _safeInt(json['version'], 1),
      benefits: benefits,
      termsAndConditions: terms,
    );
  }
}

class CustomerFoodMembershipModel {
  final String membershipId;
  final String planId;
  final String planType;
  final String planName;
  final int planVersion;
  final String status;
  final DateTime? startDate;
  final DateTime? endDate;
  final int daysRemaining;
  final bool isExpiringSoon;
  final double pricePaid;
  final double totalDiscountAvailed;
  final int ordersCount;
  final List<FoodMembershipBenefitModel> benefits;
  final List<String> termsAndConditions;

  CustomerFoodMembershipModel({
    required this.membershipId,
    required this.planId,
    required this.planType,
    required this.planName,
    this.planVersion = 1,
    required this.status,
    this.startDate,
    this.endDate,
    this.daysRemaining = 0,
    this.isExpiringSoon = false,
    this.pricePaid = 0.0,
    this.totalDiscountAvailed = 0.0,
    this.ordersCount = 0,
    this.benefits = const [],
    this.termsAndConditions = const [],
  });

  bool get isActive => status == 'active' && (endDate == null || endDate!.isAfter(DateTime.now()));
  bool get isExpired => !isActive;

  factory CustomerFoodMembershipModel.fromJson(Map<String, dynamic> json) {
    final rawBenefits = json['benefits'] as List<dynamic>? ?? [];
    final benefits = rawBenefits
        .whereType<Map>()
        .map((b) => FoodMembershipBenefitModel.fromJson(Map<String, dynamic>.from(b)))
        .toList();

    final rawTerms = json['termsAndConditions'] as List<dynamic>? ?? [];
    final terms = rawTerms.map((t) => t.toString()).toList();

    return CustomerFoodMembershipModel(
      membershipId: _safeString(json['membershipId']),
      planId: _safeString(json['planId']),
      planType: _safeString(json['planType'], 'monthly'),
      planName: _safeString(json['planName'], 'Food Saver Pass'),
      planVersion: _safeInt(json['planVersion'], 1),
      status: _safeString(json['status'], 'active'),
      startDate: json['startDate'] != null ? DateTime.tryParse(json['startDate'].toString()) : null,
      endDate: json['endDate'] != null ? DateTime.tryParse(json['endDate'].toString()) : null,
      daysRemaining: _safeInt(json['daysRemaining'], 0),
      isExpiringSoon: json['isExpiringSoon'] == true,
      pricePaid: _safeDouble(json['pricePaid']),
      totalDiscountAvailed: _safeDouble(json['totalDiscountAvailed']),
      ordersCount: _safeInt(json['ordersCount']),
      benefits: benefits,
      termsAndConditions: terms,
    );
  }
}

