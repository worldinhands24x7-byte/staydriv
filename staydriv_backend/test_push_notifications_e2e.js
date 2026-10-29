const http = require('http');
const https = require('https');

const BASE_URL = process.env.TEST_URL || 'https://dk60tgl9yds4p.cloudfront.net';

function makeRequest(method, path, body = null, headers = {}) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, BASE_URL);
    const isHttps = url.protocol === 'https:';
    const client = isHttps ? https : http;

    const reqHeaders = {
      'Content-Type': 'application/json',
      ...headers
    };

    const options = {
      method,
      hostname: url.hostname,
      port: url.port || (isHttps ? 443 : 80),
      path: url.pathname + url.search,
      headers: reqHeaders,
      timeout: 15000
    };

    const req = client.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        let json = null;
        try {
          json = JSON.parse(data);
        } catch (_) {
          json = data;
        }
        resolve({
          statusCode: res.statusCode,
          headers: res.headers,
          body: json
        });
      });
    });

    req.on('error', reject);
    req.on('timeout', () => {
      req.destroy();
      reject(new Error(`Request timeout for ${method} ${path}`));
    });

    if (body) {
      req.write(typeof body === 'string' ? body : JSON.stringify(body));
    }
    req.end();
  });
}

async function runTests() {
  console.log('================================================================');
  console.log('STAYDRIV GLOBAL PUSH NOTIFICATIONS & LOCATION E2E TEST SUITE');
  console.log('Target Base URL:', BASE_URL);
  console.log('================================================================\n');

  let passed = 0;
  let failed = 0;

  function assert(condition, description, details = '') {
    if (condition) {
      console.log(`  [PASS] ${description}`);
      passed++;
    } else {
      console.error(`  [FAIL] ${description} ${details ? '- ' + details : ''}`);
      failed++;
    }
  }

  try {
    // TEST 1: Register Customer Push Token
    console.log('--- Test 1: Register Customer Push Token ---');
    const custToken = 'fcm_test_token_customer_' + Date.now();
    const regCustRes = await makeRequest('POST', '/api/notifications/register-token', {
      token: custToken,
      uid: 'test_cust_uid_101',
      phone: '9010922111',
      role: 'customer',
      platform: 'android',
      appType: 'staydriv_combined'
    });
    assert(regCustRes.statusCode === 200, 'Register customer push token HTTP 200', `Status: ${regCustRes.statusCode}`);
    assert(regCustRes.body?.success === true, 'Response body has success: true');
    assert(regCustRes.body?.device?.token === custToken, 'Registered device token matches input');
    assert(regCustRes.body?.device?.role === 'customer', 'Registered device role is customer');

    // TEST 2: Register Partner / Pilot Push Token
    console.log('\n--- Test 2: Register Pilot / Partner Push Token ---');
    const pilotToken = 'fcm_test_token_pilot_' + Date.now();
    const regPilotRes = await makeRequest('POST', '/api/notifications/register-token', {
      token: pilotToken,
      uid: 'test_pilot_uid_202',
      phone: '7013213057',
      role: 'partner',
      platform: 'android',
      appType: 'staydriv_combined'
    });
    assert(regPilotRes.statusCode === 200, 'Register pilot push token HTTP 200', `Status: ${regPilotRes.statusCode}`);
    assert(regPilotRes.body?.success === true, 'Response body has success: true');
    assert(regPilotRes.body?.device?.role === 'partner', 'Registered device role is partner');

    // TEST 3: Get Audience Stats
    console.log('\n--- Test 3: Get Audience & Device Stats ---');
    const statsRes = await makeRequest('GET', '/api/notifications/stats');
    assert(statsRes.statusCode === 200, 'Audience stats HTTP 200');
    assert(statsRes.body?.success === true, 'Audience stats success true');
    assert(typeof statsRes.body?.stats?.totalEligible === 'number', 'totalEligible is numeric');
    assert(statsRes.body?.stats?.totalEligible >= 2, `totalEligible >= 2 (Found: ${statsRes.body?.stats?.totalEligible})`);

    // TEST 4: Broadcast Input Validation
    console.log('\n--- Test 4: Broadcast Input Validation (Empty Title / Body) ---');
    const valRes = await makeRequest('POST', '/api/notifications/broadcast', {
      title: '',
      body: ''
    });
    assert(valRes.statusCode === 400, 'Empty title/body rejected with HTTP 400', `Status: ${valRes.statusCode}`);
    assert(valRes.body?.success === false, 'Validation failure response success: false');

    // TEST 5: Broadcast to Everyone (All App Users)
    console.log('\n--- Test 5: Broadcast to Everyone (All App Users) ---');
    const broadcastAllRes = await makeRequest('POST', '/api/notifications/broadcast', {
      title: 'StayDriv Grand Festive Offer',
      body: 'Get 25% cashback on all rides and food orders this Dussehra!',
      targetGroup: 'all',
      type: 'promo',
      adminEmail: 'admin@staydriv.com'
    });
    assert(broadcastAllRes.statusCode === 200, 'Broadcast all HTTP 200', `Status: ${broadcastAllRes.statusCode}`);
    assert(broadcastAllRes.body?.success === true, 'Broadcast all success true');
    assert(broadcastAllRes.body?.campaignId?.startsWith('CAMP-'), `Valid campaignId generated: ${broadcastAllRes.body?.campaignId}`);
    assert(broadcastAllRes.body?.totalEligible >= 2, `totalEligible >= 2 (Got ${broadcastAllRes.body?.totalEligible})`);
    assert(broadcastAllRes.body?.status === 'sent', `Broadcast status is "sent" (Got ${broadcastAllRes.body?.status})`);

    // TEST 6: Broadcast to Customers Only
    console.log('\n--- Test 6: Broadcast to Customers Only ---');
    const broadcastCustRes = await makeRequest('POST', '/api/notifications/broadcast', {
      title: 'Free Food Delivery Tonight',
      body: 'Order from top rated restaurants with zero delivery fee above ₹199.',
      targetGroup: 'customers',
      type: 'push',
      adminEmail: 'superadmin@staydriv.com'
    });
    assert(broadcastCustRes.statusCode === 200, 'Broadcast customers HTTP 200');
    assert(broadcastCustRes.body?.success === true, 'Broadcast customers success true');
    assert(broadcastCustRes.body?.totalEligible >= 1, `Targeted customers totalEligible >= 1 (Got ${broadcastCustRes.body?.totalEligible})`);

    // TEST 7: Broadcast to Pilots Only (Emergency Alert)
    console.log('\n--- Test 7: Broadcast to Pilots Only (Emergency Alert) ---');
    const broadcastPilotRes = await makeRequest('POST', '/api/notifications/broadcast', {
      title: 'High Demand Surge Alert: Hitec City',
      body: 'Heavy booking inflow in Madhapur/Hitec City. Earn 1.5x on all trips now.',
      targetGroup: 'partners',
      type: 'emergency',
      adminEmail: 'operations@staydriv.com'
    });
    assert(broadcastPilotRes.statusCode === 200, 'Broadcast pilots HTTP 200');
    assert(broadcastPilotRes.body?.success === true, 'Broadcast pilots success true');
    assert(broadcastPilotRes.body?.totalEligible >= 1, `Targeted pilots totalEligible >= 1 (Got ${broadcastPilotRes.body?.totalEligible})`);

    // TEST 8: Fetch Sent Campaign History Logs
    console.log('\n--- Test 8: Fetch Sent Campaign History Logs from MongoDB ---');
    const historyRes = await makeRequest('GET', '/api/notifications/campaigns');
    assert(historyRes.statusCode === 200, 'Fetch campaigns HTTP 200');
    assert(historyRes.body?.success === true, 'Campaigns success true');
    assert(Array.isArray(historyRes.body?.campaigns), 'Campaigns returned as an array');
    assert(historyRes.body?.campaigns?.length >= 3, `Recorded at least 3 campaigns (Found: ${historyRes.body?.campaigns?.length})`);

    const latestCampaign = historyRes.body?.campaigns?.[0];
    assert(latestCampaign?.title?.length > 0, `Latest campaign has title: "${latestCampaign?.title}"`);
    assert(latestCampaign?.adminEmail?.length > 0, `Latest campaign records admin: ${latestCampaign?.adminEmail}`);
    assert(typeof latestCampaign?.totalEligible === 'number', `Latest campaign records totalEligible: ${latestCampaign?.totalEligible}`);
    assert(typeof latestCampaign?.successCount === 'number', `Latest campaign records successCount: ${latestCampaign?.successCount}`);

    // TEST 9: Reverse Geocoding for Food Order Now Location Detection
    console.log('\n--- Test 9: Reverse Geocoding API for Food Order Now ---');
    const revGeoRes = await makeRequest('GET', '/api/places/reverse-geocode?lat=17.4483&lng=78.3800');
    assert(revGeoRes.statusCode === 200, 'Reverse geocode HTTP 200');
    assert(revGeoRes.body?.status === 'OK' || revGeoRes.body?.success === true, 'Reverse geocode returned OK/success');
    assert(typeof revGeoRes.body?.formatted_address === 'string' && revGeoRes.body.formatted_address.length > 5,
      `Address resolved: "${revGeoRes.body?.formatted_address}"`);

  } catch (err) {
    console.error('Fatal error during test execution:', err);
    failed++;
  }

  console.log('\n================================================================');
  console.log(`TEST SUMMARY: ${passed} PASSED, ${failed} FAILED`);
  console.log('================================================================');

  if (failed > 0) {
    process.exit(1);
  }
}

runTests();
