const https = require('https');
https.get('https://ttbssmsgw.tatatel.co.in/', res => {
  let b = '';
  res.on('data', c => b += c);
  res.on('end', () => {
    const scripts = [...b.matchAll(/src="([^"]+)"/g)].map(m => m[1]);
    console.log('Scripts:', scripts);
  });
});
