const http = require('http');

const BASE_URL = process.env.TEST_URL || 'http://localhost:3000';

async function req(method, endpoint, body = null) {
  const url = new URL(endpoint, BASE_URL);
  const options = {
    method,
    headers: { 'Content-Type': 'application/json' },
  };
  if (body) {
    options.body = JSON.stringify(body);
  }
  const res = await fetch(url.toString(), options);
  const data = await res.json().catch(() => null);
  return { status: res.status, ok: res.ok, data };
}

async function runTests() {
  console.log(`================================================================`);
  console.log(`  StayDriv Restaurant Management, Menu & Sync Test Suite`);
  console.log(`  Target: ${BASE_URL}`);
  console.log(`================================================================\n`);

  let passed = 0;
  let failed = 0;

  function assert(desc, condition, details = '') {
    if (condition) {
      console.log(`  [PASS] ${desc}`);
      passed++;
    } else {
      console.error(`  [FAIL] ${desc} ${details ? '(' + details + ')' : ''}`);
      failed++;
    }
  }

  const testId = Date.now().toString().slice(-6);
  const testRestId = `REST_TEST_${testId}`;
  const testPhone = `9849${testId}`;

  // -------------------------------------------------------------------------
  // TEST A: Add restaurant, approve, verify admin & customer visibility
  // -------------------------------------------------------------------------
  console.log(`--- TEST A: Add Restaurant & Approval Workflow ---`);
  
  const addRestRes = await req('POST', '/api/food/admin/restaurants', {
    restaurantId: testRestId,
    name: `Test Bistro ${testId}`,
    ownerName: 'Venkatesh Rao',
    phone: testPhone,
    email: `bistro_${testId}@staydriv.com`,
    address: 'Madhapur Cyber Gateway, Hyderabad',
    cuisines: ['South Indian', 'Biryani'],
    categories: ['Main Course', 'Starters', 'Beverages'],
    commissionRate: 15.0,
    deliveryFee: 30,
    deliveryTime: '20-30 mins',
    openingHours: '08:00 AM - 11:00 PM',
    isVegOnly: false,
    status: 'approved',
    isOpen: true
  });

  assert('Admin successfully creates new restaurant', addRestRes.ok && addRestRes.data?.success, JSON.stringify(addRestRes.data));

  // Verify restaurant appears in customer listing
  const custRestRes = await req('GET', `/api/food/restaurants?q=${testId}`);
  const custFound = custRestRes.data?.restaurants?.find(r => r.restaurantId === testRestId);
  assert('Approved restaurant visible in Customer listing', !!custFound, `Found: ${!!custFound}`);
  assert('Restaurant commission correctly preserved in database', addRestRes.data?.restaurant?.commissionRate === 15.0);

  // -------------------------------------------------------------------------
  // TEST B: Add menu item with photo, description, price
  // -------------------------------------------------------------------------
  console.log(`\n--- TEST B: Add Menu Item (Restaurant Partner & Admin) ---`);

  const addDishRes = await req('POST', `/api/food/partner/${testRestId}/menu`, {
    name: 'Special Ghee Roast Dosa',
    price: 180,
    category: 'Main Course',
    description: 'Crispy golden crepe roasted in pure desi ghee, served with 4 fresh chutneys.',
    isVeg: true,
    isAvailable: true,
    imageUrl: 'https://images.unsplash.com/photo-1610192244261-3f33de3f55e4?w=800'
  });

  assert('Partner successfully adds food item with photo & description', addDishRes.ok && addDishRes.data?.success);
  const createdItemId = addDishRes.data?.item?.itemId;
  assert('Food item assigned unique itemId', !!createdItemId, `itemId: ${createdItemId}`);

  // Verify item shows up in restaurant menu
  const menuRes = await req('GET', `/api/food/restaurants/${testRestId}`);
  const itemInMenu = menuRes.data?.menuItems?.find(i => i.itemId === createdItemId);
  assert('Food item is queryable on Customer & Partner menu', !!itemInMenu && itemInMenu.price === 180);

  // -------------------------------------------------------------------------
  // TEST C: Change price (Picture 2 controls: ±₹10, ±₹50, manual rate)
  // -------------------------------------------------------------------------
  console.log(`\n--- TEST C: Price Management (Picture 2 Quick & Bulk Controls) ---`);

  // 1. Partner quick increment (+₹50)
  const adjustPlus50 = await req('PUT', `/api/food/partner/${testRestId}/menu/${createdItemId}`, {
    priceDelta: 50
  });
  assert('Quick price adjustment (+₹50) succeeds', adjustPlus50.ok && adjustPlus50.data?.item?.price === 230, `New Price: ${adjustPlus50.data?.item?.price}`);

  // 2. Partner quick decrement (-₹10)
  const adjustMinus10 = await req('PUT', `/api/food/partner/${testRestId}/menu/${createdItemId}`, {
    priceDelta: -10
  });
  assert('Quick price adjustment (-₹10) succeeds', adjustMinus10.ok && adjustMinus10.data?.item?.price === 220, `New Price: ${adjustMinus10.data?.item?.price}`);

  // 3. Manual price change box (e.g. ₹ 245)
  const manualPriceRes = await req('PUT', `/api/food/partner/${testRestId}/menu/${createdItemId}`, {
    price: 245
  });
  assert('Manual exact rate entry persists to backend', manualPriceRes.ok && manualPriceRes.data?.item?.price === 245, `Price: ${manualPriceRes.data?.item?.price}`);

  // 4. Bulk price adjustment (+₹20 across category)
  const bulkAdjustRes = await req('POST', `/api/food/partner/${testRestId}/menu/adjust-prices`, {
    delta: 20,
    category: 'Main Course'
  });
  assert('Bulk category price adjustment succeeds', bulkAdjustRes.ok && bulkAdjustRes.data?.success);

  const menuAfterBulk = await req('GET', `/api/food/restaurants/${testRestId}`);
  const itemAfterBulk = menuAfterBulk.data?.menuItems?.find(i => i.itemId === createdItemId);
  assert('New bulk adjusted price (₹ 265) visible across Customer and Partner', itemAfterBulk?.price === 265, `Price: ${itemAfterBulk?.price}`);

  // -------------------------------------------------------------------------
  // TEST D: Remove or deactivate item
  // -------------------------------------------------------------------------
  console.log(`\n--- TEST D: Item Availability & Deactivation ---`);

  // Deactivate item (mark out of stock)
  const deactivateRes = await req('PUT', `/api/food/partner/${testRestId}/menu/${createdItemId}`, {
    isAvailable: false
  });
  assert('Partner toggles item availability to Out of Stock', deactivateRes.ok && deactivateRes.data?.item?.isAvailable === false);

  const menuAfterDeact = await req('GET', `/api/food/restaurants/${testRestId}`);
  const deactItem = menuAfterDeact.data?.menuItems?.find(i => i.itemId === createdItemId);
  assert('Item marked unavailable in customer view', deactItem?.isAvailable === false);

  // Re-activate item for order placement test
  await req('PUT', `/api/food/partner/${testRestId}/menu/${createdItemId}`, {
    isAvailable: true
  });

  // -------------------------------------------------------------------------
  // TEST E: Place Order & Full Multi-Console Life Cycle
  // -------------------------------------------------------------------------
  console.log(`\n--- TEST E: Order Placement & Live Synchronization ---`);

  const orderRes = await req('POST', '/api/food/orders', {
    customerId: 'CUST_TEST_01',
    restaurantId: testRestId,
    customerName: 'Rahul Varma',
    customerPhone: '9849112233',
    deliveryAddress: {
      address: 'Flat 402, Cyber Heights, Madhapur, Hyderabad',
      lat: 17.4485,
      lng: 78.3741
    },
    items: [
      {
        itemId: createdItemId,
        quantity: 2
      }
    ],
    deliveryFee: 30,
    tip: 20,
    paymentMethod: 'staydriv_wallet'
  });

  assert('Customer places food order with server-validated rates', orderRes.ok && orderRes.data?.success, JSON.stringify(orderRes.data));
  const orderId = orderRes.data?.order?.orderId;
  assert('Order generated with valid orderId', !!orderId, `OrderID: ${orderId}`);

  // Partner receives order
  const partnerOrdersRes = await req('GET', `/api/food/partner/${testRestId}/orders`);
  const partnerFoundOrder = partnerOrdersRes.data?.orders?.find(o => o.orderId === orderId);
  assert('Restaurant Partner Console receives new incoming order', !!partnerFoundOrder);

  // Admin console displays same order
  const adminOrdersRes = await req('GET', `/api/food/admin/orders?search=${orderId}`);
  const adminFoundOrder = adminOrdersRes.data?.orders?.find(o => o.orderId === orderId);
  assert('Admin Console displays same order in real time', !!adminFoundOrder);

  // Partner accepts order with prep time
  const acceptRes = await req('POST', `/api/food/partner/orders/${orderId}/status`, {
    status: 'accepted',
    prepTime: '25 mins'
  });
  assert('Partner accepts order with estimated preparation time', acceptRes.ok && acceptRes.data?.order?.orderStatus === 'accepted');

  // Partner marks preparing -> ready_for_pickup
  const prepRes = await req('POST', `/api/food/partner/orders/${orderId}/status`, {
    status: 'preparing'
  });
  assert('Partner updates status to "preparing"', prepRes.ok && prepRes.data?.order?.orderStatus === 'preparing');

  const readyRes = await req('POST', `/api/food/partner/orders/${orderId}/status`, {
    status: 'ready_for_pickup'
  });
  assert('Partner updates status to "ready_for_pickup"', readyRes.ok && readyRes.data?.order?.orderStatus === 'ready_for_pickup');

  // -------------------------------------------------------------------------
  // TEST F: Order Cancellation & Status History Audit
  // -------------------------------------------------------------------------
  console.log(`\n--- TEST F: Order Audit History & Cancellation Sync ---`);

  const historyOrder = await req('GET', `/api/food/orders/${orderId}`);
  assert('Order contains complete status audit history', historyOrder.data?.order?.statusHistory?.length >= 3);

  // Test cancellation synchronization
  const cancelRes = await req('POST', `/api/food/admin/orders/${orderId}/status`, {
    status: 'cancelled',
    note: 'Customer requested cancellation prior to pickup'
  });
  assert('Admin cancels order with reason and note', cancelRes.ok && cancelRes.data?.order?.orderStatus === 'cancelled');

  // -------------------------------------------------------------------------
  // TEST G: Security & Role Boundaries
  // -------------------------------------------------------------------------
  console.log(`\n--- TEST G: Security & Role Boundaries ---`);

  // Partner attempts to illegally alter commission rate or approve status
  const maliciousPartnerUpdate = await req('PUT', `/api/food/partner/${testRestId}/info`, {
    commissionRate: 0.0,
    status: 'super_approved',
    phone: '9849555666'
  });

  const checkRestSecurity = await req('GET', `/api/food/restaurants/${testRestId}`);
  assert('Partner cannot modify platform commission rate', checkRestSecurity.data?.restaurant?.commissionRate === 15.0, `Rate: ${checkRestSecurity.data?.restaurant?.commissionRate}`);
  assert('Partner permitted details (phone) updated securely', checkRestSecurity.data?.restaurant?.phone === '9849555666');

  // Suspended restaurant blocks new orders
  await req('PUT', `/api/food/admin/restaurants/${testRestId}/status`, {
    status: 'suspended',
    isOpen: false
  });

  const blockedOrderRes = await req('POST', '/api/food/orders', {
    restaurantId: testRestId,
    customerName: 'Test blocked',
    customerPhone: '9849112233',
    deliveryAddress: { address: 'Hyderabad', lat: 17.44, lng: 78.38 },
    items: [{ itemId: createdItemId, quantity: 1 }],
    deliveryFee: 30
  });

  assert('Orders on suspended or offline restaurants are strictly rejected', blockedOrderRes.status === 400 || blockedOrderRes.data?.success === false);

  // -------------------------------------------------------------------------
  // TEST H: Regression (Rides, Stats, Wallet, Ledger)
  // -------------------------------------------------------------------------
  console.log(`\n--- TEST H: Non-Regression & Core StayDriv Features ---`);

  const statsRes = await req('GET', '/api/food/admin/stats');
  assert('Food admin stats endpoint intact', statsRes.ok && statsRes.data?.success);

  const healthRes = await req('GET', '/api/health');
  assert('StayDriv core backend health endpoint intact', healthRes.ok && healthRes.data?.status === 'UP');

  // Clean up test restaurant
  await req('DELETE', `/api/food/admin/restaurants/${testRestId}`);
  console.log(`\nCleaned up test restaurant ${testRestId}`);

  console.log(`\n================================================================`);
  console.log(`  TEST RESULTS: ${passed} PASSED, ${failed} FAILED`);
  console.log(`================================================================\n`);

  if (failed > 0) {
    process.exit(1);
  }
}

runTests().catch(err => {
  console.error('Test execution error:', err);
  process.exit(1);
});
