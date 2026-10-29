const fs = require('fs');
const content = fs.readFileSync('ttbs_bundle.js', 'utf8');

const start = content.indexOf('62387(e,t,a){"use strict";');
const end = content.indexOf('},', start + 10000);
console.log('End of 62387:', content.slice(end - 500, end + 200));
