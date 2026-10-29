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
    'fefe75ed-e7b1-4582-b5fd-66432f1a47c9',
    'a721b678-ece7-488d-8672-a1a70a3271cb',
    '78daa2f2-bf5e-4674-92ba-b1120a88121d',
    'c8744880-8541-441f-876c-1fbfb7de2588',
    '6dbf8a80-6a18-4c22-bcc9-6efc57ff268c'
  ];

  for (const id of ids) {
    const ep = `/api/v1/sms/campaigns/${id}/status`;
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
