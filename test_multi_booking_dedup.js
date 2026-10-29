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
        'User-Agent': 'StayDrivDedupTest/1.0',
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

async function runMultiBookingTest() {
  console.log('=== MULTI-BOOKING DEDUPLICATION VERIFICATION ===');
  const now = Date.now();
  const pilot1Uid = `pilot_1_${now}`;
  const pilot2Uid = `pilot_2_${now}`;
  const customerUid = `cust_${now}`;

  // 1. Online pilots
  await request('POST', '/api/partner/update', {
    uid: pilot1Uid,
    online: true,
    lat: 17.4705,
    lng: 78.4355,
    vehicleType: 'Bike'
  });

  await request('POST', '/api/partner/update', {
    uid: pilot2Uid,
    online: true,
    lat: 17.4400,
    lng: 78.5000,
    vehicleType: 'Bike'
  });

  console.log('Pilots registered online.');

  for (let i = 1; i <= 3; i++) {
    const bId = `BK_MULTI_${i}_${now}`;
    console.log(`\n--- Test Booking #${i}: ${bId} ---`);

    // Customer creates booking
    const cRes = await request('POST', '/api/booking/update', {
      bookingId: bId,
      status: 'searching',
      activeBooking: {
        bookingId: bId,
        passengerId: customerUid,
        pickup: `Pickup Location ${i}`,
        drop: `Drop Location ${i}`,
        pickupLatLng: { lat: 17.4705, lng: 78.4355 },
        dropLatLng: { lat: 17.4400, lng: 78.5000 },
        vehicle: 'Bike',
        price: '75',
        otp: '1234',
        status: 'searching'
      }
    });

    console.log(`Booking ${i} created. Auto-assigned: ${cRes.data?.booking?.driverId}`);

    // Pilot 1 poll 1
    const p1Poll1 = await request('GET', `/api/booking/available?vehicleType=Bike&driverId=${pilot1Uid}&lat=17.4705&lng=78.4355`);
    const count1 = (p1Poll1.data?.bookings || []).filter(b => b.bookingId === bId).length;
    console.log(`Pilot 1 first poll match count: ${count1} (Expected: 1)`);
    if (count1 !== 1) throw new Error(`Pilot 1 should receive booking exactly once!`);

    // Pilot 1 poll 2 (simulating 3-5 seconds later)
    const p1Poll2 = await request('GET', `/api/booking/available?vehicleType=Bike&driverId=${pilot1Uid}&lat=17.4705&lng=78.4355`);
    const count2 = (p1Poll2.data?.bookings || []).filter(b => b.bookingId === bId).length;
    console.log(`Pilot 1 second poll match count: ${count2} (Expected: 1, still single assignment)`);
    if (count2 !== 1) throw new Error(`Pilot 1 received duplicate booking count!`);

    // Pilot 2 poll (should NOT see the booking because it is assigned to Pilot 1)
    const p2Poll = await request('GET', `/api/booking/available?vehicleType=Bike&driverId=${pilot2Uid}&lat=17.4400&lng=78.5000`);
    const p2Count = (p2Poll.data?.bookings || []).filter(b => b.bookingId === bId).length;
    console.log(`Pilot 2 poll match count: ${p2Count} (Expected: 0)`);
    if (p2Count !== 0) throw new Error(`Pilot 2 should NOT receive Pilot 1's booking!`);

    // Complete booking to clear
    await request('POST', '/api/booking/update', {
      bookingId: bId,
      status: 'completed',
      activeBooking: { bookingId: bId, status: 'completed', driverId: pilot1Uid }
    });
    console.log(`Booking ${i} completed successfully.`);
  }

  // Cleanup pilots
  await request('POST', '/api/partner/update', { uid: pilot1Uid, online: false });
  await request('POST', '/api/partner/update', { uid: pilot2Uid, online: false });

  console.log('\n=== MULTI-BOOKING DEDUPLICATION VERIFIED 100% SUCCESSFUL! ===');
}

runMultiBookingTest().catch(err => {
  console.error('TEST FAILED:', err);
  process.exit(1);
});
