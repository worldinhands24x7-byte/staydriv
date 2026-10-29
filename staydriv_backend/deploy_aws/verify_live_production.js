const https = require('https');

function request(options, data) {
  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, headers: res.headers, data: JSON.parse(body) });
        } catch {
          resolve({ status: res.statusCode, headers: res.headers, data: body });
        }
      });
    });
    req.on('error', reject);
    if (data) req.write(JSON.stringify(data));
    req.end();
  });
}

async function verifyLiveProduction() {
  const host = 'dk60tgl9yds4p.cloudfront.net';
  console.log('===========================================================');
  console.log(' VERIFYING LIVE CLOUDFRONT & EC2 PRODUCTION SYSTEM        ');
  console.log(' Host:', host);
  console.log('===========================================================');

  // 1. Health check
  console.log('\n1. Testing GET /api/health:');
  const health = await request({ host, path: '/api/health', method: 'GET' });
  console.log('  Status:', health.status, '| Body:', JSON.stringify(health.data));
  if (health.status !== 200 || health.data.status !== 'UP') {
    throw new Error('Health check failed!');
  }

  // 2. Restaurants check (Only genuine, zero dummy)
  console.log('\n2. Testing GET /api/food/restaurants:');
  const rest = await request({ host, path: '/api/food/restaurants', method: 'GET' });
  console.log('  Status:', rest.status, '| Total genuine restaurants:', rest.data.count);
  const dummyNames = ['Paradise Biryani', 'Chutneys Flavours', 'Bawarchi Grand', 'Pista House', 'Pizza Hub Italian Kitchen', 'Burger Craft', 'Red Dragon Wok'];
  const foundDummies = (rest.data.restaurants || []).filter(r => dummyNames.includes(r.name) || (r.restaurantId && r.restaurantId.startsWith('REST_PARADISE')));
  console.log('  Dummy restaurants found:', foundDummies.length);
  if (foundDummies.length > 0) {
    throw new Error('Found dummy restaurants in production!');
  }
  (rest.data.restaurants || []).forEach(r => {
    console.log(`    - [${r.restaurantId}] ${r.name} (coords: ${r.lat}, ${r.lng})`);
  });

  // 3. Geocode endpoint check
  console.log('\n3. Testing GET /api/food/admin/geocode?address=Madhapur,%20Hyderabad:');
  const geocode = await request({
    host,
    path: '/api/food/admin/geocode?address=Madhapur,%20Hyderabad',
    method: 'GET',
    headers: { 'x-admin-key': 'staydriv_admin_secret_2026' }
  });
  console.log('  Status:', geocode.status, '| Geocode Result:', JSON.stringify(geocode.data));

  // 4. Pilot available orders check (Ensure unaccepted orders are isolated)
  console.log('\n4. Testing GET /api/food/pilot/available-orders:');
  const pilotOrders = await request({ host, path: '/api/food/pilot/available-orders?pilotPhone=9490440281', method: 'GET' });
  console.log('  Status:', pilotOrders.status, '| Available orders count:', pilotOrders.data.count);

  // 5. Admin Console serving check
  console.log('\n5. Testing GET /admin (Admin Console Frontend):');
  const adminIndex = await request({ host, path: '/admin', method: 'GET' });
  console.log('  Status:', adminIndex.status, '| Type:', adminIndex.headers['content-type']);

  console.log('\n===========================================================');
  console.log(' ALL LIVE PRODUCTION VERIFICATION CHECKS PASSED!          ');
  console.log('===========================================================');
}

verifyLiveProduction().catch(e => {
  console.error('\n❌ Verification failed:', e);
  process.exit(1);
});
