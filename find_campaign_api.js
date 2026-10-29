const fs = require('fs');
const content = fs.readFileSync('ttbs_bundle.js', 'utf8');

const target = 'bulkSimpleUpload:"/api/v1/campaigns/sms/inline/send"';
const idx = content.indexOf(target);
console.log('Index:', idx);
if (idx !== -1) {
  console.log('--- BEFORE ---');
  console.log(content.slice(Math.max(0, idx - 600), idx));
  console.log('--- AFTER ---');
  console.log(content.slice(idx, Math.min(content.length, idx + 600)));
}
