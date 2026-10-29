const fs = require('fs');
const content = fs.readFileSync('ttbs_bundle.js', 'utf8');

const regex = /\.A\)\(["']([^"']+)["']\)/g;
let m;
const endpointsUsed = new Set();
while ((m = regex.exec(content)) !== null) {
  if (m[1].toLowerCase().includes('campaign') || m[1].toLowerCase().includes('sms') || m[1].toLowerCase().includes('send') || m[1].toLowerCase().includes('submit') || m[1].toLowerCase().includes('validate')) {
    endpointsUsed.add(m[1]);
  }
}
console.log('Endpoints used:', Array.from(endpointsUsed));
