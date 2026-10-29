const https = require('https');
const { URL } = require('url');

class SmartfloService {
  constructor() {
    this.inFlightCalls = new Map(); // bookingId:callerRole -> timestamp
  }

  /**
   * Intelligently resolves the JWT API token.
   * If SMARTFLO_CALL_MASKING_API_KEY contains the JWT (starts with eyJ),
   * or SMARTFLO_API_TOKEN contains the JWT, it selects the valid JWT.
   */
  get apiToken() {
    const candidate0 = (process.env.SMARTFLO_CALL_MASKING_TOKEN || '').trim();
    const candidate1 = (process.env.SMARTFLO_CALL_MASKING_API_KEY || '').trim();
    const candidate2 = (process.env.SMARTFLO_API_TOKEN || '').trim();
    const candidate3 = (process.env.TATA_SMARTFLO_JWT_TOKEN || '').trim();
    const defaultToken = 'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzdWIiOiI3OTkyNDIiLCJjciI6ZmFsc2UsImlzcyI6Imh0dHBzOi8vY2xvdWRwaG9uZS50YXRhdGVsZXNlcnZpY2VzLmNvbS90b2tlbi9nZW5lcmF0ZSIsImlhdCI6MTc4NDkxNjA2NiwiZXhwIjoyMDg0OTE2MDY2LCJuYmYiOjE3ODQ5MTYwNjYsImp0aSI6IldFeHVWbXlQeEQwS1d2WDYifQ.ESt-Dm_ubM0uHc0e5jH6weznIfYmAGnFxzMAM8HEe4A';

    if (candidate0.startsWith('eyJ')) return candidate0;
    if (candidate1.startsWith('eyJ')) return candidate1;
    if (candidate2.startsWith('eyJ')) return candidate2;
    if (candidate3.startsWith('eyJ')) return candidate3;
    return defaultToken;
  }

  /**
   * Resolves the API Key identifier (e.g. Callmasking API)
   */
  get apiKey() {
    const candidate1 = (process.env.SMARTFLO_CALL_MASKING_API_KEY || '').trim();
    const candidate2 = (process.env.SMARTFLO_API_TOKEN || '').trim();
    if (candidate1 && !candidate1.startsWith('eyJ')) return candidate1;
    if (candidate2 && !candidate2.startsWith('eyJ')) return candidate2;
    return (process.env.TATA_SMARTFLO_API_KEY || 'CallMaskingAPI').trim();
  }

  /**
   * Tata Smartflo Click-to-Call REST API base URL.
   * If cloudphone.tatateleservices.com is passed, redirects to api-smartflo.tatateleservices.com
   */
  get baseUrl() {
    const raw = (process.env.SMARTFLO_BASE_URL || '').trim();
    if (!raw || raw.includes('cloudphone.tatateleservices.com')) {
      return 'https://api-smartflo.tatateleservices.com';
    }
    return raw.replace(/\/+$/, '');
  }

  get defaultDid() {
    const did = (process.env.SMARTFLO_DID || process.env.TATA_SMARTFLO_VIRTUAL_NUMBER || '8065916303').trim();
    return this.formatPhone(did) || '8065916303';
  }

  get callTimeout() {
    return parseInt(process.env.SMARTFLO_CALL_TIMEOUT || '300', 10);
  }

  /**
   * Cleans and normalizes Indian phone numbers to 10 digits
   */
  formatPhone(phone) {
    if (!phone) return '';
    let cleaned = String(phone).replace(/\D/g, '');
    if (cleaned.length === 12 && cleaned.startsWith('91')) {
      cleaned = cleaned.substring(2);
    } else if (cleaned.length === 11 && cleaned.startsWith('0')) {
      cleaned = cleaned.substring(1);
    }
    if (cleaned.length > 10) {
      cleaned = cleaned.slice(-10);
    }
    return cleaned;
  }

  /**
   * Masks phone numbers for secure logging (e.g. 98******21)
   */
  maskPhone(phone) {
    const cleaned = this.formatPhone(phone);
    if (cleaned.length < 4) return '******';
    const first2 = cleaned.substring(0, 2);
    const last2 = cleaned.substring(cleaned.length - 2);
    return `${first2}******${last2}`;
  }

  /**
   * In-memory debounce lock (45s window) to prevent rapid multi-taps
   */
  checkAndAcquireCallLock(bookingId, callerRole) {
    const key = `${bookingId}:${callerRole}`;
    const now = Date.now();
    const existingTime = this.inFlightCalls.get(key);

    if (existingTime && (now - existingTime) < 45000) {
      const waitSec = Math.ceil((45000 - (now - existingTime)) / 1000);
      return { acquired: false, retryAfter: waitSec };
    }

    this.inFlightCalls.set(key, now);
    return { acquired: true };
  }

  releaseCallLock(bookingId, callerRole) {
    const key = `${bookingId}:${callerRole}`;
    this.inFlightCalls.delete(key);
  }

  /**
   * Initiates Tata Smartflo Click-to-Call bridging
   */
  async initiateClickToCall({ agentPhone, destinationPhone, virtualNumber, callTimeout, bookingId }) {
    const token = this.apiToken;
    if (!token) {
      throw new Error('TATA Smartflo API Token is not configured on server.');
    }

    const cleanAgent = this.formatPhone(agentPhone);
    const cleanDest = this.formatPhone(destinationPhone);

    if (cleanAgent.length !== 10 || cleanDest.length !== 10) {
      throw new Error('Invalid agent or destination phone number. Must be 10 digits.');
    }

    const payload = {
      agent_number: cleanAgent,
      destination_number: cleanDest,
      async: 1,
      call_timeout: callTimeout || this.callTimeout
    };

    // Attach custom_identifier so Tata Smartflo webhooks correlate back to bookingId
    if (bookingId) {
      payload.custom_identifier = String(bookingId);
    }

    // Only attach caller_id if a valid DID is explicitly configured
    const did = virtualNumber || this.defaultDid;
    if (did) {
      payload.caller_id = did;
    }

    const apiUrl = `${this.baseUrl}/v1/click_to_call`;
    console.log(`[Smartflo] Calling ${apiUrl} with Agent: ${this.maskPhone(cleanAgent)} -> Destination: ${this.maskPhone(cleanDest)} (booking: ${bookingId || 'none'})`);

    const postData = JSON.stringify(payload);
    const parsedUrl = new URL(apiUrl);
    const options = {
      hostname: parsedUrl.hostname,
      port: parsedUrl.port || 443,
      path: parsedUrl.pathname + parsedUrl.search,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`,
        'x-api-key': this.apiKey,
        'Content-Length': Buffer.byteLength(postData)
      },
      timeout: 15000
    };

    return new Promise((resolve, reject) => {
      const req = https.request(options, (res) => {
        let rawBody = '';
        res.on('data', chunk => rawBody += chunk);
        res.on('end', () => {
          console.log(`[Smartflo] Response Status: ${res.statusCode}`);
          let parsed;
          try {
            parsed = JSON.parse(rawBody);
          } catch (_) {
            parsed = { raw: rawBody };
          }

          if (res.statusCode >= 200 && res.statusCode < 300) {
            resolve({
              success: true,
              statusCode: res.statusCode,
              refId: parsed.ref_id || parsed.call_id || parsed.id || null,
              message: parsed.message || 'Call successfully queued',
              data: parsed
            });
          } else {
            console.error(`[Smartflo Error ${res.statusCode}]:`, rawBody);
            reject(new Error(parsed.message || parsed.error || `Smartflo returned HTTP ${res.statusCode}`));
          }
        });
      });

      req.on('error', (err) => {
        console.error('[Smartflo Network Error]:', err.message);
        reject(new Error(`Failed to communicate with Tata Smartflo: ${err.message}`));
      });

      req.on('timeout', () => {
        req.destroy();
        reject(new Error('Tata Smartflo request timed out.'));
      });

      req.write(postData);
      req.end();
    });
  }
}

module.exports = new SmartfloService();
