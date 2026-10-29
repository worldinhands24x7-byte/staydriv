const mongoose = require('mongoose');

const restaurantSchema = new mongoose.Schema({
  restaurantId: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  name: {
    type: String,
    required: true,
    trim: true,
    index: true
  },
  ownerName: {
    type: String,
    default: ''
  },
  phone: {
    type: String,
    required: true,
    index: true
  },
  email: {
    type: String,
    default: ''
  },
  address: {
    type: String,
    required: true
  },
  lat: {
    type: Number,
    required: true
  },
  lng: {
    type: Number,
    required: true
  },
  locationDetails: {
    type: String,
    default: ''
  },
  cuisines: {
    type: [String],
    default: []
  },
  categories: {
    type: [String],
    default: ['Biryani', 'South Indian', 'North Indian', 'Pizza', 'Burgers', 'Chinese', 'Snacks', 'Desserts']
  },
  rating: {
    type: Number,
    default: 4.5
  },
  ratingCount: {
    type: Number,
    default: 120
  },
  deliveryTime: {
    type: String,
    default: '25-35 mins'
  },
  deliveryFee: {
    type: Number,
    default: 30
  },
  minimumOrder: {
    type: Number,
    default: 100
  },
  isVegOnly: {
    type: Boolean,
    default: false
  },
  isOpen: {
    type: Boolean,
    default: true
  },
  openingHours: {
    type: String,
    default: '10:00 AM - 11:30 PM'
  },
  imageUrl: {
    type: String,
    default: 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=800&auto=format&fit=crop&q=80'
  },
  fssaiNumber: {
    type: String,
    default: ''
  },
  fssaiDocUrl: {
    type: String,
    default: ''
  },
  fssaiValidity: {
    type: String,
    default: ''
  },
  gstNumber: {
    type: String,
    default: ''
  },
  gstDocUrl: {
    type: String,
    default: ''
  },
  panNumber: {
    type: String,
    default: ''
  },
  panDocUrl: {
    type: String,
    default: ''
  },
  bankAccount: {
    type: String,
    default: ''
  },
  bankAccountMasked: {
    type: String,
    default: ''
  },
  bankIfsc: {
    type: String,
    default: ''
  },
  bankHolderName: {
    type: String,
    default: ''
  },
  bankName: {
    type: String,
    default: ''
  },
  accountType: {
    type: String,
    enum: ['Savings', 'Current', 'savings', 'current'],
    default: 'Current'
  },
  registeredMobile: {
    type: String,
    default: ''
  },
  paymentPreference: {
    type: String,
    enum: ['bank_transfer', 'upi'],
    default: 'bank_transfer'
  },
  upiId: {
    type: String,
    default: ''
  },
  bankVerificationStatus: {
    type: String,
    enum: ['unverified', 'pending_verification', 'verified', 'rejected'],
    default: 'unverified',
    index: true
  },
  bankVerifiedAt: {
    type: Date
  },
  bankVerifiedBy: {
    type: String,
    default: ''
  },
  bankRejectionReason: {
    type: String,
    default: ''
  },
  bankAuditLog: [
    {
      action: { type: String, required: true },
      updatedBy: { type: String, default: 'partner' },
      maskedAccount: { type: String, default: '' },
      timestamp: { type: Date, default: Date.now },
      notes: { type: String, default: '' }
    }
  ],
  status: {
    type: String,
    enum: ['pending', 'approved', 'rejected', 'suspended', 'action_required'],
    default: 'pending',
    index: true
  },
  rejectionReason: {
    type: String,
    default: ''
  },
  actionRequiredNotes: {
    type: String,
    default: ''
  },
  approvedBy: {
    type: String,
    default: ''
  },
  approvedAt: {
    type: Date
  },
  rejectedBy: {
    type: String,
    default: ''
  },
  rejectedAt: {
    type: Date
  },
  reviewedBy: {
    type: String,
    default: ''
  },
  reviewDate: {
    type: Date
  },
  reviewHistory: [
    {
      action: { type: String },
      adminName: { type: String, default: 'Admin' },
      adminId: { type: String, default: '' },
      notes: { type: String, default: '' },
      timestamp: { type: Date, default: Date.now }
    }
  ],
  commissionRate: {
    type: Number,
    default: 15.0 // Platform fee percentage
  },
  isMembershipEnrolled: {
    type: Boolean,
    default: true,
    index: true
  },
  membershipDiscountPercent: {
    type: Number,
    default: 0 // 0 means use global membership plan discount
  },
  membershipFundingType: {
    type: String,
    enum: ['staydriv', 'restaurant', 'split'],
    default: 'staydriv'
  },
  membershipSplitRatio: {
    staydrivPercent: { type: Number, default: 100 },
    restaurantPercent: { type: Number, default: 0 }
  },
  totalEarnings: {
    type: Number,
    default: 0
  },
  settledEarnings: {
    type: Number,
    default: 0
  },
  totalSettled: {
    type: Number,
    default: 0
  },
  pendingSettlement: {
    type: Number,
    default: 0
  },
  createdAt: {
    type: Date,
    default: Date.now
  },
  updatedAt: {
    type: Date,
    default: Date.now
  }
});

restaurantSchema.pre('save', function (next) {
  this.updatedAt = new Date();
  if (typeof next === 'function') next();
});

module.exports = mongoose.models.Restaurant || mongoose.model('Restaurant', restaurantSchema);
