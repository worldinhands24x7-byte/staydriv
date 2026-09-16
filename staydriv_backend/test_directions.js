const http = require('https');

const apiKey = 'AIzaSyD2Lw1UPJAVtzSBY4JARHS6yV284w2hneg';
const origin = '17.4968,78.3606'; // Miyapur
const destination = '16.3067,80.4365'; // Guntur
const url = `https://maps.googleapis.com/maps/api/directions/json?origin=${origin}&destination=${destination}&key=${apiKey}`;

http.get(url, (res) => {
  let data = '';
  res.on('data', (chunk) => {
    data += chunk;
  });
  res.on('end', () => {
    console.log('Status Code:', res.statusCode);
    try {
      const json = JSON.parse(data);
      console.log('Directions API Status:', json.status);
      if (json.status === 'OK') {
        console.log('Route found! Polyline points length:', json.routes[0].overview_polyline.points.length);
      } else {
        console.log('Error message:', json.error_message);
      }
    } catch (e) {
      console.log('Failed to parse JSON:', e.message);
      console.log('Data sample:', data.substring(0, 500));
    }
  });
}).on('error', (err) => {
  console.error('Error:', err.message);
});
