const https = require('https');
const querystring = require('querystring');
const crypto = require('crypto');

class TwilioSmsService {
  constructor() {
    this.accountSid = process.env.TWILIO_ACCOUNT_SID || '';
    this.authToken = process.env.TWILIO_AUTH_TOKEN || '';
    this.fromNumber = process.env.TWILIO_FROM_NUMBER || '';
  }

  /**
   * Normalize phone number to E.164 format (+91XXXXXXXXXX)
   */
  normalizePhone(phone) {
    if (!phone) return null;
    let clean = String(phone).replace(/\D/g, '');
    if (clean.length === 10) return '+91' + clean;
    if (clean.length === 12 && clean.startsWith('91')) return '+' + clean;
    if (clean.startsWith('+')) return clean;
    if (clean.length > 10) return '+91' + clean.slice(-10);
    return null;
  }

  /**
   * Safe phone masking for audit logs (e.g. +91 91****3844)
   */
  maskPhone(phone) {
    if (!phone) return 'N/A';
    const clean = String(phone).replace(/\D/g, '');
    if (clean.length < 4) return '***';
    const last4 = clean.slice(-4);
    const first2 = clean.slice(0, 2);
    return `+91 ${first2}****${last4}`;
  }

  /**
   * Dispatch OTP SMS using Twilio REST API
   * Compatible with Customer, Pilot, and Admin roles
   */
  async sendOtpSms(mobile, otp, role = 'CUSTOMER') {
    const formattedRecipient = this.normalizePhone(mobile);
    if (!formattedRecipient) {
      return { success: false, provider: 'twilio', error: 'Invalid mobile number' };
    }

    const roleName = String(role).toUpperCase();
    let prefix = 'StayDriv';
    if (roleName === 'PILOT' || roleName === 'DRIVER' || roleName === 'PARTNER') {
      prefix = 'StayDriv Pilot';
    } else if (roleName === 'ADMIN') {
      prefix = 'StayDriv Admin';
    }

    const messageBody = `Your ${prefix} verification OTP is ${otp}. Valid for 5 minutes. Do not share this code with anyone.`;
    const masked = this.maskPhone(mobile);

    console.log(`[TWILIO SMS] Dispatching ${roleName} OTP to ${masked} from ${this.fromNumber}`);

    return await this.sendTwilioMessage(formattedRecipient, messageBody);
  }

  /**
   * General SMS dispatch method
   */
  async sendSms({ mobileNumber, message }) {
    const formattedRecipient = this.normalizePhone(mobileNumber);
    if (!formattedRecipient) {
      return { success: false, provider: 'twilio', error: 'Invalid mobile number' };
    }
    return await this.sendTwilioMessage(formattedRecipient, message);
  }

  /**
   * Internal Twilio REST API dispatch
   */
  sendTwilioMessage(to, body) {
    return new Promise((resolve) => {
      const postData = querystring.stringify({
        To: to,
        From: this.fromNumber,
        Body: body
      });

      const authHeader = 'Basic ' + Buffer.from(`${this.accountSid}:${this.authToken}`).toString('base64');

      const options = {
        hostname: 'api.twilio.com',
        port: 443,
        path: `/2010-04-01/Accounts/${this.accountSid}/Messages.json`,
        method: 'POST',
        headers: {
          'Authorization': authHeader,
          'Content-Type': 'application/x-www-form-urlencoded',
          'Content-Length': Buffer.byteLength(postData),
          'User-Agent': 'StayDriv-Backend/2026'
        },
        timeout: 10000
      };

      const req = https.request(options, (res) => {
        let raw = '';
        res.on('data', chunk => raw += chunk);
        res.on('end', () => {
          let responseJson = {};
          try {
            responseJson = JSON.parse(raw);
          } catch (_) {
            responseJson = { raw };
          }

          if (res.statusCode >= 200 && res.statusCode < 300) {
            console.log(`[TWILIO SMS SUCCESS] Message SID: ${responseJson.sid}, Status: ${responseJson.status}`);
            resolve({
              success: true,
              provider: 'twilio',
              messageId: responseJson.sid,
              status: responseJson.status
            });
          } else {
            console.error(`[TWILIO SMS ERROR] Status: ${res.statusCode}, Code: ${responseJson.code}, Message: ${responseJson.message}`);
            resolve({
              success: false,
              provider: 'twilio',
              errorCode: responseJson.code || `HTTP_${res.statusCode}`,
              error: responseJson.message || 'Twilio SMS dispatch failed'
            });
          }
        });
      });

      req.on('error', (err) => {
        console.error(`[TWILIO SMS EXCEPTION] ${err.message}`);
        resolve({
          success: false,
          provider: 'twilio',
          errorCode: 'NETWORK_ERROR',
          error: err.message
        });
      });

      req.on('timeout', () => {
        req.destroy();
        console.error(`[TWILIO SMS TIMEOUT]`);
        resolve({
          success: false,
          provider: 'twilio',
          errorCode: 'TIMEOUT',
          error: 'Twilio API request timed out'
        });
      });

      req.write(postData);
      req.end();
    });
  }
}

module.exports = new TwilioSmsService();
