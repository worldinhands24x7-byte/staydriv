const mongoose = require('mongoose');

const foodMembershipAuditLogSchema = new mongoose.Schema({
  auditId: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  action: {
    type: String,
    required: true,
    enum: [
      'PLAN_CREATED',
      'PLAN_UPDATED',
      'PRICE_CHANGED',
      'BENEFIT_ADDED',
      'BENEFIT_UPDATED',
      'BENEFIT_REMOVED',
      'BENEFIT_TOGGLED',
      'PLAN_PUBLISHED',
      'MEMBERSHIP_ACTIVATED',
      'MEMBERSHIP_RENEWED',
      'MEMBERSHIP_CANCELLED',
      'MEMBERSHIP_REFUNDED'
    ],
    index: true
  },
  adminId: {
    type: String,
    default: 'admin'
  },
  adminName: {
    type: String,
    default: 'Administrator'
  },
  planId: {
    type: String,
    default: '',
    index: true
  },
  planType: {
    type: String,
    default: ''
  },
  membershipId: {
    type: String,
    default: '',
    index: true
  },
  details: {
    type: String,
    default: ''
  },
  previousState: {
    type: mongoose.Schema.Types.Mixed
  },
  newState: {
    type: mongoose.Schema.Types.Mixed
  },
  ipAddress: {
    type: String,
    default: ''
  },
  createdAt: {
    type: Date,
    default: Date.now,
    index: true
  }
});

module.exports = mongoose.models.FoodMembershipAuditLog || mongoose.model('FoodMembershipAuditLog', foodMembershipAuditLogSchema);
