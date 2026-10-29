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
    '/api/v1/numbers/sender/scsa/sas',
    '/api/v2/numbers/sender/scsa/sas',
    '/api/v1/sms/templates/926f536e-4fa5-4a0c-9c84-3a9770e950cf'
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
    console.log(ep, '=> Status:', res.status);
    console.log(res.body);
  }
}

main().catch(console.error);
