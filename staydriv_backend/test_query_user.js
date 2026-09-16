const mongoose = require('mongoose');
const dotenv = require('dotenv');
dotenv.config();

const mongoUri = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/staydriv';

mongoose.connect(mongoUri)
  .then(async () => {
    const userSchema = new mongoose.Schema({}, { strict: false });
    const User = mongoose.model('User5', userSchema, 'users');
    const user = await User.findOne({ uid: 'mock_uid_9247535068_pilot' });
    console.log('Driver user details:', user);
    process.exit(0);
  });
