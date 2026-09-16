const mongoose = require('mongoose');
const dotenv = require('dotenv');
dotenv.config();

const mongoUri = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/staydriv';

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
    const User = mongoose.model('User2', userSchema, 'users');

    const bookingSchema = new mongoose.Schema({
      bookingId: String,
      pickup: String,
      drop: String,
      vehicle: String,
      status: String,
      pickupLatLng: mongoose.Schema.Types.Mixed,
      dropLatLng: mongoose.Schema.Types.Mixed,
      driverId: String,
      declinedDrivers: [String]
    });
    const Booking = mongoose.model('Booking2', bookingSchema, 'bookings');

    const booking = await Booking.findOne({ bookingId: 'BK_1782657270249' });
    console.log('Booking details:', booking);

    const driver = await User.findOne({ uid: 'mock_uid_9247535068_pilot' });
    console.log('Driver details:', driver);

    process.exit(0);
  })
  .catch(err => {
    console.error('Error:', err);
    process.exit(1);
  });
