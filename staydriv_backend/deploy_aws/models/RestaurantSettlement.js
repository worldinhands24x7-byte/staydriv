const mongoose = require('mongoose');

const restaurantSettlementSchema = new mongoose.Schema({
  settlementId: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  restaurantId: {
    type: String,
    required: true,
    index: true
  },
  restaurantName: {
    type: String,
    required: true
  },
  periodStart: {
    type: Date,
    default: Date.now
  },
  periodEnd: {
    type: Date,
    default: Date.now
  },
  orderIds: {
    type: [String],
    default: []
  },
  ordersCount: {
    type: Number,
    default: 0
  },
  grossSales: {
    type: Number,
    required: true,
    min: 0
  },
  totalCommission: {
    type: Number,
    required: true,
    min: 0
  },
  commissionRate: {
    type: Number,
    default: 15.0
  },
  totalAdjustments: {
    type: Number,
    default: 0
  },
  netPayable: {
    type: Number,
    required: true,
    min: 0
  },
  amountPaid: {
    type: Number,
    default: 0
  },
  status: {
    type: String,
    enum: ['pending', 'processing', 'paid', 'failed'],
    default: 'pending',
    index: true
  },
  paymentMethod: {
    type: String,
    enum: ['bank_transfer', 'upi'],
    default: 'bank_transfer'
  },
  bankDetails: {
    accountHolderName: { type: String, default: '' },
    bankName: { type: String, default: '' },
    accountNumberMasked: { type: String, default: '' },
    ifscCode: { type: String, default: '' },
    accountType: { type: String, default: 'Current' },
    upiId: { type: String, default: '' },
    registeredMobile: { type: String, default: '' }
  },
  payoutProvider: {
    type: String,
    default: 'manual_bank_transfer' // 'manual_bank_transfer', 'razorpayx'
  },
  payoutReference: {
    type: String,
    default: '',
    index: true
  },
  failureReason: {
    type: String,
    default: ''
  },
  initiatedBy: {
    type: String,
    default: 'admin'
  },
  initiatedAt: {
    type: Date,
    default: Date.now
  },
  settledAt: {
    type: Date
  },
  settledBy: {
    type: String,
    default: ''
  },
  notes: {
    type: String,
    default: ''
  },
  auditLog: [
    {
      action: { type: String, required: true },
      actor: { type: String, default: 'system' },
      timestamp: { type: Date, default: Date.now },
      note: { type: String, default: '' }
    }
  ],
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

restaurantSettlementSchema.pre('save', function (next) {
  this.updatedAt = new Date();
  if (typeof next === 'function') next();
});

module.exports = mongoose.models.RestaurantSettlement || mongoose.model('RestaurantSettlement', restaurantSettlementSchema);
