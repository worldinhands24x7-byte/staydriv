const mongoose = require('mongoose');

async function runConcurrentTests() {
  console.log('====================================================');
  console.log('TESTING CONCURRENT & MULTI-USER IN-APP LOGIN');
  console.log('====================================================\n');

  require('dotenv').config();
  const mongoUri = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/staydriv';
  await mongoose.connect(mongoUri, { serverSelectionTimeoutMS: 4000 });

  const otpController = require('./controllers/otpController');

  function createMockReqRes(body = {}) {
    let resStatus = 200;
    let resData = null;
    const req = { body };
    const res = {
      status(code) { resStatus = code; return this; },
      json(data) { resData = data; return this; }
    };
    return { req, res, getStatus: () => resStatus, getData: () => resData };
  }

  // Simultaneous users: User A (Customer), User B (Customer), User C (Pilot), User D (Pilot)
  console.log('1. Generating codes for 4 users simultaneously...');
  const u1 = createMockReqRes({ mobile: '9111111111', role: 'CUSTOMER' });
  const u2 = createMockReqRes({ mobile: '9222222222', role: 'CUSTOMER' });
  const u3 = createMockReqRes({ mobile: '9333333333', role: 'PILOT' });
  const u4 = createMockReqRes({ mobile: '9444444444', role: 'PILOT' });

  await Promise.all([
    otpController.sendOtp(u1.req, u1.res),
    otpController.sendOtp(u2.req, u2.res),
    otpController.sendOtp(u3.req, u3.res),
    otpController.sendOtp(u4.req, u4.res)
  ]);

  const c1 = u1.getData().verificationCode;
  const c2 = u2.getData().verificationCode;
  const c3 = u3.getData().verificationCode;
  const c4 = u4.getData().verificationCode;

  console.log('All 4 codes generated:', !!c1, !!c2, !!c3, !!c4);

  // Simultaneous verification
  console.log('2. Verifying all 4 users simultaneously...');
  const v1 = createMockReqRes({ mobile: '9111111111', otp: c1, role: 'CUSTOMER' });
  const v2 = createMockReqRes({ mobile: '9222222222', otp: c2, role: 'CUSTOMER' });
  const v3 = createMockReqRes({ mobile: '9333333333', otp: c3, role: 'PILOT' });
  const v4 = createMockReqRes({ mobile: '9444444444', otp: c4, role: 'PILOT' });

  await Promise.all([
    otpController.verifyOtp(v1.req, v1.res),
    otpController.verifyOtp(v2.req, v2.res),
    otpController.verifyOtp(v3.req, v3.res),
    otpController.verifyOtp(v4.req, v4.res)
  ]);

  console.log('U1 Verified:', v1.getData().user.role, v1.getData().user.uid);
  console.log('U2 Verified:', v2.getData().user.role, v2.getData().user.uid);
  console.log('U3 Verified:', v3.getData().user.role, v3.getData().user.uid);
  console.log('U4 Verified:', v4.getData().user.role, v4.getData().user.uid);

  if (v1.getData().user.role !== 'Customer' || v2.getData().user.role !== 'Customer') {
    throw new Error('Customers role mismatch');
  }
  if (v3.getData().user.role !== 'Driver' || v4.getData().user.role !== 'Driver') {
    throw new Error('Pilots role mismatch');
  }

  // 3. Test Logout -> Login again
  console.log('3. Testing Logout -> Login again for U1...');
  // "Logout" simply means client discards token; now u1 logs in again:
  const u1Again = createMockReqRes({ mobile: '9111111111', role: 'CUSTOMER' });
  await otpController.sendOtp(u1Again.req, u1Again.res);
  const c1Again = u1Again.getData().verificationCode;
  const v1Again = createMockReqRes({ mobile: '9111111111', otp: c1Again, role: 'CUSTOMER' });
  await otpController.verifyOtp(v1Again.req, v1Again.res);
  console.log('U1 Logged in again:', v1Again.getData().user.uid, 'Token issued:', !!v1Again.getData().token);

  console.log('\n====================================================');
  console.log('CONCURRENT & MULTI-USER TESTS PASSED (100%)');
  console.log('====================================================');
  await mongoose.disconnect();
  process.exit(0);
}

runConcurrentTests().catch(err => {
  console.error('\nCONCURRENT TEST FAILED:', err);
  process.exit(1);
});
