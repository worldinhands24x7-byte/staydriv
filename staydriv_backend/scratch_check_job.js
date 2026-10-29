require('dotenv').config({ path: './.env' });
const https = require('https');

const TATA_SMS_USER = process.env.TATA_SMS_USER || 'SADGURURL';
const TATA_SMS_PASS = process.env.TATA_SMS_PASS || 'Sadguru@2026';
const TATA_SMS_BASE_URL = (process.env.TATA_SMS_BASE_URL || 'https://ttbssmsgw.tatatel.co.in').replace(/\/+$/, '');

function getReq(urlStr, token) {
  return new Promise((resolve) => {
    const u = new URL(urlStr);
    const req = https.request({
      hostname: u.hostname,
      port: 443,
      path: u.pathname + u.search,
      method: 'GET',
      headers: {
        'Authorization': `bearer ${token}`
      },
      timeout: 10000
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        resolve({ statusCode: res.statusCode, body: data });
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

function postJson(urlStr, postObj) {
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
        'Content-Length': Buffer.byteLength(postData)
      },
      timeout: 10000
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        resolve({ statusCode: res.statusCode, body: data });
      });
    });
    req.on('error', err => resolve({ error: err.message }));
    req.write(postData);
    req.end();
  });
}

async function checkJob() {
  const loginRes = await postJson(`${TATA_SMS_BASE_URL}/login/user`, {
    username: TATA_SMS_USER,
    password: TATA_SMS_PASS
  });
  const parsed = JSON.parse(loginRes.body);
  const token = parsed.access_token || parsed.token;

  const jobId = '4ee44e77-6141-459d-9d0a-38921457a8f4';
  const campaignId = '4ee44e77-6141-459d-9d0a-38921457a8f4';

  const endpoints = [
    `/campaigns/report/${jobId}`,
    `/campaigns/status/${jobId}`,
    `/campaigns/summary/${jobId}`,
    `/campaigns/job/${jobId}`,
    `/campaignService/campaigns/status/${jobId}`,
    `/campaigns/${campaignId}`,
    `/dlog/campaign/${campaignId}`,
    `/dlog/job/${jobId}`,
    `/reports/delivery/${jobId}`,
    `/reports/sms/${jobId}`,
    `/reports/summary/${jobId}`,
    `/templates/sms`,
    `/templates`,
    `/sender-addresses`,
    `/senderAddr`
  ];

  for (const ep of endpoints) {
    const res = await getReq(`${TATA_SMS_BASE_URL}${ep}`, token);
    console.log(`[${ep}] Status: ${res.statusCode} | Response: ${res.body.slice(0, 300)}`);
  }
}

checkJob();
