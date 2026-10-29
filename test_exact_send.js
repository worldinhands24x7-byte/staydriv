const https = require('https');

async function testSend() {
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

  const now = new Date();
  // Format as YYYY-MM-DDTHH:mm:ss.000+00:00 or ISO string
  const schTime = now.toISOString();

  const payload = {
    name: "StayDriv Test " + Date.now(),
    description: "StayDriv OTP Verification",
    jobType: "BULK_SINGLE_MSG_N_RECIPIENTS",
    srcType: "WEB",
    payloadType: "JSON",
    recipientsInline: "9154101606",
    recipientsOth: "{\"distLists\":[],\"contacts\":[],\"groups\":[],\"files\":[],\"segments\":{\"segmentIds\":[]}}",
    category: "PROMO",
    msg: "Tata Tele Internal NOC Update-SADGURU ROAD LINES",
    channel: "sms",
    sender: "NOCHYD",
    templateId: "1607100000000054848",
    peId: "1601100000000001414",
    expDuration: "1d",
    scheduleType: "ONETIME",
    flash: "false",
    recurrenceId: 0
  };

  console.log("Testing validate...");
  const valData = JSON.stringify(payload);
  await new Promise(resolve => {
    const req = https.request('https://ttbssmsgw.tatatel.co.in/api/v1/sms/campaigns/b/simple/validate', {
      method: 'POST',
      headers: {
        'Authorization': 'Bearer ' + token,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(valData)
      }
    }, res => {
      let b = '';
      res.on('data', c => b += c);
      res.on('end', () => {
        console.log(`[${res.statusCode}] simple/validate =>`, b);
        resolve();
      });
    });
    req.write(valData);
    req.end();
  });

  console.log("Testing send...");
  await new Promise(resolve => {
    const req = https.request('https://ttbssmsgw.tatatel.co.in/api/v1/campaigns/sms/send', {
      method: 'POST',
      headers: {
        'Authorization': 'Bearer ' + token,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(valData)
      }
    }, res => {
      let b = '';
      res.on('data', c => b += c);
      res.on('end', () => {
        console.log(`[${res.statusCode}] campaigns/sms/send =>`, b);
        resolve();
      });
    });
    req.write(valData);
    req.end();
  });
}

testSend();
