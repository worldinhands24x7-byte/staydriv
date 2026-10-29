const Restaurant = require('../models/Restaurant');
const FoodItem = require('../models/FoodItem');
const FoodConfig = require('../models/FoodConfig');
const FoodCoupon = require('../models/FoodCoupon');
const CustomerFoodMembership = require('../models/CustomerFoodMembership');

// Haversine distance formula in km
function calculateDistanceKm(lat1, lon1, lat2, lon2) {
  if (lat1 === undefined || lon1 === undefined || lat2 === undefined || lon2 === undefined) return null;
  const nLat1 = parseFloat(lat1);
  const nLon1 = parseFloat(lon1);
  const nLat2 = parseFloat(lat2);
  const nLon2 = parseFloat(lon2);
  if (isNaN(nLat1) || isNaN(nLon1) || isNaN(nLat2) || isNaN(nLon2)) return null;

  const R = 6371; // km
  const dLat = (nLat2 - nLat1) * Math.PI / 180;
  const dLon = (nLon2 - nLon1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(nLat1 * Math.PI / 180) * Math.cos(nLat2 * Math.PI / 180) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

/**
 * Authoritative bill calculation engine for StayDriv Food Order Now.
 * Decimal safe, unified across customer checkout, order creation, payment, and admin reporting.
 */
async function calculateFoodBill({
  restaurantId,
  items,
  deliveryAddress,
  deliveryLatLng,
  couponCode,
  customerId,
  customerPhone,
  membershipId,
  paymentMethod = 'online'
}) {
  if (!restaurantId) {
    throw new Error('restaurantId is required');
  }
  if (!Array.isArray(items) || items.length === 0) {
    throw new Error('Cart cannot be empty');
  }

  // 1. Fetch Restaurant
  const restaurant = await Restaurant.findOne({ restaurantId }).lean();
  if (!restaurant) {
    throw new Error('Restaurant not found');
  }

  // 2. Fetch Config
  let config = await FoodConfig.findOne({ configId: 'staydriv_food_config' }).lean();
  if (!config) {
    config = {
      platformFee: 15,
      discountedPlatformFee: 9,
      deliveryBaseFee: 30,
      deliveryPerKmFee: 8,
      defaultPackagingFee: 10,
      taxRatePercent: 5.0,
      cashRoundingEnabled: true
    };
  }

  // 3. Verify Items and calculate subtotal
  const itemIds = items.map(i => i.itemId);
  const dbItems = await FoodItem.find({
    itemId: { $in: itemIds },
    restaurantId,
    isDeleted: { $ne: true }
  }).lean();

  const itemMap = new Map();
  dbItems.forEach(i => itemMap.set(i.itemId, i));

  let subtotal = 0;
  const verifiedItems = [];

  for (const item of items) {
    const dbItem = itemMap.get(item.itemId);
    if (!dbItem) {
      throw new Error(`Item ${item.name || item.itemId} is no longer available`);
    }
    if (!dbItem.isAvailable) {
      throw new Error(`${dbItem.name} is currently out of stock`);
    }
    const qty = Math.max(1, parseInt(item.quantity, 10) || 1);
    const price = typeof dbItem.price === 'number' ? dbItem.price : parseFloat(dbItem.price) || 0;
    const lineTotal = price * qty;
    subtotal += lineTotal;

    verifiedItems.push({
      itemId: dbItem.itemId,
      name: dbItem.name,
      price: price,
      quantity: qty,
      isVeg: Boolean(dbItem.isVeg),
      customization: item.customization || '',
      lineTotal
    });
  }

  subtotal = Math.round(subtotal * 100) / 100;

  // 4. Packaging Charges (restaurant specific or platform default)
  const packagingFee = typeof restaurant.packagingFee === 'number'
    ? restaurant.packagingFee
    : (config.defaultPackagingFee !== undefined ? config.defaultPackagingFee : 10);

  // 5. Delivery Partner Fee & Distance
  let finalDeliveryLat = 0;
  let finalDeliveryLng = 0;
  if (deliveryLatLng && !isNaN(parseFloat(deliveryLatLng.lat)) && !isNaN(parseFloat(deliveryLatLng.lng))) {
    finalDeliveryLat = parseFloat(deliveryLatLng.lat);
    finalDeliveryLng = parseFloat(deliveryLatLng.lng);
  } else if (typeof deliveryAddress === 'object' && deliveryAddress && !isNaN(parseFloat(deliveryAddress.lat))) {
    finalDeliveryLat = parseFloat(deliveryAddress.lat);
    finalDeliveryLng = parseFloat(deliveryAddress.lng);
  }

  const rLat = typeof restaurant.lat === 'number' && !isNaN(restaurant.lat) ? restaurant.lat : 17.5230;
  const rLng = typeof restaurant.lng === 'number' && !isNaN(restaurant.lng) ? restaurant.lng : 78.4222;

  let distanceKm = null;
  // Delivery Fee configuration directly interlinked with Admin Console Food Settings:
  const configBaseFee = typeof config.deliveryBaseFee === 'number' ? config.deliveryBaseFee : 30;
  const configBaseKm = typeof config.deliveryBaseKm === 'number' ? config.deliveryBaseKm : 1.0;
  const configPerKmFee = typeof config.deliveryPerKmFee === 'number' ? config.deliveryPerKmFee : 10;
  const configMinFee = typeof config.minDeliveryFee === 'number' ? config.minDeliveryFee : 25;
  const configMaxFee = typeof config.maxDeliveryFee === 'number' ? config.maxDeliveryFee : 150;

  let originalDeliveryFee = configBaseFee;

  if (finalDeliveryLat !== 0 && finalDeliveryLng !== 0) {
    const dist = calculateDistanceKm(finalDeliveryLat, finalDeliveryLng, rLat, rLng);
    if (dist !== null) {
      distanceKm = Math.round(dist * 10) / 10;
      if (distanceKm <= configBaseKm) {
        // Within base distance (e.g. 500m <= 1km) -> only base fee (₹30)
        originalDeliveryFee = configBaseFee;
      } else {
        // Beyond base distance -> base fee + extra km * perKmFee
        originalDeliveryFee = Math.round(configBaseFee + ((distanceKm - configBaseKm) * configPerKmFee));
      }
      if (configMinFee && originalDeliveryFee < configMinFee) {
        originalDeliveryFee = configMinFee;
      }
      if (configMaxFee && originalDeliveryFee > configMaxFee) {
        originalDeliveryFee = configMaxFee;
      }
    }
  }

  // Free delivery threshold if configured and subtotal qualifies
  if (config.freeDeliveryThreshold && config.freeDeliveryThreshold > 0 && subtotal >= config.freeDeliveryThreshold) {
    originalDeliveryFee = 0;
  }

  let deliveryFee = originalDeliveryFee;
  let deliveryDiscount = 0;
  let isPlatinumDelivery = false;
  let platinumBenefitMessage = '';
  let staydrivFundedDeliveryAmount = 0;
  let customerDeliveryFee = originalDeliveryFee;

  // 6. Platform Fee
  const originalPlatformFee = config.platformFee || 15;
  const platformFee = config.discountedPlatformFee !== undefined ? config.discountedPlatformFee : 9;
  const platformFeeDiscount = Math.max(0, originalPlatformFee - platformFee);

  // 7. Check Customer Food Membership (StayDriv Platinum Free Delivery Benefit)
  let hasMembership = false;
  let membershipPlanType = '';
  let resolvedMembershipId = '';
  let membershipDiscount = 0;
  let membershipFoodDiscount = 0;
  let membershipDeliveryDiscount = 0;

  const lookupCustomerId = (customerId || '').toString().trim();
  const lookupCustomerPhone = (customerPhone || '').toString().trim();
  const lookupMembershipId = (membershipId || '').toString().trim();

  if (lookupCustomerId || lookupCustomerPhone || lookupMembershipId) {
    try {
      const orConditions = [];
      if (lookupMembershipId) {
        orConditions.push({ membershipId: lookupMembershipId });
      }
      if (lookupCustomerId) {
        orConditions.push({ customerId: lookupCustomerId });
        orConditions.push({ customerPhone: lookupCustomerId });
        const cleanCust = lookupCustomerId.replace(/\D/g, '').slice(-10);
        if (cleanCust.length === 10) {
          orConditions.push({ customerPhone: cleanCust });
          orConditions.push({ customerPhone: `+91${cleanCust}` });
          orConditions.push({ customerId: `CUST_${cleanCust}` });
          orConditions.push({ customerId: `mock_uid_${cleanCust}` });
        }
      }
      if (lookupCustomerPhone) {
        orConditions.push({ customerPhone: lookupCustomerPhone });
        orConditions.push({ customerId: lookupCustomerPhone });
        const cleanPhone = lookupCustomerPhone.replace(/\D/g, '').slice(-10);
        if (cleanPhone.length === 10) {
          orConditions.push({ customerPhone: cleanPhone });
          orConditions.push({ customerPhone: `+91${cleanPhone}` });
          orConditions.push({ customerId: `CUST_${cleanPhone}` });
          orConditions.push({ customerId: `mock_uid_${cleanPhone}` });
        }
      }

      // Support active demo/project accounts with cross-referencing
      if (lookupCustomerId === 'CUST_STAYDRIV_01' || lookupCustomerPhone === '9876543210' || lookupCustomerPhone === '9247535068') {
        orConditions.push({ customerId: 'CUST_STAYDRIV_01' });
        orConditions.push({ customerPhone: '9876543210' });
      }

      const activeMembership = await CustomerFoodMembership.findOne({
        $or: orConditions,
        status: 'active',
        endDate: { $gt: new Date() }
      }).sort({ createdAt: -1 }).lean();

      if (activeMembership) {
        hasMembership = true;
        resolvedMembershipId = activeMembership.membershipId;
        membershipPlanType = activeMembership.planType || 'platinum';

        const benefits = (activeMembership.planSnapshot && activeMembership.planSnapshot.benefits) || [];
        const freeDeliveryBenefit = benefits.find(b => b.type === 'free_delivery' && b.isEnabled !== false);

        // Verification of applicability conditions (min order value, max distance)
        let isEligibleForFreeDelivery = true;
        let ineligibilityReason = '';

        const minOrderValue = (freeDeliveryBenefit && typeof freeDeliveryBenefit.minimumOrderValue === 'number' && freeDeliveryBenefit.minimumOrderValue > 0)
          ? freeDeliveryBenefit.minimumOrderValue
          : 99; // Standard Platinum condition: min ₹99 order

        const maxDeliveryDistance = (freeDeliveryBenefit && typeof freeDeliveryBenefit.maxDistanceKm === 'number' && freeDeliveryBenefit.maxDistanceKm > 0)
          ? freeDeliveryBenefit.maxDistanceKm
          : 7.0; // Standard Platinum condition: within 7 km

        if (subtotal < minOrderValue) {
          isEligibleForFreeDelivery = false;
          ineligibilityReason = `Add items worth ₹${(minOrderValue - subtotal).toFixed(0)} more for Free Delivery with Platinum (Min ₹${minOrderValue})`;
        } else if (distanceKm !== null && distanceKm > maxDeliveryDistance) {
          isEligibleForFreeDelivery = false;
          ineligibilityReason = `Free Delivery with Platinum applies within ${maxDeliveryDistance} km (Order is ${distanceKm.toFixed(1)} km)`;
        }

        if (isEligibleForFreeDelivery) {
          isPlatinumDelivery = true;
          platinumBenefitMessage = 'Platinum Membership Benefit Applied — Free Delivery! StayDriv covers your delivery charges.';
          deliveryDiscount = originalDeliveryFee;
          customerDeliveryFee = 0;
          staydrivFundedDeliveryAmount = originalDeliveryFee;
          membershipDeliveryDiscount = originalDeliveryFee;
        } else {
          isPlatinumDelivery = false;
          platinumBenefitMessage = ineligibilityReason;
          deliveryDiscount = 0;
          customerDeliveryFee = originalDeliveryFee;
          staydrivFundedDeliveryAmount = 0;
          membershipDeliveryDiscount = 0;
        }

        // Restaurant-level food discount if restaurant participates
        if (restaurant.isMembershipEnrolled !== false) {
          for (const b of benefits) {
            if (!b.isEnabled) continue;
            if (b.minimumOrderValue && subtotal < b.minimumOrderValue) continue;

            if (b.type === 'discount_percentage') {
              const pct = restaurant.membershipDiscountPercent > 0 ? restaurant.membershipDiscountPercent : b.value;
              let calc = (subtotal * pct) / 100;
              if (b.maxDiscountLimit && b.maxDiscountLimit > 0) calc = Math.min(calc, b.maxDiscountLimit);
              calc = Math.round(calc * 100) / 100;
              if (calc > membershipFoodDiscount) {
                membershipFoodDiscount = calc;
              }
            } else if (b.type === 'fixed_discount') {
              if (b.value > membershipFoodDiscount) {
                membershipFoodDiscount = Math.min(subtotal, b.value);
              }
            }
          }
        }

        membershipDiscount = Math.round((membershipFoodDiscount + membershipDeliveryDiscount) * 100) / 100;
      }
    } catch (e) {
      console.warn('[calculateFoodBill] Error verifying membership:', e.message);
    }
  }

  // 8. Coupon Code Application & Validation
  let appliedCoupon = null;
  let couponDiscount = 0;
  let couponError = null;

  if (couponCode && typeof couponCode === 'string' && couponCode.trim()) {
    const cleanCode = couponCode.trim().toUpperCase();
    const couponDoc = await FoodCoupon.findOne({
      code: cleanCode,
      isActive: true,
      validTill: { $gt: new Date() }
    }).lean();

    if (!couponDoc) {
      couponError = `Coupon '${cleanCode}' is invalid or expired`;
    } else if (couponDoc.minOrderAmount && subtotal < couponDoc.minOrderAmount) {
      couponError = `Add items worth ₹${(couponDoc.minOrderAmount - subtotal).toFixed(0)} more to apply '${cleanCode}' (Min ₹${couponDoc.minOrderAmount})`;
    } else if (couponDoc.restaurantId && couponDoc.restaurantId !== restaurantId) {
      couponError = `Coupon '${cleanCode}' is only valid at specific restaurants`;
    } else {
      appliedCoupon = {
        code: couponDoc.code,
        title: couponDoc.title,
        description: couponDoc.description,
        discountType: couponDoc.discountType
      };

      if (couponDoc.discountType === 'free_delivery' || couponDoc.freeDelivery) {
        deliveryDiscount = deliveryFee;
      } else if (couponDoc.discountType === 'percentage') {
        let calc = (subtotal * couponDoc.discountValue) / 100;
        if (couponDoc.maxDiscountAmount && couponDoc.maxDiscountAmount > 0) {
          calc = Math.min(calc, couponDoc.maxDiscountAmount);
        }
        couponDiscount = Math.round(calc * 100) / 100;
      } else if (couponDoc.discountType === 'flat') {
        couponDiscount = Math.min(subtotal, couponDoc.discountValue);
      }
    }
  }

  // 9. Taxes (GST on Subtotal + Packaging Charges)
  const taxRate = config.taxRatePercent !== undefined ? config.taxRatePercent : 5.0;
  const taxableAmount = subtotal + packagingFee;
  const taxes = Math.round(((taxableAmount * taxRate) / 100) * 100) / 100;

  // 10. Grand Total Calculation
  const effectiveDeliveryFee = Math.max(0, deliveryFee - deliveryDiscount);
  const totalDiscounts = Math.round((couponDiscount + membershipFoodDiscount) * 100) / 100;

  let grandTotal = (subtotal + packagingFee + effectiveDeliveryFee + platformFee + taxes) - totalDiscounts;
  grandTotal = Math.max(0, Math.round(grandTotal * 100) / 100);

  // 11. Cash Round Off (Applies only when payment method is COD and cash rounding is enabled)
  const isCod = (paymentMethod || '').toString().toLowerCase().includes('cod');
  let cashRoundOff = 0;
  let finalPayable = grandTotal;

  if (isCod && config.cashRoundingEnabled !== false) {
    const rounded = Math.round(grandTotal);
    cashRoundOff = Math.round((rounded - grandTotal) * 100) / 100;
    finalPayable = rounded;
  } else {
    finalPayable = Math.round(grandTotal * 100) / 100;
  }

  // 12. Total Savings
  const totalSavings = Math.round((deliveryDiscount + couponDiscount + membershipFoodDiscount + platformFeeDiscount) * 100) / 100;

  return {
    restaurant: {
      restaurantId: restaurant.restaurantId,
      name: restaurant.name,
      address: restaurant.address,
      packagingFee
    },
    verifiedItems,
    distanceKm,
    distanceText: distanceKm !== null ? (distanceKm < 1 ? `${Math.round(distanceKm * 1000)} m` : `${distanceKm.toFixed(1)} km`) : 'Nearby',
    deliveryEstimate: distanceKm ? `${Math.max(15, Math.round(15 + distanceKm * 2))}-${Math.round(25 + distanceKm * 2.5)} mins` : '20-30 mins',
    // Detailed itemized bill breakdown
    subtotal,
    packagingFee,
    originalDeliveryFee,
    baseDeliveryFee: originalDeliveryFee,
    base_delivery_fee: originalDeliveryFee,
    customerDeliveryFee: effectiveDeliveryFee,
    customer_delivery_fee: effectiveDeliveryFee,
    deliveryFee: effectiveDeliveryFee,
    deliveryDiscount,
    platinumDeliveryDiscount: isPlatinumDelivery ? deliveryDiscount : 0,
    platinum_delivery_discount: isPlatinumDelivery ? deliveryDiscount : 0,
    staydrivFundedDeliveryAmount,
    staydrivMembershipDeliverySubsidy: staydrivFundedDeliveryAmount,
    staydriv_membership_delivery_subsidy: staydrivFundedDeliveryAmount,
    isPlatinumDelivery,
    platinumBenefitMessage,
    pilotEarnings: originalDeliveryFee,
    pilotDeliveryEarnings: originalDeliveryFee,
    pilot_delivery_earnings: originalDeliveryFee,
    pilotDeliveryFee: originalDeliveryFee,
    fundingSource: isPlatinumDelivery ? 'staydriv' : 'customer',
    originalPlatformFee,
    platformFee,
    platformFeeDiscount,
    taxes,
    couponCode: appliedCoupon ? appliedCoupon.code : null,
    couponTitle: appliedCoupon ? appliedCoupon.title : null,
    couponDiscount,
    couponError,
    hasMembership,
    membershipPlanType,
    membership_plan_type: membershipPlanType,
    membershipId: resolvedMembershipId || membershipId || null,
    membership_id: resolvedMembershipId || membershipId || null,
    membershipFoodDiscount,
    membershipDeliveryDiscount,
    membershipDiscount,
    totalDiscounts,
    grandTotal,
    cashRoundOff,
    finalPayable,
    totalSavings,
    paymentMethod: isCod ? 'cod' : ((paymentMethod || '').toString().toLowerCase().includes('wallet') ? 'wallet' : 'online'),
    cashRoundingApplied: isCod && cashRoundOff !== 0
  };
}

module.exports = {
  calculateFoodBill,
  calculateDistanceKm
};
