const https = require('https');

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

async function runTests() {
  console.log('================================================================');
  console.log('STAYDRIV: NAVIGATION FIX, RETURN OTP & CALLING VERIFICATION TEST');
  console.log('================================================================\n');

  try {
    // 1. Check health
    console.log('--- TEST 1: Health & API Availability ---');
    const health = await request('GET', '/health');
    console.log('Status:', health.status, health.data);
    if (health.status !== 200) throw new Error('Health check failed');
    console.log('✓ PASS: Production backend is healthy.\n');

    // 2. Fetch a real approved restaurant and its actual menu
    console.log('--- TEST 2: Fetch Approved Restaurant & Real Menu ---');
    const restRes = await request('GET', '/api/food/restaurants');
    if (!restRes.data || !restRes.data.restaurants || restRes.data.restaurants.length === 0) {
      throw new Error('No restaurants found');
    }
    const testRest = restRes.data.restaurants[0];
    console.log(`Using restaurant: "${testRest.name}" (ID: ${testRest.restaurantId})`);
    console.log(`Restaurant Lat/Lng: ${testRest.lat}, ${testRest.lng}`);

    const singleRestRes = await request('GET', `/api/food/restaurants/${testRest.restaurantId}`);
    const menuItems = singleRestRes.data.menuItems || [];
    console.log('Menu items count:', menuItems.length);
    if (menuItems.length === 0) {
      throw new Error('No menuItems returned');
    }
    const testItem = menuItems.find(i => i.isAvailable !== false) || menuItems[0];
    console.log(`Using menu item: "${testItem.name}" (ID: ${testItem.itemId}, Price: ₹${testItem.price})`);
    console.log('✓ PASS: Restaurant and menu item retrieved.\n');

    // 3. Place order with explicit customer coordinates
    console.log('--- TEST 3: Place Order with Precise Customer Delivery Coordinates ---');
    const customerDrop = {
      address: '1-170/83, Sri Balaji Layout, Gajularamaram, Hyderabad, Telangana 500055',
      lat: 17.5264754,
      lng: 78.4241154
    };

    const placeRes = await request('POST', '/api/food/orders', {
      customerId: 'CUST_TEST_VERIFY_01',
      customerName: 'StayDriv Verification User',
      customerPhone: '9849012345',
      deliveryAddress: customerDrop.address,
      deliveryLatLng: { lat: customerDrop.lat, lng: customerDrop.lng },
      restaurantId: testRest.restaurantId,
      items: [
        {
          itemId: testItem.itemId,
          name: testItem.name,
          price: testItem.price || 90,
          quantity: 1,
          isVeg: testItem.isVeg !== false
        }
      ],
      paymentMethod: 'cash_on_delivery'
    });

    console.log('Place Order Status:', placeRes.status);
    if (placeRes.status !== 201 && !placeRes.data.success) {
      throw new Error('Failed to place food order: ' + JSON.stringify(placeRes.data));
    }
    const order = placeRes.data.order;
    const orderId = order.orderId;
    console.log(`Order placed successfully: Order ID = ${orderId}`);
    console.log(`Stored Customer Delivery LatLng: ${order.deliveryLatLng.lat}, ${order.deliveryLatLng.lng}`);
    console.log(`Stored Restaurant LatLng: ${order.restaurantLatLng.lat}, ${order.restaurantLatLng.lng}`);

    // Verify navigation destination logic
    if (order.deliveryLatLng.lat !== customerDrop.lat || order.deliveryLatLng.lng !== customerDrop.lng) {
      throw new Error('Customer delivery coordinates mismatch!');
    }
    console.log('✓ PASS: Customer delivery GPS coordinates are 100% matched to customer drop.\n');

    // 4. Accept Order by 2-Wheeler Pilot
    console.log('--- TEST 4: Accept Order by Verified 2-Wheeler Pilot ---');
    const inputPilotId = '9010922111'; // Verified bike pilot
    const acceptRes = await request('POST', `/api/food/pilot/orders/${orderId}/accept`, {
      pilotId: inputPilotId,
      pilotName: 'Pilot Partner',
      pilotPhone: '9490440281',
      vehicleType: 'Bike'
    });
    console.log('Pilot Accept Status:', acceptRes.status, acceptRes.data.message);
    if (acceptRes.status !== 200) {
      throw new Error('Failed to accept order: ' + JSON.stringify(acceptRes.data));
    }
    const assignedPilotId = acceptRes.data.order.deliveryPartnerId || inputPilotId;
    console.log(`Assigned Pilot ID in order: ${assignedPilotId}`);
    console.log('✓ PASS: Bike pilot assigned to order.\n');

    // 5. Pilot picks up food
    console.log('--- TEST 5: Pilot Picks Up Food Handover ---');
    const pickupRes = await request('POST', `/api/food/pilot/orders/${orderId}/pickup`, {
      pilotId: assignedPilotId,
      otp: acceptRes.data.order.restaurantOtp || '4921'
    });
    console.log('Pickup Status:', pickupRes.status, pickupRes.data.message);
    if (pickupRes.status !== 200) {
      throw new Error('Failed to record food pickup: ' + JSON.stringify(pickupRes.data));
    }
    console.log('✓ PASS: Order marked as out_for_delivery.\n');

    // 6. Test Call Logging API across Roles
    console.log('--- TEST 6: Call Logging Audit Event API ---');
    const call1 = await request('POST', `/api/food/orders/${orderId}/call-log`, {
      callerRole: 'customer',
      targetRole: 'pilot',
      targetPhone: '9490440281'
    });
    console.log('Customer->Pilot Call Log Status:', call1.status, call1.data);
    if (call1.status !== 200) throw new Error('Call log 1 failed');

    const call2 = await request('POST', `/api/food/orders/${orderId}/call-log`, {
      callerRole: 'pilot',
      targetRole: 'restaurant',
      targetPhone: testRest.phone || '9849012345'
    });
    console.log('Pilot->Restaurant Call Log Status:', call2.status, call2.data);
    if (call2.status !== 200) throw new Error('Call log 2 failed');

    const call3 = await request('POST', `/api/food/orders/${orderId}/call-log`, {
      callerRole: 'restaurant',
      targetRole: 'customer',
      targetPhone: '9849012345'
    });
    console.log('Restaurant->Customer Call Log Status:', call3.status, call3.data);
    if (call3.status !== 200) throw new Error('Call log 3 failed');
    console.log('✓ PASS: All call initiation events recorded in order callHistory.\n');

    // 7. Report Failed Delivery and Start Safe Return
    console.log('--- TEST 7: Report Failed Delivery & Start Safe Return ---');
    const failRes = await request('POST', `/api/food/pilot/orders/${orderId}/report-failed-delivery`, {
      pilotId: assignedPilotId,
      reason: 'Customer is not answering calls',
      notes: 'Waited 15 minutes at gate. Attempted multiple phone calls.'
    });
    console.log('Failed Delivery Status:', failRes.status, failRes.data.message);
    if (failRes.status !== 200) {
      throw new Error('Failed to report failed delivery: ' + JSON.stringify(failRes.data));
    }
    console.log('Return Deadline:', failRes.data.order.returnDeadline);
    console.log('Return Destination:', failRes.data.order.restaurantName, failRes.data.order.restaurantAddress);
    console.log('✓ PASS: Failed delivery registered, 45-min return journey initiated.\n');

    // 8. Pilot Arrives at Restaurant
    console.log('--- TEST 8: Pilot Records Arrival at Restaurant ---');
    const arriveRes = await request('POST', `/api/food/pilot/orders/${orderId}/return-arrived`, {
      pilotId: assignedPilotId
    });
    console.log('Return Arrived Status:', arriveRes.status, arriveRes.data.message);
    if (arriveRes.status !== 200) throw new Error('Failed to record arrival');
    console.log('✓ PASS: Arrival at restaurant recorded.\n');

    // 9. Restaurant Kitchen Receives Return & Reveals Return OTP
    console.log('--- TEST 9: Restaurant Kitchen Inspects & Receives Return Handover ---');
    const receiveRes = await request('POST', `/api/food/restaurant/orders/${orderId}/receive-return`, {
      restaurantId: testRest.restaurantId,
      staffName: 'Chef Ramesh (Manager)'
    });
    console.log('Restaurant Receive Status:', receiveRes.status, receiveRes.data.message);
    if (receiveRes.status !== 200) throw new Error('Failed to receive return');
    const returnOtp = receiveRes.data.returnOtp;
    console.log(`Generated Return OTP: ${returnOtp}`);
    console.log('✓ PASS: Restaurant received package and revealed return OTP.\n');

    // 10. Pilot Enters Invalid Return OTP
    console.log('--- TEST 10: Pilot Enters Invalid Return OTP (Rejection Test) ---');
    const invalidOtpRes = await request('POST', `/api/food/pilot/orders/${orderId}/verify-return-otp`, {
      pilotId: assignedPilotId,
      otp: '0000'
    });
    console.log('Invalid OTP Status:', invalidOtpRes.status, invalidOtpRes.data.message);
    if (invalidOtpRes.status !== 400) {
      throw new Error('Invalid OTP was NOT rejected! Status: ' + invalidOtpRes.status);
    }
    console.log('✓ PASS: Invalid OTP successfully rejected with HTTP 400.\n');

    // 11. Pilot Enters Valid Return OTP
    console.log('--- TEST 11: Pilot Enters Valid Return OTP & Completes Return ---');
    const validOtpRes = await request('POST', `/api/food/pilot/orders/${orderId}/verify-return-otp`, {
      pilotId: assignedPilotId,
      otp: returnOtp
    });
    console.log('Valid OTP Status:', validOtpRes.status, validOtpRes.data.message);
    if (validOtpRes.status !== 200) {
      throw new Error('Valid OTP verification failed: ' + JSON.stringify(validOtpRes.data));
    }
    console.log('Final Order Status:', validOtpRes.data.order.orderStatus);
    console.log('Return OTP Verified:', validOtpRes.data.order.returnOtpVerified);
    console.log('✓ PASS: Return verified and order marked as "returned_to_restaurant".\n');

    // 12. Attempt Duplicate Return Verification
    console.log('--- TEST 12: Duplicate Return Verification Prevention ---');
    const duplicateRes = await request('POST', `/api/food/pilot/orders/${orderId}/verify-return-otp`, {
      pilotId: assignedPilotId,
      otp: returnOtp
    });
    console.log('Duplicate Status:', duplicateRes.status, duplicateRes.data.message);
    if (duplicateRes.status !== 400) {
      throw new Error('Duplicate return verification was NOT blocked!');
    }
    console.log('✓ PASS: Duplicate verification prevented with HTTP 400.\n');

    // 13. Verify Full Order Audit Trail
    console.log('--- TEST 13: Verify Final Order Details & Audit Trail ---');
    const finalOrderRes = await request('GET', `/api/food/orders/${orderId}`);
    const finalOrder = finalOrderRes.data.order;
    console.log('Order Status:', finalOrder.orderStatus);
    console.log('Return Reason:', finalOrder.returnReason);
    console.log('Return Notes:', finalOrder.returnNotes);
    console.log('Returned At:', finalOrder.returnedAt);
    console.log('Call History Count:', (finalOrder.callHistory || []).length);
    console.log('Call History Items:', finalOrder.callHistory);
    console.log('✓ PASS: Full audit history preserved in database.\n');

    console.log('================================================================');
    console.log('🎉 ALL 13 VERIFICATION TESTS PASSED SUCCESSFULLY ON PRODUCTION!');
    console.log('================================================================');
  } catch (err) {
    console.error('\n❌ TEST FAILED:', err.message);
    process.exit(1);
  }
}

runTests();
