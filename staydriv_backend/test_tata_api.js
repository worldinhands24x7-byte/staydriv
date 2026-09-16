require('dotenv').config();
const https = require('https');

const jwtToken = process.env.TATA_SMARTFLO_JWT_TOKEN || 'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzdWIiOiI3OTkyNDIiLCJjciI6ZmFsc2UsImlzcyI6Imh0dHBzOi8vY2xvdWRwaG9uZS50YXRhdGVsZXNlcnZpY2VzLmNvbS90b2tlbi9nZW5lcmF0ZSIsImlhdCI6MTc4NDkxNjA2NiwiZXhwIjoyMDg0OTE2MDY2LCJuYmYiOjE3ODQ5MTYwNjYsImp0aSI6IldExdVmyPxD0KWvX6ifQ.ESt-Dm_ubM0uHc0e5jH6weznIfYmAGnFxzMAM8HEe4A';

console.log("Testing TATA Smartflo Click-To-Call API...");

function testClickToCall(urlPath, payload, headers) {
  return new Promise((resolve) => {
    const postData = JSON.stringify(payload);
    const options = {
      hostname: 'cloudphone.tatateleservices.com',
      port: 443,
      path: urlPath,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData),
        ...headers
      }
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        console.log(`Path [${urlPath}] Status: ${res.statusCode}`);
        console.log(`Response:`, data);
        resolve({ status: res.statusCode, data });
      });
    });

    req.on('error', (e) => {
      console.error(`Path [${urlPath}] Error:`, e.message);
      resolve({ error: e.message });
    });

    req.write(postData);
    req.end();
  });
}

async function run() {
  // Test 1: click_to_call with Bearer token
  await testClickToCall('/api/v1/click_to_call', {
    agent_number: '918121440281',
    customer_number: '919121403844'
  }, {
    'Authorization': `Bearer ${jwtToken.trim()}`
  });

  // Test 2: click_to_call without Bearer prefix
  await testClickToCall('/api/v1/click_to_call', {
    agent_number: '918121440281',
    customer_number: '919121403844'
  }, {
    'Authorization': jwtToken.trim()
  });

  // Test 3: login endpoint to get dynamic token using OR202213
  await testClickToCall('/api/v1/auth/login', {
    username: 'OR202213',
    password: 'Cpt@273095'
  }, {});
}

run();
