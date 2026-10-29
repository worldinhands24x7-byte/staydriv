const mongoose = require('mongoose');

const foodCouponSchema = new mongoose.Schema({
  code: {
    type: String,
    required: true,
    unique: true,
    uppercase: true,
    trim: true,
    index: true
  },
  title: {
    type: String,
    required: true
  },
  description: {
    type: String,
    default: ''
  },
  discountType: {
    type: String,
    enum: ['percentage', 'flat', 'free_delivery'],
    default: 'percentage'
  },
  discountValue: {
    type: Number,
    required: true,
    min: 0
  },
  minOrderAmount: {
    type: Number,
    default: 0,
    min: 0
  },
  maxDiscountAmount: {
    type: Number,
    default: 0, // 0 means uncapped
    min: 0
  },
  freeDelivery: {
    type: Boolean,
    default: false
  },
  restaurantId: {
    type: String,
    default: '', // empty means applicable to all partner restaurants
    index: true
  },
  fundedBy: {
    type: String,
    enum: ['staydriv', 'restaurant', 'split'],
    default: 'staydriv'
  },
  usageLimitTotal: {
    type: Number,
    default: 0 // 0 means unlimited
  },
  usageLimitPerUser: {
    type: Number,
    default: 5
  },
  timesUsed: {
    type: Number,
    default: 0
  },
  validFrom: {
    type: Date,
    default: Date.now
  },
  validTill: {
    type: Date,
    default: () => new Date(Date.now() + 180 * 24 * 60 * 60 * 1000) // 6 months default
  },
  isActive: {
    type: Boolean,
    default: true,
    index: true
  },
  createdAt: {
    type: Date,
    default: Date.now
  },
  updatedAt: {
    type: Date,
    default: Date.now
  }
});

foodCouponSchema.pre('save', function (next) {
  this.updatedAt = new Date();
  if (typeof next === 'function') next();
});

module.exports = mongoose.models.FoodCoupon || mongoose.model('FoodCoupon', foodCouponSchema);
