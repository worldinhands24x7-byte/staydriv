const http = require('http');

const origin = '17.526372502339854,78.42397988065278';
const destination = '17.5046831,78.521394';
const url = `http://localhost:3000/api/directions?origin=${encodeURIComponent(origin)}&destination=${encodeURIComponent(destination)}`;

http.get(url, (res) => {
  let data = '';
  res.on('data', (chunk) => {
    data += chunk;
  });
  res.on('end', () => {
    console.log('Status Code:', res.statusCode);
    try {
      const json = JSON.parse(data);
      console.log('API Status:', json.status);
      if (json.status === 'OK') {
        const polylineStr = json.routes[0].overview_polyline.points;
        console.log('Polyline sample:', polylineStr.substring(0, 50));
      } else {
        console.log('Error details:', json);
      }
    } catch (e) {
      console.log('Failed to parse response:', e.message);
      console.log('Data:', data);
    }
  });
}).on('error', (err) => {
  console.log('Request Error:', err.message);
});
