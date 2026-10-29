const https = require('https');

const GOOGLE_API_KEY = process.env.GOOGLE_MAPS_API_KEY || 'AIzaSyD2Lw1UPJAVtzSBY4JARHS6yV284w2hneg';

/**
 * Geocode a human-readable address into { lat, lng, formattedAddress }
 * Uses Google Maps Geocoding API with clean error handling and timeout.
 */
function geocodeAddress(address) {
  return new Promise((resolve) => {
    if (!address || typeof address !== 'string' || address.trim().length === 0) {
      return resolve(null);
    }
    const cleanAddr = address.trim();
    // Also try stripping floor/flat prefixes if search is too narrow
    const encoded = encodeURIComponent(cleanAddr);
    const url = `https://maps.googleapis.com/maps/api/geocode/json?address=${encoded}&key=${GOOGLE_API_KEY}`;

    const req = https.get(url, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          if (json.status === 'OK' && Array.isArray(json.results) && json.results.length > 0) {
            const first = json.results[0];
            const loc = first.geometry && first.geometry.location;
            if (loc && typeof loc.lat === 'number' && typeof loc.lng === 'number') {
              return resolve({
                lat: loc.lat,
                lng: loc.lng,
                formattedAddress: first.formatted_address || cleanAddr
              });
            }
          }
          // If first attempt gave ZERO_RESULTS, try simplified address (remove floor/plot prefixes)
          const simplified = cleanAddr
            .replace(/Plot\s*No:?\s*[\w\d\-\/]+/i, '')
            .replace(/\d+(st|nd|rd|th)?\s*Floor/i, '')
            .replace(/X['’`]?\s*Road/i, '')
            .trim();

          if (simplified.length > 5 && simplified !== cleanAddr) {
            const simpleUrl = `https://maps.googleapis.com/maps/api/geocode/json?address=${encodeURIComponent(simplified)}&key=${GOOGLE_API_KEY}`;
            https.get(simpleUrl, (sRes) => {
              let sData = '';
              sRes.on('data', c => sData += c);
              sRes.on('end', () => {
                try {
                  const sJson = JSON.parse(sData);
                  if (sJson.status === 'OK' && Array.isArray(sJson.results) && sJson.results.length > 0) {
                    const sLoc = sJson.results[0].geometry && sJson.results[0].geometry.location;
                    if (sLoc && typeof sLoc.lat === 'number' && typeof sLoc.lng === 'number') {
                      return resolve({
                        lat: sLoc.lat,
                        lng: sLoc.lng,
                        formattedAddress: sJson.results[0].formatted_address || cleanAddr
                      });
                    }
                  }
                  resolve(null);
                } catch (_) {
                  resolve(null);
                }
              });
            }).on('error', () => resolve(null));
          } else {
            resolve(null);
          }
        } catch (e) {
          resolve(null);
        }
      });
    });

    req.on('error', () => resolve(null));
    req.setTimeout(5000, () => {
      req.destroy();
      resolve(null);
    });
  });
}

module.exports = {
  geocodeAddress
};
