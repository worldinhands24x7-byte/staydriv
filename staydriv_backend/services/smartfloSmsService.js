const https = require('https');
const crypto = require('crypto');

class SmartfloSmsService {
  constructor() {
    // Tata Enterprise DLT Gateway Credentials (from TTBS REST API documentation)
    this.dltUser = (process.env.TATA_SMS_USER || 'SADGURURL').trim();
    this.dltPass = (process.env.TATA_SMS_PASS || 'Sadguru@2026').trim();
    this.dltSender = (process.env.TATA_SMS_SENDER || 'SADGRL').trim();
    this.dltPeId = (process.env.TATA_SMS_PE_ID || '1601419178359745779').trim();
    this.dltTmId = (process.env.TATA_SMS_TM_ID || '1602763178359960154').trim();
    this.dltTemplateId = (process.env.TATA_SMS_TEMPLATE_ID || '1677100000000393380').trim();
    this.ttbsBaseUrl = (process.env.TATA_SMS_BASE_URL || 'https://ttbssmsgw.tatatel.co.in').trim().replace(/\/+$/, '');

    // Smartflo JWT Token (Fallback / Direct Smartflo integration)
    this.smartfloToken = (process.env.SMARTFLO_API_TOKEN || process.env.TATA_SMARTFLO_JWT_TOKEN || '').trim();

    // In-memory cache for TTBS SMSGW Access Token
    this.cachedToken = null;
    this.tokenExpiresAt = 0;
  }

  /**
   * Normalize Indian phone numbers to 10 digits
   */
  normalizePhone(phone) {
    if (!phone) return null;
    const clean = String(phone).replace(/\D/g, '');
    if (clean.length === 10) return clean;
    if (clean.length === 12 && clean.startsWith('91')) return clean.slice(2);
    if (clean.length === 11 && clean.startsWith('0')) return clean.slice(1);
    if (clean.length > 10) return clean.slice(-10);
    return null;
  }

  /**
   * Safe phone masking for logs (e.g. +91 ******2111)
   */
  maskPhone(phone) {
    if (!phone) return 'N/A';
    const clean = this.normalizePhone(phone);
    if (!clean || clean.length < 4) return '******';
    return `+91 ******${clean.slice(-4)}`;
  }

  /**
   * Helper to hash an OTP with salt using HMAC SHA-256
   */
  hashOtp(otp, salt) {
    return crypto.createHmac('sha256', salt).update(String(otp).trim()).digest('hex');
  }

  /**
   * Generate random 6-digit OTP
   */
  generateOtp() {
    return crypto.randomInt(100000, 1000000).toString();
  }

  /**
   * Generate cryptographic salt
   */
  generateSalt() {
    return crypto.randomBytes(16).toString('hex');
  }

  /**
   * Format expiry date in Indian Standard Time (IST, UTC+5:30) as required by TTBS: 'yyyy-mm-dd HH:mm:ss'
   * Ensures compatibility regardless of whether server timezone is UTC (e.g. AWS EC2) or local.
   */
  getIstExpiryString(minutesAhead = 10) {
    const istMillis = Date.now() + (5.5 * 60 * 60 * 1000) + (minutesAhead * 60 * 1000);
    const d = new Date(istMillis);
    const pad = n => String(n).padStart(2, '0');
    return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())} ${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}:${pad(d.getUTCSeconds())}`;
  }

  /**
   * Obtain TTBS SMS Gateway Access Token (POST /login/user)
   * Automatically caches the JWT until near expiration.
   */
  async getAuthToken(forceRefresh = false) {
    const now = Date.now();
    if (!forceRefresh && this.cachedToken && now < (this.tokenExpiresAt - 60000)) {
      return this.cachedToken;
    }

    return new Promise((resolve, reject) => {
      const u = new URL(`${this.ttbsBaseUrl}/login/user`);
      const postData = JSON.stringify({
        username: this.dltUser,
        password: this.dltPass
      });

      const req = https.request({
        hostname: u.hostname,
        port: u.port || 443,
        path: u.pathname,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(postData)
        },
        timeout: 10000
      }, (res) => {
        let raw = '';
        res.on('data', chunk => raw += chunk);
        res.on('end', () => {
          if (res.statusCode >= 200 && res.statusCode < 300) {
            try {
              const data = JSON.parse(raw);
              const token = data.access_token || data.token;
              if (!token) {
                return reject(new Error('No access_token returned by TTBS login'));
              }

              // Extract expiry if available in JWT payload
              let expTime = now + 15 * 60 * 1000; // default 15 mins
              try {
                const parts = token.split('.');
                if (parts.length === 3) {
                  const payload = JSON.parse(Buffer.from(parts[1], 'base64').toString('utf8'));
                  if (payload.exp) {
                    expTime = payload.exp * 1000;
                  }
                }
              } catch (_) {}

              this.cachedToken = token;
              this.tokenExpiresAt = expTime;
              resolve(token);
            } catch (err) {
              reject(new Error(`Failed to parse TTBS auth response: ${err.message}`));
            }
          } else {
            reject(new Error(`TTBS auth failed with status ${res.statusCode}: ${raw}`));
          }
        });
      });

      req.on('error', reject);
      req.on('timeout', () => {
        req.destroy();
        reject(new Error('TTBS auth request timed out'));
      });

      req.write(postData);
      req.end();
    });
  }

  /**
   * Dispatch Non-Bulk SMS Campaign via TTBS SMS Gateway (POST /campaigns/submissions/sms/nb)
   * Follows official TTBS Messaging/Campaign REST API Specification
   */
  async sendTtbsSms({ recipient, message, templateId, isOtp = true }) {
    let token = await this.getAuthToken();
    const expiryDt = this.getIstExpiryString(10); // Exactly 10 minutes in IST

    const payload = {
      msgCategory: isOtp ? '4.2' : '4.5', // '4.2' for OTP, '4.5' for Transactional
      contentType: '3.1', // Text
      senderAddr: this.dltSender,
      peId: this.dltPeId,
      cusTemplateId: templateId || this.dltTemplateId,
      priority: 1,
      clientTxnId: 'STAYDRIV_' + Date.now(),
      recipient: recipient,
      msg: message,
      expiryDt: expiryDt,
      dr: '1'
    };

    const attemptSend = (jwtToken) => {
      return new Promise((resolve) => {
        const u = new URL(`${this.ttbsBaseUrl}/campaigns/submissions/sms/nb`);
        const postData = JSON.stringify(payload);

        const req = https.request({
          hostname: u.hostname,
          port: u.port || 443,
          path: u.pathname,
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `bearer ${jwtToken}`,
            'Content-Length': Buffer.byteLength(postData)
          },
          timeout: 10000
        }, (res) => {
          let raw = '';
          res.on('data', chunk => raw += chunk);
          res.on('end', () => {
            resolve({ statusCode: res.statusCode, body: raw });
          });
        });

        req.on('error', (err) => {
          resolve({ statusCode: 0, error: err.message });
        });

        req.on('timeout', () => {
          req.destroy();
          resolve({ statusCode: 408, error: 'Request timeout' });
        });

        req.write(postData);
        req.end();
      });
    };

    let result = await attemptSend(token);

    // If 401 Unauthorized, token may have expired. Refresh once and retry.
    if (result.statusCode === 401) {
      console.warn('[TTBS SMSGW] Token 401 encountered. Refreshing token and retrying...');
      try {
        token = await this.getAuthToken(true);
        result = await attemptSend(token);
      } catch (refreshErr) {
        console.error('[TTBS SMSGW] Token refresh failed:', refreshErr.message);
      }
    }

    const isSuccess = result.statusCode === 200 || result.statusCode === 202;
    console.log(`[TTBS_RESPONSE_RECEIVED] HTTP ${result.statusCode} | Status: ${isSuccess ? 'ACCEPTED' : 'REJECTED'}`);

    if (isSuccess) {
      let parsed = {};
      try { parsed = JSON.parse(result.body); } catch (_) {}
      const jobId = parsed.jobId || parsed.campaignId || 'ACCEPTED';
      return {
        success: true,
        provider: 'ttbs_smsgw',
        statusCode: result.statusCode,
        messageId: jobId,
        details: parsed
      };
    } else {
      console.error(`[TTBS SMSGW ERROR] HTTP ${result.statusCode}: ${result.body || result.error}`);
      return {
        success: false,
        provider: 'ttbs_smsgw',
        statusCode: result.statusCode,
        error: result.body || result.error
      };
    }
  }

  /**
   * Dispatch SMS via TTBS Quick Send (QS) HTTP interface
   * Route: https://ttbssmsgw.tatatel.co.in//campaignService/campaigns/qs?recipient=919999999999&dr=false&msg=Test&user=SADGURURL&pswd=Sadguru@2026&sender=SADGRL&PE_ID=1601419178359745779&Template_ID=1677100000000393380
   */
  async sendTtbsQsSms({ recipient, message, templateId }) {
    const cleanPhone = this.normalizePhone(recipient);
    const candidateCreds = [
      { user: 'SADGURURL', pswd: 'Sadguru@2026' }, // Primary specified for SMS alert & OTP
      { user: this.dltUser, pswd: this.dltPass },
      { user: this.dltUser, pswd: 'Bhavim1992@gmail' },
      { user: this.dltPeId, pswd: 'Bhavim1992@gmail' }
    ];

    for (const cred of candidateCreds) {
      const res = await this._dispatchQsRequest({
        recipient: cleanPhone,
        message,
        templateId: templateId || this.dltTemplateId,
        user: cred.user,
        pswd: cred.pswd
      });

      if (res.success || (res.statusCode !== 401 && res.statusCode !== 0)) {
        return res;
      }
    }

    return {
      success: false,
      provider: 'ttbs_qs',
      error: 'All QS credential candidates failed'
    };
  }

  /**
   * Dispatch SMS Alert via official TTBS Quick Send (QS) URL interface:
   * https://ttbssmsgw.tatatel.co.in//campaignService/campaigns/qs?recipient=919999999999&dr=false&msg=Test&user=SADGURURL&pswd=Sadguru@2026&sender=SADGRL&PE_ID=1601419178359745779&Template_ID=1677100000000393380
   */
  async sendSmsAlert({ to, recipient, message = 'Test', templateId }) {
    const rawTarget = to || recipient;
    const cleanPhone = this.normalizePhone(rawTarget);
    if (!cleanPhone) {
      return { success: false, provider: 'ttbs_qs', error: 'Invalid 10-digit mobile number' };
    }

    const tId = templateId || this.dltTemplateId;
    return await this._dispatchQsRequest({
      recipient: cleanPhone,
      message: message || 'Test',
      templateId: tId,
      user: 'SADGURURL',
      pswd: 'Sadguru@2026'
    });
  }

  _dispatchQsRequest({ recipient, message, templateId, user, pswd }) {
    return new Promise((resolve) => {
      try {
        const cleanDigits = String(recipient || '').replace(/\D/g, '');
        const targetRecipient = cleanDigits.length === 10 ? ('91' + cleanDigits) : cleanDigits;
        const params = new URLSearchParams({
          recipient: targetRecipient,
          dr: 'false',
          msg: message,
          user: user || this.dltUser,
          pswd: pswd || this.dltPass,
          sender: this.dltSender,
          PE_ID: this.dltPeId,
          Template_ID: templateId || this.dltTemplateId
        });

        const urlStr = `${this.ttbsBaseUrl}//campaignService/campaigns/qs?${params.toString()}`;
        const u = new URL(urlStr);

        const req = https.request({
          hostname: u.hostname,
          port: 443,
          path: u.pathname + u.search,
          method: 'GET',
          timeout: 10000
        }, (res) => {
          let raw = '';
          res.on('data', chunk => raw += chunk);
          res.on('end', () => {
            const isSuccess = res.statusCode === 200 || res.statusCode === 202;
            console.log(`[TTBS_RESPONSE_RECEIVED] QS HTTP ${res.statusCode} (user=${user}) | Status: ${isSuccess ? 'ACCEPTED' : 'REJECTED'}`);
            if (isSuccess) {
              let parsed = {};
              try { parsed = JSON.parse(raw); } catch (_) {}
              const jobId = parsed.jobId || parsed.campaignId || 'QS_ACCEPTED';
              resolve({
                success: true,
                provider: 'ttbs_qs',
                statusCode: res.statusCode,
                messageId: jobId,
                details: parsed
              });
            } else {
              resolve({
                success: false,
                provider: 'ttbs_qs',
                statusCode: res.statusCode,
                error: raw
              });
            }
          });
        });

        req.on('error', err => resolve({ success: false, provider: 'ttbs_qs', statusCode: 0, error: err.message }));
        req.on('timeout', () => {
          req.destroy();
          resolve({ success: false, provider: 'ttbs_qs', statusCode: 408, error: 'Request timeout' });
        });
        req.end();
      } catch (err) {
        resolve({ success: false, provider: 'ttbs_qs', error: err.message });
      }
    });
  }

  /**
   * Dispatch OTP SMS using Tata Enterprise DLT Gateway with approved template:
   * "Your One-Time Password (OTP) is {#var#}. This OTP is valid for 10 minutes. Do not share it with anyone. SADGURU ROAD LINES"
   */
  /**
   * Check real-time message delivery status from TTBS / Smartflo debug logs
   */
  async checkDeliveryStatus(jobId) {
    if (!jobId || jobId === 'ACCEPTED') return null;
    try {
      const token = await this.getAuthToken();
      return new Promise((resolve) => {
        const u = new URL(`${this.ttbsBaseUrl}/api/v1/logs/debug?pgsize=20&pgindex=0`);
        const req = https.request({
          hostname: u.hostname,
          port: 443,
          path: u.pathname + u.search,
          method: 'GET',
          headers: { 'Authorization': `bearer ${token}` },
          timeout: 5000
        }, (res) => {
          let b = '';
          res.on('data', c => b += c);
          res.on('end', () => {
            try {
              const parsed = JSON.parse(b);
              if (parsed.logs && Array.isArray(parsed.logs)) {
                const match = parsed.logs.find(l => l.m_id === jobId || l.p_id === jobId);
                if (match) {
                  return resolve({
                    found: true,
                    status: match.status,
                    statusCode: match.s_st,
                    sender: match.s_adr,
                    recipient: match.aud,
                    isRejected: match.status === 'INVALID_API_KEY' || match.s_st === '15019',
                    raw: match
                  });
                }
              }
              resolve({ found: false });
            } catch (_) {
              resolve({ found: false });
            }
          });
        });
        req.on('error', () => resolve({ found: false }));
        req.on('timeout', () => { req.destroy(); resolve({ found: false }); });
        req.end();
      });
    } catch (_) {
      return { found: false };
    }
  }

  /**
   * Dispatch single SMS using official Swagger /api/v1/sms/send endpoint
   */
  async sendTtbsSingleSms({ recipient, message, templateId, clientTxnId }) {
    let token = await this.getAuthToken();
    const payload = {
      msg: message,
      recipient: recipient,
      sender: this.dltSender,
      category: 'OTP',
      templateId: templateId || this.dltTemplateId,
      peId: this.dltPeId,
      clientTxnId: clientTxnId || ('STAYDRIV_' + Date.now())
    };

    const attemptSend = (jwtToken) => {
      return new Promise((resolve) => {
        const u = new URL(`${this.ttbsBaseUrl}/api/v1/sms/send`);
        const postData = JSON.stringify(payload);

        const req = https.request({
          hostname: u.hostname,
          port: u.port || 443,
          path: u.pathname,
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `bearer ${jwtToken}`,
            'Content-Length': Buffer.byteLength(postData)
          },
          timeout: 10000
        }, (res) => {
          let raw = '';
          res.on('data', chunk => raw += chunk);
          res.on('end', () => resolve({ statusCode: res.statusCode, body: raw }));
        });

        req.on('error', (err) => resolve({ statusCode: 0, error: err.message }));
        req.on('timeout', () => { req.destroy(); resolve({ statusCode: 408, error: 'Request timeout' }); });
        req.write(postData);
        req.end();
      });
    };

    let result = await attemptSend(token);
    if (result.statusCode === 401) {
      token = await this.getAuthToken(true);
      result = await attemptSend(token);
    }

    const isSuccess = result.statusCode === 200 || result.statusCode === 202;
    console.log(`[TTBS_RESPONSE_RECEIVED] HTTP ${result.statusCode} | Status: ${isSuccess ? 'ACCEPTED' : 'REJECTED'}`);

    if (isSuccess) {
      let parsed = {};
      try { parsed = JSON.parse(result.body); } catch (_) {}
      const jobId = parsed.jobId || parsed.campaignId || parsed.txnId || 'ACCEPTED';
      return {
        success: true,
        provider: 'ttbs_smsgw',
        statusCode: result.statusCode,
        messageId: jobId,
        details: parsed
      };
    } else {
      return {
        success: false,
        provider: 'ttbs_smsgw',
        statusCode: result.statusCode,
        error: result.body || result.error
      };
    }
  }

  /**
   * Dispatch OTP SMS using Tata Enterprise DLT Gateway with approved template (Template ID: 1677100000000393380, Header: SADGRL):
   * "Use OTP {#var#}. to Login into Your account of SADGURU ROAD LINES. This OTP is valid for 10 minutes. Do not share the OTP with Anyone."
   */
  async sendOtpSms(mobile, otp, clientTxnId = null) {
    const cleanMobile = this.normalizePhone(mobile);
    if (!cleanMobile) {
      return { success: false, error: 'Invalid 10-digit mobile number' };
    }

    const masked = this.maskPhone(cleanMobile);
    const recipient = '91' + cleanMobile;

    // Exact DLT approved template message (Template ID: 1677100000000393380, Header: SADGRL)
    const messageText = `Use OTP ${otp}. to Login into Your account of SADGURU ROAD LINES. This OTP is valid for 10 minutes. Do not share the OTP with Anyone.`;

    // Requirement 5: Strict DLT Template validation
    const dltTemplateRegex = /^Use OTP \d{4,8}\. to Login into Your account of SADGURU ROAD LINES\. This OTP is valid for 10 minutes\. Do not share the OTP with Anyone\.$/;
    if (!dltTemplateRegex.test(messageText)) {
      console.error(`[DLT_TEMPLATE_MISMATCH] Body does not match DLT Template ID ${this.dltTemplateId}`);
      return {
        success: false,
        status: 'SMS_REJECTED',
        provider: 'ttbs',
        errorCode: 'DLT_TEMPLATE_MISMATCH',
        error: `DLT_TEMPLATE_MISMATCH: Message body does not conform to approved template ${this.dltTemplateId}`
      };
    }

    console.log(`[TTBS_REQUEST_STARTED] Target: ${masked}, Template: ${this.dltTemplateId}, Sender: ${this.dltSender}`);

    // 1. Primary: TTBS Quick Send (QS) Campaign Gateway (https://ttbssmsgw.tatatel.co.in//campaignService/campaigns/qs)
    try {
      console.log('[SMS SERVICE] Attempting TTBS Quick Send (QS) campaign route...');
      const qsResult = await this.sendTtbsQsSms({
        recipient: cleanMobile,
        message: messageText,
        templateId: this.dltTemplateId
      });
      if (qsResult.success) {
        console.log(`[OTP_SMS_ACCEPTED] Provider: ${qsResult.provider}, Status: ${qsResult.statusCode}, Job ID: ${qsResult.messageId}`);
        const trace = await this.checkDeliveryStatus(qsResult.messageId);
        if (trace && trace.found) {
          qsResult.deliveryTrace = trace;
        }
        return qsResult;
      }
      console.warn(`[SMS SERVICE] TTBS QS route returned ${qsResult.statusCode}. Fallback to Single API...`);
    } catch (qsErr) {
      console.error('[SMS SERVICE] TTBS QS Exception:', qsErr.message);
    }

    // 2. Secondary: Official TTBS Enterprise REST API (/api/v1/sms/send)
    try {
      const singleResult = await this.sendTtbsSingleSms({
        recipient,
        message: messageText,
        templateId: this.dltTemplateId,
        clientTxnId
      });
      if (singleResult.success) {
        console.log(`[OTP_SMS_ACCEPTED] Provider: ${singleResult.provider}, Status: ${singleResult.statusCode}, Job ID: ${singleResult.messageId}`);
        // Actively check delivery trace
        const trace = await this.checkDeliveryStatus(singleResult.messageId);
        if (trace && trace.found) {
          singleResult.deliveryTrace = trace;
        }
        return singleResult;
      }
      console.warn(`[SMS SERVICE] TTBS /api/v1/sms/send returned ${singleResult.statusCode}. Fallback to campaign submission...`);
    } catch (err) {
      console.error('[SMS SERVICE] TTBS Single API Exception:', err.message);
    }

    // 3. Fallback: TTBS Non-Bulk Campaign Interface (/campaigns/submissions/sms/nb)
    try {
      const ttbsResult = await this.sendTtbsSms({
        recipient,
        message: messageText,
        templateId: this.dltTemplateId,
        isOtp: true
      });
      if (ttbsResult.success) {
        console.log(`[OTP_SMS_ACCEPTED] Provider: ${ttbsResult.provider}, Status: ${ttbsResult.statusCode}, Job ID: ${ttbsResult.messageId}`);
        const trace = await this.checkDeliveryStatus(ttbsResult.messageId);
        if (trace && trace.found) {
          ttbsResult.deliveryTrace = trace;
        }
        return ttbsResult;
      }
    } catch (err) {
      console.error('[SMS SERVICE] TTBS Primary Exception:', err.message);
    }

    console.error(`[OTP_SMS_FAILED] All TTBS dispatch routes failed for ${masked}`);
    return {
      success: false,
      provider: 'ttbs_smsgw',
      message: 'Failed to deliver SMS through TTBS gateway'
    };
  }

  /**
   * General SMS send method - utilizes TTBS Quick Send (QS) alert route as primary
   */
  async sendSms({ mobileNumber, message, templateId }) {
    const cleanMobile = this.normalizePhone(mobileNumber);
    if (!cleanMobile) {
      return { success: false, provider: 'none', errorCode: 'INVALID_MOBILE', message: 'Invalid Indian mobile number' };
    }

    const finalTemplateId = templateId || this.dltTemplateId;

    // 1. Primary: TTBS Quick Send (QS) Alert Route
    try {
      const qsRes = await this.sendSmsAlert({
        to: cleanMobile,
        message,
        templateId: finalTemplateId
      });
      if (qsRes && qsRes.success) {
        return qsRes;
      }
    } catch (e) {
      console.warn('[SMS SERVICE] QS sendSmsAlert fallback:', e.message);
    }

    // 2. Fallback: TTBS Non-Bulk Campaign Submission
    const recipient = '91' + cleanMobile;
    return await this.sendTtbsSms({
      recipient,
      message,
      templateId: finalTemplateId,
      isOtp: false
    });
  }

  /**
   * Internal Smartflo SMS Endpoint Dispatch (Backup)
   */
  sendSmartfloDirectSms({ to, message, templateId }) {
    return new Promise((resolve) => {
      try {
        const postData = JSON.stringify({
          to: to,
          message: message,
          template_id: templateId,
          sender: this.dltSender
        });

        const req = https.request({
          hostname: 'api-smartflo.tatateleservices.com',
          port: 443,
          path: '/v1/sms',
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${this.smartfloToken}`,
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Content-Length': Buffer.byteLength(postData)
          },
          timeout: 10000
        }, (res) => {
          let raw = '';
          res.on('data', chunk => raw += chunk);
          res.on('end', () => {
            const isSuccess = res.statusCode >= 200 && res.statusCode < 300;
            let messageId = null;
            try {
              const data = JSON.parse(raw);
              messageId = data.ref_id || data.message_id || data.id;
            } catch (_) {}

            if (isSuccess) {
              resolve({
                success: true,
                provider: 'smartflo_backup',
                messageId: messageId || 'SMARTFLO_QUEUED'
              });
            } else {
              resolve({
                success: false,
                provider: 'smartflo_backup',
                errorCode: `HTTP_${res.statusCode}`,
                message: raw
              });
            }
          });
        });

        req.on('error', (err) => {
          resolve({
            success: false,
            provider: 'smartflo_backup',
            errorCode: 'SMARTFLO_NETWORK_ERROR',
            message: err.message
          });
        });

        req.on('timeout', () => {
          req.destroy();
          resolve({
            success: false,
            provider: 'smartflo_backup',
            errorCode: 'SMARTFLO_TIMEOUT',
            message: 'Smartflo SMS timed out'
          });
        });

        req.write(postData);
        req.end();
      } catch (err) {
        resolve({
          success: false,
          provider: 'smartflo_backup',
          errorCode: 'CONFIG_ERROR',
          message: err.message
        });
      }
    });
  }
}

module.exports = new SmartfloSmsService();
