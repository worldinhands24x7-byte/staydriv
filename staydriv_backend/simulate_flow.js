const mongoose = require('mongoose');
const MONGO_URI = 'mongodb://127.0.0.1:27017/staydriv';

mongoose.connect(MONGO_URI)
  .then(async () => {
    const User = mongoose.model('User', new mongoose.Schema({}, { strict: false }), 'users');
    const Booking = mongoose.model('Booking', new mongoose.Schema({}, { strict: false }), 'bookings');

    console.log('Cleaning up database for simulation...');
    await User.deleteMany({ uid: { $in: ['sim_pilot_idle', 'sim_pilot_busy', 'sim_customer'] } });
    await Booking.deleteMany({ passengerId: 'sim_customer' });

    console.log('Inserting test users...');
    // Create customer in Bangalore
    const customer = new User({
      uid: 'sim_customer',
      name: 'Sim Customer',
      role: 'customer',
      lat: 12.9716,
      lng: 77.5946,
      online: true,
      approved: true
    });
    await customer.save();

    // Create a busy pilot in Bangalore (closer to the customer)
    const busyPilot = new User({
      uid: 'sim_pilot_busy',
      name: 'Sim Busy Pilot',
      role: 'partner',
      vehicleType: 'Bike',
      lat: 12.9720, // Very close to customer (40m)
      lng: 77.5950,
      online: true,
      approved: true,
      lastActive: new Date()
    });
    await busyPilot.save();

    // Create an active, idle pilot in Bangalore (further away)
    const idlePilot = new User({
      uid: 'sim_pilot_idle',
      name: 'Sim Idle Pilot',
      role: 'partner',
      vehicleType: 'Bike',
      lat: 12.9800, // Further away (~1km)
      lng: 77.6000,
      online: true,
      approved: true,
      lastActive: new Date()
    });
    await idlePilot.save();

    // Make the close pilot busy by assigning them to a completed/active booking
    const busyBooking = new Booking({
      bookingId: 'BK_SIM_BUSY',
      pickup: 'Pickup',
      drop: 'Drop',
      vehicle: 'Bike',
      status: 'accepted', // Busy status!
      passengerId: 'other_customer',
      driverId: 'sim_pilot_busy',
      createdAt: new Date()
    });
    await busyBooking.save();

    console.log('Creating a new searching booking for Sim Customer...');
    const newBooking = new Booking({
      bookingId: 'BK_SIM_NEW',
      pickup: 'Pickup 2',
      drop: 'Drop 2',
      pickupLatLng: { lat: 12.9716, lng: 77.5946 },
      dropLatLng: { lat: 12.9816, lng: 77.6046 },
      vehicle: 'Bike',
      status: 'searching',
      passengerId: 'sim_customer',
      driverId: '',
      createdAt: new Date()
    });
    await newBooking.save();

    // Now, simulate the idle pilot polling for bookings.
    // We will call the backend API or simulate it. Let's make an HTTP request to our server!
    console.log('Simulating available bookings polling for Sim Idle Pilot...');
    const http = require('http');
    const url = 'http://localhost:3000/api/booking/available?vehicleType=Bike&driverId=sim_pilot_idle&lat=12.9800&lng=77.6000';
    
    http.get(url, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', async () => {
        const result = JSON.parse(data);
        console.log('API Response status code:', res.statusCode);
        console.log('Available bookings returned for Idle Pilot:', result.bookings);

        // Verify if the booking BK_SIM_NEW was assigned to sim_pilot_idle
        const updatedBooking = await Booking.findOne({ bookingId: 'BK_SIM_NEW' });
        console.log('=== MATCHING VERIFICATION ===');
        console.log('Assigned Driver ID:', updatedBooking.driverId);
        console.log('Booking Status:', updatedBooking.status);

        if (updatedBooking.driverId === 'sim_pilot_idle') {
          console.log('SUCCESS: Booking successfully matched to the idle pilot, ignoring the closer busy pilot!');
        } else {
          console.log('FAILURE: Booking not matched to the idle pilot!');
        }

        // Clean up
        await User.deleteMany({ uid: { $in: ['sim_pilot_idle', 'sim_pilot_busy', 'sim_customer'] } });
        await Booking.deleteMany({ passengerId: 'sim_customer' });
        await Booking.deleteMany({ bookingId: 'BK_SIM_BUSY' });
        mongoose.disconnect();
      });
    });
  })
  .catch(err => {
    console.error('Simulation error:', err);
    mongoose.disconnect();
  });
