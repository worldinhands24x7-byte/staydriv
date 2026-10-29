const mongoose = require('mongoose');

const pilotWalletSchema = new mongoose.Schema({
  uid: { type: String, required: true, unique: true, index: true },
  phone: { type: String, index: true },
  pilotName: { type: String, default: 'Pilot Partner' },
  availableBalance: { type: Number, default: 0 }, // Ready for instant cashout / withdrawal
  reservedBalance: { type: Number, default: 0 }, // Held in escrow for pending/processing withdrawals
  pendingSettlement: { type: Number, default: 0 }, // In 24-hr settlement window from completed rides
  totalEarnings: { type: Number, default: 0 }, // Lifetime ride earnings (85% net fare)
  totalWithdrawn: { type: Number, default: 0 }, // Lifetime completed payouts
  currency: { type: String, default: 'INR' },
  
  // Bank Account & RazorpayX Beneficiary Details
  bankAccount: {
    accountHolderName: { type: String, default: '' },
    accountNumber: { type: String, default: '' },
    maskedAccountNumber: { type: String, default: '' },
    ifsc: { type: String, default: '' },
    bankName: { type: String, default: '' },
    upiId: { type: String, default: '' },
    isVerified: { type: Boolean, default: false },
    contactId: { type: String, default: '' }, // RazorpayX Contact (e.g. cont_...)
    fundAccountId: { type: String, default: '' }, // RazorpayX Fund Account (e.g. fa_...)
    verifiedAt: { type: Date }
  },

  // Weekly Expense Advance (₹200)
  weeklyAdvance: {
    isWithdrawn: { type: Boolean, default: false },
    amount: { type: Number, default: 200.0 },
    withdrawnAt: { type: Date, default: null },
    weekIdentifier: { type: String, default: '' }
  },

  lastTransactionAt: { type: Date, default: Date.now },
  createdAt: { type: Date, default: Date.now },
  updatedAt: { type: Date, default: Date.now }
});

module.exports = mongoose.models.PilotWallet || mongoose.model('PilotWallet', pilotWalletSchema);
