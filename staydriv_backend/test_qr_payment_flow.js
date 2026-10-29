const http = require('http');

const ALB_HOST = 'staydr20260917190326134500000018-1656960596.ap-south-2.elb.amazonaws.com';
const PORT = 80;

function request(method, path, body = null) {
  return new Promise((resolve, reject) => {
    const postData = body ? JSON.stringify(body) : '';
    const options = {
      hostname: ALB_HOST,
      port: PORT,
      path: path,
      method: method,
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'StayDrivApp/1.0',
        'Accept': 'application/json, text/plain, */*',
        'Bypass-Tunnel-Reminder': 'true',
        'Content-Length': Buffer.byteLength(postData)
      }
    };

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(data);
          resolve({ status: res.statusCode, body: parsed });
        } catch (e) {
          resolve({ status: res.statusCode, body: data });
        }
      });
    });

    req.on('error', (e) => reject(e));
    if (postData) req.write(postData);
    req.end();
  });
}

async function verifyQrPaymentFlow() {
  console.log('=== PILOT QR PAYMENT STABILITY & SPEC VERIFICATION ===\n');

  const testBookingId = `BK_QR_TEST_${Date.now()}`;
  const testPilotId = `PILOT_TEST_${Date.now()}`;
  const fare = 145.00;

  // 1. Create a completed booking with fare ₹145
  console.log('Step 1: Creating completed booking for ride...');
  const createRes = await request('POST', '/api/booking/update', {
    bookingId: testBookingId,
    status: 'completed',
    activeBooking: {
      bookingId: testBookingId,
      driverId: testPilotId,
      price: `₹${fare}`,
      vehicle: 'Auto',
      pickup: 'Kukatpally Metro',
      drop: 'HiTech City Cyber Towers',
      status: 'completed',
      paymentStatus: 'pending'
    }
  });
  console.log('  Create booking status:', createRes.status, createRes.body?.success ? 'SUCCESS' : createRes.body);

  // 2. Fetch QR details first time
  console.log('\nStep 2: Fetching Pilot QR details (Call 1)...');
  const qrRes1 = await request('GET', `/api/pilot/payment/qr/${testBookingId}`);
  console.log('  Call 1 Response:');
  console.log('    UPI URI:', qrRes1.body?.upiUri);
  console.log('    QR Image URL:', qrRes1.body?.qrImageUrl);
  console.log('    Session CreatedAt:', qrRes1.body?.createdAt);
  console.log('    ExpiresAt:', qrRes1.body?.expiresAt);

  // Validate NPCI UPI specs
  const upiUri = qrRes1.body?.upiUri || '';
  if (!upiUri.includes('pa=staydriv@icici') && !upiUri.includes('pa=')) {
    throw new Error('UPI URI missing valid pa parameter');
  }
  if (upiUri.includes('%40')) {
    throw new Error('FAILED: UPI URI contains encoded %40 instead of literal @ ! Scanning apps will reject this.');
  }
  console.log('  [PASS] UPI URI uses literal "@" for NPCI compliance.');

  if (!upiUri.includes('am=145.00')) {
    throw new Error(`FAILED: UPI URI missing formatted amount 145.00, got: ${upiUri}`);
  }
  console.log('  [PASS] UPI URI contains exact fare am=145.00.');

  // 3. Stability check: Call repeatedly to ensure session is 100% stable (no blinking/regenerating)
  console.log('\nStep 3: Verifying QR stability across multiple rapid & delayed calls...');
  for (let i = 2; i <= 5; i++) {
    const qrRes = await request('GET', `/api/pilot/payment/qr/${testBookingId}`);
    if (qrRes.body?.upiUri !== qrRes1.body?.upiUri) {
      throw new Error(`FAILED: QR upiUri changed on call ${i}! Unstable session detected.`);
    }
    if (qrRes.body?.qrImageUrl !== qrRes1.body?.qrImageUrl) {
      throw new Error(`FAILED: QR qrImageUrl changed on call ${i}! Unstable session detected.`);
    }
    if (qrRes.body?.createdAt !== qrRes1.body?.createdAt) {
      throw new Error(`FAILED: QR session createdAt changed on call ${i}! Session re-instantiated.`);
    }
    console.log(`  Call ${i}: Returned IDENTICAL cached session (createdAt: ${qrRes.body?.createdAt}). No blinking.`);
  }

  // 4. Also check customer-facing QR endpoint stability
  console.log('\nStep 4: Checking Customer-facing QR endpoint /api/booking/payment/qr/:id ...');
  const custQrRes = await request('GET', `/api/booking/payment/qr/${testBookingId}`);
  if (custQrRes.body?.upiUri !== qrRes1.body?.upiUri) {
    throw new Error('FAILED: Customer QR does not match Pilot QR session!');
  }
  console.log('  [PASS] Customer QR session matches Pilot QR session identically.');

  // 5. Complete payment (Pilot verifies UPI)
  console.log('\nStep 5: Verifying UPI Payment via /api/pilot/payment/verify-upi ...');
  const verifyRes = await request('POST', '/api/pilot/payment/verify-upi', {
    bookingId: testBookingId,
    pilotId: testPilotId,
    referenceId: `UPI_UTR_${Date.now()}`
  });
  console.log('  Verify UPI status:', verifyRes.status, verifyRes.body);
  if (verifyRes.body?.paymentStatus !== 'paid') {
    throw new Error('FAILED: Booking paymentStatus was not updated to paid');
  }

  // 6. Verify QR is stopped after payment
  console.log('\nStep 6: Checking QR endpoint after payment is completed...');
  const qrResAfter = await request('GET', `/api/pilot/payment/qr/${testBookingId}`);
  console.log('  Post-payment QR response:', qrResAfter.body);
  if (!qrResAfter.body?.alreadyPaid || qrResAfter.body?.paymentStatus !== 'paid') {
    throw new Error('FAILED: QR endpoint should return alreadyPaid: true after payment');
  }
  console.log('  [PASS] Post-payment response shows alreadyPaid: true and stops displaying active QR.');

  // 7. Verify duplicate payment prevention
  console.log('\nStep 7: Testing duplicate payment prevention...');
  const duplicateCashRes = await request('POST', '/api/pilot/payment/confirm-cash', {
    bookingId: testBookingId,
    pilotId: testPilotId
  });
  console.log('  Duplicate cash payment attempt:', duplicateCashRes.body);
  if (!duplicateCashRes.body?.alreadyPaid) {
    throw new Error('FAILED: Server did not reject duplicate payment!');
  }
  console.log('  [PASS] Server blocked duplicate payment and returned alreadyPaid: true.');

  console.log('\n========================================');
  console.log('ALL QR PAYMENT ROOT-CAUSE TESTS PASSED!');
  console.log('========================================');
}

verifyQrPaymentFlow().catch((err) => {
  console.error('\nTEST FAILED:', err.message || err);
  process.exit(1);
});
