const http = require('https');

const apiKey = 'AIzaSyD2Lw1UPJAVtzSBY4JARHS6yV284w2hneg';
const origin = '17.4968,78.3606'; // Miyapur
const destination = '16.3067,80.4365'; // Guntur
const urlString = `https://maps.googleapis.com/maps/api/directions/json?origin=${origin}&destination=${destination}&key=${apiKey}`;
const proxyUrl = `https://corsproxy.io/?` + encodeURIComponent(urlString);

http.get(proxyUrl, (res) => {
  let data = '';
  res.on('data', (chunk) => {
    data += chunk;
  });
  res.on('end', () => {
    console.log('Proxy Status Code:', res.statusCode);
    try {
      const json = JSON.parse(data);
      console.log('Proxy Directions API Status:', json.status);
      if (json.status === 'OK') {
        console.log('Proxy Route found! Polyline points length:', json.routes[0].overview_polyline.points.length);
      } else {
        console.log('Proxy error status:', json.status);
      }
    } catch (e) {
      console.log('Failed to parse proxy response:', e.message);
      console.log('Response sample:', data.substring(0, 500));
    }
  });
}).on('error', (err) => {
  console.error('Error:', err.message);
});
