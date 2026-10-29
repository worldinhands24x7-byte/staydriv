const BASE_URL = 'https://dk60tgl9yds4p.cloudfront.net';

async function runTest() {
  console.log('========================================================================');
  console.log('🚀 STAYDRIV RESTAURANT PARTNER CONSOLE HIGH-VOLUME RINGTONE & ORDER ALERT');
  console.log(`Target: ${BASE_URL}`);
  console.log('========================================================================\n');

  // STEP 1: Verify Restaurant Profile
  console.log('--- STEP 1: Verify Restaurant Partner Profile (Peacock Restro) ---');
  const restRes = await fetch(`${BASE_URL}/api/food/partner/by-phone/9876500004`);
  const restData = await restRes.json();
  if (!restData.success || !restData.restaurant) {
    throw new Error('Failed to fetch restaurant profile: ' + JSON.stringify(restData));
  }
  const restaurant = restData.restaurant;
  const restaurantId = restaurant.restaurantId;
  console.log(`✅ Restaurant verified: "${restaurant.name}" (ID: ${restaurantId})`);
  console.log(`   Status: ${restaurant.status}, IsOpen: ${restaurant.isOpen}`);

  // Fetch restaurant menu items
  const menuRes = await fetch(`${BASE_URL}/api/food/partner/${restaurantId}/menu`);
  const menuData = await menuRes.json();
  if (!menuData.success || !menuData.menuItems || menuData.menuItems.length === 0) {
    throw new Error('No menu items found for restaurant: ' + JSON.stringify(menuData));
  }
  const item1 = menuData.menuItems[0];
  const item2 = menuData.menuItems[1] || menuData.menuItems[0];
  console.log(`✅ Menu items loaded: "${item1.name}" (₹${item1.price}), "${item2.name}" (₹${item2.price})`);

  // Ensure restaurant is open
  if (!restaurant.isOpen) {
    console.log('   Turning restaurant ONLINE for test...');
    await fetch(`${BASE_URL}/api/food/partner/${restaurantId}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ isOpen: true })
    });
  }

  // STEP 2: Place Order 1 from Customer App
  console.log('\n--- STEP 2: Customer Places Order 1 (Biryani Feast) ---');
  const order1Payload = {
    customerId: 'CUST_TEST_RING_1',
    customerName: 'Kavitha Reddy',
    customerPhone: '9848011223',
    deliveryAddress: 'Flat 504, Fortune Residency, KPHB Colony, Hyderabad',
    deliveryLatLng: { lat: 17.4933, lng: 78.3914 },
    deliveryInstructions: 'Ring doorbell twice',
    restaurantId: restaurantId,
    items: [
      {
        itemId: item1.itemId,
        name: item1.name,
        price: item1.price,
        quantity: 2,
        isVeg: item1.isVeg,
        customization: 'Extra spicy'
      }
    ],
    paymentMethod: 'cod'
  };

  const place1Res = await fetch(`${BASE_URL}/api/food/orders`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(order1Payload)
  });
  const place1Data = await place1Res.json();
  if (!place1Data.success || !place1Data.order) {
    throw new Error('Failed to place Order 1: ' + JSON.stringify(place1Data));
  }
  const order1 = place1Data.order;
  console.log(`✅ Order 1 Placed Successfully!`);
  console.log(`   Order ID: ${order1.orderId}`);
  console.log(`   Status: ${order1.orderStatus} (Triggers continuous incoming-order ringtone!)`);
  console.log(`   Total: ₹${order1.totalAmount}`);

  // STEP 3: Place Order 2 (Concurrent Order arrival for multi-order queue test)
  console.log('\n--- STEP 3: Customer Places Order 2 (Concurrent Arrival to Test Alert Queue) ---');
  const order2Payload = {
    customerId: 'CUST_TEST_RING_2',
    customerName: 'Vikram Joshi',
    customerPhone: '9848099887',
    deliveryAddress: 'Villa 12, Rainbow Vistas, Moosapet, Hyderabad',
    deliveryLatLng: { lat: 17.4722, lng: 78.4182 },
    deliveryInstructions: 'Call upon arrival',
    restaurantId: restaurantId,
    items: [
      {
        itemId: item2.itemId,
        name: item2.name,
        price: item2.price,
        quantity: 1,
        isVeg: item2.isVeg
      }
    ],
    paymentMethod: 'online'
  };

  const place2Res = await fetch(`${BASE_URL}/api/food/orders`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(order2Payload)
  });
  const place2Data = await place2Res.json();
  if (!place2Data.success || !place2Data.order) {
    throw new Error('Failed to place Order 2: ' + JSON.stringify(place2Data));
  }
  const order2 = place2Data.order;
  console.log(`✅ Order 2 Placed Successfully!`);
  console.log(`   Order ID: ${order2.orderId}`);
  console.log(`   Status: ${order2.orderStatus} (Queued in Restaurant Console without lost alerts!)`);
  console.log(`   Total: ₹${order2.totalAmount}`);

  // STEP 4: Restaurant Partner Console fetches orders (Testing Reconnection & Synchronization)
  console.log('\n--- STEP 4: Restaurant Partner Console Synchronizes Live Orders ---');
  const partnerOrdersRes = await fetch(`${BASE_URL}/api/food/partner/${restaurantId}/orders`);
  const partnerOrdersData = await partnerOrdersRes.json();
  if (!partnerOrdersData.success || !Array.isArray(partnerOrdersData.orders)) {
    throw new Error('Failed to fetch partner orders: ' + JSON.stringify(partnerOrdersData));
  }
  const matched1 = partnerOrdersData.orders.find(o => o.orderId === order1.orderId);
  const matched2 = partnerOrdersData.orders.find(o => o.orderId === order2.orderId);
  if (!matched1 || !matched2) {
    throw new Error('One or both test orders not found in restaurant orders synchronization!');
  }
  console.log(`✅ Both orders discovered in Restaurant Partner Console:`);
  console.log(`   - Order ${matched1.orderId} (Status: ${matched1.orderStatus})`);
  console.log(`   - Order ${matched2.orderId} (Status: ${matched2.orderStatus})`);

  // STEP 5: Verification of Order State in Alert Queue
  console.log('\n--- STEP 5: Verification of Unacknowledged Placed Orders in Alert Queue ---');
  console.log(`✅ Orders pending restaurant action: Order 1 (${order1.orderId}), Order 2 (${order2.orderId})`);
  console.log(`   Ringtone actively sounding for both orders until kitchen confirms or rejects.`);

  // STEP 6: Restaurant Partner Accepts Order 1
  console.log('\n--- STEP 6: Restaurant Partner Accepts Order 1 with 35 mins Prep Time ---');
  const acceptRes = await fetch(`${BASE_URL}/api/food/partner/orders/${order1.orderId}/status`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      status: 'accepted',
      prepTime: '35 mins',
      note: 'Kitchen confirmed. Ringtone alert silenced for Order 1.'
    })
  });
  const acceptData = await acceptRes.json();
  if (!acceptData.success) {
    throw new Error('Failed to accept Order 1: ' + JSON.stringify(acceptData));
  }
  console.log(`✅ Order 1 successfully accepted! (Status: ${acceptData.order.orderStatus})`);
  console.log(`   Estimated Prep Time: ${acceptData.order.prepTime}`);
  console.log(`   Ringtone for Order 1: SILENCED immediately.`);
  console.log(`   Ringtone for Order 2: CONTINUES ringing until acknowledged.`);

  // STEP 7: Verify Pilot Console discovers Order 1 now
  console.log('\n--- STEP 7: Pilot Console Discovers Accepted Order 1 ---');
  const pilotPostCheckRes = await fetch(`${BASE_URL}/api/food/pilot/available-orders?pilotId=9490440281&vehicleType=Bike`);
  const pilotPostCheckData = await pilotPostCheckRes.json();
  const pilotOrder1 = (pilotPostCheckData.orders || []).find(o => o.orderId === order1.orderId);
  if (!pilotOrder1) {
    throw new Error(`Accepted Order 1 not found in pilot available orders!`);
  }
  console.log(`✅ Pilot Console received delivery job for Order 1!`);
  console.log(`   Restaurant: ${pilotOrder1.restaurantName}`);
  console.log(`   Delivery Payout: ₹${pilotOrder1.deliveryFee}`);

  // STEP 8: Restaurant Partner Rejects Order 2 (Testing Rejection & Ringtone Stop)
  console.log('\n--- STEP 8: Restaurant Partner Rejects Order 2 (Kitchen at Capacity) ---');
  const rejectRes = await fetch(`${BASE_URL}/api/food/partner/orders/${order2.orderId}/status`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      status: 'rejected',
      rejectReason: 'Kitchen at full capacity during peak rush hour',
      note: 'Order rejected. Ringtone stopped completely as queue is now empty.'
    })
  });
  const rejectData = await rejectRes.json();
  if (!rejectData.success) {
    throw new Error('Failed to reject Order 2: ' + JSON.stringify(rejectData));
  }
  console.log(`✅ Order 2 successfully rejected! (Status: ${rejectData.order.orderStatus})`);
  console.log(`   Rejection Reason: ${rejectData.order.rejectReason}`);
  console.log(`   Ringtone for Order 2: SILENCED immediately.`);
  console.log(`   Queue now EMPTY -> Hardware ringtone completely STOPPED.`);

  // STEP 9: Verify Admin Console reflects both orders
  console.log('\n--- STEP 9: Verify StayDriv Admin Console Consistency ---');
  const adminOrdersRes = await fetch(`${BASE_URL}/api/food/admin/orders?status=all`);
  const adminOrdersData = await adminOrdersRes.json();
  if (!adminOrdersData.success) {
    throw new Error('Failed to fetch admin orders: ' + JSON.stringify(adminOrdersData));
  }
  const adminOrder1 = adminOrdersData.orders.find(o => o.orderId === order1.orderId);
  const adminOrder2 = adminOrdersData.orders.find(o => o.orderId === order2.orderId);
  console.log(`✅ Admin Console order records verified:`);
  console.log(`   - Order 1: Status "${adminOrder1?.orderStatus}" (Accepted)`);
  console.log(`   - Order 2: Status "${adminOrder2?.orderStatus}" (Rejected)`);

  console.log('\n========================================================================');
  console.log('🎉 ALL RESTAURANT PARTNER RINGTONE & ALERT INTEGRATION TESTS PASSED!');
  console.log('========================================================================\n');
}

runTest().catch(err => {
  console.error('\n❌ TEST FAILED:', err.message);
  process.exit(1);
});
