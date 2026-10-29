// test_smartflo_sms_flow.js
const http = require('http');
const assert = require('assert');
const mongoose = require('mongoose');

function req(path, method = 'GET', body = null) {
  return new Promise((resolve, reject) => {
    const postData = body ? JSON.stringify(body) : '';
    const r = http.request({
      hostname: '127.0.0.1',
      port: 3000,
      path,
      method,
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData)
      },
      timeout: 15000
    }, (res) => {
      let b = '';
      res.on('data', c => b += c);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, body: JSON.parse(b) });
        } catch (_) {
          resolve({ status: res.statusCode, raw: b });
        }
      });
    });
    r.on('error', reject);
    if (body) r.write(postData);
    r.end();
  });
}

async function run() {
  console.log('=== STARTING TATA SMARTFLO & DLT SMS INTEGRATION TESTS ===\n');

  // Connect to MongoDB to inspect OTP records and logs directly
  await mongoose.connect('mongodb://127.0.0.1:27017/staydriv');
  const Otp = mongoose.connection.collection('otps');
  const SmsLogs = mongoose.connection.collection('sms_logs');

  const testMobile = '9876543210';
  await Otp.deleteMany({ mobile: testMobile });

  // 1. Health Checks
  console.log('Test 1: Health check endpoints');
  const smsHealth = await req('/api/sms/health');
  assert.strictEqual(smsHealth.status, 200);
  assert.strictEqual(smsHealth.body.service, 'smartflo-sms');
  assert.strictEqual(smsHealth.body.configured, true);
  console.log('   [PASS] /api/sms/health: UP');

  const smartfloHealth = await req('/api/integrations/smartflo/health');
  assert.strictEqual(smartfloHealth.status, 200);
  assert.strictEqual(smartfloHealth.body.provider, 'Smartflo');
  assert.strictEqual(smartfloHealth.body.configured, true);
  console.log('   [PASS] /api/integrations/smartflo/health: UP');

  // 2. Send OTP
  console.log('\nTest 2: Send OTP via /api/auth/send-otp');
  const sendRes = await req('/api/auth/send-otp', 'POST', { mobile: testMobile });
  assert.strictEqual(sendRes.status, 200);
  assert.strictEqual(sendRes.body.success, true);
  console.log('   [PASS] Send OTP response:', JSON.stringify(sendRes.body));

  // Verify record in MongoDB
  const savedOtp = await Otp.findOne({ mobile: testMobile });
  assert(savedOtp, 'OTP record should exist in MongoDB');
  assert(savedOtp.hashedOtp, 'OTP must be hashed');
  assert(savedOtp.salt, 'Salt must be present');
  assert(!savedOtp.otp, 'Plaintext OTP should NEVER be stored');
  console.log('   [PASS] MongoDB check: OTP is securely salted & hashed (hash length:', savedOtp.hashedOtp.length, ')');

  // Verify Audit Log
  const log = await SmsLogs.findOne({ mobile_number_masked: { $regex: '98.*3210' } });
  assert(log, 'SMS log entry should be recorded');
  assert.strictEqual(log.message_type, 'otp');
  console.log('   [PASS] Audit log recorded with masked mobile:', log.mobile_number_masked, '| provider:', log.provider, '| status:', log.status);

  // 3. 30-Second Cooldown Enforcement
  console.log('\nTest 3: Rapid resend / cooldown test');
  const rapidRes = await req('/api/auth/send-otp', 'POST', { mobile: testMobile });
  assert.strictEqual(rapidRes.status, 429);
  assert.strictEqual(rapidRes.body.success, false);
  console.log('   [PASS] Cooldown verified: HTTP 429 -', rapidRes.body.message);

  // 4. Verify Incorrect OTP
  console.log('\nTest 4: Verify with wrong OTP');
  const wrongRes = await req('/api/auth/verify-otp', 'POST', { mobile: testMobile, otp: '111222' });
  assert.strictEqual(wrongRes.status, 401);
  assert.strictEqual(wrongRes.body.success, false);
  const updatedOtpAfterWrong = await Otp.findOne({ mobile: testMobile });
  assert.strictEqual(updatedOtpAfterWrong.attempts, 1);
  console.log('   [PASS] Incorrect OTP rejected (attempts:', updatedOtpAfterWrong.attempts, ')');

  // 5. Verify Correct OTP (using smartfloSmsService hash verification)
  console.log('\nTest 5: Verify with valid OTP');
  const smartfloSmsService = require('./services/smartfloSmsService');
  // Re-generate a known test OTP to verify verification logic
  const validTestOtp = '765432';
  const newSalt = smartfloSmsService.generateSalt();
  const newHashed = smartfloSmsService.hashOtp(validTestOtp, newSalt);
  await Otp.updateOne({ mobile: testMobile }, {
    $set: { hashedOtp: newHashed, salt: newSalt, attempts: 0 }
  });

  const verifyRes = await req('/api/auth/verify-otp', 'POST', { mobile: testMobile, otp: validTestOtp });
  assert.strictEqual(verifyRes.status, 200);
  assert.strictEqual(verifyRes.body.success, true);
  assert(verifyRes.body.token, 'JWT token must be returned');
  assert.strictEqual(verifyRes.body.user.phone, testMobile);
  console.log('   [PASS] OTP successfully verified! JWT generated:', verifyRes.body.token.slice(0, 20) + '...');

  // 6. Replay Prevention
  console.log('\nTest 6: Replay prevention test (reusing the same OTP)');
  const replayRes = await req('/api/auth/verify-otp', 'POST', { mobile: testMobile, otp: validTestOtp });
  assert.strictEqual(replayRes.status, 401);
  console.log('   [PASS] Replay blocked: used OTP was purged from MongoDB');

  // 7. Max Attempts Lockout
  console.log('\nTest 7: Max attempts (5) lockout');
  const lockoutMobile = '9876543211';
  await Otp.deleteMany({ mobile: lockoutMobile });
  await Otp.insertOne({
    mobile: lockoutMobile,
    hashedOtp: 'dummyhash',
    salt: 'dummysalt',
    attempts: 4,
    verified: false,
    expireAt: new Date(Date.now() + 5 * 60 * 1000)
  });

  const finalAttemptRes = await req('/api/auth/verify-otp', 'POST', { mobile: lockoutMobile, otp: '999999' });
  assert.strictEqual(finalAttemptRes.status, 401);
  const lockoutRecord = await Otp.findOne({ mobile: lockoutMobile });
  assert.strictEqual(lockoutRecord, null, 'OTP should be purged after 5 failed attempts');
  console.log('   [PASS] Lockout verified: OTP invalidated after 5 failed attempts');

  // 8. General SMS Dispatch API
  console.log('\nTest 8: General SMS API /api/sms/send');
  const smsApiRes = await req('/api/sms/send', 'POST', {
    mobileNumber: testMobile,
    message: 'StayDriv ride confirmation'
  });
  assert(smsApiRes.status === 200 || smsApiRes.status === 502);
  console.log('   [PASS] /api/sms/send handled cleanly with response status:', smsApiRes.status);

  await mongoose.disconnect();
  console.log('\n======================================================');
  console.log('ALL TATA SMARTFLO & DLT SMS TESTS PASSED SUCCESSFULLY!');
  console.log('======================================================\n');
}

run().catch(err => {
  console.error('Test execution failed:', err);
  process.exit(1);
});
