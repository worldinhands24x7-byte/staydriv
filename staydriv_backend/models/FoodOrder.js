const mongoose = require('mongoose');

const orderItemSchema = new mongoose.Schema({
  itemId: {
    type: String,
    required: true
  },
  name: {
    type: String,
    required: true
  },
  price: {
    type: Number,
    required: true
  },
  quantity: {
    type: Number,
    required: true,
    min: 1
  },
  isVeg: {
    type: Boolean,
    default: false
  },
  customization: {
    type: String,
    default: ''
  }
}, { _id: false });

const statusHistorySchema = new mongoose.Schema({
  status: {
    type: String,
    required: true
  },
  timestamp: {
    type: Date,
    default: Date.now
  },
  note: {
    type: String,
    default: ''
  },
  updatedBy: {
    type: String,
    default: 'system'
  }
}, { _id: false });

const foodOrderSchema = new mongoose.Schema({
  orderId: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  customerId: {
    type: String,
    required: true,
    index: true
  },
  customerName: {
    type: String,
    required: true
  },
  customerPhone: {
    type: String,
    required: true,
    index: true
  },
  deliveryAddress: {
    type: String,
    required: true
  },
  deliveryLatLng: {
    lat: { type: Number, default: 0 },
    lng: { type: Number, default: 0 }
  },
  deliveryLat: { type: Number, default: 0 },
  deliveryLng: { type: Number, default: 0 },
  deliveryInstructions: {
    type: String,
    default: ''
  },
  restaurantId: {
    type: String,
    required: true,
    index: true
  },
  restaurantName: {
    type: String,
    required: true
  },
  restaurantPhone: {
    type: String,
    default: ''
  },
  restaurantAddress: {
    type: String,
    default: ''
  },
  restaurantLatLng: {
    lat: { type: Number, default: 0 },
    lng: { type: Number, default: 0 }
  },
  restaurantLat: { type: Number, default: 0 },
  restaurantLng: { type: Number, default: 0 },
  restaurantLocationDetails: {
    type: String,
    default: ''
  },
  items: {
    type: [orderItemSchema],
    required: true,
    validate: [v => Array.isArray(v) && v.length > 0, 'Order must contain at least one item']
  },
  subtotal: {
    type: Number,
    required: true,
    min: 0
  },
  packagingFee: {
    type: Number,
    default: 0
  },
  deliveryFee: {
    type: Number,
    default: 30
  },
  baseDeliveryFee: {
    type: Number,
    default: 0
  },
  base_delivery_fee: {
    type: Number,
    default: 0
  },
  originalDeliveryFee: {
    type: Number,
    default: 0
  },
  customerDeliveryFee: {
    type: Number,
    default: 0
  },
  customer_delivery_fee: {
    type: Number,
    default: 0
  },
  deliveryDiscount: {
    type: Number,
    default: 0
  },
  platinumDeliveryDiscount: {
    type: Number,
    default: 0
  },
  platinum_delivery_discount: {
    type: Number,
    default: 0
  },
  staydrivFundedDeliveryAmount: {
    type: Number,
    default: 0
  },
  staydrivMembershipDeliverySubsidy: {
    type: Number,
    default: 0
  },
  staydriv_membership_delivery_subsidy: {
    type: Number,
    default: 0
  },
  isPlatinumDelivery: {
    type: Boolean,
    default: false
  },
  platinumBenefitMessage: {
    type: String,
    default: ''
  },
  deliveryDistanceKm: {
    type: Number,
    default: 0
  },
  pilotDeliveryFee: {
    type: Number,
    default: 0
  },
  pilotEarnings: {
    type: Number,
    default: 0
  },
  pilotDeliveryEarnings: {
    type: Number,
    default: 0
  },
  pilot_delivery_earnings: {
    type: Number,
    default: 0
  },
  fundingSource: {
    type: String,
    enum: ['customer', 'staydriv', 'split', 'none'],
    default: 'customer'
  },
  platformFee: {
    type: Number,
    default: 15
  },
  taxes: {
    type: Number,
    default: 0
  },
  discount: {
    type: Number,
    default: 0
  },
  couponCode: {
    type: String,
    default: '',
    index: true
  },
  couponDiscount: {
    type: Number,
    default: 0
  },
  membershipDiscount: {
    type: Number,
    default: 0
  },
  membershipId: {
    type: String,
    default: '',
    index: true
  },
  membership_id: {
    type: String,
    default: '',
    index: true
  },
  membershipPlanType: {
    type: String,
    enum: ['', 'monthly', 'quarterly', 'platinum', 'gold'],
    default: ''
  },
  discountFundedBy: {
    type: String,
    enum: ['staydriv', 'restaurant', 'split', 'none'],
    default: 'none'
  },
  staydrivDiscountContribution: {
    type: Number,
    default: 0
  },
  restaurantDiscountContribution: {
    type: Number,
    default: 0
  },
  originalTotalAmount: {
    type: Number,
    default: 0
  },
  cashRoundOff: {
    type: Number,
    default: 0
  },
  finalPayable: {
    type: Number,
    default: 0
  },
  totalSavings: {
    type: Number,
    default: 0
  },
  razorpayOrderId: {
    type: String,
    default: '',
    index: true
  },
  razorpayPaymentId: {
    type: String,
    default: '',
    index: true
  },
  razorpaySignature: {
    type: String,
    default: ''
  },
  idempotencyKey: {
    type: String,
    default: '',
    index: true
  },
  orderType: {
    type: String,
    default: 'food_order',
    index: true
  },
  totalAmount: {
    type: Number,
    required: true,
    min: 0
  },
  paymentMethod: {
    type: String,
    enum: ['cod', 'wallet', 'online', 'upi', 'ONLINE_UPI', 'COD', 'WALLET', 'ONLINE'],
    default: 'online',
    set: v => (v ? v.toString().toLowerCase() : 'online')
  },
  paymentStatus: {
    type: String,
    enum: ['pending', 'paid', 'refunded', 'failed'],
    default: 'paid',
    index: true
  },
  orderStatus: {
    type: String,
    enum: [
      'placed', 'accepted', 'preparing', 'ready_for_pickup', 'pilot_assigned', 
      'picked_up', 'out_for_delivery', 'delivered', 'rejected', 'cancelled',
      'delivery_failed_reported', 'DELIVERY_FAILED_REPORTED',
      'return_to_restaurant', 'RETURN_TO_RESTAURANT',
      'return_arrived_at_restaurant', 'RETURN_ARRIVED_AT_RESTAURANT',
      'return_otp_pending', 'RETURN_OTP_PENDING',
      'returned_to_restaurant', 'RETURNED_TO_RESTAURANT',
      'return_under_admin_review', 'RETURN_UNDER_ADMIN_REVIEW',
      'return_closed', 'RETURN_CLOSED'
    ],
    default: 'placed',
    index: true
  },
  deliveryOtp: {
    type: String,
    default: ''
  },
  customerOtp: {
    type: String,
    default: '',
    index: true
  },
  customerOtpVerified: {
    type: Boolean,
    default: false
  },
  restaurantOtp: {
    type: String,
    default: '',
    index: true
  },
  restaurantOtpVerified: {
    type: Boolean,
    default: false
  },
  returnOtp: {
    type: String,
    default: '',
    index: true
  },
  returnOtpVerified: {
    type: Boolean,
    default: false
  },
  returnOtpGeneratedAt: {
    type: Date
  },
  returnReason: {
    type: String,
    default: ''
  },
  returnNotes: {
    type: String,
    default: ''
  },
  returnEvidenceUrl: {
    type: String,
    default: ''
  },
  returnReportedAt: {
    type: Date
  },
  returnArrivedAt: {
    type: Date
  },
  returnedAt: {
    type: Date
  },
  returnDeadline: {
    type: Date
  },
  returnVerifiedBy: {
    type: String,
    default: ''
  },
  walletDebitStatus: {
    type: String,
    enum: ['none', 'proposed', 'approved', 'rejected', 'debited', 'reversed'],
    default: 'none',
    index: true
  },
  settlementStatus: {
    type: String,
    enum: ['unsettled', 'pending_settlement', 'settlement_initiated', 'settled'],
    default: 'unsettled',
    index: true
  },
  settlementId: {
    type: String,
    default: '',
    index: true
  },
  proposedWalletDebitAmount: {
    type: Number,
    default: 0
  },
  actualWalletDebitAmount: {
    type: Number,
    default: 0
  },
  walletDebitTransactionId: {
    type: String,
    default: ''
  },
  walletDebitAdminNotes: {
    type: String,
    default: ''
  },
  walletDebitApprovedBy: {
    type: String,
    default: ''
  },
  walletDebitApprovedAt: {
    type: Date
  },
  notificationAlerts: {
    restaurantNotifiedAt: { type: Date },
    restaurantRespondedAt: { type: Date },
    pilotsNotifiedCount: { type: Number, default: 0 },
    pilotsNotifiedAt: { type: Date },
    pilotAcceptedAt: { type: Date }
  },
  prepTime: {
    type: String,
    default: '25 mins'
  },
  rejectReason: {
    type: String,
    default: ''
  },
  cancelReason: {
    type: String,
    default: ''
  },
  deliveryPartnerId: {
    type: String,
    default: '',
    index: true
  },
  deliveryPartnerName: {
    type: String,
    default: ''
  },
  deliveryPartnerPhone: {
    type: String,
    default: ''
  },
  deliveryPartnerVehicle: {
    type: String,
    default: 'Bike'
  },
  deliveryPartnerPlate: {
    type: String,
    default: ''
  },
  statusHistory: {
    type: [statusHistorySchema],
    default: []
  },
  callHistory: {
    type: [{
      callerRole: { type: String, default: '' },
      targetRole: { type: String, default: '' },
      targetPhone: { type: String, default: '' },
      timestamp: { type: Date, default: Date.now },
      status: { type: String, default: 'initiated' }
    }],
    default: []
  },
  placedAt: {
    type: Date,
    default: Date.now
  },
  acceptedAt: {
    type: Date
  },
  preparedAt: {
    type: Date
  },
  pickedUpAt: {
    type: Date
  },
  deliveredAt: {
    type: Date
  },
  createdAt: {
    type: Date,
    default: Date.now,
    index: true
  },
  updatedAt: {
    type: Date,
    default: Date.now
  }
});

foodOrderSchema.pre('save', function (next) {
  this.updatedAt = new Date();
  if (typeof next === 'function') next();
});

module.exports = mongoose.models.FoodOrder || mongoose.model('FoodOrder', foodOrderSchema);
