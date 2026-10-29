const mongoose = require('mongoose');

const foodConfigSchema = new mongoose.Schema({
  configId: {
    type: String,
    default: 'staydriv_food_config',
    unique: true
  },
  platformFee: {
    type: Number,
    default: 15
  },
  discountedPlatformFee: {
    type: Number,
    default: 9 // as in reference screenshot: ~~₹14.90~~ ₹9
  },
  deliveryBaseFee: {
    type: Number,
    default: 30
  },
  deliveryBaseKm: {
    type: Number,
    default: 1.0 // Base km covered by base fee (e.g. 1.0 km or up to 3 km)
  },
  deliveryPerKmFee: {
    type: Number,
    default: 10 // Fee per km beyond base km
  },
  minDeliveryFee: {
    type: Number,
    default: 25 // Minimum delivery fee floor
  },
  maxDeliveryFee: {
    type: Number,
    default: 150 // Maximum delivery fee cap
  },
  freeDeliveryThreshold: {
    type: Number,
    default: 0 // 0 = disabled, or order amount for free delivery
  },
  defaultPackagingFee: {
    type: Number,
    default: 10
  },
  taxRatePercent: {
    type: Number,
    default: 5.0
  },
  defaultCommissionRate: {
    type: Number,
    default: 15.0
  },
  cashRoundingEnabled: {
    type: Boolean,
    default: true
  },
  minOrderAmount: {
    type: Number,
    default: 0
  },
  categories: {
    type: [String],
    default: [
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
    ]
  },
  updatedAt: {
    type: Date,
    default: Date.now
  }
});

module.exports = mongoose.models.FoodConfig || mongoose.model('FoodConfig', foodConfigSchema);
