const fs = require('fs');
const content = fs.readFileSync('ttbs_bundle.js', 'utf8');

const start = content.indexOf('62387(e,t,a){"use strict";');
console.log(content.slice(start, start + 3000));
