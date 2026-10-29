const mongoose = require('mongoose');

const notificationCampaignSchema = new mongoose.Schema({
  campaignId: { 
    type: String, 
    required: true, 
    unique: true, 
    index: true 
  },
  title: { 
    type: String, 
    required: true 
  },
  body: { 
    type: String, 
    required: true 
  },
  targetGroup: { 
    type: String, 
    enum: ['all', 'customers', 'partners', 'restaurants', 'selected'], 
    default: 'all',
    index: true 
  },
  type: { 
    type: String, 
    enum: ['push', 'promo', 'alert', 'emergency'], 
    default: 'push' 
  },
  adminEmail: { 
    type: String, 
    default: 'admin@staydriv.com' 
  },
  adminName: { 
    type: String, 
    default: 'Super Admin' 
  },
  ipAddress: { 
    type: String, 
    default: '127.0.0.1' 
  },
  status: { 
    type: String, 
    enum: ['sent', 'partial', 'failed', 'sending', 'fcm_accepted', 'in_app_delivered'], 
    default: 'sent' 
  },
  totalEligible: { 
    type: Number, 
    default: 0 
  },
  successCount: { 
    type: Number, 
    default: 0 
  },
  failureCount: { 
    type: Number, 
    default: 0 
  },
  sentAt: { 
    type: Date, 
    default: Date.now,
    index: true 
  },
  deliveryStats: {
    delivered: { type: Number, default: 0 },
    opened: { type: Number, default: 0 }
  },
  metadata: { 
    type: mongoose.Schema.Types.Mixed, 
    default: {} 
  }
}, { 
  timestamps: true 
});

module.exports = mongoose.models.NotificationCampaign || mongoose.model('NotificationCampaign', notificationCampaignSchema);
