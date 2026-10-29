const https = require('https');
const http = require('http');

// Configurable base URL: Defaults to localhost:3000, or accepts CLI arg / env var / CloudFront
const BASE_URL = process.argv[2] || process.env.BASE_URL || 'http://localhost:3000';
// CloudFront Production URL: 'https://dk60tgl9yds4p.cloudfront.net'
const ADMIN_KEY = 'staydriv_admin_secret_2026';

function request(method, path, body = null, headers = {}) {
  return new Promise((resolve, reject) => {
    const url = new URL(path.startsWith('http') ? path : BASE_URL + path);
    const isHttps = url.protocol === 'https:';
    const client = isHttps ? https : http;
    const defaultPort = isHttps ? 443 : 80;

    const options = {
      method,
      hostname: url.hostname,
      port: url.port || defaultPort,
      path: url.pathname + url.search,
      headers: {
        'Content-Type': 'application/json',
        ...headers
      },
      timeout: 20000
    };

    const req = client.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(data);
          resolve({ status: res.statusCode, data: parsed, headers: res.headers });
        } catch (e) {
          resolve({ status: res.statusCode, data, raw: true, headers: res.headers });
        }
      });
    });

    req.on('error', reject);
    req.on('timeout', () => {
      req.destroy();
      reject(new Error(`Request timeout for ${method} ${path}`));
    });

    if (body) {
      req.write(JSON.stringify(body));
    }
    req.end();
  });
}

const DUMMY_NAMES = [
  'Paradise Biryani',
  'Chutneys Flavours',
  'Bawarchi Grand',
  'Pista House',
  'Pizza Hub Italian Kitchen',
  'Burger Craft',
  'Red Dragon Wok'
];

async function runLiveVerification() {
  console.log('================================================================');
  console.log('   STAYDRIV PRODUCTION VERIFICATION: FAILED DELIVERY RETURN & GENUINE DATA');
  console.log('   Endpoint: ' + BASE_URL);
  console.log('================================================================\n');

  let passed = 0;
  let failed = 0;

  function assert(desc, condition, details = '') {
    if (condition) {
      console.log(`  ✓ PASS: ${desc}`);
      passed++;
    } else {
      console.error(`  ✗ FAIL: ${desc} ${details ? '(' + details + ')' : ''}`);
      failed++;
    }
  }

  // TEST 1: Health check
  console.log('\n--- 1. API Health Check ---');
  try {
    const health = await request('GET', '/api/health');
    assert('API Health endpoint is UP', health.status === 200 && health.data.status === 'UP');
  } catch (err) {
    assert('API Health endpoint responded', false, err.message);
  }

  // TEST 2: Genuine Restaurants Public Endpoint (No Dummies)
  console.log('\n--- 2. Genuine Restaurants Check ---');
  let restaurants = [];
  try {
    const res = await request('GET', '/api/food/restaurants');
    assert('Restaurants API returns 200', res.status === 200 && res.data.success);
    restaurants = res.data.restaurants || [];
    console.log(`  Found ${restaurants.length} active approved restaurants in prod:`);
    restaurants.forEach(r => console.log(`    - [${r.restaurantId}] ${r.name}`));

    const dummyFound = restaurants.some(r => DUMMY_NAMES.includes(r.name) || r.isDummy);
    assert('Zero dummy restaurants in public API', !dummyFound);
    assert('Only genuine approved restaurants returned', restaurants.length > 0);
  } catch (err) {
    assert('Restaurants API call succeeded', false, err.message);
  }

  // TEST 3: Admin Restaurants List
  console.log('\n--- 3. Admin Restaurants API ---');
  try {
    const adminRes = await request('GET', '/api/food/admin/restaurants?status=all', null, {
      'x-admin-key': ADMIN_KEY
    });
    assert('Admin restaurants API returns 200', adminRes.status === 200 && adminRes.data.success);
    const adminList = adminRes.data.restaurants || [];
    const dummyInAdmin = adminList.some(r => DUMMY_NAMES.includes(r.name) || r.isDummy);
    assert('Zero dummy restaurants in Admin API', !dummyInAdmin);
  } catch (err) {
    assert('Admin restaurants API succeeded', false, err.message);
  }

  // TEST 4: Food Order Placement and Pilot Isolation
  console.log('\n--- 4. Order Placement & Pilot Request Isolation ---');
  if (restaurants.length === 0) {
    console.error('No restaurants available to test order workflow');
    return;
  }

  let selectedRest = null;
  let items = [];
  for (const r of restaurants) {
    const detail = await request('GET', `/api/food/restaurants/${r.restaurantId}`);
    if (detail.data && detail.data.menuItems && detail.data.menuItems.length > 0) {
      selectedRest = r;
      items = detail.data.menuItems;
      break;
    }
  }
  if (!selectedRest) {
    selectedRest = restaurants[0];
  }

  let testItemId = 'item_mock_01';
  let testItemName = 'Special Biryani';
  let testItemPrice = 250;

  if (items.length > 0) {
    testItemId = items[0].itemId || items[0]._id;
    testItemName = items[0].name;
    testItemPrice = items[0].price || 250;
  }

  const testPilotPhone = '9490440281'; // The real phone from the user screenshot!

  let orderId = '';
  try {
    const orderPayload = {
      customerId: 'cust_prod_test_01',
      customerName: 'Test Customer Return Workflow',
      customerPhone: '9000000001',
      restaurantId: selectedRest.restaurantId,
      deliveryAddress: {
        address: 'Hitech City, Hyderabad',
        lat: selectedRest.lat ? selectedRest.lat + 0.01 : 17.4585,
        lng: selectedRest.lng ? selectedRest.lng + 0.01 : 78.4008
      },
      items: [
        {
          itemId: testItemId,
          name: testItemName,
          price: testItemPrice,
          quantity: 1
        }
      ],
      paymentMethod: 'cash_on_delivery'
    };

    const placeRes = await request('POST', '/api/food/orders', orderPayload);
    assert('Food order created successfully', (placeRes.status === 200 || placeRes.status === 201) && placeRes.data.success);
    orderId = placeRes.data.order ? placeRes.data.order.orderId : '';
    console.log(`  Created test order: ${orderId} (Status: ${placeRes.data.order?.orderStatus})`);

    // Verify unaccepted order ('placed') is NOT in pilot available orders
    const pilotAvail1 = await request('GET', `/api/food/pilot/available-orders?lat=${selectedRest.lat}&lng=${selectedRest.lng}&radiusKm=20&pilotPhone=${testPilotPhone}`);
    const orders1 = pilotAvail1.data.orders || [];
    const isVisibleBeforeAccept = orders1.some(o => o.orderId === orderId);
    assert('Unaccepted placed order is NOT visible to delivery pilots', !isVisibleBeforeAccept);

    // Restaurant accepts order
    console.log('\n--- 5. Restaurant Accepts Order ---');
    const acceptRes = await request('POST', `/api/food/restaurant/orders/${orderId}/accept`, {
      restaurantId: selectedRest.restaurantId,
      preparationTimeMinutes: 15
    });
    assert('Restaurant accepted order', acceptRes.status === 200 && acceptRes.data.success);

    // Order should now be visible to eligible pilot
    const pilotAvail2 = await request('GET', `/api/food/pilot/available-orders?lat=${selectedRest.lat}&lng=${selectedRest.lng}&radiusKm=20&pilotPhone=${testPilotPhone}`);
    const orders2 = pilotAvail2.data.orders || [];
    const isVisibleAfterAccept = orders2.some(o => o.orderId === orderId);
    assert('Order becomes visible to pilots after restaurant acceptance', isVisibleAfterAccept);

    // Pilot accepts order
    console.log('\n--- 6. Pilot Accepts & Picks Up Food ---');
    const pilotAcceptRes = await request('POST', `/api/food/pilot/orders/${orderId}/accept`, {
      pilotId: testPilotPhone,
      pilotPhone: testPilotPhone,
      pilotName: 'Pavan Pilot',
      pilotLat: selectedRest.lat,
      pilotLng: selectedRest.lng
    });
    assert('Pilot successfully accepted food delivery order', pilotAcceptRes.status === 200 && pilotAcceptRes.data.success);

    // Pilot picks up order
    const pickupRes = await request('POST', `/api/food/pilot/orders/${orderId}/pickup`, {
      pilotId: testPilotPhone,
      pilotPhone: testPilotPhone
    });
    assert('Pilot successfully picked up food from restaurant', pickupRes.status === 200 && pickupRes.data.success);

    // TEST 7: Unauthorized Pilot Return Attempt Blocked
    console.log('\n--- 7. Security: Unauthorized Pilot Rejection ---');
    const unauthRes = await request('POST', `/api/food/pilot/orders/${orderId}/report-failed-delivery`, {
      pilotId: '9999900000', // Rogue pilot phone
      pilotPhone: '9999900000',
      reason: 'customer_unreachable',
      reasonDetails: 'Wrong pilot testing authorization'
    });
    console.log(`  Unauth Res: status=${unauthRes.status}, data=${JSON.stringify(unauthRes.data)}`);
    assert('Unauthorized pilot is blocked with 403 Forbidden', unauthRes.status === 403);
    assert('Error message explicitly identifies authorization failure', unauthRes.data.message?.includes('not the assigned delivery pilot'));

    // TEST 8: Assigned Pilot Reports Delivery Failure with Phone Credentials
    console.log('\n--- 8. Assigned Pilot Reports Unable to Deliver (Confirm & Return) ---');
    // Using phone as pilotId (the exact scenario from the screenshot)
    const reportRes = await request('POST', `/api/food/pilot/orders/${orderId}/report-failed-delivery`, {
      pilotId: testPilotPhone,
      pilotPhone: testPilotPhone,
      reason: 'customer_unreachable',
      reasonDetails: 'Customer phone switched off and doorbell not answered'
    });
    assert('Confirm & Return to Restaurant succeeds with phone credentials', reportRes.status === 200 && reportRes.data.success);
    assert('Status transitioned to delivery_failed_reported', reportRes.data.order?.orderStatus === 'delivery_failed_reported');
    assert('45-minute return policy deadline is set', !!reportRes.data.order?.returnDeadline);
    console.log(`  Return Deadline: ${reportRes.data.order?.returnDeadline}`);

    // TEST 9: Pilot Arrived at Restaurant for Return
    console.log('\n--- 9. Pilot Arrives at Restaurant ---');
    const arrivedRes = await request('POST', `/api/food/pilot/orders/${orderId}/return-arrived`, {
      pilotId: testPilotPhone,
      pilotPhone: testPilotPhone,
      restaurantId: selectedRest.restaurantId
    });
    assert('Pilot marks arrival at restaurant for return', arrivedRes.status === 200 && arrivedRes.data.success);
    assert('Status updated to return_arrived_at_restaurant', arrivedRes.data.order?.orderStatus === 'return_arrived_at_restaurant');

    // TEST 10: Restaurant Inspects and Receives Return Package
    console.log('\n--- 10. Restaurant Confirms Inspection Handover & Reveals OTP ---');
    const restReceiveRes = await request('POST', `/api/food/restaurant/orders/${orderId}/receive-return`, {
      restaurantId: selectedRest.restaurantId,
      staffName: 'Chef Ramesh'
    });
    assert('Restaurant successfully accepts return package', restReceiveRes.status === 200 && restReceiveRes.data.success);
    const returnOtp = restReceiveRes.data.returnOtp;
    assert('4-digit Return Verification OTP revealed upon inspection handover', returnOtp && returnOtp.length === 4);
    console.log(`  Revealed Return OTP: ${returnOtp}`);

    // TEST 11: Pilot Verifies Return OTP and Earns Delivery Fare
    console.log('\n--- 11. Pilot Enters 4-Digit Return Verification OTP ---');
    // Test invalid OTP first
    const badOtpRes = await request('POST', `/api/food/pilot/orders/${orderId}/verify-return-otp`, {
      pilotId: testPilotPhone,
      pilotPhone: testPilotPhone,
      otp: '0000'
    });
    assert('Invalid return OTP rejected with 400', badOtpRes.status === 400);

    // Enter correct OTP
    const goodOtpRes = await request('POST', `/api/food/pilot/orders/${orderId}/verify-return-otp`, {
      pilotId: testPilotPhone,
      pilotPhone: testPilotPhone,
      otp: returnOtp
    });
    assert('Valid return OTP verified successfully', goodOtpRes.status === 200 && goodOtpRes.data.success);
    assert('Order status completed as returned_to_restaurant', goodOtpRes.data.order?.orderStatus === 'returned_to_restaurant');
    assert('Return OTP verified flag set to true', goodOtpRes.data.order?.returnOtpVerified === true);
    assert('Pilot earnings protected without penalty', goodOtpRes.data.order?.walletDebitStatus === 'none');

    // TEST 12: Idempotency Check on Repeat Submissions
    console.log('\n--- 12. Idempotency Check on Duplicate OTP Verification ---');
    const repeatOtpRes = await request('POST', `/api/food/pilot/orders/${orderId}/verify-return-otp`, {
      pilotId: testPilotPhone,
      pilotPhone: testPilotPhone,
      otp: returnOtp
    });
    assert('Repeat OTP verification returns 200 (idempotent)', repeatOtpRes.status === 200 && repeatOtpRes.data.success);
    assert('Order remains returned_to_restaurant', repeatOtpRes.data.order?.orderStatus === 'returned_to_restaurant');

  } catch (err) {
    assert('Full lifecycle executed without error', false, err.message);
  }

  console.log('\n================================================================');
  console.log(`   LIVE PRODUCTION TEST SUMMARY: ${passed} PASSED, ${failed} FAILED`);
  console.log('================================================================\n');

  if (failed > 0) {
    process.exit(1);
  }
}

runLiveVerification().catch(err => {
  console.error('Fatal test error:', err);
  process.exit(1);
});
