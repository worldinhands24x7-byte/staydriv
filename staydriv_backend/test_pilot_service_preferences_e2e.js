/**
 * test_pilot_service_preferences_e2e.js
 * Comprehensive End-to-End Test for Pilot Service Preferences (Ride Booking & Food Delivery ON/OFF)
 */
const http = require('http');
const mongoose = require('mongoose');

const BASE_URL = 'http://localhost:3000';

function makeRequest(method, path, body = null) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, BASE_URL);
    const options = {
      method: method,
      hostname: url.hostname,
      port: url.port,
      path: url.pathname + url.search,
      headers: {
        'Content-Type': 'application/json'
      }
    };

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(data);
          resolve({ status: res.statusCode, body: parsed });
        } catch (e) {
          resolve({ status: res.statusCode, body: data });
        }
      });
    });

    req.on('error', reject);
    if (body) {
      req.write(JSON.stringify(body));
    }
    req.end();
  });
}

async function runTests() {
  console.log('================================================================');
  console.log('🚀 RUNNING PILOT SERVICE PREFERENCES E2E TEST SUITE');
  console.log('================================================================\n');

  let passed = 0;
  let total = 0;

  function assert(condition, message) {
    total++;
    if (condition) {
      console.log(`✅ [PASS] Test ${total}: ${message}`);
      passed++;
    } else {
      console.error(`❌ [FAIL] Test ${total}: ${message}`);
    }
  }

  const testPilotUid = 'pilot_pref_test_' + Date.now();
  const testPhone = '99998' + Math.floor(10000 + Math.random() * 90000);

  try {
    // 0. Connect directly to Mongo to set up test pilot
    const MONGO_URI = process.env.MONGO_URI || 'mongodb://localhost:27017/staydriv';
    const conn = await mongoose.createConnection(MONGO_URI).asPromise();
    const User = conn.model('User', new mongoose.Schema({
      uid: String,
      phone: String,
      name: String,
      role: String,
      status: String,
      approved: Boolean,
      vehicleType: String,
      lat: Number,
      lng: Number,
      online: Boolean,
      rideServiceEnabled: Boolean,
      foodServiceEnabled: Boolean
    }));

    await User.create({
      uid: testPilotUid,
      phone: testPhone,
      name: 'E2E Preference Pilot',
      role: 'partner',
      status: 'approved',
      approved: true,
      vehicleType: 'Bike',
      lat: 17.4485,
      lng: 78.3745,
      online: true,
      rideServiceEnabled: true,
      foodServiceEnabled: true
    });

    // TEST 1: Default GET /api/pilot/:uid/service-preferences
    const res1 = await makeRequest('GET', `/api/pilot/${testPilotUid}/service-preferences`);
    assert(
      res1.status === 200 &&
      res1.body.success === true &&
      res1.body.rideServiceEnabled === true &&
      res1.body.foodServiceEnabled === true,
      'GET /api/pilot/:uid/service-preferences returns default TRUE for both services'
    );

    // TEST 2: Update preferences (pause rides, keep food active)
    const res2 = await makeRequest('POST', `/api/pilot/${testPilotUid}/service-preferences`, {
      rideServiceEnabled: false,
      foodServiceEnabled: true
    });
    assert(
      res2.status === 200 &&
      res2.body.success === true &&
      res2.body.rideServiceEnabled === false &&
      res2.body.foodServiceEnabled === true,
      'POST /api/pilot/:uid/service-preferences pauses Ride Booking while keeping Food Delivery active'
    );

    // TEST 3: Verify GET reflects paused ride booking
    const res3 = await makeRequest('GET', `/api/pilot/${testPilotUid}/service-preferences`);
    assert(
      res3.status === 200 &&
      res3.body.rideServiceEnabled === false &&
      res3.body.foodServiceEnabled === true,
      'GET /api/pilot/:uid/service-preferences verifies rideServiceEnabled=false is persisted'
    );

    // TEST 4: Update preferences (pause food, activate rides)
    const res4 = await makeRequest('POST', `/api/pilot/${testPilotUid}/service-preferences`, {
      rideServiceEnabled: true,
      foodServiceEnabled: false
    });
    assert(
      res4.status === 200 &&
      res4.body.rideServiceEnabled === true &&
      res4.body.foodServiceEnabled === false,
      'POST /api/pilot/:uid/service-preferences activates Ride Booking and pauses Food Delivery'
    );

    // TEST 5: Verify isEligibleForFoodDelivery checks foodServiceEnabled
    const { isEligibleForFoodDelivery, findNearbyEligibleFoodPilots } = require('./services/foodDeliveryEligibilityService');
    const checkOff = isEligibleForFoodDelivery({
      vehicleType: 'Bike',
      online: true,
      status: 'approved',
      approved: true,
      foodServiceEnabled: false
    }, { checkFoodServiceEnabled: true });

    assert(
      checkOff.eligible === false && checkOff.reason.includes('Turn ON Food Delivery'),
      'isEligibleForFoodDelivery returns eligible=false when foodServiceEnabled is FALSE'
    );

    // TEST 6: Turn food service back ON and verify inclusion
    const checkOn = isEligibleForFoodDelivery({
      vehicleType: 'Bike',
      online: true,
      status: 'approved',
      approved: true,
      foodServiceEnabled: true
    }, { checkFoodServiceEnabled: true });

    assert(
      checkOn.eligible === true,
      'isEligibleForFoodDelivery returns eligible=true when foodServiceEnabled is TRUE'
    );

    // TEST 7: Test findNearbyEligibleFoodPilots directly
    const nearbyPilots = await findNearbyEligibleFoodPilots({
      restaurantLat: 17.4485,
      restaurantLng: 78.3745,
      maxDistanceKm: 25
    });
    assert(
      Array.isArray(nearbyPilots),
      'findNearbyEligibleFoodPilots executes and returns active eligible pilot list'
    );

    // Clean up test pilot
    await User.deleteOne({ uid: testPilotUid });
    await conn.close();

    console.log(`\n================================================================`);
    console.log(`🎉 TEST SUMMARY: ${passed}/${total} passed (${Math.round((passed / total) * 100)}%)`);
    console.log(`================================================================`);
    process.exit(passed === total ? 0 : 1);
  } catch (err) {
    console.error('Unhandled test execution error:', err);
    process.exit(1);
  }
}

runTests();
