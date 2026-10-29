const mongoose = require('mongoose');

const commissionConfigSchema = new mongoose.Schema({
  configId: { type: String, required: true, unique: true, index: true },
  version: { type: Number, required: true, default: 1 },
  defaultRate: { type: Number, required: true, default: 20.0 }, // 20%
  ratesByVehicle: {
    Bike: { type: Number, default: 20.0 },
    Auto: { type: Number, default: 15.0 },
    Car: { type: Number, default: 20.0 },
    'Mini Truck': { type: Number, default: 12.0 },
    '6 Ton Truck': { type: Number, default: 10.0 }
  },
  ratesByService: {
    ride: { type: Number, default: 20.0 },
    delivery: { type: Number, default: 15.0 },
    parcel: { type: Number, default: 15.0 }
  },
  taxRateGst: { type: Number, default: 5.0 }, // 5% GST on passenger transport
  gatewayFeeRate: { type: Number, default: 2.0 }, // 2% PG fee
  effectiveFrom: { type: Date, default: Date.now },
  effectiveTo: { type: Date, default: null },
  isActive: { type: Boolean, default: true },
  notes: { type: String, default: 'Standard production commission schedule' },
  createdBy: { type: String, default: 'Super Admin' },
  createdAt: { type: Date, default: Date.now },
  updatedAt: { type: Date, default: Date.now }
});

module.exports = mongoose.models.CommissionConfig || mongoose.model('CommissionConfig', commissionConfigSchema);
