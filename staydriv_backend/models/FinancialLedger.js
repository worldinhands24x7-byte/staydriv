const mongoose = require('mongoose');

const financialLedgerSchema = new mongoose.Schema({
  ledgerId: { type: String, required: true, unique: true, index: true },
  transactionId: { type: String, required: true, index: true },
  entryType: {
    type: String,
    required: true,
    enum: [
      'BOOKING_FARE_REVENUE',
      'PLATFORM_COMMISSION',
      'PILOT_FARE_EARNING',
      'PILOT_WALLET_CREDIT',
      'PILOT_WALLET_DEBIT',
      'WITHDRAWAL_RESERVE',
      'WITHDRAWAL_PAYOUT',
      'WITHDRAWAL_REVERSAL',
      'CUSTOMER_REFUND',
      'GATEWAY_FEE',
      'TAX_LIABILITY',
      'COMPANY_BANK_SETTLEMENT',
      'FOUNDER_DISTRIBUTION',
      'OPERATING_EXPENSE',
      'MANUAL_ADJUSTMENT',
      'PILOT_FOOD_DELIVERY_EARNING',
      'PLATFORM_FUNDED_DELIVERY_EXPENSE',
      'RESTAURANT_FOOD_SALES_CREDIT',
      'RESTAURANT_PLATFORM_COMMISSION',
      'RESTAURANT_PAYOUT_SETTLEMENT',
      'RESTAURANT_PAYOUT_REVERSAL'
    ]
  },
  sourceBookingId: { type: String, default: null, index: true },
  withdrawalId: { type: String, default: null, index: true },
  paymentId: { type: String, default: null, index: true },
  pilotId: { type: String, default: null, index: true },
  customerId: { type: String, default: null, index: true },
  restaurantId: { type: String, default: null, index: true },
  settlementId: { type: String, default: null, index: true },
  debitAccount: { type: String, required: true },
  creditAccount: { type: String, required: true },
  amount: { type: Number, required: true },
  currency: { type: String, default: 'INR' },
  status: {
    type: String,
    enum: ['POSTED', 'REVERSED', 'PENDING_SETTLEMENT', 'RESERVED', 'PENDING', 'FAILED'],
    default: 'POSTED'
  },
  referenceNumber: { type: String, default: '' },
  description: { type: String, default: '' },
  reversalOfLedgerId: { type: String, default: null },
  auditDetails: { type: mongoose.Schema.Types.Mixed, default: {} },
  timestamp: { type: Date, default: Date.now, index: true },
  createdAt: { type: Date, default: Date.now }
});

module.exports = mongoose.models.FinancialLedger || mongoose.model('FinancialLedger', financialLedgerSchema);
