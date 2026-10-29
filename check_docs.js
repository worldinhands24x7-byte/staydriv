const https = require('https');

const token = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJiZGFzaEBnbG9iYWx2ZXJzZW5ldHdvcmsuY29tIiwicm9sZXMiOlsiUk9MRV9TQ1NBX1VTRVIiXSwicm9sZUlkeCI6IlJPTEVfU0NTQV9VU0VSIiwiaXNzIjoiVFRCUyIsImlhdCI6MTc3NDU1MzA1NiwiZXhwIjoxNzc0NTU0ODU2fQ.wYF61tP6wP95fU-U19U-w9s-sample"; // wait, let's login first or get a fresh token!

// Let's do a quick login script to get fresh token and fetch /api-docs and /api/v1/docs
async function run() {
  const loginData = JSON.stringify({
    username: "bdash@globalversenetwork.com",
    password: "Password@123",
    role: "ROLE_SCSA_USER"
  });
  
  const post = (url, data, headers = {}) => new Promise((resolve, reject) => {
    const req = https.request(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(data),
        ...headers
      }
    }, res => {
      let b = '';
      res.on('data', d => b += d);
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: b }));
    });
    req.on('error', reject);
    req.write(data);
    req.end();
  });

  const get = (url, headers = {}) => new Promise((resolve, reject) => {
    const req = https.request(url, {
      method: 'GET',
      headers: headers
    }, res => {
      let b = '';
      res.on('data', d => b += d);
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: b }));
    });
    req.on('error', reject);
    req.end();
  });

  const loginRes = await post('https://ttbssmsgw.tatatel.co.in/api/v1/accounts/users/login', loginData);
  const json = JSON.parse(loginRes.body);
  const token = json.token;
  console.log('Got fresh token:', token ? token.slice(0, 20) + '...' : 'NONE');

  const docPaths = ['/api-docs', '/api/v1/docs', '/api/v1/campaigns/sms/send', '/api/v1/sms/campaigns/b/simple/validate'];
  for (const p of docPaths) {
    const res = await get('https://ttbssmsgw.tatatel.co.in' + p, {
      'Authorization': `Bearer ${token}`
    });
    console.log(`GET ${p} -> ${res.status}:`, res.body.slice(0, 300));
  }
}

run().catch(console.error);
