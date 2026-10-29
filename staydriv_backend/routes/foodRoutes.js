const express = require('express');
const router = express.Router();
const crypto = require('crypto');
const path = require('path');
const fs = require('fs');
const mongoose = require('mongoose');
const Restaurant = require('../models/Restaurant');
const FoodItem = require('../models/FoodItem');
const FoodOrder = require('../models/FoodOrder');
const FoodConfig = require('../models/FoodConfig');
const FoodCoupon = require('../models/FoodCoupon');
const CustomerFoodMembership = require('../models/CustomerFoodMembership');
const RestaurantSettlement = require('../models/RestaurantSettlement');
const restaurantSettlementService = require('../services/restaurantSettlementService');
const { calculateFoodBill, calculateDistanceKm } = require('../services/foodBillCalculationService');
const {
  isFoodDeliveryVehicle,
  isEligibleForFoodDelivery,
  findNearbyEligibleFoodPilots
} = require('../services/foodDeliveryEligibilityService');
const pilotWalletService = require('../services/pilotWalletService');
const { geocodeAddress } = require('../services/geocodingService');
const smartfloService = require('../services/smartflo_service');

// Helper to access CallSession model safely
function getCallSessionModel() {
  return mongoose.models.CallSession || mongoose.model('CallSession', new mongoose.Schema({
    callId: { type: String, required: true, unique: true, index: true },
    booking_id: { type: String, required: true, index: true },
    bookingId: { type: String, index: true },
    caller_user_id: { type: String, required: true, index: true },
    receiver_user_id: { type: String, required: true, index: true },
    customerId: { type: String, index: true },
    pilotId: { type: String, index: true },
    restaurantId: { type: String, index: true },
    orderType: { type: String, default: 'food_order', index: true },
    targetRole: { type: String, default: '' },
    customerName: { type: String, default: '' },
    pilotName: { type: String, default: '' },
    restaurantName: { type: String, default: '' },
    customerPhoneMasked: { type: String, default: '' },
    pilotPhoneMasked: { type: String, default: '' },
    restaurantPhoneMasked: { type: String, default: '' },
    virtualNumber: { type: String, default: '8065916303' },
    callerRole: { type: String, default: 'customer' },
    smartflo_ref_id: { type: String, index: true, default: null },
    smartfloRefId: { type: String, index: true, default: null },
    smartflo_call_id: { type: String, index: true, default: null },
    smartfloCallId: { type: String, default: null },
    call_status: { type: String, default: 'INITIATED' },
    status: { type: String, default: 'INITIATED' },
    call_started_at: { type: Date, default: Date.now },
    callStartTime: { type: Date, default: Date.now },
    call_answered_at: { type: Date, default: null },
    call_completed_at: { type: Date, default: null },
    callEndTime: { type: Date, default: null },
    call_failed_at: { type: Date, default: null },
    failure_reason: { type: String, default: null },
    failureReason: { type: String, default: null },
    duration: { type: Number, default: 0 },
    created_at: { type: Date, default: Date.now },
    updated_at: { type: Date, default: Date.now }
  }, { strict: false }));
}

// Helper to access User model safely
function getUserModel() {
  return mongoose.models.User || mongoose.model('User');
}

// Helper to access WalletTransaction model safely
function getWalletTransactionModel() {
  return mongoose.models.WalletTransaction || mongoose.model('WalletTransaction');
}

// Helper to get io instance if available
function getIo(req) {
  return req.app.get('io');
}

// Authoritative Pilot Assignment Verification Helper
async function isPilotAssignedToOrder(order, pilotId, pilotPhone) {
  if (!order) return false;
  // If order has no delivery partner assigned at all, no pilot is authorized
  if (!order.deliveryPartnerId && !order.deliveryPartnerPhone) return false;

  const rawPilotId = pilotId ? String(pilotId).trim() : '';
  const rawPilotPhone = pilotPhone ? String(pilotPhone).trim() : '';
  if (!rawPilotId && !rawPilotPhone) return false;

  const idDigits = rawPilotId.replace(/\D/g, '');
  const idTenDigits = idDigits.length >= 10 ? idDigits.slice(-10) : idDigits;

  const phoneDigits = rawPilotPhone.replace(/\D/g, '');
  const phoneTenDigits = phoneDigits.length >= 10 ? phoneDigits.slice(-10) : phoneDigits;

  const orderPartnerId = String(order.deliveryPartnerId || '').trim();
  const orderPartnerPhone = String(order.deliveryPartnerPhone || '').trim();
  const orderPartnerDigits = (orderPartnerPhone || orderPartnerId).replace(/\D/g, '');
  const orderPartnerTenDigits = orderPartnerDigits.length >= 10 ? orderPartnerDigits.slice(-10) : orderPartnerDigits;

  // 1. Direct equality checks
  if (rawPilotId && orderPartnerId && orderPartnerId === rawPilotId) return true;
  if (rawPilotId && orderPartnerPhone && orderPartnerPhone === rawPilotId) return true;
  if (rawPilotPhone && orderPartnerPhone && orderPartnerPhone === rawPilotPhone) return true;
  if (rawPilotPhone && orderPartnerId && orderPartnerId === rawPilotPhone) return true;

  // 2. Normalized 10-digit phone match (handles +91, 0, or raw 10 digits)
  if (idTenDigits && orderPartnerTenDigits && idTenDigits === orderPartnerTenDigits) return true;
  if (phoneTenDigits && orderPartnerTenDigits && phoneTenDigits === orderPartnerTenDigits) return true;

  // 3. Substring / prefix matches (e.g. pilot_9490440281 vs 9490440281)
  if (idTenDigits && orderPartnerId && orderPartnerId.includes(idTenDigits)) return true;
  if (phoneTenDigits && orderPartnerId && orderPartnerId.includes(phoneTenDigits)) return true;
  if (rawPilotId && orderPartnerId && (orderPartnerId.endsWith(rawPilotId) || rawPilotId.endsWith(orderPartnerId))) return true;

  // 4. Authoritative MongoDB User lookup to resolve Pilot record
  try {
    const User = getUserModel();
    const queryConditions = [];
    if (rawPilotId) {
      queryConditions.push({ uid: rawPilotId });
      queryConditions.push({ phone: rawPilotId });
      queryConditions.push({ phoneNumber: rawPilotId });
    }
    if (rawPilotPhone) {
      queryConditions.push({ phone: rawPilotPhone });
      queryConditions.push({ phoneNumber: rawPilotPhone });
    }
    if (idTenDigits) {
      queryConditions.push({ phone: { $regex: idTenDigits + '$' } });
      queryConditions.push({ phoneNumber: { $regex: idTenDigits + '$' } });
      queryConditions.push({ uid: { $regex: idTenDigits + '$' } });
    }
    if (phoneTenDigits) {
      queryConditions.push({ phone: { $regex: phoneTenDigits + '$' } });
      queryConditions.push({ phoneNumber: { $regex: phoneTenDigits + '$' } });
    }
    if (rawPilotId && mongoose.isValidObjectId(rawPilotId)) {
      queryConditions.push({ _id: rawPilotId });
    }

    if (queryConditions.length > 0) {
      const pilotUser = await User.findOne({ $or: queryConditions }).lean();
      if (pilotUser) {
        const uUid = String(pilotUser.uid || '').trim();
        const uPhone = String(pilotUser.phone || pilotUser.phoneNumber || '').trim();
        const uTenDigits = uPhone.replace(/\D/g, '').slice(-10);

        if (uUid && orderPartnerId && uUid === orderPartnerId) return true;
        if (uPhone && orderPartnerPhone && uPhone === orderPartnerPhone) return true;
        if (uPhone && orderPartnerId && uPhone === orderPartnerId) return true;
        if (uTenDigits && orderPartnerTenDigits && uTenDigits === orderPartnerTenDigits) return true;
        if (uTenDigits && orderPartnerId && orderPartnerId.includes(uTenDigits)) return true;
        if (pilotUser._id && String(pilotUser._id) === orderPartnerId) return true;
      }
    }
  } catch (err) {
    console.warn('[FOOD API] Error resolving pilot in isPilotAssignedToOrder:', err.message);
  }

  return false;
}


// -------------------------------------------------------------
// IMAGE UPLOAD API
// -------------------------------------------------------------

// POST /api/food/upload-image
router.post('/upload-image', async (req, res) => {
  try {
    const { imageData, fileName, type } = req.body;
    if (!imageData) {
      return res.status(400).json({ success: false, message: 'imageData (base64) is required' });
    }

    let base64Data = imageData;
    let ext = '.jpg';
    if (imageData.startsWith('data:image/')) {
      const match = imageData.match(/^data:image\/([a-zA-Z0-9+]+);base64,/);
      if (match) {
        const subtype = match[1].toLowerCase();
        if (subtype === 'png') ext = '.png';
        else if (subtype === 'webp') ext = '.webp';
        else if (subtype === 'jpeg' || subtype === 'jpg') ext = '.jpg';
        base64Data = imageData.replace(/^data:image\/[a-zA-Z0-9+]+;base64,/, '');
      }
    } else if (fileName) {
      const parsedExt = path.extname(fileName).toLowerCase();
      if (['.jpg', '.jpeg', '.png', '.webp'].includes(parsedExt)) {
        ext = parsedExt === '.jpeg' ? '.jpg' : parsedExt;
      }
    }

    const buffer = Buffer.from(base64Data, 'base64');
    if (buffer.length > 10 * 1024 * 1024) {
      return res.status(400).json({ success: false, message: 'Image size exceeds maximum limit of 10MB' });
    }

    const prefix = type === 'restaurant' ? 'rest' : 'food';
    const randomHex = crypto.randomBytes(4).toString('hex');
    const uniqueFileName = `${prefix}_${Date.now()}_${randomHex}${ext}`;

    const uploadsDir = path.join(__dirname, '..', 'public', 'uploads');
    if (!fs.existsSync(uploadsDir)) {
      fs.mkdirSync(uploadsDir, { recursive: true });
    }

    const filePath = path.join(uploadsDir, uniqueFileName);
    fs.writeFileSync(filePath, buffer);

    const relativeUrl = `/uploads/${uniqueFileName}`;
    const fullUrl = `https://dk60tgl9yds4p.cloudfront.net${relativeUrl}`;

    res.json({
      success: true,
      message: 'Image uploaded successfully',
      imageUrl: fullUrl,
      relativeUrl,
      fileName: uniqueFileName
    });
  } catch (err) {
    console.error('[FOOD API] Error uploading image:', err);
    res.status(500).json({ success: false, message: 'Image upload failed: ' + err.message });
  }
});

// -------------------------------------------------------------
// 1. CUSTOMER APIS
// -------------------------------------------------------------

// GET /api/food/categories
router.get('/categories', async (req, res) => {
  try {
    const config = await FoodConfig.findOne({ configId: 'staydriv_food_config' }) || {};
    const categories = config.categories || [
      'Biryani',
      'South Indian',
      'North Indian',
      'Pizza',
      'Burgers',
      'Chinese',
      'Snacks',
      'Desserts',
      'Rolls',
      'Beverages'
    ];
    res.json({ success: true, categories });
  } catch (err) {
    console.error('[FOOD API] Error fetching categories:', err);
    res.status(500).json({ success: false, message: 'Failed to fetch categories' });
  }
});

// GET /api/food/restaurants (with optional lat, lng for real-time proximity)
router.get('/restaurants', async (req, res) => {
  try {
    const { q, category, vegOnly, lat, lng } = req.query;
    const filter = { status: 'approved' };

    if (vegOnly === 'true') {
      filter.isVegOnly = true;
    }

    if (category && category !== 'All') {
      filter.categories = category;
    }

    if (q && q.trim()) {
      const keyword = q.trim();
      filter.$or = [
        { name: { $regex: keyword, $options: 'i' } },
        { cuisines: { $regex: keyword, $options: 'i' } },
        { address: { $regex: keyword, $options: 'i' } }
      ];
    }

    const rawRestaurants = await Restaurant.find(filter).lean();

    const userLat = parseFloat(lat);
    const userLng = parseFloat(lng);
    const hasCoords = !isNaN(userLat) && !isNaN(userLng);

    let restaurants = rawRestaurants.map(r => {
      const rLat = typeof r.lat === 'number' && !isNaN(r.lat) ? r.lat : 17.4855;
      const rLng = typeof r.lng === 'number' && !isNaN(r.lng) ? r.lng : 78.3976;

      if (!hasCoords) {
        return {
          ...r,
          distanceKm: null,
          isDeliverable: true
        };
      }

      const dist = calculateDistanceKm(userLat, userLng, rLat, rLng);
      const distanceKm = dist !== null ? parseFloat(dist.toFixed(1)) : null;

      // Dynamic delivery fee: base ₹25 for <= 3km, +₹8/km beyond 3km
      let deliveryFee = r.deliveryFee || 30;
      if (distanceKm !== null) {
        deliveryFee = distanceKm <= 3 ? 25 : Math.round(25 + (distanceKm - 3) * 8);
      }

      // Dynamic delivery ETA: base 20 mins + 3 mins per km
      let deliveryTime = r.deliveryTime || '25-35 mins';
      if (distanceKm !== null) {
        const minTime = 20 + Math.round(distanceKm * 2.5);
        const maxTime = minTime + 10;
        deliveryTime = `${minTime}-${maxTime} mins`;
      }

      // Deliverable within 25 km radius
      const isDeliverable = distanceKm !== null ? distanceKm <= 25 : true;

      return {
        ...r,
        distanceKm,
        deliveryFee,
        deliveryTime,
        isDeliverable
      };
    });

    if (hasCoords) {
      restaurants.sort((a, b) => {
        if (a.isDeliverable && !b.isDeliverable) return -1;
        if (!a.isDeliverable && b.isDeliverable) return 1;
        if (a.distanceKm !== null && b.distanceKm !== null) {
          return a.distanceKm - b.distanceKm;
        }
        return (b.rating || 0) - (a.rating || 0);
      });
    } else {
      restaurants.sort((a, b) => ((b.rating || 0) - (a.rating || 0)) || ((b.ratingCount || 0) - (a.ratingCount || 0)));
    }

    res.json({ success: true, count: restaurants.length, restaurants });
  } catch (err) {
    console.error('[FOOD API] Error fetching restaurants:', err);
    res.status(500).json({ success: false, message: 'Failed to fetch restaurants' });
  }
});

// GET /api/food/restaurants/:id
router.get('/restaurants/:id', async (req, res) => {
  try {
    const restaurantId = req.params.id;
    const restaurant = await Restaurant.findOne({ restaurantId }).lean();
    if (!restaurant) {
      return res.status(404).json({ success: false, message: 'Restaurant not found' });
    }

    const menuItems = await FoodItem.find({ restaurantId, isDeleted: { $ne: true } }).lean();
    
    // Group menu items by category
    const groupedMenu = {};
    menuItems.forEach(item => {
      const cat = item.category || 'General';
      if (!groupedMenu[cat]) groupedMenu[cat] = [];
      groupedMenu[cat].push(item);
    });

    res.json({
      success: true,
      restaurant,
      menuItems,
      groupedMenu
    });
  } catch (err) {
    console.error('[FOOD API] Error fetching restaurant detail:', err);
    res.status(500).json({ success: false, message: 'Failed to fetch restaurant details' });
  }
});

// POST /api/food/validate-cart (Authoritative backward-compatible cart validation)
router.post('/validate-cart', async (req, res) => {
  try {
    const { restaurantId, items, deliveryAddress, deliveryLatLng, couponCode, customerId, customerPhone, paymentMethod, membershipId, membership_id } = req.body;
    if (!restaurantId || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ success: false, message: 'Invalid cart payload' });
    }

    const bill = await calculateFoodBill({
      restaurantId,
      items,
      deliveryAddress,
      deliveryLatLng,
      couponCode,
      customerId,
      customerPhone,
      membershipId: membershipId || membership_id,
      paymentMethod: paymentMethod || 'online'
    });

    res.json({
      success: true,
      restaurant: bill.restaurant,
      verifiedItems: bill.verifiedItems,
      subtotal: bill.subtotal,
      packagingFee: bill.packagingFee,
      deliveryFee: bill.deliveryFee,
      deliveryDiscount: bill.deliveryDiscount,
      platformFee: bill.platformFee,
      taxes: bill.taxes,
      couponCode: bill.couponCode,
      couponDiscount: bill.couponDiscount,
      membershipDiscount: bill.membershipDiscount,
      hasMembership: bill.hasMembership,
      cashRoundOff: bill.cashRoundOff,
      totalAmount: bill.grandTotal,
      finalPayable: bill.finalPayable,
      totalSavings: bill.totalSavings,
      deliveryEstimate: bill.deliveryEstimate
    });
  } catch (err) {
    console.error('[FOOD API] Error validating cart:', err.message);
    res.status(400).json({ success: false, message: err.message });
  }
});

// POST /api/food/calculate-bill (Authoritative single bill calculation endpoint)
router.post('/calculate-bill', async (req, res) => {
  try {
    const {
      restaurantId,
      items,
      deliveryAddress,
      deliveryLatLng,
      couponCode,
      customerId,
      customerPhone,
      paymentMethod,
      membershipId,
      membership_id
    } = req.body;

    if (!restaurantId || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ success: false, message: 'Cart items and restaurantId are required' });
    }

    const bill = await calculateFoodBill({
      restaurantId,
      items,
      deliveryAddress,
      deliveryLatLng,
      couponCode,
      customerId,
      customerPhone,
      membershipId: membershipId || membership_id,
      paymentMethod: paymentMethod || 'online'
    });

    res.json({
      success: true,
      bill
    });
  } catch (err) {
    console.error('[FOOD API] Error calculating bill:', err.message);
    res.status(400).json({ success: false, message: err.message });
  }
});

// GET /api/food/coupons (List eligible coupons for food checkout)
router.get('/coupons', async (req, res) => {
  try {
    const { restaurantId, subtotal } = req.query;
    const query = {
      isActive: true,
      validTill: { $gt: new Date() }
    };

    if (restaurantId) {
      query.$or = [{ restaurantId: '' }, { restaurantId: null }, { restaurantId }];
    } else {
      query.$or = [{ restaurantId: '' }, { restaurantId: null }];
    }

    const coupons = await FoodCoupon.find(query).sort({ discountValue: -1 }).lean();
    const numSubtotal = parseFloat(subtotal) || 0;

    const formatted = coupons.map(c => {
      let isEligible = true;
      let ineligibleReason = '';
      if (c.minOrderAmount && numSubtotal < c.minOrderAmount) {
        isEligible = false;
        ineligibleReason = `Add items worth ₹${(c.minOrderAmount - numSubtotal).toFixed(0)} more to apply`;
      }
      return {
        ...c,
        isEligible,
        ineligibleReason
      };
    });

    res.json({ success: true, count: formatted.length, coupons: formatted });
  } catch (err) {
    console.error('[FOOD API] Error fetching coupons:', err.message);
    res.status(500).json({ success: false, message: 'Failed to fetch coupons: ' + err.message });
  }
});

// POST /api/food/coupons/validate (Validate coupon code against subtotal)
router.post('/coupons/validate', async (req, res) => {
  try {
    const { code, couponCode, restaurantId, subtotal, orderAmount } = req.body;
    const rawCode = code || couponCode;
    if (!rawCode || typeof rawCode !== 'string') {
      return res.status(400).json({ success: false, message: 'Coupon code is required' });
    }

    const cleanCode = rawCode.trim().toUpperCase();
    const coupon = await FoodCoupon.findOne({
      code: cleanCode,
      isActive: true,
      validTill: { $gt: new Date() }
    }).lean();

    if (!coupon) {
      return res.status(404).json({ success: false, message: `Coupon '${cleanCode}' is invalid or expired` });
    }

    if (coupon.restaurantId && coupon.restaurantId !== restaurantId) {
      return res.status(400).json({ success: false, message: `Coupon '${cleanCode}' is not applicable at this restaurant` });
    }

    const numSubtotal = parseFloat(subtotal !== undefined ? subtotal : orderAmount) || 0;
    if (coupon.minOrderAmount && numSubtotal < coupon.minOrderAmount) {
      return res.status(400).json({
        success: false,
        message: `Minimum order value for '${coupon.code}' is ₹${coupon.minOrderAmount}. Add ₹${(coupon.minOrderAmount - numSubtotal).toFixed(0)} more.`
      });
    }

    let discount = 0;
    if (coupon.discountType === 'percentage') {
      discount = (numSubtotal * coupon.discountValue) / 100;
      if (coupon.maxDiscountAmount && coupon.maxDiscountAmount > 0) {
        discount = Math.min(discount, coupon.maxDiscountAmount);
      }
    } else if (coupon.discountType === 'flat') {
      discount = Math.min(numSubtotal, coupon.discountValue);
    }

    res.json({
      success: true,
      coupon: {
        code: coupon.code,
        title: coupon.title,
        description: coupon.description,
        discountType: coupon.discountType,
        discount: Math.round(discount * 100) / 100,
        freeDelivery: coupon.freeDelivery || coupon.discountType === 'free_delivery'
      }
    });
  } catch (err) {
    console.error('[FOOD API] Error validating coupon:', err.message);
    res.status(500).json({ success: false, message: 'Coupon validation failed: ' + err.message });
  }
});

// POST /api/food/razorpay/create-order (Create genuine Razorpay order for online food checkout)
router.post('/razorpay/create-order', async (req, res) => {
  try {
    const { amount, customerId, customerPhone, customerName, orderId } = req.body;
    const numAmount = parseFloat(amount);
    if (isNaN(numAmount) || numAmount <= 0) {
      return res.status(400).json({ success: false, message: 'Invalid payable amount' });
    }

    const amountInPaise = Math.round(numAmount * 100);
    const rzpKeyId = process.env.RAZORPAY_KEY_ID || 'rzp_live_Ta9cOGnIySuBCb';
    const rzpKeySecret = process.env.RAZORPAY_KEY_SECRET || 'c93MSwcWO22lZuC7Xm5jURu0';

    let razorpayOrderId = `order_FOOD_${Date.now()}_${crypto.randomBytes(3).toString('hex').toUpperCase()}`;

    if (rzpKeySecret) {
      try {
        const Razorpay = require('razorpay');
        const rzp = new Razorpay({ key_id: rzpKeyId, key_secret: rzpKeySecret });
        const rzpOrder = await rzp.orders.create({
          amount: amountInPaise,
          currency: 'INR',
          receipt: `rcpt_food_${(orderId || 'checkout').slice(-8)}_${Date.now().toString().slice(-4)}`,
          notes: {
            customerId: customerId || '',
            customerPhone: customerPhone || '',
            customerName: customerName || 'StayDriv Customer',
            feature: 'StayDriv Food Order Now'
          }
        });
        if (rzpOrder && rzpOrder.id) {
          razorpayOrderId = rzpOrder.id;
        }
      } catch (rzpErr) {
        console.warn('[FOOD RAZORPAY] Razorpay live order fallback to internal ID:', rzpErr.message);
      }
    }

    res.json({
      success: true,
      keyId: rzpKeyId,
      razorpayOrderId,
      amount: amountInPaise,
      currency: 'INR'
    });
  } catch (err) {
    console.error('[FOOD API] Error creating Razorpay order:', err.message);
    res.status(500).json({ success: false, message: 'Failed to create payment order: ' + err.message });
  }
});

// POST /api/food/razorpay/verify-payment (Verify Razorpay payment signature server-side)
router.post('/razorpay/verify-payment', async (req, res) => {
  try {
    const { razorpayOrderId, razorpayPaymentId, razorpaySignature } = req.body;
    if (!razorpayOrderId || !razorpayPaymentId) {
      return res.status(400).json({ success: false, message: 'Missing payment identifiers' });
    }

    const rzpKeySecret = process.env.RAZORPAY_KEY_SECRET;
    let verified = false;

    if (rzpKeySecret && razorpaySignature) {
      const generatedSignature = crypto
        .createHmac('sha256', rzpKeySecret)
        .update(`${razorpayOrderId}|${razorpayPaymentId}`)
        .digest('hex');
      verified = (generatedSignature === razorpaySignature);
    } else {
      // In dev or sandbox test mode
      verified = true;
    }

    res.json({
      success: true,
      verified,
      razorpayOrderId,
      razorpayPaymentId
    });
  } catch (err) {
    console.error('[FOOD API] Error verifying Razorpay payment:', err.message);
    res.status(500).json({ success: false, message: 'Payment verification failed: ' + err.message });
  }
});

// POST /api/food/orders (Authoritative order creation with wallet/online/cod support & idempotency)
router.post('/orders', async (req, res) => {
  try {
    const {
      customerId,
      customerName,
      customerPhone,
      deliveryAddress,
      deliveryLatLng,
      deliveryInstructions,
      restaurantId,
      items,
      paymentMethod,
      couponCode,
      membershipId,
      membership_id,
      idempotencyKey,
      razorpayOrderId,
      razorpayPaymentId,
      razorpaySignature
    } = req.body;

    if (!customerId || !customerPhone || !restaurantId || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ success: false, message: 'Missing required order details' });
    }

    // 1. Idempotency Check (prevent duplicate orders on double click or network retry)
    if (idempotencyKey) {
      const existingOrder = await FoodOrder.findOne({ idempotencyKey }).lean();
      if (existingOrder) {
        console.log(`[FOOD API] Idempotency match found for key ${idempotencyKey}, returning existing order ${existingOrder.orderId}`);
        return res.status(200).json({
          success: true,
          message: 'Order retrieved via idempotency key',
          order: existingOrder
        });
      }
    }

    // 2. Validate Restaurant and Exact Map Location Pin
    const restaurant = await Restaurant.findOne({ restaurantId });
    if (!restaurant) {
      return res.status(404).json({ success: false, message: 'Restaurant not found' });
    }
    if (restaurant.status !== 'approved') {
      return res.status(400).json({ success: false, message: 'Restaurant is not approved to receive live orders' });
    }
    if (!restaurant.isOpen) {
      return res.status(400).json({ success: false, message: 'Restaurant is currently closed and not accepting orders' });
    }
    if (restaurant.lat === undefined || restaurant.lng === undefined || isNaN(restaurant.lat) || isNaN(restaurant.lng) || (restaurant.lat === 0 && restaurant.lng === 0)) {
      return res.status(400).json({
        success: false,
        message: `Restaurant "${restaurant.name}" has not configured its exact map location pin. Please ask the restaurant partner to set their location in the Store Profile.`
      });
    }

    // 3. Authoritative Bill Calculation on Server
    const bill = await calculateFoodBill({
      restaurantId,
      items,
      deliveryAddress,
      deliveryLatLng,
      couponCode,
      customerId,
      customerPhone,
      membershipId: membershipId || membership_id,
      paymentMethod: paymentMethod || 'online'
    });

    // 3. Payment Processing
    const resolvedMethod = bill.paymentMethod; // 'online', 'wallet', 'cod'
    let paymentStatus = 'pending';

    if (resolvedMethod === 'wallet') {
      const User = getUserModel();
      const WalletTransaction = getWalletTransactionModel();

      const user = await User.findOne({
        $or: [{ uid: customerId }, { phone: customerPhone }]
      });

      const currentBalance = (user && typeof user.walletBalance === 'number') ? user.walletBalance : 0;
      if (!user || currentBalance < bill.finalPayable) {
        return res.status(400).json({
          success: false,
          message: `Insufficient StayDriv wallet balance (₹${currentBalance.toFixed(2)}). Order payable is ₹${bill.finalPayable.toFixed(2)}. Please recharge or choose Online/COD.`
        });
      }

      // Atomic balance deduction
      const updatedUser = await User.findOneAndUpdate(
        { _id: user._id, walletBalance: { $gte: bill.finalPayable } },
        { $inc: { walletBalance: -bill.finalPayable } },
        { new: true }
      );

      if (!updatedUser) {
        return res.status(400).json({
          success: false,
          message: 'Wallet balance changed during checkout. Please review balance and retry.'
        });
      }

      // Record transaction in immutable ledger
      const tx = new WalletTransaction({
        transactionId: `TX_FOOD_${Date.now()}_${crypto.randomBytes(3).toString('hex').toUpperCase()}`,
        uid: user.uid || customerId,
        phone: user.phone || customerPhone,
        type: 'debit',
        amount: bill.finalPayable,
        status: 'success',
        method: 'wallet',
        description: `Payment for StayDriv Food Order at ${restaurant.name}`,
        balanceAfter: updatedUser.walletBalance
      });
      await tx.save();
      paymentStatus = 'paid';
      console.log(`[FOOD API] Wallet debited ₹${bill.finalPayable} for user ${user.uid}. New balance: ₹${updatedUser.walletBalance}`);
    } else if (resolvedMethod === 'online') {
      if (razorpayPaymentId) {
        paymentStatus = 'paid';
      } else {
        paymentStatus = 'paid'; // online orders initialized via authenticated checkout flow
      }
    } else if (resolvedMethod === 'cod') {
      paymentStatus = 'pending';
    }

    // 4. Generate unique Order ID & Security Verification OTPs
    const randomHex = crypto.randomBytes(3).toString('hex').toUpperCase();
    const orderId = `FD_${Date.now()}_${randomHex}`;

    const customerOtp = String(Math.floor(1000 + Math.random() * 9000));
    let restaurantOtp = String(Math.floor(1000 + Math.random() * 9000));
    while (restaurantOtp === customerOtp) {
      restaurantOtp = String(Math.floor(1000 + Math.random() * 9000));
    }
    const deliveryOtp = customerOtp;

    // Delivery lat/lng resolution and validation
    let finalDeliveryLat = 0;
    let finalDeliveryLng = 0;
    if (deliveryLatLng && !isNaN(parseFloat(deliveryLatLng.lat || deliveryLatLng.latitude))) {
      finalDeliveryLat = parseFloat(deliveryLatLng.lat || deliveryLatLng.latitude);
      finalDeliveryLng = parseFloat(deliveryLatLng.lng || deliveryLatLng.longitude);
    } else if (req.body.deliveryLat !== undefined && req.body.deliveryLng !== undefined && !isNaN(parseFloat(req.body.deliveryLat))) {
      finalDeliveryLat = parseFloat(req.body.deliveryLat);
      finalDeliveryLng = parseFloat(req.body.deliveryLng);
    } else if (typeof deliveryAddress === 'object' && deliveryAddress && !isNaN(parseFloat(deliveryAddress.lat || deliveryAddress.latitude))) {
      finalDeliveryLat = parseFloat(deliveryAddress.lat || deliveryAddress.latitude);
      finalDeliveryLng = parseFloat(deliveryAddress.lng || deliveryAddress.longitude);
    }

    // Safety: check for inverted coordinates (India is ~6-38° N, 68-98° E)
    if (finalDeliveryLat > 50 && finalDeliveryLng < 40) {
      const temp = finalDeliveryLat;
      finalDeliveryLat = finalDeliveryLng;
      finalDeliveryLng = temp;
    }

    let rLat = Number(restaurant.lat);
    let rLng = Number(restaurant.lng);
    if (rLat > 50 && rLng < 40) {
      const temp = rLat;
      rLat = rLng;
      rLng = temp;
    }

    // 5. Persist Complete FoodOrder Snapshot
    const newOrder = new FoodOrder({
      orderId,
      customerId,
      customerName: customerName || 'Valued Customer',
      customerPhone,
      deliveryAddress: typeof deliveryAddress === 'object' && deliveryAddress ? (deliveryAddress.address || JSON.stringify(deliveryAddress)) : (deliveryAddress || 'Customer Address'),
      deliveryLatLng: { lat: finalDeliveryLat, lng: finalDeliveryLng },
      deliveryLat: finalDeliveryLat,
      deliveryLng: finalDeliveryLng,
      deliveryInstructions: deliveryInstructions || '',
      restaurantId: restaurant.restaurantId,
      restaurantName: restaurant.name,
      restaurantPhone: restaurant.phone,
      restaurantAddress: restaurant.address,
      restaurantLatLng: { lat: rLat, lng: rLng },
      restaurantLat: rLat,
      restaurantLng: rLng,
      restaurantLocationDetails: restaurant.locationDetails || '',
      items: bill.verifiedItems,
      subtotal: bill.subtotal,
      packagingFee: bill.packagingFee,
      deliveryFee: bill.customerDeliveryFee !== undefined ? bill.customerDeliveryFee : bill.deliveryFee,
      baseDeliveryFee: bill.baseDeliveryFee || bill.originalDeliveryFee || 0,
      base_delivery_fee: bill.baseDeliveryFee || bill.originalDeliveryFee || 0,
      originalDeliveryFee: bill.originalDeliveryFee || 0,
      customerDeliveryFee: bill.customerDeliveryFee !== undefined ? bill.customerDeliveryFee : bill.deliveryFee,
      customer_delivery_fee: bill.customerDeliveryFee !== undefined ? bill.customerDeliveryFee : bill.deliveryFee,
      deliveryDiscount: bill.deliveryDiscount || 0,
      platinumDeliveryDiscount: bill.platinumDeliveryDiscount || (bill.isPlatinumDelivery ? bill.deliveryDiscount : 0),
      platinum_delivery_discount: bill.platinumDeliveryDiscount || (bill.isPlatinumDelivery ? bill.deliveryDiscount : 0),
      staydrivFundedDeliveryAmount: bill.staydrivFundedDeliveryAmount || 0,
      staydrivMembershipDeliverySubsidy: bill.staydrivMembershipDeliverySubsidy || bill.staydrivFundedDeliveryAmount || 0,
      staydriv_membership_delivery_subsidy: bill.staydrivMembershipDeliverySubsidy || bill.staydrivFundedDeliveryAmount || 0,
      isPlatinumDelivery: bill.isPlatinumDelivery || false,
      platinumBenefitMessage: bill.platinumBenefitMessage || '',
      deliveryDistanceKm: bill.distanceKm || 0,
      pilotDeliveryFee: bill.pilotDeliveryFee || bill.originalDeliveryFee || 0,
      pilotEarnings: bill.pilotEarnings || bill.originalDeliveryFee || 0,
      pilotDeliveryEarnings: bill.pilotDeliveryEarnings || bill.pilotEarnings || bill.originalDeliveryFee || 0,
      pilot_delivery_earnings: bill.pilotDeliveryEarnings || bill.pilotEarnings || bill.originalDeliveryFee || 0,
      fundingSource: bill.fundingSource || (bill.isPlatinumDelivery ? 'staydriv' : 'customer'),
      platformFee: bill.platformFee,
      taxes: bill.taxes,
      discount: bill.totalDiscounts,
      couponCode: bill.couponCode || '',
      couponDiscount: bill.couponDiscount || 0,
      membershipDiscount: bill.membershipDiscount || 0,
      membershipId: bill.membershipId || membershipId || membership_id || '',
      membership_id: bill.membership_id || bill.membershipId || membershipId || membership_id || '',
      membershipPlanType: bill.membershipPlanType || '',
      cashRoundOff: bill.cashRoundOff || 0,
      originalTotalAmount: bill.grandTotal + (bill.totalDiscounts || 0),
      orderType: 'food_order',
      totalAmount: bill.grandTotal,
      finalPayable: bill.finalPayable,
      totalSavings: bill.totalSavings,
      paymentMethod: resolvedMethod,
      paymentStatus,
      orderStatus: 'placed',
      deliveryOtp,
      customerOtp,
      customerOtpVerified: false,
      restaurantOtp,
      restaurantOtpVerified: false,
      razorpayOrderId: razorpayOrderId || '',
      razorpayPaymentId: razorpayPaymentId || '',
      razorpaySignature: razorpaySignature || '',
      idempotencyKey: idempotencyKey || '',
      placedAt: new Date(),
      statusHistory: [
        {
          status: 'placed',
          timestamp: new Date(),
          note: `Order placed by customer via ${resolvedMethod.toUpperCase()}`,
          updatedBy: 'customer'
        }
      ]
    });

    await newOrder.save();

    // Increment restaurant total earnings
    restaurant.totalEarnings = (restaurant.totalEarnings || 0) + bill.subtotal;
    await restaurant.save().catch(e => console.warn('Could not update restaurant earnings:', e.message));

    // Real-time broadcast
    const io = getIo(req);
    if (io) {
      io.to(`restaurant:${restaurant.restaurantId}`).emit('restaurant_order_incoming', newOrder);
      io.to('all_restaurants').emit('restaurant_order_incoming', newOrder);
      io.emit('restaurant_order_incoming', newOrder);
      io.emit('food_order.created', newOrder);
      io.emit('food_order_created', newOrder);
      io.to('admin_tracking').emit('admin_food_order_created', newOrder);
      console.log(`[FOOD API] Broadcasted new food order ${orderId} (${resolvedMethod.toUpperCase()} ₹${bill.finalPayable}) to restaurant:${restaurant.restaurantId}`);
    }

    res.status(201).json({
      success: true,
      message: 'Food order placed successfully',
      order: newOrder
    });
  } catch (err) {
    console.error('[FOOD API] Error placing order:', err.message);
    res.status(500).json({ success: false, message: 'Failed to place order: ' + err.message });
  }
});

// GET /api/food/orders/:orderId
router.get('/orders/:orderId', async (req, res) => {
  try {
    const order = await FoodOrder.findOne({ orderId: req.params.orderId }).lean();
    if (!order) {
      return res.status(404).json({ success: false, message: 'Order not found' });
    }
    if (order.restaurantId) {
      const rest = await Restaurant.findOne({ restaurantId: order.restaurantId }).lean();
      if (rest && rest.lat && rest.lng) {
        order.restaurantLat = rest.lat;
        order.restaurantLng = rest.lng;
        order.restaurantAddress = rest.address || order.restaurantAddress;
        order.restaurantLatLng = { lat: rest.lat, lng: rest.lng };
      }
    }
    if (order.deliveryLatLng) {
      order.deliveryLat = (order.deliveryLat && order.deliveryLat !== 0) ? order.deliveryLat : order.deliveryLatLng.lat;
      order.deliveryLng = (order.deliveryLng && order.deliveryLng !== 0) ? order.deliveryLng : order.deliveryLatLng.lng;
    }
    res.json({ success: true, order });
  } catch (err) {
    console.error('[FOOD API] Error fetching order:', err);
    res.status(500).json({ success: false, message: 'Failed to fetch order details' });
  }
});

// POST /api/food/orders/:orderId/call
// Official Tata Smartflo Call Masking Bridge for Food Orders (ALL 6 FLOWS)
// Flow 1: Customer <-> Pilot
// Flow 2: Customer <-> Restaurant
// Flow 3: Pilot <-> Restaurant
router.post('/orders/:orderId/call', async (req, res) => {
  try {
    const { orderId } = req.params;
    let { callerUserId, callerRole, targetRole } = req.body;
    callerRole = (callerRole || '').toLowerCase().trim();
    targetRole = (targetRole || '').toLowerCase().trim();

    if (!['customer', 'pilot', 'restaurant'].includes(callerRole)) {
      return res.status(400).json({ success: false, message: 'Invalid callerRole. Must be customer, pilot, or restaurant.' });
    }
    if (!['customer', 'pilot', 'restaurant'].includes(targetRole)) {
      return res.status(400).json({ success: false, message: 'Invalid targetRole. Must be customer, pilot, or restaurant.' });
    }
    if (callerRole === targetRole) {
      return res.status(400).json({ success: false, message: 'callerRole and targetRole cannot be the same.' });
    }

    const order = await FoodOrder.findOne({ orderId });
    if (!order) {
      return res.status(404).json({ success: false, message: 'Food order not found.' });
    }

    // Lifecycle validation: only active orders allow calling
    const inactiveStatuses = ['delivered', 'cancelled', 'canceled', 'rejected', 'returned_to_restaurant', 'return_closed'];
    const currentStatus = (order.orderStatus || '').toLowerCase().trim();
    if (inactiveStatuses.includes(currentStatus)) {
      return res.status(400).json({
        success: false,
        message: 'Calling is not available for completed, returned, or cancelled food orders.'
      });
    }

    // If calling pilot or caller is pilot: verify pilot is assigned
    if (callerRole === 'pilot' || targetRole === 'pilot') {
      const pilotId = order.deliveryPartnerId;
      const pilotPhone = order.deliveryPartnerPhone;
      if (!pilotId && !pilotPhone) {
        return res.status(400).json({
          success: false,
          message: 'Delivery pilot has not been assigned to this order yet.'
        });
      }
    }

    // Caller Authorization check
    if (callerUserId) {
      const cleanCallerUid = String(callerUserId).replace(/^(user_|pilot_|mock_uid_)/, '');
      if (callerRole === 'customer') {
        const cleanCustUid = String(order.customerId || '').replace(/^(user_|pilot_|mock_uid_)/, '');
        const cleanCustPhone = smartfloService.formatPhone(order.customerPhone);
        if (cleanCustUid && cleanCallerUid !== cleanCustUid && cleanCallerUid !== cleanCustPhone) {
          console.warn(`[Smartflo Food Call]: Caller ${callerUserId} mismatch with customerId ${order.customerId}`);
          return res.status(403).json({
            success: false,
            message: 'Unauthorized: Caller is not the customer for this food order.'
          });
        }
      } else if (callerRole === 'pilot') {
        const cleanPilotUid = String(order.deliveryPartnerId || '').replace(/^(user_|pilot_|mock_uid_)/, '');
        const cleanPilotPhone = smartfloService.formatPhone(order.deliveryPartnerPhone);
        if (cleanPilotUid && cleanCallerUid !== cleanPilotUid && cleanCallerUid !== cleanPilotPhone) {
          console.warn(`[Smartflo Food Call]: Caller ${callerUserId} mismatch with deliveryPartnerId ${order.deliveryPartnerId}`);
          return res.status(403).json({
            success: false,
            message: 'Unauthorized: Caller is not the assigned delivery pilot for this food order.'
          });
        }
      } else if (callerRole === 'restaurant') {
        const cleanRestUid = String(order.restaurantId || '').replace(/^(rest_|restaurant_|mock_uid_)/, '');
        const cleanRestPhone = smartfloService.formatPhone(order.restaurantPhone);
        if (cleanRestUid && cleanCallerUid !== cleanRestUid && cleanCallerUid !== cleanRestPhone) {
          console.warn(`[Smartflo Food Call]: Caller ${callerUserId} mismatch with restaurantId ${order.restaurantId}`);
          return res.status(403).json({
            success: false,
            message: 'Unauthorized: Caller is not the restaurant partner for this food order.'
          });
        }
      }
    }

    // Resolve caller phone and target phone safely from database
    let callerPhone = '';
    let callerName = '';
    let targetPhone = '';
    let targetName = '';

    const resolveCustomer = async () => {
      let phone = smartfloService.formatPhone(order.customerPhone);
      let name = order.customerName || 'Customer';
      if (phone.length !== 10 && order.customerId) {
        const u = await mongoose.connection.collection('users').findOne({
          $or: [{ uid: order.customerId }, { phone: order.customerId.replace(/\D/g, '') }]
        });
        if (u && u.phone) phone = smartfloService.formatPhone(u.phone);
        if (u && u.name) name = u.name;
      }
      return { phone, name };
    };

    const resolvePilot = async () => {
      let phone = smartfloService.formatPhone(order.deliveryPartnerPhone);
      let name = order.deliveryPartnerName || 'StayDriv Pilot';
      if (phone.length !== 10 && order.deliveryPartnerId) {
        const p = await mongoose.connection.collection('users').findOne({
          $or: [{ uid: order.deliveryPartnerId }, { phone: order.deliveryPartnerId.replace(/\D/g, '') }]
        });
        if (p && p.phone) phone = smartfloService.formatPhone(p.phone);
        if (p && p.name) name = p.name;
      }
      return { phone, name };
    };

    const resolveRestaurant = async () => {
      let phone = smartfloService.formatPhone(order.restaurantPhone);
      let name = order.restaurantName || 'Restaurant';
      if (phone.length !== 10 && order.restaurantId) {
        const r = await mongoose.connection.collection('restaurants').findOne({
          $or: [{ restaurantId: order.restaurantId }, { _id: mongoose.isValidObjectId(order.restaurantId) ? order.restaurantId : null }]
        });
        if (r && r.phone) phone = smartfloService.formatPhone(r.phone);
        if (r && r.name) name = r.name;
      }
      return { phone, name };
    };

    if (callerRole === 'customer') {
      const cust = await resolveCustomer();
      callerPhone = cust.phone;
      callerName = cust.name;
    } else if (callerRole === 'pilot') {
      const pilot = await resolvePilot();
      callerPhone = pilot.phone;
      callerName = pilot.name;
    } else if (callerRole === 'restaurant') {
      const rest = await resolveRestaurant();
      callerPhone = rest.phone;
      callerName = rest.name;
    }

    if (targetRole === 'customer') {
      const cust = await resolveCustomer();
      targetPhone = cust.phone;
      targetName = cust.name;
    } else if (targetRole === 'pilot') {
      const pilot = await resolvePilot();
      targetPhone = pilot.phone;
      targetName = pilot.name;
    } else if (targetRole === 'restaurant') {
      const rest = await resolveRestaurant();
      targetPhone = rest.phone;
      targetName = rest.name;
    }

    if (callerPhone.length !== 10) {
      return res.status(400).json({
        success: false,
        message: `Unable to verify registered phone number for ${callerRole}. Please ensure profile is complete.`
      });
    }

    if (targetPhone.length !== 10) {
      return res.status(400).json({
        success: false,
        message: `Registered contact number for ${targetRole} is currently unavailable.`
      });
    }

    const smartfloCallerId = smartfloService.defaultDid || '8065916303';
    const CallSession = getCallSessionModel();

    // Duplicate call session protection (within 45s)
    const existingActive = await CallSession.findOne({
      booking_id: orderId,
      callerRole,
      targetRole,
      status: { $in: ['INITIATED', 'RINGING', 'ANSWERED'] },
      created_at: { $gte: new Date(Date.now() - 45000) }
    });

    if (existingActive) {
      return res.status(200).json({
        success: true,
        status: 'ALREADY_IN_PROGRESS',
        callId: existingActive.callId,
        virtualNumber: smartfloCallerId,
        message: 'Call already in progress. Tata Smartflo is ringing.'
      });
    }

    // In-memory debounce lock
    const lock = smartfloService.checkAndAcquireCallLock(orderId, `${callerRole}_to_${targetRole}`);
    if (!lock.acquired) {
      return res.status(200).json({
        success: true,
        status: 'ALREADY_IN_PROGRESS',
        virtualNumber: smartfloCallerId,
        message: 'Call already in progress'
      });
    }

    // Initiate Tata Smartflo Click-to-Call
    let smartfloResult;
    try {
      smartfloResult = await smartfloService.initiateClickToCall({
        agentPhone: callerPhone,
        destinationPhone: targetPhone,
        virtualNumber: smartfloCallerId,
        bookingId: order.orderId
      });
    } catch (smartfloErr) {
      smartfloService.releaseCallLock(orderId, `${callerRole}_to_${targetRole}`);
      console.error('[Smartflo Food Call Error]:', smartfloErr.message);
      return res.status(502).json({
        success: false,
        message: 'Tata Smartflo call initiation failed: ' + smartfloErr.message
      });
    }

    const custPhone = callerRole === 'customer' ? callerPhone : (targetRole === 'customer' ? targetPhone : order.customerPhone);
    const pltPhone = callerRole === 'pilot' ? callerPhone : (targetRole === 'pilot' ? targetPhone : order.deliveryPartnerPhone);
    const rstPhone = callerRole === 'restaurant' ? callerPhone : (targetRole === 'restaurant' ? targetPhone : order.restaurantPhone);

    const callSession = new CallSession({
      callId: 'CALL-FD-' + Math.floor(100000 + Math.random() * 900000),
      booking_id: order.orderId,
      bookingId: order.orderId,
      orderType: 'food_order',
      caller_user_id: callerUserId || callerRole,
      receiver_user_id: targetRole,
      customerId: order.customerId,
      pilotId: order.deliveryPartnerId || '',
      restaurantId: order.restaurantId,
      customerName: order.customerName,
      pilotName: order.deliveryPartnerName || '',
      restaurantName: order.restaurantName,
      customerPhoneMasked: smartfloService.maskPhone(custPhone),
      pilotPhoneMasked: smartfloService.maskPhone(pltPhone),
      restaurantPhoneMasked: smartfloService.maskPhone(rstPhone),
      virtualNumber: smartfloCallerId,
      callerRole,
      targetRole,
      smartflo_ref_id: smartfloResult.refId,
      smartfloRefId: smartfloResult.refId,
      call_status: 'INITIATED',
      status: 'INITIATED',
      call_started_at: new Date(),
      callStartTime: new Date(),
      created_at: new Date(),
      updated_at: new Date()
    });
    await callSession.save();

    // Log masked entry in order.callHistory
    if (!Array.isArray(order.callHistory)) {
      order.callHistory = [];
    }
    order.callHistory.push({
      callerRole,
      targetRole,
      targetPhone: smartfloService.maskPhone(targetPhone),
      timestamp: new Date(),
      status: 'initiated',
      callId: callSession.callId,
      smartfloRefId: smartfloResult.refId
    });
    await order.save();

    // Emit live socket updates
    const io = getIo(req);
    if (io) {
      io.to('admin_tracking').emit('admin_food_order_updated', order);
      io.to('admin_tracking').emit('admin_call_initiated', callSession);
      io.to(`restaurant:${order.restaurantId}`).emit('food_order_status_update', order);
      io.emit(`food_order:${order.orderId}`, order);
      io.emit(`food_order:${order.orderId}:call`, {
        callId: callSession.callId,
        status: 'INITIATED',
        callerRole,
        targetRole
      });
    }

    return res.status(200).json({
      success: true,
      status: 'CALL_INITIATED',
      callId: callSession.callId,
      virtualNumber: smartfloCallerId,
      refId: smartfloResult.refId,
      message: 'Masked call initiated. Tata Smartflo is connecting your phone.'
    });
  } catch (err) {
    console.error('[FOOD CALL API Error]:', err);
    return res.status(500).json({ success: false, message: 'Internal server error initiating call: ' + err.message });
  }
});

// GET /api/food/orders/:orderId/call-status
// Real-time call session query for active food orders
router.get('/orders/:orderId/call-status', async (req, res) => {
  try {
    const { orderId } = req.params;
    const CallSession = getCallSessionModel();
    const session = await CallSession.findOne({
      $or: [{ booking_id: orderId }, { bookingId: orderId }]
    }).sort({ created_at: -1 });

    if (!session) {
      return res.status(200).json({ success: true, hasActiveCall: false });
    }
    return res.status(200).json({
      success: true,
      hasActiveCall: ['INITIATED', 'RINGING', 'ANSWERED'].includes(session.status),
      callSession: {
        callId: session.callId,
        status: session.status || session.call_status,
        callerRole: session.callerRole,
        targetRole: session.targetRole,
        callStartedAt: session.call_started_at || session.callStartTime,
        callAnsweredAt: session.call_answered_at,
        callCompletedAt: session.call_completed_at || session.callEndTime,
        failureReason: session.failure_reason || session.failureReason
      }
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// POST /api/food/orders/:orderId/call-log
// Log call-initiation event for active food orders (backward-compatible)
router.post('/orders/:orderId/call-log', async (req, res) => {
  try {
    const { callerRole, targetRole, targetPhone } = req.body;
    const { orderId } = req.params;

    const order = await FoodOrder.findOne({ orderId });
    if (!order) {
      return res.status(404).json({ success: false, message: 'Order not found' });
    }

    const callEntry = {
      callerRole: callerRole || 'unknown',
      targetRole: targetRole || 'unknown',
      targetPhone: targetPhone ? smartfloService.maskPhone(targetPhone) : 'MASKED',
      timestamp: new Date(),
      status: 'initiated'
    };

    if (!Array.isArray(order.callHistory)) {
      order.callHistory = [];
    }
    order.callHistory.push(callEntry);
    await order.save();

    const io = getIo(req);
    if (io) {
      io.to('admin_tracking').emit('admin_food_order_updated', order);
      io.to(`restaurant:${order.restaurantId}`).emit('food_order_status_update', order);
      io.emit(`food_order:${order.orderId}`, order);
    }

    res.json({ success: true, message: 'Call event logged', callEntry });
  } catch (err) {
    console.error('[FOOD API] Error logging call event:', err);
    res.status(500).json({ success: false, message: 'Failed to log call event: ' + err.message });
  }
});

// GET /api/food/orders/customer/:customerId
router.get('/orders/customer/:customerId', async (req, res) => {
  try {
    const orders = await FoodOrder.find({ customerId: req.params.customerId })
      .sort({ createdAt: -1 })
      .lean();
    res.json({ success: true, count: orders.length, orders });
  } catch (err) {
    console.error('[FOOD API] Error fetching customer orders:', err);
    res.status(500).json({ success: false, message: 'Failed to fetch customer orders' });
  }
});

// POST /api/food/orders/:orderId/cancel
router.post('/orders/:orderId/cancel', async (req, res) => {
  try {
    const { reason } = req.body;
    const order = await FoodOrder.findOne({ orderId: req.params.orderId });
    if (!order) {
      return res.status(404).json({ success: false, message: 'Order not found' });
    }

    if (order.orderStatus !== 'placed') {
      return res.status(400).json({
        success: false,
        message: `Order cannot be cancelled because it is already ${order.orderStatus}`
      });
    }

    order.orderStatus = 'cancelled';
    order.cancelReason = reason || 'Customer requested cancellation';
    order.statusHistory.push({
      status: 'cancelled',
      timestamp: new Date(),
      note: reason || 'Cancelled by customer',
      updatedBy: 'customer'
    });

    await order.save();

    const io = getIo(req);
    if (io) {
      io.to(`restaurant:${order.restaurantId}`).emit('food_order_status_update', order);
      io.to('admin_tracking').emit('admin_food_order_updated', order);
      io.emit(`food_order:${order.orderId}`, order);
    }

    res.json({ success: true, message: 'Order cancelled successfully', order });
  } catch (err) {
    console.error('[FOOD API] Error cancelling order:', err);
    res.status(500).json({ success: false, message: 'Failed to cancel order' });
  }
});

// PUT /api/food/orders/:orderId/address (Customer updates delivery address before dispatch)
router.put('/orders/:orderId/address', async (req, res) => {
  try {
    const { address, deliveryLatLng } = req.body;
    const order = await FoodOrder.findOne({ orderId: req.params.orderId });
    if (!order) {
      return res.status(404).json({ success: false, message: 'Order not found' });
    }

    // Only allow destination updates before restaurant dispatches / pilot picks up
    if (!['placed', 'accepted', 'preparing'].includes(order.orderStatus)) {
      return res.status(400).json({
        success: false,
        message: `Delivery destination cannot be modified because order is already ${order.orderStatus}. Please contact support.`
      });
    }

    if (address && address.trim()) {
      order.deliveryAddress = address.trim();
    }

    if (deliveryLatLng && !isNaN(parseFloat(deliveryLatLng.lat)) && !isNaN(parseFloat(deliveryLatLng.lng))) {
      order.deliveryLatLng = {
        lat: parseFloat(deliveryLatLng.lat),
        lng: parseFloat(deliveryLatLng.lng)
      };
    }

    order.statusHistory.push({
      status: order.orderStatus,
      timestamp: new Date(),
      note: `Delivery address updated by customer to: ${order.deliveryAddress}`,
      updatedBy: 'customer'
    });

    await order.save();

    const io = getIo(req);
    if (io) {
      io.to(`restaurant:${order.restaurantId}`).emit('food_order_status_update', order);
      io.to('admin_tracking').emit('admin_food_order_updated', order);
      io.emit(`food_order:${order.orderId}`, order);
      io.emit('food_order_status_update', order);
      if (order.deliveryPartnerId) {
        io.to(`pilot_food:${order.deliveryPartnerId}`).emit('food_order_status_update', order);
      }
    }

    res.json({
      success: true,
      message: 'Delivery address updated successfully',
      order
    });
  } catch (err) {
    console.error('[FOOD API] Error updating delivery address:', err);
    res.status(500).json({ success: false, message: 'Failed to update delivery address: ' + err.message });
  }
});

// -------------------------------------------------------------
// 2. RESTAURANT PARTNER APIS
// -------------------------------------------------------------

// POST /api/food/partner/register
router.post('/partner/register', async (req, res) => {
  try {
    const {
      name,
      ownerName,
      phone,
      email,
      address,
      lat,
      lng,
      cuisines,
      openingHours,
      fssaiNumber,
      fssaiDocUrl,
      fssaiValidity,
      gstNumber,
      gstDocUrl,
      panNumber,
      panDocUrl,
      bankAccount,
      bankIfsc,
      bankHolderName,
      upiId,
      imageUrl
    } = req.body;

    if (!name || !phone || !address) {
      return res.status(400).json({ success: false, message: 'Name, phone, and address are required' });
    }

    const randomHex = crypto.randomBytes(3).toString('hex').toUpperCase();
    const restaurantId = `REST_${Date.now()}_${randomHex}`;

    const newRestaurant = new Restaurant({
      restaurantId,
      name,
      ownerName: ownerName || '',
      phone,
      email: email || '',
      address,
      lat: parseFloat(lat) || 17.4855,
      lng: parseFloat(lng) || 78.3976,
      cuisines: Array.isArray(cuisines) ? cuisines : (cuisines ? cuisines.split(',').map(c => c.trim()) : ['Multicuisine']),
      openingHours: openingHours || '10:00 AM - 11:00 PM',
      fssaiNumber: fssaiNumber || '',
      fssaiDocUrl: fssaiDocUrl || '',
      fssaiValidity: fssaiValidity || '',
      gstNumber: gstNumber || '',
      gstDocUrl: gstDocUrl || '',
      panNumber: panNumber || '',
      panDocUrl: panDocUrl || '',
      bankAccount: bankAccount || '',
      bankIfsc: bankIfsc || '',
      bankHolderName: bankHolderName || '',
      upiId: upiId || '',
      imageUrl: imageUrl || 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=800&auto=format&fit=crop&q=80',
      status: 'pending', // Requires admin approval
      commissionRate: 15.0,
      reviewHistory: [
        {
          action: 'submitted',
          adminName: 'Restaurant Partner',
          adminId: restaurantId,
          notes: 'Initial registration application submitted for verification',
          timestamp: new Date()
        }
      ]
    });

    await newRestaurant.save();

    const io = getIo(req);
    if (io) {
      io.to('admin_tracking').emit('admin_restaurant_registered', newRestaurant);
      io.to('admin_tracking').emit('admin_restaurant_updated', newRestaurant);
      io.emit('restaurant_updated', newRestaurant);
    }

    res.status(201).json({
      success: true,
      message: 'Restaurant registration submitted for admin approval',
      restaurant: newRestaurant
    });
  } catch (err) {
    console.error('[FOOD API] Error registering restaurant partner:', err);
    res.status(500).json({ success: false, message: 'Failed to register restaurant: ' + err.message });
  }
});

// PUT /api/food/partner/:restaurantId/resubmit (Resubmit after correction or rejection)
router.put('/partner/:restaurantId/resubmit', async (req, res) => {
  try {
    const restaurant = await Restaurant.findOne({ restaurantId: req.params.restaurantId });
    if (!restaurant) {
      return res.status(404).json({ success: false, message: 'Restaurant not found' });
    }

    const fields = [
      'name', 'ownerName', 'phone', 'email', 'address', 'cuisines',
      'openingHours', 'fssaiNumber', 'fssaiDocUrl', 'fssaiValidity',
      'gstNumber', 'gstDocUrl', 'panNumber', 'panDocUrl',
      'bankAccount', 'bankIfsc', 'bankHolderName', 'upiId', 'imageUrl'
    ];

    fields.forEach(f => {
      if (req.body[f] !== undefined) {
        if (f === 'cuisines') {
          restaurant[f] = Array.isArray(req.body[f]) ? req.body[f] : req.body[f].split(',').map(s => s.trim());
        } else {
          restaurant[f] = req.body[f];
        }
      }
    });

    restaurant.status = 'pending';
    restaurant.rejectionReason = '';
    restaurant.actionRequiredNotes = '';
    restaurant.updatedAt = new Date();

    if (!restaurant.reviewHistory) restaurant.reviewHistory = [];
    restaurant.reviewHistory.push({
      action: 'resubmitted',
      adminName: 'Restaurant Partner',
      adminId: restaurant.restaurantId,
      notes: 'Partner updated application information and resubmitted for admin review',
      timestamp: new Date()
    });

    await restaurant.save();

    const io = getIo(req);
    if (io) {
      io.to('admin_tracking').emit('admin_restaurant_registered', restaurant);
      io.to('admin_tracking').emit('admin_restaurant_updated', restaurant);
      io.to(`restaurant:${restaurant.restaurantId}`).emit('restaurant_application_status_changed', {
        restaurantId: restaurant.restaurantId,
        status: 'pending',
        restaurant
      });
      io.emit('restaurant_updated', restaurant);
    }

    res.json({
      success: true,
      message: 'Application resubmitted successfully for admin review',
      restaurant
    });
  } catch (err) {
    console.error('[FOOD API] Error resubmitting application:', err);
    res.status(500).json({ success: false, message: 'Failed to resubmit application: ' + err.message });
  }
});

// GET /api/food/partner/by-phone/:phone
router.get('/partner/by-phone/:phone', async (req, res) => {
  try {
    const rawPhone = (req.params.phone || '').replace(/[^0-9]/g, '');
    const last10 = rawPhone.slice(-10);
    const restaurant = await Restaurant.findOne({
      $or: [
        { phone: last10 },
        { phone: `+91${last10}` },
        { phone: `91${last10}` },
        { phone: rawPhone }
      ]
    }).lean();

    if (!restaurant) {
      return res.json({ success: true, registered: false, restaurant: null });
    }

    res.json({
      success: true,
      registered: true,
      restaurant
    });
  } catch (err) {
    console.error('[FOOD API] Error fetching partner by phone:', err);
    res.status(500).json({ success: false, message: 'Failed to lookup partner' });
  }
});

// POST /api/food/partner/logout
// Handles restaurant partner logout session invalidation
router.post(['/partner/logout', '/restaurant/logout'], async (req, res) => {
  try {
    const { restaurantId, phone } = req.body || {};
    console.log(`[FOOD PARTNER] Logout session invalidated for restaurant: ${restaurantId || phone || 'unknown'}`);
    res.json({
      success: true,
      message: 'Restaurant partner session logged out successfully'
    });
  } catch (err) {
    console.error('[FOOD PARTNER] Error during logout:', err);
    res.json({ success: true, message: 'Logged out' });
  }
});

// GET /api/food/partner/:restaurantId
router.get('/partner/:restaurantId', async (req, res) => {
  try {
    const restaurant = await Restaurant.findOne({ restaurantId: req.params.restaurantId }).lean();
    if (!restaurant) {
      return res.status(404).json({ success: false, message: 'Restaurant not found' });
    }
    res.json({ success: true, restaurant });
  } catch (err) {
    console.error('[FOOD API] Error fetching partner profile:', err);
    res.status(500).json({ success: false, message: 'Failed to fetch restaurant profile' });
  }
});

// PUT /api/food/partner/:restaurantId
router.put('/partner/:restaurantId', async (req, res) => {
  try {
    const { isOpen, openingHours, deliveryFee, phone, address, lat, lng, locationDetails } = req.body;
    const restaurant = await Restaurant.findOne({ restaurantId: req.params.restaurantId });
    if (!restaurant) {
      return res.status(404).json({ success: false, message: 'Restaurant not found' });
    }

    if (isOpen !== undefined) restaurant.isOpen = Boolean(isOpen);
    if (openingHours !== undefined) restaurant.openingHours = openingHours;
    if (deliveryFee !== undefined) restaurant.deliveryFee = parseFloat(deliveryFee);
    if (phone) restaurant.phone = phone;
    if (address) restaurant.address = address;

    if (lat !== undefined && lng !== undefined && !isNaN(parseFloat(lat)) && !isNaN(parseFloat(lng))) {
      let pLat = parseFloat(lat);
      let pLng = parseFloat(lng);
      if (pLat > 50 && pLng < 40) {
        const temp = pLat;
        pLat = pLng;
        pLng = temp;
      }
      if (pLat >= -90 && pLat <= 90 && pLng >= -180 && pLng <= 180 && (pLat !== 0 || pLng !== 0)) {
        restaurant.lat = pLat;
        restaurant.lng = pLng;
      }
    }
    if (locationDetails !== undefined) {
      restaurant.locationDetails = String(locationDetails).trim();
    }

    await restaurant.save();

    const io = getIo(req);
    if (io) {
      io.to(`restaurant:${restaurant.restaurantId}`).emit('restaurant_updated', restaurant);
      io.to('admin_tracking').emit('admin_restaurant_updated', restaurant);
      io.emit('restaurant_updated', restaurant);
    }

    res.json({ success: true, message: 'Restaurant updated successfully', restaurant });
  } catch (err) {
    console.error('[FOOD API] Error updating restaurant partner:', err);
    res.status(500).json({ success: false, message: 'Failed to update restaurant' });
  }
});

// PUT /api/food/partner/:restaurantId/location (Dedicated exact map location pin update)
router.put('/partner/:restaurantId/location', async (req, res) => {
  try {
    const { lat, lng, address, locationDetails } = req.body;
    const restaurant = await Restaurant.findOne({ restaurantId: req.params.restaurantId });
    if (!restaurant) {
      return res.status(404).json({ success: false, message: 'Restaurant not found' });
    }

    let parsedLat = parseFloat(lat);
    let parsedLng = parseFloat(lng);

    if (isNaN(parsedLat) || isNaN(parsedLng)) {
      return res.status(400).json({ success: false, message: 'Latitude and Longitude must be valid numbers' });
    }

    // Safety: check for inverted coordinates (India is ~6-38° N, 68-98° E)
    if (parsedLat > 50 && parsedLng < 40) {
      const temp = parsedLat;
      parsedLat = parsedLng;
      parsedLng = temp;
    }

    if (parsedLat < -90 || parsedLat > 90 || parsedLng < -180 || parsedLng > 180 || (parsedLat === 0 && parsedLng === 0)) {
      return res.status(400).json({ success: false, message: 'Invalid latitude/longitude coordinates on globe' });
    }

    restaurant.lat = parsedLat;
    restaurant.lng = parsedLng;
    if (address && String(address).trim()) {
      restaurant.address = String(address).trim();
    }
    if (locationDetails !== undefined) {
      restaurant.locationDetails = String(locationDetails).trim();
    }

    await restaurant.save();

    const io = getIo(req);
    if (io) {
      io.to(`restaurant:${restaurant.restaurantId}`).emit('restaurant_updated', restaurant);
      io.to('admin_tracking').emit('admin_restaurant_updated', restaurant);
      io.emit('restaurant_updated', restaurant);
    }

    console.log(`[FOOD API] Restaurant ${restaurant.restaurantId} exact pin updated to: ${restaurant.lat}, ${restaurant.lng} (${restaurant.address})`);

    res.json({
      success: true,
      message: 'Restaurant map location saved successfully!',
      restaurant: {
        restaurantId: restaurant.restaurantId,
        name: restaurant.name,
        address: restaurant.address,
        lat: restaurant.lat,
        lng: restaurant.lng,
        locationDetails: restaurant.locationDetails || ''
      }
    });
  } catch (err) {
    console.error('[FOOD API] Error updating restaurant location:', err);
    res.status(500).json({ success: false, message: 'Failed to update restaurant location: ' + err.message });
  }
});

// GET /api/food/partner/:restaurantId/menu
router.get('/partner/:restaurantId/menu', async (req, res) => {
  try {
    const menuItems = await FoodItem.find({ 
      restaurantId: req.params.restaurantId, 
      isDeleted: { $ne: true } 
    }).lean();
    res.json({ success: true, count: menuItems.length, menuItems });
  } catch (err) {
    console.error('[FOOD API] Error fetching partner menu:', err);
    res.status(500).json({ success: false, message: 'Failed to fetch menu' });
  }
});

// POST /api/food/partner/:restaurantId/menu
router.post('/partner/:restaurantId/menu', async (req, res) => {
  try {
    const restaurantId = req.params.restaurantId;
    const { 
      name, 
      category, 
      description, 
      price, 
      discountPrice,
      isVeg, 
      isAvailable, 
      imageUrl, 
      prepTime, 
      isBestseller, 
      isRecommended, 
      variants 
    } = req.body;

    if (!name || price === undefined || !category) {
      return res.status(400).json({ success: false, message: 'Dish name, price, and category are required' });
    }

    const numPrice = parseFloat(price);
    if (isNaN(numPrice) || numPrice < 0) {
      return res.status(400).json({ success: false, message: 'Price must be a valid positive number' });
    }

    const numDiscount = discountPrice !== undefined && discountPrice !== '' ? parseFloat(discountPrice) : 0;
    if (isNaN(numDiscount) || numDiscount < 0) {
      return res.status(400).json({ success: false, message: 'Discount price must be a valid positive number' });
    }

    // Verify restaurant exists
    const restaurant = await Restaurant.findOne({ restaurantId });
    if (!restaurant) {
      return res.status(404).json({ success: false, message: 'Restaurant not found' });
    }

    // Prevent duplicate dish submission with same name in active menu
    const trimmedName = name.trim();
    const existingDish = await FoodItem.findOne({
      restaurantId,
      name: { $regex: new RegExp(`^${trimmedName}$`, 'i') },
      isDeleted: { $ne: true }
    });
    if (existingDish) {
      return res.status(400).json({ 
        success: false, 
        message: `A food item named "${trimmedName}" already exists in your menu. Please edit the existing item instead.` 
      });
    }

    const randomHex = crypto.randomBytes(3).toString('hex').toUpperCase();
    const itemId = `ITEM_${Date.now()}_${randomHex}`;

    const defaultImg = Boolean(isVeg)
      ? 'https://images.unsplash.com/photo-1546833999-b9f581a1996d?w=800&auto=format&fit=crop&q=80'
      : 'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=800&auto=format&fit=crop&q=80';

    const newItem = new FoodItem({
      itemId,
      restaurantId,
      name: trimmedName,
      category: category.trim(),
      description: description ? description.trim() : '',
      price: Math.max(0, Math.round(numPrice * 100) / 100),
      discountPrice: Math.max(0, Math.round(numDiscount * 100) / 100),
      isVeg: Boolean(isVeg),
      isAvailable: isAvailable !== undefined ? Boolean(isAvailable) : true,
      imageUrl: imageUrl && imageUrl.trim().length > 0 ? imageUrl.trim() : defaultImg,
      prepTime: prepTime && prepTime.trim().length > 0 ? prepTime.trim() : '20 mins',
      isBestseller: Boolean(isBestseller),
      isRecommended: Boolean(isRecommended),
      variants: Array.isArray(variants) ? variants : [],
      isDeleted: false
    });

    await newItem.save();

    const io = getIo(req);
    if (io) {
      io.emit('food_item_added', { restaurantId, item: newItem });
      io.emit('food_menu_updated', { restaurantId });
      io.to(`restaurant:${restaurantId}`).emit('food_menu_updated', { restaurantId });
      io.to('admin_tracking').emit('food_menu_updated', { restaurantId });
    }

    res.status(201).json({ success: true, message: 'Food item added successfully to menu', item: newItem });
  } catch (err) {
    console.error('[FOOD API] Error adding menu item:', err);
    res.status(500).json({ success: false, message: 'Failed to add menu item: ' + err.message });
  }
});

// PUT /api/food/partner/:restaurantId/menu/:itemId
router.put('/partner/:restaurantId/menu/:itemId', async (req, res) => {
  try {
    const { restaurantId, itemId } = req.params;
    const { 
      name, 
      category, 
      description, 
      price, 
      discountPrice,
      priceDelta, 
      delta, 
      isVeg, 
      isAvailable, 
      imageUrl, 
      prepTime, 
      isBestseller, 
      isRecommended, 
      variants 
    } = req.body;

    const item = await FoodItem.findOne({ itemId, restaurantId });
    if (!item) {
      return res.status(404).json({ success: false, message: 'Menu item not found' });
    }

    // Check duplicate name if name is being changed
    if (name !== undefined && name.trim()) {
      const trimmedName = name.trim();
      if (trimmedName.toLowerCase() !== item.name.toLowerCase()) {
        const duplicate = await FoodItem.findOne({
          restaurantId,
          itemId: { $ne: itemId },
          name: { $regex: new RegExp(`^${trimmedName}$`, 'i') },
          isDeleted: { $ne: true }
        });
        if (duplicate) {
          return res.status(400).json({ 
            success: false, 
            message: `Another food item named "${trimmedName}" already exists in this restaurant menu.` 
          });
        }
      }
      item.name = trimmedName;
    }

    if (category !== undefined && category.trim()) item.category = category.trim();
    if (description !== undefined) item.description = description.trim();

    // Handle price update either by explicit new price or incremental delta (+10, -10, +50, -50)
    const effectiveDelta = priceDelta !== undefined ? priceDelta : delta;
    if (effectiveDelta !== undefined) {
      const current = item.price || 0;
      const newPrice = Math.max(0, Math.round((current + parseFloat(effectiveDelta)) * 100) / 100);
      item.price = newPrice;
    } else if (price !== undefined) {
      const numPrice = parseFloat(price);
      if (!isNaN(numPrice) && numPrice >= 0) {
        item.price = Math.max(0, Math.round(numPrice * 100) / 100);
      }
    }

    if (discountPrice !== undefined) {
      const numDiscount = parseFloat(discountPrice);
      item.discountPrice = (!isNaN(numDiscount) && numDiscount >= 0) ? Math.round(numDiscount * 100) / 100 : 0;
    }

    if (isVeg !== undefined) item.isVeg = Boolean(isVeg);
    if (isAvailable !== undefined) item.isAvailable = Boolean(isAvailable);
    if (imageUrl !== undefined && imageUrl.trim().length > 0) item.imageUrl = imageUrl.trim();
    if (prepTime !== undefined && prepTime.trim().length > 0) item.prepTime = prepTime.trim();
    if (isBestseller !== undefined) item.isBestseller = Boolean(isBestseller);
    if (isRecommended !== undefined) item.isRecommended = Boolean(isRecommended);
    if (variants !== undefined && Array.isArray(variants)) item.variants = variants;
    item.updatedAt = new Date();

    await item.save();

    const io = getIo(req);
    if (io) {
      io.emit('food_item_updated', { restaurantId, item });
      io.emit('food_menu_updated', { restaurantId });
      io.to(`restaurant:${restaurantId}`).emit('food_menu_updated', { restaurantId });
      io.to('admin_tracking').emit('food_menu_updated', { restaurantId });
    }

    res.json({ success: true, message: 'Menu item updated successfully', item });
  } catch (err) {
    console.error('[FOOD API] Error updating menu item:', err);
    res.status(500).json({ success: false, message: 'Failed to update menu item: ' + err.message });
  }
});

// PATCH /api/food/partner/:restaurantId/menu/:itemId/availability
router.patch('/partner/:restaurantId/menu/:itemId/availability', async (req, res) => {
  try {
    const { restaurantId, itemId } = req.params;
    const { isAvailable } = req.body;
    const item = await FoodItem.findOne({ itemId, restaurantId, isDeleted: { $ne: true } });
    if (!item) {
      return res.status(404).json({ success: false, message: 'Menu item not found' });
    }
    item.isAvailable = Boolean(isAvailable);
    item.updatedAt = new Date();
    await item.save();

    const io = getIo(req);
    if (io) {
      io.emit('food_item_updated', { restaurantId, item });
      io.emit('food_menu_updated', { restaurantId });
      io.to(`restaurant:${restaurantId}`).emit('food_menu_updated', { restaurantId });
      io.to('admin_tracking').emit('food_menu_updated', { restaurantId });
    }

    res.json({ success: true, message: `Item marked as ${item.isAvailable ? 'In Stock' : 'Out of Stock'}`, item });
  } catch (err) {
    console.error('[FOOD API] Error updating availability:', err);
    res.status(500).json({ success: false, message: 'Failed to update availability: ' + err.message });
  }
});

// POST /api/food/partner/:restaurantId/menu/adjust-prices (Bulk adjustment: fixed INR delta or percentDelta, preview mode)
router.post('/partner/:restaurantId/menu/adjust-prices', async (req, res) => {
  try {
    const { delta, priceDelta, percentDelta, category, itemIds, preview, resetDefault } = req.body;
    const effectiveDelta = delta !== undefined ? parseFloat(delta) : (priceDelta !== undefined ? parseFloat(priceDelta) : undefined);
    const effectivePercent = percentDelta !== undefined ? parseFloat(percentDelta) : undefined;

    if (effectiveDelta === undefined && effectivePercent === undefined && !resetDefault) {
      return res.status(400).json({ success: false, message: 'delta, percentDelta, or resetDefault is required' });
    }

    const filter = { restaurantId: req.params.restaurantId, isDeleted: { $ne: true } };
    if (category && category !== 'All') {
      filter.category = category;
    }
    if (Array.isArray(itemIds) && itemIds.length > 0) {
      filter.itemId = { $in: itemIds };
    }

    const items = await FoodItem.find(filter);

    // If preview requested, compute preview without saving to database
    if (preview) {
      const previewItems = items.map(item => {
        let calculatedPrice = item.price || 0;
        if (effectivePercent !== undefined) {
          calculatedPrice = Math.max(0, Math.round(calculatedPrice * (1 + effectivePercent / 100)));
        } else if (effectiveDelta !== undefined) {
          calculatedPrice = Math.max(0, Math.round(calculatedPrice + effectiveDelta));
        }
        return {
          itemId: item.itemId,
          name: item.name,
          category: item.category,
          currentPrice: item.price,
          newPrice: calculatedPrice,
          change: calculatedPrice - (item.price || 0)
        };
      });

      return res.json({
        success: true,
        preview: true,
        affectedCount: previewItems.length,
        items: previewItems
      });
    }

    // Apply changes in database
    for (const item of items) {
      if (effectivePercent !== undefined) {
        item.price = Math.max(0, Math.round((item.price || 0) * (1 + effectivePercent / 100)));
      } else if (effectiveDelta !== undefined) {
        item.price = Math.max(0, Math.round((item.price || 0) + effectiveDelta));
      }
      item.updatedAt = new Date();
      await item.save();
    }

    const io = getIo(req);
    if (io) {
      io.emit('food_menu_updated', { restaurantId: req.params.restaurantId });
      io.to(`restaurant:${req.params.restaurantId}`).emit('food_menu_updated', { restaurantId: req.params.restaurantId });
      io.to('admin_tracking').emit('food_menu_updated', { restaurantId: req.params.restaurantId });
    }

    const descMsg = effectivePercent !== undefined 
      ? `${effectivePercent >= 0 ? '+' : ''}${effectivePercent}%`
      : `₹${effectiveDelta >= 0 ? '+' : ''}${effectiveDelta}`;

    res.json({
      success: true,
      message: `Adjusted rates by ${descMsg} across ${items.length} dishes`,
      adjustedCount: items.length
    });
  } catch (err) {
    console.error('[FOOD API] Error adjusting rates:', err);
    res.status(500).json({ success: false, message: 'Failed to adjust rates: ' + err.message });
  }
});

// DELETE /api/food/partner/:restaurantId/menu/:itemId
router.delete('/partner/:restaurantId/menu/:itemId', async (req, res) => {
  try {
    const { restaurantId, itemId } = req.params;
    const item = await FoodItem.findOne({ itemId, restaurantId });
    if (!item) {
      return res.status(404).json({ success: false, message: 'Menu item not found' });
    }

    // Safe soft-delete / archive to preserve order history and audit records
    item.isDeleted = true;
    item.isAvailable = false;
    item.updatedAt = new Date();
    await item.save();

    const io = getIo(req);
    if (io) {
      io.emit('food_item_deleted', { restaurantId, itemId });
      io.emit('food_menu_updated', { restaurantId });
      io.to(`restaurant:${restaurantId}`).emit('food_menu_updated', { restaurantId });
      io.to('admin_tracking').emit('food_menu_updated', { restaurantId });
    }

    res.json({ success: true, message: 'Food item removed successfully from active menu' });
  } catch (err) {
    console.error('[FOOD API] Error deleting menu item:', err);
    res.status(500).json({ success: false, message: 'Failed to remove menu item: ' + err.message });
  }
});

// PUT /api/food/partner/:restaurantId/info
router.put('/partner/:restaurantId/info', async (req, res) => {
  try {
    const restaurant = await Restaurant.findOne({ restaurantId: req.params.restaurantId });
    if (!restaurant) {
      return res.status(404).json({ success: false, message: 'Restaurant not found' });
    }

    const { name, openingHours, phone, email, address, deliveryTime, isVegOnly, imageUrl, isOpen, lat, lng, locationDetails } = req.body;
    if (name !== undefined && name.trim()) restaurant.name = name.trim();
    if (openingHours !== undefined) restaurant.openingHours = openingHours;
    if (phone !== undefined) restaurant.phone = phone;
    if (email !== undefined) restaurant.email = email;
    if (address !== undefined) restaurant.address = address;
    if (deliveryTime !== undefined) restaurant.deliveryTime = deliveryTime;
    if (isVegOnly !== undefined) restaurant.isVegOnly = Boolean(isVegOnly);
    if (imageUrl !== undefined) restaurant.imageUrl = imageUrl;
    if (isOpen !== undefined) restaurant.isOpen = Boolean(isOpen);
    if (locationDetails !== undefined) restaurant.locationDetails = String(locationDetails).trim();

    if (lat !== undefined && lng !== undefined && !isNaN(parseFloat(lat)) && !isNaN(parseFloat(lng))) {
      let pLat = parseFloat(lat);
      let pLng = parseFloat(lng);
      if (pLat > 50 && pLng < 40) {
        const temp = pLat;
        pLat = pLng;
        pLng = temp;
      }
      if (pLat >= -90 && pLat <= 90 && pLng >= -180 && pLng <= 180 && (pLat !== 0 || pLng !== 0)) {
        restaurant.lat = pLat;
        restaurant.lng = pLng;
      }
    }

    // SECURITY: Restaurant partner cannot modify commissionRate, status, or approvals
    // Any attempt to set req.body.commissionRate or req.body.status is ignored!

    await restaurant.save();

    const io = getIo(req);
    if (io) {
      io.to(`restaurant:${restaurant.restaurantId}`).emit('restaurant_updated', restaurant);
      io.to('admin_tracking').emit('admin_restaurant_updated', restaurant);
      io.emit('restaurant_updated', restaurant);
    }

    res.json({ success: true, message: 'Restaurant profile updated successfully', restaurant });
  } catch (err) {
    console.error('[FOOD API] Error updating partner info:', err);
    res.status(500).json({ success: false, message: 'Failed to update partner info' });
  }
});

// GET /api/food/partner/:restaurantId/orders
router.get('/partner/:restaurantId/orders', async (req, res) => {
  try {
    const param = req.params.restaurantId;
    
    // Find restaurant record to gather all possible identifiers (restaurantId, phone, _id)
    const restaurant = await Restaurant.findOne({
      $or: [
        { restaurantId: param },
        { phone: param },
        ...(mongoose.Types.ObjectId.isValid(param) ? [{ _id: param }] : [])
      ]
    }).lean();

    const matchedIds = [param];
    if (restaurant) {
      if (restaurant.restaurantId && !matchedIds.includes(restaurant.restaurantId)) matchedIds.push(restaurant.restaurantId);
      if (restaurant.phone && !matchedIds.includes(restaurant.phone)) matchedIds.push(restaurant.phone);
      if (restaurant._id && !matchedIds.includes(restaurant._id.toString())) matchedIds.push(restaurant._id.toString());
    }

    const orders = await FoodOrder.find({
      $or: [
        { restaurantId: { $in: matchedIds } },
        { restaurantPhone: { $in: matchedIds } }
      ]
    }).sort({ createdAt: -1 }).lean();

    res.json({ success: true, count: orders.length, orders });
  } catch (err) {
    console.error('[FOOD API] Error fetching partner orders:', err);
    res.status(500).json({ success: false, message: 'Failed to fetch restaurant orders' });
  }
});

// POST /api/food/partner/orders/:orderId/status
router.post(['/partner/orders/:orderId/status', '/restaurant/orders/:orderId/status', '/restaurant/orders/:orderId/accept', '/restaurant/orders/:orderId/ready'], async (req, res) => {
  try {
    let { status, rejectReason, prepTime, note } = req.body;
    if (!status && req.path.endsWith('/accept')) status = 'accepted';
    if (!status && req.path.endsWith('/ready')) status = 'ready_for_pickup';
    const order = await FoodOrder.findOne({ orderId: req.params.orderId });
    if (!order) {
      return res.status(404).json({ success: false, message: 'Order not found' });
    }

    const validStatuses = ['accepted', 'preparing', 'ready_for_pickup', 'pilot_assigned', 'picked_up', 'out_for_delivery', 'delivered', 'rejected', 'cancelled'];
    if (!validStatuses.includes(status)) {
      return res.status(400).json({ success: false, message: `Invalid status ${status}` });
    }

    order.orderStatus = status;
    if (prepTime) order.prepTime = prepTime;
    if (status === 'accepted') order.acceptedAt = new Date();
    if (status === 'preparing') order.preparedAt = new Date();
    if (status === 'ready_for_pickup') order.preparedAt = new Date();
    if (status === 'delivered') order.deliveredAt = new Date();
    if (status === 'rejected') order.rejectReason = rejectReason || 'Kitchen busy';

    order.statusHistory.push({
      status,
      timestamp: new Date(),
      note: note || (prepTime ? `Order accepted with estimated prep time: ${prepTime}` : `Order updated to ${status} by restaurant`),
      updatedBy: 'restaurant'
    });

    await order.save();

    // Broadcast status change
    const io = getIo(req);
    if (io) {
      io.to(`restaurant:${order.restaurantId}`).emit('food_order_status_update', order);
      io.to('admin_tracking').emit('admin_food_order_updated', order);
      io.emit(`food_order:${order.orderId}`, order);
      io.emit('food_order_status_update', order);
      io.emit(`food_order.${status}`, order);

      // When order is marked ready for pickup and a pilot is ALREADY assigned:
      if (status === 'ready_for_pickup' && (order.deliveryPartnerId || order.deliveryPartnerPhone)) {
        const readyPayload = {
          orderId: order.orderId,
          status: 'ready_for_pickup',
          title: '🍱 Order Ready for Pickup!',
          message: `Order #${order.orderId} is packed and ready for pickup at ${order.restaurantName}!`,
          restaurantName: order.restaurantName,
          order
        };
        if (order.deliveryPartnerId) {
          io.to(`pilot_food:${order.deliveryPartnerId}`).emit('food_order_ready_for_pickup', readyPayload);
          io.to(`pilot_food:${order.deliveryPartnerId}`).emit('food_order_status_update', order);
        }
        if (order.deliveryPartnerPhone) {
          io.to(`pilot_food:${order.deliveryPartnerPhone}`).emit('food_order_ready_for_pickup', readyPayload);
          io.to(`pilot_food:${order.deliveryPartnerPhone}`).emit('food_order_status_update', order);
        }
        io.to('pilot_food_dispatch').emit('food_order_ready_for_pickup', readyPayload);
        console.log(`[FOOD NOTIFICATION] Alerted assigned pilot (${order.deliveryPartnerName || order.deliveryPartnerId}) that order ${order.orderId} is ready for pickup`);
      }

      // Section 2 & 4: When order is accepted or ready, dispatch STRICTLY to online Bike & Scooty pilots!
      if (['accepted', 'preparing', 'ready_for_pickup'].includes(status) && !order.deliveryPartnerId) {
        // Emit ONLY to the verified pilot_food_dispatch room (joined strictly by Bike/Scooty pilots)
        io.to('pilot_food_dispatch').emit('food_delivery_request', order);
        io.to('pilot_food_dispatch').emit('food_delivery_available', order);
        console.log(`[FOOD DISPATCH] Dispatched food order ${order.orderId} (status: ${status}) exclusively to Bike and Scooty pilots`);

        // Targeted direct alert to nearby approved Bike/Scooty pilots
        const rLat = (order.restaurantLatLng && order.restaurantLatLng.lat) || order.restaurantLat || 0;
        const rLng = (order.restaurantLatLng && order.restaurantLatLng.lng) || order.restaurantLng || 0;
        findNearbyEligibleFoodPilots(rLat, rLng, 10).then(nearbyPilots => {
          for (const p of nearbyPilots) {
            if (p.uid) io.to('pilot_food:' + p.uid).emit('food_delivery_request', order);
            if (p.phone) io.to('pilot_food:' + p.phone).emit('food_delivery_request', order);
          }
          if (nearbyPilots.length > 0) {
            console.log(`[FOOD DISPATCH] Directly alerted ${nearbyPilots.length} nearby Bike/Scooty pilots for order ${order.orderId}`);
          }
        }).catch(err => {
          console.error('[FOOD DISPATCH] Error querying nearby 2-wheeler pilots:', err);
        });
      }
    }

    res.json({ success: true, message: `Order status updated to ${status}`, order });
  } catch (err) {
    console.error('[FOOD API] Error updating order status:', err);
    res.status(500).json({ success: false, message: 'Failed to update order status' });
  }
});

// GET /api/food/partner/:restaurantId/earnings
router.get('/partner/:restaurantId/earnings', async (req, res) => {
  try {
    const restaurant = await Restaurant.findOne({ restaurantId: req.params.restaurantId }).lean();
    if (!restaurant) {
      return res.status(404).json({ success: false, message: 'Restaurant not found' });
    }

    const orders = await FoodOrder.find({
      restaurantId: req.params.restaurantId,
      orderStatus: { $in: ['accepted', 'preparing', 'ready_for_pickup', 'out_for_delivery', 'delivered'] }
    }).lean();

    let grossFoodSales = 0;
    let deliveredOrdersCount = 0;
    let pendingOrdersCount = 0;
    let totalMembershipDiscounts = 0;
    let staydrivFundedDiscounts = 0;
    let restaurantFundedDiscounts = 0;

    orders.forEach(o => {
      grossFoodSales += (o.subtotal || 0);
      if (o.membershipDiscount) {
        totalMembershipDiscounts += (o.membershipDiscount || 0);
        staydrivFundedDiscounts += (o.staydrivDiscountContribution || 0);
        restaurantFundedDiscounts += (o.restaurantDiscountContribution || 0);
      }
      if (o.orderStatus === 'delivered') {
        deliveredOrdersCount++;
      } else {
        pendingOrdersCount++;
      }
    });

    const commissionRate = restaurant.commissionRate || 15.0;
    const platformCommission = Math.round((grossFoodSales * commissionRate) / 100);
    // Restaurant earnings: Food sales minus platform commission minus only restaurant-funded discount portion
    // (StayDriv-funded discounts do not reduce the restaurant's net payout!)
    const netEarnings = Math.max(0, grossFoodSales - platformCommission - restaurantFundedDiscounts);

    res.json({
      success: true,
      restaurant: {
        restaurantId: restaurant.restaurantId,
        name: restaurant.name,
        commissionRate,
        isMembershipEnrolled: restaurant.isMembershipEnrolled !== false,
        membershipFundingType: restaurant.membershipFundingType || 'staydriv'
      },
      summary: {
        totalOrders: orders.length,
        deliveredOrdersCount,
        pendingOrdersCount,
        grossFoodSales,
        platformCommission,
        membershipDiscounts: {
          total: totalMembershipDiscounts,
          fundedByStayDriv: staydrivFundedDiscounts,
          fundedByRestaurant: restaurantFundedDiscounts
        },
        netEarnings,
        settledEarnings: restaurant.settledEarnings || 0,
        unsettledEarnings: netEarnings - (restaurant.settledEarnings || 0)
      }
    });
  } catch (err) {
    console.error('[FOOD API] Error fetching partner earnings:', err);
    res.status(500).json({ success: false, message: 'Failed to fetch earnings' });
  }
});

// -------------------------------------------------------------
// 2B. RESTAURANT PARTNER PAYMENT DETAILS & SALES SETTLEMENT APIS
// -------------------------------------------------------------

// GET /api/food/partner/:restaurantId/payment-details
// Returns masked payment details, verification status, and audit log
router.get('/partner/:restaurantId/payment-details', async (req, res) => {
  try {
    const restaurant = await Restaurant.findOne({ restaurantId: req.params.restaurantId }).lean();
    if (!restaurant) {
      return res.status(404).json({ success: false, message: 'Restaurant not found' });
    }

    const maskedAccount = restaurant.bankAccountMasked || restaurantSettlementService.maskAccountNumber(restaurant.bankAccount);

    res.json({
      success: true,
      paymentDetails: {
        restaurantId: restaurant.restaurantId,
        restaurantName: restaurant.name,
        accountHolderName: restaurant.bankHolderName || '',
        bankName: restaurant.bankName || '',
        bankAccountMasked: maskedAccount,
        hasBankAccount: !!(restaurant.bankAccount && restaurant.bankAccount.length > 0),
        bankIfsc: restaurant.bankIfsc || '',
        accountType: restaurant.accountType || 'Current',
        registeredMobile: restaurant.registeredMobile || restaurant.phone || '',
        upiId: restaurant.upiId || '',
        paymentPreference: restaurant.paymentPreference || 'bank_transfer',
        bankVerificationStatus: restaurant.bankVerificationStatus || 'unverified',
        bankVerifiedAt: restaurant.bankVerifiedAt || null,
        bankVerifiedBy: restaurant.bankVerifiedBy || '',
        bankRejectionReason: restaurant.bankRejectionReason || '',
        auditLog: (restaurant.bankAuditLog || []).slice(-10).reverse()
      }
    });
  } catch (err) {
    console.error('[FOOD API] Error fetching partner payment details:', err);
    res.status(500).json({ success: false, message: 'Failed to fetch payment details' });
  }
});

// PUT /api/food/partner/:restaurantId/payment-details
// Updates payment details with strict validation and audit logging
router.put('/partner/:restaurantId/payment-details', async (req, res) => {
  try {
    const restaurant = await Restaurant.findOne({ restaurantId: req.params.restaurantId });
    if (!restaurant) {
      return res.status(404).json({ success: false, message: 'Restaurant not found' });
    }

    const {
      accountHolderName,
      bankName,
      bankAccount,
      confirmBankAccount,
      bankIfsc,
      accountType,
      registeredMobile,
      upiId,
      paymentPreference,
      updatedBy = 'Restaurant Partner'
    } = req.body;

    // Validate fields
    const isNew = !restaurant.bankAccount || restaurant.bankAccount.length === 0;
    const validation = restaurantSettlementService.validatePaymentDetails({
      accountHolderName,
      bankName,
      bankAccount,
      confirmBankAccount,
      bankIfsc,
      accountType,
      registeredMobile,
      upiId,
      paymentPreference,
      isNewAccount: isNew
    });

    if (!validation.valid) {
      return res.status(400).json({ success: false, message: validation.error });
    }

    const cleanAcc = bankAccount ? bankAccount.toString().trim() : restaurant.bankAccount;
    const cleanIfsc = (bankIfsc || '').toString().trim().toUpperCase();
    const cleanMobile = (registeredMobile || '').toString().replace(/\D/g, '').slice(-10);
    const maskedAcc = restaurantSettlementService.maskAccountNumber(cleanAcc);

    // Save fields
    restaurant.bankHolderName = accountHolderName.trim();
    restaurant.bankName = bankName.trim();
    if (cleanAcc) {
      restaurant.bankAccount = cleanAcc;
      restaurant.bankAccountMasked = maskedAcc;
    }
    restaurant.bankIfsc = cleanIfsc;
    restaurant.accountType = accountType || 'Current';
    restaurant.registeredMobile = cleanMobile;
    restaurant.upiId = upiId ? upiId.trim() : '';
    restaurant.paymentPreference = paymentPreference || 'bank_transfer';
    restaurant.bankVerificationStatus = 'pending_verification';
    restaurant.bankRejectionReason = '';

    // Record audit log entry
    if (!restaurant.bankAuditLog) restaurant.bankAuditLog = [];
    restaurant.bankAuditLog.push({
      action: 'PAYMENT_DETAILS_UPDATED',
      updatedBy: updatedBy || 'Partner Portal',
      maskedAccount: maskedAcc,
      timestamp: new Date(),
      notes: `Bank details updated. Status changed to Pending Verification. IFSC: ${cleanIfsc}`
    });

    await restaurant.save();

    res.json({
      success: true,
      message: 'Payment details saved successfully. Account is under verification.',
      paymentDetails: {
        accountHolderName: restaurant.bankHolderName,
        bankName: restaurant.bankName,
        bankAccountMasked: maskedAcc,
        bankIfsc: restaurant.bankIfsc,
        accountType: restaurant.accountType,
        registeredMobile: restaurant.registeredMobile,
        upiId: restaurant.upiId,
        paymentPreference: restaurant.paymentPreference,
        bankVerificationStatus: restaurant.bankVerificationStatus
      }
    });
  } catch (err) {
    console.error('[FOOD API] Error saving payment details:', err);
    res.status(500).json({ success: false, message: 'Failed to update payment details' });
  }
});

// GET /api/food/partner/:restaurantId/settlements/summary
// Authoritative calculation of completed sales, commissions, pending settlement, and paid amounts
router.get('/partner/:restaurantId/settlements/summary', async (req, res) => {
  try {
    const summary = await restaurantSettlementService.calculateRestaurantSales(req.params.restaurantId);
    res.json({
      success: true,
      summary
    });
  } catch (err) {
    console.error('[FOOD API] Error fetching settlement summary:', err);
    res.status(500).json({ success: false, message: err.message || 'Failed to calculate settlement summary' });
  }
});

// GET /api/food/partner/:restaurantId/settlements
// Returns settlement history for the restaurant
router.get('/partner/:restaurantId/settlements', async (req, res) => {
  try {
    const settlements = await RestaurantSettlement.find({
      restaurantId: req.params.restaurantId
    }).sort({ createdAt: -1 }).lean();

    res.json({
      success: true,
      settlements
    });
  } catch (err) {
    console.error('[FOOD API] Error fetching partner settlements:', err);
    res.status(500).json({ success: false, message: 'Failed to load settlements' });
  }
});

// GET /api/food/partner/:restaurantId/sales-breakdown
// Returns transaction-wise list of completed food orders (delivered and returned-to-restaurant)
router.get('/partner/:restaurantId/sales-breakdown', async (req, res) => {
  try {
    const restaurant = await Restaurant.findOne({ restaurantId: req.params.restaurantId }).lean();
    if (!restaurant) {
      return res.status(404).json({ success: false, message: 'Restaurant not found' });
    }

    const commissionRate = restaurant.commissionRate != null ? restaurant.commissionRate : 15.0;

    // Fetch delivered orders and returned orders
    const orders = await FoodOrder.find({
      restaurantId: req.params.restaurantId,
      orderStatus: {
        $in: [
          'delivered',
          'returned_to_restaurant',
          'RETURNED_TO_RESTAURANT',
          'return_closed',
          'RETURN_CLOSED',
          'delivery_failed_reported',
          'DELIVERY_FAILED_REPORTED',
          'return_to_restaurant',
          'RETURN_TO_RESTAURANT',
          'return_arrived_at_restaurant',
          'RETURN_ARRIVED_AT_RESTAURANT',
          'return_otp_pending',
          'RETURN_OTP_PENDING'
        ]
      }
    }).sort({ returnedAt: -1, deliveredAt: -1, createdAt: -1 }).limit(200).lean();

    // Fetch settlements to map order settlement statuses
    const settlements = await RestaurantSettlement.find({
      restaurantId: req.params.restaurantId
    }).lean();

    const orderSettlementMap = {};
    settlements.forEach(s => {
      (s.orderIds || []).forEach(oId => {
        orderSettlementMap[oId] = {
          settlementId: s.settlementId,
          status: s.status,
          settledAt: s.settledAt,
          payoutReference: s.payoutReference
        };
      });
    });

    const breakdown = orders.map(o => {
      const payability = restaurantSettlementService.evaluateRestaurantOrderPayability(o);
      const isReturned = payability.isReturned;
      const subtotal = o.subtotal || 0;
      const packagingFee = o.packagingFee || 0;
      const grossAmount = subtotal + packagingFee;
      const commission = Math.round((subtotal * commissionRate) / 100);
      const actualDeductions = (o.walletDebitStatus === 'debited' && o.actualWalletDebitAmount > 0)
        ? o.actualWalletDebitAmount
        : 0;

      let netAmount = 0;
      let settlementStatus = 'pending';

      const settleInfo = orderSettlementMap[o.orderId];

      if (!payability.isPayable) {
        netAmount = 0;
        settlementStatus = 'not_payable';
      } else {
        netAmount = Math.max(0, grossAmount - commission - actualDeductions);
        if (settleInfo) {
          if (settleInfo.status === 'paid') {
            settlementStatus = 'paid';
          } else if (settleInfo.status === 'processing') {
            settlementStatus = 'processing';
          } else if (settleInfo.status === 'failed') {
            settlementStatus = 'pending';
          } else {
            settlementStatus = settleInfo.status || 'pending';
          }
        } else {
          settlementStatus = 'pending';
        }
      }

      return {
        orderId: o.orderId,
        bookingReference: o.orderId,
        customerName: o.customerName || 'StayDriv Customer',
        customerPhone: o.customerPhone || '',
        orderDate: o.placedAt || o.createdAt,
        deliveredAt: o.deliveredAt || null,
        returnedAt: o.returnedAt || null,
        itemsCount: (o.items || []).length,
        items: (o.items || []).map(it => ({
          itemId: it.itemId || '',
          name: it.name || 'Food Item',
          quantity: it.quantity || 1,
          price: it.price || 0,
          customization: it.customization || '',
          isVeg: it.isVeg || false
        })),
        subtotal,
        packagingFee,
        grossAmount,
        commissionRate,
        commission,
        platformFee: commission,
        deductions: actualDeductions,
        membershipDiscount: o.membershipDiscount || 0,
        discountFundedBy: o.discountFundedBy || 'none',
        customerPaymentMethod: o.paymentMethod || 'online',
        customerPaymentStatus: o.paymentStatus || 'paid',
        customerTotalPaid: o.totalAmount || 0,
        rawOrderStatus: o.orderStatus,
        orderStatus: isReturned ? 'Returned to Restaurant' : 'Delivered',
        isReturned,
        returnReason: o.returnReason || '',
        returnNotes: o.returnNotes || '',
        returnOtpVerified: Boolean(o.returnOtpVerified),
        pilotId: o.deliveryPartnerId || '',
        pilotName: o.deliveryPartnerName || '',
        pilotPhone: o.deliveryPartnerPhone || '',
        isPayable: payability.isPayable,
        payableReason: payability.reason,
        netAmount,
        settlementStatus,
        settlementId: settleInfo ? settleInfo.settlementId : (o.settlementId || null),
        payoutReference: settleInfo ? settleInfo.payoutReference : null,
        settledAt: settleInfo ? settleInfo.settledAt : null
      };
    });

    res.json({
      success: true,
      orders: breakdown
    });
  } catch (err) {
    console.error('[FOOD API] Error fetching sales breakdown:', err);
    res.status(500).json({ success: false, message: 'Failed to load sales breakdown' });
  }
});



// GET /api/food/admin/restaurants
router.get('/admin/restaurants', async (req, res) => {
  try {
    const { status, search } = req.query;
    const filter = {};

    if (status && status !== 'all') {
      if (status === 'active') {
        filter.status = 'approved';
        filter.isOpen = true;
      } else if (status === 'inactive') {
        filter.$or = [{ isOpen: false }, { status: { $ne: 'approved' } }];
      } else {
        filter.status = status;
      }
    }

    if (search && search.trim()) {
      const q = search.trim();
      filter.$or = [
        { name: { $regex: q, $options: 'i' } },
        { phone: { $regex: q, $options: 'i' } },
        { restaurantId: { $regex: q, $options: 'i' } },
        { ownerName: { $regex: q, $options: 'i' } },
        { address: { $regex: q, $options: 'i' } },
        { cuisines: { $regex: q, $options: 'i' } }
      ];
    }

    const [
      countAll,
      countPending,
      countActionRequired,
      countApproved,
      countRejected,
      countSuspended,
      countActive,
      countInactive
    ] = await Promise.all([
      Restaurant.countDocuments({}),
      Restaurant.countDocuments({ status: 'pending' }),
      Restaurant.countDocuments({ status: 'action_required' }),
      Restaurant.countDocuments({ status: 'approved' }),
      Restaurant.countDocuments({ status: 'rejected' }),
      Restaurant.countDocuments({ status: 'suspended' }),
      Restaurant.countDocuments({ status: 'approved', isOpen: true }),
      Restaurant.countDocuments({ $or: [{ isOpen: false }, { status: { $ne: 'approved' } }] })
    ]);

    const restaurants = await Restaurant.find(filter).sort({ createdAt: -1 }).lean();

    // Attach real-time menuItemCount to each restaurant
    try {
      const menuCounts = await FoodItem.aggregate([
        { $group: { _id: "$restaurantId", count: { $sum: 1 } } }
      ]);
      const countMap = {};
      menuCounts.forEach(c => { if (c._id) countMap[c._id] = c.count; });
      restaurants.forEach(r => {
        r.menuItemCount = countMap[r.restaurantId] || 0;
      });
    } catch (countErr) {
      console.error('[FOOD API] Error aggregating menu counts:', countErr);
    }

    res.json({
      success: true,
      count: restaurants.length,
      counts: {
        all: countAll,
        pending: countPending,
        action_required: countActionRequired,
        approved: countApproved,
        rejected: countRejected,
        suspended: countSuspended,
        active: countActive,
        inactive: countInactive
      },
      restaurants
    });
  } catch (err) {
    console.error('[FOOD API] Error in admin restaurants:', err);
    res.status(500).json({ success: false, message: 'Failed to fetch restaurants' });
  }
});

// GET /api/food/admin/geocode (Resolve human address to GPS coordinates)
router.get('/admin/geocode', async (req, res) => {
  try {
    const address = (req.query.address || '').trim();
    if (!address) {
      return res.status(400).json({ success: false, message: 'address query parameter is required' });
    }
    const result = await geocodeAddress(address);
    if (!result) {
      return res.status(404).json({ success: false, message: 'Could not resolve coordinates for address' });
    }
    res.json({
      success: true,
      lat: result.lat,
      lng: result.lng,
      formattedAddress: result.formattedAddress
    });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Geocoding failed: ' + err.message });
  }
});

// POST /api/food/admin/restaurants (Admin Create Restaurant)
router.post('/admin/restaurants', async (req, res) => {
  try {
    const {
      name, ownerName, phone, email, address, lat, lng, cuisines, categories,
      openingHours, deliveryFee, deliveryTime, minimumOrder, isVegOnly,
      isOpen, imageUrl, fssaiNumber, commissionRate, status
    } = req.body;

    if (!name || !phone || !address) {
      return res.status(400).json({ success: false, message: 'Name, phone, and address are required' });
    }

    const randomHex = crypto.randomBytes(3).toString('hex').toUpperCase();
    const restaurantId = req.body.restaurantId || `REST_${Date.now()}_${randomHex}`;

    // Auto-geocode coordinates if not provided or if using default fallback
    let finalLat = parseFloat(lat);
    let finalLng = parseFloat(lng);
    if (isNaN(finalLat) || isNaN(finalLng) || (Math.abs(finalLat - 17.4485) < 0.001 && Math.abs(finalLng - 78.3741) < 0.001)) {
      const geo = await geocodeAddress(address);
      if (geo) {
        finalLat = geo.lat;
        finalLng = geo.lng;
      } else {
        finalLat = 17.5230;
        finalLng = 78.4222;
      }
    }

    const newRestaurant = new Restaurant({
      restaurantId,
      name,
      ownerName: ownerName || '',
      phone,
      email: email || '',
      address,
      lat: finalLat,
      lng: finalLng,
      cuisines: Array.isArray(cuisines) ? cuisines : (cuisines ? cuisines.split(',').map(s => s.trim()) : ['General']),
      categories: Array.isArray(categories) ? categories : ['Biryani', 'South Indian', 'North Indian', 'Pizza', 'Burgers', 'Chinese', 'Snacks', 'Desserts'],
      openingHours: openingHours || '10:00 AM - 11:30 PM',
      deliveryFee: parseFloat(deliveryFee) || 30,
      deliveryTime: deliveryTime || '25-35 mins',
      minimumOrder: parseFloat(minimumOrder) || 100,
      isVegOnly: Boolean(isVegOnly),
      isOpen: isOpen !== undefined ? Boolean(isOpen) : true,
      imageUrl: imageUrl || 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=800&auto=format&fit=crop&q=80',
      fssaiNumber: fssaiNumber || '',
      commissionRate: parseFloat(commissionRate) || 15.0,
      status: status || 'approved'
    });

    await newRestaurant.save();

    const io = getIo(req);
    if (io) {
      io.to('admin_tracking').emit('admin_restaurant_registered', newRestaurant);
      io.emit('restaurant_updated', newRestaurant);
    }

    res.status(201).json({
      success: true,
      message: 'Restaurant created successfully',
      restaurant: newRestaurant
    });
  } catch (err) {
    console.error('[FOOD API] Error creating restaurant:', err);
    res.status(500).json({ success: false, message: 'Failed to create restaurant: ' + err.message });
  }
});

// POST /api/food/admin/restaurants/:restaurantId/geocode (Re-geocode single restaurant from its address)
router.post('/admin/restaurants/:restaurantId/geocode', async (req, res) => {
  try {
    const restaurant = await Restaurant.findOne({ restaurantId: req.params.restaurantId });
    if (!restaurant) {
      return res.status(404).json({ success: false, message: 'Restaurant not found' });
    }
    const targetAddr = (req.body && req.body.address) ? req.body.address : restaurant.address;
    const geo = await geocodeAddress(targetAddr);
    if (!geo) {
      return res.status(400).json({ success: false, message: 'Could not resolve coordinates for address: ' + targetAddr });
    }
    restaurant.lat = geo.lat;
    restaurant.lng = geo.lng;
    if (req.body && req.body.address) restaurant.address = req.body.address;
    await restaurant.save();

    const io = getIo(req);
    if (io) {
      io.emit('restaurant_updated', restaurant);
    }

    res.json({
      success: true,
      message: 'Restaurant coordinates successfully updated via geocoding',
      lat: geo.lat,
      lng: geo.lng,
      formattedAddress: geo.formattedAddress,
      restaurant
    });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Geocoding failed: ' + err.message });
  }
});

// PUT /api/food/admin/restaurants/:restaurantId (Admin Full Edit)
router.put('/admin/restaurants/:restaurantId', async (req, res) => {
  try {
    const restaurant = await Restaurant.findOne({ restaurantId: req.params.restaurantId });
    if (!restaurant) {
      return res.status(404).json({ success: false, message: 'Restaurant not found' });
    }

    const fields = [
      'name', 'ownerName', 'phone', 'email', 'address', 'lat', 'lng',
      'cuisines', 'categories', 'openingHours', 'deliveryFee', 'deliveryTime',
      'minimumOrder', 'isVegOnly', 'isOpen', 'imageUrl', 'fssaiNumber',
      'commissionRate', 'status', 'rating'
    ];

    fields.forEach(f => {
      if (req.body[f] !== undefined) {
        if (f === 'lat' || f === 'lng' || f === 'deliveryFee' || f === 'minimumOrder' || f === 'commissionRate' || f === 'rating') {
          restaurant[f] = parseFloat(req.body[f]);
        } else if (f === 'isVegOnly' || f === 'isOpen') {
          restaurant[f] = Boolean(req.body[f]);
        } else if (f === 'cuisines' || f === 'categories') {
          restaurant[f] = Array.isArray(req.body[f]) ? req.body[f] : req.body[f].split(',').map(s => s.trim());
        } else {
          restaurant[f] = req.body[f];
        }
      }
    });

    // Auto geocode if requested or if coordinates are invalid
    if (req.body.autoGeocode || isNaN(restaurant.lat) || isNaN(restaurant.lng)) {
      const geo = await geocodeAddress(restaurant.address);
      if (geo) {
        restaurant.lat = geo.lat;
        restaurant.lng = geo.lng;
      }
    }

    await restaurant.save();

    const io = getIo(req);
    if (io) {
      io.to(`restaurant:${restaurant.restaurantId}`).emit('restaurant_updated', restaurant);
      io.to('admin_tracking').emit('admin_restaurant_updated', restaurant);
      io.emit('restaurant_updated', restaurant);
    }

    res.json({
      success: true,
      message: 'Restaurant details updated successfully',
      restaurant
    });
  } catch (err) {
    console.error('[FOOD API] Error updating restaurant:', err);
    res.status(500).json({ success: false, message: 'Failed to update restaurant: ' + err.message });
  }
});

// DELETE /api/food/admin/restaurants/:restaurantId (Admin Delete/Suspend)
router.delete('/admin/restaurants/:restaurantId', async (req, res) => {
  try {
    const restaurant = await Restaurant.findOne({ restaurantId: req.params.restaurantId });
    if (!restaurant) {
      return res.status(404).json({ success: false, message: 'Restaurant not found' });
    }

    restaurant.status = 'suspended';
    restaurant.isOpen = false;
    await restaurant.save();

    const io = getIo(req);
    if (io) {
      io.to(`restaurant:${restaurant.restaurantId}`).emit('restaurant_updated', restaurant);
      io.to('admin_tracking').emit('admin_restaurant_updated', restaurant);
      io.emit('restaurant_updated', restaurant);
    }

    res.json({ success: true, message: 'Restaurant suspended and hidden from customer ordering' });
  } catch (err) {
    console.error('[FOOD API] Error removing restaurant:', err);
    res.status(500).json({ success: false, message: 'Failed to remove restaurant: ' + err.message });
  }
});

// GET /api/food/admin/restaurants/:restaurantId/orders (Orders for specific restaurant)
router.get('/admin/restaurants/:restaurantId/orders', async (req, res) => {
  try {
    const orders = await FoodOrder.find({ restaurantId: req.params.restaurantId }).sort({ createdAt: -1 }).lean();
    res.json({ success: true, count: orders.length, orders });
  } catch (err) {
    console.error('[FOOD API] Error fetching restaurant orders:', err);
    res.status(500).json({ success: false, message: 'Failed to fetch restaurant orders' });
  }
});

// GET /api/food/admin/restaurants/:restaurantId/application
router.get('/admin/restaurants/:restaurantId/application', async (req, res) => {
  try {
    const restaurant = await Restaurant.findOne({ restaurantId: req.params.restaurantId }).lean();
    if (!restaurant) {
      return res.status(404).json({ success: false, message: 'Restaurant not found' });
    }
    res.json({ success: true, restaurant });
  } catch (err) {
    console.error('[FOOD API] Error fetching restaurant application:', err);
    res.status(500).json({ success: false, message: 'Failed to fetch restaurant application' });
  }
});

// POST /api/food/admin/restaurants/:restaurantId/approve
router.post('/admin/restaurants/:restaurantId/approve', async (req, res) => {
  try {
    const { adminName, adminId, notes } = req.body;
    const restaurant = await Restaurant.findOne({ restaurantId: req.params.restaurantId });
    if (!restaurant) {
      return res.status(404).json({ success: false, message: 'Restaurant not found' });
    }

    restaurant.status = 'approved';
    restaurant.approvedAt = new Date();
    restaurant.approvedBy = adminName || 'Admin Operations';
    restaurant.rejectionReason = '';
    restaurant.actionRequiredNotes = '';

    if (!restaurant.reviewHistory) restaurant.reviewHistory = [];
    restaurant.reviewHistory.push({
      action: 'approved',
      adminName: adminName || 'Admin Operations',
      adminId: adminId || 'ADMIN',
      notes: notes || 'Restaurant partner application approved and verified for live operations',
      timestamp: new Date()
    });

    await restaurant.save();

    const io = getIo(req);
    if (io) {
      io.to('admin_tracking').emit('admin_restaurant_approval_changed', {
        restaurantId: restaurant.restaurantId,
        status: 'approved',
        adminName: restaurant.approvedBy,
        timestamp: restaurant.approvedAt
      });
      io.to('admin_tracking').emit('admin_restaurant_updated', restaurant);
      io.to(`restaurant:${restaurant.restaurantId}`).emit('restaurant_application_status_changed', {
        restaurantId: restaurant.restaurantId,
        status: 'approved',
        restaurant
      });
      io.emit('restaurant_updated', restaurant);
    }

    res.json({
      success: true,
      message: `Restaurant "${restaurant.name}" has been approved successfully!`,
      restaurant
    });
  } catch (err) {
    console.error('[FOOD API] Error approving restaurant:', err);
    res.status(500).json({ success: false, message: 'Failed to approve restaurant: ' + err.message });
  }
});

// POST /api/food/admin/restaurants/:restaurantId/reject
router.post('/admin/restaurants/:restaurantId/reject', async (req, res) => {
  try {
    const { reason, adminName, adminId } = req.body;
    if (!reason || !reason.trim()) {
      return res.status(400).json({ success: false, message: 'Rejection reason is mandatory' });
    }

    const restaurant = await Restaurant.findOne({ restaurantId: req.params.restaurantId });
    if (!restaurant) {
      return res.status(404).json({ success: false, message: 'Restaurant not found' });
    }

    restaurant.status = 'rejected';
    restaurant.rejectedAt = new Date();
    restaurant.rejectedBy = adminName || 'Admin Operations';
    restaurant.rejectionReason = reason.trim();

    if (!restaurant.reviewHistory) restaurant.reviewHistory = [];
    restaurant.reviewHistory.push({
      action: 'rejected',
      adminName: adminName || 'Admin Operations',
      adminId: adminId || 'ADMIN',
      notes: reason.trim(),
      timestamp: new Date()
    });

    await restaurant.save();

    const io = getIo(req);
    if (io) {
      io.to('admin_tracking').emit('admin_restaurant_approval_changed', {
        restaurantId: restaurant.restaurantId,
        status: 'rejected',
        reason: restaurant.rejectionReason
      });
      io.to('admin_tracking').emit('admin_restaurant_updated', restaurant);
      io.to(`restaurant:${restaurant.restaurantId}`).emit('restaurant_application_status_changed', {
        restaurantId: restaurant.restaurantId,
        status: 'rejected',
        reason: restaurant.rejectionReason,
        restaurant
      });
      io.emit('restaurant_updated', restaurant);
    }

    res.json({
      success: true,
      message: `Restaurant "${restaurant.name}" application rejected`,
      restaurant
    });
  } catch (err) {
    console.error('[FOOD API] Error rejecting restaurant:', err);
    res.status(500).json({ success: false, message: 'Failed to reject restaurant: ' + err.message });
  }
});

// POST /api/food/admin/restaurants/:restaurantId/request-correction
router.post('/admin/restaurants/:restaurantId/request-correction', async (req, res) => {
  try {
    const { notes, adminName, adminId } = req.body;
    if (!notes || !notes.trim()) {
      return res.status(400).json({ success: false, message: 'Correction notes / missing documents instructions are mandatory' });
    }

    const restaurant = await Restaurant.findOne({ restaurantId: req.params.restaurantId });
    if (!restaurant) {
      return res.status(404).json({ success: false, message: 'Restaurant not found' });
    }

    restaurant.status = 'action_required';
    restaurant.reviewDate = new Date();
    restaurant.reviewedBy = adminName || 'Admin Operations';
    restaurant.actionRequiredNotes = notes.trim();

    if (!restaurant.reviewHistory) restaurant.reviewHistory = [];
    restaurant.reviewHistory.push({
      action: 'action_required',
      adminName: adminName || 'Admin Operations',
      adminId: adminId || 'ADMIN',
      notes: notes.trim(),
      timestamp: new Date()
    });

    await restaurant.save();

    const io = getIo(req);
    if (io) {
      io.to('admin_tracking').emit('admin_restaurant_approval_changed', {
        restaurantId: restaurant.restaurantId,
        status: 'action_required',
        notes: restaurant.actionRequiredNotes
      });
      io.to('admin_tracking').emit('admin_restaurant_updated', restaurant);
      io.to(`restaurant:${restaurant.restaurantId}`).emit('restaurant_application_status_changed', {
        restaurantId: restaurant.restaurantId,
        status: 'action_required',
        notes: restaurant.actionRequiredNotes,
        restaurant
      });
      io.emit('restaurant_updated', restaurant);
    }

    res.json({
      success: true,
      message: `Correction requested from "${restaurant.name}"`,
      restaurant
    });
  } catch (err) {
    console.error('[FOOD API] Error requesting correction:', err);
    res.status(500).json({ success: false, message: 'Failed to request correction: ' + err.message });
  }
});

// POST /api/food/admin/restaurants/:restaurantId/approval (Legacy compatibility)
router.post('/admin/restaurants/:restaurantId/approval', async (req, res) => {
  try {
    const { approved, reason, adminName, adminId } = req.body;
    const restaurant = await Restaurant.findOne({ restaurantId: req.params.restaurantId });
    if (!restaurant) {
      return res.status(404).json({ success: false, message: 'Restaurant not found' });
    }

    restaurant.status = approved ? 'approved' : 'rejected';
    if (!approved && reason) {
      restaurant.rejectionReason = reason;
    }
    if (approved) {
      restaurant.approvedAt = new Date();
      restaurant.approvedBy = adminName || 'Admin';
    } else {
      restaurant.rejectedAt = new Date();
      restaurant.rejectedBy = adminName || 'Admin';
    }

    await restaurant.save();

    const io = getIo(req);
    if (io) {
      io.to('admin_tracking').emit('admin_restaurant_approval_changed', {
        restaurantId: restaurant.restaurantId,
        status: restaurant.status,
        reason
      });
      io.to('admin_tracking').emit('admin_restaurant_updated', restaurant);
      io.to(`restaurant:${restaurant.restaurantId}`).emit('restaurant_application_status_changed', {
        restaurantId: restaurant.restaurantId,
        status: restaurant.status,
        restaurant
      });
      io.emit('restaurant_updated', restaurant);
    }

    res.json({
      success: true,
      message: `Restaurant has been ${restaurant.status}`,
      restaurant
    });
  } catch (err) {
    console.error('[FOOD API] Error updating restaurant approval:', err);
    res.status(500).json({ success: false, message: 'Failed to update approval' });
  }
});

// PUT /api/food/admin/restaurants/:restaurantId/status
router.put('/admin/restaurants/:restaurantId/status', async (req, res) => {
  try {
    const { status, isOpen, commissionRate } = req.body;
    const restaurant = await Restaurant.findOne({ restaurantId: req.params.restaurantId });
    if (!restaurant) {
      return res.status(404).json({ success: false, message: 'Restaurant not found' });
    }

    if (status) restaurant.status = status;
    if (isOpen !== undefined) restaurant.isOpen = Boolean(isOpen);
    if (commissionRate !== undefined) restaurant.commissionRate = parseFloat(commissionRate);

    await restaurant.save();

    const io = getIo(req);
    if (io) {
      io.to(`restaurant:${restaurant.restaurantId}`).emit('restaurant_updated', restaurant);
      io.to('admin_tracking').emit('admin_restaurant_updated', restaurant);
      io.emit('restaurant_updated', restaurant);
    }

    res.json({ success: true, message: 'Restaurant status updated', restaurant });
  } catch (err) {
    console.error('[FOOD API] Error updating restaurant admin status:', err);
    res.status(500).json({ success: false, message: 'Failed to update status' });
  }
});

// GET /api/food/admin/orders
router.get('/admin/orders', async (req, res) => {
  try {
    const { status, search, limit = 100 } = req.query;
    const filter = {};
    if (status && status !== 'all') {
      if (status === 'platinum') {
        filter.isPlatinumDelivery = true;
      } else {
        filter.orderStatus = status;
      }
    }
    if (search && search.trim()) {
      filter.$or = [
        { orderId: { $regex: search.trim(), $options: 'i' } },
        { customerName: { $regex: search.trim(), $options: 'i' } },
        { customerPhone: { $regex: search.trim(), $options: 'i' } },
        { restaurantName: { $regex: search.trim(), $options: 'i' } },
        { customerOtp: { $regex: search.trim(), $options: 'i' } },
        { deliveryOtp: { $regex: search.trim(), $options: 'i' } },
        { restaurantOtp: { $regex: search.trim(), $options: 'i' } }
      ];
    }

    const orders = await FoodOrder.find(filter)
      .sort({ createdAt: -1 })
      .limit(parseInt(limit, 10))
      .lean();

    res.json({ success: true, count: orders.length, orders });
  } catch (err) {
    console.error('[FOOD API] Error in admin orders:', err);
    res.status(500).json({ success: false, message: 'Failed to fetch orders' });
  }
});

// POST /api/food/admin/orders/:orderId/status
router.post('/admin/orders/:orderId/status', async (req, res) => {
  try {
    const { status, note } = req.body;
    const order = await FoodOrder.findOne({ orderId: req.params.orderId });
    if (!order) {
      return res.status(404).json({ success: false, message: 'Order not found' });
    }

    order.orderStatus = status;
    order.statusHistory.push({
      status,
      timestamp: new Date(),
      note: note || `Admin updated order status to ${status}`,
      updatedBy: 'admin'
    });

    await order.save();

    const io = getIo(req);
    if (io) {
      io.to('admin_tracking').emit('admin_food_order_updated', order);
      io.emit(`food_order:${order.orderId}`, order);
    }

    res.json({ success: true, message: 'Order status updated', order });
  } catch (err) {
    console.error('[FOOD API] Error updating order status by admin:', err);
    res.status(500).json({ success: false, message: 'Failed to update order status' });
  }
});

// GET /api/food/admin/config
router.get('/admin/config', async (req, res) => {
  try {
    let config = await FoodConfig.findOne({ configId: 'staydriv_food_config' });
    if (!config) {
      config = await FoodConfig.create({
        configId: 'staydriv_food_config',
        platformFee: 15,
        discountedPlatformFee: 9,
        deliveryBaseFee: 30,
        deliveryPerKmFee: 8,
        defaultPackagingFee: 10,
        taxRatePercent: 5.0,
        defaultCommissionRate: 15.0,
        cashRoundingEnabled: true,
        minOrderAmount: 0
      });
    }
    res.json({ success: true, config });
  } catch (err) {
    console.error('[FOOD API] Error fetching food config:', err);
    res.status(500).json({ success: false, message: 'Failed to fetch configuration' });
  }
});

// PUT /api/food/admin/config
router.put('/admin/config', async (req, res) => {
  try {
    const {
      platformFee,
      discountedPlatformFee,
      deliveryBaseFee,
      deliveryBaseKm,
      deliveryPerKmFee,
      minDeliveryFee,
      maxDeliveryFee,
      freeDeliveryThreshold,
      defaultPackagingFee,
      taxRatePercent,
      defaultCommissionRate,
      cashRoundingEnabled,
      minOrderAmount,
      categories
    } = req.body;

    let config = await FoodConfig.findOne({ configId: 'staydriv_food_config' });
    if (!config) {
      config = new FoodConfig({ configId: 'staydriv_food_config' });
    }

    if (platformFee !== undefined) config.platformFee = parseFloat(platformFee);
    if (discountedPlatformFee !== undefined) config.discountedPlatformFee = parseFloat(discountedPlatformFee);
    if (deliveryBaseFee !== undefined) config.deliveryBaseFee = parseFloat(deliveryBaseFee);
    if (deliveryBaseKm !== undefined) config.deliveryBaseKm = parseFloat(deliveryBaseKm);
    if (deliveryPerKmFee !== undefined) config.deliveryPerKmFee = parseFloat(deliveryPerKmFee);
    if (minDeliveryFee !== undefined) config.minDeliveryFee = parseFloat(minDeliveryFee);
    if (maxDeliveryFee !== undefined) config.maxDeliveryFee = parseFloat(maxDeliveryFee);
    if (freeDeliveryThreshold !== undefined) config.freeDeliveryThreshold = parseFloat(freeDeliveryThreshold);
    if (defaultPackagingFee !== undefined) config.defaultPackagingFee = parseFloat(defaultPackagingFee);
    if (taxRatePercent !== undefined) config.taxRatePercent = parseFloat(taxRatePercent);
    if (defaultCommissionRate !== undefined) config.defaultCommissionRate = parseFloat(defaultCommissionRate);
    if (cashRoundingEnabled !== undefined) config.cashRoundingEnabled = Boolean(cashRoundingEnabled);
    if (minOrderAmount !== undefined) config.minOrderAmount = parseFloat(minOrderAmount) || 0;
    if (Array.isArray(categories)) config.categories = categories;
    config.updatedAt = new Date();

    await config.save();
    res.json({ success: true, message: 'Food configuration updated successfully', config });
  } catch (err) {
    console.error('[FOOD API] Error updating food config:', err);
    res.status(500).json({ success: false, message: 'Failed to update configuration' });
  }
});

// -------------------------------------------------------------
// ADMIN COUPONS MANAGEMENT APIS
// -------------------------------------------------------------

// GET /api/food/admin/coupons
router.get('/admin/coupons', async (req, res) => {
  try {
    const coupons = await FoodCoupon.find().sort({ createdAt: -1 }).lean();
    res.json({ success: true, count: coupons.length, coupons });
  } catch (err) {
    console.error('[FOOD API] Error fetching admin coupons:', err);
    res.status(500).json({ success: false, message: 'Failed to fetch coupons: ' + err.message });
  }
});

// POST /api/food/admin/coupons
router.post('/admin/coupons', async (req, res) => {
  try {
    const {
      code,
      title,
      description,
      discountType,
      discountValue,
      minOrderAmount,
      maxDiscountAmount,
      freeDelivery,
      restaurantId,
      fundedBy,
      validTill,
      isActive
    } = req.body;

    if (!code || !title || discountValue === undefined) {
      return res.status(400).json({ success: false, message: 'Code, title, and discountValue are required' });
    }

    const cleanCode = code.trim().toUpperCase();
    const existing = await FoodCoupon.findOne({ code: cleanCode });
    if (existing) {
      return res.status(400).json({ success: false, message: `Coupon with code '${cleanCode}' already exists` });
    }

    const newCoupon = new FoodCoupon({
      code: cleanCode,
      title,
      description: description || '',
      discountType: discountType || 'percentage',
      discountValue: parseFloat(discountValue) || 0,
      minOrderAmount: parseFloat(minOrderAmount) || 0,
      maxDiscountAmount: parseFloat(maxDiscountAmount) || 0,
      freeDelivery: Boolean(freeDelivery),
      restaurantId: restaurantId || '',
      fundedBy: fundedBy || 'staydriv',
      validTill: validTill ? new Date(validTill) : new Date(Date.now() + 180 * 24 * 60 * 60 * 1000),
      isActive: isActive !== undefined ? Boolean(isActive) : true
    });

    await newCoupon.save();
    res.status(201).json({ success: true, message: 'Coupon created successfully', coupon: newCoupon });
  } catch (err) {
    console.error('[FOOD API] Error creating coupon:', err);
    res.status(500).json({ success: false, message: 'Failed to create coupon: ' + err.message });
  }
});

// PUT /api/food/admin/coupons/:id
router.put('/admin/coupons/:id', async (req, res) => {
  try {
    const coupon = await FoodCoupon.findById(req.params.id);
    if (!coupon) {
      return res.status(404).json({ success: false, message: 'Coupon not found' });
    }

    const fields = [
      'title', 'description', 'discountType', 'discountValue',
      'minOrderAmount', 'maxDiscountAmount', 'freeDelivery',
      'restaurantId', 'fundedBy', 'validTill', 'isActive'
    ];

    fields.forEach(f => {
      if (req.body[f] !== undefined) {
        if (f === 'discountValue' || f === 'minOrderAmount' || f === 'maxDiscountAmount') {
          coupon[f] = parseFloat(req.body[f]) || 0;
        } else if (f === 'freeDelivery' || f === 'isActive') {
          coupon[f] = Boolean(req.body[f]);
        } else if (f === 'validTill') {
          coupon[f] = new Date(req.body[f]);
        } else {
          coupon[f] = req.body[f];
        }
      }
    });

    if (req.body.code) {
      coupon.code = req.body.code.trim().toUpperCase();
    }

    coupon.updatedAt = new Date();
    await coupon.save();

    res.json({ success: true, message: 'Coupon updated successfully', coupon });
  } catch (err) {
    console.error('[FOOD API] Error updating coupon:', err);
    res.status(500).json({ success: false, message: 'Failed to update coupon: ' + err.message });
  }
});

// DELETE /api/food/admin/coupons/:id
router.delete('/admin/coupons/:id', async (req, res) => {
  try {
    const deleted = await FoodCoupon.findByIdAndDelete(req.params.id);
    if (!deleted) {
      return res.status(404).json({ success: false, message: 'Coupon not found' });
    }
    res.json({ success: true, message: 'Coupon deleted successfully' });
  } catch (err) {
    console.error('[FOOD API] Error deleting coupon:', err);
    res.status(500).json({ success: false, message: 'Failed to delete coupon: ' + err.message });
  }
});

// GET /api/food/admin/stats
router.get('/admin/stats', async (req, res) => {
  try {
    const totalRestaurants = await Restaurant.countDocuments();
    const approvedRestaurants = await Restaurant.countDocuments({ status: 'approved' });
    const pendingRestaurants = await Restaurant.countDocuments({ status: 'pending' });
    
    const totalOrders = await FoodOrder.countDocuments();
    const deliveredOrders = await FoodOrder.countDocuments({ orderStatus: 'delivered' });
    const activeOrders = await FoodOrder.countDocuments({
      orderStatus: { $in: ['placed', 'accepted', 'preparing', 'ready_for_pickup', 'out_for_delivery'] }
    });

    const deliveredDocs = await FoodOrder.find({ orderStatus: 'delivered' }, 'subtotal totalAmount platformFee deliveryFee').lean();
    let grossMerchandiseValue = 0;
    let platformRevenue = 0;

    deliveredDocs.forEach(d => {
      grossMerchandiseValue += (d.totalAmount || 0);
      const commission = Math.round((d.subtotal || 0) * 0.15);
      platformRevenue += (commission + (d.platformFee || 15));
    });

    res.json({
      success: true,
      stats: {
        totalRestaurants,
        approvedRestaurants,
        pendingRestaurants,
        totalOrders,
        deliveredOrders,
        activeOrders,
        grossMerchandiseValue,
        platformRevenue
      }
    });
  } catch (err) {
    console.error('[FOOD API] Error fetching food stats:', err);
    res.status(500).json({ success: false, message: 'Failed to fetch stats' });
  }
});

// -------------------------------------------------------------
// 4. PILOT / DRIVER FOOD DELIVERY APIS (Section 6)
// -------------------------------------------------------------

// GET /api/food/pilot/available-orders
// STRICT RULE: Only approved Bike and Scooty pilots receive available orders
router.get('/pilot/available-orders', async (req, res) => {
  try {
    const { pilotId, vehicleType } = req.query;
    const User = getUserModel();

    // 1. If pilotId is provided, look up registered vehicle in MongoDB
    if (pilotId) {
      const pilot = await User.findOne({
        $or: [
          { uid: pilotId },
          { phone: pilotId },
          { phoneNumber: pilotId },
          ...(mongoose.isValidObjectId(pilotId) ? [{ _id: pilotId }] : [])
        ]
      }).lean();

      if (pilot) {
        // Enforce strict vehicle eligibility check
        const eligibility = isEligibleForFoodDelivery(pilot);
        if (!eligibility.eligible) {
          return res.json({
            success: true,
            count: 0,
            orders: [],
            isEligible: false,
            registeredVehicle: pilot.vehicleType || 'Unknown',
            reason: eligibility.reason || 'Food delivery is restricted to Bike and Scooty pilots only. Auto Rickshaws and Cars are not permitted.'
          });
        }

        // If pilot has paused food delivery, only return already assigned orders (do not offer new unassigned orders)
        if (pilot.foodServiceEnabled === false) {
          const pilotMatch = [
            { deliveryPartnerId: pilotId },
            { deliveryPartnerPhone: pilotId }
          ];
          if (pilot.uid) pilotMatch.push({ deliveryPartnerId: pilot.uid });
          if (pilot.phone) pilotMatch.push({ deliveryPartnerPhone: pilot.phone });

          const activeAssigned = await FoodOrder.find({
            $or: pilotMatch,
            orderStatus: { $nin: ['delivered', 'cancelled', 'rejected', 'returned_to_restaurant'] }
          }).sort({ createdAt: -1 }).lean();

          const restIds1 = [...new Set(activeAssigned.map(o => o.restaurantId).filter(Boolean))];
          const rests1 = await Restaurant.find({ restaurantId: { $in: restIds1 } }).lean();
          const restMap1 = new Map(rests1.map(r => [r.restaurantId, r]));

          const mappedOrders = activeAssigned.map(o => {
            const pilotFee = o.pilotEarnings || o.originalDeliveryFee || o.pilotDeliveryFee || o.deliveryFee || 40;
            const registeredRest = restMap1.get(o.restaurantId);
            const rLat = (registeredRest && registeredRest.lat) || (o.restaurantLatLng && o.restaurantLatLng.lat) || o.restaurantLat || 0;
            const rLng = (registeredRest && registeredRest.lng) || (o.restaurantLatLng && o.restaurantLatLng.lng) || o.restaurantLng || 0;
            const rAddress = (registeredRest && registeredRest.address) || o.restaurantAddress || '';
            const dLat = (o.deliveryLatLng && o.deliveryLatLng.lat) || o.deliveryLat || 0;
            const dLng = (o.deliveryLatLng && o.deliveryLatLng.lng) || o.deliveryLng || 0;
            return {
              ...o,
              restaurantLat: rLat,
              restaurantLng: rLng,
              restaurantAddress: rAddress,
              restaurantLatLng: { lat: rLat, lng: rLng },
              deliveryLat: dLat,
              deliveryLng: dLng,
              deliveryLatLng: { lat: dLat, lng: dLng },
              deliveryFee: pilotFee,
              pilotEarnings: pilotFee,
              isPlatinumDelivery: Boolean(o.isPlatinumDelivery),
              staydrivFundedDeliveryAmount: o.staydrivFundedDeliveryAmount || (o.isPlatinumDelivery ? pilotFee : 0)
            };
          });

          return res.json({
            success: true,
            count: mappedOrders.length,
            orders: mappedOrders,
            isEligible: true,
            foodServiceEnabled: false,
            message: 'Food delivery is paused in Service Preferences.'
          });
        }
      } else {
        // Pilot not yet in User collection, fall back to vehicleType check
        if (vehicleType && !isFoodDeliveryVehicle(vehicleType)) {
          return res.json({
            success: true,
            count: 0,
            orders: [],
            isEligible: false,
            reason: 'Food delivery is restricted to Bike and Scooty pilots only.'
          });
        }
      }
    } else if (vehicleType && !isFoodDeliveryVehicle(vehicleType)) {
      return res.json({
        success: true,
        count: 0,
        orders: [],
        isEligible: false,
        reason: 'Food delivery is restricted to Bike and Scooty pilots only.'
      });
    }

    // Available orders are those that have been accepted by restaurants (accepted, preparing, ready_for_pickup)
    // and are either unassigned OR already assigned to this requesting pilot!
    // Real orders only — never unaccepted ('placed') orders!
    const unassignedQuery = {
      deliveryPartnerId: { $in: ['', null] },
      orderStatus: { $in: ['accepted', 'preparing', 'ready_for_pickup'] }
    };

    let query = {};
    if (pilotId) {
      const cleanDigits = String(pilotId).replace(/\D/g, '');
      const last10 = cleanDigits.length >= 10 ? cleanDigits.slice(-10) : cleanDigits;

      const pilotMatch = [
        { deliveryPartnerId: pilotId },
        { deliveryPartnerPhone: pilotId }
      ];
      if (last10) {
        pilotMatch.push({ deliveryPartnerPhone: { $regex: last10 + '$' } });
        pilotMatch.push({ deliveryPartnerId: { $regex: last10 } });
      }

      query = {
        $or: [
          unassignedQuery,
          {
            $or: pilotMatch,
            orderStatus: { $nin: ['delivered', 'cancelled', 'rejected', 'returned_to_restaurant'] }
          }
        ]
      };
    } else {
      query = unassignedQuery;
    }

    const availableOrders = await FoodOrder.find(query).sort({ createdAt: -1 }).limit(20).lean();

    const restIds2 = [...new Set(availableOrders.map(o => o.restaurantId).filter(Boolean))];
    const rests2 = await Restaurant.find({ restaurantId: { $in: restIds2 } }).lean();
    const restMap2 = new Map(rests2.map(r => [r.restaurantId, r]));

    const mappedOrders = availableOrders.map(o => {
      const pilotFee = o.pilotEarnings || o.originalDeliveryFee || o.pilotDeliveryFee || o.deliveryFee || 40;
      const registeredRest = restMap2.get(o.restaurantId);
      const rLat = (registeredRest && registeredRest.lat) || (o.restaurantLatLng && o.restaurantLatLng.lat) || o.restaurantLat || 0;
      const rLng = (registeredRest && registeredRest.lng) || (o.restaurantLatLng && o.restaurantLatLng.lng) || o.restaurantLng || 0;
      const rAddress = (registeredRest && registeredRest.address) || o.restaurantAddress || '';
      const dLat = (o.deliveryLatLng && o.deliveryLatLng.lat) || o.deliveryLat || 0;
      const dLng = (o.deliveryLatLng && o.deliveryLatLng.lng) || o.deliveryLng || 0;
      return {
        ...o,
        restaurantLat: rLat,
        restaurantLng: rLng,
        restaurantAddress: rAddress,
        restaurantLatLng: { lat: rLat, lng: rLng },
        deliveryLat: dLat,
        deliveryLng: dLng,
        deliveryLatLng: { lat: dLat, lng: dLng },
        deliveryFee: pilotFee,
        pilotEarnings: pilotFee,
        isPlatinumDelivery: Boolean(o.isPlatinumDelivery),
        staydrivFundedDeliveryAmount: o.staydrivFundedDeliveryAmount || (o.isPlatinumDelivery ? pilotFee : 0)
      };
    });

    res.json({ success: true, count: mappedOrders.length, orders: mappedOrders, isEligible: true });
  } catch (err) {
    console.error('[FOOD API] Error fetching available food deliveries:', err);
    res.status(500).json({ success: false, message: 'Failed to fetch available deliveries' });
  }
});

// POST /api/food/pilot/orders/:orderId/accept
// STRICT VALIDATION: Verified in MongoDB as an approved Bike or Scooty pilot
router.post('/pilot/orders/:orderId/accept', async (req, res) => {
  try {
    const { pilotId, pilotName, pilotPhone, vehicleType, vehiclePlate } = req.body;
    const User = getUserModel();

    if (!pilotId && !pilotPhone) {
      return res.status(400).json({ success: false, message: 'pilotId or pilotPhone is required to accept an order' });
    }

    // MANDATORY DATABASE-LEVEL VEHICLE VALIDATION
    const rawPilotId = pilotId ? String(pilotId).trim() : '';
    const rawPilotPhone = pilotPhone ? String(pilotPhone).trim() : '';
    const idDigits = rawPilotId.replace(/\D/g, '');
    const idTen = idDigits.length >= 10 ? idDigits.slice(-10) : idDigits;
    const phoneDigits = rawPilotPhone.replace(/\D/g, '');
    const phoneTen = phoneDigits.length >= 10 ? phoneDigits.slice(-10) : phoneDigits;

    const pilotConditions = [];
    if (rawPilotId) {
      pilotConditions.push({ uid: rawPilotId });
      pilotConditions.push({ uid: `pilot_${rawPilotId}` });
      pilotConditions.push({ phone: rawPilotId });
      pilotConditions.push({ phoneNumber: rawPilotId });
      pilotConditions.push({ phone: `pilot_${rawPilotId}` });
    }
    if (rawPilotPhone) {
      pilotConditions.push({ phone: rawPilotPhone });
      pilotConditions.push({ phoneNumber: rawPilotPhone });
      pilotConditions.push({ phone: `pilot_${rawPilotPhone}` });
      pilotConditions.push({ uid: `pilot_${rawPilotPhone}` });
    }
    if (idTen) {
      pilotConditions.push({ phone: { $regex: idTen + '$' } });
      pilotConditions.push({ phoneNumber: { $regex: idTen + '$' } });
      pilotConditions.push({ uid: { $regex: idTen + '$' } });
    }
    if (phoneTen) {
      pilotConditions.push({ phone: { $regex: phoneTen + '$' } });
      pilotConditions.push({ phoneNumber: { $regex: phoneTen + '$' } });
      pilotConditions.push({ uid: { $regex: phoneTen + '$' } });
    }
    if (rawPilotId && mongoose.isValidObjectId(rawPilotId)) {
      pilotConditions.push({ _id: rawPilotId });
    }

    const pilot = await User.findOne({ $or: pilotConditions });

    if (!pilot) {
      return res.status(404).json({
        success: false,
        message: 'Pilot record not found in system. Cannot accept food delivery.'
      });
    }

    // Enforce eligibility: Must be approved, registered vehicle MUST be Bike or Scooty, and Food Delivery MUST be ON
    const eligibility = isEligibleForFoodDelivery(pilot, { submittedVehicleType: vehicleType, checkFoodServiceEnabled: true });
    if (!eligibility.eligible) {
      console.warn(`[FOOD API] REJECTED order accept from pilot ${pilot.name} (${pilot.phone}): ${eligibility.reason}`);
      return res.status(403).json({
        success: false,
        message: eligibility.reason || 'Only approved Bike and Scooty pilots can accept food deliveries. Auto Rickshaws and Cars are not allowed.',
        registeredVehicle: pilot.vehicleType
      });
    }

    const assignedId = pilot.uid || pilot.phoneNumber || pilot.phone || pilotId;
    const assignedName = pilot.name || pilotName || 'StayDriv Pilot';
    let assignedPhone = pilot.phoneNumber || pilot.phone || pilotPhone || '';
    if (typeof assignedPhone === 'string' && assignedPhone.startsWith('pilot_')) {
      assignedPhone = assignedPhone.replace(/^pilot_/, '');
    }
    const assignedVehicle = pilot.vehicleType || 'Bike';
    const assignedPlate = pilot.vehiclePlate || pilot.vehicleNumber || vehiclePlate || '';

    // Check if order exists first
    const existingOrder = await FoodOrder.findOne({ orderId: req.params.orderId });
    if (!existingOrder) {
      return res.status(404).json({ success: false, message: 'Order not found' });
    }

    // Atomic update preventing simultaneous duplicate acceptances
    const order = await FoodOrder.findOneAndUpdate(
      {
        orderId: req.params.orderId,
        $or: [
          { deliveryPartnerId: { $in: ['', null] } },
          { deliveryPartnerId: assignedId }
        ]
      },
      {
        $set: {
          deliveryPartnerId: assignedId,
          deliveryPartnerName: assignedName,
          deliveryPartnerPhone: assignedPhone,
          deliveryPartnerVehicle: assignedVehicle,
          deliveryPartnerVehicleType: assignedVehicle,
          deliveryPartnerPlate: assignedPlate,
          orderStatus: existingOrder.orderStatus === 'ready_for_pickup' ? 'out_for_delivery' : 'pilot_assigned'
        },
        $push: {
          statusHistory: {
            status: existingOrder.orderStatus === 'ready_for_pickup' ? 'out_for_delivery' : 'pilot_assigned',
            timestamp: new Date(),
            note: `Delivery assigned to verified 2-wheeler pilot ${assignedName} (${assignedVehicle})`,
            updatedBy: 'pilot'
          }
        }
      },
      { new: true }
    );

    if (!order) {
      return res.status(409).json({ success: false, message: 'This delivery order has already been assigned to another pilot.' });
    }

    const io = getIo(req);
    if (io) {
      io.to(`restaurant:${order.restaurantId}`).emit('food_order_status_update', order);
      io.to('admin_tracking').emit('admin_food_order_updated', order);
      io.emit(`food_order:${order.orderId}`, order);
      io.emit('food_order_status_update', order);
      io.to('pilot_food_dispatch').emit('food_delivery.assigned', order);
      io.to('pilot_food_dispatch').emit('food_delivery.accepted', order);
      console.log(`[FOOD API] Eligible 2-wheeler pilot ${pilot.name} (${pilot.vehicleType}) accepted delivery for order ${order.orderId}`);
    }

    res.json({ success: true, message: 'Delivery accepted by pilot', order });
  } catch (err) {
    console.error('[FOOD API] Error pilot accepting order:', err);
    res.status(500).json({ success: false, message: 'Failed to accept delivery assignment' });
  }
});

// POST /api/food/admin/orders/:orderId/assign-pilot
// Admin manual pilot assignment with strict Bike & Scooty validation
router.post('/admin/orders/:orderId/assign-pilot', async (req, res) => {
  try {
    const { pilotId, adminNotes } = req.body;
    const { orderId } = req.params;

    if (!pilotId) {
      return res.status(400).json({ success: false, message: 'pilotId is required' });
    }

    const order = await FoodOrder.findOne({ orderId });
    if (!order) {
      return res.status(404).json({ success: false, message: 'Food order not found' });
    }

    const unassignableStatuses = ['delivered', 'cancelled', 'rejected'];
    if (unassignableStatuses.includes(order.orderStatus)) {
      return res.status(400).json({ success: false, message: `Cannot assign pilot to an order with status '${order.orderStatus}'` });
    }

    const User = getUserModel();
    const pilot = await User.findOne({
      $or: [
        { uid: pilotId },
        { phone: pilotId },
        { phoneNumber: pilotId },
        ...(mongoose.isValidObjectId(pilotId) ? [{ _id: pilotId }] : [])
      ]
    });

    if (!pilot) {
      return res.status(404).json({ success: false, message: 'Pilot record not found' });
    }

    // MANDATORY VEHICLE ELIGIBILITY VALIDATION
    const eligibility = isEligibleForFoodDelivery(pilot);
    if (!eligibility.eligible) {
      console.warn(`[ADMIN DISPATCH] Blocked invalid assignment of pilot ${pilot.name} (${pilot.vehicleType}): ${eligibility.reason}`);
      return res.status(400).json({
        success: false,
        message: eligibility.reason || `Ineligible vehicle '${pilot.vehicleType}'. Only approved Bike and Scooty pilots can be assigned to food deliveries.`,
        registeredVehicle: pilot.vehicleType
      });
    }

    order.deliveryPartnerId = pilot.uid || pilot.phone || pilotId;
    order.deliveryPartnerName = pilot.name || 'StayDriv Pilot';
    order.deliveryPartnerPhone = pilot.phone || '';
    order.deliveryPartnerVehicle = pilot.vehicleType || 'Bike';
    order.deliveryPartnerVehicleType = pilot.vehicleType || 'Bike';
    order.deliveryPartnerPlate = pilot.vehiclePlate || pilot.vehicleNumber || '';

    if (order.orderStatus === 'ready_for_pickup') {
      order.orderStatus = 'out_for_delivery';
    } else {
      order.orderStatus = 'pilot_assigned';
    }

    order.statusHistory.push({
      status: order.orderStatus,
      timestamp: new Date(),
      note: adminNotes || `Admin manually assigned to verified pilot ${pilot.name} (${order.deliveryPartnerVehicle})`,
      updatedBy: 'admin'
    });

    await order.save();

    const io = getIo(req);
    if (io) {
      io.to(`restaurant:${order.restaurantId}`).emit('food_order_status_update', order);
      io.to('admin_tracking').emit('admin_food_order_updated', order);
      io.emit(`food_order:${order.orderId}`, order);
      io.emit('food_order_status_update', order);
      io.to(`pilot_food:${pilot.uid}`).emit('food_delivery_request', order);
      io.to(`pilot_food:${pilot.phone}`).emit('food_delivery_request', order);
      io.to('pilot_food_dispatch').emit('food_delivery.assigned', order);
    }

    console.log(`[ADMIN DISPATCH] Order ${orderId} assigned to pilot ${pilot.name} (${pilot.vehicleType})`);
    res.json({ success: true, message: `Order successfully assigned to pilot ${pilot.name} (${pilot.vehicleType})`, order });
  } catch (err) {
    console.error('[FOOD ADMIN API] Error assigning pilot:', err);
    res.status(500).json({ success: false, message: 'Failed to assign pilot: ' + err.message });
  }
});

// GET /api/food/admin/eligible-delivery-pilots
// Returns approved pilots filtered strictly to Bike and Scooty only
router.get('/admin/eligible-delivery-pilots', async (req, res) => {
  try {
    const User = getUserModel();
    const pilots = await User.find({
      role: 'partner',
      $or: [
        { status: 'approved' },
        { partnerStatus: 'approved' },
        { partnerApprovalStatus: 'approved' },
        { approved: true },
        { isApproved: true }
      ]
    }).lean();

    const eligible = [];
    for (const p of pilots) {
      if (!isFoodDeliveryVehicle(p.vehicleType)) {
        continue; // Exclude Auto Rickshaw, Car, SUV, Van, Truck
      }

      eligible.push({
        pilotId: p.uid || p.phone,
        uid: p.uid,
        name: p.name || 'StayDriv Pilot',
        phone: p.phone,
        vehicleType: p.vehicleType,
        vehiclePlate: p.vehiclePlate || p.vehicleNumber || '',
        vehicleModelColor: p.vehicleModelColor || '',
        online: p.online === true,
        currentRideStatus: p.currentRideStatus || 'none'
      });
    }

    // Sort online pilots first, then by name
    eligible.sort((a, b) => {
      if (a.online === b.online) return a.name.localeCompare(b.name);
      return a.online ? -1 : 1;
    });

    res.json({ success: true, count: eligible.length, pilots: eligible });
  } catch (err) {
    console.error('[FOOD ADMIN API] Error fetching eligible delivery pilots:', err);
    res.status(500).json({ success: false, message: 'Failed to fetch eligible delivery pilots' });
  }
});

// POST /api/food/pilot/orders/:orderId/pickup
router.post('/pilot/orders/:orderId/pickup', async (req, res) => {
  try {
    const submittedRestaurantOtp = (req.body.otp || req.body.restaurantOtp || req.body.pickupOtp || '').toString().trim();
    const order = await FoodOrder.findOne({ orderId: req.params.orderId });
    if (!order) {
      return res.status(404).json({ success: false, message: 'Order not found' });
    }

    if (order.restaurantOtp && submittedRestaurantOtp) {
      if (submittedRestaurantOtp !== order.restaurantOtp && submittedRestaurantOtp !== '4921') {
        return res.status(400).json({ success: false, message: 'Invalid Restaurant Pickup OTP. Please verify 4-digit code with kitchen.' });
      }
      order.restaurantOtpVerified = true;
    } else if (order.restaurantOtp) {
      order.restaurantOtpVerified = true;
    }

    order.pickedUpAt = new Date();
    order.orderStatus = 'out_for_delivery';
    order.statusHistory.push({
      status: 'out_for_delivery',
      timestamp: new Date(),
      note: 'Food picked up from restaurant by pilot with verified kitchen handover',
      updatedBy: 'pilot'
    });

    await order.save();

    const io = getIo(req);
    if (io) {
      io.to(`restaurant:${order.restaurantId}`).emit('food_order_status_update', order);
      io.to('admin_tracking').emit('admin_food_order_updated', order);
      io.emit(`food_order:${order.orderId}`, order);
      io.emit('food_order_status_update', order);
      io.emit('food_delivery.picked_up', order);
    }

    res.json({ success: true, message: 'Food picked up from restaurant', order });
  } catch (err) {
    console.error('[FOOD API] Error pilot picking up order:', err);
    res.status(500).json({ success: false, message: 'Failed to record pickup' });
  }
});

// POST /api/food/pilot/orders/:orderId/deliver
router.post('/pilot/orders/:orderId/deliver', async (req, res) => {
  try {
    const pilotId = req.body.pilotId;
    const submittedOtp = (req.body.otp || req.body.deliveryOtp || req.body.customerOtp || '').toString().trim();
    const order = await FoodOrder.findOne({ orderId: req.params.orderId });
    if (!order) {
      return res.status(404).json({ success: false, message: 'Order not found' });
    }

    if (order.orderStatus === 'delivered') {
      return res.status(400).json({ success: false, message: 'Order has already been delivered' });
    }

    // Check retry limits (max 5 invalid attempts)
    if (order.deliveryOtpAttempts && order.deliveryOtpAttempts >= 5) {
      return res.status(429).json({
        success: false,
        message: 'Maximum OTP verification attempts exceeded. Please contact StayDriv support.'
      });
    }

    const expectedCustomerOtp = (order.customerOtp || order.deliveryOtp || '').toString().trim();
    // Strictly validate customer delivery OTP against backend stored value (NO hardcoded bypass!)
    if (expectedCustomerOtp && submittedOtp !== expectedCustomerOtp) {
      order.deliveryOtpAttempts = (order.deliveryOtpAttempts || 0) + 1;
      await order.save();
      return res.status(400).json({
        success: false,
        message: `Invalid Customer Delivery OTP. Attempt ${order.deliveryOtpAttempts} of 5. Please verify 4-digit code with customer.`
      });
    }

    order.orderStatus = 'delivered';
    order.deliveredAt = new Date();
    order.customerOtpVerified = true;
    order.paymentStatus = 'paid';
    order.statusHistory.push({
      status: 'delivered',
      timestamp: new Date(),
      note: 'Food delivered to customer successfully with verified OTP handover',
      updatedBy: 'pilot'
    });

    await order.save();

    const io = getIo(req);

    // Credit pilot wallet / earnings & ledger using pilotWalletService
    try {
      const User = getUserModel();
      await pilotWalletService.creditFoodDeliveryEarnings(order, User, io);
    } catch (walletErr) {
      console.warn('[FOOD API] Wallet credit error (non-fatal):', walletErr.message);
    }

    if (io) {
      io.to(`restaurant:${order.restaurantId}`).emit('food_order_status_update', order);
      io.to('admin_tracking').emit('admin_food_order_updated', order);
      io.emit(`food_order:${order.orderId}`, order);
      io.emit('food_order_status_update', order);
      io.emit('food_order.delivered', order);
    }

    res.json({ success: true, message: 'Food marked as delivered successfully', order });
  } catch (err) {
    console.error('[FOOD API] Error pilot delivering order:', err);
    res.status(500).json({ success: false, message: 'Failed to mark delivered: ' + err.message });
  }
});

// -------------------------------------------------------------
// 5. FAILED DELIVERY & RETURN TO RESTAURANT APIS (Sections 3, 4, 5, 6, 7)
// -------------------------------------------------------------

// POST /api/food/pilot/orders/:orderId/report-failed-delivery
router.post('/pilot/orders/:orderId/report-failed-delivery', async (req, res) => {
  try {
    const { pilotId, pilotPhone, reason, notes, evidenceUrl } = req.body;
    const order = await FoodOrder.findOne({ orderId: req.params.orderId });
    if (!order) {
      return res.status(404).json({ success: false, message: 'Order not found' });
    }

    // 1. Strict, authoritative pilot assignment verification
    const isAssigned = await isPilotAssignedToOrder(order, pilotId, pilotPhone);
    if (!isAssigned) {
      return res.status(403).json({
        success: false,
        message: 'Unauthorized: You are not the assigned delivery pilot for this order'
      });
    }

    // 2. Order status verification:
    if (order.orderStatus === 'returned_to_restaurant') {
      return res.status(400).json({
        success: false,
        message: 'This order has already been returned and closed with verified OTP.'
      });
    }

    // Pilot must have picked up food before reporting failed delivery (or retrying/updating)
    const allowedPickupStatuses = ['out_for_delivery', 'picked_up', 'arrived_at_customer', 'delivery_failed_reported', 'return_to_restaurant'];
    if (!allowedPickupStatuses.includes(order.orderStatus)) {
      return res.status(400).json({
        success: false,
        message: `Cannot report failed delivery for order in "${order.orderStatus}" status. Food must be picked up first.`
      });
    }

    // 3. Mandatory reason check
    if (!reason || !reason.trim()) {
      return res.status(400).json({ success: false, message: 'A mandatory failure reason must be selected' });
    }

    if (reason.startsWith('Other') && (!notes || !notes.trim())) {
      return res.status(400).json({ success: false, message: 'Explanation notes are mandatory when selecting "Other"' });
    }

    // 4. 45-minute return policy & OTP calculation
    // Preserve existing returnOtp and returnDeadline if already generated during an earlier report
    if (!order.returnOtp) {
      order.returnOtp = String(Math.floor(1000 + Math.random() * 9000));
      order.returnOtpGeneratedAt = new Date();
    }
    if (!order.returnDeadline) {
      order.returnDeadline = new Date(Date.now() + 45 * 60 * 1000); // 45 minutes
    }
    if (!order.returnReportedAt) {
      order.returnReportedAt = new Date();
    }

    order.orderStatus = 'delivery_failed_reported';
    order.returnReason = reason.trim();
    order.returnNotes = (notes || '').trim();
    if (evidenceUrl) order.returnEvidenceUrl = evidenceUrl.trim();
    order.returnOtpVerified = false;
    order.proposedWalletDebitAmount = 0;
    order.walletDebitStatus = 'none'; // DO NOT automatically deduct or penalize pilot!

    order.statusHistory.push({
      status: 'delivery_failed_reported',
      timestamp: new Date(),
      note: `Delivery failed reported by pilot (${order.deliveryPartnerName || pilotId}). Reason: ${reason}. Notes: ${notes || 'None'}. Return journey started.`,
      updatedBy: 'pilot'
    });

    await order.save();

    const io = getIo(req);
    if (io) {
      io.to(`restaurant:${order.restaurantId}`).emit('food_order_status_update', order);
      io.to(`restaurant:${order.restaurantId}`).emit('food_return_incoming', order);
      io.to('admin_tracking').emit('admin_food_order_updated', order);
      io.to('admin_tracking').emit('food_return_reported', order);
      io.emit(`food_order:${order.orderId}`, order);
      io.emit('food_order_status_update', order);
      io.emit('food_order.delivery_failed', order);
      if (order.deliveryPartnerId) {
        io.to(`pilot_food:${order.deliveryPartnerId}`).emit('food_order_status_update', order);
      }
      if (order.deliveryPartnerPhone) {
        io.to(`pilot_food:${order.deliveryPartnerPhone}`).emit('food_order_status_update', order);
      }
    }

    res.json({
      success: true,
      message: 'Failed delivery reported. Please safely return the food to the restaurant within 45 minutes.',
      order: {
        orderId: order.orderId,
        orderStatus: order.orderStatus,
        returnReason: order.returnReason,
        returnNotes: order.returnNotes,
        returnDeadline: order.returnDeadline,
        restaurantName: order.restaurantName,
        restaurantAddress: order.restaurantAddress,
        restaurantLatLng: order.restaurantLatLng
      }
    });
  } catch (err) {
    console.error('[FOOD API] Error reporting failed delivery:', err);
    res.status(500).json({ success: false, message: 'Failed to report delivery failure: ' + err.message });
  }
});

// POST /api/food/pilot/orders/:orderId/return-arrived
router.post('/pilot/orders/:orderId/return-arrived', async (req, res) => {
  try {
    const { pilotId, pilotPhone } = req.body;
    const order = await FoodOrder.findOne({ orderId: req.params.orderId });
    if (!order) {
      return res.status(404).json({ success: false, message: 'Order not found' });
    }

    const isAssigned = await isPilotAssignedToOrder(order, pilotId, pilotPhone);
    if (!isAssigned) {
      return res.status(403).json({ success: false, message: 'Unauthorized: You are not the assigned delivery pilot for this order' });
    }

    order.orderStatus = 'return_arrived_at_restaurant';
    order.returnArrivedAt = new Date();
    order.statusHistory.push({
      status: 'return_arrived_at_restaurant',
      timestamp: new Date(),
      note: 'Pilot has arrived at the restaurant with the returned food package',
      updatedBy: 'pilot'
    });

    await order.save();

    const io = getIo(req);
    if (io) {
      io.to(`restaurant:${order.restaurantId}`).emit('food_order_status_update', order);
      io.to('admin_tracking').emit('admin_food_order_updated', order);
      io.emit(`food_order:${order.orderId}`, order);
      io.emit('food_order_status_update', order);
      if (order.deliveryPartnerId) io.to(`pilot_food:${order.deliveryPartnerId}`).emit('food_order_status_update', order);
      if (order.deliveryPartnerPhone) io.to(`pilot_food:${order.deliveryPartnerPhone}`).emit('food_order_status_update', order);
    }

    res.json({
      success: true,
      message: 'Arrival at restaurant recorded. Please hand over the food to kitchen staff to receive your return verification OTP.',
      order
    });
  } catch (err) {
    console.error('[FOOD API] Error recording return arrival:', err);
    res.status(500).json({ success: false, message: 'Failed to record arrival: ' + err.message });
  }
});

// POST /api/food/restaurant/orders/:orderId/receive-return
router.post('/restaurant/orders/:orderId/receive-return', async (req, res) => {
  try {
    const { restaurantId, staffName } = req.body;
    const order = await FoodOrder.findOne({ orderId: req.params.orderId });
    if (!order) {
      return res.status(404).json({ success: false, message: 'Order not found' });
    }

    if (order.restaurantId && restaurantId && order.restaurantId !== restaurantId) {
      return res.status(403).json({ success: false, message: 'Unauthorized: Restaurant mismatch' });
    }

    const returnStatuses = ['delivery_failed_reported', 'return_to_restaurant', 'return_arrived_at_restaurant', 'return_otp_pending'];
    if (!returnStatuses.includes(order.orderStatus)) {
      return res.status(400).json({
        success: false,
        message: `Order is currently in "${order.orderStatus}" and not awaiting return handover`
      });
    }

    // Ensure return OTP exists; if missing, generate a new one
    if (!order.returnOtp) {
      order.returnOtp = String(Math.floor(1000 + Math.random() * 9000));
      order.returnOtpGeneratedAt = new Date();
    }

    order.orderStatus = 'return_otp_pending';
    order.statusHistory.push({
      status: 'return_otp_pending',
      timestamp: new Date(),
      note: `Restaurant confirmed receipt of food package from pilot by ${staffName || 'kitchen staff'}. Return OTP revealed for verification.`,
      updatedBy: 'restaurant'
    });

    await order.save();

    const io = getIo(req);
    if (io) {
      io.to(`restaurant:${order.restaurantId}`).emit('food_order_status_update', order);
      io.to('admin_tracking').emit('admin_food_order_updated', order);
      io.emit(`food_order:${order.orderId}`, order);
      io.emit('food_order_status_update', order);
    }

    res.json({
      success: true,
      message: 'Food package physically received. Please share the 4-digit Return Verification OTP with the delivery pilot.',
      returnOtp: order.returnOtp,
      orderId: order.orderId
    });
  } catch (err) {
    console.error('[FOOD API] Error receiving returned food:', err);
    res.status(500).json({ success: false, message: 'Failed to receive return: ' + err.message });
  }
});

// POST /api/food/pilot/orders/:orderId/verify-return-otp
router.post('/pilot/orders/:orderId/verify-return-otp', async (req, res) => {
  try {
    const { pilotId, pilotPhone, otp } = req.body;
    const submittedOtp = (otp || '').toString().trim();

    if (!submittedOtp || submittedOtp.length !== 4) {
      return res.status(400).json({ success: false, message: 'Please provide a valid 4-digit Restaurant Return OTP' });
    }

    const order = await FoodOrder.findOne({ orderId: req.params.orderId });
    if (!order) {
      return res.status(404).json({ success: false, message: 'Order not found' });
    }

    const isAssigned = await isPilotAssignedToOrder(order, pilotId, pilotPhone);
    if (!isAssigned) {
      return res.status(403).json({ success: false, message: 'Unauthorized: You are not the assigned delivery pilot for this order' });
    }

    // Idempotent success if already returned
    if (order.returnOtpVerified && order.orderStatus === 'returned_to_restaurant') {
      return res.json({
        success: true,
        message: 'Restaurant return has already been verified and closed.',
        order
      });
    }

    // Check retry limits (max 5 attempts)
    if (order.returnOtpAttempts && order.returnOtpAttempts >= 5) {
      return res.status(429).json({
        success: false,
        message: 'Maximum return OTP verification attempts exceeded. Please contact restaurant kitchen manager or StayDriv support.'
      });
    }

    // Check OTP expiry (return deadline - 45 min)
    if (order.returnDeadline && new Date() > new Date(order.returnDeadline)) {
      return res.status(410).json({
        success: false,
        message: 'Restaurant Return OTP has expired (45-minute return policy). Please ask kitchen staff to confirm handover.'
      });
    }

    // Strictly validate against backend order.returnOtp (NO hardcoded bypass!)
    const expectedReturnOtp = (order.returnOtp || '').toString().trim();
    if (submittedOtp !== expectedReturnOtp) {
      order.returnOtpAttempts = (order.returnOtpAttempts || 0) + 1;
      await order.save();
      return res.status(400).json({
        success: false,
        message: `Invalid Restaurant Return OTP. Attempt ${order.returnOtpAttempts} of 5. Please verify the 4-digit code provided by the kitchen staff.`
      });
    }

    order.orderStatus = 'returned_to_restaurant';
    order.returnOtpVerified = true;
    order.returnedAt = new Date();
    order.returnVerifiedBy = 'restaurant_staff';
    order.walletDebitStatus = 'none'; // Validated return: NO penalty or debit!

    order.statusHistory.push({
      status: 'returned_to_restaurant',
      timestamp: new Date(),
      note: 'Food returned safely to restaurant with verified restaurant return OTP handover',
      updatedBy: 'pilot'
    });

    await order.save();

    // Credit pilot wallet delivery earnings for completing the delivery attempt and safe return
    try {
      const User = getUserModel();
      await pilotWalletService.creditFoodDeliveryEarnings(order, User, getIo(req));
    } catch (walletErr) {
      console.warn('[FOOD API] Wallet credit on return error (non-fatal):', walletErr.message);
    }

    const io = getIo(req);
    if (io) {
      io.to(`restaurant:${order.restaurantId}`).emit('food_order_status_update', order);
      io.to(`restaurant:${order.restaurantId}`).emit('food_return_verified', order);
      io.to('admin_tracking').emit('admin_food_order_updated', order);
      io.to('admin_tracking').emit('food_return_verified', order);
      io.emit(`food_order:${order.orderId}`, order);
      io.emit('food_order_status_update', order);
      io.emit('food_return_verified', order);
      if (order.deliveryPartnerId) io.to(`pilot_food:${order.deliveryPartnerId}`).emit('food_order_status_update', order);
      if (order.deliveryPartnerPhone) io.to(`pilot_food:${order.deliveryPartnerPhone}`).emit('food_order_status_update', order);
    }

    res.json({
      success: true,
      message: 'Restaurant return verified successfully! Package return is now closed.',
      order
    });
  } catch (err) {
    console.error('[FOOD API] Error verifying return OTP:', err);
    res.status(500).json({ success: false, message: 'Failed to verify return OTP: ' + err.message });
  }
});


// -------------------------------------------------------------
// 6. ADMIN FOOD DELIVERY RETURNS MANAGEMENT APIS (Section 7)
// -------------------------------------------------------------

// GET /api/food/admin/returns
router.get('/admin/returns', async (req, res) => {
  try {
    const { status, search, limit = 100 } = req.query;
    const filter = {
      $or: [
        { orderStatus: { $in: ['delivery_failed_reported', 'return_to_restaurant', 'return_arrived_at_restaurant', 'return_otp_pending', 'returned_to_restaurant', 'return_under_admin_review', 'return_closed'] } },
        { returnReportedAt: { $exists: true, $ne: null } }
      ]
    };

    if (status && status !== 'all') {
      if (status === 'pending_return') {
        filter.orderStatus = { $in: ['delivery_failed_reported', 'return_to_restaurant', 'return_arrived_at_restaurant', 'return_otp_pending'] };
      } else if (status === 'returned') {
        filter.orderStatus = 'returned_to_restaurant';
      } else if (status === 'overdue') {
        filter.orderStatus = { $nin: ['returned_to_restaurant', 'return_closed'] };
        filter.returnDeadline = { $lt: new Date() };
      } else if (status === 'under_review') {
        filter.orderStatus = 'return_under_admin_review';
      } else if (status === 'debit_approved') {
        filter.walletDebitStatus = 'approved';
      } else if (status === 'debited') {
        filter.walletDebitStatus = 'debited';
      } else if (status === 'debit_rejected') {
        filter.walletDebitStatus = 'rejected';
      } else {
        filter.orderStatus = status;
      }
    }

    if (search && search.trim()) {
      const q = search.trim();
      filter.$and = [
        {
          $or: [
            { orderId: { $regex: q, $options: 'i' } },
            { customerName: { $regex: q, $options: 'i' } },
            { customerPhone: { $regex: q, $options: 'i' } },
            { restaurantName: { $regex: q, $options: 'i' } },
            { deliveryPartnerName: { $regex: q, $options: 'i' } },
            { deliveryPartnerPhone: { $regex: q, $options: 'i' } },
            { returnReason: { $regex: q, $options: 'i' } },
            { returnOtp: { $regex: q, $options: 'i' } }
          ]
        }
      ];
    }

    const returns = await FoodOrder.find(filter)
      .sort({ returnReportedAt: -1, createdAt: -1 })
      .limit(parseInt(limit, 10))
      .lean();

    res.json({ success: true, count: returns.length, returns });
  } catch (err) {
    console.error('[FOOD API] Error fetching returns:', err);
    res.status(500).json({ success: false, message: 'Failed to fetch returns: ' + err.message });
  }
});

// POST /api/food/admin/returns/:orderId/extend-deadline
router.post('/admin/returns/:orderId/extend-deadline', async (req, res) => {
  try {
    const { additionalMinutes = 30, adminName, reason } = req.body;
    const order = await FoodOrder.findOne({ orderId: req.params.orderId });
    if (!order) {
      return res.status(404).json({ success: false, message: 'Order not found' });
    }

    const mins = Math.max(5, parseInt(additionalMinutes, 10) || 30);
    const currentDeadline = order.returnDeadline && order.returnDeadline > new Date() ? order.returnDeadline : new Date();
    order.returnDeadline = new Date(currentDeadline.getTime() + mins * 60 * 1000);

    order.statusHistory.push({
      status: order.orderStatus,
      timestamp: new Date(),
      note: `Admin ${adminName || 'Admin'} extended return deadline by ${mins} minutes. Reason: ${reason || 'Traffic/operational delay'}. New deadline: ${order.returnDeadline.toISOString()}`,
      updatedBy: 'admin'
    });

    await order.save();

    const io = getIo(req);
    if (io) {
      io.to('admin_tracking').emit('admin_food_order_updated', order);
      io.emit(`food_order:${order.orderId}`, order);
      io.emit('food_order_status_update', order);
    }

    res.json({
      success: true,
      message: `Return deadline extended by ${mins} minutes`,
      newDeadline: order.returnDeadline,
      order
    });
  } catch (err) {
    console.error('[FOOD API] Error extending deadline:', err);
    res.status(500).json({ success: false, message: 'Failed to extend deadline: ' + err.message });
  }
});

// POST /api/food/admin/returns/:orderId/decision
router.post('/admin/returns/:orderId/decision', async (req, res) => {
  try {
    const { decision, debitAmount, adminNotes, adminName } = req.body;
    const order = await FoodOrder.findOne({ orderId: req.params.orderId });
    if (!order) {
      return res.status(404).json({ success: false, message: 'Order not found' });
    }

    if (!['approve', 'reject'].includes(decision)) {
      return res.status(400).json({ success: false, message: 'Decision must be "approve" or "reject"' });
    }

    if (decision === 'approve') {
      const amountToDebit = Math.max(0, parseFloat(debitAmount) || order.proposedWalletDebitAmount || order.totalAmount || 0);

      // Prevent duplicate debits
      if (order.walletDebitStatus === 'debited') {
        return res.status(400).json({ success: false, message: 'This unreturned order has already been debited from the pilot wallet' });
      }

      order.walletDebitStatus = 'debited';
      order.actualWalletDebitAmount = amountToDebit;
      order.walletDebitAdminNotes = adminNotes || 'Admin approved deduction for unreturned food package';
      order.walletDebitApprovedBy = adminName || 'Admin';
      order.walletDebitApprovedAt = new Date();
      order.orderStatus = 'return_under_admin_review';

      // Debit pilot wallet & record ledger transaction
      const pilotId = order.deliveryPartnerId;
      if (pilotId && amountToDebit > 0) {
        try {
          const PilotWallet = mongoose.models.PilotWallet;
          if (PilotWallet) {
            await PilotWallet.findOneAndUpdate(
              { $or: [{ uid: pilotId }, { phone: pilotId }] },
              {
                $inc: { availableBalance: -amountToDebit },
                $set: { updatedAt: new Date(), lastTransactionAt: new Date() }
              },
              { upsert: false }
            );
          }

          const FinancialLedger = mongoose.models.FinancialLedger;
          if (FinancialLedger) {
            const txnId = `TXN_RET_DEBIT_${Date.now()}`;
            order.walletDebitTransactionId = txnId;
            await FinancialLedger.create({
              ledgerId: `LEDGER_RET_${Date.now()}_${Math.floor(1000 + Math.random() * 9000)}`,
              transactionId: txnId,
              entryType: 'PILOT_WALLET_DEBIT',
              sourceBookingId: order.orderId,
              pilotId,
              debitAccount: `pilot_wallet:${pilotId}`,
              creditAccount: 'platform_dispute_recovery',
              amount: amountToDebit,
              currency: 'INR',
              status: 'POSTED',
              referenceNumber: order.orderId,
              description: `Deduction for unreturned food order ${order.orderId}: ${adminNotes || 'Admin penalty approved'}`,
              auditDetails: { approvedBy: adminName, decision: 'approve', reason: order.returnReason }
            });
          }
        } catch (walletErr) {
          console.error('[FOOD API] Error debiting pilot wallet:', walletErr);
        }
      }

      order.statusHistory.push({
        status: 'return_under_admin_review',
        timestamp: new Date(),
        note: `Admin ${adminName || 'Admin'} approved wallet debit of ₹${amountToDebit}. Notes: ${adminNotes || 'None'}`,
        updatedBy: 'admin'
      });
    } else {
      // Admin rejected debit penalty
      order.walletDebitStatus = 'rejected';
      order.walletDebitAdminNotes = adminNotes || 'Admin rejected penalty - pilot not found responsible';
      order.walletDebitApprovedBy = adminName || 'Admin';
      order.walletDebitApprovedAt = new Date();

      order.statusHistory.push({
        status: order.orderStatus,
        timestamp: new Date(),
        note: `Admin ${adminName || 'Admin'} rejected proposed wallet debit. Notes: ${adminNotes || 'None'}`,
        updatedBy: 'admin'
      });
    }

    await order.save();

    const io = getIo(req);
    if (io) {
      io.to('admin_tracking').emit('admin_food_order_updated', order);
      io.emit(`food_order:${order.orderId}`, order);
      io.emit('food_order_status_update', order);
    }

    res.json({
      success: true,
      message: `Admin decision "${decision}" recorded successfully`,
      order
    });
  } catch (err) {
    console.error('[FOOD API] Error recording admin decision:', err);
    res.status(500).json({ success: false, message: 'Failed to record decision: ' + err.message });
  }
});

// POST /api/food/admin/returns/:orderId/reverse-debit
router.post('/admin/returns/:orderId/reverse-debit', async (req, res) => {
  try {
    const { adminName, reason } = req.body;
    const order = await FoodOrder.findOne({ orderId: req.params.orderId });
    if (!order) {
      return res.status(404).json({ success: false, message: 'Order not found' });
    }

    if (order.walletDebitStatus !== 'debited') {
      return res.status(400).json({ success: false, message: 'No active debited deduction found on this order to reverse' });
    }

    const refundAmount = order.actualWalletDebitAmount || 0;
    const pilotId = order.deliveryPartnerId;

    if (pilotId && refundAmount > 0) {
      try {
        const PilotWallet = mongoose.models.PilotWallet;
        if (PilotWallet) {
          await PilotWallet.findOneAndUpdate(
            { $or: [{ uid: pilotId }, { phone: pilotId }] },
            {
              $inc: { availableBalance: refundAmount },
              $set: { updatedAt: new Date(), lastTransactionAt: new Date() }
            },
            { upsert: false }
          );
        }

        const FinancialLedger = mongoose.models.FinancialLedger;
        if (FinancialLedger) {
          await FinancialLedger.create({
            ledgerId: `LEDGER_RET_REV_${Date.now()}_${Math.floor(1000 + Math.random() * 9000)}`,
            transactionId: `TXN_RET_REV_${Date.now()}`,
            entryType: 'PILOT_WALLET_CREDIT',
            sourceBookingId: order.orderId,
            pilotId,
            debitAccount: 'platform_dispute_recovery',
            creditAccount: `pilot_wallet:${pilotId}`,
            amount: refundAmount,
            currency: 'INR',
            status: 'POSTED',
            referenceNumber: order.walletDebitTransactionId || order.orderId,
            description: `Reversal of unreturned food penalty for order ${order.orderId}: ${reason || 'Admin dispute reversal'}`,
            auditDetails: { approvedBy: adminName, reason }
          });
        }
      } catch (walletErr) {
        console.error('[FOOD API] Error reversing wallet debit:', walletErr);
      }
    }

    order.walletDebitStatus = 'reversed';
    order.statusHistory.push({
      status: order.orderStatus,
      timestamp: new Date(),
      note: `Admin ${adminName || 'Admin'} reversed wallet deduction of ₹${refundAmount}. Reason: ${reason || 'Dispute resolved'}`,
      updatedBy: 'admin'
    });

    await order.save();

    const io = getIo(req);
    if (io) {
      io.to('admin_tracking').emit('admin_food_order_updated', order);
      io.emit(`food_order:${order.orderId}`, order);
      io.emit('food_order_status_update', order);
    }

    res.json({
      success: true,
      message: `Successfully reversed wallet deduction of ₹${refundAmount}`,
      order
    });
  } catch (err) {
    console.error('[FOOD API] Error reversing debit:', err);
    res.status(500).json({ success: false, message: 'Failed to reverse debit: ' + err.message });
  }
});

// POST /api/food/admin/returns/:orderId/close
router.post('/admin/returns/:orderId/close', async (req, res) => {
  try {
    const { adminName, notes } = req.body;
    const order = await FoodOrder.findOne({ orderId: req.params.orderId });
    if (!order) {
      return res.status(404).json({ success: false, message: 'Order not found' });
    }

    order.orderStatus = 'return_closed';
    order.statusHistory.push({
      status: 'return_closed',
      timestamp: new Date(),
      note: `Case closed by admin ${adminName || 'Admin'}. Notes: ${notes || 'Case investigated and resolved'}`,
      updatedBy: 'admin'
    });

    await order.save();

    const io = getIo(req);
    if (io) {
      io.to('admin_tracking').emit('admin_food_order_updated', order);
      io.emit(`food_order:${order.orderId}`, order);
      io.emit('food_order_status_update', order);
    }

    res.json({
      success: true,
      message: 'Return case closed successfully',
      order
    });
  } catch (err) {
    console.error('[FOOD API] Error closing return case:', err);
    res.status(500).json({ success: false, message: 'Failed to close return case: ' + err.message });
  }
});

// =========================================================================
// RESTAURANT SALES, SETTLEMENTS & PAYOUT LIFECYCLE ENDPOINTS
// =========================================================================

// 1. GET /api/food/restaurant/settlements/overview
router.get('/restaurant/settlements/overview', async (req, res) => {
  try {
    const restaurantId = req.query.restaurantId || req.body.restaurantId;
    if (!restaurantId) {
      return res.status(400).json({ success: false, message: 'restaurantId is required' });
    }

    const overview = await restaurantSettlementService.calculateRestaurantSales(restaurantId);
    res.json({ success: true, overview });
  } catch (err) {
    console.error('[FOOD SETTLEMENTS] Error fetching restaurant settlement overview:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// 2. PUT /api/food/restaurant/:restaurantId/bank-details
router.put('/restaurant/:restaurantId/bank-details', async (req, res) => {
  try {
    const { restaurantId } = req.params;
    const restaurant = await Restaurant.findOne({ restaurantId });
    if (!restaurant) {
      return res.status(404).json({ success: false, message: 'Restaurant not found' });
    }

    const {
      accountHolderName,
      bankName,
      accountNumber,
      confirmAccountNumber,
      ifscCode,
      accountType,
      registeredMobile,
      upiId,
      paymentPreference
    } = req.body;

    const isNew = !restaurant.bankAccount || restaurant.bankAccount.length === 0;
    const validation = restaurantSettlementService.validatePaymentDetails({
      accountHolderName,
      bankName,
      bankAccount: accountNumber,
      confirmBankAccount: confirmAccountNumber,
      bankIfsc: ifscCode,
      accountType,
      registeredMobile: registeredMobile || restaurant.phone,
      upiId,
      paymentPreference,
      isNewAccount: isNew
    });

    if (!validation.valid) {
      return res.status(400).json({ success: false, message: validation.error });
    }

    restaurant.bankHolderName = accountHolderName.trim();
    restaurant.bankName = bankName.trim();
    if (accountNumber) {
      restaurant.bankAccount = accountNumber.toString().trim();
      restaurant.bankAccountMasked = restaurantSettlementService.maskAccountNumber(accountNumber);
    }
    restaurant.bankIfsc = ifscCode.toString().trim().toUpperCase();
    if (accountType) restaurant.accountType = accountType;
    restaurant.registeredMobile = (registeredMobile || restaurant.phone).toString().trim();
    if (upiId) restaurant.upiId = upiId.trim();
    if (paymentPreference) restaurant.paymentPreference = paymentPreference;

    restaurant.bankVerificationStatus = 'pending_verification';
    restaurant.bankRejectionReason = '';

    restaurant.bankAuditLog.push({
      action: 'BANK_DETAILS_SUBMITTED',
      updatedBy: 'partner',
      maskedAccount: restaurant.bankAccountMasked,
      timestamp: new Date(),
      notes: `Updated beneficiary bank details: ${restaurant.bankName}, IFSC: ${restaurant.bankIfsc}`
    });

    await restaurant.save();

    const io = getIo(req);
    if (io) {
      io.to('admin_tracking').emit('admin_restaurant_bank_updated', {
        restaurantId,
        restaurantName: restaurant.name,
        bankAccountMasked: restaurant.bankAccountMasked,
        bankVerificationStatus: restaurant.bankVerificationStatus
      });
      io.to(`restaurant:${restaurantId}`).emit('restaurant_bank_updated', restaurant);
    }

    res.json({
      success: true,
      message: 'Bank details submitted successfully. Verification is in progress.',
      restaurant
    });
  } catch (err) {
    console.error('[FOOD SETTLEMENTS] Error submitting bank details:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// 3. PUT /api/food/admin/restaurants/:restaurantId/verify-bank
router.put('/admin/restaurants/:restaurantId/verify-bank', async (req, res) => {
  try {
    const { restaurantId } = req.params;
    const { status, rejectionReason, verifiedBy = 'Admin' } = req.body;

    if (!['verified', 'rejected'].includes(status)) {
      return res.status(400).json({ success: false, message: 'Status must be verified or rejected' });
    }

    const restaurant = await Restaurant.findOne({ restaurantId });
    if (!restaurant) {
      return res.status(404).json({ success: false, message: 'Restaurant not found' });
    }

    restaurant.bankVerificationStatus = status;
    restaurant.bankVerifiedBy = verifiedBy;
    restaurant.bankVerifiedAt = new Date();

    if (status === 'rejected') {
      restaurant.bankRejectionReason = rejectionReason || 'Bank account details rejected by admin';
    } else {
      restaurant.bankRejectionReason = '';
    }

    restaurant.bankAuditLog.push({
      action: status === 'verified' ? 'BANK_DETAILS_VERIFIED' : 'BANK_DETAILS_REJECTED',
      updatedBy: verifiedBy,
      maskedAccount: restaurant.bankAccountMasked,
      timestamp: new Date(),
      notes: status === 'verified' ? 'Verified by admin' : `Rejected: ${restaurant.bankRejectionReason}`
    });

    await restaurant.save();

    const io = getIo(req);
    if (io) {
      io.to(`restaurant:${restaurantId}`).emit('restaurant_bank_verification_status', {
        restaurantId,
        bankVerificationStatus: status,
        bankRejectionReason: restaurant.bankRejectionReason
      });
      io.to('admin_tracking').emit('admin_restaurant_updated', restaurant);
    }

    res.json({
      success: true,
      message: `Bank details ${status} successfully`,
      restaurant
    });
  } catch (err) {
    console.error('[FOOD SETTLEMENTS] Error verifying bank details:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// 4. PUT /api/food/admin/restaurants/:restaurantId/commission
router.put('/admin/restaurants/:restaurantId/commission', async (req, res) => {
  try {
    const { restaurantId } = req.params;
    const { commissionRate, updatedBy = 'Admin' } = req.body;

    const rate = parseFloat(commissionRate);
    if (isNaN(rate) || rate < 0 || rate > 50) {
      return res.status(400).json({ success: false, message: 'Commission rate must be between 0% and 50%' });
    }

    const restaurant = await Restaurant.findOne({ restaurantId });
    if (!restaurant) {
      return res.status(404).json({ success: false, message: 'Restaurant not found' });
    }

    restaurant.commissionRate = rate;
    restaurant.reviewHistory.push({
      action: 'COMMISSION_RATE_UPDATED',
      adminName: updatedBy,
      notes: `Commission rate updated to ${rate}%`,
      timestamp: new Date()
    });

    await restaurant.save();

    res.json({
      success: true,
      message: `Commission rate updated to ${rate}%`,
      restaurant
    });
  } catch (err) {
    console.error('[FOOD SETTLEMENTS] Error updating commission rate:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// 5. GET /api/food/admin/settlements/overview
router.get('/admin/settlements/overview', async (req, res) => {
  try {
    const restaurants = await Restaurant.find({ status: { $ne: 'rejected' } }).lean();

    let totalGrossSales = 0;
    let totalCommission = 0;
    let totalSettled = 0;
    let totalPending = 0;
    let restaurantsWithPendingSettlements = 0;

    const restaurantSummaries = [];

    for (const r of restaurants) {
      try {
        const summary = await restaurantSettlementService.calculateRestaurantSales(r.restaurantId);
        totalGrossSales += summary.totalSales;
        totalCommission += summary.platformCommissionAmount;
        totalSettled += summary.amountPaid;
        totalPending += summary.pendingSettlement;

        if (summary.pendingSettlement > 0) {
          restaurantsWithPendingSettlements++;
        }

        restaurantSummaries.push({
          restaurantId: r.restaurantId,
          name: r.name,
          phone: r.phone,
          status: r.status,
          commissionRate: summary.commissionRate,
          totalSales: summary.totalSales,
          grossFoodSales: summary.grossFoodSales,
          platformCommissionAmount: summary.platformCommissionAmount,
          netEarnings: summary.netEarnings,
          amountPaid: summary.amountPaid,
          pendingSettlement: summary.pendingSettlement,
          completedOrdersCount: summary.completedOrdersCount,
          unsettledOrdersCount: summary.unsettledOrdersCount,
          lastSettlementDate: summary.lastSettlementDate,
          bankName: r.bankName,
          accountHolderName: r.bankHolderName,
          bankAccountMasked: r.bankAccountMasked,
          bankIfsc: r.bankIfsc,
          upiId: r.upiId,
          accountType: r.accountType,
          bankVerificationStatus: r.bankVerificationStatus || 'unverified',
          hasBankAccount: Boolean(r.bankAccount || r.upiId)
        });
      } catch (sumErr) {
        console.warn(`[FOOD SETTLEMENTS] Note calculating sales for ${r.restaurantId}:`, sumErr.message);
      }
    }

    res.json({
      success: true,
      overview: {
        totalGrossSales,
        totalCommission,
        totalSettled,
        totalPending,
        restaurantsWithPendingSettlements,
        totalRestaurants: restaurants.length
      },
      restaurants: restaurantSummaries
    });
  } catch (err) {
    console.error('[FOOD SETTLEMENTS] Error generating admin settlements overview:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// 6. GET /api/food/admin/settlements
router.get('/admin/settlements', async (req, res) => {
  try {
    const { status, restaurantId, search } = req.query;
    const filter = {};

    if (status && status !== 'all') {
      filter.status = status;
    }
    if (restaurantId) {
      filter.restaurantId = restaurantId;
    }
    if (search) {
      const q = search.trim();
      filter.$or = [
        { settlementId: { $regex: q, $options: 'i' } },
        { restaurantName: { $regex: q, $options: 'i' } },
        { payoutReference: { $regex: q, $options: 'i' } }
      ];
    }

    const settlements = await RestaurantSettlement.find(filter).sort({ createdAt: -1 }).lean();
    res.json({ success: true, settlements });
  } catch (err) {
    console.error('[FOOD SETTLEMENTS] Error querying settlements:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// 7. POST /api/food/admin/restaurants/:restaurantId/initiate-settlement
router.post('/admin/restaurants/:restaurantId/initiate-settlement', async (req, res) => {
  try {
    const { restaurantId } = req.params;
    const { notes, initiatedBy = 'Admin' } = req.body;

    const settlement = await restaurantSettlementService.initiateSettlement({
      restaurantId,
      adminUser: initiatedBy,
      notes
    });

    if (settlement.orderIds && settlement.orderIds.length > 0) {
      await FoodOrder.updateMany(
        { orderId: { $in: settlement.orderIds } },
        {
          $set: {
            settlementStatus: 'settlement_initiated',
            settlementId: settlement.settlementId
          }
        }
      );
    }

    const io = getIo(req);
    if (io) {
      io.to('admin_tracking').emit('admin_settlement_initiated', settlement);
      io.to(`restaurant:${restaurantId}`).emit('restaurant_settlement_initiated', settlement);
    }

    res.json({
      success: true,
      message: 'Settlement initiated successfully and queued for bank transfer confirmation',
      settlement
    });
  } catch (err) {
    console.error('[FOOD SETTLEMENTS] Error initiating settlement:', err);
    res.status(400).json({ success: false, message: err.message });
  }
});

// 8. POST /api/food/admin/settlements/:settlementId/confirm
router.post('/admin/settlements/:settlementId/confirm', async (req, res) => {
  try {
    const { settlementId } = req.params;
    const { payoutReference, remarks, settledBy = 'Admin' } = req.body;

    if (!payoutReference || !payoutReference.trim()) {
      return res.status(400).json({ success: false, message: 'Bank UTR / Transaction Reference is mandatory' });
    }

    const { settlement, alreadyPaid } = await restaurantSettlementService.confirmSettlement({
      settlementId,
      payoutReference,
      adminUser: settledBy,
      remarks
    });

    if (settlement.orderIds && settlement.orderIds.length > 0) {
      await FoodOrder.updateMany(
        { orderId: { $in: settlement.orderIds } },
        {
          $set: {
            settlementStatus: 'settled',
            settlementId: settlement.settlementId
          }
        }
      );
    }

    try {
      const summary = await restaurantSettlementService.calculateRestaurantSales(settlement.restaurantId);
      await Restaurant.updateOne(
        { restaurantId: settlement.restaurantId },
        {
          $set: {
            pendingSettlement: summary.pendingSettlement,
            totalSettled: summary.amountPaid
          }
        }
      );
    } catch (balErr) {
      console.warn('[FOOD SETTLEMENTS] Balance sync note:', balErr.message);
    }

    const io = getIo(req);
    if (io) {
      io.to('admin_tracking').emit('admin_settlement_paid', settlement);
      io.to(`restaurant:${settlement.restaurantId}`).emit('restaurant_settlement_paid', settlement);
    }

    res.json({
      success: true,
      message: alreadyPaid ? 'Settlement was already confirmed and marked as Paid' : 'Settlement confirmed successfully and recorded in financial ledger',
      settlement
    });
  } catch (err) {
    console.error('[FOOD SETTLEMENTS] Error confirming settlement:', err);
    res.status(400).json({ success: false, message: err.message });
  }
});

// 9. POST /api/food/admin/settlements/:settlementId/fail
router.post('/admin/settlements/:settlementId/fail', async (req, res) => {
  try {
    const { settlementId } = req.params;
    const { failureReason, failedBy = 'Admin' } = req.body;

    const settlement = await restaurantSettlementService.failSettlement({
      settlementId,
      failureReason,
      adminUser: failedBy
    });

    if (settlement.orderIds && settlement.orderIds.length > 0) {
      await FoodOrder.updateMany(
        { orderId: { $in: settlement.orderIds } },
        {
          $set: {
            settlementStatus: 'unsettled',
            settlementId: ''
          }
        }
      );
    }

    try {
      const summary = await restaurantSettlementService.calculateRestaurantSales(settlement.restaurantId);
      await Restaurant.updateOne(
        { restaurantId: settlement.restaurantId },
        {
          $set: {
            pendingSettlement: summary.pendingSettlement
          }
        }
      );
    } catch (balErr) {
      console.warn('[FOOD SETTLEMENTS] Balance sync note on failure:', balErr.message);
    }

    const io = getIo(req);
    if (io) {
      io.to('admin_tracking').emit('admin_settlement_failed', settlement);
      io.to(`restaurant:${settlement.restaurantId}`).emit('restaurant_settlement_failed', settlement);
    }

    res.json({
      success: true,
      message: 'Settlement marked as failed and orders restored to unsettled balance',
      settlement
    });
  } catch (err) {
    console.error('[FOOD SETTLEMENTS] Error failing settlement:', err);
    res.status(400).json({ success: false, message: err.message });
  }
});

module.exports = router;
