const fs = require('fs');
const content = fs.readFileSync('ttbs_bundle.js', 'utf8');

const target = 'listCampaign:"/api/v1/campaigns"';
const idx = content.indexOf(target);
console.log('Index:', idx);
if (idx !== -1) {
  console.log('--- 1000 CHARS BEFORE ---');
  console.log(content.slice(Math.max(0, idx - 1000), idx));
}
