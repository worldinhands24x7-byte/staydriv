const mongoose = require('mongoose');

const foodMembershipTransactionSchema = new mongoose.Schema({
  transactionId: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  membershipId: {
    type: String,
    required: true,
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
  planId: {
    type: String,
    required: true
  },
  planType: {
    type: String,
    enum: ['monthly', 'quarterly', 'platinum'],
    required: true
  },
  amount: {
    type: Number,
    required: true,
    min: 0
  },
  currency: {
    type: String,
    default: 'INR'
  },
  gateway: {
    type: String,
    default: 'razorpay'
  },
  gatewayOrderId: {
    type: String,
    default: '',
    index: true
  },
  gatewayPaymentId: {
    type: String,
    default: '',
    index: true
  },
  gatewaySignature: {
    type: String,
    default: ''
  },
  paymentStatus: {
    type: String,
    enum: ['created', 'pending', 'success', 'failed', 'refunded'],
    default: 'created',
    index: true
  },
  // Idempotency key ensures duplicate webhook callbacks or repeat requests cannot double-charge or double-activate
  idempotencyKey: {
    type: String,
    unique: true,
    sparse: true,
    index: true
  },
  failureReason: {
    type: String,
    default: ''
  },
  refundId: {
    type: String,
    default: ''
  },
  refundAmount: {
    type: Number,
    default: 0
  },
  refundedAt: {
    type: Date
  },
  metadata: {
    type: mongoose.Schema.Types.Mixed,
    default: {}
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

foodMembershipTransactionSchema.pre('save', function(next) {
  this.updatedAt = new Date();
  if (typeof next === 'function') next();
});

module.exports = mongoose.models.FoodMembershipTransaction || mongoose.model('FoodMembershipTransaction', foodMembershipTransactionSchema);
