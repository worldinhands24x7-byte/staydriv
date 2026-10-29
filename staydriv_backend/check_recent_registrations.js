const mongoose = require('mongoose');
const MONGO_URI = 'mongodb://127.0.0.1:27017/staydriv';

mongoose.connect(MONGO_URI).then(async () => {
  const User = mongoose.model('User', new mongoose.Schema({}, { strict: false }), 'users');
  const users = await User.find({ role: 'partner' }).sort({ updatedAt: -1, createdAt: -1 });
  console.log(`=== FOUND ${users.length} PARTNERS ===`);
  users.forEach((u, i) => {
    console.log(`\n[#${i + 1}] UID: ${u.get('uid')} | Name: ${u.get('name')} | Phone: ${u.get('phone')}`);
    console.log(`     Status: ${u.get('status')} | Approved: ${u.get('approved')} | isApproved: ${u.get('isApproved')}`);
    console.log(`     Vehicle: ${u.get('vehicleType')} | Plate: ${u.get('vehiclePlate')}`);
    console.log(`     Created: ${u.get('createdAt')} | Updated: ${u.get('updatedAt')} | LastActive: ${u.get('lastActive')}`);
    console.log(`     Documents:`, u.get('documents') ? Object.keys(u.get('documents')) : 'none');
  });
  mongoose.disconnect();
}).catch(console.error);
