const smartfloSmsService = require('./smartfloSmsService');

class SmsService {
  static async sendOtpSms(mobile, otp, clientTxnId = null) {
    return await smartfloSmsService.sendOtpSms(mobile, otp, clientTxnId);
  }

  static async sendSms({ mobileNumber, message, templateId }) {
    return await smartfloSmsService.sendSms({ mobileNumber, message, templateId });
  }

  static async sendSmsAlert({ to, recipient, mobile, mobileNumber, message = 'Test', templateId }) {
    const target = to || recipient || mobile || mobileNumber;
    return await smartfloSmsService.sendSmsAlert({ to: target, message, templateId });
  }
}

module.exports = SmsService;
