const fs = require('fs');
const content = fs.readFileSync('ttbs_bundle.js', 'utf8');

const targets = ['bulkSimpleUpload', 'bulkTemplateUpload', 'templateSubmit', 'simpleSubmit'];
for (const t of targets) {
  let pos = 0;
  const matches = [];
  while ((pos = content.indexOf(t, pos)) !== -1) {
    matches.push(pos);
    pos += t.length;
  }
  console.log(`Target ${t}: found ${matches.length} times`);
  matches.forEach((p, idx) => {
    if (idx > 0) { // skip the definition
      console.log(`[${t} #${idx}]`, content.slice(Math.max(0, p - 100), Math.min(content.length, p + 200)));
    }
  });
}
