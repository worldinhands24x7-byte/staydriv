const https = require('https');
const fs = require('fs');

console.log('Downloading TTBS main bundle...');
https.get('https://ttbssmsgw.tatatel.co.in/static/js/main.2bcf79a818365fb021ca.js', (res) => {
  let b = '';
  res.on('data', c => b += c);
  res.on('end', () => {
    console.log('Bundle length:', b.length);
    fs.writeFileSync('d:/staydriv/ttbs_bundle.js', b);

    // Search for API paths
    const apiRegex = /["']\/[a-zA-Z0-9_\-\/]+["']/g;
    const matches = b.match(apiRegex) || [];
    const unique = [...new Set(matches.map(m => m.slice(1, -1)))];
    
    console.log('--- Template related paths ---');
    console.log(unique.filter(p => p.toLowerCase().includes('template')));

    console.log('--- Report related paths ---');
    console.log(unique.filter(p => p.toLowerCase().includes('report') || p.toLowerCase().includes('mis') || p.toLowerCase().includes('log')));

    console.log('--- Campaign related paths ---');
    console.log(unique.filter(p => p.toLowerCase().includes('campaign')));
  });
}).on('error', console.error);
