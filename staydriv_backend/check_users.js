const mongoose = require('mongoose');
const MONGO_URI = 'mongodb://127.0.0.1:27017/staydriv';

mongoose.connect(MONGO_URI)
  .then(async () => {
    const User = mongoose.model('User', new mongoose.Schema({}, { strict: false }), 'users');
    const users = await User.find();
    console.log(`=== ALL USERS (${users.length}) ===`);
    users.forEach(u => {
      console.log({
        uid: u.get('uid'),
        name: u.get('name'),
        phone: u.get('phone'),
        role: u.get('role'),
        online: u.get('online'),
        approved: u.get('approved'),
        vehicleType: u.get('vehicleType'),
        lat: u.get('lat'),
        lng: u.get('lng')
      });
    });
    mongoose.disconnect();
  });
