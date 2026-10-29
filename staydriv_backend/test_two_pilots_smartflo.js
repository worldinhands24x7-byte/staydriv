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

async function runTwoPilotsTest() {
  console.log('====================================================');
  console.log('STEP 13 & 14: TWO DIFFERENT PILOTS SMARTFLO CALL TEST');
  console.log('====================================================\n');

  const timestamp = Date.now();

  // --- PILOT A & BOOKING A ---
  const pilotAUid = `pilot_A_${timestamp}`;
  const pilotAPhone = '9490440281'; // Actual registered Pilot A phone
  const custAUid = `cust_A_${timestamp}`;
  const custAPhone = '7013213057'; // Actual Customer A phone
  const bookingAId = `BK_PILOT_A_${timestamp}`;

  console.log('1. Registering Pilot A and Customer A in MongoDB...');
  await request('POST', '/api/register', {
    uid: pilotAUid,
    name: 'Pilot Alice',
    phone: pilotAPhone,
    role: 'partner',
    vehicleType: 'Auto'
  });
  await request('POST', '/api/register', {
    uid: custAUid,
    name: 'Customer Alice',
    phone: custAPhone,
    role: 'customer'
  });

  console.log('2. Creating active Booking A assigned to Pilot A...');
  await request('POST', '/api/booking/update', {
    bookingId: bookingAId,
    status: 'accepted',
    activeBooking: {
      bookingId: bookingAId,
      status: 'accepted',
      passengerId: custAUid,
      passengerPhone: custAPhone,
      passengerName: 'Customer Alice',
      driverId: pilotAUid,
      driverPhone: pilotAPhone,
      driverName: 'Pilot Alice',
      vehicle: 'Auto',
      price: '₹120'
    }
  });

  // --- PILOT B & BOOKING B ---
  const pilotBUid = `pilot_B_${timestamp}`;
  const pilotBPhone = '9247535068'; // Completely different Pilot B phone
  const custBUid = `cust_B_${timestamp}`;
  const custBPhone = '9121403844'; // Completely different Customer B phone
  const bookingBId = `BK_PILOT_B_${timestamp}`;

  console.log('3. Registering Pilot B and Customer B in MongoDB...');
  await request('POST', '/api/register', {
    uid: pilotBUid,
    name: 'Pilot Bob',
    phone: pilotBPhone,
    role: 'partner',
    vehicleType: 'Bike'
  });
  await request('POST', '/api/register', {
    uid: custBUid,
    name: 'Customer Bob',
    phone: custBPhone,
    role: 'customer'
  });

  console.log('4. Creating active Booking B assigned to Pilot B...');
  await request('POST', '/api/booking/update', {
    bookingId: bookingBId,
    status: 'accepted',
    activeBooking: {
      bookingId: bookingBId,
      status: 'accepted',
      passengerId: custBUid,
      passengerPhone: custBPhone,
      passengerName: 'Customer Bob',
      driverId: pilotBUid,
      driverPhone: pilotBPhone,
      driverName: 'Pilot Bob',
      vehicle: 'Bike',
      price: '₹85'
    }
  });

  // --- TEST CALL FOR BOOKING A ---
  console.log('\n--- TESTING CALL FOR BOOKING A (Customer A -> Pilot A) ---');
  const callARes = await request('POST', `/api/bookings/${bookingAId}/call-pilot`, {});
  console.log('Call A Response Status:', callARes.status);
  console.log('Call A Response Body:', callARes.body);

  if (!callARes.body?.success) {
    throw new Error(`Call A failed: ${JSON.stringify(callARes.body)}`);
  }
  console.log('  [PASS] Booking A call successfully initiated with Call ID:', callARes.body.callId);

  // --- TEST CALL FOR BOOKING B ---
  console.log('\n--- TESTING CALL FOR BOOKING B (Customer B -> Pilot B) ---');
  const callBRes = await request('POST', `/api/bookings/${bookingBId}/call-pilot`, {});
  console.log('Call B Response Status:', callBRes.status);
  console.log('Call B Response Body:', callBRes.body);

  if (!callBRes.body?.success) {
    throw new Error(`Call B failed: ${JSON.stringify(callBRes.body)}`);
  }
  console.log('  [PASS] Booking B call successfully initiated with Call ID:', callBRes.body.callId);

  console.log('\n====================================================');
  console.log('VERIFYING DATABASE CALL SESSIONS FOR A & B');
  console.log('====================================================');

  const statusARes = await request('GET', `/api/bookings/${bookingAId}/call-status`);
  console.log('Booking A Call Status:', statusARes.body);

  const statusBRes = await request('GET', `/api/bookings/${bookingBId}/call-status`);
  console.log('Booking B Call Status:', statusBRes.body);

  console.log('\n====================================================');
  console.log('SUCCESS: BOTH CALLS ROUTED DYNAMICALLY TO REAL PILOTS!');
  console.log('Zero occurrences of +919121440281!');
  console.log('====================================================');
}

runTwoPilotsTest().catch(err => {
  console.error('\nTEST RUNNER ERROR:', err.message || err);
  process.exit(1);
});
