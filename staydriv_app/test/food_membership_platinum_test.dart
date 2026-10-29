import 'package:flutter_test/flutter_test.dart';
import 'package:staydriv_app/features/food_ordering/models/food_models.dart';

void main() {
  group('StayDriv Platinum Food Membership Tests', () {
    test('Platinum Plan model initialization and pricing', () {
      final plan = FoodMembershipPlanModel(
        planId: 'plan_platinum_3m',
        planType: 'platinum',
        name: 'StayDriv Platinum Food Membership',
        tagline: '₹1 for 3 months • Free Delivery & Up to 30% Extra Off',
        description: 'Unlimited free delivery above ₹99 within 7 km & up to 30% extra off on food orders.',
        price: 1.0,
        originalPrice: 499.0,
        validityDays: 90,
        validityMonths: 3,
        minOrderAmount: 99.0,
        deliveryRadiusKm: 7.0,
        maxDiscountPercent: 30.0,
      );

      expect(plan.price, 1.0);
      expect(plan.validityDays, 90);
      expect(plan.validityMonths, 3);
      expect(plan.planType, 'platinum');
      expect((plan.price * 100).toInt(), 100); // 100 paise = ₹1 for Razorpay
    });

    test('CustomerFoodMembershipModel active status and expiration calculation', () {
      final now = DateTime.now();
      final expiry = now.add(const Duration(days: 90));

      final membership = CustomerFoodMembershipModel(
        membershipId: 'SD-PLATINUM-TEST01',
        planId: 'plan_platinum_3m',
        planType: 'platinum',
        planName: 'StayDriv Platinum Food Membership',
        status: 'active',
        startDate: now,
        endDate: expiry,
        pricePaid: 1.0,
        daysRemaining: 90,
      );

      expect(membership.isActive, isTrue);
      expect(membership.pricePaid, 1.0);
      expect(membership.isExpired, isFalse);
      expect(membership.planType, 'platinum');
      expect(membership.membershipId.startsWith('SD-PLATINUM-'), isTrue);
    });

    test('CustomerFoodMembershipModel expired status', () {
      final pastDate = DateTime.now().subtract(const Duration(days: 1));

      final expiredMembership = CustomerFoodMembershipModel(
        membershipId: 'SD-PLATINUM-EXP01',
        planId: 'plan_platinum_3m',
        planType: 'platinum',
        planName: 'StayDriv Platinum Food Membership',
        status: 'expired',
        startDate: DateTime.now().subtract(const Duration(days: 91)),
        endDate: pastDate,
        pricePaid: 1.0,
        daysRemaining: 0,
      );

      expect(expiredMembership.isActive, isFalse);
      expect(expiredMembership.isExpired, isTrue);
    });
  });
}
