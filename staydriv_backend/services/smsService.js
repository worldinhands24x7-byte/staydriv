const https = require('https');

class SmsService {
  static async sendOtpSms(mobile, otp) {
    let cleanMobile = String(mobile).replace(/\D/g, '');
    if (cleanMobile.length === 10) cleanMobile = '91' + cleanMobile;

    console.log(`[TATA DLT SMS] Sending Real-Time DLT OTP ${otp} to +${cleanMobile}...`);

    const user = process.env.TATA_SMS_USER || 'SADGURURL';
    const pswd = process.env.TATA_SMS_PASS || 'Sadguru@2026';
    const sender = process.env.TATA_SMS_SENDER || 'SRL';
    const peId = process.env.TATA_SMS_PE_ID || '1601419178359745779';
    const templateId = process.env.TATA_SMS_TEMPLATE_ID || '1677100000000387025';

    // Exact DLT registered template: "Your One-Time Password (OTP) is {#var#}. This OTP is valid for 10 minutes. Do not share it with anyone."
    const messageText = `Your One-Time Password (OTP) is ${otp}. This OTP is valid for 10 minutes. Do not share it with anyone.`;

    const gatewayUrl = `https://ttbssmsgw.tatatel.co.in/campaignService/campaigns/qs?recipient=${encodeURIComponent(cleanMobile)}&dr=false&msg=${encodeURIComponent(messageText)}&user=${encodeURIComponent(user)}&pswd=${encodeURIComponent(pswd)}&sender=${encodeURIComponent(sender)}&PE_ID=${encodeURIComponent(peId)}&Template_ID=${encodeURIComponent(templateId)}`;

    try {
      return new Promise((resolve) => {
        https.get(gatewayUrl, (res) => {
          let data = '';
          res.on('data', chunk => data += chunk);
          res.on('end', () => {
            console.log(`[TATA DLT SMS] Response (${res.statusCode}): ${data}`);
            let isSuccess = res.statusCode >= 200 && res.statusCode < 300;
            try {
              const json = JSON.parse(data);
              if (json.totalCnt > 0 || json.jobId) {
                isSuccess = true;
              }
            } catch (e) {
              // raw response
            }
            resolve({ success: isSuccess, response: data, otp });
          });
        }).on('error', (err) => {
          console.error('[TATA DLT SMS ERROR]:', err.message);
          resolve({ success: false, error: err.message, simulatedOtp: otp });
        });
      });
    } catch (err) {
      console.error('[SMS SERVICE EXCEPTION]:', err.message);
      return { success: false, error: err.message, simulatedOtp: otp };
    }
  }
}

module.exports = SmsService;

