const mongoose = require('mongoose');
const dotenv = require('dotenv');
dotenv.config();

const mongoUri = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/staydriv';

function getDistance(lat1, lon1, lat2, lon2) {
  const R = 6371e3; // metres
  const phi1 = lat1 * Math.PI/180;
  const phi2 = lat2 * Math.PI/180;
  const deltaPhi = (lat2-lat1) * Math.PI/180;
  const deltaLambda = (lon2-lon1) * Math.PI/180;

  const a = Math.sin(deltaPhi/2) * Math.sin(deltaPhi/2) +
            Math.cos(phi1) * Math.cos(phi2) *
            Math.sin(deltaLambda/2) * Math.sin(deltaLambda/2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));

  return R * c; // in metres
}

const isPilotMatch = (pilot, queryId) => {
  if (!pilot || !queryId) return false;
  const qIdStr = String(queryId);
  if (pilot.uid === qIdStr) return true;
  
  let normQuery = qIdStr.replace('mock_uid_', '');
  let normPilotUid = pilot.uid ? String(pilot.uid).replace('mock_uid_', '') : '';
  let normPilotPhone = pilot.phone ? String(pilot.phone).replace('mock_uid_', '') : '';
  
  if (normQuery.endsWith('_pilot')) normQuery = normQuery.replace('_pilot', '');
  if (normPilotUid.endsWith('_pilot')) normPilotUid = normPilotUid.replace('_pilot', '');
  if (normPilotPhone.endsWith('_pilot')) normPilotPhone = normPilotPhone.replace('_pilot', '');
  
  return normQuery === normPilotUid || normQuery === normPilotPhone;
};

mongoose.connect(mongoUri)
  .then(async () => {
    console.log('Connected to MongoDB');
    
    // Schema definitions
    const userSchema = new mongoose.Schema({
      uid: String,
      name: String,
      phone: String,
      role: String,
      vehicleType: String,
      online: { type: Boolean, default: false },
      approved: { type: Boolean, default: false },
      lat: Number,
      lng: Number,
      lastActive: Date
    });
    const User = mongoose.model('User3', userSchema, 'users');

    const bookingSchema = new mongoose.Schema({
      bookingId: String,
      pickup: String,
      drop: String,
      vehicle: String,
      status: String,
      pickupLatLng: mongoose.Schema.Types.Mixed,
      dropLatLng: mongoose.Schema.Types.Mixed,
      driverId: String,
      declinedDrivers: [String],
      createdAt: Date
    });
    const Booking = mongoose.model('Booking3', bookingSchema, 'bookings');

    const driverId = 'mock_uid_9247535068_pilot';
    const vehicleType = 'Heavy Truck';

    // Simulate search
    let vehicleRegex = new RegExp('^' + (vehicleType || '') + '$', 'i');
    if (vehicleType) {
      const vtLower = vehicleType.toLowerCase();
      if (vtLower.includes('truck')) {
        vehicleRegex = new RegExp('truck', 'i');
      }
    }
    console.log('vehicleRegex:', vehicleRegex);

    // Let's find a booking matching this or mock one temporarily in searching state
    let b = await Booking.findOne({ bookingId: 'BK_1782657270249' });
    if (b) {
      b.status = 'searching'; // change to searching for testing match
    } else {
      console.log('Booking not found');
      process.exit(1);
    }

    console.log('Simulating matching for booking:', b.bookingId, 'vehicle:', b.vehicle);

    const onlinePilots = await User.find({
      role: 'partner',
      online: true,
      vehicleType: vehicleRegex
    });
    console.log('Found onlinePilots matching vehicleRegex:', onlinePilots.map(p => ({ uid: p.uid, online: p.online, vehicleType: p.vehicleType, lastActive: p.lastActive })));

    const activeThreshold = new Date(Date.now() - 15000);
    console.log('activeThreshold:', activeThreshold);

    const eligiblePilots = onlinePilots.filter(p => {
      // Must have polled in the last 15 seconds to be considered active
      if (!p.lastActive || p.lastActive < activeThreshold) {
        console.log(`Pilot ${p.uid} rejected: lastActive ${p.lastActive} is older than activeThreshold ${activeThreshold}`);
        return false;
      }

      if (b.declinedDrivers && (b.declinedDrivers.includes(p.uid) || (p.phone && b.declinedDrivers.includes(p.phone)))) {
        console.log(`Pilot ${p.uid} rejected: declined this booking`);
        return false;
      }
      
      return true;
    });

    console.log('eligiblePilots count:', eligiblePilots.length);

    if (eligiblePilots.length > 0) {
      const pickupLat = b.pickupLatLng.lat;
      const pickupLng = b.pickupLatLng.lng;

      const sortedPilots = eligiblePilots.map(p => {
        const dist = getDistance(pickupLat, pickupLng, p.lat || 0, p.lng || 0);
        return { pilot: p, dist };
      }).sort((a, b) => a.dist - b.dist);

      console.log('sortedPilots:', sortedPilots.map(sp => ({ uid: sp.pilot.uid, dist: sp.dist })));

      if (isPilotMatch(sortedPilots[0].pilot, driverId)) {
        console.log(`SUCCESS! Assigned booking ${b.bookingId} to driver ${driverId}`);
      } else {
        console.log(`FAILED! sortedPilots[0] is ${sortedPilots[0].pilot.uid}, but requested driver is ${driverId}`);
      }
    } else {
      console.log('No eligible pilots found.');
    }

    process.exit(0);
  })
  .catch(err => {
    console.error('Error:', err);
    process.exit(1);
  });
