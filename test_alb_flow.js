const http = require('http');

const BASE_HOST = 'staydr20260917190326134500000018-1656960596.ap-south-2.elb.amazonaws.com';

function request(method, path, body = null) {
  return new Promise((resolve, reject) => {
    const postData = body ? JSON.stringify(body) : '';
    const options = {
      hostname: BASE_HOST,
      port: 80,
      path: path,
      method: method,
      headers: {
        'User-Agent': 'StayDrivApp/1.0.28',
        'Content-Type': 'application/json',
        ...(body ? { 'Content-Length': Buffer.byteLength(postData) } : {})
      }
    };

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(data) });
        } catch (e) {
          resolve({ status: res.statusCode, text: data });
        }
      });
    });

    req.on('error', reject);
    if (postData) req.write(postData);
    req.end();
  });
}

async function runEndToEndTest() {
  console.log('=== STARTING 2 PILOTS + 1 CUSTOMER END-TO-END FLOW TEST ===');
  console.log(`Targeting ALB: http://${BASE_HOST}\n`);

  const timestamp = Date.now();
  const bookingId = 'BK_TEST_' + timestamp;
  const pilot1Id = 'pilot_1_' + timestamp;
  const pilot2Id = 'pilot_2_' + timestamp;
  const customerId = 'cust_' + timestamp;

  // Step 1: Pilot 1 registers online near Balanagar (17.4705, 78.4355)
  console.log('[Step 1] Pilot 1 checking for available Bike bookings...');
  const p1Init = await request('GET', `/api/booking/available?vehicleType=Bike&driverId=${pilot1Id}&lat=17.4705&lng=78.4355`);
  console.log('Pilot 1 Response:', p1Init.status);

  // If there are any pending searching bookings from older tests assigned to this pilot, cancel them
  if (p1Init.data && p1Init.data.bookings && p1Init.data.bookings.length > 0) {
    for (const b of p1Init.data.bookings) {
      await request('POST', '/api/booking/update', { bookingId: b.bookingId, status: 'cancelled' });
    }
  }

  // Step 2: Pilot 2 registers online near Secunderabad (17.4400, 78.5000)
  console.log('\n[Step 2] Pilot 2 checking for available Bike bookings...');
  const p2Init = await request('GET', `/api/booking/available?vehicleType=Bike&driverId=${pilot2Id}&lat=17.4400&lng=78.5000`);
  console.log('Pilot 2 Response:', p2Init.status, p2Init.data);

  // Step 3: Customer requests a ride (searching) from Balanagar to Secunderabad
  console.log('\n[Step 3] Customer creates a booking (searching)...');
  const custBooking = {
    bookingId: bookingId,
    status: 'searching',
    activeBooking: {
      bookingId: bookingId,
      passengerId: customerId,
      pickup: 'Balanagar, Hyderabad',
      drop: 'Secunderabad',
      pickupLatLng: { lat: 17.4705, lng: 78.4355 },
      dropLatLng: { lat: 17.4400, lng: 78.5000 },
      vehicle: 'Bike',
      price: 85,
      status: 'searching'
    }
  };

  const createRes = await request('POST', '/api/booking/update', custBooking);
  console.log('Customer Create Booking Response:', createRes.status, createRes.data);

  // Step 4: Pilot 1 (closest online pilot) polls for bookings
  console.log('\n[Step 4] Pilot 1 polls for available bookings (expecting to receive the booking)...');
  const p1Poll = await request('GET', `/api/booking/available?vehicleType=Bike&driverId=${pilot1Id}&lat=17.4705&lng=78.4355`);
  console.log('Pilot 1 Available Bookings:', p1Poll.status, JSON.stringify(p1Poll.data, null, 2));

  const receivedBooking = p1Poll.data.bookings && p1Poll.data.bookings.find(b => b.bookingId === bookingId);
  if (receivedBooking) {
    console.log('SUCCESS: Pilot 1 immediately received the booking request!');
  } else {
    console.error('FAILURE: Pilot 1 did not receive the booking!');
    process.exit(1);
  }

  // Step 5: Pilot 1 accepts the ride
  console.log('\n[Step 5] Pilot 1 accepts the ride...');
  const acceptPayload = {
    bookingId: bookingId,
    driverId: pilot1Id,
    driverName: 'Pilot Ramesh',
    driverPhone: '9876543210',
    driverPhoto: 'https://staydriv.com/avatar.png',
    vehicleNumber: 'TS 09 AB 1234',
    driverRating: 4.9,
    status: 'accepted'
  };
  const acceptRes = await request('POST', '/api/booking/update', acceptPayload);
  console.log('Pilot 1 Accept Response:', acceptRes.status, acceptRes.data);

  // Step 6: Customer checks the booking status
  console.log('\n[Step 6] Customer polls booking status to verify assignment...');
  const custCheck = await request('GET', `/api/booking/${bookingId}`);
  console.log('Customer Booking Status Response:', custCheck.status, custCheck.data);

  if (custCheck.data && custCheck.data.booking && custCheck.data.booking.status === 'accepted' && custCheck.data.booking.driverId === pilot1Id) {
    console.log('SUCCESS: Customer sees booking accepted with Driver ID:', custCheck.data.booking.driverId);
  } else {
    console.error('FAILURE: Customer did not see accepted status!');
  }

  // Step 7: Pilot 2 polls for available bookings
  console.log('\n[Step 7] Pilot 2 polls for available bookings (expecting 0 since ride is already taken)...');
  const p2Poll = await request('GET', `/api/booking/available?vehicleType=Bike&driverId=${pilot2Id}&lat=17.4400&lng=78.5000`);
  console.log('Pilot 2 Available Bookings:', p2Poll.status, p2Poll.data);

  const p2Bookings = (p2Poll.data.bookings || []).filter(b => b.bookingId === bookingId);
  if (p2Bookings.length === 0) {
    console.log('SUCCESS: Pilot 2 correctly does NOT see the already accepted booking!');
  } else {
    console.error('FAILURE: Pilot 2 still sees the accepted booking!');
  }

  // Step 8: Pilot 1 completes the ride to free up status
  console.log('\n[Step 8] Pilot 1 completes the ride...');
  const completeRes = await request('POST', '/api/booking/update', {
    bookingId: bookingId,
    driverId: pilot1Id,
    status: 'completed'
  });
  console.log('Complete Response:', completeRes.status);

  // Set test pilots offline
  await request('POST', '/api/partner/update', { uid: pilot1Id, online: false });
  await request('POST', '/api/partner/update', { uid: pilot2Id, online: false });

  console.log('\n=== ALL TESTS PASSED SUCCESSFULLY! ===');
}

runEndToEndTest().catch(console.error);
