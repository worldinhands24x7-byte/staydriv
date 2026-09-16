const mongoose = require('mongoose');
const MONGO_URI = 'mongodb://127.0.0.1:27017/staydriv';

mongoose.connect(MONGO_URI)
  .then(async () => {
    console.log("Connected to MongoDB!");
    const User = mongoose.model('User', new mongoose.Schema({}, { strict: false }), 'users');

    const result = await User.updateMany({ role: 'partner' }, { approved: true });
    console.log(`Updated ${result.modifiedCount} partners to approved: true`);

    const users = await User.find({ role: 'partner' });
    console.log("\n=== PARTNERS STATUS ===");
    users.forEach(u => {
      console.log(`UID: ${u.get('uid')}, Phone: ${u.get('phone')}, Approved: ${u.get('approved')}, Online: ${u.get('online')}`);
    });

    mongoose.disconnect();
  })
  .catch(err => {
    console.error("Error:", err);
  });
