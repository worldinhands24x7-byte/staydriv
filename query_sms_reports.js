const https = require('https');

async function main() {
  const postData = JSON.stringify({ username: 'SADGURURL', password: 'Sadguru@2026' });
  const token = await new Promise(resolve => {
    const r = https.request({
      hostname: 'ttbssmsgw.tatatel.co.in',
      port: 443,
      path: '/login/user',
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(postData) }
    }, (res) => {
      let b = '';
      res.on('data', c => b += c);
      res.on('end', () => resolve(JSON.parse(b).access_token));
    });
    r.write(postData);
    r.end();
  });

  const eps = [
    '/api/v1/reports/sms/_details',
    '/api/v1/reports/sms/_summary',
    '/api/v1/reports/sms/campaign/_stats',
    '/api/v1/reports/sms/campaign/_view',
    '/api/v1/reports/sms/campaign/_detail'
  ];

  for (const ep of eps) {
    const res = await new Promise(resolve => {
      https.get('https://ttbssmsgw.tatatel.co.in' + ep, {
        headers: { 'Authorization': 'bearer ' + token, 'Accept': 'application/json' }
      }, r => {
        let b = '';
        r.on('data', c => b += c);
        r.on('end', () => resolve({ status: r.statusCode, body: b }));
      }).on('error', e => resolve({ error: e.message }));
    });
    console.log(ep, '=> Status:', res.status, res.body ? res.body.slice(0, 200) : '');
  }
}

main().catch(console.error);
