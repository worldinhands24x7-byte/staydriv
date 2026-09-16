const mongoose = require('mongoose');

const otpSchema = new mongoose.Schema({
  mobile: {
    type: String,
    required: true,
    index: true
  },
  otp: {
    type: String,
    required: true
  },
  expireAt: {
    type: Date,
    default: () => new Date(Date.now() + 5 * 60 * 1000), // 5 minutes expiry
    index: { expires: 0 } // MongoDB TTL index to auto-delete after 5 min
  }
}, { timestamps: true });

module.exports = mongoose.model('Otp', otpSchema);
