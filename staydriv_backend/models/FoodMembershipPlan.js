const mongoose = require('mongoose');

const benefitSchema = new mongoose.Schema({
  benefitId: {
    type: String,
    required: true
  },
  title: {
    type: String,
    required: true
  },
  description: {
    type: String,
    default: ''
  },
  icon: {
    type: String,
    default: 'percent'
  },
  type: {
    type: String,
    enum: ['discount_percentage', 'fixed_discount', 'free_delivery', 'restaurant_special'],
    required: true
  },
  value: {
    type: Number,
    required: true,
    min: 0
  },
  minimumOrderValue: {
    type: Number,
    default: 0,
    min: 0
  },
  maxDiscountLimit: {
    type: Number,
    default: 0, // 0 means uncapped
    min: 0
  },
  eligibleRestaurantIds: {
    type: [String],
    default: [] // empty means all participating restaurants
  },
  eligibleItemCategories: {
    type: [String],
    default: [] // empty means all item categories
  },
  usageLimitPerDay: {
    type: Number,
    default: 0 // 0 means unlimited
  },
  usageLimitPerMonth: {
    type: Number,
    default: 0
  },
  fundedBy: {
    type: String,
    enum: ['staydriv', 'restaurant', 'split'],
    default: 'staydriv'
  },
  staydrivSharePercent: {
    type: Number,
    default: 100,
    min: 0,
    max: 100
  },
  restaurantSharePercent: {
    type: Number,
    default: 0,
    min: 0,
    max: 100
  },
  isEnabled: {
    type: Boolean,
    default: true
  }
}, { _id: false });

const foodMembershipPlanSchema = new mongoose.Schema({
  planId: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  // STRICT CONSTRAINT: Only 'monthly' and 'quarterly' are permitted. Never annual.
  planType: {
    type: String,
    required: true,
    enum: ['monthly', 'quarterly', 'platinum'],
    index: true
  },
  name: {
    type: String,
    required: true,
    trim: true
  },
  tagline: {
    type: String,
    default: 'Exclusive savings on Food Order Now'
  },
  description: {
    type: String,
    default: ''
  },
  price: {
    type: Number,
    required: true,
    min: 0
  },
  originalPrice: {
    type: Number,
    default: 0,
    min: 0
  },
  currency: {
    type: String,
    default: 'INR'
  },
  validityDays: {
    type: Number,
    required: true,
    min: 1
  },
  validityMonths: {
    type: Number,
    required: true,
    default: 3
  },
  minOrderAmount: {
    type: Number,
    default: 99
  },
  deliveryRadiusKm: {
    type: Number,
    default: 7
  },
  maxDiscountPercent: {
    type: Number,
    default: 30
  },
  participatingRestaurantIds: {
    type: [String],
    default: []
  },
  excludedRestaurantIds: {
    type: [String],
    default: []
  },
  benefits: {
    type: [benefitSchema],
    default: []
  },
  termsAndConditions: {
    type: [String],
    default: [
      'Applies exclusively to StayDriv Food Order Now orders.',
      'Does not apply to bike rides, auto rides, car rides, round trips, or any ride services.',
      'Discounts apply only at participating restaurant partners.',
      'Benefits are subject to configured minimum order values and maximum discount caps.',
      'Non-transferable and non-refundable once activated.'
    ]
  },
  isActive: {
    type: Boolean,
    default: true,
    index: true
  },
  isArchived: {
    type: Boolean,
    default: false,
    index: true
  },
  archivedAt: {
    type: Date
  },
  isPublished: {
    type: Boolean,
    default: true,
    index: true
  },
  draftPrice: {
    type: Number
  },
  draftOriginalPrice: {
    type: Number
  },
  draftValidityDays: {
    type: Number
  },
  version: {
    type: Number,
    default: 1
  },
  versionHistory: [
    {
      version: Number,
      price: Number,
      validityDays: Number,
      benefits: [benefitSchema],
      publishedAt: { type: Date, default: Date.now },
      publishedBy: { type: String, default: 'admin' },
      changeSummary: String
    }
  ],
  publishedAt: {
    type: Date,
    default: Date.now
  },
  updatedBy: {
    type: String,
    default: 'admin'
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

foodMembershipPlanSchema.pre('save', function(next) {
  this.updatedAt = new Date();
  if (typeof next === 'function') next();
});

module.exports = mongoose.models.FoodMembershipPlan || mongoose.model('FoodMembershipPlan', foodMembershipPlanSchema);
