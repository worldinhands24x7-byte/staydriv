const mongoose = require('mongoose');

async function findPavan() {
  await mongoose.connect('mongodb://127.0.0.1:27017/staydriv');
  const collection = mongoose.connection.db.collection('users');
  
  const users = await collection.find({
    $or: [
      { phone: /9490440281/ },
      { ownerPhone: /9490440281/ },
      { driverPhone: /9490440281/ },
      { name: /pavan/i },
      { applicationId: /3005|3OOS|0000/i }
    ]
  }).toArray();
  
  console.log(`Found ${users.length} users:`);
  for (const u of users) {
    console.log({
      _id: u._id,
      uid: u.uid,
      name: u.name,
      phone: u.phone,
      ownerPhone: u.ownerPhone,
      driverPhone: u.driverPhone,
      role: u.role,
      status: u.status,
      approved: u.approved,
      isApproved: u.isApproved,
      isBlocked: u.isBlocked,
      applicationId: u.applicationId,
      documents: u.documents ? Object.keys(u.documents) : null
    });
  }

  // Also check all pilots
  console.log('\n--- ALL PILOTS IN DATABASE ---');
  const allPilots = await collection.find({ role: { $in: ['partner', 'driver'] } }).toArray();
  console.log(`Total pilots: ${allPilots.length}`);
  for (const p of allPilots) {
    console.log({
      _id: p._id,
      uid: p.uid,
      name: p.name,
      phone: p.phone,
      status: p.status,
      approved: p.approved,
      isApproved: p.isApproved,
      isBlocked: p.isBlocked,
      applicationId: p.applicationId
    });
  }

  await mongoose.disconnect();
}

findPavan().catch(err => {
  console.error(err);
  process.exit(1);
});
