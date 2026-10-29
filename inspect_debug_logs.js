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

  https.get('https://ttbssmsgw.tatatel.co.in/api/v1/logs/debug?pgsize=20&pgindex=0', {
    headers: { 'Authorization': 'bearer ' + token }
  }, res => {
    let b = '';
    res.on('data', c => b += c);
    res.on('end', () => {
      const parsed = JSON.parse(b);
      const statuses = new Set(parsed.logs.map(l => `${l.status} (code: ${l.s_st}) sender: ${l.s_adr}`));
      console.log('Unique statuses in latest 20:', [...statuses]);
      parsed.logs.slice(0, 10).forEach(l => {
        console.log(`Time: ${new Date(Number(l.c_tm)).toISOString()} | Sender: ${l.s_adr} | Aud: ${l.aud} | Status: ${l.status} (${l.s_st}) | Source: ${l.source}`);
      });
    });
  });
}

main().catch(console.error);
