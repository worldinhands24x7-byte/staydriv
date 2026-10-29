const io = require('socket.io-client');
const { spawn } = require('child_process');
const assert = require('assert');
const path = require('path');

const PORT = 5055;
const BASE_URL = `http://localhost:${PORT}`;

async function runTests() {
  console.log('=== [TEST] Starting Live Rider Location Flow Tests ===');
  console.log(`Starting test server on port ${PORT}...`);

  const serverProc = spawn('node', ['server.js'], {
    cwd: path.resolve(__dirname),
    env: { ...process.env, PORT: PORT.toString(), NODE_ENV: 'test', IS_TEST_MODE: 'true' },
    stdio: 'pipe'
  });

  serverProc.stdout.on('data', () => {});
  serverProc.stderr.on('data', () => {});

  // Wait for server to start
  let ready = false;
  for (let i = 0; i < 30; i++) {
    await new Promise((r) => setTimeout(r, 600));
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

  try {
    // Test 1: GET /api/admin/live-riders endpoint
    console.log('\n[Test 1] Testing GET /api/admin/live-riders endpoint...');
    const res = await fetch(`${BASE_URL}/api/admin/live-riders`, {
      headers: {
        'x-admin-key': 'staydriv_admin_secret_2026'
      }
    });
    assert.strictEqual(res.status, 200, `Expected 200 but got ${res.status}`);
    const data = await res.json();
    assert.strictEqual(data.success, true, 'Expected data.success to be true');
    assert.ok(Array.isArray(data.riders), 'Expected data.riders to be an array');
    assert.ok(typeof data.liveRidersCount === 'number', 'Expected liveRidersCount to be a number');
    assert.ok(data.stats, 'Expected stats object');
    assert.ok(data.riders.length >= 3, `Expected at least 3 riders, got ${data.riders.length}`);
    console.log(`✅ [Test 1 PASSED] Fetched ${data.riders.length} riders. Live transmitting count: ${data.liveRidersCount}`);

    // Test 2: Admin Socket.IO join and live snapshot
    console.log('\n[Test 2] Testing Admin Socket.IO join_tracking & live_riders_snapshot...');
    const adminSocket = io(BASE_URL, { transports: ['websocket', 'polling'] });

    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Admin socket connection timeout')), 8000);

      adminSocket.on('connect', () => {
        adminSocket.emit('admin_join_tracking', {
          adminKey: 'staydriv_admin_secret_2026',
          role: 'super_admin'
        });
      });

      adminSocket.on('live_riders_snapshot', (snapshot) => {
        clearTimeout(timeout);
        assert.strictEqual(snapshot.success, true);
        assert.ok(Array.isArray(snapshot.riders));
        assert.ok(typeof snapshot.liveRidersCount === 'number');
        console.log(`✅ [Test 2 PASSED] Received live_riders_snapshot with ${snapshot.riders.length} riders. Stats:`, snapshot.stats);
        resolve();
      });

      adminSocket.on('admin_auth_error', (err) => {
        clearTimeout(timeout);
        reject(new Error(`Admin auth error: ${JSON.stringify(err)}`));
      });
    });

    // Test 3: Pilot emits driver_update -> Admin receives pilot_location_update
    console.log('\n[Test 3] Testing Pilot driver_update real-time broadcast to Admin...');
    const pilotSocket = io(BASE_URL, { transports: ['websocket', 'polling'] });

    const testPilotUid = 'pilot_test_' + Date.now();
    const testLat = 17.4968;
    const testLng = 78.3606;

    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('pilot_location_update timeout')), 8000);

      const handler = (update) => {
        if (update.uid === testPilotUid) {
          adminSocket.off('pilot_location_update', handler);
          clearTimeout(timeout);
          assert.strictEqual(update.online, true, 'Pilot should be marked online');
          assert.strictEqual(update.status, 'online', 'Status should be online');
          assert.strictEqual(update.vehicleType, 'Bike');
          assert.strictEqual(update.lat, testLat);
          assert.strictEqual(update.lng, testLng);
          assert.strictEqual(update.heading, 45);
          assert.strictEqual(update.speed, 28);
          console.log(`✅ [Test 3 PASSED] Admin received real-time pilot_location_update for ${update.name} (${update.lat}, ${update.lng})`);
          resolve();
        }
      };

      adminSocket.on('pilot_location_update', handler);

      pilotSocket.on('connect', () => {
        pilotSocket.emit('driver_update', {
          uid: testPilotUid,
          online: true,
          lat: testLat,
          lng: testLng,
          vehicle: 'Bike',
          name: 'John Pilot',
          phone: '9490440281',
          vehiclePlate: 'TS 09 EA 1234',
          heading: 45,
          speed: 28
        });
      });
    });

    // Test 4: Pilot emits ride_location_update -> Admin receives on_ride status
    console.log('\n[Test 4] Testing ride_location_update with turn-by-turn navigation stream...');
    const newLat = 17.5020;
    const newLng = 78.3650;
    const testRideId = 'BK_TEST_' + Date.now();

    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('ride_location_update broadcast timeout')), 8000);

      const handler = (update) => {
        if (update.uid === testPilotUid && update.status === 'on_ride') {
          adminSocket.off('pilot_location_update', handler);
          clearTimeout(timeout);
          assert.strictEqual(update.lat, newLat);
          assert.strictEqual(update.lng, newLng);
          assert.strictEqual(update.heading, 90);
          assert.strictEqual(update.speed, 42);
          assert.strictEqual(update.rideId, testRideId);
          console.log(`✅ [Test 4 PASSED] Admin received on_ride location stream: Lat=${update.lat}, Lng=${update.lng}, Heading=${update.heading}°, Speed=${update.speed} km/h`);
          resolve();
        }
      };

      adminSocket.on('pilot_location_update', handler);

      pilotSocket.emit('ride_location_update', {
        rideId: testRideId,
        pilotId: testPilotUid,
        vehicleType: 'Bike',
        latitude: newLat,
        longitude: newLng,
        heading: 90,
        speed: 42,
        accuracy: 4.5,
        remainingDistance: '1.8 km',
        eta: '4 mins',
        navigationStatus: 'started',
        timestamp: Date.now()
      });
    });

    // Test 5: Pilot disconnect -> Admin receives offline status update
    console.log('\n[Test 5] Testing Pilot disconnect event handling...');
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Disconnect pilot_location_update timeout')), 8000);

      const handler = (update) => {
        if (update.uid === testPilotUid && update.status === 'offline') {
          adminSocket.off('pilot_location_update', handler);
          clearTimeout(timeout);
          assert.strictEqual(update.online, false);
          console.log(`✅ [Test 5 PASSED] Pilot disconnected and marked offline in Admin Console.`);
          resolve();
        }
      };

      adminSocket.on('pilot_location_update', handler);

      pilotSocket.disconnect();
    });

    // Test 6: Simulation endpoint POST /api/admin/simulate-pilot-location
    console.log('\n[Test 6] Testing simulation endpoint POST /api/admin/simulate-pilot-location...');
    const simRes = await fetch(`${BASE_URL}/api/admin/simulate-pilot-location`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        uid: 'sim_pilot_1',
        name: 'Simulated Pilot',
        vehicleType: 'Auto',
        vehiclePlate: 'TS 08 AP 9999',
        lat: 17.4485,
        lng: 78.3750,
        heading: 180,
        speed: 35,
        status: 'online'
      })
    });
    assert.strictEqual(simRes.status, 200);
    const simData = await simRes.json();
    assert.strictEqual(simData.success, true);
    assert.strictEqual(simData.rider.name, 'Simulated Pilot');
    console.log(`✅ [Test 6 PASSED] Pilot location simulated successfully via admin API.`);

    adminSocket.disconnect();
    console.log('\n🎉 ALL 6 LIVE RIDER TRACKING INTEGRATION TESTS PASSED SUCCESSFULLY! 🎉\n');
  } finally {
    serverProc.kill();
  }
}

runTests().catch(err => {
  console.error('\n❌ Integration Test Run Terminated with Error:', err);
  process.exit(1);
});
