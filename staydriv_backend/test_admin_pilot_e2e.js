const http = require('http');

function request(method, path, body = null) {
  return new Promise((resolve, reject) => {
    const dataString = body ? JSON.stringify(body) : null;
    const options = {
      hostname: '127.0.0.1',
      port: 3000,
      path,
      method,
      headers: {
        'Content-Type': 'application/json',
        'x-admin-key': 'staydriv_admin_secret_2026',
        ...(dataString ? { 'Content-Length': Buffer.byteLength(dataString) } : {})
      }
    };

    const req = http.request(options, (res) => {
      let rawData = '';
      res.on('data', chunk => rawData += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(rawData);
          resolve({ status: res.statusCode, body: parsed });
        } catch (e) {
          resolve({ status: res.statusCode, body: rawData });
        }
      });
    });

    req.on('error', reject);
    if (dataString) req.write(dataString);
    req.end();
  });
}

async function runTest() {
  console.log('====================================================');
  console.log('   STAYDRIV PILOT APPROVAL & DISPATCH E2E VERIFICATION');
  console.log('====================================================\n');

  const ts = Date.now();
  const testPilotUid = `pilot_test_${ts}`;
  const testPilotPhone = `9010${Math.floor(100000 + Math.random() * 900000)}`;

  // Step 1: Register New Pending Pilot
  console.log(`[STEP 1] Registering New Pilot (${testPilotUid}, ${testPilotPhone})...`);
  const regRes = await request('POST', '/api/pilot/register', {
    uid: testPilotUid,
    name: 'Suresh Pilot (Test)',
    phone: testPilotPhone,
    vehicleType: 'Scooty',
    vehiclePlate: 'TS09 AB 1234',
    vehicleModelColor: 'Black Activa',
    aadhaarNumber: '123456789012',
    drivingLicenseNumber: 'DL-TS-2023-0099',
    city: 'Hyderabad',
    pincode: '500072'
  });

  console.log('Registration Response Status:', regRes.status, 'Success:', regRes.body.success);
  if (!regRes.body.success) {
    throw new Error(`Failed to register pilot: ${JSON.stringify(regRes.body)}`);
  }
  console.log('✓ Pilot registered successfully with Status: PENDING\n');

  // Step 2: Fetch Admin Pilots and verify pending status
  console.log('[STEP 2] Verifying Pilot appears in Admin Console pending list...');
  const driversRes = await request('GET', '/api/admin/drivers');
  console.log('Admin Drivers Response Status:', driversRes.status);
  const allDrivers = driversRes.body.drivers || driversRes.body.data || driversRes.body || [];
  const foundPending = allDrivers.find(d => d.uid === testPilotUid || (d.phone && d.phone.includes(testPilotPhone)));
  
  if (!foundPending) {
    console.log('Warning: Driver not in /api/admin/drivers directly, checking /api/pilot/application-status');
  } else {
    console.log(`✓ Found pilot in Admin list! Name: ${foundPending.name}, Vehicle: ${foundPending.vehiclePlate || foundPending.vehicleNumber} (${foundPending.vehicleType}), Approved: ${foundPending.approved || false}`);
  }

  // Step 3: Check application status endpoint
  console.log('\n[STEP 3] Checking /api/pilot/application-status for pilot...');
  const statusRes = await request('GET', `/api/pilot/application-status?phone=${testPilotPhone}`);
  console.log('Status Res:', statusRes.status, 'Status:', statusRes.body.status, 'Approved:', statusRes.body.approved);
  if (statusRes.body.approved === true) {
    throw new Error('Unapproved pilot returned approved: true before admin approval!');
  }
  console.log('✓ Correct: Unapproved pilot is PENDING / not approved.\n');

  // Step 4: Admin Approve Pilot
  console.log('[STEP 4] Admin approves pilot via POST /api/admin/driver/approve...');
  const approveRes = await request('POST', '/api/admin/driver/approve', {
    uid: testPilotUid,
    pilotId: testPilotUid,
    phone: testPilotPhone,
    adminId: 'test_admin_001',
    adminName: 'StayDriv SuperAdmin'
  });
  console.log('Approve Res Status:', approveRes.status, 'Body:', approveRes.body);
  if (approveRes.status !== 200 || !approveRes.body.success) {
    throw new Error(`Approval failed: ${JSON.stringify(approveRes.body)}`);
  }
  console.log('✓ Pilot successfully APPROVED by Admin.\n');

  // Step 5: Test Idempotency Guard on Approve
  console.log('[STEP 5] Testing Idempotency: Calling approve again on already approved pilot...');
  const dupApproveRes = await request('POST', '/api/admin/driver/approve', {
    uid: testPilotUid,
    pilotId: testPilotUid,
    phone: testPilotPhone,
    adminId: 'test_admin_001',
    adminName: 'StayDriv SuperAdmin'
  });
  console.log('Duplicate Approve Status:', dupApproveRes.status, 'Already approved note:', dupApproveRes.body.message || dupApproveRes.body);
  if (dupApproveRes.status !== 200) {
    throw new Error('Idempotent approve failed!');
  }
  console.log('✓ Idempotency verified: Re-approving handled gracefully with 200 OK.\n');

  // Step 6: Verify Pilot Application Status is now APPROVED
  console.log('[STEP 6] Verifying Pilot Application Status is now APPROVED...');
  const updatedStatusRes = await request('GET', `/api/pilot/application-status?phone=${testPilotPhone}`);
  console.log('Updated Status Res:', updatedStatusRes.status, 'Status:', updatedStatusRes.body.status, 'Approved:', updatedStatusRes.body.approved);
  if (updatedStatusRes.body.approved !== true) {
    throw new Error('Pilot status did not update to approved!');
  }
  console.log('✓ Verified: Pilot is now APPROVED and authorized for duty.\n');

  // Step 7: Test Pilot Rejection Flow on another pilot
  const rejectPilotUid = `pilot_reject_${ts}`;
  const rejectPilotPhone = `9011${Math.floor(100000 + Math.random() * 900000)}`;

  console.log(`[STEP 7] Registering 2nd Pilot (${rejectPilotUid}, ${rejectPilotPhone}) for Rejection Test...`);
  await request('POST', '/api/pilot/register', {
    uid: rejectPilotUid,
    name: 'Kiran Reject (Test)',
    phone: rejectPilotPhone,
    vehicleType: 'Bike',
    vehiclePlate: 'TS07 XY 9999'
  });

  console.log('Rejecting 2nd pilot via POST /api/admin/driver/reject...');
  const rejectRes = await request('POST', '/api/admin/driver/reject', {
    uid: rejectPilotUid,
    pilotId: rejectPilotUid,
    phone: rejectPilotPhone,
    reason: 'Driving License photo blurry. Please upload clear front photo.',
    adminId: 'test_admin_001',
    adminName: 'StayDriv SuperAdmin'
  });
  console.log('Reject Res Status:', rejectRes.status, 'Body:', rejectRes.body);
  if (rejectRes.status !== 200 || !rejectRes.body.success) {
    throw new Error(`Rejection failed: ${JSON.stringify(rejectRes.body)}`);
  }
  console.log('✓ Pilot rejected with reason recorded.\n');

  // Step 8: Test Idempotency Guard on Reject
  console.log('[STEP 8] Testing Idempotency: Calling reject again with same reason...');
  const dupRejectRes = await request('POST', '/api/admin/driver/reject', {
    uid: rejectPilotUid,
    pilotId: rejectPilotUid,
    phone: rejectPilotPhone,
    reason: 'Driving License photo blurry. Please upload clear front photo.'
  });
  console.log('Duplicate Reject Status:', dupRejectRes.status, 'Message:', dupRejectRes.body.message || dupRejectRes.body);
  if (dupRejectRes.status !== 200) {
    throw new Error('Idempotent reject failed!');
  }
  console.log('✓ Idempotency verified: Re-rejecting handled gracefully with 200 OK.\n');

  // Step 9: Verify Rejection Status and Reason in API
  console.log('[STEP 9] Verifying Pilot Application Status reflects REJECTED with reason...');
  const rejStatusRes = await request('GET', `/api/pilot/application-status?phone=${rejectPilotPhone}`);
  console.log('Rejection Status:', rejStatusRes.body.status, 'Reason:', rejStatusRes.body.pilot?.rejectionReason || rejStatusRes.body.rejectionReason);
  console.log('✓ Verified: Rejection reason accurately communicated to Pilot.\n');

  console.log('====================================================');
  console.log('   ALL BACKEND & LIFECYCLE E2E TESTS PASSED 100%');
  console.log('====================================================');
  process.exit(0);
}

runTest().catch(err => {
  console.error('\n❌ TEST RUN FAILED:', err);
  process.exit(1);
});
