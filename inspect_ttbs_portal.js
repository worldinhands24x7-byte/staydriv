const https = require('https');

https.get('https://ttbssmsgw.tatatel.co.in/', (res) => {
  let b = '';
  res.on('data', c => b += c);
  res.on('end', () => {
    console.log('HTML length:', b.length);
    const scriptMatches = b.match(/src="([^"]+)"/g) || [];
    console.log('Scripts:', scriptMatches);
  });
}).on('error', console.error);
