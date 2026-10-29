const mongoose = require('mongoose');

const customerFoodMembershipSchema = new mongoose.Schema({
  membershipId: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  customerId: {
    type: String,
    required: true,
    index: true
  },
  customerPhone: {
    type: String,
    required: true,
    index: true
  },
  customerName: {
    type: String,
    default: 'Customer'
  },
  planId: {
    type: String,
    required: true,
    index: true
  },
  planType: {
    type: String,
    enum: ['monthly', 'quarterly', 'platinum'],
    required: true
  },
  planName: {
    type: String,
    required: true
  },
  planVersion: {
    type: Number,
    default: 1
  },
  // Immutable snapshot of plan benefits and terms at time of purchase, preserving grandfathered terms
  planSnapshot: {
    type: mongoose.Schema.Types.Mixed,
    required: true
  },
  pricePaid: {
    type: Number,
    required: true,
    min: 0
  },
  status: {
    type: String,
    enum: ['active', 'expired', 'cancelled', 'pending'],
    default: 'pending',
    index: true
  },
  startDate: {
    type: Date
  },
  endDate: {
    type: Date,
    index: true
  },
  validityDays: {
    type: Number,
    required: true
  },
  paymentStatus: {
    type: String,
    enum: ['pending', 'paid', 'failed', 'refunded'],
    default: 'pending',
    index: true
  },
  paymentMethod: {
    type: String,
    default: 'razorpay'
  },
  transactionId: {
    type: String,
    default: '',
    index: true
  },
  gatewayOrderId: {
    type: String,
    default: '',
    index: true
  },
  gatewayPaymentId: {
    type: String,
    default: ''
  },
  gatewaySignature: {
    type: String,
    default: ''
  },
  // Total cumulative discounts availed across all food orders under this membership
  totalDiscountAvailed: {
    type: Number,
    default: 0
  },
  ordersCount: {
    type: Number,
    default: 0
  },
  autoRenew: {
    type: Boolean,
    default: false
  },
  renewalCount: {
    type: Number,
    default: 0
  },
  renewalHistory: [
    {
      renewedAt: { type: Date, default: Date.now },
      previousEndDate: Date,
      newEndDate: Date,
      pricePaid: Number,
      transactionId: String
    }
  ],
  cancelledAt: {
    type: Date
  },
  cancellationReason: {
    type: String,
    default: ''
  },
  cancelledBy: {
    type: String,
    default: ''
  },
  refundAmount: {
    type: Number,
    default: 0
  },
  refundStatus: {
    type: String,
    enum: ['none', 'requested', 'processed', 'rejected'],
    default: 'none'
  },
  createdAt: {
    type: Date,
    default: Date.now,
    index: true
  },
  updatedAt: {
    type: Date,
    default: Date.now
  }
});

// Helper virtual to check if active
customerFoodMembershipSchema.virtual('isCurrentlyActive').get(function() {
  if (this.status !== 'active') return false;
  if (!this.endDate) return false;
  return new Date() <= new Date(this.endDate);
});

customerFoodMembershipSchema.pre('save', function(next) {
  this.updatedAt = new Date();
  if (this.endDate && this.status === 'active' && new Date() > new Date(this.endDate)) {
    this.status = 'expired';
  }
  if (typeof next === 'function') next();
});

module.exports = mongoose.models.CustomerFoodMembership || mongoose.model('CustomerFoodMembership', customerFoodMembershipSchema);
