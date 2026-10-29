const mongoose = require('mongoose');

const deviceTokenSchema = new mongoose.Schema({
  token: { 
    type: String, 
    required: true, 
    unique: true, 
    index: true 
  },
  uid: { 
    type: String, 
    index: true 
  },
  phone: { 
    type: String, 
    index: true 
  },
  role: { 
    type: String, 
    enum: ['customer', 'partner', 'restaurant', 'admin', 'unknown'], 
    default: 'customer',
    index: true
  },
  platform: { 
    type: String, 
    enum: ['android', 'ios', 'web'], 
    default: 'android' 
  },
  appType: { 
    type: String, 
    default: 'staydriv_combined' 
  },
  topics: { 
    type: [String], 
    default: ['all'] 
  },
  isActive: { 
    type: Boolean, 
    default: true,
    index: true
  },
  lastSeenAt: { 
    type: Date, 
    default: Date.now 
  }
}, { 
  timestamps: true 
});

module.exports = mongoose.models.DeviceToken || mongoose.model('DeviceToken', deviceTokenSchema);
