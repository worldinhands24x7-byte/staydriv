require('dotenv').config();
const http = require('http');
const crypto = require('crypto');

const BASE_URL = 'http://localhost:3000';
const TEST_CUSTOMER_ID = 'TEST_CUST_PLATINUM_' + Date.now();
const TEST_PHONE = '98765' + Math.floor(10000 + Math.random() * 90000);
const TEST_NAME = 'Platinum VIP Tester';

function makeRequest(path, method = 'GET', data = null) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, BASE_URL);
    const options = {
      hostname: url.hostname,
      port: url.port || 3000,
      path: url.pathname + url.search,
      method: method,
      headers: {
        'Content-Type': 'application/json',
      },
    };

    const req = http.request(options, (res) => {
      let body = '';
      res.on('data', (chunk) => body += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(body);
          resolve({ status: res.statusCode, data: parsed });
        } catch (e) {
          resolve({ status: res.statusCode, raw: body });
        }
      });
    });

    req.on('error', (err) => reject(err));
    if (data) req.write(JSON.stringify(data));
    req.end();
  });
}

async function runTestSuite() {
  console.log('====================================================');
  console.log('STAYDRIV PLATINUM FOOD MEMBERSHIP E2E VERIFICATION');
  console.log('====================================================\n');

  let passed = 0;
  let failed = 0;

  function assert(condition, message) {
    if (condition) {
      console.log(`[PASS] ${message}`);
      passed++;
    } else {
      console.error(`[FAIL] ${message}`);
      failed++;
    }
  }

  try {
    // 1. Fetch Membership Plans
    console.log('--- TEST 1: Fetch Plans (/api/food/membership/plans) ---');
    const plansRes = await makeRequest('/api/food/membership/plans');
    assert(plansRes.status === 200, 'Fetch plans responded with HTTP 200');
    assert(plansRes.data.success === true, 'Response indicates success = true');
    assert(Array.isArray(plansRes.data.plans), 'Plans is an array');

    const platinumPlan = plansRes.data.plans.find(p => p.planType === 'platinum' || p.planId === 'plan_platinum_3m');
    assert(!!platinumPlan, 'Platinum food membership plan is published');
    if (platinumPlan) {
      assert(platinumPlan.price === 1, `Plan selling price is ₹1 (Actual: ₹${platinumPlan.price})`);
      assert(platinumPlan.validityMonths === 3, `Validity is 3 months (Actual: ${platinumPlan.validityMonths})`);
      assert(platinumPlan.validityDays === 90, `Validity is 90 days (Actual: ${platinumPlan.validityDays})`);
      assert(platinumPlan.minOrderAmount === 99, `Min order amount is ₹99 (Actual: ₹${platinumPlan.minOrderAmount})`);
      assert(platinumPlan.deliveryRadiusKm === 7, `Delivery radius is 7 km (Actual: ${platinumPlan.deliveryRadiusKm} km)`);
      assert(platinumPlan.maxDiscountPercent === 30, `Max extra discount is 30% (Actual: ${platinumPlan.maxDiscountPercent}%)`);
    }

    // 2. Fetch Participating Restaurants ("On Delivery" section)
    console.log('\n--- TEST 2: Fetch Participating Restaurants (/api/food/membership/participating-restaurants) ---');
    const restRes = await makeRequest('/api/food/membership/participating-restaurants');
    assert(restRes.status === 200, 'Fetch participating restaurants responded with HTTP 200');
    assert(restRes.data.success === true, 'Response indicates success = true');
    assert(Array.isArray(restRes.data.restaurants), 'Restaurants is an array');
    assert(restRes.data.restaurants.length >= 4, `At least 4 partner restaurants enrolled (Actual: ${restRes.data.restaurants.length})`);

    const restaurantNames = restRes.data.restaurants.map(r => r.name);
    assert(restaurantNames.some(n => n.includes('Punjabi Affair')), 'Includes reference restaurant "Punjabi Affair"');
    assert(restaurantNames.some(n => n.includes('Bakinnbros')), 'Includes reference restaurant "Bakinnbros"');
    assert(restaurantNames.some(n => n.includes('KS Bakers')), 'Includes reference restaurant "KS Bakers"');
    assert(restaurantNames.some(n => n.includes('Peacock Restro')), 'Includes reference restaurant "Peacock Restro"');

    // 3. Create Razorpay Payment Order
    console.log('\n--- TEST 3: Create Razorpay Order (/api/food/membership/order/create) ---');
    const createRes = await makeRequest('/api/food/membership/order/create', 'POST', {
      customerId: TEST_CUSTOMER_ID,
      customerPhone: TEST_PHONE,
      customerName: TEST_NAME,
      planId: 'plan_platinum_3m',
    });

    assert(createRes.status === 200, 'Create order responded with HTTP 200');
    assert(createRes.data.success === true, 'Create order success = true');
    assert(!!createRes.data.order && !!createRes.data.order.orderId, `Received Razorpay Order ID (${createRes.data.order?.orderId})`);
    assert(createRes.data.order.amount === 100, `Order amount in paise is 100 (₹1) (Actual: ${createRes.data.order?.amount})`);
    assert(createRes.data.order.currency === 'INR', `Currency is INR (Actual: ${createRes.data.order?.currency})`);
    assert(createRes.data.order.keyId !== undefined, 'Razorpay Key ID provided');

    const razorpayOrderId = createRes.data.order.orderId;
    const razorpayPaymentId = 'pay_sim_' + Math.floor(100000 + Math.random() * 900000);

    // Compute real HMAC-SHA256 signature
    const secret = process.env.RAZORPAY_KEY_SECRET || 'rzp_test_staydriv_secret';
    const expectedSignature = crypto
      .createHmac('sha256', secret)
      .update(`${razorpayOrderId}|${razorpayPaymentId}`)
      .digest('hex');

    // 4. Verify Razorpay Payment and Activate Membership
    console.log('\n--- TEST 4: Verify Payment & Activate Platinum Membership (/api/food/membership/order/verify) ---');
    const verifyRes = await makeRequest('/api/food/membership/order/verify', 'POST', {
      customerId: TEST_CUSTOMER_ID,
      customerPhone: TEST_PHONE,
      customerName: TEST_NAME,
      planId: 'plan_platinum_3m',
      gatewayOrderId: razorpayOrderId,
      gatewayPaymentId: razorpayPaymentId,
      gatewaySignature: expectedSignature,
      paymentMethod: 'razorpay',
    });

    assert(verifyRes.status === 200, 'Verify payment responded with HTTP 200');
    assert(verifyRes.data.success === true, 'Activation success = true');
    assert(!!verifyRes.data.membership, 'Membership object returned');
    assert(verifyRes.data.membership.status === 'active', 'Membership status is "active"');
    assert(verifyRes.data.membership.planType === 'platinum', 'Membership planType is "platinum"');
    assert(verifyRes.data.membership.membershipId.startsWith('SD-PLATINUM-'), `Membership ID has prefix SD-PLATINUM- (${verifyRes.data.membership.membershipId})`);

    // 5. Test Idempotency (prevent duplicate charges / double activations)
    console.log('\n--- TEST 5: Verify Idempotency on Repeated Payment Callback ---');
    const duplicateRes = await makeRequest('/api/food/membership/order/verify', 'POST', {
      customerId: TEST_CUSTOMER_ID,
      customerPhone: TEST_PHONE,
      customerName: TEST_NAME,
      planId: 'plan_platinum_3m',
      gatewayOrderId: razorpayOrderId,
      gatewayPaymentId: razorpayPaymentId,
      gatewaySignature: expectedSignature,
      paymentMethod: 'razorpay',
    });

    assert(duplicateRes.status === 200, 'Duplicate verify handled gracefully with HTTP 200');
    assert(duplicateRes.data.success === true, 'Duplicate verify returns success (idempotent)');
    assert(duplicateRes.data.membership.membershipId === verifyRes.data.membership.membershipId, 'Returns existing membership record without creating duplicate');

    // 6. Test Discount Calculation: Food Order within 7 km and >= ₹99
    console.log('\n--- TEST 6: Authoritative Checkout Discount Calculation (Eligible Food Order) ---');
    const eligibleCalcRes = await makeRequest('/api/food/membership/calculate-discount', 'POST', {
      customerId: TEST_CUSTOMER_ID,
      customerPhone: TEST_PHONE,
      orderType: 'food',
      isFoodOrder: true,
      restaurantId: 'rest_punjabi_affair',
      foodSubtotal: 250,
      deliveryDistanceKm: 3.5,
      deliveryFee: 40,
    });

    assert(eligibleCalcRes.status === 200, 'Calculate discount responded with HTTP 200');
    assert(eligibleCalcRes.data.hasActiveMembership === true, 'Recognizes active Platinum food membership');
    assert(eligibleCalcRes.data.freeDeliveryApplied === true, 'Free delivery applied for order >= ₹99 within 7 km');
    assert(eligibleCalcRes.data.finalDeliveryFee === 0, `Final delivery fee is ₹0 (Actual: ₹${eligibleCalcRes.data.finalDeliveryFee})`);
    assert(eligibleCalcRes.data.membershipFoodDiscount > 0, `Partner restaurant extra discount applied (Saved: ₹${eligibleCalcRes.data.membershipFoodDiscount})`);

    // 7. Test Discount Calculation: Order Beyond 7 km (Surge/Distance restriction)
    console.log('\n--- TEST 7: Delivery Radius Limit Enforced (> 7 km) ---');
    const farCalcRes = await makeRequest('/api/food/membership/calculate-discount', 'POST', {
      customerId: TEST_CUSTOMER_ID,
      customerPhone: TEST_PHONE,
      orderType: 'food',
      isFoodOrder: true,
      restaurantId: 'rest_punjabi_affair',
      foodSubtotal: 250,
      deliveryDistanceKm: 9.5, // Exceeds 7 km
      deliveryFee: 60,
    });

    assert(farCalcRes.status === 200, 'Calculate discount responded with HTTP 200');
    assert(farCalcRes.data.freeDeliveryApplied === false, 'Free delivery NOT applied when distance > 7 km');
    assert(farCalcRes.data.finalDeliveryFee === 60, `Standard delivery fee charged (₹60)`);

    // 8. Test Isolation: Ride Booking must NEVER receive membership benefits
    console.log('\n--- TEST 8: Strict Non-Food / Ride Order Isolation Enforced ---');
    const rideCalcRes = await makeRequest('/api/food/membership/calculate-discount', 'POST', {
      customerId: TEST_CUSTOMER_ID,
      customerPhone: TEST_PHONE,
      orderType: 'ride', // Ride booking
      isFoodOrder: false,
      rideFare: 150,
      deliveryFee: 0,
    });

    assert(
      rideCalcRes.status === 400 || (rideCalcRes.status === 200 && (rideCalcRes.data.totalMembershipDiscount === 0 || rideCalcRes.data.hasMembership === false)),
      'Ride order strictly rejected or granted zero membership discount (HTTP ' + rideCalcRes.status + ')'
    );
    assert(
      rideCalcRes.status === 400 || rideCalcRes.data.freeDeliveryApplied === false,
      'No free delivery applied for rides'
    );

    console.log('\n====================================================');
    console.log(`TEST SUMMARY: ${passed} PASSED, ${failed} FAILED`);
    console.log('====================================================');

    process.exit(failed > 0 ? 1 : 0);
  } catch (err) {
    console.error('Test execution failed with error:', err);
    process.exit(1);
  }
}

runTestSuite();
