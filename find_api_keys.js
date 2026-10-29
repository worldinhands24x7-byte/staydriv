const fs = require('fs');
const content = fs.readFileSync('ttbs_bundle.js', 'utf8');

const regex = /[a-zA-Z0-9_]{0,20}(?:apiKey|api_key|API_KEY|Apikey)[a-zA-Z0-9_]{0,20}/g;
const matches = new Set(content.match(regex) || []);
console.log('Matches:', [...matches]);
