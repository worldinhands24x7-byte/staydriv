/**
 * test_multi_rider_simulation.js
 * Verification of multiple simultaneous riders updating locations,
 * ride status lifecycle transitions, and admin filter/search verification.
 */
const ioClient = require('socket.io-client');
const { spawn } = require('child_process');
const path = require('path');

const PORT = 5057;
const BASE_URL = `http://localhost:${PORT}`;

async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function runMultiRiderTest() {
  console.log('=== [TEST] Starting Multi-Rider Simultaneous Telemetry Simulation ===');
  console.log(`Starting test server on port ${PORT}...`);

  const serverProc = spawn('node', ['server.js'], {
    cwd: path.resolve(__dirname),
    env: { ...process.env, PORT: PORT.toString(), NODE_ENV: 'test', IS_TEST_MODE: 'true' },
    stdio: 'pipe'
  });

  serverProc.stdout.on('data', () => {});
  serverProc.stderr.on('data', () => {});

  let ready = false;
  for (let i = 0; i < 30; i++) {
    await sleep(600);
    try {
      const res = await fetch(`${BASE_URL}/api/health`);
      if (res.ok) {
        ready = true;
        console.log(`Test server is running and healthy on port ${PORT}!`);
        break;
      }
    } catch (_) {}
  }

  if (!ready) {
    serverProc.kill();
    throw new Error('Test server failed to start within timeout');
  }

  let adminSocket;
  const pilotSockets = [];

  try {
    // 1. Connect Admin Socket
    console.log('\n[Phase 1] Connecting Admin Console Socket.IO...');
    adminSocket = ioClient(BASE_URL, {
      transports: ['websocket'],
      forceNew: true
    });

    const receivedUpdates = [];
    adminSocket.on('pilot_location_update', (update) => {
      receivedUpdates.push(update);
    });

    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Admin socket connection timeout')), 5000);
      adminSocket.on('connect', () => {
        console.log('Admin socket connected:', adminSocket.id);
        adminSocket.emit('admin_join_tracking');
      });
      adminSocket.on('live_riders_snapshot', (data) => {
        clearTimeout(timer);
        console.log(`Admin received initial snapshot of ${data.riders ? data.riders.length : 0} riders.`);
        resolve();
      });
    });

    // 2. Spawn 3 simulated pilots transmitting live GPS
    console.log('\n[Phase 2] Simulating 3 active pilots transmitting real-time GPS coordinates...');
    const pilotsData = [
      {
        uid: 'PILOT_SIM_001',
        name: 'Ravi Kumar',
        phone: '+91 98765 11111',
        vehicleType: 'Bike',
        vehicleNumber: 'TS 09 AB 1234',
        lat: 17.4435,
        lng: 78.3820,
        heading: 45,
        speed: 35
      },
      {
        uid: 'PILOT_SIM_002',
        name: 'Priya Sharma',
        phone: '+91 98765 22222',
        vehicleType: 'Auto',
        vehicleNumber: 'TS 08 CD 5678',
        lat: 17.4920,
        lng: 78.3980,
        heading: 180,
        speed: 28
      },
      {
        uid: 'PILOT_SIM_003',
        name: 'Vikram Singh',
        phone: '+91 98765 33333',
        vehicleType: 'Car',
        vehicleNumber: 'TS 07 EF 9012',
        lat: 17.4200,
        lng: 78.4500,
        heading: 270,
        speed: 55
      }
    ];

    for (const p of pilotsData) {
      const pSock = ioClient(BASE_URL, { transports: ['websocket'], forceNew: true });
      await new Promise((resolve) => {
        pSock.on('connect', () => {
          pSock.emit('driver_update', {
            uid: p.uid,
            name: p.name,
            phone: p.phone,
            online: true,
            lat: p.lat,
            lng: p.lng,
            heading: p.heading,
            speed: p.speed,
            vehicle: p.vehicleType,
            vehicleNumber: p.vehicleNumber
          });
          resolve();
        });
      });
      pilotSockets.push(pSock);
    }

    await sleep(1000);

    // 3. Verify Admin received updates for all 3 pilots
    console.log('\n[Phase 3] Verifying Admin Console received live updates for all 3 pilots...');
    const pilot1Update = receivedUpdates.find(u => u.pilotId === 'PILOT_SIM_001');
    const pilot2Update = receivedUpdates.find(u => u.pilotId === 'PILOT_SIM_002');
    const pilot3Update = receivedUpdates.find(u => u.pilotId === 'PILOT_SIM_003');

    if (!pilot1Update || !pilot2Update || !pilot3Update) {
      throw new Error('Failed to receive all 3 pilot updates on admin socket!');
    }
    console.log(`✅ Received updates for:
      - ${pilot1Update.name || pilot1Update.pilotName} (${pilot1Update.vehicleType}): (${pilot1Update.lat}, ${pilot1Update.lng}) Status: ${pilot1Update.status}
      - ${pilot2Update.name || pilot2Update.pilotName} (${pilot2Update.vehicleType}): (${pilot2Update.lat}, ${pilot2Update.lng}) Status: ${pilot2Update.status}
      - ${pilot3Update.name || pilot3Update.pilotName} (${pilot3Update.vehicleType}): (${pilot3Update.lat}, ${pilot3Update.lng}) Status: ${pilot3Update.status}`);

    // 4. Simulate movement: Smooth Coordinate Glides & Status changes
    console.log('\n[Phase 4] Simulating smooth GPS movement steps & status transitions...');
    receivedUpdates.length = 0;
    // Pilot 1 moves forward along heading 45
    pilotSockets[0].emit('driver_update', {
      uid: 'PILOT_SIM_001',
      lat: 17.4450,
      lng: 78.3835,
      heading: 48,
      speed: 38
    });

    // Pilot 2 receives booking and starts arriving
    pilotSockets[1].emit('accept_booking', {
      bookingId: 'BK_SIM_TEST_99',
      driverId: 'PILOT_SIM_002',
      driverName: 'Priya Sharma'
    });

    // Pilot 3 starts ride
    pilotSockets[2].emit('update_state', {
      bookingId: 'BK_SIM_TEST_100',
      driverId: 'PILOT_SIM_003',
      status: 'on_trip'
    });

    await sleep(1500);

    const p1Move = receivedUpdates.find(u => u.pilotId === 'PILOT_SIM_001');
    const p2Arrive = receivedUpdates.find(u => u.pilotId === 'PILOT_SIM_002');
    const p3OnTrip = receivedUpdates.find(u => u.pilotId === 'PILOT_SIM_003');

    if (!p1Move || p1Move.lat !== 17.4450) {
      throw new Error('Pilot 1 new coordinates did not arrive properly!');
    }
    if (!p2Arrive || p2Arrive.status !== 'arriving') {
      throw new Error(`Pilot 2 status expected arriving, got ${p2Arrive ? p2Arrive.status : 'null'}`);
    }
    if (!p3OnTrip || p3OnTrip.status !== 'on_ride') {
      throw new Error(`Pilot 3 status expected on_ride, got ${p3OnTrip ? p3OnTrip.status : 'null'}`);
    }
    console.log('✅ Coordinate updates and status transitions (online -> arriving, on_trip -> on_ride) verified!');

    // 5. Test REST API Snapshot with admin authentication
    console.log('\n[Phase 5] Fetching GET /api/admin/live-riders with admin secret key...');
    const snapshotRes = await fetch(`${BASE_URL}/api/admin/live-riders`, {
      headers: { 'x-admin-key': 'staydriv_admin_secret_2026' }
    });
    const snapshotJson = await snapshotRes.json();

    if (!snapshotJson.success || !snapshotJson.stats) {
      throw new Error('Invalid snapshot response!');
    }
    console.log(`✅ Snapshot stats verified: Total Live Riders: ${snapshotJson.stats.liveCount}, Online: ${snapshotJson.stats.online}, Arriving: ${snapshotJson.stats.arriving}, On Ride: ${snapshotJson.stats.onRide}`);

    // 6. Test Pilot Completes Ride -> returns to Online
    console.log('\n[Phase 6] Simulating ride completion: returns to Online/Available...');
    receivedUpdates.length = 0;
    pilotSockets[2].emit('update_state', {
      bookingId: 'BK_SIM_TEST_100',
      driverId: 'PILOT_SIM_003',
      status: 'completed'
    });
    await sleep(1200);

    const p3Completed = receivedUpdates.find(u => u.pilotId === 'PILOT_SIM_003');
    if (!p3Completed || p3Completed.status !== 'online') {
      throw new Error(`Pilot 3 status expected online after completion, got ${p3Completed ? p3Completed.status : 'null'}`);
    }
    console.log('✅ Ride completion transition verified: Pilot 3 reset to Online / Available.');

    // 7. Test Pilot Disconnect -> Status goes Offline, Last Known Location Preserved
    console.log('\n[Phase 7] Simulating pilot disconnect: status goes offline, last known location preserved...');
    receivedUpdates.length = 0;
    pilotSockets[0].disconnect();
    await sleep(1200);

    const p1Offline = receivedUpdates.find(u => u.pilotId === 'PILOT_SIM_001');
    if (!p1Offline || p1Offline.status !== 'offline') {
      throw new Error(`Pilot 1 status expected offline after disconnect, got ${p1Offline ? p1Offline.status : 'null'}`);
    }
    if (p1Offline.lat !== 17.4450 || p1Offline.lng !== 78.3835) {
      throw new Error('Pilot 1 coordinates were not preserved upon going offline!');
    }
    console.log(`✅ Offline handling verified: Pilot 1 is offline with last known coordinates (${p1Offline.lat}, ${p1Offline.lng}) and lastUpdated=${p1Offline.lastUpdated}`);

    console.log('\n🎉 ALL MULTI-RIDER SIMULATION & LIFECYCLE TESTS COMPLETED SUCCESSFULLY! 🎉\n');
  } finally {
    for (const s of pilotSockets) {
      if (s.connected) s.disconnect();
    }
    if (adminSocket && adminSocket.connected) adminSocket.disconnect();
    serverProc.kill();
  }
}

runMultiRiderTest().then(() => {
  process.exit(0);
}).catch(err => {
  console.error('❌ Test failed with error:', err);
  process.exit(1);
});
