const fs = require('fs');
const content = fs.readFileSync('ttbs_bundle.js', 'utf8');

const regex = /bulkTemplateUpload/g;
let m;
while ((m = regex.exec(content)) !== null) {
  console.log('Match at', m.index);
  console.log(content.slice(Math.max(0, m.index - 100), Math.min(content.length, m.index + 200)));
}
