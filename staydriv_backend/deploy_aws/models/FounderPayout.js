const mongoose = require('mongoose');

const founderPayoutSchema = new mongoose.Schema({
  payoutId: { type: String, required: true, unique: true, index: true },
  amount: { type: Number, required: true },
  beneficiaryName: { type: String, required: true },
  destinationBank: { type: String, required: true },
  accountNumberMasked: { type: String, required: true },
  ifsc: { type: String, required: true },
  paymentReference: { type: String, default: '' },
  status: {
    type: String,
    enum: ['PENDING_AUTHORIZATION', 'APPROVED', 'PROCESSING', 'SETTLED', 'REJECTED'],
    default: 'APPROVED'
  },
  financialPeriod: { type: String, default: '' },
  availableCashBalanceAtDistribution: { type: Number, default: 0 },
  authorizedBy: { type: String, required: true },
  authorizationReason: { type: String, required: true },
  legalDocumentRef: { type: String, default: '' },
  notes: { type: String, default: '' },
  settlementDate: { type: Date, default: Date.now },
  auditTrail: [{
    action: String,
    performedBy: String,
    timestamp: { type: Date, default: Date.now },
    notes: String
  }],
  createdAt: { type: Date, default: Date.now }
});

module.exports = mongoose.models.FounderPayout || mongoose.model('FounderPayout', founderPayoutSchema);
