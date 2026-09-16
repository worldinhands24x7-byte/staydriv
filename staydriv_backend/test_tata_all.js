const https = require('https');

const jwtToken = 'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzdWIiOiI3OTkyNDIiLCJjciI6ZmFsc2UsImlzcyI6Imh0dHBzOi8vY2xvdWRwaG9uZS50YXRhdGVsZXNlcnZpY2VzLmNvbS90b2tlbi9nZW5lcmF0ZSIsImlhdCI6MTc4NDkxNjA2NiwiZXhwIjoyMDg0OTE2MDY2LCJuYmYiOjE3ODQ5MTYwNjYsImp0aSI6IldFeHVWbXlQeEQwS1d2WDYifQ.ESt-Dm_ubM0uHc0e5jH6weznIfYmAGnFxzMAM8HEe4A';

const hosts = [
  'cloudphone.tatateleservices.com',
  'api-smartflo.tatateleservices.com',
  'smartflo.tatateleservices.com'
];

const clickPaths = [
  '/api/v1/click_to_call',
  '/api/v1/click2call',
  '/api/v1/call/click_to_call',
  '/api/v1/call_masking',
  '/api/v1/click_to_call/initiate'
];

const loginPaths = [
  '/api/v1/auth/login',
  '/api/v1/login',
  '/api/v1/user/login',
  '/token/generate'
];

function makeReq(hostname, path, payload, token) {
  return new Promise((resolve) => {
    const postData = JSON.stringify(payload);
    const headers = {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(postData)
    };
    if (token) {
      headers['Authorization'] = `Bearer ${token}`;
    }

    const req = https.request({
      hostname,
      port: 443,
      path,
      method: 'POST',
      headers
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        resolve({ host: hostname, path, status: res.statusCode, data });
      });
    });

    req.on('error', err => resolve({ host: hostname, path, error: err.message }));
    req.write(postData);
    req.end();
  });
}

async function main() {
  console.log("=== TESTING TATA SMARTFLO APIS ===");
  for (const host of hosts) {
    console.log(`\n--- Host: ${host} ---`);
    for (const path of clickPaths) {
      const res = await makeReq(host, path, {
        agent_number: '918121440281',
        customer_number: '919121403844'
      }, jwtToken);
      console.log(`[CLICK] ${path} => ${res.status || res.error} | ${res.data || ''}`);
    }

    for (const path of loginPaths) {
      const res = await makeReq(host, path, {
        username: 'OR202213',
        password: 'Cpt@273095'
      });
      console.log(`[LOGIN] ${path} => ${res.status || res.error} | ${res.data || ''}`);
    }
  }
}

main();
