const https = require('https');

async function testValidate() {
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

  const basePayload = {
    name: "OTP Test " + Date.now(),
    description: "OTP Verification",
    jobType: "BULK_SINGLE_MSG_N_RECIPIENTS",
    srcType: "WEB",
    payloadType: "JSON",
    recipientsInline: "9154101606",
    category: "PROMO",
    msg: "Tata Tele Internal NOC Update-SADGURU ROAD LINES",
    channel: "sms",
    sender: "NOCHYD",
    templateId: "1607100000000054848",
    peId: "1601100000000001414",
    expiryDuration: 60,
    expiry: 60
  };

  const data = JSON.stringify(basePayload);
  const req = https.request('https://ttbssmsgw.tatatel.co.in/api/v1/sms/campaigns/b/simple/validate', {
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
      console.log(`[${res.statusCode}] simple/validate =>`, b);
    });
  });
  req.write(data);
  req.end();
}

testValidate();
