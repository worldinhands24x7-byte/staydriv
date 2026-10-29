const fs = require('fs');
const content = fs.readFileSync('ttbs_bundle.js', 'utf8');

const regex = /\.append\(["']([^"']+)["']/g;
const fields = new Set();
let m;
while ((m = regex.exec(content)) !== null) {
  fields.add(m[1]);
}
console.log('Appended form fields:', Array.from(fields));
