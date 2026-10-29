const mongoose = require('mongoose');

async function fixPavanLocal() {
  await mongoose.connect('mongodb://127.0.0.1:27017/staydriv');
  const collection = mongoose.connection.db.collection('users');

  // Update or insert pavan with the exact Application ID from Screenshot 1 & 2
  const pavanData = {
    uid: 'mock_uid_9490440281_pilot',
    name: 'pavan',
    driverName: 'pavan',
    ownerName: 'pavan',
    phone: '9490440281',
    driverPhone: '9490440281',
    ownerPhone: '9490440281',
    role: 'partner',
    vehicleType: 'Bike',
    vehiclePlate: 'TS 09 SD 1234',
    vehicleNumber: 'TS 09 SD 1234',
    vehicleModelColor: 'Black Bike',
    vehicleModel: 'Black Bike',
    status: 'PENDING_VERIFICATION',
    approved: false,
    isApproved: false,
    isBlocked: false,
    online: false,
    applicationId: 'SD-PLT-0000-3OOS',
    submittedAt: new Date(),
    updatedAt: new Date(),
    documents: {
      aadhaarFront: {
        url: 'https://dk60tgl9yds4p.cloudfront.net/api/files/6abee175e22b69e8431dc271',
        status: 'PENDING',
        uploadedAt: new Date()
      },
      aadhaarBack: {
        url: 'https://dk60tgl9yds4p.cloudfront.net/api/files/6abee175e22b69e8431dc276',
        status: 'PENDING',
        uploadedAt: new Date()
      },
      panFront: {
        url: 'https://dk60tgl9yds4p.cloudfront.net/api/files/6abee175e22b69e8431dc27b',
        status: 'PENDING',
        uploadedAt: new Date()
      },
      panBack: {
        url: 'https://dk60tgl9yds4p.cloudfront.net/api/files/6abee175e22b69e8431dc27d',
        status: 'PENDING',
        uploadedAt: new Date()
      },
      rcFront: {
        url: 'https://dk60tgl9yds4p.cloudfront.net/api/files/6abee175e22b69e8431dc27f',
        status: 'PENDING',
        uploadedAt: new Date()
      },
      rcBack: {
        url: 'https://dk60tgl9yds4p.cloudfront.net/api/files/6abee176e22b69e8431dc284',
        status: 'PENDING',
        uploadedAt: new Date()
      },
      licenseFront: {
        url: 'https://dk60tgl9yds4p.cloudfront.net/api/files/6abee176e22b69e8431dc289',
        status: 'PENDING',
        uploadedAt: new Date()
      },
      licenseBack: {
        url: 'https://dk60tgl9yds4p.cloudfront.net/api/files/6abee176e22b69e8431dc28e',
        status: 'PENDING',
        uploadedAt: new Date()
      },
      photo: {
        url: 'https://dk60tgl9yds4p.cloudfront.net/api/files/6abee176e22b69e8431dc293',
        status: 'PENDING',
        uploadedAt: new Date()
      }
    },
    verificationHistory: [],
    correctionNotes: '',
    rejectionReason: '',
    aadhaarFront: 'https://dk60tgl9yds4p.cloudfront.net/api/files/6abee175e22b69e8431dc271',
    aadhaarBack: 'https://dk60tgl9yds4p.cloudfront.net/api/files/6abee175e22b69e8431dc276',
    panFront: 'https://dk60tgl9yds4p.cloudfront.net/api/files/6abee175e22b69e8431dc27b',
    panBack: 'https://dk60tgl9yds4p.cloudfront.net/api/files/6abee175e22b69e8431dc27d',
    rcFront: 'https://dk60tgl9yds4p.cloudfront.net/api/files/6abee175e22b69e8431dc27f',
    rcBack: 'https://dk60tgl9yds4p.cloudfront.net/api/files/6abee176e22b69e8431dc284',
    licenseFront: 'https://dk60tgl9yds4p.cloudfront.net/api/files/6abee176e22b69e8431dc289',
    licenseBack: 'https://dk60tgl9yds4p.cloudfront.net/api/files/6abee176e22b69e8431dc28e',
    photo: 'https://dk60tgl9yds4p.cloudfront.net/api/files/6abee176e22b69e8431dc293'
  };

  // Update existing pilot record for 9490440281
  const res = await collection.updateOne(
    { uid: 'mock_uid_9490440281_pilot' },
    { $set: pavanData },
    { upsert: true }
  );

  console.log('Local MongoDB updated for Pavan:', res);

  // Verify
  const user = await collection.findOne({ uid: 'mock_uid_9490440281_pilot' });
  console.log('Verified user in local DB:', {
    name: user.name,
    phone: user.phone,
    role: user.role,
    status: user.status,
    applicationId: user.applicationId,
    approved: user.approved
  });

  await mongoose.disconnect();
}

fixPavanLocal().catch(console.error);
