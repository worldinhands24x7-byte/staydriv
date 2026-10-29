const fs = require('fs');
const content = fs.readFileSync('ttbs_bundle.js', 'utf8');

const targets = ['"bulkSimpleUpload"', '"bulkTemplateUpload"', '"simpleSubmit"', '"templateSubmit"'];
for (const t of targets) {
  let pos = 0;
  while ((pos = content.indexOf(t, pos)) !== -1) {
    console.log(`Found ${t} at ${pos}:`);
    console.log(content.slice(Math.max(0, pos - 150), Math.min(content.length, pos + 300)));
    pos += t.length;
  }
}
