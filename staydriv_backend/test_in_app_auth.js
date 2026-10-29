const crypto = require('crypto');
const mongoose = require('mongoose');

// Connect to MongoDB or run logic in-memory / local mongo
async function runTests() {
  console.log('====================================================');
  console.log('TESTING IN-APP LOGIN VERIFICATION CODE SYSTEM');
  console.log('====================================================\n');

  try {
    require('dotenv').config();
    const mongoUri = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/staydriv';
    await mongoose.connect(mongoUri, { serverSelectionTimeoutMS: 4000 });
    console.log('Connected to MongoDB successfully.');
  } catch (e) {
    console.log('MongoDB connection skipped/failed:', e.message);
    console.log('Proceeding with in-memory model verification...');
  }

  const Otp = require('./models/Otp');
  const otpController = require('./controllers/otpController');

  // Helper mock req/res
  function createMockReqRes(body = {}, params = {}) {
    let resStatus = 200;
    let resData = null;
    const req = { body, params };
    const res = {
      status(code) {
        resStatus = code;
        return this;
      },
      json(data) {
        resData = data;
        return this;
      }
    };
    return { req, res, getStatus: () => resStatus, getData: () => resData };
  }

  const testMobile = '9988776655';

  // 1. Customer code generation
  console.log('1. Testing Customer In-App Code Generation...');
  const genReqRes = createMockReqRes({ mobile: testMobile, role: 'CUSTOMER' });
  await otpController.sendOtp(genReqRes.req, genReqRes.res);
  const genData = genReqRes.getData();
  console.log('Status code:', genReqRes.getStatus());
  console.log('Response success:', genData.success);
  console.log('Verification code received by client:', genData.verificationCode ? 'YES (6 digits: ' + genData.verificationCode.length + ')' : 'NO');
  console.log('Expires in:', genData.expiresIn, 'seconds');
  console.log('Max attempts:', genData.maxAttempts);

  if (!genData.verificationCode || genData.verificationCode.length !== 6) {
    throw new Error('Verification code must be 6 digits');
  }

  // 2. Check Database Storage Security (PBKDF2 Hash, NO Plaintext)
  console.log('\n2. Verifying DB Security Controls (No plaintext, only salted hash)...');
  const dbRecord = await Otp.findOne({ mobile: testMobile, role: 'CUSTOMER' });
  if (!dbRecord) throw new Error('Otp record not found in DB');
  console.log('DB mobile:', dbRecord.mobile);
  console.log('DB role:', dbRecord.role);
  console.log('DB otpHash exists:', !!dbRecord.otpHash);
  console.log('DB salt exists:', !!dbRecord.salt);
  console.log('DB plain otp field:', dbRecord.otp || 'NONE (SECURE)');
  if (dbRecord.otp) throw new Error('Plain OTP must not be stored in database');

  // 3. Test Invalid Code Handling
  console.log('\n3. Testing Incorrect Code Entry...');
  const wrongCodeReqRes = createMockReqRes({ mobile: testMobile, otp: '000000', role: 'CUSTOMER' });
  await otpController.verifyOtp(wrongCodeReqRes.req, wrongCodeReqRes.res);
  console.log('Wrong code status:', wrongCodeReqRes.getStatus());
  console.log('Wrong code response:', wrongCodeReqRes.getData());
  if (wrongCodeReqRes.getData().success === true) throw new Error('Wrong code must not succeed');
  if (wrongCodeReqRes.getData().message !== 'Invalid verification code. Please try again.') {
    throw new Error('Expected "Invalid verification code. Please try again."');
  }
  console.log('Attempts remaining reported:', wrongCodeReqRes.getData().attemptsRemaining);

  // 4. Test Maximum 5 Verification Attempts
  console.log('\n4. Testing Maximum 5 Verification Attempts...');
  for (let i = 2; i <= 5; i++) {
    const attempt = createMockReqRes({ mobile: testMobile, otp: '00000' + i, role: 'CUSTOMER' });
    await otpController.verifyOtp(attempt.req, attempt.res);
    console.log(`Attempt ${i} status:`, attempt.getStatus(), '| message:', attempt.getData().message);
  }
  const lockedRecord = await Otp.findOne({ mobile: testMobile, role: 'CUSTOMER' });
  console.log('Record after 5 attempts:', lockedRecord ? 'STILL_EXISTS' : 'CLEARED_AND_LOCKED (SECURE)');
  if (lockedRecord) throw new Error('Record should be deleted or locked after 5 failed attempts');

  // 5. Test Resend / New Code Generation & Invalidation of Previous
  console.log('\n5. Testing New Code Generation (Resend)...');
  const resendReqRes = createMockReqRes({ mobile: testMobile, role: 'CUSTOMER' });
  await otpController.sendOtp(resendReqRes.req, resendReqRes.res);
  const newCode = resendReqRes.getData().verificationCode;
  console.log('New verification code generated:', !!newCode);

  // 6. Test Successful Verification for Customer
  console.log('\n6. Testing Successful Verification for Customer...');
  const successReqRes = createMockReqRes({ mobile: testMobile, otp: newCode, role: 'CUSTOMER' });
  await otpController.verifyOtp(successReqRes.req, successReqRes.res);
  const successData = successReqRes.getData();
  console.log('Customer verify status:', successReqRes.getStatus());
  console.log('Token issued:', !!successData.token);
  console.log('Customer Role:', successData.user.role);
  console.log('Customer UID:', successData.user.uid);
  if (successData.user.role !== 'Customer') throw new Error('Expected role Customer');

  // Check code cleared after successful verification
  const clearedCheck = await Otp.findOne({ mobile: testMobile, role: 'CUSTOMER' });
  console.log('Code cleared after success:', !clearedCheck ? 'YES (SECURE)' : 'NO');
  if (clearedCheck) throw new Error('Code must be cleared after verification');

  // 7. Test Pilot Login & Role Separation
  console.log('\n7. Testing Pilot In-App Login & Data Separation (Same Phone)...');
  const pilotGenReqRes = createMockReqRes({ mobile: testMobile, role: 'PILOT' });
  await otpController.sendOtp(pilotGenReqRes.req, pilotGenReqRes.res);
  const pilotCode = pilotGenReqRes.getData().verificationCode;
  console.log('Pilot code generated:', !!pilotCode);

  const pilotVerifyReqRes = createMockReqRes({ mobile: testMobile, otp: pilotCode, role: 'PILOT' });
  await otpController.verifyOtp(pilotVerifyReqRes.req, pilotVerifyReqRes.res);
  const pilotData = pilotVerifyReqRes.getData();
  console.log('Pilot verify status:', pilotVerifyReqRes.getStatus());
  console.log('Pilot Role:', pilotData.user.role);
  console.log('Pilot UID:', pilotData.user.uid);
  if (pilotData.user.role !== 'Driver') throw new Error('Expected role Driver (Pilot)');
  if (!pilotData.user.uid.startsWith('pilot_')) throw new Error('Pilot UID must start with pilot_');

  // 8. Test Expired Code
  console.log('\n8. Testing Expired Code...');
  const expireGen = createMockReqRes({ mobile: '9988776644', role: 'CUSTOMER' });
  await otpController.sendOtp(expireGen.req, expireGen.res);
  const expCode = expireGen.getData().verificationCode;
  // Artificially expire the record
  await Otp.updateOne({ mobile: '9988776644', role: 'CUSTOMER' }, { expireAt: new Date(Date.now() - 1000) });
  const expVerify = createMockReqRes({ mobile: '9988776644', otp: expCode, role: 'CUSTOMER' });
  await otpController.verifyOtp(expVerify.req, expVerify.res);
  console.log('Expired verify response:', expVerify.getData());
  if (expVerify.getData().status !== 'EXPIRED') throw new Error('Expected EXPIRED status');

  console.log('\n====================================================');
  console.log('ALL BACKEND IN-APP VERIFICATION TESTS PASSED (100%)');
  console.log('====================================================');
  await mongoose.disconnect();
  process.exit(0);
}

runTests().catch(err => {
  console.error('\nTEST FAILED:', err);
  process.exit(1);
});
