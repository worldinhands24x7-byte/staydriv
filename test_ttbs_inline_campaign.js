const https = require('https');

async function test() {
  const loginData = JSON.stringify({ username: 'SADGURURL', password: 'Sadguru@2026' });
  const token = await new Promise(r => {
    const req = https.request('https://ttbssmsgw.tatatel.co.in/login/user', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(loginData) }
    }, res => {
      let b = '';
      res.on('data', c => b += c);
      res.on('end', () => r(JSON.parse(b).access_token));
    });
    req.write(loginData);
    req.end();
  });

  const payload = {
    name: "OTP Test " + Date.now(),
    description: "OTP Verification",
    jobType: "BULK_SINGLE_MSG_N_RECIPIENTS",
    srcType: "WEB",
    payloadType: "JSON",
    recipientsInline: "919154101606",
    category: "PROMO",
    msg: "Tata Tele Internal NOC Update-SADGURU ROAD LINES",
    channel: "sms",
    sender: "NOCHYD",
    templateId: "1607100000000054848",
    peId: "1601100000000001414"
  };

  const endpoints = [
    '/api/v1/campaigns/sms/inline/send',
    '/api/v1/campaigns/sms/template/inline/send',
    '/api/v1/campaigns/sms/send',
    '/api/v1/sms/campaigns/b/simple/validate',
    '/api/v1/sms/campaigns/b/template/validate'
  ];

  for (const ep of endpoints) {
    const data = JSON.stringify(payload);
    await new Promise(resolve => {
      const req = https.request('https://ttbssmsgw.tatatel.co.in' + ep, {
        method: 'POST',
        headers: {
          'Authorization': 'Bearer ' + token,
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(data)
        }
      }, res => {
        let b = '';
        res.on('data', c => b += c);
        res.on('end', () => {
          console.log(`[${res.statusCode}] ${ep} =>`, b);
          resolve();
        });
      });
      req.write(data);
      req.end();
    });
  }
}

test();
