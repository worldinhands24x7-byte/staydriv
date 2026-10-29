const express = require('express');
const router = express.Router();
const otpController = require('../controllers/otpController');

// Production Specification Endpoints (Section 9: POST /api/auth/request-otp)
router.post('/auth/request-otp', otpController.sendOtp);
router.post('/request-otp', otpController.sendOtp);
router.post('/auth/otp/request', otpController.sendOtp);
router.post('/otp/request', otpController.sendOtp);
router.post('/send-otp', otpController.sendOtp);
router.post('/auth/send-otp', otpController.sendOtp);
router.post('/request', otpController.sendOtp);

// OTP Verification Endpoints
router.post('/auth/verify-otp', otpController.verifyOtp);
router.post('/verify-otp', otpController.verifyOtp);
router.post('/auth/otp/verify', otpController.verifyOtp);
router.post('/otp/verify', otpController.verifyOtp);
router.post('/verify', otpController.verifyOtp);

// OTP Resend Endpoints
router.post('/auth/resend-otp', otpController.resendOtp || otpController.sendOtp);
router.post('/resend-otp', otpController.resendOtp || otpController.sendOtp);
router.post('/auth/otp/resend', otpController.resendOtp || otpController.sendOtp);
router.post('/otp/resend', otpController.resendOtp || otpController.sendOtp);
router.post('/resend', otpController.resendOtp || otpController.sendOtp);

// Real-time OTP status polling endpoints (Requirement 17)
router.get('/auth/otp-status/:transactionId', otpController.getOtpStatus);
router.get('/otp-status/:transactionId', otpController.getOtpStatus);
router.get('/auth/otp/status/:transactionId', otpController.getOtpStatus);
router.get('/otp/status/:transactionId', otpController.getOtpStatus);
router.get('/status/:transactionId', otpController.getOtpStatus);

// Webhook endpoints for TTBS delivery reports (Requirement 16)
router.post('/webhooks/ttbs/sms', otpController.handleTtbsSmsWebhook);
router.post('/webhook/ttbs/sms', otpController.handleTtbsSmsWebhook);

// OTP Diagnostic Logs for Admin Console (Requirement 14)
router.get('/admin/otp-logs', otpController.getOtpLogs);
router.get('/otp/logs', otpController.getOtpLogs);
router.get('/otp-logs', otpController.getOtpLogs);
router.get('/diagnostic-logs', otpController.getOtpLogs);

// Admin-only diagnostic test endpoint (Requirement 16)
router.post('/admin/otp/test-ttbs', otpController.testTtbsDelivery);
router.post('/otp/test-ttbs', otpController.testTtbsDelivery);
router.post('/test-ttbs', otpController.testTtbsDelivery);

// Provisioning status endpoint (Requirement 4)
router.get('/admin/otp/provisioning-status', otpController.getProvisioningStatus);
router.get('/otp/provisioning-status', otpController.getProvisioningStatus);
router.get('/provisioning-status', otpController.getProvisioningStatus);

// SMS Alert endpoints via TTBS QS Campaign interface
router.post('/sms/send-alert', otpController.sendSmsAlert);
router.get('/sms/send-alert', otpController.sendSmsAlert);
router.post('/admin/sms/send-alert', otpController.sendSmsAlert);
router.get('/admin/sms/send-alert', otpController.sendSmsAlert);
router.post('/send-alert', otpController.sendSmsAlert);
router.get('/send-alert', otpController.sendSmsAlert);

// Logout endpoint
router.post(['/auth/logout', '/logout'], (req, res) => {
  const { mobile, role, verificationSessionId } = req.body || {};
  console.log(`[AUTH] Session logged out for ${mobile || 'unknown'} (${role || 'user'})`);
  res.json({ success: true, message: 'Logged out successfully' });
});

module.exports = router;
