const fs = require('fs');
const content = fs.readFileSync('ttbs_bundle.js', 'utf8');

const targets = ['simpleSubmit', 'bulkSimpleUpload', 'campaignSimpleValidate', '/campaigns/sms/inline/send', '/campaigns/sms/send'];
for (const t of targets) {
  let idx = 0;
  while ((idx = content.indexOf(t, idx)) !== -1) {
    console.log(`=== Found ${t} at ${idx} ===`);
    console.log(content.slice(Math.max(0, idx - 150), Math.min(content.length, idx + 250)));
    idx += t.length;
  }
}
