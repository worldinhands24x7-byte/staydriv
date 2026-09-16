const http = require('https');

const apiKey = 'AIzaSyD2Lw1UPJAVtzSBY4JARHS6yV284w2hneg';
const origin = '17.4968,78.3606'; // Miyapur
const destination = '16.3067,80.4365'; // Guntur
const url = `https://maps.googleapis.com/maps/api/directions/json?origin=${origin}&destination=${destination}&key=${apiKey}`;

function decodePolyline(encoded) {
  let poly = [];
  let index = 0, len = encoded.length;
  let lat = 0, lng = 0;

  while (index < len) {
    let b, shift = 0, result = 0;
    do {
      b = encoded.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    let dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
    lat += dlat;

    shift = 0;
    result = 0;
    do {
      b = encoded.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    let dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
    lng += dlng;

    poly.push({ lat: lat / 1E5, lng: lng / 1E5 });
  }
  return poly;
}

http.get(url, (res) => {
  let data = '';
  res.on('data', (chunk) => {
    data += chunk;
  });
  res.on('end', () => {
    try {
      const json = JSON.parse(data);
      if (json.status === 'OK') {
        const points = json.routes[0].overview_polyline.points;
        const decoded = decodePolyline(points);
        console.log('Total decoded points:', decoded.length);
        console.log('First 5 points:', decoded.slice(0, 5));
        console.log('Last 5 points:', decoded.slice(-5));
      }
    } catch (e) {
      console.log('Error:', e.message);
    }
  });
});
