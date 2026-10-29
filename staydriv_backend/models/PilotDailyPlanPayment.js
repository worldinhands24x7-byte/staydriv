const mongoose = require('mongoose');

const pilotDailyPlanPaymentSchema = new mongoose.Schema({
  pilotId: { type: String, required: true, index: true },
  pilotName: { type: String, default: 'Pilot Partner' },
  pilotPhone: { type: String, required: true, index: true },
  vehicleType: { type: String, default: 'Bike' },
  amount: { type: Number, default: 20 },
  currency: { type: String, default: 'INR' },
  paymentStatus: {
    type: String,
    enum: ['paid', 'pending', 'failed', 'expired'],
    default: 'paid',
    index: true
  },
  transactionId: { type: String, required: true, unique: true, index: true },
  gatewayPaymentId: { type: String, default: '' },
  gatewayOrderId: { type: String, default: '' },
  paymentMethod: { type: String, default: 'UPI' },
  paidAt: { type: Date, default: Date.now, index: true },
  expiresAt: { type: Date, required: true, index: true },
  bookingAccessStatus: {
    type: String,
    enum: ['enabled', 'disabled'],
    default: 'disabled',
    index: true
  },
  dutyStatus: {
    type: String,
    enum: ['DUTY ON', 'DUTY OFF', 'ON', 'OFF'],
    default: 'DUTY OFF',
    index: true
  },
  adminStartStopStatus: {
    type: String,
    enum: ['START', 'STOP', 'DUTY_ON', 'DUTY_OFF', 'NONE'],
    default: 'NONE'
  },
  adminReason: { type: String, default: '' },
  adminUpdatedBy: { type: String, default: '' },
  adminUpdatedAt: { type: Date },
  auditHistory: [{
    action: { type: String, enum: ['DUTY_ON', 'DUTY_OFF', 'PAYMENT_RECEIVED', 'EXPIRED', 'START_BOOKING', 'STOP_BOOKING', 'ADMIN_OVERRIDE'] },
    changedBy: { type: String, default: 'SYSTEM' },
    reason: { type: String, default: '' },
    timestamp: { type: Date, default: Date.now }
  }],
  notes: { type: String, default: '₹20 Daily Plan - 100% Ride & Food Earnings' }
}, {
  timestamps: true
});

pilotDailyPlanPaymentSchema.index({ pilotPhone: 1, paymentStatus: 1, expiresAt: -1 });
pilotDailyPlanPaymentSchema.index({ paidAt: -1 });

module.exports = mongoose.models.PilotDailyPlanPayment || mongoose.model('PilotDailyPlanPayment', pilotDailyPlanPaymentSchema);
