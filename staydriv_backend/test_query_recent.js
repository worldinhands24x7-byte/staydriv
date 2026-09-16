const mongoose = require('mongoose');
const dotenv = require('dotenv');
dotenv.config();

const mongoUri = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/staydriv';

mongoose.connect(mongoUri)
  .then(async () => {
    const bookingSchema = new mongoose.Schema({}, { strict: false });
    const Booking = mongoose.model('Booking7', bookingSchema, 'bookings');
    const bookings = await Booking.find().sort({ createdAt: -1 }).limit(5);
    console.log('Recent bookings:');
    for (let b of bookings) {
      console.log(`ID: ${b.bookingId}, vehicle: ${b.vehicle}, status: ${b.status}, pickup: ${b.pickup.substring(0, 30)}, drop: ${b.drop.substring(0, 30)}, pickupLatLng:`, b.pickupLatLng, 'dropLatLng:', b.dropLatLng);
    }
    process.exit(0);
  });
