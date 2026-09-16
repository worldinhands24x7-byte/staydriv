const mongoose = require('mongoose');
const MONGO_URI = 'mongodb://127.0.0.1:27017/staydriv';

mongoose.connect(MONGO_URI)
  .then(async () => {
    console.log("Connected to MongoDB!");
    const User = mongoose.model('User', new mongoose.Schema({}, { strict: false }), 'users');
    const Booking = mongoose.model('Booking', new mongoose.Schema({}, { strict: false }), 'bookings');

    // 1. Delete or reset all bookings
    const bookingsResult = await Booking.deleteMany({});
    console.log(`Deleted ${bookingsResult.deletedCount} bookings`);

    // 2. Set all partners to offline but approved
    const usersResult = await User.updateMany({ role: 'partner' }, { online: false, approved: true });
    console.log(`Reset ${usersResult.modifiedCount} partners to offline and approved: true`);

    // 3. Set all customers to online: false
    const customersResult = await User.updateMany({ role: 'customer' }, { online: false });
    console.log(`Reset ${customersResult.modifiedCount} customers to offline`);

    mongoose.disconnect();
  })
  .catch(err => {
    console.error("Error:", err);
  });
