const fs = require('fs');
const content = fs.readFileSync('ttbs_bundle.js', 'utf8');

const target = '/campaigns/sms/inline/send';
let pos = 0;
while ((pos = content.indexOf(target, pos)) !== -1) {
  console.log('Pos:', pos);
  console.log(content.slice(Math.max(0, pos - 200), Math.min(content.length, pos + 300)));
  pos += target.length;
}
