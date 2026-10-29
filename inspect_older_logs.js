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

  // Check page 10 or 20 (older logs)
  https.get('https://ttbssmsgw.tatatel.co.in/api/v1/logs/debug?pgsize=50&pgindex=10', {
    headers: { 'Authorization': 'bearer ' + token }
  }, res => {
    let b = '';
    res.on('data', c => b += c);
    res.on('end', () => {
      try {
        const parsed = JSON.parse(b);
        console.log('Total:', parsed.info?.totalsize);
        const senders = new Set(parsed.logs.map(l => l.s_adr));
        const statuses = new Set(parsed.logs.map(l => `${l.status} (${l.s_st})`));
        console.log('Senders in page 10:', [...senders]);
        console.log('Statuses in page 10:', [...statuses]);
        if (parsed.logs.length > 0) {
          console.log('Sample log:', JSON.stringify(parsed.logs[0], null, 2));
        }
      } catch (e) {
        console.error('Parse error:', e.message);
      }
    });
  });
}

main().catch(console.error);
