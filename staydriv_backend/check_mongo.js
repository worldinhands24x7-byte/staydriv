const mongoose = require('mongoose');

const MONGO_URI = 'mongodb://127.0.0.1:27017/staydriv';

mongoose.connect(MONGO_URI)
  .then(async () => {
    console.log("Connected to MongoDB!");
    
    const User = mongoose.model('User', new mongoose.Schema({}, { strict: false }), 'users');
    const Booking = mongoose.model('Booking', new mongoose.Schema({}, { strict: false }), 'bookings');

    const users = await User.find();
    console.log(`\n=== USERS (${users.length}) ===`);
    users.forEach(u => {
      console.log(`UID: ${u.get('uid')}, Name: ${u.get('name')}, Phone: ${u.get('phone')}, Role: ${u.get('role')}, Online: ${u.get('online')}, Vehicle: ${u.get('vehicleType')}, Lat: ${u.get('lat')}, Lng: ${u.get('lng')}`);
    });

    const bookings = await Booking.find();
    console.log(`\n=== BOOKINGS (${bookings.length}) ===`);
    bookings.forEach(b => {
      console.log(`ID: ${b.get('bookingId')}, Status: ${b.get('status')}, Vehicle: ${b.get('vehicle')}, DriverId: ${b.get('driverId')}, PassengerId: ${b.get('passengerId')}, PickupLatLng:`, b.get('pickupLatLng'));
    });

    mongoose.disconnect();
  })
  .catch(err => {
    console.error("Error:", err);
  });
