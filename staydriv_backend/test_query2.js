const mongoose = require('mongoose');
const dotenv = require('dotenv');
dotenv.config();

const mongoUri = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/staydriv';

mongoose.connect(mongoUri)
  .then(async () => {
    const bookingSchema = new mongoose.Schema({}, { strict: false });
    const Booking = mongoose.model('Booking4', bookingSchema, 'bookings');
    const booking = await Booking.findOne({ bookingId: 'BK_1782655902782' });
    console.log('Guntur Booking details:', booking);
    process.exit(0);
  });
