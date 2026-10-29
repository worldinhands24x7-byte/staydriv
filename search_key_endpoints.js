const fs = require('fs');
const content = fs.readFileSync('ttbs_bundle.js', 'utf8');

const regex = /"(\/api\/[^"]*)"/g;
let match;
const apiEndpoints = new Set();
while ((match = regex.exec(content)) !== null) {
  apiEndpoints.add(match[1]);
}

const list = [...apiEndpoints];
console.log('--- ALL KEY ENDPOINTS ---');
list.filter(e => /key/i.test(e)).forEach(e => console.log(e));
