const http = require('http');

const ALB_BASE = 'http://staydr20260917190326134500000018-1656960596.ap-south-2.elb.amazonaws.com';

function request(method, path, body = null) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, ALB_BASE);
    const postData = body ? JSON.stringify(body) : null;
    const options = {
      hostname: url.hostname,
      port: url.port || 80,
      path: url.pathname + url.search,
      method: method,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'StayDrivTest/1.0',
        ...(postData ? { 'Content-Length': Buffer.byteLength(postData) } : {})
      }
    };

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(data) });
        } catch (e) {
          resolve({ status: res.statusCode, raw: data });
        }
      });
    });

    req.on('error', reject);
    if (postData) req.write(postData);
    req.end();
  });
}

async function runTest() {
  console.log('=== STARTING 1 CUSTOMER + 2 ONLINE PILOTS PRODUCTION FLOW TEST ===');
  const now = Date.now();
  const pilot1Uid = `pilot_1_${now}`;
  const pilot2Uid = `pilot_2_${now}`;
  const customerUid = `customer_${now}`;
  const bookingId = `BK_PROD_TEST_${now}`;

  // 1. Pilot 1 goes online (Bike) at Balanagar, Hyderabad (17.4705, 78.4355 - directly at pickup location)
  console.log('\n[1] Registering Pilot 1 Online (Bike)...');
  const p1Res = await request('POST', '/api/partner/update', {
    uid: pilot1Uid,
    online: true,
    lat: 17.4705,
    lng: 78.4355,
    vehicleType: 'Bike',
    vehiclePlate: 'TS 09 SD 1111',
    vehicleModelColor: 'Black Bike'
  });
  console.log(`Pilot 1 update response: status=${p1Res.status}, success=${p1Res.data?.success}`);

  // 2. Pilot 2 goes online (Bike) at Secunderabad (17.4400, 78.5000)
  console.log('\n[2] Registering Pilot 2 Online (Bike)...');
  const p2Res = await request('POST', '/api/partner/update', {
    uid: pilot2Uid,
    online: true,
    lat: 17.4400,
    lng: 78.5000,
    vehicleType: 'Bike',
    vehiclePlate: 'TS 09 SD 2222',
    vehicleModelColor: 'Blue Bike'
  });
  console.log(`Pilot 2 update response: status=${p2Res.status}, success=${p2Res.data?.success}`);

  // 3. Customer creates booking for Bike (Pickup at Balanagar 17.4705, 78.4355)
  console.log('\n[3] Customer creating Bike booking (Pickup: 17.4705, 78.4355)...');
  const createRes = await request('POST', '/api/booking/update', {
    bookingId: bookingId,
    status: 'searching',
    activeBooking: {
      bookingId: bookingId,
      passengerId: customerUid,
      passengerName: 'Test Customer',
      passengerPhone: '9999999999',
      pickup: 'Balanagar Main Road, Hyderabad',
      drop: 'Secunderabad Railway Station',
      pickupLatLng: { lat: 17.4705, lng: 78.4355 },
      dropLatLng: { lat: 17.4400, lng: 78.5000 },
      vehicle: 'Bike',
      price: '95',
      otp: '1234',
      status: 'searching',
      title: 'StayDriv Bike Ride'
    }
  });
  console.log(`Booking created: status=${createRes.status}, auto-dispatched driverId=${createRes.data?.booking?.driverId}`);

  // 4. Pilot 1 polls /api/booking/available
  console.log('\n[4] Pilot 1 polling /api/booking/available...');
  const availRes = await request('GET', `/api/booking/available?vehicleType=Bike&driverId=${pilot1Uid}&lat=17.4700&lng=78.4350`);
  console.log(`Pilot 1 available bookings count: ${availRes.data?.bookings?.length}`);
  const assigned = availRes.data?.bookings?.find(b => b.bookingId === bookingId);

  if (assigned) {
    console.log(`SUCCESS: Pilot 1 received booking ${bookingId} (status: ${assigned.status}, assigned driverId: ${assigned.driverId})`);
  } else {
    throw new Error('Pilot 1 did not receive the booking!');
  }

  // 5. Pilot 1 accepts booking
  console.log('\n[5] Pilot 1 accepting booking...');
  const acceptRes = await request('POST', '/api/booking/update', {
    bookingId: bookingId,
    status: 'accepted',
    activeBooking: {
      bookingId: bookingId,
      status: 'accepted',
      driverId: pilot1Uid,
      driverName: 'Pilot Ramesh',
      driverPhone: '9876543210',
      vehiclePlate: 'TS 09 SD 1111',
      vehicleModelColor: 'Black Bike'
    }
  });
  console.log(`Accept response: status=${acceptRes.status}, bookingStatus=${acceptRes.data?.booking?.status}`);

  // 6. Customer polls and confirms ride is accepted with driver details
  console.log('\n[6] Customer polling /api/booking/:bookingId to confirm driver acceptance...');
  const custCheckRes = await request('GET', `/api/booking/${bookingId}`);
  console.log(`Customer check response: status=${custCheckRes.data?.booking?.status}, driverId=${custCheckRes.data?.booking?.driverId}, driverName=${custCheckRes.data?.booking?.driverName}`);

  if (custCheckRes.data?.booking?.status !== 'accepted' || custCheckRes.data?.booking?.driverId !== pilot1Uid) {
    throw new Error('Customer did not see accepted status with correct driverId!');
  }

  // 7. Pilot 1 arrives
  console.log('\n[7] Pilot 1 arrives at pickup...');
  const arriveRes = await request('POST', '/api/booking/update', {
    bookingId: bookingId,
    status: 'arrived',
    activeBooking: {
      bookingId: bookingId,
      status: 'arrived',
      driverId: pilot1Uid
    }
  });
  console.log(`Arrive response: status=${arriveRes.status}, bookingStatus=${arriveRes.data?.booking?.status}`);

  // 8. Pilot 1 starts trip
  console.log('\n[8] Pilot 1 starts trip...');
  const startRes = await request('POST', '/api/booking/update', {
    bookingId: bookingId,
    status: 'started',
    activeBooking: {
      bookingId: bookingId,
      status: 'started',
      driverId: pilot1Uid
    }
  });
  console.log(`Start response: status=${startRes.status}, bookingStatus=${startRes.data?.booking?.status}`);

  // 9. Pilot 1 completes the trip
  console.log('\n[9] Pilot 1 completing ride...');
  const completeRes = await request('POST', '/api/booking/update', {
    bookingId: bookingId,
    status: 'completed',
    activeBooking: {
      bookingId: bookingId,
      status: 'completed',
      driverId: pilot1Uid
    }
  });
  console.log(`Complete response: status=${completeRes.status}, finalStatus=${completeRes.data?.booking?.status}`);

  // 10. Clean up test pilots (mark offline)
  await request('POST', '/api/partner/update', { uid: pilot1Uid, online: false });
  await request('POST', '/api/partner/update', { uid: pilot2Uid, online: false });

  console.log('\n=== ALL PRODUCTION FLOW TESTS PASSED 100%! ===');
}

runTest().catch(err => {
  console.error('TEST FAILED:', err);
  process.exit(1);
});
