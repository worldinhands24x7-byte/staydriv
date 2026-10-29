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

  https.get('https://ttbssmsgw.tatatel.co.in/api/v1/logs/debug', {
    headers: { 'Authorization': 'bearer ' + token }
  }, res => {
    let b = '';
    res.on('data', c => b += c);
    res.on('end', () => {
      const parsed = JSON.parse(b);
      console.log('Total Logs:', parsed.info ? parsed.info.totalsize : 0);
      console.log('Latest 5 Logs:');
      console.log(JSON.stringify(parsed.logs.slice(0, 5), null, 2));
    });
  });
}

main().catch(console.error);
