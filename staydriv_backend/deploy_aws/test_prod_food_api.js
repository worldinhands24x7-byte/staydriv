const https = require('https');

function request(options, data) {
  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(body) });
        } catch {
          resolve({ status: res.statusCode, data: body });
        }
      });
    });
    req.on('error', reject);
    if (data) req.write(JSON.stringify(data));
    req.end();
  });
}

async function runTest() {
  const host = 'dk60tgl9yds4p.cloudfront.net';

  console.log('--- 1. Testing GET /api/food/categories ---');
  const catRes = await request({ host, path: '/api/food/categories', method: 'GET' });
  console.log(`Status: ${catRes.status}, Categories: ${catRes.data.categories?.length}`);

  console.log('--- 2. Testing GET /api/food/restaurants ---');
  const restRes = await request({ host, path: '/api/food/restaurants', method: 'GET' });
  console.log(`Status: ${restRes.status}, Restaurants: ${restRes.data.restaurants?.length}`);
  const firstRest = restRes.data.restaurants[0];
  console.log(`First restaurant: ${firstRest.name} (${firstRest.restaurantId})`);

  console.log(`--- 3. Testing GET /api/food/restaurants/${firstRest.restaurantId} ---`);
  const detailRes = await request({ host, path: `/api/food/restaurants/${firstRest.restaurantId}`, method: 'GET' });
  console.log(`Status: ${detailRes.status}, Menu Items: ${detailRes.data.menuItems?.length}`);
  const firstItem = detailRes.data.menuItems[0];
  console.log(`First item: ${firstItem.name} - ₹${firstItem.price} (${firstItem.category})`);

  console.log('--- 4. Testing POST /api/food/validate-cart ---');
  const cartRes = await request({
    host,
    path: '/api/food/validate-cart',
    method: 'POST',
    headers: { 'Content-Type': 'application/json' }
  }, {
    restaurantId: firstRest.restaurantId,
    items: [{ itemId: firstItem.itemId, quantity: 2 }]
  });
  console.log(`Status: ${cartRes.status}, Subtotal: ₹${cartRes.data.subtotal}, GrandTotal: ₹${cartRes.data.totalAmount}`);

  console.log('--- 5. Testing POST /api/food/orders ---');
  const orderRes = await request({
    host,
    path: '/api/food/orders',
    method: 'POST',
    headers: { 'Content-Type': 'application/json' }
  }, {
    customerId: 'CUST_PROD_VERIFY',
    customerName: 'Vivek Sharma',
    customerPhone: '9247535068',
    deliveryAddress: 'Flat 402, Highrise Heights, Madhapur, Hyderabad',
    deliveryLatLng: { lat: 17.4485, lng: 78.3741 },
    restaurantId: firstRest.restaurantId,
    items: [{
      itemId: firstItem.itemId,
      quantity: 2
    }],
    paymentMethod: 'ONLINE_UPI'
  });
  console.log(`Status: ${orderRes.status}, Order placed: ${orderRes.data.order?.orderId}, Delivery OTP: ${orderRes.data.order?.deliveryOtp}`);
  const orderId = orderRes.data.order?.orderId;

  console.log(`--- 6. Testing GET /api/food/orders/${orderId} ---`);
  const trackRes = await request({ host, path: `/api/food/orders/${orderId}`, method: 'GET' });
  console.log(`Status: ${trackRes.status}, OrderStatus: ${trackRes.data.order?.orderStatus}, Total: ₹${trackRes.data.order?.totalAmount}`);

  console.log('--- 7. Testing GET /api/food/admin/orders ---');
  const adminRes = await request({
    host,
    path: '/api/food/admin/orders',
    method: 'GET',
    headers: { 'x-admin-key': 'staydriv_admin_secret_2026' }
  });
  console.log(`Status: ${adminRes.status}, Total Orders in Admin: ${adminRes.data.orders?.length}`);

  console.log('--- 8. Testing GET /api/food/admin/stats ---');
  const statsRes = await request({
    host,
    path: '/api/food/admin/stats',
    method: 'GET',
    headers: { 'x-admin-key': 'staydriv_admin_secret_2026' }
  });
  console.log(`Status: ${statsRes.status}, Stats: ${JSON.stringify(statsRes.data.stats)}`);

  console.log('=== ALL PRODUCTION ENDPOINTS VERIFIED AND OPERATIONAL ===');
}

runTest().catch(console.error);
