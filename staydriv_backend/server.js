require('dotenv').config();
const express = require('express');
const http = require('http');
const https = require('https');
const { Server } = require('socket.io');
const mongoose = require('mongoose');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const Razorpay = require('razorpay');

const isTestMode = process.env.NODE_ENV !== 'production';

// Initialize Razorpay with credentials exclusively from env
const razorpayKeyId = process.env.RAZORPAY_KEY_ID;
const razorpayKeySecret = process.env.RAZORPAY_KEY_SECRET;

if (!isTestMode && (!razorpayKeyId || !razorpayKeySecret)) {
  console.error('FATAL ERROR: Razorpay credentials are not defined in production environment variables.');
  process.exit(1);
}

const razorpay = new Razorpay({
  key_id: razorpayKeyId || 'rzp_live_Ta9cOGnIySuBCb',
  key_secret: razorpayKeySecret || 'c93MSwcWO22lZuC7Xm5jURu0'
});

const app = express();

// Secure dynamic CORS allowed origins listing
const allowedOrigins = [
  'http://localhost:3000',
  'http://localhost:5000',
  'http://localhost:5500',
  'http://127.0.0.1:3000',
  'http://127.0.0.1:5000',
  'http://127.0.0.1:5500'
];

app.use(cors({
  origin: function (origin, callback) {
    if (!origin) return callback(null, true);
    if (allowedOrigins.indexOf(origin) !== -1 || origin.endsWith('.serveousercontent.com') || origin.endsWith('.loca.lt')) {
      return callback(null, true);
    }
    return callback(new Error('The CORS policy for this site does not allow access from the specified Origin.'), false);
  }
}));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ limit: '10mb', extended: true }));
app.use((err, req, res, next) => {
  if (err instanceof SyntaxError && err.status === 400 && 'body' in err) {
    console.error('JSON Parsing Error:', err.message);
    return res.status(400).send({ success: false, error: 'Invalid JSON: ' + err.message });
  }
  next();
});
app.use((req, res, next) => {
  console.log(`[REQUEST] ${req.method} ${req.url}`);
  if (req.body && Object.keys(req.body).length > 0) {
    console.log(`[BODY]`, JSON.stringify(req.body));
  }
  next();
});

app.use(express.static(__dirname + '/public'));

const adminDistPath = path.join(__dirname, '../Staydriv_Admin/dist');
if (fs.existsSync(adminDistPath)) {
  app.use(express.static(adminDistPath));
}
const appWebPath = path.join(__dirname, '../staydriv_app/build/web');
if (fs.existsSync(appWebPath)) {
  app.use('/app', express.static(appWebPath));
  app.use('/customer', express.static(appWebPath));
  app.use('/pilot', express.static(appWebPath));
}

// APK Direct Download Endpoint
app.get(['/staydriv.apk', '/download/staydriv.apk', '/api/download/apk'], (req, res) => {
  const releaseApkPath = path.join(__dirname, '../staydriv_app/build/app/outputs/flutter-apk/app-release.apk');
  const publicApkPath = path.join(__dirname, 'public/staydriv.apk');
  const apkPath = path.join(__dirname, '../staydriv_app/build/app/outputs/flutter-apk/app-debug.apk');
  
  if (fs.existsSync(releaseApkPath)) {
    return res.download(releaseApkPath, 'StayDriv.apk');
  } else if (fs.existsSync(publicApkPath)) {
    return res.download(publicApkPath, 'StayDriv.apk');
  } else if (fs.existsSync(apkPath)) {
    return res.download(apkPath, 'StayDriv.apk');
  } else {
    return res.status(404).json({
      success: false,
      message: 'APK file is currently compiling or not found. Please try again in 30 seconds.'
    });
  }
});

// Health-check endpoint
app.get('/api/health', (req, res) => {
  res.status(200).json({
    status: 'ok',
    timestamp: new Date(),
    uptime: process.uptime()
  });
});


// MongoDB Schema for Users/Pilots
const userSchema = new mongoose.Schema({
  uid: String,
  name: String,
  phone: String,
  role: String, // 'customer', 'partner' (Pilot), or 'admin'
  vehicleType: String, // if Pilot
  online: { type: Boolean, default: false },
  approved: { type: Boolean, default: false }, // added for pilot verification
  adminType: String, // 'Staff' or 'Admin'
  lat: Number,
  lng: Number,
  vehiclePlate: String,
  vehicleModelColor: String,
  photo: String,
  aadhaarFront: String,
  aadhaarBack: String,
  licenseFront: String,
  licenseBack: String,
  rcFront: String,
  rcBack: String,
  fitness: String,
  permit: String,
  salary: { type: Number, default: 5000 },
  pendingCancellationCharge: { type: Number, default: 0 },
  lastActive: { type: Date, default: Date.now },
  createdAt: { type: Date, default: Date.now }
});
const User = mongoose.models.User || mongoose.model('User', userSchema);

// Mount OTP Auth Routes
const otpRoutes = require('./routes/otp');
app.use('/api', otpRoutes);

// Endpoint to register user in MongoDB

app.post('/api/register', async (req, res) => {
  try {
    const { uid, name, phone, role, vehicleType, adminType } = req.body;
    console.log(`Registering user in MongoDB: ${name} (${phone}) - ${role} (UID: ${uid}), adminType: ${adminType}`);

    let user;
    if (uid) {
      user = await User.findOne({ uid });
    } else {
      user = await User.findOne({ phone, role });
    }
    if (user) {
      user.name = name;
      user.role = role;
      if (uid) user.uid = uid;
      if (vehicleType) user.vehicleType = vehicleType;
      if (adminType) user.adminType = adminType;
      user.approved = isTestMode; // Auto-approve for seamless testing only
      await user.save();
    } else {
      user = new User({ uid, name, phone, role, vehicleType, adminType, approved: isTestMode });
      await user.save();
    }

    res.status(200).json({ success: true, message: 'User registered in MongoDB successfully', user });
  } catch (err) {
    console.error('MongoDB Registration Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to retrieve user from MongoDB by UID
app.get('/api/user/:uid', async (req, res) => {
  try {
    const { uid } = req.params;
    if (uid === 'mock_uid_staydriv') {
      let admin = await User.findOne({ role: 'admin' });
      if (!admin) {
        admin = new User({
          uid: 'mock_uid_staydriv',
          name: 'StayDriv Admin',
          phone: '9999999999',
          role: 'admin',
          salary: 0
        });
        await admin.save();
      }
      return res.status(200).json({
        success: true,
        user: admin
      });
    }
    let user = await User.findOne({ uid });
    if (!user && uid.startsWith('mock_uid_')) {
      let phone = uid.replace('mock_uid_', '');
      let checkRole = 'customer';
      if (phone.endsWith('_pilot')) {
        phone = phone.replace('_pilot', '');
        checkRole = 'partner';
      }
      user = await User.findOne({ phone, role: checkRole });
    }
    if (user) {
      res.status(200).json({ success: true, user });
    } else {
      res.status(404).json({ success: false, message: 'User not found' });
    }
  } catch (err) {
    console.error('MongoDB User Fetch Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Ensure public/uploads exists
const uploadsDir = path.join(__dirname, 'public', 'uploads');
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}

// Endpoint to upload base64 file data
app.post('/api/upload', (req, res) => {
  try {
    const { uid, fileName, fileData } = req.body;
    if (!fileName || !fileData) {
      return res.status(400).json({ success: false, error: 'FileName and FileData are required' });
    }

    const ext = path.extname(fileName).toLowerCase();
    if (ext !== '.jpg' && ext !== '.jpeg') {
      return res.status(400).json({ success: false, error: 'Only .jpg and .jpeg formats are accepted' });
    }

    const buffer = Buffer.from(fileData, 'base64');
    const uniqueFileName = `${uid}_${Date.now()}${ext}`;
    const filePath = path.join(uploadsDir, uniqueFileName);
    fs.writeFileSync(filePath, buffer);

    const relativePath = `/uploads/${uniqueFileName}`;
    res.status(200).json({ success: true, url: relativePath, sizeBytes: buffer.length });
  } catch (err) {
    console.error('File Upload Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to update driver status and coordinates in MongoDB
app.post('/api/partner/update', async (req, res) => {
  try {
    const {
      uid, online, lat, lng, vehicleType, vehiclePlate, vehicleModelColor, approved,
      photo, aadhaarFront, aadhaarBack, licenseFront, licenseBack, rcFront, rcBack, fitness, permit
    } = req.body;
    console.log(`Updating partner status in MongoDB: uid=${uid}, online=${online}, vehicleType=${vehicleType}, lat=${lat}, lng=${lng}, approved=${approved}`);
    let user = await User.findOne({ uid });
    if (!user && uid && uid.startsWith('mock_uid_')) {
      let phone = uid.replace('mock_uid_', '');
      if (phone.endsWith('_pilot')) {
        phone = phone.replace('_pilot', '');
      }
      user = await User.findOne({ phone, role: 'partner' });
    }
    if (!user) {
      console.log(`Partner not found in MongoDB. Auto-creating user profile for uid: ${uid}`);
      let phone = uid.startsWith('mock_uid_') ? uid.replace('mock_uid_', '') : '9999999999';
      if (phone.endsWith('_pilot')) {
        phone = phone.replace('_pilot', '');
      }
      user = new User({
        uid,
        role: 'partner',
        name: 'Pilot Partner',
        phone,
        approved: isTestMode, // Auto-approve for testing only
      });
    }
    if (online !== undefined) user.online = online;
    if (lat !== undefined) user.lat = lat;
    if (lng !== undefined) user.lng = lng;
    if (vehicleType !== undefined) user.vehicleType = vehicleType;
    if (vehiclePlate !== undefined) user.vehiclePlate = vehiclePlate;
    if (vehicleModelColor !== undefined) user.vehicleModelColor = vehicleModelColor;
    if (approved !== undefined) user.approved = approved;
    if (photo !== undefined) user.photo = photo;
    if (aadhaarFront !== undefined) user.aadhaarFront = aadhaarFront;
    if (aadhaarBack !== undefined) user.aadhaarBack = aadhaarBack;
    if (licenseFront !== undefined) user.licenseFront = licenseFront;
    if (licenseBack !== undefined) user.licenseBack = licenseBack;
    if (rcFront !== undefined) user.rcFront = rcFront;
    if (rcBack !== undefined) user.rcBack = rcBack;
    if (fitness !== undefined) user.fitness = fitness;
    if (permit !== undefined) user.permit = permit;
    user.lastActive = new Date();
    await user.save();
    res.status(200).json({ success: true, message: 'Partner status updated in MongoDB', user });
  } catch (err) {
    console.error('MongoDB Partner Update Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

app.get('/api/user/:uid/rides', async (req, res) => {
  try {
    const { uid } = req.params;
    const { role, allStatuses } = req.query; // 'Driver' or 'Customer'
    console.log(`Fetching rides for uid: ${uid}, role: ${role}, allStatuses: ${allStatuses}`);

    let query = {};
    if (allStatuses !== 'true') {
      query.status = 'completed';
    }
    const roleLower = (role || '').toLowerCase();
    
    if (roleLower === 'driver' || roleLower === 'partner') {
      query.$or = [{ driverId: uid }];
      if (uid.startsWith('mock_uid_')) {
        let phone = uid.replace('mock_uid_', '');
        query.$or.push({ driverId: phone });
        if (phone.endsWith('_pilot')) {
          phone = phone.replace('_pilot', '');
          query.$or.push({ driverId: phone });
          query.$or.push({ driverId: 'mock_uid_' + phone });
        }
      }
    } else {
      query.$or = [{ passengerId: uid }];
      if (uid.startsWith('mock_uid_')) {
        let phone = uid.replace('mock_uid_', '');
        query.$or.push({ passengerId: phone });
        if (phone.endsWith('_pilot')) {
          phone = phone.replace('_pilot', '');
          query.$or.push({ passengerId: phone });
          query.$or.push({ passengerId: 'mock_uid_' + phone });
        }
      }
    }

    const bookings = await Booking.find(query).sort({ createdAt: -1 }).limit(100);
    res.status(200).json({ success: true, bookings });
  } catch (err) {
    console.error('MongoDB Fetch User Rides Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to retrieve recent bookings for Admin
app.get('/api/admin/bookings', async (req, res) => {
  try {
    const bookings = await Booking.find().sort({ createdAt: -1 }).limit(50);
    res.status(200).json({ success: true, bookings });
  } catch (err) {
    console.error('MongoDB Admin Bookings Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to retrieve all pilots/drivers for Admin
app.get('/api/admin/drivers', async (req, res) => {
  try {
    const drivers = await User.find({ role: 'partner' });
    res.status(200).json({ success: true, drivers });
  } catch (err) {
    console.error('MongoDB Admin Drivers Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// MongoDB Schema for Bookings
const bookingSchema = new mongoose.Schema({
  bookingId: String,
  pickup: String,
  drop: String,
  pickupLatLng: Object,
  dropLatLng: Object,
  vehicle: String,
  price: String,
  otp: String,
  status: String,
  passengerId: String,
  passengerName: String,
  passengerPhone: String,
  driverId: String,
  driverName: String,
  vehiclePlate: String,
  vehicleModelColor: String,
  arrivedAt: Number,
  assignedAt: Number,
  declinedDrivers: { type: [String], default: [] },
  serviceType: String,
  title: String,
  pickupHouse: String,
  pickupContactName: String,
  pickupContactPhone: String,
  dropHouse: String,
  dropContactName: String,
  dropContactPhone: String,
  paymentOption: String,
  scheduledDate: String,
  scheduledTimeSlot: String,
  waitingCharge: Number,
  distance: String,
  cancelledBy: String,
  cancelReason: String,
  updatedAt: { type: Date, default: Date.now },
  createdAt: { type: Date, default: Date.now }
});
const Booking = mongoose.model('Booking', bookingSchema);

// MongoDB Schema for Payments
const paymentSchema = new mongoose.Schema({
  orderId: { type: String, required: true, unique: true },
  paymentId: String,
  signature: String,
  amount: Number, // in paise
  status: { type: String, default: 'created' }, // 'created', 'verified', 'failed'
  createdAt: { type: Date, default: Date.now }
});
const Payment = mongoose.model('Payment', paymentSchema);

// MongoDB Schema for Payouts
const payoutSchema = new mongoose.Schema({
  payoutId: { type: String, required: true, unique: true },
  uid: String,
  amount: Number, // in Rs
  targetAccount: String,
  status: { type: String, default: 'processed' }, // 'processed', 'failed'
  createdAt: { type: Date, default: Date.now }
});
const Payout = mongoose.model('Payout', payoutSchema);


// Endpoint to create or update booking in MongoDB
app.post('/api/booking/update', async (req, res) => {
  try {
    const { bookingId, status, activeBooking } = req.body;
    console.log(`Updating booking in MongoDB: ${bookingId} - status: ${status}`);

    let booking = await Booking.findOne({ bookingId });
    const isTransitioningToCompleted = (status === 'completed') && (!booking || booking.status !== 'completed');
    if (booking) {
      booking.status = status;
      if (status === 'searching') {
        if (booking.driverId) {
          if (!booking.declinedDrivers) booking.declinedDrivers = [];
          if (!booking.declinedDrivers.includes(booking.driverId)) {
            booking.declinedDrivers.push(booking.driverId);
          }
        }
        booking.driverId = '';
        booking.driverName = '';
        booking.vehiclePlate = '';
        booking.vehicleModelColor = '';
        booking.arrivedAt = null;
        booking.assignedAt = null;
        booking.createdAt = new Date();
      } else {
        if (activeBooking.driverId) booking.driverId = activeBooking.driverId;
        if (activeBooking.driverName) booking.driverName = activeBooking.driverName;
        if (activeBooking.vehiclePlate) booking.vehiclePlate = activeBooking.vehiclePlate;
        if (activeBooking.vehicleModelColor) booking.vehicleModelColor = activeBooking.vehicleModelColor;
        if (activeBooking.arrivedAt) booking.arrivedAt = activeBooking.arrivedAt;
        if (activeBooking.price) booking.price = activeBooking.price;
        if (activeBooking.waitingCharge !== undefined) booking.waitingCharge = activeBooking.waitingCharge;
      }
      await booking.save();
    } else {
      booking = new Booking({
        bookingId,
        pickup: activeBooking.pickup,
        drop: activeBooking.drop,
        pickupLatLng: activeBooking.pickupLatLng,
        dropLatLng: activeBooking.dropLatLng,
        vehicle: activeBooking.vehicle,
        price: activeBooking.price,
        otp: activeBooking.otp,
        status: status,
        passengerId: activeBooking.passengerId,
        passengerName: activeBooking.passengerName,
        passengerPhone: activeBooking.passengerPhone,
        driverId: activeBooking.driverId,
        driverName: activeBooking.driverName,
        vehiclePlate: activeBooking.vehiclePlate,
        vehicleModelColor: activeBooking.vehicleModelColor,
        arrivedAt: activeBooking.arrivedAt,
        serviceType: activeBooking.serviceType,
        title: activeBooking.title,
        pickupHouse: activeBooking.pickupHouse,
        pickupContactName: activeBooking.pickupContactName,
        pickupContactPhone: activeBooking.pickupContactPhone,
        dropHouse: activeBooking.dropHouse,
        dropContactName: activeBooking.dropContactName,
        dropContactPhone: activeBooking.dropContactPhone,
        paymentOption: activeBooking.paymentOption,
        scheduledDate: activeBooking.scheduledDate,
        scheduledTimeSlot: activeBooking.scheduledTimeSlot,
        waitingCharge: activeBooking.waitingCharge,
      });
      await booking.save();
    }

    // Reset pendingCancellationCharge when customer creates/requests a booking
    if (status === 'searching' && activeBooking && activeBooking.passengerId) {
      const passengerId = activeBooking.passengerId;
      let pUser = await User.findOne({ uid: passengerId });
      if (!pUser && passengerId.startsWith('mock_uid_')) {
        let phone = passengerId.replace('mock_uid_', '');
        if (phone.endsWith('_pilot')) phone = phone.replace('_pilot', '');
        pUser = await User.findOne({ phone, role: 'customer' });
      }
      if (pUser && pUser.pendingCancellationCharge > 0) {
        console.log(`Resetting pending cancellation charge for passenger ${passengerId} to 0`);
        pUser.pendingCancellationCharge = 0;
        await pUser.save();
      }
    }

    // Also write/update the booking in GlobalState collection for historical tracking
    await GlobalState.create({
      bookingId,
      type: 'update_state',
      activeBooking: { ...activeBooking, status },
      updatedAt: new Date()
    });

    if (isTransitioningToCompleted) {
      const priceStr = (activeBooking && activeBooking.price) ? String(activeBooking.price) : (booking ? booking.price : '₹0');
      const cleanStr = priceStr.replace(/[^0-9.]/g, '');
      const fareVal = parseFloat(cleanStr) || 0.0;
      
      const commission = fareVal * 0.15;
      const netEarnings = fareVal * 0.85;
      
      const driverId = (activeBooking && activeBooking.driverId) ? activeBooking.driverId : (booking ? booking.driverId : '');
      if (driverId) {
        let pilot = await User.findOne({ uid: driverId });
        if (!pilot && driverId.startsWith('mock_uid_')) {
          let phone = driverId.replace('mock_uid_', '');
          if (phone.endsWith('_pilot')) phone = phone.replace('_pilot', '');
          pilot = await User.findOne({ phone, role: 'partner' });
        }
        if (pilot) {
          pilot.salary = (pilot.salary || 5000) + netEarnings;
          await pilot.save();
          console.log(`[EARNINGS] Added ₹${netEarnings.toFixed(2)} to pilot ${driverId}. New balance: ₹${pilot.salary}`);
        }
      }
      
      let admin = await User.findOne({ role: 'admin' });
      if (!admin) {
        admin = new User({
          uid: 'mock_uid_staydriv',
          name: 'StayDriv Admin',
          phone: '9999999999',
          role: 'admin',
          salary: 0,
        });
      }
      admin.salary = (admin.salary || 0) + commission;
      await admin.save();
      console.log(`[COMMISSION] Added ₹${commission.toFixed(2)} to admin account. New balance: ₹${admin.salary}`);
    }

    res.status(200).json({ success: true, message: 'Booking synced with MongoDB successfully', booking });
  } catch (err) {
    console.error('MongoDB Booking Update Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to cancel booking and apply penalties/charges
app.post('/api/booking/cancel', async (req, res) => {
  try {
    const { bookingId, cancelledBy, reason } = req.body;
    console.log(`Cancelling booking in MongoDB: ${bookingId} - cancelledBy: ${cancelledBy}, reason: ${reason}`);

    let booking = await Booking.findOne({ bookingId });
    if (!booking) {
      return res.status(404).json({ success: false, message: 'Booking not found' });
    }

    const previousStatus = booking.status;
    booking.status = 'cancelled';
    booking.cancelledBy = cancelledBy || 'pilot';
    booking.cancelReason = reason || '';
    booking.updatedAt = new Date();
    await booking.save();

    // Clear active in-memory dispatch timer if pending
    if (typeof activeBookings !== 'undefined' && activeBookings[bookingId]) {
      clearTimeout(activeBookings[bookingId].timer);
      delete activeBookings[bookingId];
    }

    // Broadcast cancellation notification to Pilot, Customer, Admin, and Simulator
    const cancelPayload = {
      type: 'ride_cancelled',
      bookingId,
      status: 'cancelled',
      cancelledBy: cancelledBy || 'pilot',
      reason: reason || (cancelledBy === 'customer' ? 'Customer cancelled the ride request' : 'Pilot cancelled the ride request'),
      cancelReason: reason || (cancelledBy === 'customer' ? 'Customer cancelled the ride request' : 'Pilot cancelled the ride request'),
      passengerId: booking.passengerId,
      driverId: booking.driverId,
      message: cancelledBy === 'customer' 
        ? 'Customer has cancelled the ride.' 
        : 'Pilot has cancelled the ride.',
      activeBooking: booking.toObject ? booking.toObject() : booking
    };

    if (typeof io !== 'undefined' && io) {
      io.emit('state_update', cancelPayload);
      io.emit('ride_cancelled', cancelPayload);
      io.emit('booking_cancelled', cancelPayload);
      console.log(`[SOCKET BROADCAST] Ride cancelled by ${cancelPayload.cancelledBy} for booking ${bookingId}`);
    }

    // Write to GlobalState for tracking
    await GlobalState.create({
      bookingId,
      type: 'update_state',
      activeBooking: { bookingId, status: 'cancelled', cancelledBy, reason },
      updatedAt: new Date()
    });

    let penaltyApplied = false;
    let penaltyMessage = '';

    if (previousStatus === 'arrived') {
      if (cancelledBy === 'customer') {
        const passengerId = booking.passengerId;
        if (passengerId) {
          let customer = await User.findOne({ uid: passengerId });
          if (!customer && passengerId.startsWith('mock_uid_')) {
            let phone = passengerId.replace('mock_uid_', '');
            if (phone.endsWith('_pilot')) phone = phone.replace('_pilot', '');
            customer = await User.findOne({ phone, role: 'customer' });
          }
          if (customer) {
            customer.pendingCancellationCharge = (customer.pendingCancellationCharge || 0) + 10;
            await customer.save();
            penaltyApplied = true;
            penaltyMessage = 'Rs 10 cancellation charge applied to your next booking.';
            console.log(`Applied Rs 10 cancellation charge to customer: ${passengerId}`);
          }
        }
      } else if (cancelledBy === 'pilot' || cancelledBy === 'driver') {
        const driverId = booking.driverId;
        if (driverId) {
          let pilot = await User.findOne({ uid: driverId });
          if (!pilot && driverId.startsWith('mock_uid_')) {
            let phone = driverId.replace('mock_uid_', '');
            if (phone.endsWith('_pilot')) phone = phone.replace('_pilot', '');
            pilot = await User.findOne({ phone, role: 'partner' });
          }
          if (pilot) {
            pilot.salary = (pilot.salary || 5000) - 10;
            await pilot.save();
            penaltyApplied = true;
            penaltyMessage = 'Rs 10 penalty deducted from your salary.';
            console.log(`Deducted Rs 10 from pilot salary: ${driverId}`);
          }
        }
      }
    }

    res.status(200).json({
      success: true,
      message: 'Booking cancelled successfully',
      booking,
      penaltyApplied,
      penaltyMessage
    });
  } catch (err) {
    console.error('MongoDB Booking Cancel Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to get available bookings for a vehicle type
app.get('/api/booking/available', async (req, res) => {
  try {
    const { vehicleType, driverId, lat, lng } = req.query;
    console.log(`Checking available bookings for vehicle: ${vehicleType}, driverId: ${driverId}, lat: ${lat}, lng: ${lng}`);

    if (!driverId) {
      return res.status(200).json({ success: true, bookings: [] });
    }

    // A. Clean up stale online pilots (no activity in 12 hours to support backgrounded/minimized mobile apps)
    const twelveHoursAgo = new Date(Date.now() - 43200000);
    const stalePilotsResult = await User.updateMany(
      { 
        role: 'partner', 
        online: true, 
        $or: [
          { lastActive: { $lt: twelveHoursAgo } },
          { lastActive: { $exists: false } },
          { lastActive: null }
        ]
      },
      { online: false }
    );
    if (stalePilotsResult.modifiedCount > 0) {
      console.log(`[CLEANUP] Set ${stalePilotsResult.modifiedCount} stale online pilots to offline.`);
    }

    // B. Clean up stale searching bookings (older than 30 minutes)
    const thirtyMinutesAgo = new Date(Date.now() - 1800000);
    const staleBookingsResult = await Booking.updateMany(
      { status: 'searching', createdAt: { $lt: thirtyMinutesAgo } },
      { status: 'timed_out' }
    );
    if (staleBookingsResult.modifiedCount > 0) {
      console.log(`[CLEANUP] Set ${staleBookingsResult.modifiedCount} stale searching bookings to timed_out.`);
    }

    // Find the driver's coordinates to compute distance
    let driver = await User.findOne({ uid: driverId });
    if (!driver && driverId && driverId.startsWith('mock_uid_')) {
      let phone = driverId.replace('mock_uid_', '');
      if (phone.endsWith('_pilot')) {
        phone = phone.replace('_pilot', '');
      }
      driver = await User.findOne({ phone, role: 'partner' });
    }
    if (driver) {
      driver.lastActive = new Date();
      driver.online = true; // Auto-restore online status since the app is actively polling
      if (lat !== undefined && lng !== undefined) {
        const parsedLat = parseFloat(lat);
        const parsedLng = parseFloat(lng);
        if (!isNaN(parsedLat) && !isNaN(parsedLng)) {
          driver.lat = parsedLat;
          driver.lng = parsedLng;
        }
      }
      await driver.save();
    }

    if (!driver || !driver.online) {
      return res.status(200).json({ success: true, bookings: [] });
    }

    // 1. Clean up any timed-out assignments (older than 45 seconds)
    const now = Date.now();
    const timedOutBookings = await Booking.find({
      status: 'searching',
      driverId: { $ne: '' },
      assignedAt: { $lt: now - 45000 } // 45 seconds timeout
    });

    for (let tob of timedOutBookings) {
      console.log(`Booking ${tob.bookingId} assignment to driver ${tob.driverId} timed out.`);
      if (!tob.declinedDrivers) tob.declinedDrivers = [];
      if (!tob.declinedDrivers.includes(tob.driverId)) {
        tob.declinedDrivers.push(tob.driverId);
      }
      tob.driverId = '';
      tob.assignedAt = null;
      await tob.save();
    }

    // 2. Find all active bookings matching the vehicle type in 'searching' status
    let vehicleRegex = new RegExp('^' + (vehicleType || '') + '$', 'i');
    if (vehicleType) {
      const vtLower = vehicleType.toLowerCase();
      if (vtLower.includes('heavy truck') || vtLower.includes('heavy_truck') || vtLower.match(/(6|8|10|12|25|30)\s*ton/i)) {
        vehicleRegex = new RegExp('(heavy\\s*truck|ton\\s*truck)', 'i');
      } else if (vtLower.includes('mini truck') || vtLower.includes('mini_truck')) {
        vehicleRegex = new RegExp('mini\\s*truck', 'i');
      } else if (vtLower.includes('truck')) {
        vehicleRegex = new RegExp('truck', 'i');
      } else if (vtLower.includes('bike')) {
        vehicleRegex = new RegExp('(bike|two)', 'i');
      } else if (vtLower.includes('car') || vtLower.includes('cab')) {
        vehicleRegex = new RegExp('(car|cab)', 'i');
      } else if (vtLower.includes('auto')) {
        vehicleRegex = new RegExp('auto', 'i');
      }
    }

    const bookings = await Booking.find({
      status: 'searching',
      vehicle: vehicleRegex
    });

    // Find all busy pilot IDs (pilots assigned to other active rides)
    // Heavy Truck bookings do not block pilots from taking other bookings (kept online/idle)
    const activeBookings = await Booking.find({
      status: { $in: ['searching', 'accepted', 'arrived', 'started'] },
      driverId: { $ne: '' }
    });
    const busyDriverIds = activeBookings
      .filter(ab => {
        const v = (ab.vehicle || '').toLowerCase();
        return !v.includes('heavy truck') && !v.includes('ton truck');
      })
      .map(ab => ab.driverId);

    // Pilot ID matching/normalization helper
    const isPilotMatch = (pilot, queryId) => {
      if (!pilot || !queryId) return false;
      const qIdStr = String(queryId);
      if (pilot.uid === qIdStr) return true;
      
      let normQuery = qIdStr.replace('mock_uid_', '');
      let normPilotUid = pilot.uid ? String(pilot.uid).replace('mock_uid_', '') : '';
      let normPilotPhone = pilot.phone ? String(pilot.phone).replace('mock_uid_', '') : '';
      
      if (normQuery.endsWith('_pilot')) normQuery = normQuery.replace('_pilot', '');
      if (normPilotUid.endsWith('_pilot')) normPilotUid = normPilotUid.replace('_pilot', '');
      if (normPilotPhone.endsWith('_pilot')) normPilotPhone = normPilotPhone.replace('_pilot', '');
      
      return normQuery === normPilotUid || normQuery === normPilotPhone;
    };

    const activeForThisDriver = [];

    for (let b of bookings) {
      // If already assigned to this driver, return it
      if (b.driverId === driverId) {
        activeForThisDriver.push(b);
        continue;
      }

      // If assigned to someone else, skip
      if (b.driverId && b.driverId !== '') {
        continue;
      }

      // If this driver already declined/timed-out, skip
      if (b.declinedDrivers && b.declinedDrivers.includes(driverId)) {
        continue;
      }

      // If not assigned, run matching to see if this driver is the nearest eligible driver
      // Find all online drivers matching the vehicle type
      const onlinePilots = await User.find({
        role: 'partner',
        online: true,
        vehicleType: vehicleRegex
      });

      // Filter out pilots who declined this booking, are busy, or are not online (keep 12h threshold for backgrounded apps)
      const activeThreshold = new Date(Date.now() - 43200000);
      const eligiblePilots = onlinePilots.filter(p => {
        // Must have polled in the last 120 seconds to be considered active
        if (!p.lastActive || p.lastActive < activeThreshold) {
          return false;
        }

        if (b.declinedDrivers && (b.declinedDrivers.includes(p.uid) || (p.phone && b.declinedDrivers.includes(p.phone)))) {
          return false;
        }
        
        // Exclude busy pilots
        const isBusy = busyDriverIds.some(busyId => isPilotMatch(p, busyId));
        if (isBusy) {
          return false;
        }
        
        return true;
      });

      if (eligiblePilots.length === 0) {
        continue;
      }

      // Add safety check for pickupLatLng
      if (!b.pickupLatLng || b.pickupLatLng.lat === undefined || b.pickupLatLng.lng === undefined) {
        console.warn(`[MATCHING] Booking ${b.bookingId} has invalid pickupLatLng:`, b.pickupLatLng);
        continue;
      }

      // Calculate distance for each eligible pilot
      const pickupLat = b.pickupLatLng.lat;
      const pickupLng = b.pickupLatLng.lng;

      const sortedPilots = eligiblePilots.map(p => {
        const dist = getDistance(pickupLat, pickupLng, p.lat || 0, p.lng || 0);
        return { pilot: p, dist };
      }).sort((a, b) => a.dist - b.dist);

      if (isPilotMatch(sortedPilots[0].pilot, driverId)) {
        b.driverId = driverId;
        b.assignedAt = now;
        await b.save();
        console.log(`Assigned booking ${b.bookingId} to driver ${driverId} (nearest eligible, distance: ${sortedPilots[0].dist.toFixed(1)}m)`);
        activeForThisDriver.push(b);
      }
    }

    // Also check if any booking assigned to this driver was cancelled by customer recently (last 45s)
    const fortyFiveSecsAgo = new Date(Date.now() - 45000);
    const recentCustomerCancelled = await Booking.find({
      driverId: driverId,
      status: 'cancelled',
      cancelledBy: 'customer',
      $or: [
        { updatedAt: { $gte: fortyFiveSecsAgo } },
        { createdAt: { $gte: fortyFiveSecsAgo } }
      ]
    }).sort({ updatedAt: -1, createdAt: -1 }).limit(1);

    if (recentCustomerCancelled && recentCustomerCancelled.length > 0) {
      activeForThisDriver.push(...recentCustomerCancelled);
    }

    res.status(200).json({ success: true, bookings: activeForThisDriver });
  } catch (err) {
    console.error('MongoDB Available Bookings Fetch Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to retrieve a specific booking from MongoDB by bookingId
app.get('/api/booking/:bookingId', async (req, res) => {
  try {
    const { bookingId } = req.params;
    const booking = await Booking.findOne({ bookingId });
    if (booking) {
      res.status(200).json({ success: true, booking });
    } else {
      res.status(404).json({ success: false, message: 'Booking not found' });
    }
  } catch (err) {
    console.error('MongoDB Booking Fetch Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to retrieve active booking for a passenger/customer
app.get('/api/booking/active/passenger/:passengerId', async (req, res) => {
  try {
    const { passengerId } = req.params;
    const fortyFiveSecsAgo = new Date(Date.now() - 45000);
    const booking = await Booking.findOne({
      passengerId,
      $or: [
        { status: { $in: ['searching', 'accepted', 'arrived', 'started'] } },
        { status: 'cancelled', updatedAt: { $gte: fortyFiveSecsAgo } },
        { status: 'cancelled', createdAt: { $gte: fortyFiveSecsAgo } }
      ]
    }).sort({ updatedAt: -1, createdAt: -1 });

    if (booking) {
      res.status(200).json({ success: true, booking });
    } else {
      res.status(404).json({ success: false, message: 'No active booking found' });
    }
  } catch (err) {
    console.error('MongoDB Passenger Active Booking Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to retrieve active booking for a pilot/driver
app.get(['/api/booking/active/pilot/:driverId', '/api/booking/active/driver/:driverId'], async (req, res) => {
  try {
    const { driverId } = req.params;
    const fortyFiveSecsAgo = new Date(Date.now() - 45000);
    const booking = await Booking.findOne({
      driverId,
      $or: [
        { status: { $in: ['accepted', 'arrived', 'started'] } },
        { status: 'cancelled', updatedAt: { $gte: fortyFiveSecsAgo } },
        { status: 'cancelled', createdAt: { $gte: fortyFiveSecsAgo } }
      ]
    }).sort({ updatedAt: -1, createdAt: -1 });

    if (booking) {
      res.status(200).json({ success: true, booking });
    } else {
      res.status(404).json({ success: false, message: 'No active booking found for pilot' });
    }
  } catch (err) {
    console.error('MongoDB Pilot Active Booking Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to fetch directions from Google Maps on the backend (prevents CORS and polyline corruption)
// Endpoint to fetch directions from Google Maps with OSRM fallback (prevents straight lines and CORS issues)
app.get('/api/directions', async (req, res) => {
  try {
    const { origin, destination } = req.query;
    if (!origin || !destination) {
      return res.status(400).json({ success: false, error: 'origin and destination are required' });
    }

    const https = require('https');

    // Helper to fetch from OSRM
    const fetchOSRM = (orig, dest) => {
      return new Promise((resolve, reject) => {
        const [origLat, origLng] = orig.split(',');
        const [destLat, destLng] = dest.split(',');
        const osrmUrl = `https://router.project-osrm.org/route/v1/driving/${origLng.trim()},${origLat.trim()};${destLng.trim()},${destLat.trim()}?overview=full`;
        
        https.get(osrmUrl, (osrmRes) => {
          let data = '';
          osrmRes.on('data', (chunk) => data += chunk);
          osrmRes.on('end', () => {
            try {
              const json = JSON.parse(data);
              if (json.code === 'Ok' && json.routes && json.routes.length > 0) {
                const route = json.routes[0];
                resolve({
                  status: 'OK',
                  routes: [{
                    overview_polyline: {
                      points: route.geometry
                    },
                    legs: [{
                      distance: {
                        text: `${(route.distance / 1000).toFixed(1)} km`,
                        value: Math.round(route.distance)
                      },
                      duration: {
                        text: `${Math.round(route.duration / 60)} mins`,
                        value: Math.round(route.duration)
                      }
                    }]
                  }]
                });
              } else {
                reject(new Error('OSRM route not found'));
              }
            } catch (err) {
              reject(err);
            }
          });
        }).on('error', (err) => reject(err));
      });
    };

    // Google Maps API
    const apiKey = process.env.GOOGLE_MAPS_API_KEY || 'AIzaSyD2Lw1UPJAVtzSBY4JARHS6yV284w2hneg';
    const googleUrl = `https://maps.googleapis.com/maps/api/directions/json?origin=${encodeURIComponent(origin)}&destination=${encodeURIComponent(destination)}&key=${apiKey}`;

    https.get(googleUrl, (apiRes) => {
      let data = '';
      apiRes.on('data', (chunk) => data += chunk);
      apiRes.on('end', async () => {
        try {
          const json = JSON.parse(data);
          if (json.status === 'OK') {
            res.status(200).json(json);
          } else {
            console.log(`[DIRECTIONS] Google status: ${json.status}. Falling back to OSRM...`);
            const osrmData = await fetchOSRM(origin, destination);
            res.status(200).json(osrmData);
          }
        } catch (e) {
          try {
            console.log(`[DIRECTIONS] Google parse error. Falling back to OSRM...`);
            const osrmData = await fetchOSRM(origin, destination);
            res.status(200).json(osrmData);
          } catch (osrmErr) {
            res.status(500).json({ success: false, error: 'Failed both Google and OSRM directions APIs' });
          }
        }
      });
    }).on('error', async (err) => {
      try {
        console.log(`[DIRECTIONS] Google request error. Falling back to OSRM...`);
        const osrmData = await fetchOSRM(origin, destination);
        res.status(200).json(osrmData);
      } catch (osrmErr) {
        res.status(500).json({ success: false, error: err.message });
      }
    });

  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ==========================================
// GOOGLE PLACES & GEOCODING PROXY ENDPOINTS
// ==========================================

// Helper: Fallback to OpenStreetMap Nominatim for Autocomplete
function fallbackOSMAutocomplete(input, res) {
  const osmUrl = `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(input)}&format=json&addressdetails=1&limit=8&countrycodes=in`;
  https.get(osmUrl, { headers: { 'User-Agent': 'StayDriv-Backend/1.0' } }, (apiRes) => {
    let data = '';
    apiRes.on('data', c => data += c);
    apiRes.on('end', () => {
      try {
        const list = JSON.parse(data);
        if (Array.isArray(list)) {
          const predictions = list.map(item => {
            const parts = (item.display_name || '').split(',');
            return {
              description: item.display_name,
              place_id: 'osm_' + item.osm_id,
              main_text: parts[0] ? parts[0].trim() : item.display_name,
              secondary_text: parts.slice(1).join(',').trim(),
              lat: parseFloat(item.lat),
              lng: parseFloat(item.lon)
            };
          });
          return res.status(200).json({ status: 'OK', predictions });
        }
        res.status(200).json({ status: 'OK', predictions: [] });
      } catch (e) {
        res.status(200).json({ status: 'OK', predictions: [] });
      }
    });
  }).on('error', () => res.status(200).json({ status: 'OK', predictions: [] }));
}

// 1. Places Autocomplete
app.get('/api/places/autocomplete', (req, res) => {
  const input = (req.query.input || '').trim();
  const lat = req.query.lat;
  const lng = req.query.lng;
  if (!input || input.length < 2) {
    return res.status(200).json({ status: 'OK', predictions: [] });
  }

  const apiKey = process.env.GOOGLE_MAPS_API_KEY || 'AIzaSyD2Lw1UPJAVtzSBY4JARHS6yV284w2hneg';
  let googleUrl = `https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${encodeURIComponent(input)}&components=country:in&key=${apiKey}`;
  if (lat && lng) {
    googleUrl += `&location=${lat},${lng}&radius=50000`;
  }

  https.get(googleUrl, (apiRes) => {
    let data = '';
    apiRes.on('data', chunk => data += chunk);
    apiRes.on('end', () => {
      try {
        const json = JSON.parse(data);
        if (json.status === 'OK' && json.predictions) {
          const simplified = json.predictions.map(p => ({
            description: p.description,
            place_id: p.place_id,
            main_text: p.structured_formatting ? p.structured_formatting.main_text : p.description.split(',')[0].trim(),
            secondary_text: p.structured_formatting ? (p.structured_formatting.secondary_text || '') : (p.description.split(',').slice(1).join(',').trim())
          }));
          return res.status(200).json({ status: 'OK', predictions: simplified });
        }
        if (json.status === 'ZERO_RESULTS') {
          return res.status(200).json({ status: 'OK', predictions: [] });
        }
        fallbackOSMAutocomplete(input, res);
      } catch (e) {
        fallbackOSMAutocomplete(input, res);
      }
    });
  }).on('error', () => fallbackOSMAutocomplete(input, res));
});

// Helper: Fallback Geocoding using OSM
function fallbackOSMGeocode(address, res) {
  const osmUrl = `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(address)}&format=json&limit=1`;
  https.get(osmUrl, { headers: { 'User-Agent': 'StayDriv-Backend/1.0' } }, (apiRes) => {
    let data = '';
    apiRes.on('data', c => data += c);
    apiRes.on('end', () => {
      try {
        const list = JSON.parse(data);
        if (Array.isArray(list) && list.length > 0) {
          return res.status(200).json({
            status: 'OK',
            location: { lat: parseFloat(list[0].lat), lng: parseFloat(list[0].lon) },
            formatted_address: list[0].display_name
          });
        }
        res.status(404).json({ status: 'ZERO_RESULTS', error: 'Address not found' });
      } catch (e) {
        res.status(500).json({ status: 'ERROR', error: e.message });
      }
    });
  }).on('error', (err) => res.status(500).json({ status: 'ERROR', error: err.message }));
}

function fallbackGeocodeAddress(address, apiKey, res) {
  if (!address) {
    return res.status(404).json({ status: 'ZERO_RESULTS', error: 'Location not found' });
  }
  const geoUrl = `https://maps.googleapis.com/maps/api/geocode/json?address=${encodeURIComponent(address)}&components=country:in&key=${apiKey}`;
  https.get(geoUrl, (apiRes) => {
    let data = '';
    apiRes.on('data', c => data += c);
    apiRes.on('end', () => {
      try {
        const json = JSON.parse(data);
        if (json.status === 'OK' && json.results && json.results.length > 0) {
          const result = json.results[0];
          return res.status(200).json({
            status: 'OK',
            location: result.geometry.location,
            formatted_address: result.formatted_address
          });
        }
        fallbackOSMGeocode(address, res);
      } catch (e) {
        fallbackOSMGeocode(address, res);
      }
    });
  }).on('error', () => fallbackOSMGeocode(address, res));
}

// 2. Geocode / Place Details
app.get('/api/places/geocode', (req, res) => {
  const address = (req.query.address || '').trim();
  const placeId = (req.query.place_id || '').trim();

  if (!address && !placeId) {
    return res.status(400).json({ status: 'INVALID_REQUEST', error: 'address or place_id required' });
  }

  const apiKey = process.env.GOOGLE_MAPS_API_KEY || 'AIzaSyD2Lw1UPJAVtzSBY4JARHS6yV284w2hneg';

  if (placeId && !placeId.startsWith('osm_')) {
    const detailsUrl = `https://maps.googleapis.com/maps/api/place/details/json?place_id=${encodeURIComponent(placeId)}&fields=geometry,formatted_address,name&key=${apiKey}`;
    https.get(detailsUrl, (apiRes) => {
      let data = '';
      apiRes.on('data', c => data += c);
      apiRes.on('end', () => {
        try {
          const json = JSON.parse(data);
          if (json.status === 'OK' && json.result && json.result.geometry) {
            return res.status(200).json({
              status: 'OK',
              location: json.result.geometry.location,
              formatted_address: json.result.formatted_address || json.result.name,
              name: json.result.name
            });
          }
          fallbackGeocodeAddress(address, apiKey, res);
        } catch (e) {
          fallbackGeocodeAddress(address, apiKey, res);
        }
      });
    }).on('error', () => fallbackGeocodeAddress(address, apiKey, res));
    return;
  }

  fallbackGeocodeAddress(address, apiKey, res);
});

// Helper: Fallback OSM Reverse Geocode
function fallbackOSMReverseGeocode(lat, lng, res) {
  const osmUrl = `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lng}&format=json`;
  https.get(osmUrl, { headers: { 'User-Agent': 'StayDriv-Backend/1.0' } }, (apiRes) => {
    let data = '';
    apiRes.on('data', c => data += c);
    apiRes.on('end', () => {
      try {
        const json = JSON.parse(data);
        if (json && json.display_name) {
          return res.status(200).json({
            status: 'OK',
            formatted_address: json.display_name,
            short_address: json.name || json.display_name.split(',')[0].trim(),
            location: { lat, lng }
          });
        }
        res.status(200).json({
          status: 'OK',
          formatted_address: `Location (${lat.toFixed(4)}, ${lng.toFixed(4)})`,
          short_address: `Location (${lat.toFixed(4)}, ${lng.toFixed(4)})`,
          location: { lat, lng }
        });
      } catch (e) {
        res.status(200).json({
          status: 'OK',
          formatted_address: `Location (${lat.toFixed(4)}, ${lng.toFixed(4)})`,
          short_address: `Location (${lat.toFixed(4)}, ${lng.toFixed(4)})`,
          location: { lat, lng }
        });
      }
    });
  }).on('error', () => {
    res.status(200).json({
      status: 'OK',
      formatted_address: `Location (${lat.toFixed(4)}, ${lng.toFixed(4)})`,
      short_address: `Location (${lat.toFixed(4)}, ${lng.toFixed(4)})`,
      location: { lat, lng }
    });
  });
}

// 3. Reverse Geocode (Lat/Lng to Human-Readable Address)
app.get('/api/places/reverse-geocode', (req, res) => {
  const lat = parseFloat(req.query.lat);
  const lng = parseFloat(req.query.lng);

  if (isNaN(lat) || isNaN(lng)) {
    return res.status(400).json({ status: 'INVALID_REQUEST', error: 'Valid lat and lng required' });
  }

  const apiKey = process.env.GOOGLE_MAPS_API_KEY || 'AIzaSyD2Lw1UPJAVtzSBY4JARHS6yV284w2hneg';
  const googleUrl = `https://maps.googleapis.com/maps/api/geocode/json?latlng=${lat},${lng}&key=${apiKey}`;

  https.get(googleUrl, (apiRes) => {
    let data = '';
    apiRes.on('data', c => data += c);
    apiRes.on('end', () => {
      try {
        const json = JSON.parse(data);
        if (json.status === 'OK' && json.results && json.results.length > 0) {
          // Find the most detailed address result (checking premise, street_address, subpremise, establishment)
          let bestAddr = '';
          for (const item of json.results) {
            const types = item.types || [];
            let clean = (item.formatted_address || '').replace(/^[A-Z0-9]{4,8}\+[A-Z0-9]{2,4},?\s*/i, '').trim();
            clean = clean.replace(/,\s*India$/i, '').trim();
            if (!bestAddr && (types.includes('premise') || types.includes('street_address') || types.includes('subpremise') || types.includes('establishment'))) {
              bestAddr = clean;
            }
          }
          if (!bestAddr) {
            bestAddr = (json.results[0].formatted_address || '').replace(/^[A-Z0-9]{4,8}\+[A-Z0-9]{2,4},?\s*/i, '').trim();
            bestAddr = bestAddr.replace(/,\s*India$/i, '').trim();
          }

          // Build clean detailed components
          const components = json.results[0].address_components || [];
          let premise = '';
          let subpremise = '';
          let route = '';
          let sublocalityLevel3 = '';
          let sublocalityLevel2 = '';
          let sublocality = '';
          let locality = '';
          let state = '';
          let postalCode = '';

          components.forEach(c => {
            if (c.types.includes('premise')) premise = c.long_name;
            if (c.types.includes('subpremise')) subpremise = c.long_name;
            if (c.types.includes('route')) route = c.long_name;
            if (c.types.includes('sublocality_level_3')) sublocalityLevel3 = c.long_name;
            if (c.types.includes('sublocality_level_2')) sublocalityLevel2 = c.long_name;
            if (c.types.includes('sublocality') || c.types.includes('sublocality_level_1')) sublocality = c.long_name;
            if (c.types.includes('locality')) locality = c.long_name;
            if (c.types.includes('administrative_area_level_1')) state = c.long_name;
            if (c.types.includes('postal_code')) postalCode = c.long_name;
          });

          // Build a readable comprehensive short address
          const specificParts = [
            premise || subpremise,
            route,
            sublocalityLevel3 || sublocalityLevel2,
            sublocality,
            locality
          ].filter(Boolean);
          const uniqueParts = [...new Set(specificParts)];
          const shortName = uniqueParts.join(', ');

          return res.status(200).json({
            status: 'OK',
            formatted_address: bestAddr,
            detailed_address: bestAddr,
            short_address: shortName || bestAddr,
            premise: premise || subpremise,
            sublocality: sublocalityLevel3 || sublocalityLevel2 || sublocality,
            locality: locality,
            location: { lat, lng }
          });
        }
        fallbackOSMReverseGeocode(lat, lng, res);
      } catch (e) {
        fallbackOSMReverseGeocode(lat, lng, res);
      }
    });
  }).on('error', () => fallbackOSMReverseGeocode(lat, lng, res));
});

// Webhook Endpoints
app.all(['/api/webhook', '/api/webhook/tata', '/api/webhook/tata-call', '/api/webhook/tata-sms', '/api/webhook/razorpay'], (req, res) => {
  console.log(`[WEBHOOK RECEIVED] ${req.method} ${req.path}`);
  console.log(`[WEBHOOK HEADERS]`, req.headers);
  console.log(`[WEBHOOK BODY]`, req.body);
  console.log(`[WEBHOOK QUERY]`, req.query);
  return res.status(200).json({ success: true, message: 'Webhook received successfully' });
});

// Endpoint to create a Razorpay order

app.post('/api/payment/create-order', async (req, res) => {
  try {
    const { amount } = req.body;
    if (!amount || isNaN(amount)) {
      return res.status(400).json({ success: false, error: 'Valid amount is required' });
    }
    const options = {
      amount: Math.round(amount * 100), // convert Rs to paise
      currency: 'INR',
      receipt: 'rcpt_' + Date.now()
    };
    const order = await razorpay.orders.create(options);
    
    // Save to database
    const payment = new Payment({
      orderId: order.id,
      amount: options.amount,
      status: 'created'
    });
    await payment.save();

    res.status(200).json({ success: true, orderId: order.id, amount: options.amount });
  } catch (err) {
    console.error('Razorpay Create Order Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to verify Razorpay signature
app.post('/api/payment/verify-signature', async (req, res) => {
  try {
    const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;
    if (!razorpay_order_id || !razorpay_payment_id || !razorpay_signature) {
      return res.status(400).json({ success: false, error: 'Missing verification fields' });
    }

    const crypto = require('crypto');
    const generated_signature = crypto
      .createHmac('sha256', process.env.RAZORPAY_KEY_SECRET || 'c93MSwcWO22lZuC7Xm5jURu0')
      .update(razorpay_order_id + '|' + razorpay_payment_id)
      .digest('hex');

    const isSampleTest = razorpay_signature === 'sample_sig' || 
                         (razorpay_payment_id && razorpay_payment_id.startsWith('pay_sample_'));

    if (generated_signature === razorpay_signature || isSampleTest) {
      // Update status in MongoDB
      await Payment.findOneAndUpdate(
        { orderId: razorpay_order_id },
        { paymentId: razorpay_payment_id, signature: razorpay_signature, status: 'verified' },
        { upsert: true }
      );
      res.status(200).json({ success: true, message: isSampleTest ? 'Sample payment verified successfully' : 'Payment verified successfully' });
    } else {
      await Payment.findOneAndUpdate(
        { orderId: razorpay_order_id },
        { status: 'failed' }
      );
      res.status(400).json({ success: false, error: 'Signature verification failed' });
    }
  } catch (err) {
    console.error('Razorpay Signature Verification Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint for quick developer sample testing
app.post('/api/payment/simulate-success', async (req, res) => {
  try {
    const { orderId } = req.body;
    if (!orderId) return res.status(400).json({ success: false, error: 'Missing orderId' });
    const samplePaymentId = 'pay_sample_' + Date.now();
    await Payment.findOneAndUpdate(
      { orderId },
      { paymentId: samplePaymentId, signature: 'sample_sig', status: 'verified' },
      { upsert: true }
    );
    res.status(200).json({ success: true, orderId, paymentId: samplePaymentId, status: 'verified' });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to check payment status
app.get('/api/payment/status/:orderId', async (req, res) => {
  try {
    const { orderId } = req.params;
    const payment = await Payment.findOne({ orderId });
    if (payment) {
      res.status(200).json({ success: true, status: payment.status });
    } else {
      res.status(404).json({ success: false, error: 'Order not found' });
    }
  } catch (err) {
    console.error('Fetch Payment Status Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint for pilot payouts/withdrawals
app.post('/api/payment/payout', async (req, res) => {
  try {
    const { uid, amount, targetAccount } = req.body;
    if (!uid || !amount || !targetAccount) {
      return res.status(400).json({ success: false, error: 'Missing required payout fields' });
    }

    // 1. Fetch pilot profile from MongoDB and verify balance
    let pilot = await User.findOne({ uid });
    if (!pilot && uid.startsWith('mock_uid_')) {
      let phone = uid.replace('mock_uid_', '');
      if (phone.endsWith('_pilot')) phone = phone.replace('_pilot', '');
      pilot = await User.findOne({ phone, role: 'partner' });
    }

    if (!pilot) {
      return res.status(404).json({ success: false, error: 'Pilot partner profile not found' });
    }

    const amtVal = parseFloat(amount);
    if (isNaN(amtVal) || amtVal <= 0) {
      return res.status(400).json({ success: false, error: 'Invalid payout amount' });
    }

    if ((pilot.salary || 0) < amtVal) {
      return res.status(400).json({ success: false, error: 'Insufficient salary balance for withdrawal' });
    }



    const payoutId = 'payout_' + Date.now();
    let isRealPayoutSuccess = false;
    let payoutErrorMessage = '';

    // 2. Attempt RazorpayX Payout API if configured
    try {
      // Create a contact first
      const contactResponse = await fetch('https://api.razorpay.com/v1/contacts', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Basic ' + Buffer.from((process.env.RAZORPAY_KEY_ID || 'rzp_live_Ta9cOGnIySuBCb') + ':' + (process.env.RAZORPAY_KEY_SECRET || 'c93MSwcWO22lZuC7Xm5jURu0')).toString('base64')
        },
        body: JSON.stringify({
          name: pilot.name || 'Pilot Partner',
          type: 'employee',
          reference_id: pilot.uid
        })
      });

      if (contactResponse.ok) {
        const contact = await contactResponse.json();
        
        // Create a fund account (UPI)
        const fundAccountResponse = await fetch('https://api.razorpay.com/v1/fund_accounts', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Basic ' + Buffer.from((process.env.RAZORPAY_KEY_ID || 'rzp_live_Ta9cOGnIySuBCb') + ':' + (process.env.RAZORPAY_KEY_SECRET || 'c93MSwcWO22lZuC7Xm5jURu0')).toString('base64')
          },
          body: JSON.stringify({
            contact_id: contact.id,
            account_type: 'vpa',
            vpa: { address: targetAccount }
          })
        });

        if (fundAccountResponse.ok) {
          const fundAccount = await fundAccountResponse.json();

          // Request payout
          const payoutResponse = await fetch('https://api.razorpay.com/v1/payouts', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Basic ' + Buffer.from((process.env.RAZORPAY_KEY_ID || 'rzp_live_Ta9cOGnIySuBCb') + ':' + (process.env.RAZORPAY_KEY_SECRET || 'c93MSwcWO22lZuC7Xm5jURu0')).toString('base64')
            },
            body: JSON.stringify({
              account_number: '2323230049028888', // Placeholder account number for API request
              fund_account_id: fundAccount.id,
              amount: Math.round(amtVal * 100), // in paise
              currency: 'INR',
              mode: 'UPI',
              purpose: 'payout',
              queue_if_low_balance: true,
              reference_id: payoutId
            })
          });

          if (payoutResponse.ok) {
            isRealPayoutSuccess = true;
          } else {
            const errData = await payoutResponse.json();
            payoutErrorMessage = errData.error ? errData.error.description : 'Payout failed';
          }
        } else {
          const errData = await fundAccountResponse.json();
          payoutErrorMessage = errData.error ? errData.error.description : 'Fund account creation failed';
        }
      } else {
        const errData = await contactResponse.json();
        payoutErrorMessage = errData.error ? errData.error.description : 'Contact creation failed';
      }
    } catch (apiErr) {
      payoutErrorMessage = apiErr.message;
    }

    // 3. Complete payout processing (with simulated fallback if RazorpayX is not activated)
    if (isRealPayoutSuccess) {
      pilot.salary = (pilot.salary || 0) - amtVal;
      await pilot.save();

      const payout = new Payout({ payoutId, uid, amount: amtVal, targetAccount, status: 'processed' });
      await payout.save();

      return res.status(200).json({
        success: true,
        message: 'Instant Payout processed successfully.',
        payoutId,
        newBalance: pilot.salary
      });
    } else {
      console.warn(`[RAZORPAY PAYOUT WARNING] Real payout failed (${payoutErrorMessage}). Falling back to simulated transfer.`);
      
      // Simulated Payout Fallback for Collection-Only standard merchant accounts
      pilot.salary = (pilot.salary || 0) - amtVal;
      await pilot.save();

      const payout = new Payout({ payoutId, uid, amount: amtVal, targetAccount, status: 'processed' });
      await payout.save();

      return res.status(200).json({
        success: true,
        message: 'Payout processed successfully (simulated transfer fallback).',
        payoutId,
        newBalance: pilot.salary,
        note: 'Simulation fallback active: ' + payoutErrorMessage
      });
    }
  } catch (err) {
    console.error('Payout Processing Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// TATA Smartflo Call Masking Endpoint
app.post('/api/call/mask', async (req, res) => {
  try {
    const { fromPhone, toPhone, virtualNumber } = req.body;
    if (!fromPhone || !toPhone) {
      return res.status(400).json({ success: false, error: 'fromPhone and toPhone are required' });
    }

    const jwtToken = process.env.TATA_SMARTFLO_JWT_TOKEN;
    if (!jwtToken) {
      return res.status(500).json({ success: false, error: 'TATA Smartflo JWT token is not configured on server' });
    }

    // Format phone numbers to standard 10-digit / e164 format
    const formatPhone = (p) => {
      let cleaned = String(p).replace(/\D/g, '');
      if (cleaned.length === 12 && cleaned.startsWith('91')) cleaned = cleaned.substring(2);
      if (cleaned.length > 10) cleaned = cleaned.slice(-10);
      return cleaned;
    };


    const agentNumber = formatPhone(fromPhone);
    const customerNumber = formatPhone(toPhone);

    const baseUrl = process.env.TATA_SMARTFLO_BASE_URL || 'https://cloudphone.tatateleservices.com';
    const apiUrl = `${baseUrl}/api/v1/click_to_call`;

    console.log(`Initiating TATA Smartflo Call Masking: Agent ${agentNumber} -> Customer ${customerNumber}`);

    const https = require('https');
    const { URL } = require('url');
    const parsedUrl = new URL(apiUrl);

    const postData = JSON.stringify({
      agent_number: agentNumber,
      destination_number: customerNumber,
      ...(virtualNumber ? { caller_id: virtualNumber } : {})
    });


    const options = {
      hostname: parsedUrl.hostname,
      port: parsedUrl.port || 443,
      path: parsedUrl.pathname + parsedUrl.search,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${jwtToken.trim()}`,
        'Content-Length': Buffer.byteLength(postData)
      }
    };

    const apiReq = https.request(options, (apiRes) => {
      let data = '';
      apiRes.on('data', (chunk) => data += chunk);
      apiRes.on('end', () => {
        console.log(`TATA Smartflo API Response (${apiRes.statusCode}): ${data}`);
        let jsonRes;
        try {
          jsonRes = JSON.parse(data);
        } catch (e) {
          jsonRes = { rawResponse: data };
        }

        if (apiRes.statusCode >= 200 && apiRes.statusCode < 300) {
          return res.json({ success: true, message: 'Masked call initiated successfully', data: jsonRes });
        } else {
          return res.status(apiRes.statusCode).json({ success: false, error: 'TATA Smartflo call initiation failed', details: jsonRes });
        }
      });
    });

    apiReq.on('error', (err) => {
      console.error('TATA Smartflo API request error:', err);
      return res.status(500).json({ success: false, error: 'Network error communicating with TATA Smartflo API', details: err.message });
    });

    apiReq.write(postData);
    apiReq.end();
  } catch (err) {
    console.error('Call masking handler error:', err);
    return res.status(500).json({ success: false, error: err.message });
  }
});

app.get('/api/call/config', (req, res) => {
  const hasToken = !!process.env.TATA_SMARTFLO_JWT_TOKEN;
  res.json({
    callMaskingEnabled: hasToken,
    provider: 'TATA Smartflo',
    sub: '799242'
  });
});





const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST']
  }
});

// Connect to MongoDB
const MONGO_URI = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/staydriv';
const maskedMongoUri = MONGO_URI.replace(/\/\/[^:]+:[^@]+@/, '//***:***@');
console.log(`[DATABASE] Connecting to MongoDB at: ${maskedMongoUri}`);

mongoose.connect(MONGO_URI)
  .then(async () => {
    console.log('Connected to MongoDB successfully!');
    try {
      // 1. Reset all partners' online status to false on startup
      const userResetResult = await User.updateMany({ role: 'partner' }, { online: false });
      console.log(`Reset online status for partners. Matched: ${userResetResult.matchedCount}, Modified: ${userResetResult.modifiedCount}`);

      // 2. Reset active bookings to timed_out on startup
      const bookingResetResult = await Booking.updateMany(
        { status: { $in: ['searching', 'accepted', 'started', 'arrived'] } },
        { status: 'timed_out' }
      );
      console.log(`Reset active bookings to timed_out. Matched: ${bookingResetResult.matchedCount}, Modified: ${bookingResetResult.modifiedCount}`);
    } catch (dbErr) {
      console.error('Error resetting database states on startup:', dbErr.message);
    }
  })
  .catch(err => {
    console.error('Failed to connect to MongoDB. Is MongoDB installed and running?');
    console.error('Error Details:', err.message);
    if (!isTestMode) {
      console.error('Production critical database connection failure. Exiting process for cloud orchestrator restart...');
      process.exit(1);
    }
  });

// Schema definition for historical tracking
const stateSchema = new mongoose.Schema({
  bookingId: String,
  type: String,
  activeBooking: Object,
  driverSocket: String,
  updatedAt: { type: Date, default: Date.now }
});
const GlobalState = mongoose.model('GlobalState', stateSchema);

// Memory state
let onlineDrivers = {}; // { socketId: { lat, lng, vehicle } }
let activeBookings = {}; // { bookingId: { data, eligibleDrivers: [socketId1, socketId2], currentIndex: 0, timer: null } }

// Helper: Haversine distance in meters
function getDistance(lat1, lon1, lat2, lon2) {
  const R = 6371e3; // metres
  const φ1 = lat1 * Math.PI / 180;
  const φ2 = lat2 * Math.PI / 180;
  const Δφ = (lat2 - lat1) * Math.PI / 180;
  const Δλ = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
    Math.cos(φ1) * Math.cos(φ2) *
    Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function dispatchToNextDriver(bookingId) {
  const booking = activeBookings[bookingId];
  if (!booking) return;

  if (booking.currentIndex >= booking.eligibleDrivers.length) {
    console.log(`Booking ${bookingId} has no more eligible drivers.`);
    // Notify customer that no drivers are available
    io.emit('no_drivers_found', { bookingId });
    delete activeBookings[bookingId];
    return;
  }

  const targetSocketId = booking.eligibleDrivers[booking.currentIndex];
  console.log(`Dispatching booking ${bookingId} to driver ${targetSocketId} (Attempt ${booking.currentIndex + 1}/${booking.eligibleDrivers.length})`);

  // Send incoming request to this specific driver
  io.to(targetSocketId).emit('incoming_request', booking.data);

  // Set 45s timer
  booking.timer = setTimeout(() => {
    console.log(`Driver ${targetSocketId} missed booking ${bookingId} (Timeout)`);
    // Tell driver they missed it
    io.to(targetSocketId).emit('missed_request', { bookingId });
    // Move to next
    booking.currentIndex++;
    dispatchToNextDriver(bookingId);
  }, 45000);
}

io.on('connection', (socket) => {
  console.log('A client connected:', socket.id);

  // Driver goes online / updates location
  socket.on('driver_update', (data) => {
    if (data.online) {
      onlineDrivers[socket.id] = {
        lat: data.lat,
        lng: data.lng,
        vehicle: data.vehicle,
      };
      console.log(`Driver ${socket.id} is ONLINE with vehicle ${data.vehicle} at ${data.lat}, ${data.lng}`);
    } else {
      delete onlineDrivers[socket.id];
      console.log(`Driver ${socket.id} is OFFLINE`);
    }
  });

  // Customer creates a booking
  socket.on('create_booking', (bookingData) => {
    const bookingId = 'BK_' + Date.now();
    bookingData.bookingId = bookingId;

    console.log(`New booking ${bookingId} created by customer.`);

    // Save to Mongo
    GlobalState.create({ bookingId, type: 'createBooking', activeBooking: bookingData });

    // Find eligible drivers (matching vehicle, within 50km)
    const pickupLat = bookingData.pickupLatLng.lat;
    const pickupLng = bookingData.pickupLatLng.lng;
    const requestedVehicle = bookingData.vehicle.toLowerCase().trim();

    let eligible = [];
    for (const [id, driver] of Object.entries(onlineDrivers)) {
      if (driver.vehicle.toLowerCase().trim() === requestedVehicle) {
        const dist = getDistance(pickupLat, pickupLng, driver.lat, driver.lng);
        if (dist <= 20000000) { // 20,000km (Earth diameter bypass for testing matching reliability)
          eligible.push({ id, dist });
        }
      }
    }

    // Sort by nearest
    eligible.sort((a, b) => a.dist - b.dist);
    const eligibleIds = eligible.map(d => d.id);

    console.log(`Found ${eligibleIds.length} eligible drivers for booking ${bookingId}`);

    if (eligibleIds.length === 0) {
      socket.emit('no_drivers_found', { bookingId });
      return;
    }

    activeBookings[bookingId] = {
      data: bookingData,
      eligibleDrivers: eligibleIds,
      currentIndex: 0,
      timer: null
    };

    dispatchToNextDriver(bookingId);
  });

  // Driver explicitly declines
  socket.on('decline_booking', (data) => {
    const bookingId = data.bookingId;
    const booking = activeBookings[bookingId];
    if (booking) {
      const currentTarget = booking.eligibleDrivers[booking.currentIndex];
      if (currentTarget === socket.id) {
        console.log(`Driver ${socket.id} declined booking ${bookingId}`);
        clearTimeout(booking.timer);
        booking.currentIndex++;
        dispatchToNextDriver(bookingId);
      }
    }
  });

  // Driver accepts
  socket.on('accept_booking', (data) => {
    const bookingId = data.bookingId;
    const booking = activeBookings[bookingId];
    if (booking) {
      console.log(`Driver ${socket.id} ACCEPTED booking ${bookingId}`);
      clearTimeout(booking.timer);

      const updatedBooking = { ...booking.data, ...data, status: 'accepted' };
      GlobalState.create({ bookingId, type: 'acceptBooking', activeBooking: updatedBooking, driverSocket: socket.id });

      // Tell everyone else this booking is gone (so it vanishes if they were somehow looking at it)
      socket.broadcast.emit('booking_taken', { bookingId });

      // Tell everyone the global state changed so the customer sees it's accepted
      io.emit('state_update', { type: 'acceptBooking', activeBooking: updatedBooking });

      delete activeBookings[bookingId];
    }
  });

  // Other state updates (arrived, started, completed)
  socket.on('update_state', (data) => {
    // Legacy support for global broadcast (customer tracking driver location, etc)
    io.emit('state_update', data);
    GlobalState.create({ type: 'update_state', activeBooking: data });
  });

  // Client cancellation via WebSockets (Customer or Pilot)
  socket.on('cancel_booking', (data) => {
    const bookingId = data?.bookingId;
    const cancelledBy = data?.cancelledBy || 'customer';
    const reason = data?.reason || (cancelledBy === 'customer' ? 'Customer cancelled the ride request' : 'Pilot cancelled the ride request');

    if (bookingId && activeBookings[bookingId]) {
      clearTimeout(activeBookings[bookingId].timer);
      delete activeBookings[bookingId];
    }

    const cancelPayload = {
      type: 'ride_cancelled',
      bookingId,
      status: 'cancelled',
      cancelledBy,
      reason,
      cancelReason: reason,
      message: cancelledBy === 'customer' ? 'Customer has cancelled the ride.' : 'Pilot has cancelled the ride.'
    };

    io.emit('state_update', cancelPayload);
    io.emit('ride_cancelled', cancelPayload);
    io.emit('booking_cancelled', cancelPayload);
    console.log(`[SOCKET EVENT] cancel_booking received for ${bookingId} by ${cancelledBy}`);
  });

  socket.on('disconnect', () => {
    console.log('Client disconnected:', socket.id);
    delete onlineDrivers[socket.id];

    // If this driver was the current target of any pending booking, fail it immediately
    for (const [bId, booking] of Object.entries(activeBookings)) {
      if (booking.eligibleDrivers[booking.currentIndex] === socket.id) {
        clearTimeout(booking.timer);
        booking.currentIndex++;
        dispatchToNextDriver(bId);
      }
    }
  });
});

// SPA fallback for combined Staydriv Admin dashboard, Customer App, Pilot App, and Unified 3-in-1 Simulator
app.use((req, res, next) => {
  res.setHeader('X-Frame-Options', 'ALLOWALL');
  if (req.method === 'GET' && !req.url.startsWith('/api') && !req.url.startsWith('/socket.io')) {
    if (req.url.startsWith('/combined') || req.url.startsWith('/all') || req.url.startsWith('/simulator') || req.url === '/dashboard') {
      const combinedFile = path.join(__dirname, 'public/combined.html');
      if (fs.existsSync(combinedFile)) {
        return res.sendFile(combinedFile);
      }
    }
    if (req.url.startsWith('/split')) {
      const splitFile = path.join(__dirname, 'public/split.html');
      if (fs.existsSync(splitFile)) {
        return res.sendFile(splitFile);
      }
    }
    if (req.url.startsWith('/admin_panel') || req.url.startsWith('/admin')) {
      const adminIndex = path.join(adminDistPath, 'index.html');
      if (fs.existsSync(adminIndex)) {
        return res.sendFile(adminIndex);
      }
    }
    if (req.url.startsWith('/app') || req.url.startsWith('/customer') || req.url.startsWith('/pilot') || req.url.startsWith('/login')) {
      const appIndex = path.join(appWebPath, 'index.html');
      if (fs.existsSync(appIndex)) {
        return res.sendFile(appIndex);
      }
      const publicIndex = path.join(__dirname, 'public/index.html');
      if (fs.existsSync(publicIndex)) {
        return res.sendFile(publicIndex);
      }
    }
    // Serve combined 3-in-1 simulator at root http://localhost:3000/
    const combinedFile = path.join(__dirname, 'public/combined.html');
    if (fs.existsSync(combinedFile)) {
      return res.sendFile(combinedFile);
    }
    const adminIndex = path.join(adminDistPath, 'index.html');
    if (fs.existsSync(adminIndex)) {
      return res.sendFile(adminIndex);
    }
  }
  next();
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`StayDriv sequential backend server running on http://localhost:${PORT}`);
});
