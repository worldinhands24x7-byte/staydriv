const mongoose = require('mongoose');

const inAppNotificationSchema = new mongoose.Schema({
  notificationId: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  campaignId: {
    type: String,
    index: true,
    default: null
  },
  title: {
    type: String,
    required: true,
    trim: true
  },
  body: {
    type: String,
    required: true,
    trim: true
  },
  type: {
    type: String,
    enum: ['push', 'promo', 'alert', 'emergency'],
    default: 'push'
  },
  targetGroup: {
    type: String,
    enum: ['all', 'customers', 'partners', 'restaurants', 'selected'],
    default: 'all',
    index: true
  },
  destination: {
    type: { type: String, default: 'none' },
    screen: { type: String, default: '' },
    id: { type: String, default: '' },
    url: { type: String, default: '' }
  },
  readBy: [{
    phone: { type: String, index: true },
    uid: { type: String, index: true },
    readAt: { type: Date, default: Date.now }
  }],
  adminEmail: {
    type: String,
    default: 'admin@staydriv.com'
  },
  metadata: {
    type: mongoose.Schema.Types.Mixed,
    default: {}
  },
  createdAt: {
    type: Date,
    default: Date.now,
    index: true
  }
});

// Helper method to check if read by user
inAppNotificationSchema.methods.isReadBy = function(phone, uid) {
  if (!this.readBy || this.readBy.length === 0) return false;
  return this.readBy.some(r => 
    (phone && r.phone === phone) || 
    (uid && r.uid === uid)
  );
};

module.exports = mongoose.model('InAppNotification', inAppNotificationSchema);
