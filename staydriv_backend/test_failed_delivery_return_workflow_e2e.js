const mongoose = require('mongoose');
const express = require('express');
const http = require('http');

// Import models
const Restaurant = require('./models/Restaurant');
const FoodItem = require('./models/FoodItem');
const FoodOrder = require('./models/FoodOrder');
const PilotWallet = require('./models/PilotWallet');
const FinancialLedger = require('./models/FinancialLedger');
const FoodConfig = require('./models/FoodConfig');

// User model definition
const User = mongoose.models.User || mongoose.model('User', new mongoose.Schema({
  uid: { type: String, unique: true },
  phone: String,
  phoneNumber: String,
  name: String,
  role: String,
  status: String,
  approved: Boolean,
  isApproved: Boolean,
  vehicleType: String,
  vehicleNumber: String,
  vehiclePlate: String,
  salary: Number,
  walletBalance: Number,
  totalLifetimeEarnings: Number,
  bankAccount: Object
}, { strict: false }));

// Setup mock app
const app = express();
app.use(express.json());

// Attach mock io
const mockIo = {
  to: () => ({ emit: () => {} }),
  emit: () => {}
};
app.set('io', mockIo);

const foodRoutes = require('./routes/foodRoutes');
app.use('/api/food', foodRoutes);

async function runE2ETests() {
  console.log('========================================================================');
  console.log('🧪 STAYDRIV E2E VERIFICATION: FAILED DELIVERY & RETURN TO RESTAURANT');
  console.log('========================================================================');

  const mongoUri = process.env.MONGODB_URI || 'mongodb://localhost:27017/staydriv';
  await mongoose.connect(mongoUri);
  console.log(' Connected to MongoDB:', mongoUri);

  const server = http.createServer(app);
  await new Promise(resolve => server.listen(0, resolve));
  const port = server.address().port;
  const baseUrl = `http://localhost:${port}`;
  console.log(` Test Server running on ${baseUrl}`);

  let passed = 0;
  let total = 0;

  function assert(condition, testName) {
    total++;
    if (condition) {
      console.log(`  ✅ [PASS] ${testName}`);
      passed++;
    } else {
      console.error(`  ❌ [FAIL] ${testName}`);
      process.exitCode = 1;
    }
  }

  async function api(path, options = {}) {
    const res = await fetch(`${baseUrl}${path}`, {
      ...options,
      headers: {
        'Content-Type': 'application/json',
        ...(options.headers || {})
      },
      body: options.body ? JSON.stringify(options.body) : undefined
    });
    const text = await res.text();
    let body = {};
    try { body = JSON.parse(text); } catch (e) { body = text; }
    return { status: res.status, body };
  }

  try {
    // Clean up test data
    const testPilotPhone = '9490440281';
    const testPilotUid = 'pilot_9490440281';
    const testRestaurantId = 'REST_TEST_RETURN_KITCHEN';
    const testCustomerId = 'CUST_TEST_RETURN_CUSTOMER';
    const testCustomerPhone = '9849012345';
    const testOrderId = `FD_TEST_${Date.now()}`;

    await User.deleteMany({ phone: { $in: [testPilotPhone, '9999900000', testCustomerPhone] } });
    await Restaurant.deleteOne({ restaurantId: testRestaurantId });
    await FoodItem.deleteMany({ restaurantId: testRestaurantId });
    await FoodOrder.deleteMany({ orderId: { $regex: '^FD_TEST_' } });
    await PilotWallet.deleteMany({ uid: { $in: [testPilotUid, testPilotPhone, '9999900000'] } });
    await FinancialLedger.deleteMany({ sourceBookingId: testOrderId });

    // Setup Pilot
    await User.create({
      uid: testPilotUid,
      name: 'StayDriv Verified Pilot',
      phone: testPilotPhone,
      phoneNumber: testPilotPhone,
      role: 'partner',
      status: 'approved',
      approved: true,
      vehicleType: 'Bike',
      walletBalance: 1000,
      totalLifetimeEarnings: 1000,
      salary: 1000
    });

    // Setup Rogue/Unauthorized Pilot
    await User.create({
      uid: 'pilot_9999900000',
      name: 'Unassigned Rogue Pilot',
      phone: '9999900000',
      phoneNumber: '9999900000',
      role: 'partner',
      status: 'approved',
      approved: true,
      vehicleType: 'Bike'
    });

    // Setup Restaurant
    await Restaurant.create({
      restaurantId: testRestaurantId,
      name: 'Spice Valley Restro',
      phone: '8121440281',
      address: 'Plot 10, HiTech City, Hyderabad',
      lat: 17.4485,
      lng: 78.3741,
      status: 'approved',
      isOpen: true,
      categories: ['Biryani', 'Starters']
    });

    // Setup Food Items
    await FoodItem.create({
      itemId: 'ITEM_TEST_BIRYANI',
      restaurantId: testRestaurantId,
      name: 'Hyderabadi Chicken Biryani',
      category: 'Biryani',
      price: 250,
      isVeg: false,
      isDeleted: false
    });

    // TEST 1: Genuine Restaurants Check (no fake/mock fallback)
    console.log('\n--- 1. GENUINE RESTAURANTS API CHECK ---');
    const restRes = await api('/api/food/restaurants');
    assert(restRes.status === 200 && restRes.body.success === true, 'GET /restaurants returns 200 OK');
    const dummyNames = ['Paradise Biryani', 'Chutneys Flavours', 'Bawarchi Grand', 'Pista House & Bakery', 'Pizza Hub Italian Kitchen'];
    const hasDummy = (restRes.body.restaurants || []).some(r => dummyNames.includes(r.name));
    assert(!hasDummy, 'No hardcoded dummy/mock restaurants returned from restaurants API');

    // TEST 2: Order Placement - 'placed' status not shown to pilots
    console.log('\n--- 2. REAL ORDER PLACEMENT & STATUS ISOLATION ---');
    const order = await FoodOrder.create({
      orderId: testOrderId,
      customerId: testCustomerId,
      customerName: 'Test Customer',
      customerPhone: testCustomerPhone,
      deliveryAddress: 'Flat 302, Gachibowli, Hyderabad',
      deliveryLatLng: { lat: 17.4400, lng: 78.3800 },
      restaurantId: testRestaurantId,
      restaurantName: 'Spice Valley Restro',
      restaurantPhone: '8121440281',
      restaurantAddress: 'Plot 10, HiTech City, Hyderabad',
      restaurantLatLng: { lat: 17.4485, lng: 78.3741 },
      items: [{
        itemId: 'ITEM_TEST_BIRYANI',
        name: 'Hyderabadi Chicken Biryani',
        price: 250,
        quantity: 1
      }],
      subtotal: 250,
      packagingFee: 10,
      deliveryFee: 50,
      originalDeliveryFee: 50,
      customerDeliveryFee: 50,
      pilotEarnings: 50,
      platformFee: 9,
      taxes: 12.5,
      totalAmount: 331.5,
      finalPayable: 331.5,
      paymentMethod: 'cod',
      paymentStatus: 'pending',
      orderStatus: 'placed',
      deliveryOtp: '4567',
      customerOtp: '4567',
      restaurantOtp: '8912'
    });

    const availWhilePlaced = await api(`/api/food/pilot/available-orders?pilotId=${testPilotPhone}&vehicleType=Bike`);
    const containsPlaced = (availWhilePlaced.body.orders || []).some(o => o.orderId === testOrderId);
    assert(!containsPlaced, 'Unaccepted "placed" order is NOT visible to pilots');

    // TEST 3: Restaurant Accepts Order -> Available to Pilot
    console.log('\n--- 3. RESTAURANT ACCEPTANCE ---');
    order.orderStatus = 'accepted';
    await order.save();

    const availAfterAccept = await api(`/api/food/pilot/available-orders?pilotId=${testPilotPhone}&vehicleType=Bike`);
    const containsAccepted = (availAfterAccept.body.orders || []).some(o => o.orderId === testOrderId);
    assert(containsAccepted, 'Accepted order is now visible to eligible 2-wheeler pilot');

    // TEST 4: Pilot Accepts Order -> Stored with pilot.uid
    console.log('\n--- 4. PILOT ACCEPTS ORDER ---');
    const acceptRes = await api(`/api/food/pilot/orders/${testOrderId}/accept`, {
      method: 'POST',
      body: {
        pilotId: testPilotPhone,
        pilotName: 'StayDriv Verified Pilot',
        pilotPhone: testPilotPhone,
        vehicleType: 'Bike'
      }
    });
    assert(acceptRes.status === 200 && acceptRes.body.success === true, 'Pilot accepts order successfully');

    const acceptedOrder = await FoodOrder.findOne({ orderId: testOrderId });
    assert(acceptedOrder.deliveryPartnerId === testPilotUid, 'deliveryPartnerId stored as pilot UID (' + testPilotUid + ')');
    assert(acceptedOrder.deliveryPartnerPhone === testPilotPhone, 'deliveryPartnerPhone stored as phone (' + testPilotPhone + ')');

    // TEST 5: Food Handover / Pickup
    console.log('\n--- 5. FOOD PICKUP HANDOVER ---');
    const pickupRes = await api(`/api/food/pilot/orders/${testOrderId}/pickup`, {
      method: 'POST',
      body: { otp: '8912' }
    });
    assert(pickupRes.status === 200 && pickupRes.body.order.orderStatus === 'out_for_delivery', 'Food picked up and out for delivery');

    // TEST 6: Unauthorized Pilot Blocked from Reporting Failed Delivery
    console.log('\n--- 6. UNAUTHORIZED PILOT REJECTION ---');
    const rogueFailRes = await api(`/api/food/pilot/orders/${testOrderId}/report-failed-delivery`, {
      method: 'POST',
      body: {
        pilotId: '9999900000',
        pilotPhone: '9999900000',
        reason: 'Customer is not answering calls'
      }
    });
    assert(rogueFailRes.status === 403, 'Unauthorized pilot correctly blocked with 403 Forbidden');
    assert(rogueFailRes.body.message.includes('Unauthorized'), 'Returned clean unauthorized message');

    // TEST 7: Assigned Pilot Reports Failed Delivery ("Confirm & Return to Restaurant")
    console.log('\n--- 7. ASSIGNED PILOT CONFIRMS RETURN TO RESTAURANT ---');
    // Pilot App passes pilotId: widget.phoneNumber ("9490440281"), NOT "pilot_9490440281"!
    const reportFailRes = await api(`/api/food/pilot/orders/${testOrderId}/report-failed-delivery`, {
      method: 'POST',
      body: {
        pilotId: testPilotPhone,
        pilotPhone: testPilotPhone,
        reason: 'Customer is not answering calls',
        notes: 'Rang doorbell 3 times, phone switched off'
      }
    });
    assert(reportFailRes.status === 200 && reportFailRes.body.success === true, 'Assigned pilot successfully reported failed delivery via phone credentials');
    
    const failedOrder = await FoodOrder.findOne({ orderId: testOrderId });
    assert(failedOrder.orderStatus === 'delivery_failed_reported', 'orderStatus updated to "delivery_failed_reported"');
    assert(failedOrder.returnReason === 'Customer is not answering calls', 'returnReason properly recorded');
    assert(failedOrder.returnOtp && failedOrder.returnOtp.length === 4, '4-digit returnOtp generated: ' + failedOrder.returnOtp);
    assert(failedOrder.returnDeadline > new Date(), '45-minute returnDeadline established: ' + failedOrder.returnDeadline.toISOString());
    assert(failedOrder.walletDebitStatus === 'none', 'walletDebitStatus is "none" (pilot not penalized or debited)');

    // TEST 8: Pilot Arrival at Restaurant
    console.log('\n--- 8. PILOT ARRIVED AT RESTAURANT FOR RETURN ---');
    const arrivedRes = await api(`/api/food/pilot/orders/${testOrderId}/return-arrived`, {
      method: 'POST',
      body: {
        pilotId: testPilotPhone,
        pilotPhone: testPilotPhone
      }
    });
    assert(arrivedRes.status === 200 && arrivedRes.body.success === true, 'Pilot arrival recorded at restaurant');

    // TEST 9: Restaurant Physical Receipt & OTP Reveal
    console.log('\n--- 9. RESTAURANT CONFIRMS HANDOVER & REVEALS OTP ---');
    const restReceiveRes = await api(`/api/food/restaurant/orders/${testOrderId}/receive-return`, {
      method: 'POST',
      body: {
        restaurantId: testRestaurantId,
        staffName: 'Chef Ramesh'
      }
    });
    assert(restReceiveRes.status === 200 && restReceiveRes.body.success === true, 'Restaurant confirms receipt of returned food');
    assert(restReceiveRes.body.returnOtp === failedOrder.returnOtp, 'Handover reveals matching 4-digit Return OTP to kitchen');

    // TEST 10: Pilot Enters Return OTP -> Order Closed & Pilot Protected Earning Credited
    console.log('\n--- 10. RETURN OTP VERIFICATION & PILOT WALLET SETTLEMENT ---');
    const verifyOtpRes = await api(`/api/food/pilot/orders/${testOrderId}/verify-return-otp`, {
      method: 'POST',
      body: {
        pilotId: testPilotPhone,
        pilotPhone: testPilotPhone,
        otp: failedOrder.returnOtp
      }
    });
    assert(verifyOtpRes.status === 200 && verifyOtpRes.body.success === true, 'Return OTP successfully verified');

    const closedOrder = await FoodOrder.findOne({ orderId: testOrderId });
    assert(closedOrder.orderStatus === 'returned_to_restaurant', 'Order status finalized to "returned_to_restaurant"');
    assert(closedOrder.returnOtpVerified === true, 'returnOtpVerified marked true');
    assert(closedOrder.returnedAt != null, 'returnedAt timestamp recorded');

    // Check Pilot Wallet credit
    const pilotWallet = await PilotWallet.findOne({ uid: testPilotUid });
    assert(pilotWallet != null, 'Pilot wallet found');
    assert(pilotWallet.pendingSettlement >= 50, 'Pilot received full ₹50 delivery fare pending settlement');

    // Check Financial Ledger
    const ledger = await FinancialLedger.findOne({ sourceBookingId: testOrderId });
    assert(ledger != null, 'Double-entry Financial Ledger created for food delivery');
    assert(ledger.amount === 50, 'Financial ledger credited ₹50 to pilot pending settlement');

    // TEST 11: Idempotency Check on Repeat OTP Verification
    console.log('\n--- 11. IDEMPOTENCY & FINANCIAL SAFETY ---');
    const repeatVerify = await api(`/api/food/pilot/orders/${testOrderId}/verify-return-otp`, {
      method: 'POST',
      body: {
        pilotId: testPilotPhone,
        pilotPhone: testPilotPhone,
        otp: failedOrder.returnOtp
      }
    });
    assert(repeatVerify.status === 200 && repeatVerify.body.success === true, 'Repeat verify returns idempotent success');
    const ledgerCount = await FinancialLedger.countDocuments({ sourceBookingId: testOrderId });
    assert(ledgerCount === 1, 'Exactly 1 Financial Ledger record exists (0 duplicate credits)');

    console.log('\n========================================================================');
    console.log(`🎉 SUMMARY: ${passed}/${total} TESTS PASSED`);
    console.log('========================================================================\n');

    server.close();
    process.exit(passed === total ? 0 : 1);
  } catch (err) {
    console.error('Test Execution Error:', err);
    server.close();
    process.exit(1);
  }
}

runE2ETests();
