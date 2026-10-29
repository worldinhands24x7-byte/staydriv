const mongoose = require('mongoose');

const promotionSchema = new mongoose.Schema({
  promotionId: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  title: {
    type: String,
    required: true,
    trim: true
  },
  description: {
    type: String,
    default: '',
    trim: true
  },
  mediaType: {
    type: String,
    enum: ['image', 'gif', 'video'],
    default: 'image'
  },
  mediaUrl: {
    type: String,
    required: true,
    trim: true
  },
  thumbnailUrl: {
    type: String,
    default: '',
    trim: true
  },
  targetScreen: {
    type: String,
    enum: ['home', 'food', 'both'],
    default: 'both',
    index: true
  },
  destinationType: {
    type: String,
    enum: ['none', 'food_screen', 'restaurant', 'membership', 'ride_screen', 'parcel_screen', 'external_url', 'food', 'ride', 'parcel'],
    default: 'none'
  },
  destinationId: {
    type: String,
    default: '',
    trim: true
  },
  destinationUrl: {
    type: String,
    default: '',
    trim: true
  },
  offerText: {
    type: String,
    default: '',
    trim: true
  },
  buttonLabel: {
    type: String,
    default: '',
    trim: true
  },
  startAt: {
    type: Date,
    default: Date.now,
    index: true
  },
  endAt: {
    type: Date,
    default: null,
    index: true
  },
  displayOrder: {
    type: Number,
    default: 0,
    index: true
  },
  isActive: {
    type: Boolean,
    default: true,
    index: true
  },
  isDeleted: {
    type: Boolean,
    default: false,
    index: true
  },
  clicksCount: {
    type: Number,
    default: 0
  },
  impressionsCount: {
    type: Number,
    default: 0
  },
  createdBy: {
    type: String,
    default: 'admin'
  },
  createdAt: {
    type: Date,
    default: Date.now
  },
  updatedAt: {
    type: Date,
    default: Date.now
  },
  deletedAt: {
    type: Date,
    default: null
  }
});

promotionSchema.pre('save', function (next) {
  this.updatedAt = new Date();
  if (typeof next === 'function') next();
});

module.exports = mongoose.models.Promotion || mongoose.model('Promotion', promotionSchema);
