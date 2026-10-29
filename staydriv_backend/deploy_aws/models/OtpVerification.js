const mongoose = require('mongoose');

const otpVerificationSchema = new mongoose.Schema({
  mobile_number: {
    type: String,
    required: true,
    index: true
  },
  user_id: {
    type: String,
    default: null,
    index: true
  },
  role: {
    type: String,
    enum: ['CUSTOMER', 'PILOT', 'PARTNER', 'ADMIN'],
    default: 'CUSTOMER',
    index: true
  },
  purpose: {
    type: String,
    enum: ['CUSTOMER_LOGIN', 'PILOT_LOGIN', 'PARTNER_LOGIN', 'ADMIN_LOGIN'],
    default: 'CUSTOMER_LOGIN',
    index: true
  },
  otp_hash: {
    type: String,
    required: true
  },
  salt: {
    type: String,
    required: true
  },
  attempt_count: {
    type: Number,
    default: 0
  },
  max_attempts: {
    type: Number,
    default: 3
  },
  status: {
    type: String,
    enum: ['PENDING', 'USED', 'EXPIRED', 'FAILED'],
    default: 'PENDING',
    index: true
  },
  used_at: {
    type: Date,
    default: null
  },
  last_sent_at: {
    type: Date,
    default: Date.now
  },
  provider: {
    type: String,
    default: 'tata_dlt'
  },
  provider_message_id: {
    type: String,
    default: null
  },
  expires_at: {
    type: Date,
    default: () => new Date(Date.now() + 5 * 60 * 1000), // 5 minutes expiry
    index: { expires: 0 } // MongoDB TTL index to auto-purge expired documents
  }
}, {
  timestamps: { createdAt: 'created_at', updatedAt: 'updated_at' }
});

// Composite index for fast lookup
otpVerificationSchema.index({ mobile_number: 1, purpose: 1, status: 1 });

module.exports = mongoose.model('OtpVerification', otpVerificationSchema, 'otp_verifications');
