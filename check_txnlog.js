const https = require('https');

async function main() {
  const postData = JSON.stringify({ username: 'SADGURURL', password: 'Sadguru@2026' });
  const token = await new Promise(r => {
    const req = https.request('https://ttbssmsgw.tatatel.co.in/login/user', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(postData) }
    }, res => {
      let b = '';
      res.on('data', c => b += c);
      res.on('end', () => r(JSON.parse(b).access_token));
    });
    req.write(postData);
    req.end();
  });

  const eps = [
    '/api/v1/txnlog/transactions',
    '/api/v1/wallet/creditHistory/d7cd1a10-6f30-44ba-9a64-ce3a9cd9b12a',
    '/api/v1/metrics/campaigns/sms/_status',
    '/api/v1/metrics/campaigns/sms/_stats',
    '/api/v1/reports/sms/_summary',
    '/api/v1/reports/sms/_details',
    '/api/v1/logs/debug',
    '/api/v1/logs/audit'
  ];

  for (const ep of eps) {
    await new Promise(resolve => {
      https.get('https://ttbssmsgw.tatatel.co.in' + ep, {
        headers: { 'Authorization': 'bearer ' + token, 'Accept': 'application/json' }
      }, res => {
        let b = '';
        res.on('data', c => b += c);
        res.on('end', () => {
          console.log(`[${ep}] Status: ${res.statusCode} | Data: ${b.slice(0, 300)}`);
          resolve();
        });
      }).on('error', e => {
        console.log(`[${ep}] Error: ${e.message}`);
        resolve();
      });
    });
  }
}

main().catch(console.error);
