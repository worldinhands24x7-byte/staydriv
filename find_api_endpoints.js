const fs = require('fs');
const content = fs.readFileSync('d:/staydriv/ttbs_bundle.js', 'utf8');
const matches = content.match(/"(\/api\/[^"]+)"/g) || [];
const unique = [...new Set(matches.map(m => m.slice(1, -1)))];
console.log('Total /api/ endpoints:', unique.length);
console.log(unique.filter(u => u.includes('dlt') || u.includes('sender') || u.includes('header') || u.includes('template')));
