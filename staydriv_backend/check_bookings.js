const mongoose = require('mongoose');
const MONGO_URI = 'mongodb://127.0.0.1:27017/staydriv';

mongoose.connect(MONGO_URI)
  .then(async () => {
    const Booking = mongoose.model('Booking', new mongoose.Schema({}, { strict: false }), 'bookings');
    const bookings = await Booking.find().sort({ createdAt: -1 }).limit(10);
    console.log(`=== RECENT BOOKINGS (${bookings.length}) ===`);
    bookings.forEach(b => {
      console.log({
        bookingId: b.get('bookingId'),
        pickup: b.get('pickup'),
        drop: b.get('drop'),
        vehicle: b.get('vehicle'),
        status: b.get('status'),
        passengerId: b.get('passengerId'),
        driverId: b.get('driverId'),
        createdAt: b.get('createdAt')
      });
    });
    mongoose.disconnect();
  });
