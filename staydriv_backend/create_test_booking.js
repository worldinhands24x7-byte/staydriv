const mongoose = require('mongoose');
const MONGO_URI = 'mongodb://127.0.0.1:27017/staydriv';

mongoose.connect(MONGO_URI)
  .then(async () => {
    const Booking = mongoose.model('Booking', new mongoose.Schema({}, { strict: false }), 'bookings');

    const bookingId = 'BK_TEST_' + Date.now();
    const newBooking = new Booking({
      bookingId,
      pickup: 'Kukatpally Housing Board Colony, Hyderabad',
      drop: 'Secunderabad Railway Station, Hyderabad',
      pickupLatLng: { lat: 17.5264942, lng: 78.4240839 }, // Right near the active pilot!
      dropLatLng: { lat: 17.5000, lng: 78.4000 },
      vehicle: 'Bike',
      price: '₹120',
      otp: '1234',
      status: 'searching',
      passengerId: 'mock_uid_customer_test',
      passengerName: 'Jane Doe (Test)',
      driverId: '',
      declinedDrivers: [],
      createdAt: new Date()
    });

    await newBooking.save();
    console.log('Successfully created test booking:', bookingId);
    console.log('Pickup:', newBooking.pickup);
    console.log('Coordinates:', newBooking.pickupLatLng);
    console.log('Wait for the pilot app to receive the booking...');
    
    mongoose.disconnect();
  })
  .catch(err => {
    console.error('Error creating booking:', err);
    mongoose.disconnect();
  });
