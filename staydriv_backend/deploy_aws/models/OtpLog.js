const mongoose = require('mongoose');

const otpLogSchema = new mongoose.Schema({
  requestId: { 
    type: String, 
    required: true, 
    unique: true, 
    index: true 
  },
  transactionId: {
    type: String,
    required: true,
    index: true
  },
  mobileMasked: { 
    type: String, 
    required: true 
  },
  mobileClean: { 
    type: String, 
    required: true, 
    index: true 
  },
  userType: { 
    type: String, 
    default: 'CUSTOMER' 
  },
  otpHashed: {
    type: String
  },
  salt: {
    type: String
  },
  status: {
    type: String,
    enum: [
      'OTP_GENERATED',
      'CODE_GENERATED',
      'READY_IN_APP',
      'OTP_SUBMITTED',
      'GATEWAY_ACCEPTED',
      'PENDING_CARRIER',
      'SMS_DELIVERED',
      'SMS_REJECTED',
      'SMS_FAILED',
      'EXPIRED',
      'VERIFIED'
    ],
    default: 'CODE_GENERATED',
    index: true
  },
  gateway: { 
    type: String, 
    default: 'ttbs_smsgw' 
  },
  provider: {
    type: String,
    default: 'ttbs'
  },
  providerMessageId: { 
    type: String,
    index: true
  },
  jobId: { 
    type: String 
  },
  campaignId: { 
    type: String 
  },
  templateId: { 
    type: String, 
    default: '1677100000000387025' 
  },
  senderId: { 
    type: String, 
    default: 'SRL' 
  },
  submissionStatus: { 
    type: String, 
    default: 'GATEWAY_ACCEPTED' 
  },
  deliveryStatus: { 
    type: String, 
    default: 'PENDING_CARRIER' 
  },
  providerErrorCode: {
    type: String
  },
  failureReason: { 
    type: String 
  },
  bind: {
    type: String,
    default: null
  },
  pkg: {
    type: String,
    default: null
  },
  attemptCount: {
    type: Number,
    default: 0
  },
  submittedAt: {
    type: Date
  },
  gatewayAcceptedAt: {
    type: Date
  },
  deliveryConfirmedAt: {
    type: Date
  },
  rejectedAt: {
    type: Date
  },
  verifiedAt: {
    type: Date
  },
  expiresAt: {
    type: Date
  },
  verificationStatus: {
    type: String,
    enum: ['PENDING', 'VERIFIED', 'FAILED'],
    default: 'PENDING'
  },
  statusCode: { 
    type: Number, 
    default: 202 
  },
  callbackPayload: {
    type: mongoose.Schema.Types.Mixed
  }
}, { timestamps: true });

module.exports = mongoose.model('OtpLog', otpLogSchema);
