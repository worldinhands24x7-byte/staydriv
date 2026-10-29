const mongoose = require('mongoose');
const crypto = require('crypto');

const otpSchema = new mongoose.Schema({
  mobile: {
    type: String,
    required: true,
    index: true
  },
  role: {
    type: String,
    enum: ['CUSTOMER', 'PILOT', 'ADMIN'],
    default: 'CUSTOMER',
    index: true
  },
  otpHash: {
    type: String,
    required: true
  },
  salt: {
    type: String,
    required: true
  },
  transactionId: {
    type: String,
    required: false,
    index: true
  },
  verificationSessionId: {
    type: String,
    required: false,
    index: true
  },
  status: {
    type: String,
    enum: ['PENDING', 'VERIFIED', 'EXPIRED', 'MAX_ATTEMPTS_EXCEEDED'],
    default: 'PENDING',
    index: true
  },
  attempts: {
    type: Number,
    default: 0
  },
  maxAttempts: {
    type: Number,
    default: 5
  },
  verified: {
    type: Boolean,
    default: false
  },
  requestCount: {
    type: Number,
    default: 1
  },
  lastSentAt: {
    type: Date,
    default: Date.now
  },
  expireAt: {
    type: Date,
    default: () => new Date(Date.now() + 5 * 60 * 1000), // 5 minutes validity
    index: { expires: 0 } // MongoDB TTL index to automatically purge expired records
  }
}, { timestamps: true });

otpSchema.index({ mobile: 1, role: 1 });

otpSchema.methods.verifyCode = function(candidateOtp) {
  if (!candidateOtp) return false;
  const cleanCode = String(candidateOtp).trim();
  if (this.otpHash && this.salt) {
    const computedHash = crypto.pbkdf2Sync(cleanCode, this.salt, 1000, 32, 'sha256').toString('hex');
    try {
      const a = Buffer.from(computedHash, 'hex');
      const b = Buffer.from(this.otpHash, 'hex');
      if (a.length === b.length && crypto.timingSafeEqual(a, b)) {
        return true;
      }
    } catch (_) {}
    return computedHash === this.otpHash;
  }
  return false;
};

module.exports = mongoose.models.Otp || mongoose.model('Otp', otpSchema);
