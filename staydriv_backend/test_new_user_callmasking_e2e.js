const http = require('http');

function request(method, path, body = null) {
  return new Promise((resolve, reject) => {
    const postData = body ? JSON.stringify(body) : null;
    const req = http.request({
      hostname: '127.0.0.1',
      port: 3000,
      path,
      method,
      headers: {
        'Content-Type': 'application/json',
        'x-admin-key': 'staydriv_admin_secret_2026',
        ...(postData ? { 'Content-Length': Buffer.byteLength(postData) } : {})
      },
      timeout: 10000
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, body: JSON.parse(data) });
        } catch (_) {
          resolve({ status: res.statusCode, body: data });
        }
      });
    });

    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('Request timed out')); });
    if (postData) req.write(postData);
    req.end();
  });
}

async function verifyNewUserCallMasking() {
  console.log('===============================================================');
  console.log(' DEEP VERIFICATION: NEW CUSTOMER & NEW PILOT CALL MASKING');
  console.log('       (Auto-Discovery, PBX Masking & Admin Panel Sync)        ');
  console.log('===============================================================\n');

  const ts = Date.now();
  const rawCustPhone = '+91 98765 43210';
  const rawPilotPhone = '09876543211';
  const newCustUid = `cust_new_${ts}`;
  const newPilotUid = `pilot_new_${ts}`;
  const bookingId = `BK_NEW_JOIN_${ts}`;

  // STEP 1: Register Brand New Customer (with +91 and spaces)
  console.log(`[STEP 1] Registering New Customer: Ananya Sharma (${rawCustPhone})...`);
  const custReg = await request('POST', '/api/register', {
    uid: newCustUid,
    name: 'Ananya Sharma',
    phone: rawCustPhone,
    role: 'customer'
  });
  console.log('Customer Registration Status:', custReg.status);
  if (custReg.status !== 200) throw new Error('Customer registration failed');
  console.log('✓ New Customer registered in MongoDB.\n');

  // STEP 2: Register Brand New Pilot (with leading 0)
  console.log(`[STEP 2] Registering New Pilot: Vikram Singh (${rawPilotPhone})...`);
  const pilotReg = await request('POST', '/api/pilot/register', {
    uid: newPilotUid,
    name: 'Vikram Singh',
    phone: rawPilotPhone,
    role: 'partner',
    vehicleType: 'Scooty',
    vehiclePlate: 'TS09 AB 1234',
    applicationId: `PLT-${ts}`
  });
  console.log('Pilot Registration Status:', pilotReg.status);
  if (pilotReg.status !== 200) throw new Error('Pilot registration failed');
  console.log('✓ New Pilot registered in MongoDB with PENDING status.\n');

  // STEP 3: Admin Approves New Pilot
  console.log(`[STEP 3] Admin approves New Pilot (${newPilotUid})...`);
  const approveRes = await request('POST', '/api/admin/driver/approve', {
    uid: newPilotUid,
    phone: rawPilotPhone,
    adminName: 'Super Admin'
  });
  console.log('Approve Status:', approveRes.status, '| Success:', approveRes.body.success);
  if (approveRes.status !== 200) throw new Error('Pilot approval failed');
  console.log('✓ New Pilot is APPROVED.\n');

  // STEP 4: Create Active Ride Booking between New Customer and New Pilot
  console.log(`[STEP 4] Dispatching active ride booking (${bookingId})...`);
  const bookingRes = await request('POST', '/api/booking/update', {
    bookingId,
    passengerId: newCustUid,
    passengerName: 'Ananya Sharma',
    passengerPhone: rawCustPhone,
    driverId: newPilotUid,
    driverName: 'Vikram Singh',
    driverPhone: rawPilotPhone,
    status: 'accepted',
    pickup: 'Kondapur, Hyderabad',
    drop: 'Gachibowli, Hyderabad',
    vehicle: 'Scooty'
  });
  console.log('Booking Status:', bookingRes.status);
  console.log('✓ Active ride booked.\n');

  // STEP 5: New Customer Calls New Pilot (Masked via Tata Smartflo)
  console.log('[STEP 5] New Customer taps "Call Pilot"...');
  const custCallRes = await request('POST', `/api/bookings/${bookingId}/call-pilot`, {
    callerUserId: newCustUid
  });
  console.log('Call Pilot Status:', custCallRes.status);
  console.log('Call Pilot Response:', custCallRes.body);
  if (custCallRes.status !== 200) throw new Error('Call pilot failed');

  // Verify privacy
  const custCallStr = JSON.stringify(custCallRes.body);
  if (custCallStr.includes('9876543211')) {
    throw new Error('SECURITY VIOLATION: Raw pilot phone was returned to customer!');
  }
  console.log(`✓ Call Masking Active: Customer connects to virtual DID ${custCallRes.body.virtualNumber}.\n`);

  // STEP 6: New Pilot Calls New Customer (Masked via Tata Smartflo)
  console.log('[STEP 6] New Pilot taps "Call Customer"...');
  const pilotCallRes = await request('POST', `/api/bookings/${bookingId}/call-customer`, {
    callerUserId: newPilotUid
  });
  console.log('Call Customer Status:', pilotCallRes.status);
  console.log('Call Customer Response:', pilotCallRes.body);
  if (pilotCallRes.status !== 200) throw new Error('Call customer failed');

  // Verify privacy
  const pilotCallStr = JSON.stringify(pilotCallRes.body);
  if (pilotCallStr.includes('9876543210')) {
    throw new Error('SECURITY VIOLATION: Raw customer phone was returned to pilot!');
  }
  console.log(`✓ Call Masking Active: Pilot connects to virtual DID ${pilotCallRes.body.virtualNumber}.\n`);

  // STEP 7: Admin Panel Direct Support Call to New Pilot
  console.log('[STEP 7] Admin initiates direct masked support call to New Pilot...');
  const adminCallRes = await request('POST', '/api/admin/call/initiate', {
    targetPhone: rawPilotPhone,
    targetName: 'Vikram Singh',
    targetRole: 'pilot',
    bookingId
  });
  console.log('Admin Call Status:', adminCallRes.status);
  console.log('Admin Call Response:', adminCallRes.body);
  if (adminCallRes.status !== 200) throw new Error('Admin initiate call failed');
  console.log('✓ Admin support call bridged via Smartflo.\n');

  // STEP 8: Verify Admin Panel Call Logs
  console.log('[STEP 8] Inspecting Admin Panel Call Logs (GET /api/admin/calls)...');
  const adminLogsRes = await request('GET', '/api/admin/calls?limit=10');
  console.log('Admin Logs Status:', adminLogsRes.status);
  const calls = adminLogsRes.body.calls || [];

  const custToPilotCall = calls.find(c => c.bookingId === bookingId && c.callerRole === 'customer');
  const pilotToCustCall = calls.find(c => c.bookingId === bookingId && c.callerRole === 'pilot');
  const adminToPilotCall = calls.find(c => c.bookingId === bookingId && c.callerRole === 'admin');

  console.log('\n--- ADMIN PANEL VERIFICATION ---');
  if (custToPilotCall) {
    console.log(`✓ Customer->Pilot Call in Admin: Customer="${custToPilotCall.customerName}" (${custToPilotCall.customerPhoneMasked}), Pilot="${custToPilotCall.pilotName}" (${custToPilotCall.pilotPhoneMasked}), Status=${custToPilotCall.status}`);
  } else {
    throw new Error('Customer->Pilot call not found in Admin Logs');
  }

  if (pilotToCustCall) {
    console.log(`✓ Pilot->Customer Call in Admin: Customer="${pilotToCustCall.customerName}" (${pilotToCustCall.customerPhoneMasked}), Pilot="${pilotToCustCall.pilotName}" (${pilotToCustCall.pilotPhoneMasked}), Status=${pilotToCustCall.status}`);
  } else {
    throw new Error('Pilot->Customer call not found in Admin Logs');
  }

  if (adminToPilotCall) {
    console.log(`✓ Admin->Pilot Call in Admin: Customer="${adminToPilotCall.customerName}", Pilot="${adminToPilotCall.pilotName}" (${adminToPilotCall.pilotPhoneMasked}), Role=${adminToPilotCall.callerRole}`);
  } else {
    throw new Error('Admin direct support call not found in Admin Logs');
  }

  console.log('\n===============================================================');
  console.log(' ALL NEW USER CALL MASKING & ADMIN INTEGRATION TESTS PASSED 100%');
  console.log('===============================================================');
  process.exit(0);
}

verifyNewUserCallMasking().catch(err => {
  console.error('\n❌ TEST FAILED:', err);
  process.exit(1);
});
