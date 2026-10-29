const mongoose = require('mongoose');

async function run() {
  await mongoose.connect('mongodb://127.0.0.1:27017/staydriv');
  const user = await mongoose.connection.db.collection('users').findOne({ uid: 'mock_uid_9490440281_pilot' });
  console.log('PILOT USER:', {
    uid: user?.uid,
    name: user?.name,
    phone: user?.phone,
    vehiclePlate: user?.vehiclePlate,
    vehicleNumber: user?.vehicleNumber,
    vehicleType: user?.vehicleType,
    vehicleModelColor: user?.vehicleModelColor,
    status: user?.status,
    approved: user?.approved
  });

  const bookings = await mongoose.connection.db.collection('bookings').find({
    $or: [
      { driverPhone: '9490440281' },
      { driverId: 'mock_uid_9490440281_pilot' },
      { driverName: 'pavan' }
    ]
  }).sort({ createdAt: -1 }).toArray();

  console.log('BOOKINGS COUNT:', bookings.length);
  bookings.forEach(b => console.log({
    bookingId: b.bookingId,
    status: b.status,
    driverName: b.driverName,
    driverPhone: b.driverPhone,
    driverId: b.driverId,
    vehiclePlate: b.vehiclePlate,
    vehicleModelColor: b.vehicleModelColor,
    createdAt: b.createdAt
  }));

  // Also check any other active/recent bookings
  const recentBookings = await mongoose.connection.db.collection('bookings').find({}).sort({ createdAt: -1 }).limit(5).toArray();
  console.log('RECENT 5 BOOKINGS IN DB:');
  recentBookings.forEach(b => console.log({
    bookingId: b.bookingId,
    status: b.status,
    driverName: b.driverName,
    driverPhone: b.driverPhone,
    vehiclePlate: b.vehiclePlate
  }));

  await mongoose.disconnect();
}

run().catch(err => {
  console.error(err);
  process.exit(1);
});
