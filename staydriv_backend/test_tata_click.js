const https = require('https');

const jwtToken = 'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzdWIiOiI3OTkyNDIiLCJjciI6ZmFsc2UsImlzcyI6Imh0dHBzOi8vY2xvdWRwaG9uZS50YXRhdGVsZXNlcnZpY2VzLmNvbS90b2tlbi9nZW5lcmF0ZSIsImlhdCI6MTc4NTE3Njc5MCwiZXhwIjoyMDg1MTc2NzkwLCJuYmYiOjE3ODUxNzY3OTAsImp0aSI6InYzeUZhaUNsRkdXVkRycFMifQ.OIrViD-xEDeYf4XMBn9Ro_4IUvZBzLIOBJjOr8JVHJI';


function testPayload(payload) {
  return new Promise((resolve) => {
    const postData = JSON.stringify(payload);
    const options = {
      hostname: 'cloudphone.tatateleservices.com',
      port: 443,
      path: '/api/v1/click_to_call',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${jwtToken.trim()}`,
        'Content-Length': Buffer.byteLength(postData)
      }
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        console.log("Payload:", payload);
        console.log(`Status: ${res.statusCode} | Response: ${data}\n`);
        resolve({ status: res.statusCode, data });
      });
    });

    req.on('error', err => resolve({ error: err.message }));
    req.write(postData);
    req.end();
  });
}

async function run() {
  console.log("--- Testing Tata Smartflo click_to_call payloads ---\n");
  
  // Test 1: agent_number + destination_number
  await testPayload({
    agent_number: '918121440281',
    destination_number: '919121403844'
  });

  // Test 2: agent_number + destination_number + 10 digits
  await testPayload({
    agent_number: '8121440281',
    destination_number: '9121403844'
  });

  // Test 3: agent_number + destination_number + customer_number
  await testPayload({
    agent_number: '8121440281',
    destination_number: '9121403844',
    customer_number: '9121403844'
  });
}

run();
