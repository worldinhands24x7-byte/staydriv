const https = require('https');

function get(url) {
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
    }).on('error', reject);
  });
}

async function verify() {
  console.log('Checking live CloudFront endpoint (https://dk60tgl9yds4p.cloudfront.net)...');
  const cfHealth = await get('https://dk60tgl9yds4p.cloudfront.net/api/health');
  console.log('CloudFront /api/health:', cfHealth.status, cfHealth.body);

  const cfRest = await get('https://dk60tgl9yds4p.cloudfront.net/api/food/restaurants');
  console.log('CloudFront /api/food/restaurants status:', cfRest.status);
  const parsed = JSON.parse(cfRest.body);
  console.log('Live restaurants count:', parsed.count);
  if (parsed.restaurants && parsed.restaurants.length > 0) {
    for (const r of parsed.restaurants) {
      console.log(`- [${r.restaurantId}] ${r.name} | Pin: (${r.lat}, ${r.lng}) | Address: ${r.address} | LocationDetails: "${r.locationDetails || ''}"`);
    }
  }

  // Also test the admin path
  const adminRes = await get('https://dk60tgl9yds4p.cloudfront.net/admin/');
  console.log('\nCloudFront /admin/ index status:', adminRes.status, `(length: ${adminRes.body.length})`);
}

verify().catch(console.error);
