const https = require('https');

const recipient = '918121440281';
const otp = '949022';
const messageText = `Your One-Time Password (OTP) is ${otp}. This OTP is valid for 10 minutes. Do not share it with anyone.`;

const user = 'SADGURURL';
const pswd = 'Sadguru@2026';
const sender = 'SRL';
const peId = '1601419178359745779';
const templateId = '1677100000000387025';

const url = `https://ttbssmsgw.tatatel.co.in/campaignService/campaigns/qs?recipient=${encodeURIComponent(recipient)}&dr=false&msg=${encodeURIComponent(messageText)}&user=${encodeURIComponent(user)}&pswd=${encodeURIComponent(pswd)}&sender=${encodeURIComponent(sender)}&PE_ID=${encodeURIComponent(peId)}&Template_ID=${encodeURIComponent(templateId)}`;

console.log('Sending request to TATA DLT SMS Gateway:');
console.log(url);

https.get(url, (res) => {
  let data = '';
  res.on('data', chunk => data += chunk);
  res.on('end', () => {
    console.log(`STATUS: ${res.statusCode}`);
    console.log(`RESPONSE: ${data}`);
  });
}).on('error', err => {
  console.error('ERROR:', err.message);
});
