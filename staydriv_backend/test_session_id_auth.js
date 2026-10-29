const mongoose = require('mongoose');

async function testSessionIsolation() {
  require('dotenv').config();
  const mongoUri = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/staydriv';
  await mongoose.connect(mongoUri);

  const otpController = require('./controllers/otpController');

  function createMockReqRes(body = {}) {
    let resStatus = 200;
    let resData = null;
    return {
      req: { body, params: {} },
      res: {
        status(code) { resStatus = code; return this; },
        json(data) { resData = data; return this; }
      },
      getStatus: () => resStatus,
      getData: () => resData
    };
  }

  console.log('Testing User A and User B session isolation...');
  const reqA = createMockReqRes({ mobile: '9111111111', role: 'CUSTOMER' });
  await otpController.sendOtp(reqA.req, reqA.res);
  const dataA = reqA.getData();

  const reqB = createMockReqRes({ mobile: '9222222222', role: 'CUSTOMER' });
  await otpController.sendOtp(reqB.req, reqB.res);
  const dataB = reqB.getData();

  console.log('User A Session:', dataA.verificationSessionId, 'Code:', dataA.verificationCode);
  console.log('User B Session:', dataB.verificationSessionId, 'Code:', dataB.verificationCode);

  // User A enters User B's code with Session A
  const wrongCodeReq = createMockReqRes({
    mobile: '9111111111',
    code: dataB.verificationCode,
    role: 'CUSTOMER',
    verificationSessionId: dataA.verificationSessionId
  });
  await otpController.verifyOtp(wrongCodeReq.req, wrongCodeReq.res);
  console.log('User A using User B code status:', wrongCodeReq.getStatus(), 'success:', wrongCodeReq.getData().success);
  if (wrongCodeReq.getData().success === true) throw new Error('Cross-user verification should fail!');

  // User A enters User A's code with Session A
  const correctReqA = createMockReqRes({
    mobile: '9111111111',
    code: dataA.verificationCode,
    role: 'CUSTOMER',
    verificationSessionId: dataA.verificationSessionId
  });
  await otpController.verifyOtp(correctReqA.req, correctReqA.res);
  console.log('User A using correct code status:', correctReqA.getStatus(), 'success:', correctReqA.getData().success);
  if (correctReqA.getData().success !== true) throw new Error('User A verification should succeed!');

  // User B enters User B's code with Session B
  const correctReqB = createMockReqRes({
    mobile: '9222222222',
    code: dataB.verificationCode,
    role: 'CUSTOMER',
    verificationSessionId: dataB.verificationSessionId
  });
  await otpController.verifyOtp(correctReqB.req, correctReqB.res);
  console.log('User B using correct code status:', correctReqB.getStatus(), 'success:', correctReqB.getData().success);
  if (correctReqB.getData().success !== true) throw new Error('User B verification should succeed!');

  console.log('SESSION ISOLATION TEST PASSED 100%!');
  process.exit(0);
}

testSessionIsolation();
