const mongoose = require('mongoose');
const FoodCoupon = require('../models/FoodCoupon');

async function seed() {
  await mongoose.connect('mongodb://127.0.0.1:27017/staydriv');
  console.log('[Seed] Connected to MongoDB');

  const count = await FoodCoupon.countDocuments();
  if (count === 0) {
    await FoodCoupon.insertMany([
      {
        code: 'TAKEOFF50ON99',
        title: "Save ₹69.50 with 'TAKEOFF50ON99'",
        description: '50% OFF up to ₹70 on food orders above ₹99',
        discountType: 'percentage',
        discountValue: 50,
        minOrderAmount: 99,
        maxDiscountAmount: 70,
        freeDelivery: false,
        isActive: true,
        validTill: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000)
      },
      {
        code: 'NEWMEAL',
        title: 'Restaurant Coupon - (NEWMEAL)',
        description: 'Flat ₹100 OFF on delicious meals above ₹149',
        discountType: 'flat',
        discountValue: 100,
        minOrderAmount: 149,
        maxDiscountAmount: 100,
        freeDelivery: false,
        isActive: true,
        validTill: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000)
      },
      {
        code: 'STAYDRIV50',
        title: '50% OFF up to ₹100',
        description: 'Exclusive 50% discount on StayDriv Food Order Now',
        discountType: 'percentage',
        discountValue: 50,
        minOrderAmount: 120,
        maxDiscountAmount: 100,
        freeDelivery: false,
        isActive: true,
        validTill: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000)
      },
      {
        code: 'FREEDEL',
        title: 'Free Delivery Special',
        description: '100% off on delivery partner charges on orders above ₹99',
        discountType: 'free_delivery',
        discountValue: 0,
        minOrderAmount: 99,
        maxDiscountAmount: 0,
        freeDelivery: true,
        isActive: true,
        validTill: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000)
      }
    ]);
    console.log('[Seed] Successfully seeded 4 default food coupons');
  } else {
    console.log('[Seed] Food coupons already present, count:', count);
  }

  await mongoose.disconnect();
}

seed().catch(err => {
  console.error('[Seed Error]:', err);
  process.exit(1);
});
