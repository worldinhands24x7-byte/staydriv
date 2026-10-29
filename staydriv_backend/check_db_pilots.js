const mongoose = require('mongoose');

async function check() {
  const uri = process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/staydriv';
  try {
    await mongoose.connect(uri, { serverSelectionTimeoutMS: 2000 });
    const User = mongoose.model('User', new mongoose.Schema({}, { strict: false }));
    const users = await User.find({}).lean();
    console.log(`Total users in DB: ${users.length}`);
    users.forEach(u => {
      console.log(`_id: ${u._id}, Phone: ${u.phone}, UID: ${u.uid}, Name: ${u.name}, Role: ${u.role}, Status: ${u.status}, Blocked: ${u.isBlocked}, AdminBooking: ${u.adminBookingEnabled}, BookingAccess: ${JSON.stringify(u.bookingAccess)}, DailyPlan: ${JSON.stringify(u.dailyPlan)}`);
    });
    await mongoose.disconnect();
  } catch (err) {
    console.log('MongoDB connection error:', err.message);
  }
}
check();
