const https = require('https');

class SmsService {
  static async sendOtpSms(mobile, otp) {
    let cleanMobile = String(mobile).replace(/\D/g, '');
    if (cleanMobile.length === 10) cleanMobile = '91' + cleanMobile;

    console.log(`[TATA SMARTFLO SMS] Sending OTP ${otp} to mobile +${cleanMobile}...`);

    const jwtToken = process.env.TATA_SMARTFLO_JWT_TOKEN;
    const baseUrl = process.env.TATA_SMARTFLO_BASE_URL || 'https://cloudphone.tatateleservices.com';

    if (!jwtToken) {
      console.warn(`[SMS WARNING] TATA_SMARTFLO_JWT_TOKEN not set in environment. Simulated SMS OTP: ${otp}`);
      return { success: true, simulated: true, otp };
    }

    try {
      const messageText = `Your StayDriv OTP code is ${otp}. Valid for 5 minutes. Do not share it with anyone.`;
      const postData = JSON.stringify({
        destination_number: cleanMobile,
        message: messageText,
        text: messageText,
        sender_id: 'STDRIV'
      });

      const parsedUrl = new URL(`${baseUrl}/api/v1/sms/send`);
      const options = {
        hostname: parsedUrl.hostname,
        port: 443,
        path: parsedUrl.pathname,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${jwtToken.trim()}`,
          'Content-Length': Buffer.byteLength(postData)
        }
      };

      return new Promise((resolve) => {
        const req = https.request(options, (res) => {
          let data = '';
          res.on('data', chunk => data += chunk);
          res.on('end', () => {
            console.log(`[TATA SMARTFLO SMS] Response (${res.statusCode}): ${data}`);
            resolve({ success: res.statusCode >= 200 && res.statusCode < 300, data });
          });
        });

        req.on('error', (err) => {
          console.error('[TATA SMARTFLO SMS ERROR]:', err.message);
          resolve({ success: false, error: err.message, simulatedOtp: otp });
        });

        req.write(postData);
        req.end();
      });
    } catch (err) {
      console.error('[SMS SERVICE EXCEPTION]:', err.message);
      return { success: false, error: err.message, simulatedOtp: otp };
    }
  }
}

module.exports = SmsService;
