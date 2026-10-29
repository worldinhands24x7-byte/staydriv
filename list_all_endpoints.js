const fs = require('fs');
const content = fs.readFileSync('ttbs_bundle.js', 'utf8');

const regex = /"(\/api\/v[0-9]\/[^"]*)"/g;
let match;
const apiEndpoints = new Set();
while ((match = regex.exec(content)) !== null) {
  apiEndpoints.add(match[1]);
}

const list = [...apiEndpoints].sort();
console.log('Total v-endpoints:', list.length);
console.log(list.join('\n'));
