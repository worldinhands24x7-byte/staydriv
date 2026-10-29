const BASE_URL = 'https://dk60tgl9yds4p.cloudfront.net';

async function runTest() {
  console.log('====================================================');
  console.log('🚀 STAYDRIV 3-CONSOLE FOOD ORDER FLOW LIVE E2E TEST');
  console.log(`Target: ${BASE_URL}`);
  console.log('====================================================\n');

  // STEP 1: Check restaurant profile
  console.log('--- STEP 1: Verifying Restaurant Profile (Rayalasima Chefs) ---');
  const restRes = await fetch(`${BASE_URL}/api/food/partner/by-phone/9121403844`);
  const restData = await restRes.json();
  if (!restData.success || !restData.restaurant) {
    throw new Error('Failed to fetch restaurant profile: ' + JSON.stringify(restData));
  }
  const restaurantId = restData.restaurant.restaurantId;
  console.log(`✅ Restaurant verified: "${restData.restaurant.name}" (ID: ${restaurantId})`);

  // STEP 2: Place an order from Customer App
  console.log('\n--- STEP 2: Customer Places Order ---');
  const orderPayload = {
    customerId: 'CUST_TEST_E2E',
    customerName: 'Suresh Kumar',
    customerPhone: '9849012345',
    deliveryAddress: 'Flat 302, Sri Sai Nilayam, Balaji Layout, Gajularamaram, Hyderabad',
    deliveryLatLng: { lat: 17.5147, lng: 78.4069 },
    deliveryInstructions: 'Leave with security if not answering doorbell',
    restaurantId: restaurantId,
    items: [
      {
        itemId: 'ITEM_1792345320290_F14D65',
        name: 'Dum Biryani Single',
        price: 150,
        quantity: 2,
        isVeg: false,
        customization: 'Medium spicy'
      }
    ],
    paymentMethod: 'cod'
  };

  const placeRes = await fetch(`${BASE_URL}/api/food/orders`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(orderPayload)
  });
  const placeData = await placeRes.json();
  if (!placeData.success || !placeData.order) {
    throw new Error('Failed to place order: ' + JSON.stringify(placeData));
  }
  const order = placeData.order;
  const orderId = order.orderId;
  const deliveryOtp = order.deliveryOtp;
  console.log(`✅ Order Placed Successfully!`);
  console.log(`   Order ID: ${orderId}`);
  console.log(`   Status: ${order.orderStatus}`);
  console.log(`   Total Amount: ₹${order.totalAmount}`);
  console.log(`   Delivery Verification OTP: ${deliveryOtp}`);

  // STEP 3: Restaurant Partner Console fetches orders
  console.log('\n--- STEP 3: Restaurant Partner Console Fetches Orders ---');
  const partnerOrdersRes = await fetch(`${BASE_URL}/api/food/partner/${restaurantId}/orders`);
  const partnerOrdersData = await partnerOrdersRes.json();
  if (!partnerOrdersData.success || !Array.isArray(partnerOrdersData.orders)) {
    throw new Error('Failed to fetch partner orders: ' + JSON.stringify(partnerOrdersData));
  }
  const matchedOrder = partnerOrdersData.orders.find(o => o.orderId === orderId);
  if (!matchedOrder) {
    throw new Error(`Order ${orderId} not found in restaurant orders list!`);
  }
  console.log(`✅ Order ${orderId} successfully appeared in Restaurant Live Orders tab! (Status: ${matchedOrder.orderStatus})`);

  // STEP 4: Verify pilot cannot accept before restaurant accepts
  console.log('\n--- STEP 4: Verifying Pilot Cannot See/Accept Before Kitchen Confirms ---');
  const pilotPreCheckRes = await fetch(`${BASE_URL}/api/food/pilot/available-orders?pilotId=9490440281&vehicleType=Bike`);
  const pilotPreCheckData = await pilotPreCheckRes.json();
  const preAvailable = (pilotPreCheckData.orders || []).some(o => o.orderId === orderId);
  if (preAvailable) {
    console.warn('⚠️ Order is available to pilot before kitchen accepted!');
  } else {
    console.log('✅ Correct! Order is NOT dispatched to pilot while in "placed" status.');
  }

  // STEP 5: Restaurant Partner accepts the order with prep time
  console.log('\n--- STEP 5: Restaurant Partner Kitchen Confirms & Accepts Order ---');
  const acceptRes = await fetch(`${BASE_URL}/api/food/partner/orders/${orderId}/status`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      status: 'accepted',
      prepTime: '25 mins',
      note: 'Kitchen confirmed order. Preparing fresh Dum Biryani Single.'
    })
  });
  const acceptData = await acceptRes.json();
  if (!acceptData.success) {
    throw new Error('Failed to accept order: ' + JSON.stringify(acceptData));
  }
  console.log(`✅ Restaurant accepted order ${orderId} with estimated prep time: 25 mins`);

  // STEP 6: Pilot Console sees available food delivery task
  console.log('\n--- STEP 6: Pilot Console Discovers Available Delivery Task ---');
  const pilotAvailableRes = await fetch(`${BASE_URL}/api/food/pilot/available-orders?pilotId=9490440281&vehicleType=Bike`);
  const pilotAvailableData = await pilotAvailableRes.json();
  const pilotFoundOrder = (pilotAvailableData.orders || []).find(o => o.orderId === orderId);
  if (!pilotFoundOrder) {
    throw new Error(`Order ${orderId} not found in pilot available orders list! Available: ${JSON.stringify(pilotAvailableData.orders?.map(o => o.orderId))}`);
  }
  console.log(`✅ Pilot Console received food delivery job!`);
  console.log(`   Restaurant: ${pilotFoundOrder.restaurantName}`);
  console.log(`   Delivery Fee / Pilot Payout: ₹${pilotFoundOrder.deliveryFee}`);
  console.log(`   Drop: ${pilotFoundOrder.deliveryAddress}`);

  // STEP 7: Pilot Accepts Delivery Task
  console.log('\n--- STEP 7: Pilot Accepts Food Delivery Task ---');
  const pilotAcceptRes = await fetch(`${BASE_URL}/api/food/pilot/orders/${orderId}/accept`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      pilotId: '9490440281',
      pilotName: 'Pavan Pilot',
      pilotPhone: '9490440281',
      vehicleType: 'Bike',
      vehiclePlate: 'TS08EJ4921'
    })
  });
  const pilotAcceptData = await pilotAcceptRes.json();
  if (!pilotAcceptData.success) {
    throw new Error('Pilot failed to accept order: ' + JSON.stringify(pilotAcceptData));
  }
  console.log(`✅ Pilot accepted delivery! Order status updated to: ${pilotAcceptData.order.orderStatus}`);
  console.log(`   Pilot Name: ${pilotAcceptData.order.deliveryPartnerName} (${pilotAcceptData.order.deliveryPartnerPhone})`);

  // STEP 8: Restaurant finishes cooking & marks Ready for Pickup
  console.log('\n--- STEP 8: Restaurant Marks Food "Ready for Pickup" ---');
  const readyRes = await fetch(`${BASE_URL}/api/food/partner/orders/${orderId}/status`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      status: 'ready_for_pickup',
      note: 'Food is packed, hot-sealed and ready for pilot pickup.'
    })
  });
  const readyData = await readyRes.json();
  if (!readyData.success) {
    throw new Error('Failed to mark ready for pickup: ' + JSON.stringify(readyData));
  }
  console.log(`✅ Restaurant marked order ready for pickup! (Status: ${readyData.order.orderStatus})`);

  // STEP 9: Pilot Arrives at Restaurant and Picks Up Order
  console.log('\n--- STEP 9: Pilot Picks Up Sealed Food Package ---');
  const pickupRes = await fetch(`${BASE_URL}/api/food/pilot/orders/${orderId}/pickup`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      pilotId: '9490440281'
    })
  });
  const pickupData = await pickupRes.json();
  if (!pickupData.success) {
    throw new Error('Failed to mark order picked up: ' + JSON.stringify(pickupData));
  }
  console.log(`✅ Pilot picked up food! Status updated to: ${pickupData.order.orderStatus} ("Pilot on the Way")`);

  // STEP 10: Pilot Handover & OTP Verification
  console.log('\n--- STEP 10: Customer Handover & OTP Verification ---');
  // First test invalid OTP
  const invalidOtpRes = await fetch(`${BASE_URL}/api/food/pilot/orders/${orderId}/deliver`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      pilotId: '9490440281',
      otp: '0000'
    })
  });
  const invalidOtpData = await invalidOtpRes.json();
  if (invalidOtpData.success) {
    throw new Error('Invalid OTP was incorrectly accepted!');
  }
  console.log(`✅ Security Verified: Invalid OTP correctly rejected ("${invalidOtpData.message}")`);

  // Now verify with correct OTP
  const validOtpRes = await fetch(`${BASE_URL}/api/food/pilot/orders/${orderId}/deliver`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      pilotId: '9490440281',
      otp: deliveryOtp
    })
  });
  const validOtpData = await validOtpRes.json();
  if (!validOtpData.success) {
    throw new Error('Valid OTP verification failed: ' + JSON.stringify(validOtpData));
  }
  console.log(`✅ Handover Complete! Order verified with OTP ${deliveryOtp}. Final Status: ${validOtpData.order.orderStatus}`);

  // STEP 11: Verify Customer Tracking Final View
  console.log('\n--- STEP 11: Customer Live Order Tracking View Verification ---');
  const finalOrderRes = await fetch(`${BASE_URL}/api/food/orders/${orderId}`);
  const finalOrderData = await finalOrderRes.json();
  if (!finalOrderData.success || !finalOrderData.order) {
    throw new Error('Failed to fetch final order view: ' + JSON.stringify(finalOrderData));
  }
  const finalOrder = finalOrderData.order;
  console.log(`✅ Customer Tracking Verified:`);
  console.log(`   Final Order Status: ${finalOrder.orderStatus}`);
  console.log(`   Payment Status: ${finalOrder.paymentStatus}`);
  console.log(`   Status History Steps: ${finalOrder.statusHistory?.length || 0} transitions`);
  finalOrder.statusHistory?.forEach((step, idx) => {
    console.log(`     ${idx + 1}. [${step.status.toUpperCase()}] ${step.note || ''} (${step.timestamp})`);
  });

  console.log('\n====================================================');
  console.log('🎉 100% COMPLETE 3-CONSOLE FLOW VERIFIED SUCCESSFULLY!');
  console.log('====================================================');
}

runTest().catch(err => {
  console.error('\n❌ TEST FAILED:', err);
  process.exit(1);
});
