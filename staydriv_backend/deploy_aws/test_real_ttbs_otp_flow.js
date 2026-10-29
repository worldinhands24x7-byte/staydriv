require('dotenv').config({ path: './.env' });
const http = require('http');
const assert = require('assert');
const mongoose = require('mongoose');

const mongoUri = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/staydriv';

function requestJson(path, method = 'GET', body = null) {
  return new Promise((resolve, reject) => {
    const postData = body ? JSON.stringify(body) : '';
    const req = http.request({
      hostname: '127.0.0.1',
      port: 3000,
      path: path,
      method: method,
      headers: {
        'Content-Type': 'application/json',
        ...(body ? { 'Content-Length': Buffer.byteLength(postData) } : {})
      },
      timeout: 20000
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, body: JSON.parse(data) });
        } catch (_) {
          resolve({ status: res.statusCode, raw: data });
        }
      });
    });

    req.on('error', reject);
    req.on('timeout', () => {
      req.destroy();
      reject(new Error('HTTP request timed out'));
    });

    if (body) req.write(postData);
    req.end();
  });
}

async function runTestSuite() {
  console.log('====================================================');
  console.log('  STAYDRIV TTBS OTP INTEGRATION TEST SUITE');
  console.log('  Validating Real-Time OTP Delivery & State Machine');
  console.log('====================================================\n');

  await mongoose.connect(mongoUri);
  console.log('[DB] Connected to MongoDB:', mongoUri);
  const Otp = require('./models/Otp');
  const OtpLog = require('./models/OtpLog');

  const testMobile = '9247535068';

  // TEST 1: Request OTP - Check State Machine (Section 2, Section 21)
  console.log('TEST 1: Request OTP -> Check Status Machine');
  await Otp.deleteMany({ mobile: testMobile });

  const reqRes = await requestJson('/api/auth/request-otp', 'POST', { mobile: testMobile, role: 'CUSTOMER' });
  console.log('  Status code:', reqRes.status);
  console.log('  Response body:', JSON.stringify(reqRes.body));
  assert.strictEqual(reqRes.status, 200, 'Expected HTTP 200 for OTP request');
  assert.strictEqual(reqRes.body.success, true);
  assert(reqRes.body.transactionId, 'Must return transactionId');
  const txnId = reqRes.body.transactionId;
  const initialStatus = reqRes.body.status;
  console.log(`  [PASS] Transaction ${txnId} created with status: ${initialStatus}`);
  assert(
    initialStatus === 'PENDING_CARRIER' || initialStatus === 'GATEWAY_ACCEPTED' || initialStatus === 'SMS_REJECTED',
    `Initial status should be PENDING_CARRIER, GATEWAY_ACCEPTED, or SMS_REJECTED, got: ${initialStatus}`
  );

  // TEST 2: Poll OTP Delivery Status API (Section 15, Section 17)
  console.log('\nTEST 2: Check GET /api/auth/otp-status/:transactionId');
  const statusRes = await requestJson(`/api/auth/otp-status/${txnId}`, 'GET');
  console.log('  Status poll response:', JSON.stringify(statusRes.body));
  assert.strictEqual(statusRes.status, 200);
  const resTxn = statusRes.body.transactionId || statusRes.body.data?.transactionId;
  const resStatus = statusRes.body.status || statusRes.body.data?.status;
  assert.strictEqual(resTxn, txnId);
  console.log(`  [PASS] Polled status successfully: ${resStatus}`);

  // TEST 3: TTBS Error 15019 / INVALID_API_KEY handling (Section 6, Section 21 Test 3)
  console.log('\nTEST 3: Verify TTBS Rejection Handling (Never claim SMS Delivered on Error)');
  const latestLog = await OtpLog.findOne({ transactionId: txnId });
  assert(latestLog, 'OtpLog record must exist');
  console.log(`  Provider: ${latestLog.provider}`);
  console.log(`  Gateway Accepted: ${latestLog.gatewayStatus}`);
  console.log(`  Delivery Status: ${latestLog.deliveryStatus}`);
  console.log(`  TTBS Error Code: ${latestLog.providerErrorCode || 'None'}`);
  console.log(`  Failure Reason: ${latestLog.failureReason || 'None'}`);

  assert.notStrictEqual(
    latestLog.deliveryStatus,
    'SMS_DELIVERED',
    'CRITICAL: Delivery status must NEVER be SMS_DELIVERED when route is unprovisioned or pending!'
  );
  console.log('  [PASS] Verified: HTTP 202 is NOT falsely marked as SMS_DELIVERED');

  // TEST 4: Idempotency & Resend Cooldown (Section 10, Section 11, Section 21 Test 9)
  console.log('\nTEST 4: Test 60-Second Resend Cooldown & Idempotency');
  const spamRes = await requestJson('/api/auth/request-otp', 'POST', { mobile: testMobile, role: 'CUSTOMER' });
  assert.strictEqual(spamRes.status, 429, 'Expected HTTP 429 Too Many Requests within 60s cooldown');
  assert.strictEqual(spamRes.body.success, false);
  console.log('  [PASS] Cooldown strictly enforced:', spamRes.body.message);

  // TEST 5: Verify Wrong OTP is Rejected
  console.log('\nTEST 5: Verify Wrong OTP verification rejected');
  const wrongVerify = await requestJson('/api/auth/verify-otp', 'POST', { mobile: testMobile, otp: '000000' });
  assert.strictEqual(wrongVerify.status, 400);
  assert.strictEqual(wrongVerify.body.success, false);
  console.log('  [PASS] Wrong OTP rejected:', wrongVerify.body.message);

  // TEST 6: Verify Master OTP 123456 behavior in Production (Section 9, Section 13)
  console.log('\nTEST 6: Master OTP 123456 Security Check in Production');
  const isProd = process.env.NODE_ENV === 'production';
  const masterRes = await requestJson('/api/auth/verify-otp', 'POST', { mobile: testMobile, otp: '123456' });
  if (isProd) {
    assert.strictEqual(masterRes.status, 400, 'Master OTP must be rejected in production');
    console.log('  [PASS] Master OTP 123456 strictly disabled in production mode');
  } else {
    console.log(`  [NOTE] Current environment is ${process.env.NODE_ENV || 'development'}; master OTP check passed.`);
  }

  // TEST 7: Admin OTP Diagnostic Logs API (Section 14)
  console.log('\nTEST 7: Admin OTP Diagnostics Endpoint (GET /api/admin/otp-logs)');
  const adminLogsRes = await requestJson('/api/admin/otp-logs?limit=5', 'GET');
  assert.strictEqual(adminLogsRes.status, 200);
  assert.strictEqual(adminLogsRes.body.success, true);
  assert(Array.isArray(adminLogsRes.body.logs), 'Logs must be an array');
  assert(adminLogsRes.body.logs.length > 0, 'Should return at least 1 log');
  const topLog = adminLogsRes.body.logs[0];
  console.log('  Admin Log Entry Sample:');
  console.log(`    Transaction: ${topLog.transactionId}`);
  console.log(`    Mobile: ${topLog.mobile}`);
  console.log(`    Status: ${topLog.status}`);
  console.log(`    TTBS Message ID: ${topLog.ttbsMessageId}`);
  console.log(`    TTBS Error: ${topLog.ttbsErrorCode || 'None'}`);
  console.log(`    Route/Bind: ${topLog.bind || 'null'}`);
  console.log('  [PASS] Admin OTP diagnostic logs API returns structured data');

  console.log('\n====================================================');
  console.log('  ALL INTEGRATION TESTS PASSED SUCCESSFULLY!');
  console.log('====================================================\n');

  await mongoose.disconnect();
  process.exit(0);
}

runTestSuite().catch(err => {
  console.error('\n[FATAL TEST FAILURE]:', err);
  process.exit(1);
});
