const https = require('https');
const assert = require('assert');

const BASE_URL = 'https://dk60tgl9yds4p.cloudfront.net';

function request(method, path, body = null) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, BASE_URL);
    const options = {
      hostname: url.hostname,
      port: 443,
      path: url.pathname + url.search,
      method: method,
      headers: {
        'Content-Type': 'application/json',
      }
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          resolve({ status: res.statusCode, data: json });
        } catch (e) {
          resolve({ status: res.statusCode, raw: data });
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

async function runTest() {
  console.log('================================================================');
  console.log('TEST: FOOD DELIVERY LIFECYCLE & PILOT ACTIVITY EARNINGS HISTORY');
  console.log('================================================================\n');

  const testPilotPhone = '9490440281';
  const testPilotUid = `mock_uid_${testPilotPhone}_pilot`;

  // 1. Fetch available restaurants and menu
  console.log('Step 1: Fetching restaurant & menu...');
  const restRes = await request('GET', '/api/food/restaurants');
  assert.strictEqual(restRes.status, 200, 'Restaurant fetch status 200');
  const restaurant = restRes.data.restaurants[0];
  console.log(`✓ Using Restaurant: ${restaurant.name} (${restaurant.restaurantId})`);

  const singleRestRes = await request('GET', `/api/food/restaurants/${restaurant.restaurantId}`);
  const menuItems = singleRestRes.data.menuItems || [];
  const testItem = menuItems.find(i => i.isAvailable !== false) || menuItems[0];
  console.log(`Using menu item: "${testItem.name}" (ID: ${testItem.itemId}, Price: ₹${testItem.price})`);

  // 2. Place food order
  console.log('Step 2: Placing Food Order...');
  const orderPayload = {
    customerId: 'cust_test_earnings_999',
    customerName: 'StayDriv Customer',
    customerPhone: '9849012345',
    deliveryAddress: 'Flat 402, Sunshine Heights, Madhapur, Hyderabad',
    deliveryLatLng: { lat: 17.4485, lng: 78.3750 },
    restaurantId: restaurant.restaurantId,
    items: [
      {
        itemId: testItem.itemId,
        name: testItem.name,
        price: testItem.price || 150,
        quantity: 1,
        isVeg: testItem.isVeg !== false
      }
    ],
    paymentMethod: 'cash_on_delivery'
  };

  const placeRes = await request('POST', '/api/food/orders', orderPayload);
  assert.strictEqual(placeRes.status, 201, 'Order created status 201');
  const orderId = placeRes.data.order.orderId;
  const deliveryOtp = placeRes.data.order.deliveryOtp || placeRes.data.order.customerOtp;
  console.log(`✓ Food Order Placed: ${orderId}, Customer Delivery OTP: ${deliveryOtp}`);

  // 3. Restaurant Partner Accepts Order
  console.log('Step 3: Restaurant Accepts Order...');
  const acceptRes = await request('POST', `/api/food/partner/orders/${orderId}/status`, {
    status: 'accepted',
    prepTime: '20 mins',
    note: 'Order accepted by kitchen'
  });
  if (acceptRes.status !== 200) {
    console.error('Restaurant Accept Error Data:', acceptRes.data);
  }
  assert.strictEqual(acceptRes.status, 200, 'Restaurant accept 200');
  console.log(`✓ Order Status: ${acceptRes.data.order.orderStatus}`);

  // 4. Pilot Accepts Food Delivery Assignment
  console.log('Step 4: Pilot Accepts Delivery...');
  const pilotAcceptRes = await request('POST', `/api/food/pilot/orders/${orderId}/accept`, {
    pilotId: testPilotUid,
    pilotName: 'Suresh Pilot',
    pilotPhone: testPilotPhone,
    vehicleType: 'Bike',
    vehiclePlate: 'TS09AB1234'
  });
  assert.strictEqual(pilotAcceptRes.status, 200, 'Pilot accept 200');
  console.log(`✓ Pilot Assigned: ${pilotAcceptRes.data.order.deliveryPartnerId}`);

  // 5. Food Prepared & Ready for Pickup
  console.log('Step 5: Food Ready for Pickup...');
  const readyRes = await request('POST', `/api/food/partner/orders/${orderId}/status`, {
    status: 'ready_for_pickup',
    note: 'Packed hot and fresh'
  });
  assert.strictEqual(readyRes.status, 200, 'Food ready 200');
  console.log(`✓ Order Status: ${readyRes.data.order.orderStatus}`);

  // 6. Pilot Picks Up Food Handover
  console.log('Step 6: Pilot Picks Up Food...');
  const pickupRes = await request('POST', `/api/food/pilot/orders/${orderId}/pickup`, {
    pilotId: testPilotUid
  });
  assert.strictEqual(pickupRes.status, 200, 'Pickup status 200');
  console.log(`✓ Order Status: ${pickupRes.data.order.orderStatus}`);

  // 7. Complete Delivery with Customer OTP Verification
  console.log('Step 7: Verifying Customer Delivery OTP...');
  // Test invalid OTP first
  const invalidOtpRes = await request('POST', `/api/food/pilot/orders/${orderId}/deliver`, {
    otp: '0000',
    pilotId: testPilotUid
  });
  assert.strictEqual(invalidOtpRes.status, 400, 'Invalid OTP rejected with 400');
  console.log(`✓ Invalid OTP rejected: ${invalidOtpRes.data.message}`);

  // Verify valid OTP
  const deliverRes = await request('POST', `/api/food/pilot/orders/${orderId}/deliver`, {
    otp: deliveryOtp,
    pilotId: testPilotUid
  });
  assert.strictEqual(deliverRes.status, 200, 'Valid delivery 200');
  console.log(`✓ Delivery Verified: Status = ${deliverRes.data.order.orderStatus}, Earnings Credited`);

  // 8. Verify Pilot Activity / Rides History Endpoint
  console.log('Step 8: Checking Pilot Activity / Rides History (GET /api/user/:uid/rides)...');
  const ridesRes = await request('GET', `/api/user/${testPilotUid}/rides?role=Pilot&phone=${testPilotPhone}&allStatuses=true`);
  assert.strictEqual(ridesRes.status, 200, 'Rides history fetch 200');
  const rides = ridesRes.data.rides || ridesRes.data.bookings || [];
  console.log(`Total Bookings & Deliveries returned: ${rides.length}`);
  
  const foundOrder = rides.find(r => r.bookingId === orderId || r.orderId === orderId);
  assert(foundOrder, `Completed food order ${orderId} must be present in Pilot Rides history!`);
  console.log(`✓ Found Food Delivery in Activity:`, {
    bookingId: foundOrder.bookingId,
    serviceType: foundOrder.serviceType,
    vehicle: foundOrder.vehicle,
    pickup: foundOrder.pickup,
    drop: foundOrder.drop,
    price: foundOrder.price,
    pilotEarnings: foundOrder.pilotEarnings,
    status: foundOrder.status
  });
  assert.strictEqual(foundOrder.serviceType, 'food', 'Service type is food');
  assert.strictEqual(foundOrder.status, 'completed', 'Status is completed');
  assert.strictEqual(foundOrder.pilotEarnings, foundOrder.deliveryFee, 'Pilot earnings equals delivery fee');

  // 9. Verify Booking Details Endpoint (GET /api/booking/:bookingId)
  console.log('Step 9: Checking Booking Details Endpoint (GET /api/booking/:bookingId)...');
  const bookingDetailRes = await request('GET', `/api/booking/${orderId}?role=pilot`);
  assert.strictEqual(bookingDetailRes.status, 200, 'Booking detail fetch 200');
  assert.strictEqual(bookingDetailRes.data.booking.bookingId, orderId, 'Correct order ID returned');
  assert.strictEqual(bookingDetailRes.data.booking.serviceType, 'food', 'Correct service type');
  console.log(`✓ Booking Details Endpoint returned full transparent food delivery breakdown!`);

  // 10. Verify Pilot Wallet / Earnings Endpoint (GET /api/pilot/wallet/:uid)
  console.log('Step 10: Checking Pilot Wallet (GET /api/pilot/wallet/:uid)...');
  const walletRes = await request('GET', `/api/pilot/wallet/${testPilotUid}`);
  assert.strictEqual(walletRes.status, 200, 'Wallet fetch 200');
  console.log(`✓ Pilot Wallet Pending Settlement: ₹${walletRes.data.pendingSettlement}`);
  assert(walletRes.data.pendingSettlement >= 25, 'Pending settlement has been credited with food delivery earnings!');

  console.log('\n================================================================');
  console.log('🎉 ALL 10 TESTS PASSED! FOOD DELIVERY IS 100% INTEGRATED IN PILOT ACTIVITY & EARNINGS!');
  console.log('================================================================');
}

runTest().catch(err => {
  console.error('Test Failed:', err);
  process.exit(1);
});
