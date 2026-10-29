const http = require('http');

function request(options, data) {
  return new Promise((resolve, reject) => {
    const req = http.request(options, (res) => {
      let body = '';
      res.on('data', (chunk) => body += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(body);
          resolve({ status: res.statusCode, body: parsed });
        } catch (e) {
          resolve({ status: res.statusCode, raw: body });
        }
      });
    });
    req.on('error', reject);
    if (data) {
      req.write(typeof data === 'string' ? data : JSON.stringify(data));
    }
    req.end();
  });
}

async function runTests() {
  console.log('--- STARTING FOOD CHECKOUT & BILL SUMMARY VALIDATION ---');
  let passed = 0;
  let failed = 0;

  function assert(desc, condition, details) {
    if (condition) {
      console.log(`[PASS] ${desc}`);
      passed++;
    } else {
      console.error(`[FAIL] ${desc}`, details || '');
      failed++;
    }
  }

  try {
    // 1. Fetch available coupons
    const couponsRes = await request({
      hostname: 'localhost',
      port: 3000,
      path: '/api/food/coupons',
      method: 'GET',
    });
    assert('GET /api/food/coupons returns 200 and coupons list', 
      couponsRes.status === 200 && Array.isArray(couponsRes.body.coupons) && couponsRes.body.coupons.length > 0,
      couponsRes.body
    );

    // 2. Validate Coupon TAKEOFF50ON99
    const valCouponRes = await request({
      hostname: 'localhost',
      port: 3000,
      path: '/api/food/coupons/validate',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
    }, {
      couponCode: 'TAKEOFF50ON99',
      orderAmount: 150,
      customerId: 'CUST_TEST_01'
    });
    assert('POST /api/food/coupons/validate accepts valid coupon TAKEOFF50ON99',
      valCouponRes.status === 200 && valCouponRes.body.success === true && valCouponRes.body.coupon && valCouponRes.body.coupon.discount > 0,
      valCouponRes.body
    );

    // 3. Validate Invalid Coupon
    const invalidCouponRes = await request({
      hostname: 'localhost',
      port: 3000,
      path: '/api/food/coupons/validate',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
    }, {
      couponCode: 'NONEXISTENT999',
      orderAmount: 200,
      customerId: 'CUST_TEST_01'
    });
    assert('POST /api/food/coupons/validate rejects invalid coupon',
      invalidCouponRes.status === 404 && invalidCouponRes.body.success === false,
      invalidCouponRes.body
    );

    // 4. Calculate Bill with Online Payment (No Cash Rounding)
    const billOnlineRes = await request({
      hostname: 'localhost',
      port: 3000,
      path: '/api/food/calculate-bill',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
    }, {
      restaurantId: 'REST_PARADISE_01',
      items: [{ itemId: 'ITEM_PARADISE_01', quantity: 1 }],
      paymentMethod: 'online',
      couponCode: 'TAKEOFF50ON99'
    });
    assert('POST /api/food/calculate-bill (online) has packaging, platform, taxes, coupon and 0 cash round off',
      billOnlineRes.status === 200 && 
      billOnlineRes.body.success === true &&
      billOnlineRes.body.bill.packagingFee > 0 &&
      billOnlineRes.body.bill.platformFee > 0 &&
      billOnlineRes.body.bill.couponDiscount > 0 &&
      billOnlineRes.body.bill.cashRoundOff === 0,
      billOnlineRes.body
    );

    // 5. Calculate Bill with COD Payment (Cash Rounding to nearest integer)
    const billCodRes = await request({
      hostname: 'localhost',
      port: 3000,
      path: '/api/food/calculate-bill',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
    }, {
      restaurantId: 'REST_PARADISE_01',
      items: [{ itemId: 'ITEM_PARADISE_01', quantity: 1 }],
      paymentMethod: 'cod',
      couponCode: 'NEWMEAL'
    });
    assert('POST /api/food/calculate-bill (COD) rounds final payable to exact whole integer',
      billCodRes.status === 200 && 
      billCodRes.body.success === true &&
      Number.isInteger(billCodRes.body.bill.finalPayable) &&
      typeof billCodRes.body.bill.cashRoundOff === 'number',
      billCodRes.body
    );

    // 6. Test Admin Config and Coupon endpoints
    const adminConfigRes = await request({
      hostname: 'localhost',
      port: 3000,
      path: '/api/food/admin/config',
      method: 'GET',
    });
    assert('GET /api/food/admin/config returns config with packagingFee and cashRoundingEnabled',
      adminConfigRes.status === 200 &&
      adminConfigRes.body.config &&
      typeof adminConfigRes.body.config.defaultPackagingFee === 'number' &&
      typeof adminConfigRes.body.config.cashRoundingEnabled === 'boolean',
      adminConfigRes.body
    );

    const adminCouponsRes = await request({
      hostname: 'localhost',
      port: 3000,
      path: '/api/food/admin/coupons',
      method: 'GET',
    });
    assert('GET /api/food/admin/coupons returns coupon list for admin console',
      adminCouponsRes.status === 200 &&
      Array.isArray(adminCouponsRes.body.coupons),
      adminCouponsRes.body
    );

    // 7. Place Test Order with COD
    const orderCodRes = await request({
      hostname: 'localhost',
      port: 3000,
      path: '/api/food/orders',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
    }, {
      restaurantId: 'REST_PARADISE_01',
      customerId: 'CUST_TEST_01',
      customerName: 'Test Customer',
      customerPhone: '9876543210',
      items: [{ itemId: 'ITEM_PARADISE_01', quantity: 1 }],
      deliveryAddress: {
        address: 'Plot 42, Hitech City, Hyderabad',
        latitude: 17.4483,
        longitude: 78.3915
      },
      paymentMethod: 'cod',
      couponCode: 'TAKEOFF50ON99',
      idempotencyKey: 'TEST_IDEM_' + Date.now()
    });
    assert('POST /api/food/orders places order with itemized breakdown snapshot',
      orderCodRes.status === 201 &&
      orderCodRes.body.success === true &&
      orderCodRes.body.order &&
      orderCodRes.body.order.packagingFee > 0 &&
      orderCodRes.body.order.platformFee > 0 &&
      orderCodRes.body.order.couponCode === 'TAKEOFF50ON99' &&
      typeof orderCodRes.body.order.cashRoundOff === 'number' &&
      orderCodRes.body.order.finalPayable > 0,
      orderCodRes.body
    );

    console.log(`\n--- TEST SUMMARY: ${passed} PASSED, ${failed} FAILED ---`);
    if (failed === 0) {
      console.log('ALL FOOD CHECKOUT & BILLING INTEGRATION TESTS PASSED SUCCESSFULLY!');
      process.exit(0);
    } else {
      process.exit(1);
    }
  } catch (err) {
    console.error('Test execution error:', err);
    process.exit(1);
  }
}

runTests();
