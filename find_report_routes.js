const fs = require('fs');
const content = fs.readFileSync('d:/staydriv/ttbs_bundle.js', 'utf8');
const matches = content.match(/"\/api\/v1\/reports\/[^"]+"/g) || [];
console.log([...new Set(matches.map(m => m.slice(1, -1)))]);
