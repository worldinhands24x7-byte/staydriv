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

  const ids = [
    'a721b678-ece7-488d-8672-a1a70a3271cb',
    '78daa2f2-bf5e-4674-92ba-b1120a88121d',
    'c721a286-8065-42a0-9e60-564b7ab5bc6f'
  ];

  for (const id of ids) {
    const urls = [
      `/api/v1/campaigns/c/sms/${id}/0`,
      `/api/v1/campaigns/c/sms/${id}`,
      `/api/v1/campaigns/${id}`
    ];
    for (const u of urls) {
      const res = await new Promise(resolve => {
        https.get('https://ttbssmsgw.tatatel.co.in' + u, {
          headers: { 'Authorization': 'bearer ' + token, 'Accept': 'application/json' }
        }, r => {
          let b = '';
          r.on('data', c => b += c);
          r.on('end', () => resolve({ status: r.statusCode, body: b }));
        }).on('error', e => resolve({ error: e.message }));
      });
      console.log(u, '=> Status:', res.status, res.body ? res.body.slice(0, 150) : '');
    }
  }
}

main().catch(console.error);
