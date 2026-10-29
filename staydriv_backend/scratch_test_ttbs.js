require('dotenv').config({ path: './.env' });
const https = require('https');

const TATA_SMS_USER = process.env.TATA_SMS_USER || 'SADGURURL';
const TATA_SMS_PASS = process.env.TATA_SMS_PASS || 'Sadguru@2026';
const TATA_SMS_SENDER = process.env.TATA_SMS_SENDER || 'SRL';
const TATA_SMS_PE_ID = process.env.TATA_SMS_PE_ID || '1601419178359745779';
const TATA_SMS_TM_ID = process.env.TATA_SMS_TM_ID || '1602763178359960154';
const TATA_SMS_TEMPLATE_ID = process.env.TATA_SMS_TEMPLATE_ID || '1677100000000387025';
const TATA_SMS_BASE_URL = (process.env.TATA_SMS_BASE_URL || 'https://ttbssmsgw.tatatel.co.in').replace(/\/+$/, '');
const targetPhone = '919247535068';

console.log('=== TTBS DIAGNOSTIC TEST ===');
console.log('Base URL:', TATA_SMS_BASE_URL);
console.log('User:', TATA_SMS_USER);
console.log('Sender:', TATA_SMS_SENDER);
console.log('PE ID:', TATA_SMS_PE_ID);
console.log('TM ID:', TATA_SMS_TM_ID);
console.log('Template ID:', TATA_SMS_TEMPLATE_ID);
console.log('Target Phone:', targetPhone);

function postJson(urlStr, postObj, headers = {}) {
  return new Promise((resolve) => {
    const u = new URL(urlStr);
    const postData = JSON.stringify(postObj);
    const req = https.request({
      hostname: u.hostname,
      port: 443,
      path: u.pathname + u.search,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData),
        ...headers
      },
      timeout: 10000
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        resolve({ statusCode: res.statusCode, headers: res.headers, body: data });
      });
    });
    req.on('error', err => resolve({ error: err.message }));
    req.on('timeout', () => {
      req.destroy();
      resolve({ error: 'Timeout' });
    });
    req.write(postData);
    req.end();
  });
}

function getReq(urlStr) {
  return new Promise((resolve) => {
    const u = new URL(urlStr);
    const req = https.request({
      hostname: u.hostname,
      port: 443,
      path: u.pathname + u.search,
      method: 'GET',
      timeout: 10000
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        resolve({ statusCode: res.statusCode, headers: res.headers, body: data });
      });
    });
    req.on('error', err => resolve({ error: err.message }));
    req.on('timeout', () => {
      req.destroy();
      resolve({ error: 'Timeout' });
    });
    req.end();
  });
}

async function test() {
  console.log('\n--- STEP 1: AUTHENTICATING WITH TTBS (/login/user) ---');
  const loginRes = await postJson(`${TATA_SMS_BASE_URL}/login/user`, {
    username: TATA_SMS_USER,
    password: TATA_SMS_PASS
  });
  console.log('Login Status:', loginRes.statusCode);
  console.log('Login Response:', loginRes.body);

  let token = null;
  try {
    const parsed = JSON.parse(loginRes.body);
    token = parsed.access_token || parsed.token;
  } catch (_) {}

  if (!token) {
    console.error('Failed to get token!');
    return;
  }
  console.log('Token obtained successfully (length:', token.length, ')');

  const otp = '849201';
  // Check both template variations:
  // Variation A: with SADGURU ROAD LINES
  // Variation B: without SADGURU ROAD LINES
  const msgA = `Your One-Time Password (OTP) is ${otp}. This OTP is valid for 10 minutes. Do not share it with anyone. SADGURU ROAD LINES`;
  const msgB = `Your One-Time Password (OTP) is ${otp}. This OTP is valid for 10 minutes. Do not share it with anyone.`;

  console.log('\n--- STEP 2: TEST REST API (/campaigns/submissions/sms/nb) with msgA ---');
  // IST time
  const istMillis = Date.now() + (5.5 * 60 * 60 * 1000) + (10 * 60 * 1000);
  const d = new Date(istMillis);
  const pad = n => String(n).padStart(2, '0');
  const expiryDt = `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())} ${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}:${pad(d.getUTCSeconds())}`;

  const payloadA = {
    msgCategory: '4.2',
    contentType: '3.1',
    senderAddr: TATA_SMS_SENDER,
    peId: TATA_SMS_PE_ID,
    cusTemplateId: TATA_SMS_TEMPLATE_ID,
    priority: 1,
    clientTxnId: 'STAYDRIV_DIAG_' + Date.now(),
    recipient: targetPhone,
    msg: msgA,
    expiryDt: expiryDt,
    dr: '1'
  };
  console.log('Payload A:', JSON.stringify(payloadA, null, 2));

  const sendResA = await postJson(`${TATA_SMS_BASE_URL}/campaigns/submissions/sms/nb`, payloadA, {
    'Authorization': `bearer ${token}`
  });
  console.log('Send A Status:', sendResA.statusCode);
  console.log('Send A Response:', sendResA.body);

  console.log('\n--- STEP 3: TEST REST API (/campaigns/submissions/sms/nb) with msgB ---');
  const payloadB = {
    ...payloadA,
    clientTxnId: 'STAYDRIV_DIAG_' + (Date.now() + 1),
    msg: msgB
  };
  const sendResB = await postJson(`${TATA_SMS_BASE_URL}/campaigns/submissions/sms/nb`, payloadB, {
    'Authorization': `bearer ${token}`
  });
  console.log('Send B Status:', sendResB.statusCode);
  console.log('Send B Response:', sendResB.body);

  console.log('\n--- STEP 4: TEST QUICK SEND API (QS) ---');
  const qsParamsA = new URLSearchParams({
    recipient: targetPhone,
    dr: 'true',
    msg: msgA,
    user: TATA_SMS_USER,
    pswd: TATA_SMS_PASS,
    sender: TATA_SMS_SENDER,
    PE_ID: TATA_SMS_PE_ID,
    Template_ID: TATA_SMS_TEMPLATE_ID
  });
  const qsResA = await getReq(`${TATA_SMS_BASE_URL}/campaignService/campaigns/qs?${qsParamsA.toString()}`);
  console.log('QS A Status:', qsResA.statusCode);
  console.log('QS A Response:', qsResA.body);

  const qsParamsB = new URLSearchParams({
    recipient: targetPhone,
    dr: 'true',
    msg: msgB,
    user: TATA_SMS_USER,
    pswd: TATA_SMS_PASS,
    sender: TATA_SMS_SENDER,
    PE_ID: TATA_SMS_PE_ID,
    Template_ID: TATA_SMS_TEMPLATE_ID
  });
  const qsResB = await getReq(`${TATA_SMS_BASE_URL}/campaignService/campaigns/qs?${qsParamsB.toString()}`);
  console.log('QS B Status:', qsResB.statusCode);
  console.log('QS B Response:', qsResB.body);
}

test();
