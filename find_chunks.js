const fs = require('fs');
const content = fs.readFileSync('ttbs_bundle.js', 'utf8');

const regex = /["']([^"']+\.chunk\.js|\/static\/js\/[^"']+\.js)["']/g;
let m;
const chunks = new Set();
while ((m = regex.exec(content)) !== null) {
  chunks.add(m[1]);
}
console.log('Chunks found:', Array.from(chunks).slice(0, 50));
