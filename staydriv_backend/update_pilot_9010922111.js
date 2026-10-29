const mongoose = require('mongoose');

async function run() {
  const mongoUri = process.env.MONGO_URI || 'mongodb://localhost:27017/staydriv';
  await mongoose.connect(mongoUri);
  console.log('Connected to MongoDB');

  const db = mongoose.connection.db;
  const usersColl = db.collection('users');

  // Time requested by user: 11:34 PM Today (Sep 30, 2026)
  // 11:34 PM IST = 23:34 IST = 18:04 UTC
  const submissionTime = new Date('2026-09-30T18:04:00.000Z');

  // Update or upsert 9010922111
  const updateResult = await usersColl.updateOne(
    { phone: '9010922111', role: 'partner' },
    {
      $set: {
        uid: 'mock_uid_9010922111_pilot',
        name: 'Pilot Partner',
        driverName: 'Pilot Partner',
        ownerName: 'Pilot Partner',
        phone: '9010922111',
        driverPhone: '9010922111',
        ownerPhone: '9010922111',
        role: 'partner',
        vehicleType: 'Bike',
        vehiclePlate: 'TS 09 SD 1234',
        vehicleNumber: 'TS 09 SD 1234',
        vehicleModel: 'Hero Splendor Plus',
        vehicleModelColor: 'Standard Bike',
        status: 'pending',
        approved: false,
        isApproved: false,
        isDocumentVerified: false,
        online: false,
        submittedAt: submissionTime,
        updatedAt: submissionTime,
        lastActive: submissionTime,
        aadhaarFront: '/uploads/sample_aadhaar_front.jpg',
        aadhaarBack: '/uploads/sample_aadhaar_back.jpg',
        panFront: '/uploads/sample_pan.jpg',
        rcFront: '/uploads/sample_rc_front.jpg',
        rcBack: '/uploads/sample_rc_back.jpg',
        licenseFront: '/uploads/sample_dl_front.jpg',
        licenseBack: '/uploads/sample_dl_back.jpg',
        photo: '/uploads/sample_pilot_photo.jpg',
        documents: {
          aadhaarFront: { url: '/uploads/sample_aadhaar_front.jpg', uploadedAt: submissionTime },
          aadhaarBack: { url: '/uploads/sample_aadhaar_back.jpg', uploadedAt: submissionTime },
          panFront: { url: '/uploads/sample_pan.jpg', uploadedAt: submissionTime },
          rcFront: { url: '/uploads/sample_rc_front.jpg', uploadedAt: submissionTime },
          rcBack: { url: '/uploads/sample_rc_back.jpg', uploadedAt: submissionTime },
          licenseFront: { url: '/uploads/sample_dl_front.jpg', uploadedAt: submissionTime },
          licenseBack: { url: '/uploads/sample_dl_back.jpg', uploadedAt: submissionTime },
          photo: { url: '/uploads/sample_pilot_photo.jpg', uploadedAt: submissionTime },
        }
      }
    },
    { upsert: true }
  );

  console.log('Updated 9010922111:', updateResult);

  const pilot = await usersColl.findOne({ phone: '9010922111', role: 'partner' });
  console.log('Verified pilot in DB:', {
    uid: pilot.uid,
    phone: pilot.phone,
    name: pilot.name,
    status: pilot.status,
    submittedAt: pilot.submittedAt,
    localTimeString: new Date(pilot.submittedAt).toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' })
  });

  await mongoose.disconnect();
}

run().catch(err => {
  console.error(err);
  process.exit(1);
});
