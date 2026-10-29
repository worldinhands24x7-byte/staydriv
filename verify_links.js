const https = require('https');
const urls = [
  'https://dk60tgl9yds4p.cloudfront.net/staydriv-combined.apk',
  'https://dk60tgl9yds4p.cloudfront.net/staydriv-combined.aab',
  'https://dk60tgl9yds4p.cloudfront.net/apk/staydriv-combined.apk',
  'https://dk60tgl9yds4p.cloudfront.net/aab/staydriv-combined.aab',
  'https://dk60tgl9yds4p.cloudfront.net/staydriv-latest.apk',
  'https://dk60tgl9yds4p.cloudfront.net/staydriv-latest.aab',
  'https://dk60tgl9yds4p.cloudfront.net/staydriv-v1.0.105.apk',
  'https://dk60tgl9yds4p.cloudfront.net/staydriv-v1.0.105.aab',
  'https://dk60tgl9yds4p.cloudfront.net/version.json'
];

async function testAll() {
  console.log('Testing live endpoints...');
  for (const url of urls) {
    await new Promise((resolve) => {
      https.get(url, { method: 'HEAD' }, (res) => {
        const sizeMb = res.headers['content-length'] ? (res.headers['content-length'] / 1024 / 1024).toFixed(2) + ' MB' : 'N/A';
        console.log(`[HTTP ${res.statusCode}] ${sizeMb} -> ${url}`);
        resolve();
      }).on('error', (err) => {
        console.error('FAIL:', url, err.message);
        resolve();
      });
    });
  }
}
testAll();
