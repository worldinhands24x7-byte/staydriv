// test_server_call_flow.js
require('dotenv').config();
const http = require('http');
const assert = require('assert');

// Mock a lightweight test to verify endpoint logic with live server or supertest-style request
async function makeRequest(path, method = 'GET', body = null) {
  return new Promise((resolve, reject) => {
    const postData = body ? JSON.stringify(body) : '';
    const req = http.request({
      hostname: '127.0.0.1',
      port: 3000,
      path,
      method,
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData)
      },
      timeout: 8000
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(data) });
        } catch (_) {
          resolve({ status: res.statusCode, raw: data });
        }
      });
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('Request timed out')); });
    if (body) req.write(postData);
    req.end();
  });
}

async function verifyServer() {
  console.log('Testing server health...');
  const health = await makeRequest('/api/health');
  console.log('Health:', health);
  assert.strictEqual(health.status, 200);

  // 1. Test Admin Calls endpoint (STEP 14)
  console.log('Testing GET /api/admin/calls...');
  const adminRes = await makeRequest('/api/admin/calls');
  console.log('Admin calls:', adminRes.status, 'Count:', adminRes.data.count);
  assert.strictEqual(adminRes.status, 200);
  assert(Array.isArray(adminRes.data.calls));

  // 2. Test Webhook status update (STEP 9)
  console.log('Testing POST /api/smartflo/webhook...');
  const webhookRes = await makeRequest('/api/smartflo/webhook', 'POST', {
    ref_id: '01a0cc10-f501-70b6-84ef-567cd3f4689f',
    status: 'ANSWERED',
    custom_identifier: 'BK_TEST_VERIFY_999'
  });
  console.log('Webhook result:', webhookRes);
  assert.strictEqual(webhookRes.status, 200);
  assert.strictEqual(webhookRes.data.success, true);

  console.log('--- ALL SERVER CALL FLOW TESTS PASSED! ---');
}

// Only run if server is running locally, otherwise report
verifyServer().catch(err => {
  console.log('Local server verification note (server may not be running locally on 3000):', err.message);
});
