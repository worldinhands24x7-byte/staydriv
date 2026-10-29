const { io } = require('socket.io-client');

const TARGET_URL = process.argv[2] || 'https://dk60tgl9yds4p.cloudfront.net';

async function runProductionRealtimeVerification() {
  console.log(`\n=============================================================`);
  console.log(`🚀 [TEST] Verifying Real-Time Interconnection on: ${TARGET_URL}`);
  console.log(`=============================================================\n`);

  // Health check
  console.log('[Step 1] Checking /api/health...');
  const healthRes = await fetch(`${TARGET_URL}/api/health`);
  if (!healthRes.ok) throw new Error(`Health check failed with status ${healthRes.status}`);
  const healthData = await healthRes.json();
  console.log('✅ /api/health is UP:', healthData.service, healthData.environment);

  // Connect Admin Socket
  console.log('\n[Step 2] Connecting Admin WebSocket stream...');
  const adminSocket = io(TARGET_URL, {
    transports: ['websocket', 'polling'],
    timeout: 15000,
    reconnection: true
  });

  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Admin Socket connection timeout')), 12000);
    adminSocket.on('connect', () => {
      console.log('✅ Admin Socket connected. ID:', adminSocket.id);
      adminSocket.emit('admin_join_tracking', {
        adminKey: 'staydriv_admin_secret_2026',
        role: 'super_admin'
      });
    });

    adminSocket.on('admin_tracking_joined', (data) => {
      console.log('✅ admin_tracking_joined received:', data);
    });

    adminSocket.on('live_operations_snapshot', (snap) => {
      clearTimeout(timer);
      console.log('✅ live_operations_snapshot received! Pilots:', snap.pilots?.length, 'Stats:', snap.stats);
      resolve();
    });

    adminSocket.on('connect_error', (err) => {
      clearTimeout(timer);
      reject(err);
    });
  });

  const testPilotUid = 'pilot_prod_test_' + Date.now();
  const testPhone = '9999988888';
  let receivedEvents = [];

  adminSocket.on('pilot_online', (data) => {
    if (data.uid === testPilotUid) {
      console.log('🎯 [ADMIN STREAM] pilot_online event received:', data.uid, data.name);
      receivedEvents.push('pilot_online');
    }
  });

  adminSocket.on('pilot_location_update', (data) => {
    if (data.uid === testPilotUid) {
      console.log(`🎯 [ADMIN STREAM] pilot_location_update received: [${data.latitude}, ${data.longitude}], status=${data.rideStatus}`);
      receivedEvents.push('pilot_location_update');
    }
  });

  adminSocket.on('booking_accepted', (data) => {
    if (data.pilotId === testPilotUid || data.driverId === testPilotUid) {
      console.log('🎯 [ADMIN STREAM] booking_accepted received:', data.bookingId);
      receivedEvents.push('booking_accepted');
    }
  });

  adminSocket.on('ride_started', (data) => {
    if (data.pilotId === testPilotUid || data.driverId === testPilotUid) {
      console.log('🎯 [ADMIN STREAM] ride_started received:', data.bookingId);
      receivedEvents.push('ride_started');
    }
  });

  adminSocket.on('ride_completed', (data) => {
    if (data.pilotId === testPilotUid || data.driverId === testPilotUid) {
      console.log('🎯 [ADMIN STREAM] ride_completed received:', data.bookingId);
      receivedEvents.push('ride_completed');
    }
  });

  adminSocket.on('pilot_offline', (data) => {
    if (data.uid === testPilotUid) {
      console.log('🎯 [ADMIN STREAM] pilot_offline event received:', data.uid);
      receivedEvents.push('pilot_offline');
    }
  });

  // Step 3: Pilot goes online via REST
  console.log('\n[Step 3] Pilot toggling online via POST /api/partner/update...');
  const onlineRes = await fetch(`${TARGET_URL}/api/partner/update`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      uid: testPilotUid,
      phone: testPhone,
      name: 'CloudFront Test Pilot',
      online: true,
      latitude: 17.4933,
      longitude: 78.3914,
      heading: 90.0,
      rideStatus: 'idle',
      vehicleType: 'car'
    })
  });
  console.log('HTTP Status:', onlineRes.status);
  await new Promise(r => setTimeout(r, 2000));

  // Step 4: Booking Acceptance via REST
  const testBookingId = 'bk_cf_' + Date.now();
  console.log(`\n[Step 4] Pilot accepting booking ${testBookingId} via POST /api/booking/update...`);
  const acceptRes = await fetch(`${TARGET_URL}/api/booking/update`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      bookingId: testBookingId,
      status: 'accepted',
      driverId: testPilotUid,
      pilotId: testPilotUid,
      pilotName: 'CloudFront Test Pilot',
      pilotPhone: testPhone,
      vehicleNumber: 'TS09TEST01',
      vehicleModel: 'Hyundai Aura',
      pickupLocation: { latitude: 17.4950, longitude: 78.3930, address: 'KPHB Colony' },
      dropLocation: { latitude: 17.4400, longitude: 78.3489, address: 'HITEC City' },
      fare: 250
    })
  });
  console.log('HTTP Status:', acceptRes.status);
  await new Promise(r => setTimeout(r, 2000));

  // Step 5: Pilot GPS update on route
  console.log('\n[Step 5] Pilot sending GPS updates while arriving at pickup...');
  const gpsRes = await fetch(`${TARGET_URL}/api/partner/update`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      uid: testPilotUid,
      phone: testPhone,
      online: true,
      latitude: 17.4942,
      longitude: 78.3921,
      heading: 110.0,
      rideStatus: 'arriving',
      currentBookingId: testBookingId
    })
  });
  console.log('HTTP Status:', gpsRes.status);
  await new Promise(r => setTimeout(r, 2000));

  // Step 6: Start Ride
  console.log('\n[Step 6] Pilot starting ride via POST /api/booking/update...');
  const startRes = await fetch(`${TARGET_URL}/api/booking/update`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      bookingId: testBookingId,
      status: 'started',
      driverId: testPilotUid,
      pilotId: testPilotUid
    })
  });
  console.log('HTTP Status:', startRes.status);
  await new Promise(r => setTimeout(r, 2000));

  // Step 7: Complete Ride
  console.log('\n[Step 7] Pilot completing ride via POST /api/booking/update...');
  const completeRes = await fetch(`${TARGET_URL}/api/booking/update`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      bookingId: testBookingId,
      status: 'completed',
      driverId: testPilotUid,
      pilotId: testPilotUid
    })
  });
  console.log('HTTP Status:', completeRes.status);
  await new Promise(r => setTimeout(r, 2000));

  // Step 8: Pilot toggles offline
  console.log('\n[Step 8] Pilot toggling offline via POST /api/partner/update...');
  const offlineRes = await fetch(`${TARGET_URL}/api/partner/update`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      uid: testPilotUid,
      phone: testPhone,
      online: false
    })
  });
  console.log('HTTP Status:', offlineRes.status);
  await new Promise(r => setTimeout(r, 2000));

  console.log('\n=============================================================');
  console.log('📊 Verification Summary:');
  console.log('Received WebSocket Events by Admin Panel:');
  console.log(receivedEvents);
  console.log('=============================================================\n');

  adminSocket.disconnect();

  const expected = ['pilot_online', 'pilot_location_update', 'booking_accepted', 'ride_started', 'ride_completed', 'pilot_offline'];
  const allMatched = expected.every(e => receivedEvents.includes(e));

  if (allMatched) {
    console.log('🎉 ALL 6 REAL-TIME LIFECYCLE EVENTS WERE RECEIVED SUCCESSFULLY BY ADMIN PANEL!');
    process.exit(0);
  } else {
    console.error('⚠️ Some events were missing:', expected.filter(e => !receivedEvents.includes(e)));
    process.exit(1);
  }
}

runProductionRealtimeVerification().catch(err => {
  console.error('❌ Test failed with error:', err);
  process.exit(1);
});
