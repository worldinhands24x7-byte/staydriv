const fs = require('fs');
const content = fs.readFileSync('ttbs_bundle.js', 'utf8');
const pos = content.indexOf('.u=');
if (pos !== -1) {
  console.log('u=', content.slice(pos - 50, pos + 250));
} else {
  console.log('u= not found');
}
const pPos = content.indexOf('__webpack_require__.u');
if (pPos !== -1) {
  console.log('pPos=', content.slice(pPos, pPos + 300));
}
