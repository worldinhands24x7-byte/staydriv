const mongoose = require('mongoose');

const smsLogSchema = new mongoose.Schema({
  logId: {
    type: String,
    unique: true,
    required: true,
    index: true
  },
  userId: {
    type: String,
    index: true,
    default: null
  },
  mobile_number_masked: {
    type: String,
    required: true
  },
  provider: {
    type: String,
    enum: ['smartflo', 'tata_dlt', 'mock'],
    default: 'tata_dlt'
  },
  message_type: {
    type: String,
    enum: ['otp', 'transactional', 'notification'],
    default: 'otp'
  },
  template_id: {
    type: String,
    default: null
  },
  provider_message_id: {
    type: String,
    default: null
  },
  status: {
    type: String,
    enum: ['QUEUED', 'SENT', 'DELIVERED', 'FAILED'],
    default: 'SENT'
  },
  error_code: {
    type: String,
    default: null
  }
}, { timestamps: true });

module.exports = mongoose.model('SmsLog', smsLogSchema, 'sms_logs');
