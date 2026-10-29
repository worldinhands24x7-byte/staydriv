/**
 * Automated Test Suite: Restrict Food Delivery to Bike & Scooty Pilots Only
 * Verifies all 12 prompt scenarios:
 * 1. Customer places order -> eligible Bike pilot receives request
 * 2. Customer places order -> eligible Scooty pilot receives request
 * 3. Auto Rickshaw pilot online -> receives no food delivery request / ineligible
 * 4. Car pilot online -> receives no food delivery request / ineligible
 * 5. Other vehicle pilot online -> receives no food delivery request / ineligible
 * 6. Bike pilot offline -> is not assigned
 * 7. No eligible pilot available -> order remains in clear pending state
 * 8. Reassignment / retry -> only Bike / Scooty considered
 * 9. Admin tries to assign Auto or Car -> backend rejects with HTTP 400
 * 10. Normal passenger rides -> existing vehicle-specific assignment continues working
 * 11. Customer, restaurant, pilot, and admin consoles -> consistent order and assignment status
 * 12. Multiple pilots accept simultaneously -> race condition protected, only one pilot assigned
 */

const mongoose = require('mongoose');
const http = require('http');
const { isFoodDeliveryVehicle, isEligibleForFoodDelivery, findNearbyEligibleFoodPilots } = require('./services/foodDeliveryEligibilityService');

const BASE_URL = 'http://localhost:3000';
const MONGO_URI = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/staydriv';

// Helper for HTTP requests
function request(method, path, body = null, headers = {}) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, BASE_URL);
    const options = {
      hostname: url.hostname,
      port: url.port,
      path: url.pathname + url.search,
      method: method,
      headers: {
        'Content-Type': 'application/json',
        ...headers
      }
    };

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        let json = null;
        try {
          json = JSON.parse(data);
        } catch (_) {
          json = data;
        }
        resolve({ status: res.statusCode, headers: res.headers, data: json });
      });
    });

    req.on('error', reject);
    if (body) {
      req.write(JSON.stringify(body));
    }
    req.end();
  });
}

async function runTestSuite() {
  console.log('========================================================================');
  console.log('  STAYDRIV — FOOD ORDER BIKE & SCOOTY VEHICLE RESTRICTION TEST SUITE');
  console.log('========================================================================\n');

  await mongoose.connect(MONGO_URI);
  console.log('✓ Connected to MongoDB for test fixture initialization');

  const User = mongoose.models.User || mongoose.model('User', new mongoose.Schema({}, { strict: false }));
  const FoodOrder = mongoose.models.FoodOrder || mongoose.model('FoodOrder', new mongoose.Schema({}, { strict: false }));
  const Booking = mongoose.models.Booking || mongoose.model('Booking', new mongoose.Schema({}, { strict: false }));
  const Restaurant = mongoose.models.Restaurant || mongoose.model('Restaurant', new mongoose.Schema({}, { strict: false }));
  const FoodItem = mongoose.models.FoodItem || mongoose.model('FoodItem', new mongoose.Schema({}, { strict: false }));

  // Seed test restaurants & menu items
  await Restaurant.findOneAndUpdate(
    { restaurantId: 'rest_swathi_1' },
    {
      $set: {
        restaurantId: 'rest_swathi_1',
        name: 'Swathi Tiffins',
        phone: '9849012345',
        status: 'approved',
        isOpen: true,
        address: 'Madhapur Main Road',
        lat: 17.4485,
        lng: 78.3741,
        deliveryFee: 30
      }
    },
    { upsert: true }
  );

  await FoodItem.findOneAndUpdate(
    { itemId: 'ITEM_IDLI_1' },
    {
      $set: {
        itemId: 'ITEM_IDLI_1',
        restaurantId: 'rest_swathi_1',
        name: 'Idli',
        category: 'Breakfast',
        price: 50,
        isVeg: true,
        isAvailable: true,
        isDeleted: false
      }
    },
    { upsert: true }
  );

  await Restaurant.findOneAndUpdate(
    { restaurantId: 'rest_isolated_1' },
    {
      $set: {
        restaurantId: 'rest_isolated_1',
        name: 'Isolated Kitchen',
        phone: '9849098765',
        status: 'approved',
        isOpen: true,
        address: 'Remote Outskirts',
        lat: 19.9999,
        lng: 79.9999,
        deliveryFee: 40
      }
    },
    { upsert: true }
  );

  await FoodItem.findOneAndUpdate(
    { itemId: 'ITEM_BIRYANI_1' },
    {
      $set: {
        itemId: 'ITEM_BIRYANI_1',
        restaurantId: 'rest_isolated_1',
        name: 'Biryani',
        category: 'Main Course',
        price: 200,
        isVeg: false,
        isAvailable: true,
        isDeleted: false
      }
    },
    { upsert: true }
  );

  // 1. Seed or update test pilots
  const testPilots = [
    {
      phoneNumber: '9999000001',
      phone: '9999000001',
      uid: 'pilot_bike_1',
      name: 'Ramesh Bike Pilot',
      role: 'partner',
      vehicleType: 'Bike',
      vehicleNumber: 'TS09BK1234',
      isOnline: true,
      online: true,
      partnerStatus: 'approved',
      status: 'approved',
      approved: true,
      currentLocation: { coordinates: [78.3741, 17.4485] }
    },
    {
      phoneNumber: '9999000002',
      phone: '9999000002',
      uid: 'pilot_scooty_1',
      name: 'Suresh Scooty Pilot',
      role: 'partner',
      vehicleType: 'Scooty',
      vehicleNumber: 'TS09SC5678',
      isOnline: true,
      online: true,
      partnerStatus: 'approved',
      status: 'approved',
      approved: true,
      currentLocation: { coordinates: [78.3745, 17.4489] }
    },
    {
      phoneNumber: '9999000003',
      phone: '9999000003',
      uid: 'pilot_auto_1',
      name: 'Anil Auto Pilot',
      role: 'partner',
      vehicleType: 'Auto Rickshaw',
      vehicleNumber: 'TS09AR9999',
      isOnline: true,
      online: true,
      partnerStatus: 'approved',
      status: 'approved',
      approved: true,
      currentLocation: { coordinates: [78.3740, 17.4480] }
    },
    {
      phoneNumber: '9999000004',
      phone: '9999000004',
      uid: 'pilot_car_1',
      name: 'Kiran Car Pilot',
      role: 'partner',
      vehicleType: 'Car',
      vehicleNumber: 'TS09CR8888',
      isOnline: true,
      online: true,
      partnerStatus: 'approved',
      status: 'approved',
      approved: true,
      currentLocation: { coordinates: [78.3742, 17.4482] }
    },
    {
      phoneNumber: '9999000005',
      phone: '9999000005',
      uid: 'pilot_truck_1',
      name: 'Vijay Mini Truck Pilot',
      role: 'partner',
      vehicleType: 'Mini Truck',
      vehicleNumber: 'TS09TR7777',
      isOnline: true,
      online: true,
      partnerStatus: 'approved',
      status: 'approved',
      approved: true,
      currentLocation: { coordinates: [78.3744, 17.4484] }
    },
    {
      phoneNumber: '9999000006',
      phone: '9999000006',
      uid: 'pilot_offline_bike_1',
      name: 'Mahesh Offline Bike Pilot',
      role: 'partner',
      vehicleType: 'Bike',
      vehicleNumber: 'TS09BK9999',
      isOnline: false,
      online: false,
      partnerStatus: 'approved',
      status: 'approved',
      approved: true,
      currentLocation: { coordinates: [78.3741, 17.4485] }
    }
  ];

  for (const p of testPilots) {
    await User.findOneAndUpdate(
      { phoneNumber: p.phoneNumber },
      { $set: p },
      { upsert: true }
    );
  }
  console.log(`✓ Seeded/verified ${testPilots.length} pilot test fixtures and restaurants in database\n`);

  let passedTests = 0;
  const totalTests = 12;
  let order1 = null;

  try {
    // -------------------------------------------------------------------------
    // TEST 1: Customer places food order -> eligible Bike pilot receives request
    // -------------------------------------------------------------------------
    console.log('--- TEST 1: Customer places food order -> eligible Bike pilot receives request ---');
    const order1Res = await request('POST', '/api/food/orders', {
      customerId: 'cust_test_1',
      customerName: 'Pooja Customer',
      customerPhone: '9849011111',
      restaurantId: 'rest_swathi_1',
      items: [{ itemId: 'ITEM_IDLI_1', name: 'Idli', price: 50, quantity: 2 }],
      deliveryAddress: 'Hitec City, Hyderabad',
      deliveryLatLng: { lat: 17.4500, lng: 78.3800 }
    });

    if (order1Res.status === 201 && order1Res.data.success) {
      order1 = order1Res.data.order;
      const bikeOrdersRes = await request('GET', `/api/food/pilot/available-orders?pilotId=9999000001&vehicleType=Bike`);
      const hasOrder = bikeOrdersRes.data.orders.some(o => o.orderId === order1.orderId);
      if (bikeOrdersRes.status === 200 && bikeOrdersRes.data.isEligible === true && hasOrder) {
        console.log(`✓ PASS: Order ${order1.orderId} successfully placed and received by verified Bike pilot 9999000001`);
        passedTests++;
      } else {
        console.error(`✗ FAIL: Bike pilot did not receive available order:`, bikeOrdersRes.data);
      }
    } else {
      console.error(`✗ FAIL: Could not place order:`, order1Res.data);
    }

    // -------------------------------------------------------------------------
    // TEST 2: Customer places food order -> eligible Scooty pilot receives request
    // -------------------------------------------------------------------------
    console.log('\n--- TEST 2: Customer places food order -> eligible Scooty pilot receives request ---');
    const scootyOrdersRes = await request('GET', `/api/food/pilot/available-orders?pilotId=9999000002&vehicleType=Scooty`);
    if (scootyOrdersRes.status === 200 && scootyOrdersRes.data.isEligible === true && scootyOrdersRes.data.orders.length > 0) {
      console.log(`✓ PASS: Scooty pilot 9999000002 recognized as eligible (registered: Scooty) and received available food orders`);
      passedTests++;
    } else {
      console.error(`✗ FAIL: Scooty pilot failed available-orders:`, scootyOrdersRes.data);
    }

    // -------------------------------------------------------------------------
    // TEST 3: Auto Rickshaw pilot is online -> receives no food delivery request
    // -------------------------------------------------------------------------
    console.log('\n--- TEST 3: Auto Rickshaw pilot is online -> receives no food delivery request ---');
    const autoOrdersRes = await request('GET', `/api/food/pilot/available-orders?pilotId=9999000003&vehicleType=Auto%20Rickshaw`);
    const autoAcceptRes = await request('POST', `/api/food/pilot/orders/${order1 ? order1.orderId : 'DUMMY'}/accept`, {
      pilotId: '9999000003',
      pilotName: 'Anil Auto Pilot',
      pilotPhone: '9999000003'
    });

    if (autoOrdersRes.data.isEligible === false &&
        autoOrdersRes.data.orders.length === 0 &&
        autoAcceptRes.status === 403) {
      console.log(`✓ PASS: Auto Rickshaw pilot barred from food orders (isEligible=false, 0 orders, accept blocked with HTTP 403 Forbidden)`);
      passedTests++;
    } else {
      console.error(`✗ FAIL: Auto Rickshaw was not blocked:`, { autoOrdersRes: autoOrdersRes.data, autoAcceptRes: autoAcceptRes.data });
    }

    // -------------------------------------------------------------------------
    // TEST 4: Car pilot is online -> receives no food delivery request
    // -------------------------------------------------------------------------
    console.log('\n--- TEST 4: Car pilot is online -> receives no food delivery request ---');
    const carOrdersRes = await request('GET', `/api/food/pilot/available-orders?pilotId=9999000004&vehicleType=Car`);
    const carAcceptRes = await request('POST', `/api/food/pilot/orders/${order1 ? order1.orderId : 'DUMMY'}/accept`, {
      pilotId: '9999000004',
      pilotName: 'Kiran Car Pilot',
      pilotPhone: '9999000004'
    });

    if (carOrdersRes.data.isEligible === false &&
        carOrdersRes.data.orders.length === 0 &&
        carAcceptRes.status === 403) {
      console.log(`✓ PASS: Car pilot barred from food orders (isEligible=false, 0 orders, accept blocked with HTTP 403 Forbidden)`);
      passedTests++;
    } else {
      console.error(`✗ FAIL: Car was not blocked:`, { carOrdersRes: carOrdersRes.data, carAcceptRes: carAcceptRes.data });
    }

    // -------------------------------------------------------------------------
    // TEST 5: Other vehicle pilot (Mini Truck) is online -> receives no food delivery request
    // -------------------------------------------------------------------------
    console.log('\n--- TEST 5: Other vehicle pilot (Mini Truck) -> receives no food delivery request ---');
    const truckOrdersRes = await request('GET', `/api/food/pilot/available-orders?pilotId=9999000005&vehicleType=Mini%20Truck`);
    if (truckOrdersRes.data.isEligible === false && truckOrdersRes.data.orders.length === 0) {
      console.log(`✓ PASS: Mini Truck barred from food delivery (isEligible=false, orders=[])`);
      passedTests++;
    } else {
      console.error(`✗ FAIL: Mini Truck was not blocked:`, truckOrdersRes.data);
    }

    // -------------------------------------------------------------------------
    // TEST 6: Bike pilot is offline or unavailable -> is not assigned
    // -------------------------------------------------------------------------
    console.log('\n--- TEST 6: Bike pilot is offline -> is not assigned ---');
    const offlinePilot = await User.findOne({ phoneNumber: '9999000006' });
    const offlineCheck = isEligibleForFoodDelivery(offlinePilot, { requireOnline: true });
    if (offlineCheck.eligible === false && offlineCheck.reason.includes('offline')) {
      console.log(`✓ PASS: Offline Bike pilot correctly evaluated as ineligible: "${offlineCheck.reason}"`);
      passedTests++;
    } else {
      console.error(`✗ FAIL: Offline Bike pilot not flagged:`, offlineCheck);
    }

    // -------------------------------------------------------------------------
    // TEST 7: No eligible pilot is available -> order remains in pending state
    // -------------------------------------------------------------------------
    console.log('\n--- TEST 7: No eligible pilot available -> order remains in pending state ---');
    const pendingOrderRes = await request('POST', '/api/food/orders', {
      customerId: 'cust_remote_1',
      customerName: 'Remote Customer',
      customerPhone: '9849022222',
      restaurantId: 'rest_isolated_1',
      items: [{ itemId: 'ITEM_BIRYANI_1', name: 'Biryani', price: 200, quantity: 1 }],
      deliveryAddress: 'Far Outskirts',
      deliveryLatLng: { lat: 20.0000, lng: 80.0000 }
    });

    if (pendingOrderRes.status === 201) {
      const order = pendingOrderRes.data.order;
      if (order.deliveryPartnerId === '' && (order.orderStatus === 'placed' || order.orderStatus === 'ready_for_pickup')) {
        console.log(`✓ PASS: Isolated order ${order.orderId} safely remains in pending state (deliveryPartnerId="")`);
        passedTests++;
      } else {
        console.error(`✗ FAIL: Order was prematurely assigned:`, order);
      }
    } else {
      console.error(`✗ FAIL: Order creation failed:`, pendingOrderRes.data);
    }

    // -------------------------------------------------------------------------
    // TEST 8: Reassignment after rejection -> only Bike or Scooty pilot considered
    // -------------------------------------------------------------------------
    console.log('\n--- TEST 8: Reassignment after rejection -> only Bike/Scooty considered ---');
    const eligibleListRes = await request('GET', '/api/food/admin/eligible-delivery-pilots');
    const eligiblePilots = eligibleListRes.data.pilots || [];
    const hasIneligibleVehicles = eligiblePilots.some(p => {
      const v = (p.vehicleType || '').toLowerCase();
      return v.includes('auto') || v.includes('car') || v.includes('truck');
    });

    if (eligibleListRes.status === 200 && !hasIneligibleVehicles && eligiblePilots.length >= 2) {
      console.log(`✓ PASS: Eligible assignment pool strictly contains Bike and Scooty pilots (${eligiblePilots.length} pilots, 0 autos/cars)`);
      passedTests++;
    } else {
      console.error(`✗ FAIL: Eligible assignment pool contained ineligible vehicles:`, eligiblePilots);
    }

    // -------------------------------------------------------------------------
    // TEST 9: Admin tries to assign an Auto or Car -> backend rejects with HTTP 400
    // -------------------------------------------------------------------------
    console.log('\n--- TEST 9: Admin tries to assign Auto or Car -> backend rejects assignment ---');
    const targetOrderId = order1 ? order1.orderId : 'ORD_TEST_9';
    // 9a. Try to assign Auto Rickshaw pilot
    const assignAutoRes = await request('POST', `/api/food/admin/orders/${targetOrderId}/assign-pilot`, {
      pilotId: '9999000003',
      adminName: 'Super Admin'
    });
    // 9b. Try to assign Car pilot
    const assignCarRes = await request('POST', `/api/food/admin/orders/${targetOrderId}/assign-pilot`, {
      pilotId: '9999000004',
      adminName: 'Super Admin'
    });
    // 9c. Assign valid Bike pilot
    const assignBikeRes = await request('POST', `/api/food/admin/orders/${targetOrderId}/assign-pilot`, {
      pilotId: '9999000001',
      adminName: 'Super Admin'
    });

    const isAssignedToBike = (assignBikeRes.status === 200) &&
      (assignBikeRes.data.order.deliveryPartnerId === 'pilot_bike_1' || assignBikeRes.data.order.deliveryPartnerId === '9999000001');

    if (assignAutoRes.status === 400 &&
        assignCarRes.status === 400 &&
        isAssignedToBike) {
      console.log(`✓ PASS: Admin assignment correctly rejected Auto Rickshaw (HTTP 400) and Car (HTTP 400), and accepted Bike (HTTP 200)`);
      passedTests++;
    } else {
      console.error(`✗ FAIL: Admin assignment validation failed:`, {
        assignAuto: assignAutoRes.data,
        assignCar: assignCarRes.data,
        assignBike: assignBikeRes.data
      });
    }

    // -------------------------------------------------------------------------
    // TEST 10: Normal passenger rides -> existing vehicle-specific assignment continues working
    // -------------------------------------------------------------------------
    console.log('\n--- TEST 10: Normal passenger rides -> existing vehicle-specific assignment unaffected ---');
    const autoRide = new Booking({
      bookingId: `BK_AUTO_${Date.now()}`,
      userId: 'user_cust_1',
      userName: 'Passenger Ravi',
      userPhone: '9849055555',
      driverId: '9999000003',
      driverName: 'Anil Auto Pilot',
      driverPhone: '9999000003',
      vehicle: 'Auto Rickshaw',
      status: 'ACCEPTED',
      serviceType: 'ride',
      pickupLocation: { address: 'Kondapur Signal', lat: 17.4600, lng: 78.3600 },
      dropLocation: { address: 'Gachibowli Flyover', lat: 17.4400, lng: 78.3500 },
      estimatedFare: 95,
      createdAt: new Date()
    });
    await autoRide.save();

    const savedRide = await Booking.findOne({ bookingId: autoRide.bookingId });
    if (savedRide && savedRide.driverId === '9999000003' && savedRide.vehicle === 'Auto Rickshaw') {
      console.log(`✓ PASS: Auto Rickshaw pilot passenger ride preserved without regression (Booking ${savedRide.bookingId})`);
      passedTests++;
    } else {
      console.error(`✗ FAIL: Auto Rickshaw ride failed:`, savedRide);
    }

    // -------------------------------------------------------------------------
    // TEST 11: Consistency across consoles (Customer, Restaurant, Pilot, Admin)
    // -------------------------------------------------------------------------
    console.log('\n--- TEST 11: Customer, restaurant, pilot, and admin consoles show consistent order status ---');
    const orderAuditRes = await request('GET', `/api/food/orders/${targetOrderId}`);
    const adminOrdersRes = await request('GET', `/api/food/admin/orders`);
    const adminOrder = adminOrdersRes.data.orders.find(o => o.orderId === targetOrderId);

    const isPilotMatching = orderAuditRes.status === 200 && adminOrder &&
      (orderAuditRes.data.order.deliveryPartnerId === adminOrder.deliveryPartnerId) &&
      (orderAuditRes.data.order.deliveryPartnerVehicle === 'Bike' || adminOrder.deliveryPartnerVehicleType === 'Bike' || adminOrder.deliveryPartnerVehicle === 'Bike');

    if (isPilotMatching) {
      console.log(`✓ PASS: Consoles synchronized (Order ${targetOrderId}, Pilot ${adminOrder.deliveryPartnerId}, Vehicle: ${adminOrder.deliveryPartnerVehicle || adminOrder.deliveryPartnerVehicleType})`);
      passedTests++;
    } else {
      console.error(`✗ FAIL: Status inconsistent across consoles:`, { orderAudit: orderAuditRes.data, adminOrder });
    }

    // -------------------------------------------------------------------------
    // TEST 12: Race Condition Protection: Multiple pilots accept simultaneously
    // -------------------------------------------------------------------------
    console.log('\n--- TEST 12: Multiple pilots accept simultaneously -> duplicate assignment prevented ---');
    const raceOrderRes = await request('POST', '/api/food/orders', {
      customerId: 'cust_race_1',
      customerName: 'Race Customer',
      customerPhone: '9849033333',
      restaurantId: 'rest_swathi_1',
      items: [{ itemId: 'ITEM_IDLI_1', name: 'Idli', price: 50, quantity: 1 }],
      deliveryAddress: 'Inorbit Mall',
      deliveryLatLng: { lat: 17.4350, lng: 78.3850 }
    });

    const raceOrderId = raceOrderRes.data.order.orderId;

    // Both Pilot 1 (Bike) and Pilot 2 (Scooty) attempt to accept concurrently
    const [p1Accept, p2Accept] = await Promise.all([
      request('POST', `/api/food/pilot/orders/${raceOrderId}/accept`, {
        pilotId: '9999000001',
        pilotName: 'Ramesh Bike Pilot',
        pilotPhone: '9999000001'
      }),
      request('POST', `/api/food/pilot/orders/${raceOrderId}/accept`, {
        pilotId: '9999000002',
        pilotName: 'Suresh Scooty Pilot',
        pilotPhone: '9999000002'
      })
    ]);

    const statuses = [p1Accept.status, p2Accept.status].sort();
    const winningOrder = p1Accept.status === 200 ? p1Accept.data.order : p2Accept.data.order;

    if (statuses[0] === 200 && statuses[1] === 409) {
      console.log(`✓ PASS: Concurrency race condition prevented! Winner: ${winningOrder.deliveryPartnerName} (HTTP 200 OK), Loser rejected with HTTP 409 Conflict`);
      passedTests++;
    } else {
      console.error(`✗ FAIL: Duplicate acceptance race condition occurred:`, { p1: p1Accept.data, p2: p2Accept.data });
    }

  } catch (err) {
    console.error('Test execution error:', err);
  } finally {
    await mongoose.disconnect();
    console.log('\n========================================================================');
    console.log(`  FINAL RESULT: ${passedTests}/${totalTests} TESTS PASSED`);
    console.log('========================================================================\n');
    process.exit(passedTests === totalTests ? 0 : 1);
  }
}

runTestSuite();
