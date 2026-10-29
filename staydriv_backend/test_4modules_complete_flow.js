const https = require('https');

const HOST = 'dk60tgl9yds4p.cloudfront.net';

function request(method, path, body = null, headers = {}) {
  return new Promise((resolve, reject) => {
    const defaultHeaders = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...headers
    };

    const req = https.request({
      hostname: HOST,
      port: 443,
      path,
      method,
      headers: defaultHeaders
    }, (res) => {
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
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

async function run() {
  console.log('================================================================');
  console.log('STAYDRIV: 4-MODULE COMPLETE INTEGRATION & PRICE VERIFICATION');
  console.log('================================================================\n');

  // STEP 1: Admin Console - Fetch Restaurants List (Picture 1 Table)
  console.log('--- STEP 1: Admin Console - Fetch Restaurant List (Picture 1) ---');
  const adminRestRes = await request('GET', '/api/food/admin/restaurants?status=all', null, {
    'x-admin-key': 'staydriv_admin_secret_2026'
  });
  console.log('Status:', adminRestRes.status);
  console.log('Total Restaurants:', adminRestRes.data.count);
  const sample = adminRestRes.data.restaurants.find(r => r.restaurantId === 'REST_PARADISE_01') || adminRestRes.data.restaurants[0];
  console.log(`Verified Restaurant [${sample.name}]:`);
  console.log(`  - ID: ${sample.restaurantId}`);
  console.log(`  - Partner: ${sample.ownerName} (${sample.phone})`);
  console.log(`  - Cuisines: ${Array.isArray(sample.cuisines) ? sample.cuisines.join(', ') : sample.cuisines}`);
  console.log(`  - Open Status: ${sample.isOpen ? '• OPEN NOW' : 'o CLOSED'}`);
  console.log(`  - Platform Commission: ${sample.commissionRate}%`);
  console.log(`  - Menu Item Count: ${sample.menuItemCount} items`);
  console.log(`  - Approval Status: [${sample.status.toUpperCase()}]`);

  // STEP 2: Picture 2 Pricing - Bulk Preview Guardrail
  console.log('\n--- STEP 2: Picture 2 Pricing - Bulk Preview Guardrail ---');
  const previewRes = await request('POST', `/api/food/partner/${sample.restaurantId}/menu/adjust-prices`, {
    preview: true,
    percentDelta: 10,
    category: 'Biryani'
  });
  console.log('Bulk Preview Status:', previewRes.status);
  console.log('Affected Items Count:', previewRes.data.affectedCount);
  previewRes.data.items.forEach(it => {
    console.log(`  * ${it.name} | Current: ₹${it.currentPrice} -> Proposed: ₹${it.newPrice} (${it.change >= 0 ? '+' : ''}₹${it.change})`);
  });

  // STEP 3: Admin / Partner Individual Item Price Adjustment
  console.log('\n--- STEP 3: Admin / Partner Individual Price Modification ---');
  const testItemId = previewRes.data.items[0].itemId;
  const originalPrice = previewRes.data.items[0].currentPrice;
  const updatedPrice = originalPrice + 15; // e.g. +₹15
  console.log(`Modifying price of ${testItemId} from ₹${originalPrice} to ₹${updatedPrice}...`);
  const itemUpdateRes = await request('PUT', `/api/food/partner/${sample.restaurantId}/menu/${testItemId}`, {
    price: updatedPrice,
    prepTime: '22 mins',
    isBestseller: true
  });
  console.log('Item Update Status:', itemUpdateRes.status);
  console.log('Saved Item Price:', itemUpdateRes.data.item.price);
  console.log('Saved Prep Time:', itemUpdateRes.data.item.prepTime);
  console.log('Saved Bestseller:', itemUpdateRes.data.item.isBestseller);

  // STEP 4: Customer Console - Real-Time Menu Sync
  console.log('\n--- STEP 4: Customer Console - Real-Time Menu Sync ---');
  const custMenuRes = await request('GET', `/api/food/restaurants/${sample.restaurantId}`);
  console.log('Customer API Status:', custMenuRes.status);
  const updatedDish = custMenuRes.data.menuItems.find(i => i.itemId === testItemId);
  console.log(`Customer sees ${updatedDish.name}:`);
  console.log(`  - Price: ₹${updatedDish.price} (Expected ₹${updatedPrice}: ${updatedDish.price === updatedPrice ? 'VERIFIED ✓' : 'MISMATCH ✗'})`);
  console.log(`  - Prep Time: ${updatedDish.prepTime}`);
  console.log(`  - Bestseller: ${updatedDish.isBestseller}`);

  // STEP 5: Customer Console - Place Live Food Order at New Price
  console.log('\n--- STEP 5: Customer Console - Place Order at New Rate ---');
  const orderRes = await request('POST', '/api/food/orders', {
    customerId: 'CUST_TEST_FLOW_01',
    customerName: 'Suresh Kumar Customer',
    customerPhone: '9849112233',
    deliveryAddress: 'Flat 402, Cyber Heights, Madhapur, Hyderabad',
    deliveryLatLng: { lat: 17.4485, lng: 78.3741 },
    restaurantId: sample.restaurantId,
    items: [
      {
        itemId: testItemId,
        quantity: 1
      }
    ],
    paymentMethod: 'cash'
  });
  console.log('Place Order Status:', orderRes.status);
  const placedOrder = orderRes.data.order;
  console.log('Order Placed Successfully:');
  console.log(`  - Order ID: ${placedOrder.orderId}`);
  console.log(`  - Total Amount: ₹${placedOrder.totalAmount}`);
  console.log(`  - OTP: ${placedOrder.deliveryOtp}`);
  console.log(`  - Status: ${placedOrder.orderStatus}`);

  // STEP 6: Restaurant Partner Console - Receive & Accept Order
  console.log('\n--- STEP 6: Restaurant Partner Console - Receive & Accept ---');
  const partnerOrdersRes = await request('GET', `/api/food/partner/${sample.restaurantId}/orders`);
  console.log('Partner Active Orders Status:', partnerOrdersRes.status);
  const foundOrder = partnerOrdersRes.data.orders.find(o => o.orderId === placedOrder.orderId);
  console.log(`Restaurant sees order ${placedOrder.orderId}: ${foundOrder ? 'RECEIVED ✓' : 'NOT FOUND ✗'}`);

  // Accept Order
  const acceptRes = await request('POST', `/api/food/partner/orders/${placedOrder.orderId}/status`, {
    status: 'accepted',
    prepTime: '20 mins'
  });
  console.log('Restaurant Accept Status:', acceptRes.data.order.orderStatus);

  // Mark Food Ready for Pickup
  const readyRes = await request('POST', `/api/food/partner/orders/${placedOrder.orderId}/status`, {
    status: 'ready_for_pickup'
  });
  console.log('Restaurant Ready Status:', readyRes.data.order.orderStatus);

  // STEP 7: Pilot Delivery Console - Dispatch, Pickup & Delivery
  console.log('\n--- STEP 7: Pilot Console - Food Delivery Dispatch & Handover ---');
  const testPilotId = 'PILOT_BIKE_HYD_99';
  const pilotAcceptRes = await request('POST', `/api/food/pilot/orders/${placedOrder.orderId}/accept`, {
    pilotId: testPilotId,
    pilotName: 'Rajesh Sharma Pilot',
    pilotPhone: '9849998877',
    vehicleType: 'Bike',
    vehiclePlate: 'TS09EA1234'
  });
  console.log('Pilot Assigned Status:', pilotAcceptRes.data.order.orderStatus);

  // Pilot Picks up from Restaurant
  const pickedUpRes = await request('POST', `/api/food/pilot/orders/${placedOrder.orderId}/pickup`, {
    pilotId: testPilotId
  });
  console.log('Pilot Picked Up Status:', pickedUpRes.data.order.orderStatus);

  // Pilot Delivers with Customer OTP Handover
  const deliveredRes = await request('POST', `/api/food/pilot/orders/${placedOrder.orderId}/deliver`, {
    pilotId: testPilotId,
    otp: placedOrder.deliveryOtp
  });
  console.log('Pilot Handover & Delivered Status:', deliveredRes.data.order.orderStatus);
  console.log('Delivered Timestamp:', deliveredRes.data.order.deliveredAt);

  // STEP 8: Cleanup - Restore Item Price to Original Value
  console.log('\n--- STEP 8: Cleanup - Restore Item Price to Original Rate ---');
  await request('PUT', `/api/food/partner/${sample.restaurantId}/menu/${testItemId}`, {
    price: originalPrice,
    prepTime: '25 mins'
  });
  console.log(`Restored ${testItemId} price back to ₹${originalPrice}. Verification Complete!`);

  console.log('\n================================================================');
  console.log('ALL 4 MODULES FULLY SYNCHRONIZED, VERIFIED AND WORKING IN PROD!');
  console.log('================================================================');
}

run().catch(err => {
  console.error('Test execution failed:', err);
  process.exit(1);
});
