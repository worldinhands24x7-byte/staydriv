const mongoose = require('mongoose');

async function run() {
  await mongoose.connect('mongodb://127.0.0.1:27017/staydriv');
  console.log('Connected to MongoDB');

  const usersCol = mongoose.connection.collection('users');
  const bookingsCol = mongoose.connection.collection('bookings');

  // Update user for Pavan
  const userResult = await usersCol.updateMany(
    { phone: '9490440281' },
    {
      $set: {
        vehiclePlate: 'AP 07 AX 6057',
        vehicleNumber: 'AP 07 AX 6057'
      }
    }
  );
  console.log('Users updated:', userResult.matchedCount, userResult.modifiedCount);

  // Update bookings for Pavan
  const bookingResult = await bookingsCol.updateMany(
    {
      $or: [
        { driverPhone: '9490440281' },
        { driverId: /9490440281/ },
        { driverName: /pavan/i }
      ]
    },
    {
      $set: {
        vehiclePlate: 'AP 07 AX 6057',
        vehicleNumber: 'AP 07 AX 6057'
      }
    }
  );
  console.log('Bookings updated:', bookingResult.matchedCount, bookingResult.modifiedCount);

  const updatedUsers = await usersCol.find({ phone: '9490440281' }).toArray();
  console.log('Updated Users:', updatedUsers.map(u => ({ uid: u.uid, name: u.name, phone: u.phone, role: u.role, vehiclePlate: u.vehiclePlate, vehicleNumber: u.vehicleNumber })));

  const updatedBookings = await bookingsCol.find({
    $or: [
      { driverPhone: '9490440281' },
      { driverId: /9490440281/ },
      { driverName: /pavan/i }
    ]
  }).sort({ createdAt: -1 }).limit(3).toArray();
  console.log('Updated Recent Bookings:', updatedBookings.map(b => ({ bookingId: b.bookingId, status: b.status, driverName: b.driverName, driverPhone: b.driverPhone, vehiclePlate: b.vehiclePlate })));

  await mongoose.disconnect();
}

run().catch(err => {
  console.error(err);
  process.exit(1);
});
