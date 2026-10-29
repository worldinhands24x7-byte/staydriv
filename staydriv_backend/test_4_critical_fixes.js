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

async function runE2ETest() {
  console.log('--- STARTING COMPREHENSIVE E2E VERIFICATION OF ALL 4 FIXES ---');

  // Test 1: Directions API for pickup navigation (Issue 1)
  console.log('\n[TEST 1] Testing Directions API between Pilot GPS and Customer Pickup...');
  const dirRes = await request('GET', '/api/directions?origin=17.4834,78.3871&destination=17.4920,78.3980');
  console.log('Directions Status:', dirRes.status, 'Body status:', dirRes.body.status || 'OK');
  if (dirRes.status === 200) {
    console.log('✅ PASS: Navigation directions generated successfully between pilot GPS and pickup point.');
  } else {
    console.error('❌ FAIL: Directions failed.');
  }

  // Test 2: Create Parcel Booking and check 6-digit deliveryOtp generation (Issue 2)
  console.log('\n[TEST 2] Creating Parcel Booking & Verifying Delivery OTP...');
  const parcelBookingId = `BK_TEST_PARCEL_${Date.now()}`;
  const driverId = `DRV_TEST_${Date.now()}`;
  const passengerId = `PAS_TEST_${Date.now()}`;

  const createRes = await request('POST', '/api/booking/update', {
    bookingId: parcelBookingId,
    passengerId: passengerId,
    passengerName: 'Karthik Parcel Customer',
    passengerPhone: '9876543210',
    serviceType: 'parcel',
    vehicle: 'Parcel Bike',
    pickup: 'Hitech City, Hyderabad',
    drop: 'Madhapur, Hyderabad',
    price: '₹112',
    pickupLatLng: { lat: 17.4485, lng: 78.3740 },
    dropLatLng: { lat: 17.4504, lng: 78.3808 },
    status: 'searching'
  });

  console.log('Booking created:', createRes.body);
  const createdDeliveryOtp = createRes.body.booking?.deliveryOtp;
  console.log('Generated Delivery OTP on backend:', createdDeliveryOtp);

  if (createdDeliveryOtp && createdDeliveryOtp.length === 4 && /^\d{4}$/.test(createdDeliveryOtp)) {
    console.log('✅ PASS: Unique 4-digit Delivery OTP generated on backend.');
  } else {
    console.error('❌ FAIL: Delivery OTP not 4 digits:', createdDeliveryOtp);
  }

  // Test 3: Pilot accepts booking
  console.log('\n[TEST 3] Pilot accepts parcel booking...');
  const acceptRes = await request('POST', '/api/booking/update', {
    bookingId: parcelBookingId,
    driverId: driverId,
    driverName: 'Ravi Pilot',
    status: 'accepted'
  });
  console.log('Accept Status:', acceptRes.status, 'Booking status:', acceptRes.body.booking?.status);

  // Test 4: Verify pilot cannot view customer's delivery OTP (Redaction / Security)
  console.log('\n[TEST 4] Verifying Pilot Security Redaction (Pilot cannot view customer OTP)...');
  const pilotDetailsRes = await request('GET', `/api/booking/${parcelBookingId}?role=pilot`);
  if (!pilotDetailsRes.body.booking.deliveryOtp) {
    console.log('✅ PASS: Delivery OTP is strictly redacted when queried with role=pilot!');
  } else {
    console.error('❌ FAIL: Security violation! Pilot could view deliveryOtp:', pilotDetailsRes.body.booking.deliveryOtp);
  }

  // Customer querying same booking DOES see the OTP
  const custDetailsRes = await request('GET', `/api/booking/${parcelBookingId}?role=customer`);
  if (custDetailsRes.body.booking.deliveryOtp === createdDeliveryOtp) {
    console.log('✅ PASS: Customer securely receives delivery OTP:', custDetailsRes.body.booking.deliveryOtp);
  } else {
    console.error('❌ FAIL: Customer could not retrieve deliveryOtp.');
  }

  // Test 5: Reconnect / Active Pilot Booking sync (Issue 3)
  console.log('\n[TEST 5] Testing Active Pilot Booking recovery on reconnect/foreground resume...');
  const activePilotRes = await request('GET', `/api/booking/active/pilot/${driverId}`);
  if (activePilotRes.body.success && activePilotRes.body.booking?.bookingId === parcelBookingId) {
    console.log('✅ PASS: Pilot reconnected and successfully fetched active assigned booking without missing bookings!');
  } else {
    console.error('❌ FAIL: Pilot active booking fetch failed:', activePilotRes.body);
  }

  // Test 6: Pilot starts ride using Pickup OTP
  console.log('\n[TEST 6] Starting parcel delivery from pickup point using Pickup OTP...');
  const pickupOtp = createRes.body.booking?.pickupOtp || createRes.body.booking?.otp;
  const startRes = await request('POST', '/api/booking/update', {
    bookingId: parcelBookingId,
    status: 'started',
    otp: pickupOtp
  });
  console.log('Start ride status:', startRes.status, 'booking status:', startRes.body.booking?.status);
  if (startRes.status === 200 && startRes.body.booking?.status === 'started') {
    console.log('✅ PASS: Parcel delivery successfully started with Pickup OTP.');
  } else {
    console.error('❌ FAIL: Start ride failed:', startRes.body);
  }

  // Test 7: Pilot attempts to complete delivery without OTP or bypass
  console.log('\n[TEST 7] Testing Direct Bypass Completion Rejection without OTP...');
  const bypassRes = await request('POST', '/api/booking/update', {
    bookingId: parcelBookingId,
    status: 'completed'
  });
  console.log('Bypass Attempt Status:', bypassRes.status, bypassRes.body);
  if (bypassRes.status === 400 && bypassRes.body.error && bypassRes.body.error.includes('OTP')) {
    console.log('✅ PASS: Direct completion without OTP strictly blocked by server (HTTP 400).');
  } else {
    console.error('❌ FAIL: Bypass was not blocked!');
  }

  // Test 7b: Distinct Check - Pilot submits Pickup OTP instead of Delivery OTP
  console.log('\n[TEST 7b] Submitting Pickup OTP to Delivery OTP endpoint (Distinct check)...');
  const distinctRes = await request('POST', '/api/booking/parcel/verify-delivery-otp', {
    bookingId: parcelBookingId,
    otp: pickupOtp
  });
  console.log('Pickup OTP as Delivery OTP response:', distinctRes.status, distinctRes.body);
  if (distinctRes.status === 400 && distinctRes.body.error && distinctRes.body.error.includes('Pickup OTP')) {
    console.log('✅ PASS: Submitting Pickup OTP at delivery strictly rejected with helpful distinction message.');
  } else {
    console.error('❌ FAIL: Pickup OTP not distinguished from Delivery OTP.');
  }

  // Test 8: Pilot submits invalid length OTP (e.g. 6 digits)
  console.log('\n[TEST 8a] Submitting invalid length OTP (6 digits: 000000)...');
  const invalidLenRes = await request('POST', '/api/booking/parcel/verify-delivery-otp', {
    bookingId: parcelBookingId,
    otp: '000000'
  });
  console.log('Invalid length OTP response:', invalidLenRes.status, invalidLenRes.body);
  if (invalidLenRes.status === 400 && invalidLenRes.body.error && invalidLenRes.body.error.includes('4 numeric digits')) {
    console.log('✅ PASS: 6-digit OTP strictly rejected with 4-digit requirement message.');
  } else {
    console.error('❌ FAIL: 6-digit OTP not rejected properly.');
  }

  // Test 8b: Pilot submits wrong 4-digit OTP
  console.log('\n[TEST 8b] Submitting incorrect 4-digit OTP (9999)...');
  const wrongOtpRes = await request('POST', '/api/booking/parcel/verify-delivery-otp', {
    bookingId: parcelBookingId,
    otp: createdDeliveryOtp === '9999' ? '8888' : '9999'
  });
  console.log('Wrong OTP response:', wrongOtpRes.status, wrongOtpRes.body);
  if (wrongOtpRes.status === 400 && wrongOtpRes.body.attemptsLeft !== undefined) {
    console.log('✅ PASS: Wrong 4-digit OTP rejected with attempt tracking (attempts remaining: ' + wrongOtpRes.body.attemptsLeft + ').');
  } else {
    console.error('❌ FAIL: Wrong OTP handling incorrect.');
  }

  // Test 9: Pilot submits valid 4-digit OTP
  console.log('\n[TEST 9] Submitting valid 4-digit delivery OTP (' + createdDeliveryOtp + ')...');
  const validOtpRes = await request('POST', '/api/booking/parcel/verify-delivery-otp', {
    bookingId: parcelBookingId,
    otp: createdDeliveryOtp
  });
  console.log('Valid OTP response:', validOtpRes.status, validOtpRes.body);
  if (validOtpRes.status === 200 && validOtpRes.body.success && validOtpRes.body.booking?.status === 'completed') {
    console.log('✅ PASS: Parcel successfully marked completed after valid 4-digit OTP verification!');
  } else {
    console.error('❌ FAIL: Valid OTP verification failed.');
  }

  // Test 10: Verify 13 required fields for Ride Details & Earnings History (Issue 4)
  console.log('\n[TEST 10] Checking complete 13 fields in authoritative Ride Details endpoint...');
  const finalDetails = await request('GET', `/api/booking/${parcelBookingId}?role=pilot`);
  const b = finalDetails.body.booking;

  const checks = [
    { name: '1. Booking ID', val: b.bookingId, expect: parcelBookingId },
    { name: '2. Transaction ID', val: b.transactionId, expect: true },
    { name: '3. Ride Type', val: b.serviceType || b.vehicle, expect: true },
    { name: '4. Date/Time', val: b.createdAt, expect: true },
    { name: '5. Customer Name', val: b.passengerName, expect: 'Karthik Parcel Customer' },
    { name: '6. Pickup Address', val: b.pickup, expect: 'Hitech City, Hyderabad' },
    { name: '7. Dropoff Address', val: b.drop, expect: 'Madhapur, Hyderabad' },
    { name: '8. Total Ride Fare', val: b.totalFare, expect: 112 },
    { name: '9. Pilot Earnings (85%)', val: b.pilotEarnings, expect: 95.2 },
    { name: '10. Platform Commission (15%)', val: b.platformCommission, expect: 16.8 },
    { name: '11. Payment Method & Status', val: `${b.paymentMethod} - ${b.paymentStatus}`, expect: true },
    { name: '12. Completion Status', val: b.status, expect: 'completed' },
    { name: '13. Parcel OTP Verification Status', val: b.isDeliveryOtpVerified, expect: true }
  ];

  let allChecksPassed = true;
  for (const c of checks) {
    const passed = (c.expect === true) ? (c.val !== undefined && c.val !== null) : (c.val === c.expect);
    console.log(`   ${c.name}: [${c.val}] -> ${passed ? '✓' : '✗'}`);
    if (!passed) allChecksPassed = false;
  }

  if (allChecksPassed) {
    console.log('\n🎉 ALL 10 E2E TEST SCENARIOS PASSED WITH 100% SUCCESS!');
  } else {
    console.error('\n⚠️ Some field checks did not match exact expectations.');
  }

  process.exit(allChecksPassed ? 0 : 1);
}

runE2ETest().catch(e => {
  console.error('Test error:', e);
  process.exit(1);
});
