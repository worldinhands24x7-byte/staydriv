const mongoose = require('mongoose');

async function runCleanup() {
  await mongoose.connect('mongodb://127.0.0.1:27017/staydriv');
  console.log('Connected to MongoDB staydriv for safe cleanup...');

  const db = mongoose.connection.db;

  // 1. Identify and delete confirmed dummy users
  const dummyUserQuery = {
    $or: [
      { uid: { $regex: /^sim_/ } },
      { uid: { $regex: /^pilot_prod_test/ } },
      { phone: { $regex: /^9900000/ } },
      { phone: '9999999999' },
      { phone: '9111111111' },
      { phone: '9222222222' },
      { phone: '9333333333' },
      { phone: '9444444444' },
      { phone: '9988776655' },
      { uid: 'user_9999999999' },
      { uid: 'mock_uid_9999999999' }
    ]
  };

  const usersToDelete = await db.collection('users').find(dummyUserQuery).toArray();
  console.log(`Found ${usersToDelete.length} confirmed dummy users to remove:`);
  usersToDelete.forEach(u => console.log(`  - [${u.role}] ${u.name} (${u.phone}) UID: ${u.uid}`));

  const delUsersResult = await db.collection('users').deleteMany(dummyUserQuery);
  console.log(`Removed ${delUsersResult.deletedCount} dummy users.`);

  // 2. Remove confirmed dummy bookings
  const dummyBookingQuery = {
    $or: [
      { bookingId: { $regex: /^BK_SIM_/ } },
      { passengerId: 'sim_customer' },
      { passengerPhone: { $in: ['9999999999', '9111111111', '9222222222', '9333333333', '9444444444', '9988776655'] } },
      { driverPhone: { $in: ['9999999999', '9111111111', '9222222222', '9333333333', '9444444444', '9988776655'] } }
    ]
  };
  const delBookingsResult = await db.collection('bookings').deleteMany(dummyBookingQuery);
  console.log(`Removed ${delBookingsResult.deletedCount} dummy bookings.`);

  // 3. Remove confirmed dummy complaints and refunds
  const delComplaintsResult = await db.collection('complaints').deleteMany({
    complaintId: { $in: ['CMP-104821', 'CMP-104822', 'CMP-104823'] }
  });
  console.log(`Removed ${delComplaintsResult.deletedCount} dummy complaints.`);

  const delRefundsResult = await db.collection('refunds').deleteMany({
    refundId: { $in: ['REF-801201', 'REF-801202', 'REF-801203'] }
  });
  console.log(`Removed ${delRefundsResult.deletedCount} dummy refunds.`);

  // 4. Update genuine pilot accounts to ensure clean PENDING_VERIFICATION state and application IDs
  const genuinePilots = await db.collection('users').find({ role: { $in: ['partner', 'driver'] } }).toArray();
  console.log(`\nStructuring ${genuinePilots.length} genuine pilot applications with proper IDs and PENDING_VERIFICATION state:`);

  for (const pilot of genuinePilots) {
    const phone = pilot.phone || '9010922111';
    const appId = pilot.applicationId || `SD-PLT-${phone.slice(-4)}-${pilot._id.toString().slice(-4).toUpperCase()}`;

    // Build structured documents map with verification state
    const docs = pilot.documents || {};
    const docFields = [
      ['aadhaarFront', pilot.aadhaarFront],
      ['aadhaarBack', pilot.aadhaarBack],
      ['panFront', pilot.panFront],
      ['panBack', pilot.panBack],
      ['rcFront', pilot.rcFront],
      ['rcBack', pilot.rcBack],
      ['licenseFront', pilot.licenseFront],
      ['licenseBack', pilot.licenseBack],
      ['photo', pilot.photo],
      ['fitness', pilot.fitness],
      ['permit', pilot.permit]
    ];

    docFields.forEach(([key, val]) => {
      if (val) {
        if (!docs[key] || typeof docs[key] === 'string') {
          docs[key] = { url: typeof docs[key] === 'string' ? docs[key] : val, status: 'PENDING', uploadedAt: new Date() };
        } else if (!docs[key].status) {
          docs[key].status = 'PENDING';
        }
      }
    });

    await db.collection('users').updateOne(
      { _id: pilot._id },
      {
        $set: {
          applicationId: appId,
          status: 'PENDING_VERIFICATION',
          approved: false,
          isApproved: false,
          isDocumentVerified: false,
          online: false,
          documents: docs,
          updatedAt: new Date()
        }
      }
    );

    console.log(`  ✓ Updated Pilot: ${pilot.name} (${phone}) -> App ID: ${appId} [Status: PENDING_VERIFICATION]`);
  }

  const remainingUsers = await db.collection('users').countDocuments();
  const remainingBookings = await db.collection('bookings').countDocuments();
  const remainingComplaints = await db.collection('complaints').countDocuments();
  const remainingRefunds = await db.collection('refunds').countDocuments();

  console.log('\n=== CLEANUP SUMMARY ===');
  console.log(`Total Genuine Users Preserved: ${remainingUsers}`);
  console.log(`Total Genuine Bookings Preserved: ${remainingBookings}`);
  console.log(`Complaints Remaining: ${remainingComplaints} (Clean empty state)`);
  console.log(`Refunds Remaining: ${remainingRefunds} (Clean empty state)`);

  process.exit(0);
}

runCleanup().catch(err => {
  console.error('Cleanup error:', err);
  process.exit(1);
});
