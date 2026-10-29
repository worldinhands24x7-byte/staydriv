const fs = require('fs');
const content = fs.readFileSync('ttbs_bundle.js', 'utf8');

const regex = /["']([a-zA-Z0-9_]*expiry[a-zA-Z0-9_]*)["']/gi;
const set = new Set();
let m;
while ((m = regex.exec(content)) !== null) {
  set.add(m[1]);
}
console.log('Expiry keys:', Array.from(set));
