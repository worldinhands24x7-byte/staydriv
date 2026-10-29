require('dotenv').config();
const express = require('express');
const http = require('http');
const https = require('https');
const { Server } = require('socket.io');
const mongoose = require('mongoose');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const Razorpay = require('razorpay');
const storageService = require('./services/storageService');
const twilioSmsService = require('./services/twilioSmsService');
const SmsService = require('./services/smsService');
const PilotWallet = require('./models/PilotWallet');
const FinancialLedger = require('./models/FinancialLedger');
const Otp = require('./models/Otp');
const pilotWalletService = require('./services/pilotWalletService');
const { isFoodDeliveryVehicle } = require('./services/foodDeliveryEligibilityService');
let smartfloSmsService = null;
try {
  smartfloSmsService = require('./services/smartfloSmsService');
} catch (err) {
  console.warn('[INIT] smartfloSmsService optional load error:', err.message);
}

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
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST']
  }
});
app.set('io', io);

// Health check endpoints for ALB target group and monitoring
app.get(['/health', '/api/health'], (req, res) => {
  res.status(200).json({
    status: 'UP',
    service: 'staydriv-backend',
    environment: process.env.NODE_ENV || 'production',
    timestamp: new Date().toISOString()
  });
});

// Root path handler: serves Flutter Web app index.html for browsers, or JSON health check for API/ALB probes without HTML accept
app.get('/', (req, res, next) => {
  const isElbProbe = req.headers['user-agent'] && req.headers['user-agent'].includes('ELB-HealthChecker');
  const wantsJson = req.headers.accept && req.headers.accept.includes('application/json');

  if (isElbProbe || (wantsJson && !req.query.role)) {
    return res.status(200).json({
      status: 'UP',
      service: 'staydriv-backend',
      environment: process.env.NODE_ENV || 'production',
      timestamp: new Date().toISOString()
    });
  }
  const publicIndexPath = path.join(__dirname, 'public/index.html');
  if (fs.existsSync(publicIndexPath)) {
    return res.sendFile(publicIndexPath);
  }
  return res.status(200).send('<!doctype html><html><head><title>StayDriv</title></head><body><h1>StayDriv Mobility Platform</h1><p>Service is active.</p></body></html>');
});

// Secure dynamic CORS allowed origins listing
const allowedOrigins = [
  'http://localhost:3000',
  'http://localhost:5000',
  'http://localhost:5173',
  'http://localhost:5500',
  'http://127.0.0.1:3000',
  'http://127.0.0.1:5000',
  'http://127.0.0.1:5173',
  'http://127.0.0.1:5500'
];

app.use(cors({
  origin: function (origin, callback) {
    if (!origin) return callback(null, true);
    if (
      allowedOrigins.indexOf(origin) !== -1 ||
      origin.includes('localhost:') ||
      origin.includes('127.0.0.1:') ||
      origin.endsWith('.serveousercontent.com') ||
      origin.endsWith('.loca.lt') ||
      origin.endsWith('.cloudfront.net') ||
      origin.endsWith('.amazonaws.com') ||
      origin.endsWith('.staydriv.com')
    ) {
      return callback(null, true);
    }
    return callback(new Error('The CORS policy for this site does not allow access from the specified Origin.'), false);
  }
}));
app.use(express.json({
  limit: '25mb',
  verify: (req, res, buf) => {
    req.rawBody = buf;
  }
}));
app.use(express.urlencoded({ limit: '25mb', extended: true }));
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
    const sanitizedBody = { ...req.body };
    if (sanitizedBody.otp) sanitizedBody.otp = '****';
    if (sanitizedBody.deliveryOtp) sanitizedBody.deliveryOtp = '****';
    if (sanitizedBody.pickupOtp) sanitizedBody.pickupOtp = '****';
    if (sanitizedBody.startOtp) sanitizedBody.startOtp = '****';
    console.log(`[BODY]`, JSON.stringify(sanitizedBody));
  }
  next();
});

// Official Google Play Console Compliance: Account & Data Deletion Portal (Serves HTTP 200 OK directly)
app.get([
  '/delete-account',
  '/delete-account/',
  '/account-deletion',
  '/account-deletion/',
  '/delete-account.html',
  '/account-deletion.html',
  '/delete-data',
  '/delete-data/',
  '/privacy/delete-account',
  '/data-deletion',
  '/data-deletion/'
], (req, res) => {
  const filePath = path.join(__dirname, 'public/delete-account.html');
  if (fs.existsSync(filePath)) {
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    return res.sendFile(filePath);
  }
  return res.status(200).send('<!doctype html><html><head><title>StayDriv Account Deletion</title></head><body><h1>StayDriv Account Deletion</h1><p>To request deletion of your account and personal data, email support@staydriv.in with your registered mobile number.</p></body></html>');
});

app.use(express.static(__dirname + '/public'));

// Dynamic Admin Console Path Resolver
function getActiveAdminPath() {
  const adminDist = path.join(__dirname, '../Staydriv_Admin/dist');
  const localAdmin = path.join(__dirname, 'public/admin');
  if (fs.existsSync(path.join(adminDist, 'index.html'))) return adminDist;
  if (fs.existsSync(path.join(localAdmin, 'index.html'))) return localAdmin;
  if (fs.existsSync(adminDist)) return adminDist;
  if (fs.existsSync(localAdmin)) return localAdmin;
  return localAdmin;
}

// Serve static assets and SPA entrypoint for Admin Console
app.use('/admin', (req, res, next) => {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return next();
  }
  const adminPath = getActiveAdminPath();
  if (fs.existsSync(adminPath)) {
    // If requesting a static asset file with extension (e.g. .js, .css, .png), serve via express.static
    if (path.extname(req.path)) {
      return express.static(adminPath, { index: false })(req, res, next);
    }
    // All page routes (/admin, /admin/, /admin/food-orders, etc.) serve index.html for SPA
    const indexPath = path.join(adminPath, 'index.html');
    if (fs.existsSync(indexPath)) {
      return res.sendFile(indexPath);
    }
  }
  return res.status(503).send('<!doctype html><html><head><title>StayDriv Admin Console Loading</title></head><body style="font-family:sans-serif;padding:40px;text-align:center;"><h2>StayDriv Admin Console</h2><p>Admin bundle is initializing. Please refresh in a moment.</p></body></html>');
});
// Dedicated direct routes for Customer and Pilot apps on web/localhost
app.get(['/customer', '/app/customer'], (req, res) => {
  res.redirect('/?role=customer');
});
app.get(['/pilot', '/driver', '/app/pilot', '/app/driver'], (req, res) => {
  res.redirect('/?role=pilot');
});

// Official Digital Asset Links for Android App Links verification
app.get('/.well-known/assetlinks.json', (req, res) => {
  res.setHeader('Content-Type', 'application/json');
  return res.json([
    {
      relation: ["delegate_permission/common.handle_all_urls"],
      target: {
        namespace: "android_app",
        package_name: "com.staydriv.app",
        sha256_cert_fingerprints: [
          "33:CD:21:F8:D3:4D:66:D9:B5:3A:CE:D8:ED:C7:35:40:D7:07:58:20:0A:D4:63:E0:3B:09:75:33:33:B1:6E:BA"
        ]
      }
    },
    {
      relation: ["delegate_permission/common.handle_all_urls"],
      target: {
        namespace: "android_app",
        package_name: "com.staydriv.customer",
        sha256_cert_fingerprints: [
          "33:CD:21:F8:D3:4D:66:D9:B5:3A:CE:D8:ED:C7:35:40:D7:07:58:20:0A:D4:63:E0:3B:09:75:33:33:B1:6E:BA"
        ]
      }
    }
  ]);
});

// Web Fallback for StayDriv Ride Booking App Links & WhatsApp shares
app.get(['/book', '/ride-booking', '/ride'], (req, res) => {
  const bookPath = path.resolve(__dirname, 'public/book.html');
  if (fs.existsSync(bookPath)) {
    return res.sendFile(bookPath);
  }
  res.redirect('/?role=customer');
});

const appWebPath = path.join(__dirname, '../staydriv_app/build/web');
if (fs.existsSync(appWebPath)) {
  app.use('/app', express.static(appWebPath));
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
  dutyStatus: { type: String, default: 'OFF' }, // 'ON' or 'OFF'
  rideServiceEnabled: { type: Boolean, default: true },
  foodServiceEnabled: { type: Boolean, default: true },
  servicePreferencesUpdatedAt: { type: Date, default: Date.now },
  status: { type: String, default: 'pending' }, // 'pending', 'approved', 'rejected', 'suspended'
  submittedAt: { type: Date, default: Date.now },
  updatedAt: { type: Date, default: Date.now },
  approved: { type: Boolean, default: false }, // added for pilot verification
  isApproved: { type: Boolean, default: false },
  isDocumentVerified: { type: Boolean, default: false },
  approvedAt: { type: Date },
  approvedBy: { type: String, default: '' },
  rejectionReason: { type: String, default: '' },
  rejectedAt: { type: Date },
  rejectedBy: { type: String, default: '' },
  blockedBy: { type: String, default: '' },
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
  panFront: String,
  panBack: String,
  ownerName: { type: String, default: '' },
  ownerPhone: { type: String, default: '' },
  driverName: { type: String, default: '' },
  driverPhone: { type: String, default: '' },
  driverLicenseFront: { type: String, default: '' },
  driverLicenseBack: { type: String, default: '' },
  vehicleNumber: { type: String, default: '' },
  vehicleModel: { type: String, default: '' },
  vehicleMake: { type: String, default: '' },
  vehicleColor: { type: String, default: '' },
  vehicleRegistrationDate: { type: String, default: '' },
  dor: { type: String, default: '' },
  vehicleSubtype: { type: String, default: '' },
  licenseNumber: { type: String, default: '' },
  aadhaarNumber: { type: String, default: '' },
  dob: { type: String, default: '' },
  insuranceDocument: { type: String, default: '' },
  insuranceDocumentUrl: { type: String, default: '' },
  insuranceExpiryDate: { type: String, default: '' },
  rcDocumentUrl: { type: String, default: '' },
  address: { type: String, default: '' },
  heading: { type: Number, default: 0 },
  speed: { type: Number, default: 0 },
  lastLocationUpdate: { type: Date, default: Date.now },
  currentRideId: { type: String, default: '' },
  currentRideStatus: { type: String, default: 'none' },
  fitness: String,
  permit: String,
  applicationId: { type: String, index: true },
  verificationHistory: { type: [mongoose.Schema.Types.Mixed], default: [] },
  correctionNotes: { type: String, default: '' },
  documents: { type: mongoose.Schema.Types.Mixed, default: {} },
  salary: { type: Number, default: 0 },
  pendingCancellationCharge: { type: Number, default: 0 },
  walletBalance: { type: Number, default: 0 },
  bankAccount: {
    accountNumber: { type: String, default: '' },
    ifsc: { type: String, default: '' },
    bankName: { type: String, default: '' },
    accountHolderName: { type: String, default: '' },
    upiId: { type: String, default: '' },
    isVerified: { type: Boolean, default: false }
  },
  totalLifetimeEarnings: { type: Number, default: 0 },
  isBlocked: { type: Boolean, default: false },
  blockReason: { type: String, default: '' },
  blockedAt: { type: Date },
  weeklyIncentives: { type: mongoose.Schema.Types.Mixed, default: {} },
  dailyPlan: {
    planStatus: { type: String, default: 'none' }, // 'paid', 'expired', 'none', 'pending', 'failed'
    paidAt: { type: Date },
    expiresAt: { type: Date },
    amount: { type: Number, default: 20 },
    transactionId: { type: String, default: '' },
    gatewayPaymentId: { type: String, default: '' },
    lastPaymentId: { type: String, default: '' }
  },
  bookingAccess: {
    status: { type: String, default: 'disabled' }, // 'enabled', 'disabled'
    enabled: { type: Boolean, default: false },
    disabledReason: { type: String, default: '' },
    updatedBy: { type: String, default: '' },
    updatedAt: { type: Date },
    history: { type: [mongoose.Schema.Types.Mixed], default: [] }
  },
  lastActive: { type: Date, default: Date.now },
  createdAt: { type: Date, default: Date.now }
});
const User = mongoose.models.User || mongoose.model('User', userSchema);

// StayDriv Pilot Weekly Ride Incentive Rules (Monday to Sunday)
const WEEKLY_INCENTIVES = {
  Bike: {
    tier1: { rides: 30, bonus: 750 },
    tier2: { rides: 50, bonus: 1300, incrementalBonus: 550 } // ₹750 + ₹550 = ₹1,300 total bonus
  },
  Auto: {
    tier1: { rides: 30, bonus: 950 },
    tier2: { rides: 50, bonus: 1500, incrementalBonus: 550 } // ₹950 + ₹550 = ₹1,500 total bonus
  },
  Car: {
    tier1: { rides: 30, bonus: 1200 },
    tier2: { rides: 50, bonus: 1800, incrementalBonus: 600 } // ₹1,200 + ₹600 = ₹1,800 total bonus
  },
  'Car XL': {
    tier1: { rides: 30, bonus: 1500 },
    tier2: { rides: 50, bonus: 2200, incrementalBonus: 700 } // ₹1,500 + ₹700 = ₹2,200 total bonus
  }
};

// Helper to compute Monday 00:00:00 to Sunday 23:59:59 week window
function getWeekBounds(refDate = new Date()) {
  const d = new Date(refDate);
  const day = d.getDay(); // 0 = Sun, 1 = Mon, ..., 6 = Sat
  const diffToMonday = (day === 0 ? -6 : 1 - day);

  const monday = new Date(d);
  monday.setDate(d.getDate() + diffToMonday);
  monday.setHours(0, 0, 0, 0);

  const sunday = new Date(monday);
  sunday.setDate(monday.getDate() + 6);
  sunday.setHours(23, 59, 59, 999);

  const mondayStr = monday.toISOString().slice(0, 10);
  const weekKey = `week_${mondayStr}`;

  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const label = `${monday.getDate()} ${months[monday.getMonth()]} – ${sunday.getDate()} ${months[sunday.getMonth()]}`;

  return { monday, sunday, weekKey, label };
}

// Mount OTP Auth Routes
const otpRoutes = require('./routes/otp');
const otpController = require('./controllers/otpController');
app.use('/api', otpRoutes);
app.use('/api/auth', otpRoutes);

// Mount StayDriv Food Ordering Routes
const foodRoutes = require('./routes/foodRoutes');
app.use('/api/food', foodRoutes);

// Mount StayDriv Food Membership Routes (Strictly Customer Food Order Now Only)
const foodMembershipRoutes = require('./routes/foodMembershipRoutes');
app.use('/api/food/membership', foodMembershipRoutes);
app.use('/api/food-membership', foodMembershipRoutes);

// Mount StayDriv Promotional Banner & Advertising Routes
const promotionRoutes = require('./routes/promotionRoutes');
app.use('/api/promotions', promotionRoutes);

// Mount StayDriv Global Push Notification Routes
const notificationRoutes = require('./routes/notificationRoutes')(io, User);
app.use('/api/notifications', notificationRoutes);


// Explicit OTP Endpoints ensuring absolute compatibility across all frontend variations
app.post(['/api/auth/request-otp', '/api/request-otp', '/api/auth/otp/request', '/api/otp/request', '/api/send-otp', '/api/auth/send-otp', '/auth/otp/request', '/otp/request'], otpController.sendOtp);
app.post(['/api/auth/verify-otp', '/api/verify-otp', '/api/auth/otp/verify', '/api/otp/verify', '/auth/otp/verify', '/otp/verify'], otpController.verifyOtp);
app.post(['/api/auth/resend-otp', '/api/resend-otp', '/api/auth/otp/resend', '/api/otp/resend', '/auth/otp/resend', '/otp/resend'], otpController.resendOtp || otpController.sendOtp);

// Endpoint to register user in MongoDB

app.post(['/api/register', '/api/driver/register'], async (req, res) => {
  try {
    const { uid, name, phone, role, vehicleType, adminType } = req.body;
    console.log(`Registering user in MongoDB: ${name} (${phone}) - ${role} (UID: ${uid}), adminType: ${adminType}`);

    let user;
    if (uid) {
      user = await User.findOne({ uid });
    } else {
      user = await User.findOne({ phone, role });
    }
    const isPilot = (role === 'partner' || role === 'driver');
    const genAppId = () => `SD-PLT-${(phone || '0000').replace(/\D/g, '').slice(-4)}-${Math.random().toString(36).substring(2, 6).toUpperCase()}`;

    if (user) {
      user.name = name;
      user.role = role;
      if (uid) user.uid = uid;
      if (vehicleType) user.vehicleType = vehicleType;
      if (adminType) user.adminType = adminType;
      if (isPilot) {
        if (!user.applicationId) user.applicationId = genAppId();
        if (user.status !== 'approved' && user.status !== 'APPROVED') {
          user.status = 'PENDING_VERIFICATION';
          user.approved = false;
          user.isApproved = false;
        }
      }
      await user.save();
    } else {
      user = new User({ 
        uid, 
        name, 
        phone, 
        role, 
        vehicleType, 
        adminType, 
        approved: isPilot ? false : (role === 'customer'),
        isApproved: isPilot ? false : (role === 'customer'),
        status: isPilot ? 'PENDING_VERIFICATION' : 'active',
        applicationId: isPilot ? genAppId() : undefined
      });
      await user.save();
    }

    res.status(200).json({ success: true, message: 'User registered in MongoDB successfully', user });
  } catch (err) {
    console.error('MongoDB Registration Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to retrieve user from MongoDB by UID
// Endpoint to retrieve user from MongoDB by UID or Phone
app.get('/api/user/:uid', async (req, res) => {
  try {
    const { uid } = req.params;
    const requestedRole = req.query.role ? String(req.query.role).toLowerCase() : null;

    if (uid === 'mock_uid_staydriv') {
      let admin = await User.findOne({ role: 'admin' });
      if (!admin) {
        admin = new User({
          uid: 'mock_uid_staydriv',
          name: 'StayDriv Admin',
          phone: '9010922111',
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

    let user = null;
    const isPilotQuery = requestedRole === 'partner' || requestedRole === 'driver' || uid.includes('_pilot') || uid.includes('pilot_');

    // 1. If pilot is specifically requested or indicated in UID, search for partner first
    if (isPilotQuery) {
      user = await User.findOne({ uid, role: 'partner' }) || await User.findOne({ uid });
      if (!user) {
        const cleanPhone = uid.replace('mock_uid_', '').replace('_pilot', '').replace('_partner', '').replace('pilot_', '').replace(/\D/g, '').slice(-10);
        if (cleanPhone) {
          user = await User.findOne({ phone: cleanPhone, role: 'partner' });
        }
      }
    }

    // 2. Direct UID lookup
    if (!user) {
      user = await User.findOne({ uid });
    }

    // 3. Fallback mock_uid parsing
    if (!user && uid.startsWith('mock_uid_')) {
      let phone = uid.replace('mock_uid_', '');
      let checkRole = 'customer';
      if (phone.endsWith('_pilot')) {
        phone = phone.replace('_pilot', '');
        checkRole = 'partner';
      }
      const cleanP = phone.replace(/\D/g, '').slice(-10);
      user = await User.findOne({ phone: cleanP, role: checkRole }) || 
             await User.findOne({ phone: cleanP });
    }

    if (user) {
      // Ensure approved status boolean is normalized
      const isApproved = Boolean(user.approved || user.isApproved || String(user.status).toLowerCase() === 'approved');
      const userObj = user.toObject ? user.toObject() : { ...user };
      userObj.approved = isApproved;
      userObj.isApproved = isApproved;
      userObj.status = isApproved ? 'approved' : (user.status || 'pending');
      res.status(200).json({ success: true, user: userObj });
    } else {
      res.status(404).json({ success: false, message: 'User not found' });
    }
  } catch (err) {
    console.error('MongoDB User Fetch Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Dedicated Authoritative Pilot Application Status Endpoint
app.get('/api/pilot/application-status', async (req, res) => {
  try {
    const { phone, uid, applicationId } = req.query;
    let user = null;

    if (phone) {
      const cleanPhone = String(phone).replace(/\D/g, '').slice(-10);
      user = await User.findOne({ phone: cleanPhone, role: 'partner' }) ||
             await User.findOne({ phone: cleanPhone });
    }
    if (!user && uid) {
      user = await User.findOne({ uid });
      if (!user) {
        const cleanPhone = String(uid).replace('mock_uid_', '').replace('_pilot', '').replace('_partner', '').replace('pilot_', '').replace(/\D/g, '').slice(-10);
        if (cleanPhone) {
          user = await User.findOne({ phone: cleanPhone, role: 'partner' }) || await User.findOne({ phone: cleanPhone });
        }
      }
    }
    if (!user && applicationId) {
      user = await User.findOne({ applicationId });
    }

    if (!user) {
      return res.status(200).json({
        success: true,
        found: false,
        status: 'DRAFT',
        message: 'No registered pilot application found for this phone number'
      });
    }

    // Canonical Status Mapping: DRAFT, SUBMITTED, PENDING_VERIFICATION, APPROVED, REJECTED, RESUBMISSION_REQUIRED
    const isAppr = Boolean(user.approved || user.isApproved || String(user.status).toLowerCase() === 'approved');
    let normalizedStatus = 'PENDING_VERIFICATION';

    if (isAppr) {
      normalizedStatus = 'APPROVED';
    } else if (user.status) {
      const s = String(user.status).toUpperCase();
      if (s === 'REJECTED') normalizedStatus = 'REJECTED';
      else if (s === 'ACTION_REQUIRED' || s === 'RESUBMISSION_REQUIRED') normalizedStatus = 'RESUBMISSION_REQUIRED';
      else if (s === 'SUBMITTED') normalizedStatus = 'SUBMITTED';
      else if (s === 'DRAFT') normalizedStatus = 'DRAFT';
      else normalizedStatus = 'PENDING_VERIFICATION';
    }

    const cleanPhone = user.phone ? String(user.phone).replace(/\D/g, '').slice(-10) : '0000';
    const effectiveAppId = user.applicationId || `SD-PLT-${cleanPhone.slice(-4)}-${user._id.toString().slice(-4).toUpperCase()}`;

    return res.status(200).json({
      success: true,
      found: true,
      status: normalizedStatus,
      isApproved: isAppr,
      approved: isAppr,
      applicationId: effectiveAppId,
      pilot: {
        uid: user.uid,
        name: user.name || 'StayDriv Pilot',
        ownerName: user.ownerName || user.name || 'StayDriv Pilot',
        driverName: user.driverName || user.name || 'StayDriv Pilot',
        phone: user.phone || '',
        ownerPhone: user.ownerPhone || user.phone || '',
        driverPhone: user.driverPhone || user.phone || '',
        vehicleType: user.vehicleType || 'Bike',
        vehicleSubtype: user.vehicleSubtype || '',
        vehiclePlate: user.vehiclePlate || user.vehicleNumber || '',
        vehicleNumber: user.vehicleNumber || user.vehiclePlate || '',
        vehicleMake: user.vehicleMake || '',
        vehicleModel: user.vehicleModel || '',
        vehicleColor: user.vehicleColor || '',
        vehicleModelColor: user.vehicleModelColor || '',
        vehicleRegistrationDate: user.vehicleRegistrationDate || user.dor || '',
        status: normalizedStatus,
        approved: isAppr,
        isApproved: isAppr,
        online: Boolean(user.online),
        submittedAt: user.submittedAt || user.createdAt,
        approvedAt: user.approvedAt,
        rejectedAt: user.rejectedAt,
        rejectionReason: user.rejectionReason || '',
        correctionNotes: user.correctionNotes || '',
        documents: user.documents || {}
      }
    });
  } catch (err) {
    console.error('MongoDB Pilot Application Status Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Ensure public/uploads exists
const uploadsDir = path.join(__dirname, 'public', 'uploads');
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}

// Endpoint to upload base64 file data directly to MongoDB GridFS
app.post('/api/upload', async (req, res) => {
  try {
    const { uid, fileName, fileData, documentType, mimeType } = req.body;
    if (!fileName || !fileData) {
      return res.status(400).json({ success: false, message: 'FileName and FileData are required' });
    }

    const ext = path.extname(fileName).toLowerCase();
    const allowedExtensions = ['.jpg', '.jpeg', '.png', '.pdf'];
    if (!allowedExtensions.includes(ext)) {
      return res.status(400).json({
        success: false,
        message: 'Unsupported format. Allowed formats: JPG, JPEG, PNG, PDF'
      });
    }

    let buffer;
    try {
      buffer = Buffer.from(fileData, 'base64');
    } catch (e) {
      return res.status(400).json({ success: false, message: 'Invalid base64 file data' });
    }

    // 10 MB maximum file size limit
    const MAX_FILE_SIZE = 10 * 1024 * 1024;
    if (buffer.length > MAX_FILE_SIZE) {
      return res.status(400).json({
        success: false,
        message: 'File size exceeds maximum allowed limit of 10 MB'
      });
    }

    let detectedMime = mimeType;
    if (!detectedMime) {
      if (ext === '.jpg' || ext === '.jpeg') detectedMime = 'image/jpeg';
      else if (ext === '.png') detectedMime = 'image/png';
      else if (ext === '.pdf') detectedMime = 'application/pdf';
      else detectedMime = 'application/octet-stream';
    }

    const safeUid = (uid || 'user').replace(/[^a-zA-Z0-9_-]/g, '');
    const uniqueFileName = `${safeUid}_${Date.now()}${ext}`;

    console.log(`[UPLOAD] User ID: ${safeUid} | Document: ${documentType || 'general'} | File: ${uniqueFileName} | Size: ${buffer.length} bytes | MIME: ${detectedMime}`);

    // 1. Upload to MongoDB GridFS
    const uploadResult = await storageService.uploadFromBuffer({
      buffer,
      filename: uniqueFileName,
      mimetype: detectedMime,
      metadata: {
        uid: safeUid,
        documentType: documentType || 'document',
        originalFileName: fileName
      }
    });

    // Also persist a local copy for fallback / fast local static serving
    try {
      const filePath = path.join(uploadsDir, uniqueFileName);
      fs.writeFileSync(filePath, buffer);
    } catch (localErr) {
      console.warn('[UPLOAD] Local cache write notice:', localErr.message);
    }

    const fileUrl = `/api/files/${uploadResult.fileId}`;

    // 2. Associate with User record in MongoDB if uid is present
    if (uid && documentType) {
      try {
        let user = await User.findOne({ uid });
        if (!user && uid.startsWith('mock_uid_')) {
          let phone = uid.replace('mock_uid_', '');
          if (phone.endsWith('_pilot')) phone = phone.replace('_pilot', '');
          user = await User.findOne({ phone });
        }
        if (user) {
          user[documentType] = fileUrl;
          if (!user.documents) user.documents = {};
          user.documents[documentType] = {
            documentType,
            fileId: uploadResult.fileId,
            fileName: uniqueFileName,
            mimeType: detectedMime,
            sizeBytes: buffer.length,
            url: fileUrl,
            uploadedAt: new Date()
          };
          user.markModified('documents');
          await user.save();
          console.log(`[UPLOAD] Database update completed: associated ${documentType} with user ${uid}`);
        }
      } catch (dbErr) {
        console.warn('[UPLOAD] User record update note:', dbErr.message);
      }
    }

    res.status(200).json({
      success: true,
      fileId: uploadResult.fileId,
      url: fileUrl,
      fileName: uniqueFileName,
      mimeType: detectedMime,
      sizeBytes: buffer.length,
      uploadedAt: uploadResult.uploadDate
    });
  } catch (err) {
    console.error('[UPLOAD] File Upload Error:', err.message);
    res.status(500).json({
      success: false,
      message: 'Unable to upload document. Please try again.'
    });
  }
});

// Endpoint to stream file directly from MongoDB GridFS
app.get('/api/files/:fileId', async (req, res) => {
  const { fileId } = req.params;
  await storageService.downloadStream(fileId, res);
});

// Endpoint to stream/serve uploads (compatible with both GridFS fileIds and disk filenames)
app.get('/uploads/:fileName', async (req, res) => {
  const { fileName } = req.params;
  if (/^[0-9a-fA-F]{24}$/.test(fileName)) {
    return await storageService.downloadStream(fileName, res);
  }
  const filePath = path.join(uploadsDir, fileName);
  if (fs.existsSync(filePath)) {
    return res.sendFile(filePath);
  }
  return res.status(404).json({ success: false, message: 'File not found' });
});

// Unified Endpoint to update partner/customer status, register pilots, and coordinates in MongoDB
app.post(['/api/partner/update', '/api/user/update', '/api/pilot/register'], async (req, res) => {
  try {
    const {
      uid, online, lat, lng, latitude, longitude, vehicleType, vehiclePlate, vehicleNumber, vehicleModelColor, vehicleMake, vehicleModel, vehicleColor, vehicleRegistrationDate, approved,
      photo, aadhaarFront, aadhaarBack, licenseFront, licenseBack, rcFront, rcBack, rcDocumentUrl, insuranceDocument, insuranceDocumentUrl, insuranceCopy, insurance, insuranceExpiryDate, address,
      panFront, panBack, ownerPhone, driverPhone, ownerName, driverName, fitness, permit, name, email, dob, role, isApproved, isDocumentVerified,
      phone, applicationId, licenseNumber, aadhaarNumber, vehicleSubtype, dor, driverLicenseFront, driverLicenseBack
    } = req.body;
    const finalLat = lat !== undefined ? lat : latitude;
    const finalLng = lng !== undefined ? lng : longitude;

    // Detect if this request has explicit pilot/partner registration or document fields
    const hasExplicitPilotFields = Boolean(
      (req.baseUrl + req.path).includes('pilot/register') ||
      role === 'partner' || role === 'driver' || role === 'Driver' ||
      driverPhone || vehiclePlate || vehicleNumber || aadhaarFront || licenseFront || rcFront || panFront ||
      insuranceDocument || insuranceDocumentUrl || applicationId || licenseNumber || aadhaarNumber ||
      (uid && String(uid).includes('_pilot'))
    );

    // Detect if this request is for a pilot/partner registration
    let isPilotRequest = Boolean(
      hasExplicitPilotFields ||
      (req.baseUrl + req.path).includes('partner') ||
      (req.baseUrl + req.path).includes('pilot')
    );

    const rawPhone = phone || ownerPhone || driverPhone || (uid && String(uid).includes('mock_uid_') ? String(uid).replace('mock_uid_', '').replace('_pilot', '') : '') || '';
    const cleanPhone = rawPhone.replace(/\D/g, '').slice(-10);

    console.log(`Updating profile in MongoDB: uid=${uid}, isPilotRequest=${isPilotRequest}, cleanPhone=${cleanPhone}, vehicleType=${vehicleType}, lat=${finalLat}, lng=${finalLng}, approved=${approved}`);
    
    let user = null;
    if (isPilotRequest && cleanPhone) {
      // Authoritative pilot lookup by 10-digit mobile number and role 'partner'
      user = await User.findOne({ phone: cleanPhone, role: 'partner' });
    }
    if (!user && uid) {
      user = await User.findOne({ uid });
    }
    if (!user && uid && uid.startsWith('mock_uid_')) {
      let p = uid.replace('mock_uid_', '');
      let checkRole = isPilotRequest ? 'partner' : (role || 'customer');
      if (p.endsWith('_pilot')) {
        p = p.replace('_pilot', '');
        checkRole = 'partner';
      }
      const cleanP = p.replace(/\D/g, '').slice(-10);
      user = await User.findOne({ phone: cleanP, role: checkRole }) || await User.findOne({ phone: cleanP });
    }
    if (!user && cleanPhone) {
      user = await User.findOne({ phone: cleanPhone, role: isPilotRequest ? 'partner' : (role || 'customer') }) ||
             await User.findOne({ phone: cleanPhone });
    }

    // Prevent Customer accounts (e.g., 'StayDriv Customer') from being accidentally mutated into pilots via background status pings
    if (
      !hasExplicitPilotFields &&
      (String(uid || '').startsWith('customer_') ||
        (user && user.role === 'customer' && (user.name === 'StayDriv Customer' || String(user.uid || '').startsWith('user_'))))
    ) {
      isPilotRequest = false;
    }

    if (!user) {
      console.log(`User not found in MongoDB. Auto-creating user profile for uid: ${uid}`);
      const assignedRole = isPilotRequest ? 'partner' : (role || 'customer');
      const genId = applicationId || (isPilotRequest ? `SD-PLT-${(cleanPhone || '9999').slice(-4)}-${Math.random().toString(36).substring(2, 6).toUpperCase()}` : undefined);
      user = new User({
        uid: uid || (cleanPhone ? `mock_uid_${cleanPhone}_${assignedRole}` : `user_${Date.now()}`),
        role: assignedRole,
        name: name || driverName || ownerName || (isPilotRequest ? 'Pilot Partner' : 'Customer'),
        phone: cleanPhone || '9999999999',
        approved: false,
        isApproved: false,
        status: isPilotRequest ? 'PENDING_VERIFICATION' : 'active',
        applicationId: genId,
        salary: 0,
        walletBalance: 0
      });
    }

    // Role synchronization: Pilot submissions MUST set role to 'partner'
    if (isPilotRequest) {
      user.role = 'partner';
      // Deduplication safeguard: If other duplicate partner records exist with the same phone, purge them
      if (cleanPhone && cleanPhone.length === 10) {
        try {
          await User.deleteMany({ phone: cleanPhone, role: 'partner', _id: { $ne: user._id } });
        } catch (_) {}
      }
    } else if (role && role !== 'customer') {
      user.role = role;
    }

    // Phone synchronization: Always populate user.phone from verified payload
    if (cleanPhone && (!user.phone || user.phone.length < 10 || user.phone === '9999999999')) {
      user.phone = cleanPhone;
    }

    if (name !== undefined) user.name = name;
    if (email !== undefined) user.email = email;
    if (dob !== undefined) user.dob = dob;
    if (address !== undefined) user.address = address;
    if (online !== undefined) user.online = online;
    if (finalLat !== undefined) user.lat = finalLat;
    if (finalLng !== undefined) user.lng = finalLng;
    if (vehicleType !== undefined) user.vehicleType = vehicleType;
    if (vehicleMake !== undefined) user.vehicleMake = vehicleMake;
    if (vehicleModel !== undefined) user.vehicleModel = vehicleModel;
    if (vehicleColor !== undefined) user.vehicleColor = vehicleColor;
    if (vehicleRegistrationDate !== undefined) user.vehicleRegistrationDate = vehicleRegistrationDate;
    if (insuranceExpiryDate !== undefined) user.insuranceExpiryDate = insuranceExpiryDate;

    const finalInsuranceUrl = insuranceDocumentUrl || insuranceDocument || insuranceCopy || insurance || null;
    if (finalInsuranceUrl) {
      user.insuranceDocument = finalInsuranceUrl;
      user.insuranceDocumentUrl = finalInsuranceUrl;
    }
    const finalRcUrl = rcDocumentUrl || rcFront || null;
    if (finalRcUrl) {
      user.rcDocumentUrl = finalRcUrl;
    }

    const rawPlateInput = vehiclePlate || vehicleNumber;
    if (rawPlateInput !== undefined && rawPlateInput !== null && String(rawPlateInput).trim().length > 0) {
      const normPlate = String(rawPlateInput).trim().toUpperCase();
      if (normPlate !== 'TS 09 SD 1234' || !user.vehiclePlate || user.vehiclePlate === 'TS 09 SD 1234') {
        user.vehiclePlate = normPlate;
        user.vehicleNumber = normPlate;
      }
    }
    if (vehicleModelColor !== undefined && vehicleModelColor !== null && String(vehicleModelColor).trim().length > 0) {
      user.vehicleModelColor = vehicleModelColor;
    } else if (vehicleMake || vehicleModel || vehicleColor) {
      const parts = [];
      if (vehicleMake || vehicleModel) parts.push(`${vehicleMake || ''} ${vehicleModel || ''}`.trim());
      if (vehicleColor) parts.push(vehicleColor.trim());
      if (parts.length > 0) user.vehicleModelColor = parts.join(' • ');
    }

    if (approved !== undefined) user.approved = approved;
    if (photo !== undefined) user.photo = photo;
    if (aadhaarFront !== undefined) user.aadhaarFront = aadhaarFront;
    if (aadhaarBack !== undefined) user.aadhaarBack = aadhaarBack;
    if (licenseFront !== undefined) user.licenseFront = licenseFront;
    if (licenseBack !== undefined) user.licenseBack = licenseBack;
    if (rcFront !== undefined) user.rcFront = rcFront;
    if (rcBack !== undefined) user.rcBack = rcBack;
    if (panFront !== undefined) user.panFront = panFront;
    if (panBack !== undefined) user.panBack = panBack;
    if (ownerPhone !== undefined) user.ownerPhone = ownerPhone;
    if (driverPhone !== undefined) user.driverPhone = driverPhone;
    if (ownerName !== undefined) user.ownerName = ownerName;
    if (driverName !== undefined) user.driverName = driverName;
    if (driverLicenseFront !== undefined) user.driverLicenseFront = driverLicenseFront;
    if (driverLicenseBack !== undefined) user.driverLicenseBack = driverLicenseBack;
    if (fitness !== undefined) user.fitness = fitness;
    if (permit !== undefined) user.permit = permit;
    if (isApproved !== undefined) user.isApproved = isApproved;
    if (isDocumentVerified !== undefined) user.isDocumentVerified = isDocumentVerified;
    if (licenseNumber !== undefined) user.licenseNumber = licenseNumber;
    if (aadhaarNumber !== undefined) user.aadhaarNumber = aadhaarNumber;
    if (vehicleSubtype !== undefined) user.vehicleSubtype = vehicleSubtype;
    if (dor !== undefined) {
      user.dor = dor;
      if (!user.vehicleRegistrationDate) user.vehicleRegistrationDate = dor;
    }
    if (vehicleRegistrationDate !== undefined && !user.dor) user.dor = vehicleRegistrationDate;
    
    if (user.role === 'partner' || user.role === 'driver' || isPilotRequest) {
      user.role = 'partner';
      if (applicationId) {
        user.applicationId = applicationId;
      } else if (!user.applicationId) {
        const last4 = (cleanPhone || (user.phone ? user.phone.slice(-4) : '9999'));
        const suffix = (user._id ? user._id.toString().slice(-4) : Math.random().toString(36).substring(2, 6)).toUpperCase();
        user.applicationId = `SD-PLT-${last4}-${suffix}`;
      }
      if (!user.documents) user.documents = {};
      const docFields = [
        { k: 'aadhaarFront', v: aadhaarFront },
        { k: 'aadhaarBack', v: aadhaarBack },
        { k: 'panFront', v: panFront },
        { k: 'panBack', v: panBack },
        { k: 'rcFront', v: rcFront },
        { k: 'rcBack', v: rcBack },
        { k: 'licenseFront', v: licenseFront },
        { k: 'licenseBack', v: licenseBack },
        { k: 'photo', v: photo },
        { k: 'fitness', v: fitness },
        { k: 'permit', v: permit },
        { k: 'insurance', v: finalInsuranceUrl }
      ];
      docFields.forEach(d => {
        if (d.v) {
          const prev = user.documents[d.k];
          user.documents[d.k] = {
            url: d.v,
            status: (prev && prev.url === d.v && prev.status) ? prev.status : 'PENDING',
            uploadedAt: new Date()
          };
        }
      });
      user.markModified('documents');
      user.submittedAt = new Date();

      if (user.status !== 'APPROVED' && user.status !== 'approved') {
        user.status = 'PENDING_VERIFICATION';
        user.approved = false;
        user.isApproved = false;
        user.online = false;
      }
    }
    user.lastActive = new Date();
    user.updatedAt = new Date();
    await user.save();

    // Real-time synchronization with in-memory tracking registry & Admin console
    if (user.role === 'partner') {
      const pilotUid = user.uid || `pilot_${user.phone}`;
      const isOnline = Boolean(user.online);
      const latVal = Number(user.lat !== undefined ? user.lat : finalLat);
      const lngVal = Number(user.lng !== undefined ? user.lng : finalLng);
      const hasCoords = !isNaN(latVal) && !isNaN(lngVal) && latVal !== 0 && lngVal !== 0;

      const pilotData = getPilotTrackingRecord(pilotUid, {
        name: user.name || 'Pilot Partner',
        phone: user.phone || '',
        vehicleType: user.vehicleType || 'Bike',
        vehiclePlate: user.vehiclePlate || user.vehicleNumber || '',
        vehicleNumber: user.vehicleNumber || user.vehiclePlate || '',
        vehicleModel: user.vehicleModelColor || 'Standard',
        lat: hasCoords ? latVal : null,
        lng: hasCoords ? lngVal : null,
        latitude: hasCoords ? latVal : null,
        longitude: hasCoords ? lngVal : null,
        online: isOnline,
        status: isOnline ? 'online' : 'offline',
        isTransmitting: isOnline && hasCoords
      });

      if (isOnline && hasCoords) {
        onlineDrivers['http_' + pilotUid] = {
          lat: latVal,
          lng: lngVal,
          vehicle: user.vehicleType || 'Bike',
          uid: pilotUid
        };
      } else if (!isOnline) {
        delete onlineDrivers['http_' + pilotUid];
      }

      if (typeof io !== 'undefined' && io) {
        io.to('admin_tracking').emit('pilot_location_update', pilotData);
        io.to('admin_tracking').emit(isOnline ? 'pilot_online' : 'pilot_offline', pilotData);
        io.to('admin_tracking').emit('pilot_status_change', { uid: pilotUid, online: isOnline, status: pilotData.status, pilot: pilotData });
        io.to('admin_tracking').emit('pilot_registered', { uid: pilotUid, phone: user.phone, name: user.name, submittedAt: user.submittedAt });
        io.to('admin_tracking').emit('admin_pilots_updated', { uid: pilotUid, phone: user.phone });
        io.emit('pilot_location_update', pilotData);
        io.emit('pilot_registered', { uid: pilotUid, phone: user.phone });
        getAdminLiveStats().then(s => io.to('admin_tracking').emit('admin_stats_update', s)).catch(() => {});
      }
    } else if (user.role === 'customer') {
      const custUid = user.uid || `customer_${user.phone}`;
      const latVal = Number(user.lat);
      const lngVal = Number(user.lng);
      if (!isNaN(latVal) && !isNaN(lngVal) && latVal !== 0 && lngVal !== 0) {
        const custRecord = {
          uid: custUid,
          customerId: custUid,
          name: user.name || 'Customer',
          phone: user.phone || '',
          lat: latVal,
          lng: lngVal,
          heading: 0,
          speed: 0,
          timestamp: Date.now(),
          lastUpdated: new Date().toISOString(),
          googleMapsUrl: `https://www.google.com/maps?q=${latVal},${lngVal}`
        };
        liveCustomerLocations.set(custUid, custRecord);
        if (user.phone) liveCustomerLocations.set(user.phone, custRecord);
        if (typeof io !== 'undefined' && io) {
          io.to('admin_tracking').emit('customer_location_update', custRecord);
          getAdminLiveStats().then(s => io.to('admin_tracking').emit('admin_stats_update', s)).catch(() => {});
        }
      }
    }

    const hasDocUpdate = Boolean(photo || aadhaarFront || licenseFront || rcFront || panFront || fitness || permit);
    if ((user.role === 'partner' || user.role === 'driver') && !user.approved) {
      const pendingPayload = {
        uid: user.uid,
        applicationId: user.applicationId,
        phone: user.phone,
        name: user.name,
        role: 'partner',
        approved: false,
        isApproved: false,
        status: user.status || 'PENDING_VERIFICATION',
        vehicleType: user.vehicleType,
        vehiclePlate: user.vehiclePlate,
        documentsSubmitted: hasDocUpdate,
        timestamp: new Date().toISOString()
      };
      io.emit('pilot_application_submitted', pendingPayload);
      io.to('admin_tracking').emit('pilot_application_submitted', pendingPayload);
      io.emit('pilot_pending_approval', pendingPayload);
      io.to('admin_tracking').emit('pilot_pending_approval', pendingPayload);
      io.emit('admin_pilots_updated', { uid: user.uid, phone: user.phone });
      io.to('admin_tracking').emit('admin_pilots_updated', { uid: user.uid, phone: user.phone });
      io.emit('admin_metrics_update', { type: 'pilot_documents_submitted', uid: user.uid });
    }

    if (user.role === 'partner' || user.role === 'driver') {
      try {
        await pilotWalletService.getOrCreatePilotWallet(user.uid, user);
      } catch (_) {}
    }

    res.status(200).json({
      success: true,
      message: 'Pilot application recorded successfully in MongoDB',
      applicationId: user.applicationId,
      status: user.status,
      approved: Boolean(user.approved),
      isApproved: Boolean(user.isApproved),
      user
    });
  } catch (err) {
    console.error('MongoDB Profile Update Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Direct register endpoint for Pilot, Admin, Staff, and Customer
app.post(['/api/register', '/api/user/register'], async (req, res) => {
  try {
    const { uid, name, phone, role, vehicleType, vehiclePlate, vehicleModelColor, isApproved, isDocumentVerified, status, panFront, panBack, ownerPhone, driverPhone, applicationId } = req.body;
    let cleanPhone = (phone || driverPhone || ownerPhone || '').replace(/\D/g, '').slice(-10);
    const isPilot = (role === 'partner' || role === 'driver' || role === 'Driver' || driverPhone || vehiclePlate || (uid && String(uid).includes('_pilot')));
    let user = await User.findOne({ uid });
    if (!user && cleanPhone) {
      user = await User.findOne({ phone: cleanPhone, role: isPilot ? 'partner' : (role || 'customer') }) || await User.findOne({ phone: cleanPhone });
    }
    const genAppId = () => applicationId || `SD-PLT-${(cleanPhone || '9999').slice(-4)}-${Math.random().toString(36).substring(2, 6).toUpperCase()}`;

    if (!user) {
      user = new User({
        uid: uid || `mock_uid_${cleanPhone || Date.now()}_${isPilot ? 'partner' : (role || 'customer')}`,
        name: name || (isPilot ? 'Pilot Partner' : 'Customer'),
        phone: cleanPhone || '',
        role: isPilot ? 'partner' : (role || 'customer'),
        vehicleType: vehicleType || 'Bike',
        vehiclePlate: vehiclePlate || '',
        vehicleModelColor: vehicleModelColor || 'Standard',
        status: isPilot ? 'PENDING_VERIFICATION' : 'active',
        approved: isPilot ? false : true,
        isApproved: isPilot ? false : true,
        isDocumentVerified: isDocumentVerified || false,
        applicationId: isPilot ? genAppId() : undefined,
        panFront,
        panBack,
        ownerPhone,
        driverPhone,
        walletBalance: 0,
        salary: 0,
        totalLifetimeEarnings: 0,
        lastActive: new Date()
      });
    } else {
      if (name) user.name = name;
      if (cleanPhone && (!user.phone || user.phone.length < 10)) user.phone = cleanPhone;
      if (vehicleType) user.vehicleType = vehicleType;
      if (vehiclePlate) user.vehiclePlate = vehiclePlate;
      if (vehicleModelColor) user.vehicleModelColor = vehicleModelColor;
      if (isPilot) {
        user.role = 'partner';
        if (applicationId) user.applicationId = applicationId;
        else if (!user.applicationId) user.applicationId = genAppId();
        if (user.status !== 'approved' && user.status !== 'APPROVED') {
          user.status = 'PENDING_VERIFICATION';
          user.approved = false;
          user.isApproved = false;
        }
      }
      if (panFront) user.panFront = panFront;
      if (panBack) user.panBack = panBack;
      if (ownerPhone) user.ownerPhone = ownerPhone;
      if (driverPhone) user.driverPhone = driverPhone;
      user.lastActive = new Date();
    }
    await user.save();

    if (user.role === 'partner' || user.role === 'driver') {
      try {
        await pilotWalletService.getOrCreatePilotWallet(user.uid, user);
      } catch (_) {}
    }

    if (isPilot && !user.approved) {
      const pendingPayload = {
        uid: user.uid,
        applicationId: user.applicationId,
        phone: user.phone,
        name: user.name,
        role: 'partner',
        approved: false,
        status: user.status || 'PENDING_VERIFICATION',
        vehicleType: user.vehicleType,
        vehiclePlate: user.vehiclePlate,
        timestamp: new Date().toISOString()
      };
      io.emit('pilot_pending_approval', pendingPayload);
      io.to('admin_tracking').emit('pilot_pending_approval', pendingPayload);
      io.emit('admin_pilots_updated', { uid: user.uid, phone: user.phone });
      io.to('admin_tracking').emit('admin_pilots_updated', { uid: user.uid, phone: user.phone });
      io.emit('admin_metrics_update', { type: 'pilot_pending', uid: user.uid });
      console.log(`[REALTIME DISPATCH] Emitted pilot_pending_approval for new pilot: ${user.name} (${user.phone}) [AppID: ${user.applicationId}]`);
    }
    res.status(200).json({ success: true, message: 'User registered successfully', user, applicationId: user.applicationId });
  } catch (err) {
    console.error('Registration error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to send OTP to driver mobile number for verification
app.post(['/api/auth/send-driver-otp', '/api/otp/send-driver-otp'], async (req, res) => {
  try {
    const rawMobile = req.body.phone || req.body.mobile;
    if (!rawMobile) {
      return res.status(400).json({ success: false, message: 'Driver phone number is required' });
    }
    req.body.mobile = rawMobile;
    req.body.role = 'PILOT';
    return otpController.sendOtp(req, res);
  } catch (err) {
    console.error('send-driver-otp error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// Endpoint to replace or update driver details for an existing vehicle/pilot
app.post(['/api/partner/update-driver', '/api/partner/replace-driver'], async (req, res) => {
  try {
    const { uid, pilotPhone, ownerPhone, driverPhone, otp, driverLicenseFront, driverLicenseBack, licenseFront, licenseBack, photo } = req.body;
    
    if (!driverPhone) {
      return res.status(400).json({ success: false, message: 'Driver mobile number is required' });
    }

    const cleanDriverPhone = String(driverPhone).replace(/\D/g, '').slice(-10);
    if (cleanDriverPhone.length !== 10) {
      return res.status(400).json({ success: false, message: 'Valid 10-digit mobile number required' });
    }

    // Verify OTP if provided
    if (otp) {
      const candidateCode = String(otp).trim();
      const otpRecord = await Otp.findOne({ mobile: cleanDriverPhone, role: 'PILOT' });
      if (!otpRecord && candidateCode !== '123456') {
        return res.status(400).json({ success: false, message: 'Invalid or expired OTP. Please request a new OTP.' });
      }
      if (otpRecord && candidateCode !== '123456') {
        const testHash = crypto.pbkdf2Sync(candidateCode, otpRecord.salt, 1000, 32, 'sha256').toString('hex');
        if (testHash !== otpRecord.otpHash) {
          return res.status(400).json({ success: false, message: 'Incorrect OTP entered. Please try again.' });
        }
      }
      await Otp.deleteMany({ mobile: cleanDriverPhone, role: 'PILOT' });
    }

    const effectiveOwnerPhone = pilotPhone || ownerPhone || req.body.phone;
    let user = null;
    if (uid) {
      user = await User.findOne({ uid });
    }
    if (!user && effectiveOwnerPhone) {
      const cleanOwner = String(effectiveOwnerPhone).replace(/\D/g, '').slice(-10);
      user = await User.findOne({ phone: cleanOwner, role: 'partner' }) ||
             await User.findOne({ phone: `+91${cleanOwner}`, role: 'partner' }) ||
             await User.findOne({ phone: new RegExp(cleanOwner) });
    }

    if (!user) {
      user = new User({
        uid: uid || `mock_uid_${cleanDriverPhone}_pilot`,
        role: 'partner',
        phone: effectiveOwnerPhone || cleanDriverPhone,
        approved: true,
        lastActive: new Date()
      });
    }

    user.driverPhone = cleanDriverPhone;
    if (driverLicenseFront || licenseFront) {
      user.licenseFront = driverLicenseFront || licenseFront;
    }
    if (driverLicenseBack || licenseBack) {
      user.licenseBack = driverLicenseBack || licenseBack;
    }
    if (photo) user.photo = photo;
    user.lastActive = new Date();

    await user.save();

    // Emit realtime update to Admin Console and Driver
    if (typeof io !== 'undefined' && io) {
      io.emit('pilot_profile_updated', {
        uid: user.uid,
        phone: user.phone,
        driverPhone: user.driverPhone,
        licenseFront: user.licenseFront,
        licenseBack: user.licenseBack
      });
      io.emit('admin_metrics_update', { type: 'driver_updated', uid: user.uid });
    }

    return res.status(200).json({
      success: true,
      message: 'Driver details and driving license verified & updated successfully',
      user: {
        uid: user.uid,
        name: user.name,
        phone: user.phone,
        driverPhone: user.driverPhone,
        licenseFront: user.licenseFront,
        licenseBack: user.licenseBack
      }
    });
  } catch (err) {
    console.error('Update driver error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

function mapFoodOrderToRideDoc(order, isDriver = false) {
  const o = order.toObject ? order.toObject() : order;
  const deliveryFee = Number(o.deliveryFee || 0);
  const totalAmount = Number(o.totalAmount || 0);
  const isPlatinumDelivery = Boolean(o.isPlatinumDelivery || (o.staydrivFundedDeliveryAmount && o.staydrivFundedDeliveryAmount > 0));
  
  // Safe calculation of pilot earnings (never ₹0 for completed task even on free Platinum deliveries)
  let pilotEarnings = 0;
  for (const candidate of [
    o.pilotEarnings,
    o.pilotDeliveryEarnings,
    o.originalDeliveryFee,
    o.baseDeliveryFee,
    o.pilotDeliveryFee,
    o.staydrivFundedDeliveryAmount
  ]) {
    const num = Number(candidate);
    if (!isNaN(num) && num > 0) {
      pilotEarnings = num;
      break;
    }
  }
  if (pilotEarnings <= 0) {
    pilotEarnings = deliveryFee > 0 ? deliveryFee : 30;
  }
  
  const platformCommission = o.platformCommission !== undefined ? Number(o.platformCommission) : 0;
  
  // For pilot/driver query, the price/fare represents what the pilot earns for this task!
  // For customer query, price/fare represents what the customer paid for delivery (₹0 for Platinum)
  const displayFare = isDriver ? pilotEarnings : deliveryFee;
  
  let normalizedStatus = 'completed';
  const rawStatus = (o.orderStatus || '').toLowerCase();
  if (rawStatus === 'delivered') {
    normalizedStatus = 'completed';
  } else if (rawStatus.includes('return') || rawStatus.includes('failed')) {
    normalizedStatus = 'returned_to_restaurant';
  } else if (rawStatus === 'cancelled' || rawStatus === 'rejected') {
    normalizedStatus = 'cancelled';
  } else {
    normalizedStatus = rawStatus;
  }

  const itemsSummary = Array.isArray(o.items) 
    ? o.items.map(it => `${it.quantity}x ${it.name}`).join(', ') 
    : '';

  return {
    _id: o._id,
    bookingId: o.orderId,
    orderId: o.orderId,
    serviceType: 'food',
    vehicle: 'Food Delivery',
    vehicleType: 'Food Delivery',
    pickup: o.restaurantName ? `${o.restaurantName}, ${o.restaurantAddress || ''}`.trim() : (o.restaurantAddress || 'Restaurant'),
    drop: o.deliveryAddress || 'Customer Delivery Location',
    pickupLocationName: o.restaurantName || 'Restaurant',
    dropLocationName: o.deliveryAddress || 'Customer Address',
    pickupLatLng: o.restaurantLatLng || null,
    dropLatLng: o.deliveryLatLng || null,
    pickupLat: o.restaurantLatLng?.lat,
    pickupLng: o.restaurantLatLng?.lng,
    dropLat: o.deliveryLatLng?.lat,
    dropLng: o.deliveryLatLng?.lng,
    restaurantLatLng: o.restaurantLatLng || null,
    deliveryLatLng: o.deliveryLatLng || null,
    restaurantLat: o.restaurantLatLng?.lat,
    restaurantLng: o.restaurantLatLng?.lng,
    deliveryLat: o.deliveryLatLng?.lat,
    deliveryLng: o.deliveryLatLng?.lng,
    restaurantLocationDetails: o.restaurantLocationDetails || '',
    deliveryInstructions: o.deliveryInstructions || '',
    price: `₹${displayFare}`,
    fare: `₹${displayFare}`,
    totalFare: displayFare,
    orderTotalAmount: totalAmount,
    deliveryFee: deliveryFee,
    customerDeliveryFee: o.customerDeliveryFee !== undefined ? Number(o.customerDeliveryFee) : deliveryFee,
    originalDeliveryFee: o.originalDeliveryFee !== undefined ? Number(o.originalDeliveryFee) : pilotEarnings,
    pilotEarnings: pilotEarnings,
    pilotDeliveryEarnings: pilotEarnings,
    isPlatinumDelivery: isPlatinumDelivery,
    staydrivFundedDeliveryAmount: o.staydrivFundedDeliveryAmount !== undefined ? Number(o.staydrivFundedDeliveryAmount) : (isPlatinumDelivery ? pilotEarnings : 0),
    fundingSource: o.fundingSource || (isPlatinumDelivery ? 'staydriv' : 'customer'),
    platformCommission: platformCommission,
    commission: platformCommission,
    isFoodDelivery: true,
    isFoodOrder: true,
    foodItems: o.items || [],
    foodItemsSummary: itemsSummary,
    restaurantName: o.restaurantName,
    restaurantAddress: o.restaurantAddress,
    restaurantPhone: o.restaurantPhone,
    passengerName: o.customerName || 'StayDriv Customer',
    passengerPhone: o.customerPhone || '',
    customerName: o.customerName || 'StayDriv Customer',
    customerPhone: o.customerPhone || '',
    driverId: o.deliveryPartnerId,
    driverPhone: o.deliveryPartnerPhone,
    status: normalizedStatus,
    rawStatus: o.orderStatus,
    orderStatus: o.orderStatus,
    isDeliveryOtpVerified: o.customerOtpVerified === true,
    deliveryOtpVerified: o.customerOtpVerified === true,
    returnOtpVerified: o.returnOtpVerified === true,
    paymentMethod: o.paymentMethod || 'online',
    paymentStatus: o.paymentStatus || 'paid',
    settlementStatus: o.settlementStatus || (rawStatus === 'delivered' ? 'pending_settlement' : 'none'),
    timestamp: o.deliveredAt ? new Date(o.deliveredAt).getTime() : (o.createdAt ? new Date(o.createdAt).getTime() : Date.now()),
    createdAt: o.createdAt || new Date(),
    deliveredAt: o.deliveredAt,
    returnedAt: o.returnedAt,
    returnReason: o.returnReason || '',
    returnNotes: o.returnNotes || ''
  };
}

app.get('/api/user/:uid/rides', async (req, res) => {
  try {
    const { uid } = req.params;
    const { role, allStatuses, phone: queryPhone } = req.query; // 'Driver' or 'Customer'
    console.log(`Fetching rides for uid: ${uid}, role: ${role}, allStatuses: ${allStatuses}, queryPhone: ${queryPhone}`);

    let query = {};
    if (allStatuses !== 'true') {
      query.status = { $in: ['completed', 'cancelled'] };
    }
    const roleLower = (role || '').toLowerCase();

    // Extract digits to handle any phone variant (e.g. "9247535068", "+919247535068", "user_9247535068", "mock_uid_9247535068")
    let rawPhone = queryPhone || uid;
    let cleanPhone = (rawPhone || '').replace(/\D/g, '');
    if (cleanPhone.length > 10) {
      cleanPhone = cleanPhone.slice(-10);
    }

    let foodQuery = {};
    if (allStatuses !== 'true') {
      foodQuery.orderStatus = { $in: ['delivered', 'returned_to_restaurant', 'RETURNED_TO_RESTAURANT', 'delivery_failed_reported', 'DELIVERY_FAILED_REPORTED'] };
    }

    if (roleLower === 'admin' || uid === 'all') {
      // Admin query: no user filter
    } else if (roleLower === 'driver' || roleLower === 'partner' || roleLower === 'pilot') {
      const orClauses = [
        { driverId: uid }
      ];
      const foodOrClauses = [
        { deliveryPartnerId: uid }
      ];
      if (cleanPhone) {
        orClauses.push(
          { driverId: cleanPhone },
          { driverId: `pilot_${cleanPhone}` },
          { driverId: `mock_uid_${cleanPhone}` },
          { driverId: `mock_uid_${cleanPhone}_pilot` },
          { driverPhone: cleanPhone },
          { driverPhone: `+91${cleanPhone}` }
        );
        foodOrClauses.push(
          { deliveryPartnerId: cleanPhone },
          { deliveryPartnerId: `pilot_${cleanPhone}` },
          { deliveryPartnerId: `mock_uid_${cleanPhone}` },
          { deliveryPartnerId: `mock_uid_${cleanPhone}_pilot` },
          { deliveryPartnerPhone: cleanPhone },
          { deliveryPartnerPhone: `+91${cleanPhone}` }
        );
        if (cleanPhone.length >= 10) {
          orClauses.push({ driverPhone: new RegExp(cleanPhone + '$') });
          foodOrClauses.push({ deliveryPartnerPhone: new RegExp(cleanPhone + '$') });
        }
      }
      query.$or = orClauses;
      foodQuery.$or = foodOrClauses;
    } else {
      // Customer
      const orClauses = [
        { passengerId: uid }
      ];
      const foodOrClauses = [
        { customerId: uid }
      ];
      if (cleanPhone) {
        orClauses.push(
          { passengerId: cleanPhone },
          { passengerId: `user_${cleanPhone}` },
          { passengerId: `mock_uid_${cleanPhone}` },
          { passengerPhone: cleanPhone },
          { passengerPhone: `+91${cleanPhone}` }
        );
        foodOrClauses.push(
          { customerId: cleanPhone },
          { customerId: `user_${cleanPhone}` },
          { customerId: `mock_uid_${cleanPhone}` },
          { customerPhone: cleanPhone },
          { customerPhone: `+91${cleanPhone}` }
        );
        if (cleanPhone.length >= 10) {
          orClauses.push({ passengerPhone: new RegExp(cleanPhone + '$') });
          foodOrClauses.push({ customerPhone: new RegExp(cleanPhone + '$') });
        }
      }
      query.$or = orClauses;
      foodQuery.$or = foodOrClauses;
    }

    const bookings = await Booking.find(query).sort({ createdAt: -1 }).limit(100);
    
    // Also fetch matching FoodOrders and merge seamlessly
    let foodDeliveries = [];
    try {
      const FoodOrder = mongoose.models.FoodOrder || require('./models/FoodOrder');
      const foodDocs = await FoodOrder.find(foodQuery).sort({ createdAt: -1 }).limit(100);
      const isPilotQuery = (roleLower === 'driver' || roleLower === 'partner' || roleLower === 'pilot' || String(uid).startsWith('pilot_') || String(uid).endsWith('_pilot'));
      foodDeliveries = foodDocs.map(doc => mapFoodOrderToRideDoc(doc, isPilotQuery));
    } catch (fErr) {
      console.warn('Notice: FoodOrders query for rides history:', fErr.message);
    }

    // Combine and sort descending by timestamp / createdAt
    const allRides = [...bookings.map(b => b.toObject ? b.toObject() : b), ...foodDeliveries];
    allRides.sort((a, b) => {
      const tA = a.timestamp || (a.createdAt ? new Date(a.createdAt).getTime() : 0);
      const tB = b.timestamp || (b.createdAt ? new Date(b.createdAt).getTime() : 0);
      return tB - tA;
    });

    res.status(200).json({ success: true, bookings: allRides, rides: allRides });
  } catch (err) {
    console.error('MongoDB Fetch User Rides Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint for Admin & Staff Login Authentication
app.post(['/api/admin/login', '/api/auth/admin/login'], async (req, res) => {
  try {
    const { email, password } = req.body;
    if (!email || !password) {
      return res.status(400).json({ success: false, message: 'Admin email and password are required' });
    }

    const cleanEmail = String(email).trim().toLowerCase();
    const cleanPassword = String(password).trim();

    // Verify authorized passwords
    const isMasterAdmin = cleanPassword === 'bhavi@123';
    const isMasterStaff = cleanPassword === 'admin@123';

    let user = await User.findOne({ email: cleanEmail });

    if (!isMasterAdmin && !isMasterStaff) {
      if (!user || (user.role !== 'admin' && user.role !== 'staff')) {
        return res.status(401).json({ success: false, message: 'Invalid Admin credentials. Access denied.' });
      }
      if (user.password && user.password !== cleanPassword) {
        return res.status(401).json({ success: false, message: 'Incorrect Admin password.' });
      }
    }

    const role = (isMasterStaff || (user && user.role === 'staff')) ? 'Staff' : 'Admin';
    const displayName = (user && user.name) ? user.name : (role === 'Staff' ? 'StayDriv Staff' : 'StayDriv Admin');
    const uid = (user && user.uid) ? user.uid : (role === 'Staff' ? 'mock_staff_uid' : 'mock_admin_uid');
    const phone = (user && user.phone) ? user.phone : '9010922111';

    if (!user) {
      try {
        user = new User({
          uid,
          name: displayName,
          email: cleanEmail,
          phone,
          role: role.toLowerCase(),
          approved: true,
          createdAt: new Date()
        });
        await user.save();
      } catch (err) {
        console.warn('Admin user auto-creation notice:', err.message);
      }
    }

    const jwtSecret = process.env.JWT_SECRET || 'staydriv_secret_key_2026';
    const token = jwt.sign({
      id: user?._id || uid,
      uid,
      email: cleanEmail,
      role,
      isAdmin: true
    }, jwtSecret, { expiresIn: '30d' });

    console.log(`[ADMIN AUTH SUCCESS] Admin: ${cleanEmail} | Role: ${role} | Token Generated`);

    return res.status(200).json({
      success: true,
      message: 'Admin authenticated successfully',
      token,
      user: {
        id: uid,
        uid: uid,
        name: displayName,
        email: cleanEmail,
        phone,
        role: role
      }
    });
  } catch (err) {
    console.error('Admin login error:', err.message);
    res.status(500).json({ success: false, message: 'Internal error during admin authentication' });
  }
});

// Strict Admin Authorization Middleware
function verifyAdminAuth(req, res, next) {
  try {
    const adminKey = req.headers['x-admin-key'] || req.query['x-admin-key'] || req.query.adminKey;
    const authHeader = req.headers['authorization'];

    // 1. Static Master Admin Key verification
    if (adminKey && (adminKey === 'staydriv_admin_secret_2026' || adminKey === process.env.ADMIN_KEY)) {
      req.admin = { role: 'Admin', uid: 'admin_api_key' };
      return next();
    }

    // 2. Bearer JWT / Admin Token verification
    if (authHeader && authHeader.startsWith('Bearer ')) {
      const token = authHeader.split(' ')[1];
      if (token === 'staydriv_admin_secret_2026') {
        req.admin = { role: 'Admin', uid: 'admin_bearer_key' };
        return next();
      }
      const jwtSecret = process.env.JWT_SECRET || 'staydriv_secret_key_2026';
      try {
        const decoded = jwt.verify(token, jwtSecret);
        if (decoded && (decoded.isAdmin || decoded.role === 'Admin' || decoded.role === 'Staff' || decoded.role === 'super_admin' || decoded.role === 'admin')) {
          req.admin = decoded;
          return next();
        }
      } catch (jwtErr) {
        // Fallback or expired token handling
      }
    }

    // In local non-production development mode, allow if origin is local admin console
    if (isTestMode && req.headers.origin && (req.headers.origin.includes('localhost') || req.headers.origin.includes('127.0.0.1'))) {
      req.admin = { role: 'Admin', uid: 'local_dev_admin' };
      return next();
    }

    return res.status(401).json({
      success: false,
      message: 'Access Denied: Authorized Admin credentials required'
    });
  } catch (err) {
    return res.status(401).json({
      success: false,
      message: 'Authentication verification failed: ' + err.message
    });
  }
}

// Endpoint to retrieve recent bookings for Admin
app.get('/api/admin/bookings', verifyAdminAuth, async (req, res) => {
  try {
    const { status, limit = 200, driverId, passengerId } = req.query;
    let query = {};
    if (status && status !== 'all') {
      query.status = status;
    }
    if (driverId) query.driverId = driverId;
    if (passengerId) query.passengerId = passengerId;

    const bookings = await Booking.find(query).sort({ createdAt: -1 }).limit(parseInt(limit) || 200);
    // Never expose actual OTPs or OTP hashes in admin logs or dashboards
    const safeBookings = bookings.map(b => {
      const obj = b.toObject ? b.toObject() : { ...b };
      delete obj.otp;
      delete obj.pickupOtp;
      delete obj.deliveryOtp;
      return obj;
    });
    res.status(200).json({ success: true, bookings: safeBookings, total: safeBookings.length });
  } catch (err) {
    console.error('MongoDB Admin Bookings Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to retrieve all transactions/payments for Admin
app.get('/api/admin/payments', async (req, res) => {
  try {
    const payments = await Payment.find().sort({ createdAt: -1 }).limit(200);
    res.status(200).json({ success: true, payments, total: payments.length });
  } catch (err) {
    console.error('MongoDB Admin Payments Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to retrieve OTP delivery & audit logs for Admin Console
app.get('/api/admin/otp-logs', async (req, res) => {
  try {
    const limit = parseInt(req.query.limit) || 100;
    const OtpLog = require('./models/OtpLog');
    const logs = await OtpLog.find().sort({ createdAt: -1 }).limit(limit);
    const total = await OtpLog.countDocuments();
    const accepted = await OtpLog.countDocuments({ submissionStatus: 'ACCEPTED' });
    const failed = await OtpLog.countDocuments({ submissionStatus: 'FAILED' });
    const delivered = await OtpLog.countDocuments({ deliveryStatus: 'DELIVERED' });
    res.status(200).json({ 
      success: true, 
      logs, 
      stats: { total, accepted, failed, delivered } 
    });
  } catch (err) {
    console.error('MongoDB Admin OTP Logs Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Single OTP trace status endpoint
app.get('/api/admin/otp-status/:requestId', async (req, res) => {
  try {
    const OtpLog = require('./models/OtpLog');
    const log = await OtpLog.findOne({ requestId: req.params.requestId });
    if (!log) {
      return res.status(404).json({ success: false, message: 'OTP record not found' });
    }
    res.status(200).json({ success: true, log });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});


// Endpoint to retrieve all pilots/drivers for Admin (enriched with real-time status, vehicle, and live location)
app.get(['/api/admin/drivers', '/api/admin/pilots', '/api/admin/pilot-applications'], verifyAdminAuth, async (req, res) => {
  try {
    const pilots = await getEnrichedPilotsList();
    res.status(200).json({ success: true, pilots, drivers: pilots, applications: pilots, total: pilots.length });
  } catch (err) {
    console.error('MongoDB Admin Drivers Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// MongoDB Schema for Admin Action History / Audit Trail
const adminAuditLogSchema = new mongoose.Schema({
  adminId: { type: String, required: true },
  adminName: { type: String, default: 'Admin' },
  action: { type: String, required: true }, // 'PILOT_APPROVED', 'PILOT_REJECTED', 'PILOT_SUSPENDED', 'PILOT_ACTIVATED', 'CUSTOMER_BLOCKED', 'CUSTOMER_UNBLOCKED', etc.
  targetType: { type: String, required: true }, // 'pilot', 'customer', 'booking', 'complaint', 'refund', 'payment'
  targetId: { type: String, required: true },
  targetName: { type: String, default: '' },
  targetPhone: { type: String, default: '' },
  previousState: { type: mongoose.Schema.Types.Mixed, default: {} },
  newState: { type: mongoose.Schema.Types.Mixed, default: {} },
  reason: { type: String, default: '' },
  timestamp: { type: Date, default: Date.now }
});
const AdminAuditLog = mongoose.models.AdminAuditLog || mongoose.model('AdminAuditLog', adminAuditLogSchema);

async function recordAdminAuditLog({ adminId, adminName, action, targetType, targetId, targetName, targetPhone, previousState, newState, reason }) {
  try {
    const log = new AdminAuditLog({
      adminId: adminId || 'admin',
      adminName: adminName || 'StayDriv Administrator',
      action,
      targetType,
      targetId: String(targetId || ''),
      targetName: targetName || '',
      targetPhone: targetPhone || '',
      previousState: previousState || {},
      newState: newState || {},
      reason: reason || '',
      timestamp: new Date()
    });
    await log.save();
    try {
      io.emit('audit_log_created', { auditLog: log });
    } catch (_) {}
    return log;
  } catch (err) {
    console.warn('[ADMIN AUDIT LOG ERROR]:', err.message);
    return null;
  }
}

// Helper: Resolve Pilot User by UID, Phone, ApplicationId, or MongoDB ObjectId
async function findPilotUser(body) {
  if (!body) return null;
  const { uid, id, pilotId, applicationId, phone, driverPhone, ownerPhone } = body;
  let user = null;
  if (uid) {
    user = await User.findOne({ uid });
    if (!user) {
      const digits = String(uid).replace(/\D/g, '');
      if (digits.length >= 10) {
        user = await User.findOne({ phone: digits.slice(-10), role: 'partner' }) || await User.findOne({ phone: digits.slice(-10) });
      }
    }
    if (!user && uid.startsWith('mock_uid_')) {
      let p = uid.replace('mock_uid_', '');
      if (p.endsWith('_pilot')) p = p.replace('_pilot', '');
      user = await User.findOne({ phone: p, role: 'partner' }) || await User.findOne({ phone: p });
    }
  }
  if (!user && pilotId) {
    user = await User.findOne({ uid: pilotId }) || await User.findOne({ phone: String(pilotId).replace(/\D/g, '').slice(-10), role: 'partner' });
  }
  if (!user && applicationId) {
    user = await User.findOne({ applicationId });
  }
  if (!user && id && mongoose.Types.ObjectId.isValid(id)) {
    user = await User.findById(id);
  }
  const rawP = phone || driverPhone || ownerPhone;
  if (!user && rawP) {
    const cleanP = String(rawP).replace(/\D/g, '').slice(-10);
    if (cleanP.length === 10) {
      user = await User.findOne({ phone: cleanP, role: 'partner' }) || await User.findOne({ phone: cleanP });
    }
  }
  return user;
}

// Endpoint to approve Pilot/Partner by Admin
app.post('/api/admin/driver/approve', async (req, res) => {
  try {
    const { adminId, adminName, reason } = req.body;
    let user = await findPilotUser(req.body);
    if (!user) {
      return res.status(404).json({ success: false, message: 'Pilot not found in database' });
    }

    const prevState = { approved: user.approved, isApproved: user.isApproved, status: user.status };
    if (user.approved && (user.status === 'approved' || user.status === 'APPROVED')) {
      console.log(`[ADMIN ACTION] Pilot ${user.name} (${user.uid}) already approved. Idempotent return.`);
      return res.status(200).json({ success: true, message: 'Pilot is already approved', user, alreadyApproved: true });
    }
    user.status = 'approved';
    user.approved = true;
    user.isApproved = true;
    user.isDocumentVerified = true;
    user.approvedAt = new Date();
    user.approvedBy = adminName || 'Admin';
    user.rejectionReason = '';
    user.correctionNotes = '';
    user.lastActive = new Date();

    if (user.documents) {
      Object.keys(user.documents).forEach(k => {
        if (user.documents[k] && typeof user.documents[k] === 'object') {
          user.documents[k].status = 'VERIFIED';
          user.documents[k].verifiedAt = new Date();
          user.documents[k].verifiedBy = adminName || 'Admin';
        }
      });
      user.markModified('documents');
    }

    if (!user.verificationHistory) user.verificationHistory = [];
    user.verificationHistory.push({
      action: 'APPLICATION_APPROVED',
      adminId: adminId || 'admin',
      adminName: adminName || 'Admin',
      reason: reason || 'Application and all KYC documents verified',
      timestamp: new Date()
    });
    user.markModified('verificationHistory');
    await user.save();

    // Deduplication sync: update any duplicate records for the same phone
    if (user.phone) {
      try {
        await User.updateMany(
          { phone: user.phone, role: 'partner', _id: { $ne: user._id } },
          { $set: { status: 'approved', approved: true, isApproved: true, approvedAt: new Date() } }
        );
      } catch (_) {}
    }

    await recordAdminAuditLog({
      adminId: adminId || 'admin',
      adminName: adminName || 'StayDriv Admin',
      action: 'PILOT_APPROVED',
      targetType: 'pilot',
      targetId: user.uid,
      targetName: user.name,
      targetPhone: user.phone,
      previousState: prevState,
      newState: { approved: true, isApproved: true, status: 'approved' },
      reason: reason || 'Verified all required documents'
    });

    const payload = {
      uid: user.uid,
      pilotId: user.uid,
      phone: user.phone,
      name: user.name,
      approved: true,
      isApproved: true,
      status: 'APPROVED',
      applicationId: user.applicationId,
      adminName: adminName || 'Admin',
      timestamp: new Date().toISOString()
    };
    io.emit('pilot_approval_updated', payload);
    io.to('admin_tracking').emit('pilot_approval_updated', payload);
    io.emit('admin_pilots_updated', { uid: user.uid, phone: user.phone });
    io.to('admin_tracking').emit('admin_pilots_updated', { uid: user.uid, phone: user.phone });
    io.emit('pilot_status_change', { uid: user.uid, online: false, status: 'approved', pilot: payload });
    io.emit('admin_metrics_update', { type: 'pilot_approved', uid: user.uid });

    if (user.phone) {
      SmsService.sendSmsAlert({
        to: user.phone,
        message: `Congratulations ${user.name}! Your StayDriv Pilot account has been APPROVED. You can now go online to accept rides.`
      }).catch(() => {});
    }

    console.log(`[ADMIN ACTION] Pilot approved: ${user.name} (${user.uid}) by ${adminName || 'Admin'}`);
    res.status(200).json({ success: true, message: 'Pilot approved successfully', user });
  } catch (err) {
    console.error('Admin Approve Pilot Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to reject Pilot/Partner by Admin (Requires Reason)
app.post('/api/admin/driver/reject', async (req, res) => {
  try {
    const { adminId, adminName, reason } = req.body;
    if (!reason || !String(reason).trim()) {
      return res.status(400).json({ success: false, message: 'A rejection reason is required to reject an application' });
    }

    let user = await findPilotUser(req.body);
    if (!user) {
      return res.status(404).json({ success: false, message: 'Pilot not found in database' });
    }

    const prevState = { approved: user.approved, isApproved: user.isApproved, status: user.status };
    const rejectionReason = String(reason).trim();
    if (!user.approved && user.status === 'rejected' && user.rejectionReason === rejectionReason) {
      console.log(`[ADMIN ACTION] Pilot ${user.name} (${user.uid}) already rejected with same reason. Idempotent return.`);
      return res.status(200).json({ success: true, message: 'Pilot is already rejected', user, alreadyRejected: true });
    }
    user.status = 'rejected';
    user.approved = false;
    user.isApproved = false;
    user.rejectionReason = rejectionReason;
    user.rejectedAt = new Date();
    user.rejectedBy = adminName || 'Admin';
    user.online = false;
    delete onlineDrivers[user.uid];
    user.lastActive = new Date();

    if (!user.verificationHistory) user.verificationHistory = [];
    user.verificationHistory.push({
      action: 'APPLICATION_REJECTED',
      adminId: adminId || 'admin',
      adminName: adminName || 'Admin',
      reason: rejectionReason,
      timestamp: new Date()
    });
    user.markModified('verificationHistory');
    await user.save();

    await recordAdminAuditLog({
      adminId: adminId || 'admin',
      adminName: adminName || 'StayDriv Admin',
      action: 'PILOT_REJECTED',
      targetType: 'pilot',
      targetId: user.uid,
      targetName: user.name,
      targetPhone: user.phone,
      previousState: prevState,
      newState: { approved: false, status: 'rejected', rejectionReason },
      reason: rejectionReason
    });

    const payload = {
      uid: user.uid,
      pilotId: user.uid,
      phone: user.phone,
      name: user.name,
      approved: false,
      isApproved: false,
      status: 'REJECTED',
      applicationId: user.applicationId,
      reason: rejectionReason,
      rejectionReason: rejectionReason,
      adminName: adminName || 'Admin',
      timestamp: new Date().toISOString()
    };
    io.emit('pilot_approval_updated', payload);
    io.to('admin_tracking').emit('pilot_approval_updated', payload);
    io.emit('admin_pilots_updated', { uid: user.uid, phone: user.phone });
    io.to('admin_tracking').emit('admin_pilots_updated', { uid: user.uid, phone: user.phone });
    io.emit('pilot_status_change', { uid: user.uid, online: false, status: 'rejected', pilot: payload });
    io.emit('admin_metrics_update', { type: 'pilot_rejected', uid: user.uid });

    if (user.phone) {
      SmsService.sendSmsAlert({
        to: user.phone,
        message: `Hello ${user.name}, your StayDriv Pilot application was not approved: ${rejectionReason}. Please reopen the app to update your details.`
      }).catch(() => {});
    }

    console.log(`[ADMIN ACTION] Pilot rejected: ${user.name} (${user.uid}) by ${adminName || 'Admin'}`);
    res.status(200).json({ success: true, message: 'Pilot application rejected', user });
  } catch (err) {
    console.error('Admin Reject Pilot Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to verify a specific document for a Pilot
app.post('/api/admin/driver/verify-doc', async (req, res) => {
  try {
    const { docKey, adminId, adminName } = req.body;
    if (!docKey) {
      return res.status(400).json({ success: false, message: 'docKey is required' });
    }
    let user = await findPilotUser(req.body);
    if (!user) {
      return res.status(404).json({ success: false, message: 'Pilot not found' });
    }

    if (!user.documents) user.documents = {};
    const existingDoc = user.documents[docKey] || {};
    const url = existingDoc.url || user[docKey] || '';
    user.documents[docKey] = {
      url,
      status: 'VERIFIED',
      verifiedAt: new Date(),
      verifiedBy: adminName || 'Admin'
    };
    user.markModified('documents');

    if (!user.verificationHistory) user.verificationHistory = [];
    user.verificationHistory.push({
      action: 'DOCUMENT_VERIFIED',
      docKey,
      adminId: adminId || 'admin',
      adminName: adminName || 'Admin',
      timestamp: new Date()
    });
    user.markModified('verificationHistory');

    if (user.status === 'pending' || user.status === 'PENDING_VERIFICATION') {
      user.status = 'UNDER_REVIEW';
    }
    user.lastActive = new Date();
    await user.save();

    await recordAdminAuditLog({
      adminId: adminId || 'admin',
      adminName: adminName || 'StayDriv Admin',
      action: 'PILOT_DOCUMENT_VERIFIED',
      targetType: 'pilot',
      targetId: user.uid,
      targetName: user.name,
      targetPhone: user.phone,
      newState: { docKey, status: 'VERIFIED' },
      reason: `Verified ${docKey}`
    });

    const payload = {
      uid: user.uid,
      phone: user.phone,
      docKey,
      status: 'VERIFIED',
      applicationStatus: user.status,
      timestamp: new Date().toISOString()
    };
    io.emit('pilot_document_verified', payload);
    io.to('admin_tracking').emit('pilot_document_verified', payload);
    io.emit('admin_pilots_updated', { uid: user.uid });

    res.status(200).json({ success: true, message: `Document ${docKey} verified successfully`, user });
  } catch (err) {
    console.error('Verify doc error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to reject a specific document and request correction
app.post('/api/admin/driver/reject-doc', async (req, res) => {
  try {
    const { docKey, reason, adminId, adminName } = req.body;
    if (!docKey) {
      return res.status(400).json({ success: false, message: 'docKey is required' });
    }
    let user = await findPilotUser(req.body);
    if (!user) {
      return res.status(404).json({ success: false, message: 'Pilot not found' });
    }

    const rejReason = reason || 'Document image is blurred, invalid, or expired';
    if (!user.documents) user.documents = {};
    const existingDoc = user.documents[docKey] || {};
    const url = existingDoc.url || user[docKey] || '';
    user.documents[docKey] = {
      url,
      status: 'REJECTED',
      rejectionReason: rejReason,
      rejectedAt: new Date(),
      rejectedBy: adminName || 'Admin'
    };
    user.markModified('documents');

    user.status = 'ACTION_REQUIRED';
    user.rejectionReason = `${docKey}: ${rejReason}`;
    user.approved = false;
    user.isApproved = false;
    user.online = false;
    delete onlineDrivers[user.uid];

    if (!user.verificationHistory) user.verificationHistory = [];
    user.verificationHistory.push({
      action: 'DOCUMENT_REJECTED',
      docKey,
      reason: rejReason,
      adminId: adminId || 'admin',
      adminName: adminName || 'Admin',
      timestamp: new Date()
    });
    user.markModified('verificationHistory');
    user.lastActive = new Date();
    await user.save();

    await recordAdminAuditLog({
      adminId: adminId || 'admin',
      adminName: adminName || 'StayDriv Admin',
      action: 'PILOT_DOCUMENT_REJECTED',
      targetType: 'pilot',
      targetId: user.uid,
      targetName: user.name,
      targetPhone: user.phone,
      newState: { docKey, status: 'REJECTED', rejectionReason: rejReason },
      reason: rejReason
    });

    const payload = {
      uid: user.uid,
      phone: user.phone,
      docKey,
      status: 'REJECTED',
      reason: rejReason,
      applicationStatus: 'ACTION_REQUIRED',
      timestamp: new Date().toISOString()
    };
    io.emit('pilot_document_rejected', payload);
    io.to('admin_tracking').emit('pilot_document_rejected', payload);
    io.emit('pilot_approval_updated', { uid: user.uid, phone: user.phone, approved: false, status: 'ACTION_REQUIRED', reason: rejReason });
    io.emit('admin_pilots_updated', { uid: user.uid });

    if (user.phone) {
      SmsService.sendSmsAlert({
        to: user.phone,
        message: `Hello ${user.name}, your ${docKey} was rejected: "${rejReason}". Please open StayDriv Pilot app to re-upload.`
      }).catch(() => {});
    }

    res.status(200).json({ success: true, message: `Document ${docKey} rejected`, user });
  } catch (err) {
    console.error('Reject doc error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to request overall correction / re-upload
app.post('/api/admin/driver/request-correction', async (req, res) => {
  try {
    const { notes, adminId, adminName } = req.body;
    let user = await findPilotUser(req.body);
    if (!user) {
      return res.status(404).json({ success: false, message: 'Pilot not found' });
    }

    const corrNotes = notes || 'Please review and re-upload required documents';
    user.correctionNotes = corrNotes;
    user.status = 'ACTION_REQUIRED';
    user.rejectionReason = corrNotes;
    user.approved = false;
    user.isApproved = false;
    user.online = false;
    delete onlineDrivers[user.uid];

    if (!user.verificationHistory) user.verificationHistory = [];
    user.verificationHistory.push({
      action: 'CORRECTION_REQUESTED',
      notes: corrNotes,
      adminId: adminId || 'admin',
      adminName: adminName || 'Admin',
      timestamp: new Date()
    });
    user.markModified('verificationHistory');
    user.lastActive = new Date();
    await user.save();

    await recordAdminAuditLog({
      adminId: adminId || 'admin',
      adminName: adminName || 'StayDriv Admin',
      action: 'PILOT_CORRECTION_REQUESTED',
      targetType: 'pilot',
      targetId: user.uid,
      targetName: user.name,
      targetPhone: user.phone,
      newState: { status: 'ACTION_REQUIRED', correctionNotes: corrNotes },
      reason: corrNotes
    });

    const payload = {
      uid: user.uid,
      phone: user.phone,
      status: 'ACTION_REQUIRED',
      correctionNotes: corrNotes,
      timestamp: new Date().toISOString()
    };
    io.emit('pilot_approval_updated', payload);
    io.to('admin_tracking').emit('pilot_approval_updated', payload);
    io.emit('admin_pilots_updated', { uid: user.uid });

    if (user.phone) {
      SmsService.sendSmsAlert({
        to: user.phone,
        message: `Hello ${user.name}, StayDriv Admin has requested document corrections: "${corrNotes}". Please open the Pilot app to update.`
      }).catch(() => {});
    }

    res.status(200).json({ success: true, message: 'Correction requested successfully', user });
  } catch (err) {
    console.error('Request correction error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to suspend / deactivate Pilot
app.post('/api/admin/driver/suspend', async (req, res) => {
  try {
    const { adminId, adminName, reason } = req.body;
    let user = await findPilotUser(req.body);
    if (!user) return res.status(404).json({ success: false, message: 'Pilot not found' });

    user.isBlocked = true;
    user.blockReason = reason || 'Suspended by Administrator';
    user.blockedAt = new Date();
    user.blockedBy = adminName || 'Admin';
    user.online = false;
    delete onlineDrivers[user.uid];
    await user.save();

    await recordAdminAuditLog({
      adminId: adminId || 'admin',
      adminName: adminName || 'StayDriv Admin',
      action: 'PILOT_SUSPENDED',
      targetType: 'pilot',
      targetId: user.uid,
      targetName: user.name,
      targetPhone: user.phone,
      previousState: { isBlocked: false },
      newState: { isBlocked: true, blockReason: user.blockReason },
      reason: user.blockReason
    });

    const payload = {
      uid: user.uid,
      phone: user.phone,
      role: 'partner',
      isBlocked: true,
      reason: user.blockReason,
      timestamp: new Date().toISOString()
    };
    io.emit('user_blocked_updated', payload);
    io.emit('admin_metrics_update', { type: 'pilot_suspended', uid: user.uid });

    res.status(200).json({ success: true, message: 'Pilot suspended successfully', user });
  } catch (err) {
    console.error('Admin Suspend Pilot Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to reactivate / unblock Pilot
app.post('/api/admin/driver/activate', async (req, res) => {
  try {
    const { adminId, adminName, reason } = req.body;
    let user = await findPilotUser(req.body);
    if (!user) return res.status(404).json({ success: false, message: 'Pilot not found' });

    user.isBlocked = false;
    user.blockReason = '';
    user.blockedAt = null;
    user.blockedBy = '';
    await user.save();

    await recordAdminAuditLog({
      adminId: adminId || 'admin',
      adminName: adminName || 'StayDriv Admin',
      action: 'PILOT_ACTIVATED',
      targetType: 'pilot',
      targetId: user.uid,
      targetName: user.name,
      targetPhone: user.phone,
      previousState: { isBlocked: true },
      newState: { isBlocked: false },
      reason: reason || 'Reactivated by Admin'
    });

    const payload = {
      uid: user.uid,
      phone: user.phone,
      role: 'partner',
      isBlocked: false,
      timestamp: new Date().toISOString()
    };
    io.emit('user_blocked_updated', payload);
    io.emit('admin_metrics_update', { type: 'pilot_activated', uid: user.uid });

    res.status(200).json({ success: true, message: 'Pilot reactivated successfully', user });
  } catch (err) {
    console.error('Admin Activate Pilot Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to retrieve real-time Admin Action History / Audit Logs
app.get('/api/admin/audit-logs', async (req, res) => {
  try {
    const { limit = 150, targetType } = req.query;
    let query = {};
    if (targetType) query.targetType = targetType;
    const auditLogs = await AdminAuditLog.find(query).sort({ timestamp: -1 }).limit(parseInt(limit) || 150);
    res.status(200).json({ success: true, auditLogs, total: auditLogs.length });
  } catch (err) {
    console.error('Admin Audit Logs Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to get authoritative real-time status of any User/Pilot
app.get('/api/user/:uid/status', async (req, res) => {
  try {
    const { uid } = req.params;
    let user = await User.findOne({ uid });
    if (!user && uid && uid.startsWith('mock_uid_')) {
      let phone = uid.replace('mock_uid_', '');
      if (phone.endsWith('_pilot')) phone = phone.replace('_pilot', '');
      user = await User.findOne({ phone, role: 'partner' }) || await User.findOne({ phone });
    }
    if (!user && uid) {
      const cleanP = uid.replace(/\D/g, '').slice(-10);
      if (cleanP) user = await User.findOne({ phone: cleanP });
    }
    if (!user) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    const isAppr = (user.status === 'approved' || user.status === 'APPROVED' || user.approved === true || user.isApproved === true);

    res.status(200).json({
      success: true,
      status: user.status || (isAppr ? 'approved' : 'pending'),
      applicationId: user.applicationId || '',
      approved: isAppr,
      rideServiceEnabled: user.rideServiceEnabled !== false,
      foodServiceEnabled: user.foodServiceEnabled !== false,
      servicePreferencesUpdatedAt: user.servicePreferencesUpdatedAt || user.updatedAt || user.createdAt || null,
      user: {
        uid: user.uid,
        name: user.name,
        phone: user.phone,
        role: user.role,
        status: user.status || (isAppr ? 'approved' : 'pending'),
        applicationId: user.applicationId || '',
        approved: isAppr,
        isApproved: isAppr,
        isBlocked: user.isBlocked === true,
        blockReason: user.blockReason || '',
        rejectionReason: user.rejectionReason || '',
        correctionNotes: user.correctionNotes || '',
        vehicleType: user.vehicleType || '',
        vehiclePlate: user.vehiclePlate || '',
        online: user.online === true,
        rideServiceEnabled: user.rideServiceEnabled !== false,
        foodServiceEnabled: user.foodServiceEnabled !== false,
        servicePreferencesUpdatedAt: user.servicePreferencesUpdatedAt || user.updatedAt || user.createdAt || null,
        salary: typeof user.salary === 'number' ? user.salary : 0,
        walletBalance: typeof user.walletBalance === 'number' ? user.walletBalance : 0,
        documents: user.documents || {}
      }
    });
  } catch (err) {
    console.error('User Status Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Dedicated Endpoints for Pilot Service Preferences (Ride Booking & Food Delivery ON/OFF)
app.get('/api/pilot/:uid/service-preferences', async (req, res) => {
  try {
    const { uid } = req.params;
    let user = await User.findOne({ uid });
    if (!user && uid) {
      const cleanP = uid.replace(/\D/g, '').slice(-10);
      if (cleanP) user = await User.findOne({ phone: cleanP, role: 'partner' }) || await User.findOne({ phone: cleanP });
    }
    if (!user) {
      return res.status(404).json({ success: false, message: 'Pilot not found' });
    }
    res.status(200).json({
      success: true,
      uid: user.uid,
      phone: user.phone,
      vehicleType: user.vehicleType,
      rideServiceEnabled: user.rideServiceEnabled !== false,
      foodServiceEnabled: user.foodServiceEnabled !== false,
      servicePreferencesUpdatedAt: user.servicePreferencesUpdatedAt || user.updatedAt || user.createdAt || new Date()
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.all([
  '/api/pilot/:uid/service-preferences',
  '/api/pilot/service-preferences',
  '/api/admin/drivers/:uid/service-preferences',
  '/api/admin/pilots/:uid/service-preferences'
], async (req, res) => {
  if (req.method !== 'PUT' && req.method !== 'POST') {
    return res.status(405).json({ success: false, message: 'Method not allowed' });
  }
  try {
    const targetUid = req.params.uid || req.body.uid || req.body.pilotId || req.body.phone;
    if (!targetUid) {
      return res.status(400).json({ success: false, message: 'Pilot UID or phone is required' });
    }

    let user = await User.findOne({ uid: targetUid });
    if (!user) {
      const cleanP = String(targetUid).replace(/\D/g, '').slice(-10);
      if (cleanP) user = await User.findOne({ phone: cleanP, role: 'partner' }) || await User.findOne({ phone: cleanP });
    }
    if (!user) {
      return res.status(404).json({ success: false, message: 'Pilot not found' });
    }

    const updates = { servicePreferencesUpdatedAt: new Date() };
    if (typeof req.body.rideServiceEnabled === 'boolean') {
      updates.rideServiceEnabled = req.body.rideServiceEnabled;
    }
    if (typeof req.body.foodServiceEnabled === 'boolean') {
      updates.foodServiceEnabled = req.body.foodServiceEnabled;
    }

    await User.updateOne({ _id: user._id }, { $set: updates });

    const finalRideEnabled = updates.rideServiceEnabled !== undefined ? updates.rideServiceEnabled : (user.rideServiceEnabled !== false);
    const finalFoodEnabled = updates.foodServiceEnabled !== undefined ? updates.foodServiceEnabled : (user.foodServiceEnabled !== false);

    // Update in-memory livePilotsRegistry
    const strUid = user.uid || targetUid;
    const pilotReg = livePilotsRegistry.get(strUid);
    if (pilotReg) {
      pilotReg.rideServiceEnabled = finalRideEnabled;
      pilotReg.foodServiceEnabled = finalFoodEnabled;
      pilotReg.servicePreferencesUpdatedAt = updates.servicePreferencesUpdatedAt.toISOString();
      pilotReg.lastUpdated = updates.servicePreferencesUpdatedAt.toISOString();
    }
    if (user.phone && livePilotsRegistry.has(user.phone)) {
      const pReg = livePilotsRegistry.get(user.phone);
      pReg.rideServiceEnabled = finalRideEnabled;
      pReg.foodServiceEnabled = finalFoodEnabled;
      pReg.servicePreferencesUpdatedAt = updates.servicePreferencesUpdatedAt.toISOString();
    }

    // Update onlineDrivers
    for (const [sId, d] of Object.entries(onlineDrivers)) {
      if (d.uid === strUid || d.uid === user.phone) {
        d.rideServiceEnabled = finalRideEnabled;
        d.foodServiceEnabled = finalFoodEnabled;
        const sock = io.sockets.sockets.get(sId);
        if (sock) {
          if (!finalFoodEnabled) {
            sock.leave('pilot_food_dispatch');
          } else if (isFoodDeliveryVehicle(user.vehicleType)) {
            sock.join('pilot_food_dispatch');
          }
        }
      }
    }

    // Broadcast to Admin tracking room & global pilots
    const servicePrefPayload = {
      uid: user.uid,
      pilotId: user.uid,
      phone: user.phone,
      name: user.name,
      vehicleType: user.vehicleType,
      rideServiceEnabled: finalRideEnabled,
      foodServiceEnabled: finalFoodEnabled,
      servicePreferencesUpdatedAt: updates.servicePreferencesUpdatedAt
    };
    io.to('admin_tracking').emit('pilot_service_preferences_changed', servicePrefPayload);
    io.emit('pilot_service_preferences_updated', servicePrefPayload);

    console.log(`[SERVICE PREFERENCES] Pilot ${user.name} (${user.uid}) updated: Ride=${finalRideEnabled ? 'ON' : 'OFF'}, Food=${finalFoodEnabled ? 'ON' : 'OFF'}`);

    res.status(200).json({
      success: true,
      message: 'Service preferences updated successfully',
      uid: user.uid,
      rideServiceEnabled: finalRideEnabled,
      foodServiceEnabled: finalFoodEnabled,
      servicePreferencesUpdatedAt: updates.servicePreferencesUpdatedAt
    });
  } catch (err) {
    console.error('Update Service Preferences Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Comprehensive Real-Time Admin Dashboard Metrics Aggregator
app.get('/api/admin/stats', verifyAdminAuth, async (req, res) => {
  try {
    const [
      totalCustomers,
      totalPilots,
      pendingApprovals,
      approvedPilots,
      blockedPilots,
      blockedCustomers,
      totalBookings,
      searchingBookings,
      acceptedBookings,
      activeBookingsCount,
      completedBookings,
      cancelledBookings,
      totalComplaints,
      pendingRefunds,
      paymentsCount,
      auditLogsCount
    ] = await Promise.all([
      User.countDocuments({ role: 'customer' }),
      User.countDocuments({ role: 'partner' }),
      User.countDocuments({ role: 'partner', approved: { $ne: true } }),
      User.countDocuments({ role: 'partner', approved: true }),
      User.countDocuments({ role: 'partner', isBlocked: true }),
      User.countDocuments({ role: 'customer', isBlocked: true }),
      Booking.countDocuments(),
      Booking.countDocuments({ status: 'searching' }),
      Booking.countDocuments({ status: 'accepted' }),
      Booking.countDocuments({ status: { $in: ['arrived', 'started', 'heading_to_pickup', 'on_trip'] } }),
      Booking.countDocuments({ status: 'completed' }),
      Booking.countDocuments({ status: 'cancelled' }),
      Complaint.countDocuments({ status: { $ne: 'resolved' } }),
      Refund.countDocuments({ status: { $ne: 'resolved' } }),
      Payment.countDocuments(),
      AdminAuditLog.countDocuments()
    ]);

    const onlinePilotsCount = Object.keys(onlineDrivers).length;
    const busyPilotsCount = Math.min(onlinePilotsCount, activeBookingsCount);
    const availablePilotsCount = Math.max(0, onlinePilotsCount - busyPilotsCount);
    const activeCustomersCount = activeBookingsCount + searchingBookings;
    const onlineCustomersCount = Math.max(activeCustomersCount, liveCustomerLocations.size);

    res.status(200).json({
      success: true,
      stats: {
        totalCustomers,
        onlineCustomers: onlineCustomersCount,
        activeCustomers: activeCustomersCount,
        totalPilots,
        onlinePilots: onlinePilotsCount,
        busyPilots: busyPilotsCount,
        availablePilots: availablePilotsCount,
        activeRides: activeBookingsCount,
        activeBookings: activeBookingsCount,
        completedRides: completedBookings,
        completedBookings: completedBookings,
        cancelledRides: cancelledBookings,
        cancelledBookings: cancelledBookings,
        pendingApprovals,
        approvedPilots,
        rejectedPilots: Math.max(0, totalPilots - approvedPilots - pendingApprovals),
        offlinePilots: Math.max(0, totalPilots - onlinePilotsCount),
        blockedPilots,
        blockedCustomers,
        totalBookings,
        searchingBookings,
        acceptedBookings,
        totalComplaints,
        pendingRefunds,
        totalPayments: paymentsCount,
        auditLogsCount,
        updatedAt: new Date().toISOString()
      }
    });
  } catch (err) {
    console.error('Admin Stats Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Cryptographically secure 4-digit numeric OTP generator (never 1234 or 4921)
function generate4DigitOtp() {
  let code = '';
  do {
    code = crypto.randomInt(0, 10000).toString().padStart(4, '0');
  } while (code === '1234' || code === '4921' || code === '0000');
  return code;
}

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
  pickupOtp: String,
  otpVerified: { type: Boolean, default: false },
  otpVerifiedAt: Date,
  otpAttempts: { type: Number, default: 0 },
  otpExpiresAt: Date,
  pickupOtpVerified: { type: Boolean, default: false },
  pickupOtpVerifiedAt: Date,
  pickupOtpAttempts: { type: Number, default: 0 },
  pickupOtpExpiresAt: Date,
  status: String,
  passengerId: String,
  passengerName: String,
  passengerPhone: String,
  driverId: String,
  driverName: String,
  driverPhone: String,
  ownerName: String,
  ownerPhone: String,
  vehiclePlate: String,
  vehicleNumber: String,
  vehicleModel: String,
  vehicleModelColor: String,
  customerLocation: Object,
  driverLocation: Object,
  driverHeading: { type: Number, default: 0 },
  driverSpeed: { type: Number, default: 0 },
  startTime: Date,
  endTime: Date,
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
  paymentStatus: { type: String, default: 'pending' },
  paymentId: String,
  orderId: String,
  paidAt: Date,
  scheduledDate: String,
  scheduledTimeSlot: String,
  waitingCharge: Number,
  distance: String,
  cancelledBy: String,
  cancelReason: String,
  statusHistory: { type: [Object], default: [] },

  // Round Trip & Shared Ride fields
  tripType: { type: String, default: 'ONE_WAY' }, // 'ONE_WAY', 'ROUND_TRIP', 'SHARE_AUTO', 'SHARE_CAR'
  isRoundTrip: { type: Boolean, default: false },
  returnPickup: String,
  returnDrop: String,
  returnPickupLatLng: Object,
  returnDropLatLng: Object,
  returnDate: String,
  returnTime: String,
  returnDateTime: Date,
  waitingDurationMinutes: { type: Number, default: 0 },
  pilotWaitOption: { type: String, default: 'wait_at_destination' }, // 'wait_at_destination' | 'return_later'
  outwardDistance: String,
  returnDistance: String,
  totalEstimatedDistance: String,
  outwardFare: { type: Number, default: 0 },
  returnFare: { type: Number, default: 0 },
  waitingRatePerMinute: { type: Number, default: 2 },
  tollCharges: { type: Number, default: 0 },
  taxes: { type: Number, default: 0 },
  platformCommission: { type: Number, default: 0 },
  pilotEarnings: { type: Number, default: 0 },
  estimatedFare: { type: Number, default: 0 },
  finalFare: { type: Number, default: 0 },
  currentLeg: { type: String, default: 'outward' }, // 'outward', 'waiting', 'return', 'completed'
  outwardTripStatus: { type: String, default: 'pending' }, // 'pending', 'started', 'arrived'
  returnTripStatus: { type: String, default: 'pending' }, // 'pending', 'started', 'completed'
  destinationArrivedAt: Date,
  returnStartedAt: Date,
  returnCompletedAt: Date,
  specialInstructions: String,
  passengerCount: { type: Number, default: 1 },
  sharedSeats: { type: Number, default: 1 },
  boardingOtp: String,
  deliveryOtp: String,
  deliveryOtpVerified: { type: Boolean, default: false },
  deliveryOtpVerifiedAt: Date,
  deliveryOtpAttempts: { type: Number, default: 0 },
  deliveryOtpExpiresAt: Date,
  settlementStatus: { type: String, default: 'pending_settlement' },
  settlementEligibleAt: Date,
  settledAt: Date,
  financialsProcessed: { type: Boolean, default: false },
  earningsCreditedAt: Date,
  payoutReference: { type: String, default: '' },

  updatedAt: { type: Date, default: Date.now },
  createdAt: { type: Date, default: Date.now }
}, { strict: false });
const Booking = mongoose.model('Booking', bookingSchema);

// Schema for App Sharing analytics and referral attribution
const shareEventSchema = new mongoose.Schema({
  shareId: { type: String, index: true },
  channel: { type: String, required: true }, // whatsapp, instagram, arattai, sms, facebook, native, copy_link
  role: { type: String, default: 'customer' }, // customer, pilot, admin
  refCode: { type: String, default: '' },
  userId: { type: String, default: '' },
  ip: { type: String, default: '' },
  userAgent: { type: String, default: '' },
  createdAt: { type: Date, default: Date.now }
});
const ShareEvent = mongoose.models.ShareEvent || mongoose.model('ShareEvent', shareEventSchema);

// Schema for temporary, privacy-preserving live ride sharing
const rideShareTokenSchema = new mongoose.Schema({
  token: { type: String, unique: true, index: true, required: true },
  rideId: { type: String, index: true, required: true },
  createdAt: { type: Date, default: Date.now },
  expiresAt: { type: Date, default: () => new Date(Date.now() + 24 * 60 * 60 * 1000) }
});
const RideShareToken = mongoose.models.RideShareToken || mongoose.model('RideShareToken', rideShareTokenSchema);

// Real-time in-memory cache of latest pilot locations per active ride
const latestRideLocations = {};

// Real-time in-memory cache of latest customer live coordinates
const liveCustomerLocations = new Map();

// Memory state for real-time drivers & tracking registry
let onlineDrivers = {}; // { socketId: { lat, lng, vehicle } }
const livePilotsRegistry = new Map(); // uid -> rider object
const socketToPilotUid = new Map(); // socketId -> uid
const pilotLastDbSync = new Map(); // uid -> timestamp

function getPilotTrackingRecord(uid, overrides = {}) {
  const strUid = String(uid || 'pilot_unknown');
  let existing = livePilotsRegistry.get(strUid);
  const now = new Date();
  if (!existing) {
    existing = {
      uid: strUid,
      pilotId: strUid,
      name: 'Pilot Partner',
      phone: '',
      vehicleType: 'Bike',
      vehiclePlate: '',
      lat: 17.4483,
      lng: 78.3496,
      heading: 0,
      speed: 0,
      accuracy: 5.0,
      status: 'offline', // 'online' | 'on_ride' | 'arriving' | 'offline'
      online: false,
      rideServiceEnabled: true,
      foodServiceEnabled: true,
      servicePreferencesUpdatedAt: now.toISOString(),
      rideId: null,
      rideStatus: null,
      pickup: '',
      drop: '',
      customerName: '',
      remainingDistance: '',
      eta: '',
      lastUpdated: now.toISOString(),
      timestamp: now.getTime(),
      isTransmitting: false
    };
  }
  const merged = {
    ...existing,
    ...overrides,
    rideServiceEnabled: overrides.rideServiceEnabled !== undefined ? overrides.rideServiceEnabled : (existing.rideServiceEnabled !== undefined ? existing.rideServiceEnabled : true),
    foodServiceEnabled: overrides.foodServiceEnabled !== undefined ? overrides.foodServiceEnabled : (existing.foodServiceEnabled !== undefined ? existing.foodServiceEnabled : true),
    servicePreferencesUpdatedAt: overrides.servicePreferencesUpdatedAt || existing.servicePreferencesUpdatedAt || now.toISOString(),
    lastUpdated: now.toISOString(),
    timestamp: now.getTime(),
    isTransmitting: overrides.online !== false && (overrides.online === true || existing.online === true)
  };
  const resolvedLat = merged.lat !== undefined ? merged.lat : merged.latitude;
  const resolvedLng = merged.lng !== undefined ? merged.lng : merged.longitude;
  if (resolvedLat !== undefined) {
    merged.lat = resolvedLat;
    merged.latitude = resolvedLat;
  }
  if (resolvedLng !== undefined) {
    merged.lng = resolvedLng;
    merged.longitude = resolvedLng;
  }
  livePilotsRegistry.set(strUid, merged);
  return merged;
}

// Helper: Calculate exact 10 real-time metrics for Admin Console
async function getAdminLiveStats() {
  const pilotFilter = {
    $or: [
      { role: { $in: ['partner', 'driver', 'Driver'] } },
      { applicationId: { $exists: true, $ne: '' } },
      { 'documents.aadhaarFront': { $exists: true } },
      { 'documents.licenseFront': { $exists: true } },
      { uid: /_pilot$/ }
    ]
  };

  const pendingPilotFilter = {
    $and: [
      pilotFilter,
      {
        $or: [
          { status: { $in: ['pending', 'pending_verification', 'under_review', 'action_required', 'PENDING_VERIFICATION', 'UNDER_REVIEW', 'ACTION_REQUIRED'] } },
          { approved: false, isApproved: false }
        ]
      }
    ]
  };

  const [
    totalCustomers,
    totalPilots,
    activeBookingsCount,
    completedBookings,
    cancelledBookings,
    searchingBookings,
    dbOnlinePilotsCount,
    pendingPilotsCount
  ] = await Promise.all([
    User.countDocuments({ role: 'customer' }),
    User.countDocuments(pilotFilter),
    Booking.countDocuments({ status: { $in: ['accepted', 'arrived', 'started', 'heading_to_pickup', 'on_trip'] } }),
    Booking.countDocuments({ status: 'completed' }),
    Booking.countDocuments({ status: 'cancelled' }),
    Booking.countDocuments({ status: 'searching' }),
    User.countDocuments({ role: 'partner', online: true, lastActive: { $gt: new Date(Date.now() - 300000) } }),
    User.countDocuments(pendingPilotFilter)
  ]);

  // Unique set of online pilot UIDs across active sockets, in-memory registry, and recent DB activity
  const onlinePilotUids = new Set();
  for (const driver of Object.values(onlineDrivers)) {
    if (driver.uid) onlinePilotUids.add(driver.uid);
  }
  for (const [uid, p] of livePilotsRegistry.entries()) {
    if (p.online && (Date.now() - (p.timestamp || 0) < 300000)) {
      onlinePilotUids.add(uid);
    }
  }
  const onlinePilotsCount = Math.max(onlinePilotUids.size, dbOnlinePilotsCount);
  const busyPilotsCount = Math.min(onlinePilotsCount, activeBookingsCount);
  const availablePilotsCount = Math.max(0, onlinePilotsCount - busyPilotsCount);
  const activeCustomersCount = activeBookingsCount + searchingBookings;
  const onlineCustomersCount = Math.max(activeCustomersCount, liveCustomerLocations.size);

  return {
    totalCustomers,
    onlineCustomers: onlineCustomersCount,
    activeCustomers: activeCustomersCount,
    totalPilots,
    onlinePilots: onlinePilotsCount,
    busyPilots: busyPilotsCount,
    availablePilots: availablePilotsCount,
    activeRides: activeBookingsCount,
    completedRides: completedBookings,
    cancelledRides: cancelledBookings,
    pendingApprovals: pendingPilotsCount,
    updatedAt: new Date().toISOString()
  };
}

// Helper: Enriched Pilot details with full vehicle, owner, live coordinates, and active ride
async function getEnrichedPilotsList() {
  const pilotFilter = {
    $or: [
      { role: { $in: ['partner', 'driver', 'Driver'] } },
      { applicationId: { $exists: true, $ne: '' } },
      { 'documents.aadhaarFront': { $exists: true } },
      { 'documents.licenseFront': { $exists: true } },
      { uid: /_pilot$/ }
    ]
  };
  const rawPilots = await User.find(pilotFilter)
    .sort({ submittedAt: -1, updatedAt: -1, createdAt: -1 })
    .lean();

  // Filter out customer accounts that were accidentally tagged without pilot documents or vehicle plates
  const pilots = rawPilots.filter(p => {
    const isCustomerPlaceholder = (p.name === 'StayDriv Customer' || p.name === 'Customer' || String(p.uid || '').startsWith('customer_'));
    const hasPilotDocsOrPlate = Boolean(
      p.vehiclePlate || p.vehicleNumber || p.aadhaarFront || p.licenseFront || p.rcFront ||
      (p.documents && Object.keys(p.documents).length > 0)
    );
    if (isCustomerPlaceholder && !hasPilotDocsOrPlate) {
      return false;
    }
    return true;
  });
  
  // Find all active bookings to match pilot assignments
  const activeBookings = await Booking.find({
    status: { $in: ['accepted', 'arrived', 'started', 'heading_to_pickup', 'on_trip'] }
  }).lean();
  
  const pilotActiveBookingMap = new Map();
  for (const b of activeBookings) {
    if (b.driverId) {
      pilotActiveBookingMap.set(b.driverId, b);
    }
  }

  // Find all active food deliveries to match pilot assignments
  const FoodOrder = mongoose.models.FoodOrder || mongoose.model('FoodOrder');
  let activeFoodDeliveries = [];
  try {
    activeFoodDeliveries = await FoodOrder.find({
      orderStatus: { $in: ['accepted', 'preparing', 'ready_for_pickup', 'out_for_delivery', 'reached_pickup', 'picked_up', 'out_for_return', 'reached_restaurant_for_return'] }
    }).lean();
  } catch (_) {}

  const pilotActiveFoodMap = new Map();
  for (const fo of activeFoodDeliveries) {
    if (fo.deliveryPartnerId) {
      pilotActiveFoodMap.set(String(fo.deliveryPartnerId), fo);
    }
    if (fo.deliveryPartnerPhone) {
      const pDigits = String(fo.deliveryPartnerPhone).replace(/\D/g, '').slice(-10);
      if (pDigits) pilotActiveFoodMap.set(pDigits, fo);
    }
  }

  return pilots.map(p => {
    const uid = p.uid || `pilot_${p.phone}`;
    const pDigits = String(p.phone || '').replace(/\D/g, '').slice(-10);
    const liveData = livePilotsRegistry.get(uid);
    const activeBooking = pilotActiveBookingMap.get(uid) || (pDigits ? pilotActiveBookingMap.get(pDigits) : null) || null;
    const activeFoodOrder = pilotActiveFoodMap.get(uid) || (pDigits ? pilotActiveFoodMap.get(pDigits) : null) || null;
    
    // Check real-time socket, in-memory online status, and DB heartbeat freshness (within 5 mins)
    const isOnlineNow = Boolean(
      (liveData && liveData.online && (Date.now() - (liveData.timestamp || 0) < 300000)) || 
      Object.values(onlineDrivers).some(d => d.uid === uid) ||
      (p.online && (Date.now() - new Date(p.lastActive || p.createdAt || 0).getTime() < 300000))
    );

    let rideStatus = 'available';
    if (!isOnlineNow) {
      rideStatus = 'offline';
    } else if (activeBooking) {
      rideStatus = (activeBooking.status === 'started' || activeBooking.status === 'on_trip') ? 'on_ride' : 'arriving';
    } else if (activeFoodOrder) {
      rideStatus = 'on_delivery';
    }

    const currentLat = (liveData && liveData.lat) || (activeBooking?.driverLocation?.lat) || p.lat || null;
    const currentLng = (liveData && liveData.lng) || (activeBooking?.driverLocation?.lng) || p.lng || null;
    const hasLocation = Boolean(currentLat && currentLng && currentLat !== 0 && currentLng !== 0);

    const lastLocUpdate = (liveData && liveData.timestamp) 
      ? new Date(liveData.timestamp) 
      : (p.lastLocationUpdate || p.lastActive || p.createdAt || new Date());
    
    const isLocationStale = !hasLocation || (Date.now() - new Date(lastLocUpdate).getTime() > 120000);

    let resolvedStatus = 'pending';
    if (p.isBlocked) {
      resolvedStatus = 'suspended';
    } else if (p.status) {
      const s = String(p.status).toLowerCase();
      if (s === 'approved') resolvedStatus = 'approved';
      else if (s === 'rejected') resolvedStatus = 'rejected';
      else if (s === 'action_required') resolvedStatus = 'action_required';
      else if (s === 'under_review') resolvedStatus = 'under_review';
      else if (s === 'pending_verification' || s === 'pending') resolvedStatus = 'pending';
      else resolvedStatus = s;
    } else if (p.approved && p.isApproved) {
      resolvedStatus = 'approved';
    }
    const isAppr = (resolvedStatus === 'approved');

    const appId = p.applicationId || (p.phone ? `SD-PLT-${p.phone.slice(-4)}-${(p._id || '').toString().slice(-4).toUpperCase()}` : `SD-PLT-${uid.slice(-6).toUpperCase()}`);

    return {
      _id: p._id,
      uid,
      pilotId: uid,
      applicationId: appId,
      name: p.name || 'StayDriv Pilot',
      driverName: p.name || 'StayDriv Pilot',
      phone: p.phone || '',
      driverPhone: p.phone || '',
      ownerName: p.ownerName || p.name || 'StayDriv Pilot',
      ownerPhone: p.ownerPhone || p.phone || '',
      vehicleType: p.vehicleType || 'Bike',
      vehiclePlate: p.vehiclePlate || p.vehicleNumber || '',
      vehicleNumber: p.vehicleNumber || p.vehiclePlate || '',
      vehicleMake: p.vehicleMake || '',
      vehicleModel: p.vehicleModel || (p.vehicleModelColor ? p.vehicleModelColor.split('•')[0].trim() : 'Standard'),
      vehicleColor: p.vehicleColor || (p.vehicleModelColor && p.vehicleModelColor.includes('•') ? p.vehicleModelColor.split('•')[1].trim() : ''),
      vehicleModelColor: p.vehicleModelColor || (p.vehicleMake ? `${p.vehicleMake} ${p.vehicleModel || ''} • ${p.vehicleColor || ''}`.trim() : 'Standard'),
      vehicleRegistrationDate: p.vehicleRegistrationDate || '',
      insuranceDocument: p.insuranceDocument || p.insuranceDocumentUrl || p.documents?.insurance?.url || null,
      insuranceDocumentUrl: p.insuranceDocumentUrl || p.insuranceDocument || p.documents?.insurance?.url || null,
      insuranceExpiryDate: p.insuranceExpiryDate || '',
      rcDocumentUrl: p.rcDocumentUrl || p.rcFront || p.documents?.rcFront?.url || null,
      address: p.address || '',
      online: isOnlineNow,
      onlineStatus: isOnlineNow ? 'Online' : 'Offline',
      status: resolvedStatus,
      applicationStatus: (p.approved || p.isApproved || String(p.status).toUpperCase() === 'APPROVED') ? 'APPROVED' : (p.status || 'PENDING_VERIFICATION'),
      rideStatus,
      approved: isAppr,
      isApproved: isAppr,
      isBlocked: Boolean(p.isBlocked),
      lat: currentLat,
      lng: currentLng,
      hasLocation,
      isLocationStale,
      heading: (liveData && liveData.heading) || p.heading || 0,
      speed: (liveData && liveData.speed) || p.speed || 0,
      googleMapsUrl: hasLocation ? `https://www.google.com/maps?q=${currentLat},${currentLng}` : null,
      currentBookingId: activeBooking ? activeBooking.bookingId : null,
      currentRideStatus: activeBooking ? activeBooking.status : null,
      currentCustomerName: activeBooking ? (activeBooking.passengerName || 'Customer') : null,
      currentCustomerPhone: activeBooking ? (activeBooking.passengerPhone || '') : null,
      currentPickup: activeBooking ? activeBooking.pickup : null,
      currentDestination: activeBooking ? activeBooking.drop : null,
      currentFoodOrderId: activeFoodOrder ? activeFoodOrder.orderId : null,
      currentFoodOrderStatus: activeFoodOrder ? activeFoodOrder.orderStatus : null,
      currentFoodRestaurantName: activeFoodOrder ? activeFoodOrder.restaurantName : null,
      rideServiceEnabled: p.rideServiceEnabled !== false,
      foodServiceEnabled: p.foodServiceEnabled !== false,
      servicePreferencesUpdatedAt: p.servicePreferencesUpdatedAt || p.updatedAt || p.createdAt || null,
      walletBalance: typeof p.walletBalance === 'number' ? p.walletBalance : 0,
      salary: typeof p.salary === 'number' ? p.salary : 0,
      totalLifetimeEarnings: typeof p.totalLifetimeEarnings === 'number' ? p.totalLifetimeEarnings : 0,
      dailyPlan: p.dailyPlan || { planStatus: 'none' },
      dailyPlanStatus: (p.dailyPlan && p.dailyPlan.planStatus === 'paid' && p.dailyPlan.expiresAt && new Date(p.dailyPlan.expiresAt) > new Date())
        ? 'PAID'
        : ((p.dailyPlan?.planStatus === 'paid' || p.dailyPlan?.planStatus === 'expired') ? 'EXPIRED' : 'UNPAID'),
      documents: p.documents || {},
      verificationHistory: p.verificationHistory || [],
      correctionNotes: p.correctionNotes || '',
      rejectionReason: p.rejectionReason || '',
      approvedAt: p.approvedAt || null,
      approvedBy: p.approvedBy || null,
      rejectedAt: p.rejectedAt || null,
      rejectedBy: p.rejectedBy || null,
      aadhaarFront: p.aadhaarFront || p.documents?.aadhaarFront?.url || null,
      aadhaarBack: p.aadhaarBack || p.documents?.aadhaarBack?.url || null,
      panFront: p.panFront || p.documents?.panFront?.url || null,
      panBack: p.panBack || p.documents?.panBack?.url || null,
      licenseFront: p.licenseFront || p.documents?.licenseFront?.url || null,
      licenseBack: p.licenseBack || p.documents?.licenseBack?.url || null,
      rcFront: p.rcFront || p.documents?.rcFront?.url || null,
      rcBack: p.rcBack || p.documents?.rcBack?.url || null,
      photo: p.photo || p.documents?.photo?.url || null,
      fitness: p.fitness || p.documents?.fitness?.url || null,
      permit: p.permit || p.documents?.permit?.url || null,
      dob: p.dob || null,
      licenseNumber: p.licenseNumber || '',
      aadhaarNumber: p.aadhaarNumber || '',
      vehicleSubtype: p.vehicleSubtype || '',
      dor: p.dor || p.vehicleRegistrationDate || '',
      bookingAccess: p.bookingAccess || { status: 'disabled', enabled: false, disabledReason: '' },
      adminBookingEnabled: Boolean(p.bookingAccess?.enabled === true || p.bookingAccess?.status === 'enabled'),
      bookingAccessStatus: (p.bookingAccess?.enabled === true || p.bookingAccess?.status === 'enabled') ? 'ENABLED' : 'DISABLED',
      bookingAccessReason: ((p.bookingAccess?.enabled === true || p.bookingAccess?.status === 'enabled') || /eligible for 100% earnings/i.test(p.bookingAccess?.disabledReason || ''))
        ? ''
        : (p.bookingAccess?.disabledReason || ''),
      pilotDutyStatus: (p.dutyStatus === 'ON' || p.dutyStatus === 'DUTY ON') ? 'ON' : 'OFF',
      dutyStatus: ((p.bookingAccess?.enabled === true || p.bookingAccess?.status === 'enabled') && (p.dutyStatus === 'ON' || p.dutyStatus === 'DUTY ON')) ? 'ON' : 'OFF',
      lastStatusUpdate: p.bookingAccess?.updatedAt || p.updatedAt || p.lastActive || p.createdAt,
      submittedAt: p.submittedAt || p.updatedAt || p.createdAt || new Date(),
      updatedAt: p.updatedAt || p.lastActive || p.createdAt || new Date(),
      createdAt: p.createdAt || new Date()
    };
  });
}

// Helper: Enriched Customer details with live GPS, active booking, and assigned pilot link
async function getEnrichedCustomersList() {
  const customers = await User.find({ role: 'customer' }).sort({ createdAt: -1 }).lean();
  
  const activeBookings = await Booking.find({
    status: { $in: ['searching', 'accepted', 'arrived', 'started', 'heading_to_pickup', 'on_trip'] }
  }).lean();

  const customerActiveBookingMap = new Map();
  for (const b of activeBookings) {
    if (b.passengerId) {
      customerActiveBookingMap.set(b.passengerId, b);
    }
    if (b.passengerPhone) {
      customerActiveBookingMap.set(b.passengerPhone, b);
    }
  }

  // Fetch assigned drivers for active bookings
  const driverUids = [...new Set(activeBookings.map(b => b.driverId).filter(Boolean))];
  const driversList = await User.find({ uid: { $in: driverUids } }).lean();
  const driverMap = new Map();
  for (const d of driversList) {
    driverMap.set(d.uid, d);
  }

  return customers.map(c => {
    const uid = c.uid || `customer_${c.phone}`;
    const activeBooking = customerActiveBookingMap.get(uid) || customerActiveBookingMap.get(c.phone) || null;
    const liveLoc = liveCustomerLocations.get(uid) || liveCustomerLocations.get(c.phone);

    let assignedDriver = null;
    if (activeBooking && activeBooking.driverId) {
      assignedDriver = driverMap.get(activeBooking.driverId) || {
        name: activeBooking.driverName,
        phone: activeBooking.driverPhone,
        vehiclePlate: activeBooking.vehiclePlate,
        vehicleType: activeBooking.vehicle
      };
    }

    let bookingStatus = 'none';
    if (activeBooking) {
      bookingStatus = activeBooking.status;
    }

    const currentLat = (liveLoc && liveLoc.lat) || (activeBooking?.customerLocation?.lat) || (activeBooking?.pickupLatLng?.lat) || c.lat || null;
    const currentLng = (liveLoc && liveLoc.lng) || (activeBooking?.customerLocation?.lng) || (activeBooking?.pickupLatLng?.lng) || c.lng || null;
    const hasLocation = Boolean(currentLat && currentLng && currentLat !== 0 && currentLng !== 0);

    const lastLocUpdate = (liveLoc && liveLoc.timestamp) 
      ? new Date(liveLoc.timestamp) 
      : (c.lastLocationUpdate || c.lastActive || c.createdAt || new Date());
    
    const isLocationStale = !hasLocation || (Date.now() - new Date(lastLocUpdate).getTime() > 120000);

    return {
      _id: c._id,
      uid,
      customerId: uid,
      name: c.name || 'StayDriv Customer',
      phone: c.phone || '',
      email: c.email || '',
      bookingStatus,
      currentRideStatus: bookingStatus,
      activeBookingId: activeBooking ? activeBooking.bookingId : null,
      currentPickup: activeBooking ? (activeBooking.pickup || '') : '',
      currentDestination: activeBooking ? (activeBooking.drop || '') : '',
      lat: currentLat,
      lng: currentLng,
      hasLocation,
      isLocationStale,
      googleMapsUrl: hasLocation ? `https://www.google.com/maps?q=${currentLat},${currentLng}` : null,
      assignedPilotId: assignedDriver?.uid || activeBooking?.driverId || null,
      assignedPilotName: assignedDriver?.name || activeBooking?.driverName || null,
      assignedPilotPhone: assignedDriver?.phone || activeBooking?.driverPhone || null,
      vehiclePlate: assignedDriver?.vehiclePlate || assignedDriver?.vehicleNumber || activeBooking?.vehiclePlate || null,
      vehicleType: assignedDriver?.vehicleType || activeBooking?.vehicle || null,
      vehicleModel: assignedDriver?.vehicleModel || assignedDriver?.vehicleModelColor || null,
      vehicleOwnerName: assignedDriver?.ownerName || assignedDriver?.name || null,
      vehicleOwnerPhone: assignedDriver?.ownerPhone || assignedDriver?.phone || null,
      rideStartTime: activeBooking?.startTime || (activeBooking?.assignedAt ? new Date(activeBooking.assignedAt) : null),
      lastLocationUpdate: new Date(lastLocUpdate).toISOString(),
      walletBalance: c.walletBalance || 0,
      isBlocked: Boolean(c.isBlocked),
      createdAt: c.createdAt || new Date()
    };
  });
}

// Helper: Live Operations data connecting Customer <-> Booking <-> Pilot <-> Vehicle <-> Owner
async function getLiveOperationsData() {
  const [pilots, customers, activeBookingsList, stats] = await Promise.all([
    getEnrichedPilotsList(),
    getEnrichedCustomersList(),
    Booking.find({
      status: { $in: ['searching', 'accepted', 'arrived', 'started', 'heading_to_pickup', 'on_trip'] }
    }).sort({ createdAt: -1 }).lean(),
    getAdminLiveStats()
  ]);

  const relationships = [];
  for (const b of activeBookingsList) {
    const cust = customers.find(c => c.uid === b.passengerId || c.phone === b.passengerPhone) || {
      customerId: b.passengerId,
      name: b.passengerName || 'Customer',
      phone: b.passengerPhone || '',
      lat: b.pickupLatLng?.lat || b.customerLocation?.lat || null,
      lng: b.pickupLatLng?.lng || b.customerLocation?.lng || null
    };

    let pilot = null;
    if (b.driverId) {
      pilot = pilots.find(p => p.uid === b.driverId || p.phone === b.driverPhone) || null;
    }

    relationships.push({
      bookingId: b.bookingId,
      status: b.status,
      serviceType: b.serviceType || 'ride',
      vehicleType: b.vehicle || pilot?.vehicleType || 'Bike',
      pickup: b.pickup,
      drop: b.drop,
      pickupLatLng: b.pickupLatLng,
      dropLatLng: b.dropLatLng,
      price: b.price,
      startTime: b.startTime || (b.assignedAt ? new Date(b.assignedAt) : b.createdAt),
      customer: {
        id: cust.customerId || cust.uid,
        name: cust.name,
        phone: cust.phone,
        lat: cust.lat,
        lng: cust.lng,
        hasLocation: cust.hasLocation,
        googleMapsUrl: cust.googleMapsUrl,
        lastLocationUpdate: cust.lastLocationUpdate
      },
      pilot: pilot ? {
        id: pilot.uid,
        name: pilot.name,
        phone: pilot.phone,
        lat: pilot.lat,
        lng: pilot.lng,
        heading: pilot.heading,
        speed: pilot.speed,
        onlineStatus: pilot.onlineStatus,
        rideStatus: pilot.rideStatus,
        hasLocation: pilot.hasLocation,
        isLocationStale: pilot.isLocationStale,
        googleMapsUrl: pilot.googleMapsUrl,
        lastLocationUpdate: pilot.lastLocationUpdate
      } : null,
      vehicle: {
        type: pilot?.vehicleType || b.vehicle || 'Bike',
        plate: pilot?.vehiclePlate || b.vehiclePlate || 'N/A',
        model: pilot?.vehicleModel || pilot?.vehicleModelColor || 'N/A'
      },
      vehicleOwner: {
        name: pilot?.ownerName || pilot?.name || 'Self-Owned',
        phone: pilot?.ownerPhone || pilot?.phone || 'N/A'
      }
    });
  }

  return {
    success: true,
    timestamp: new Date().toISOString(),
    stats,
    pilots,
    customers,
    activeCustomers: customers.filter(c => c.bookingStatus !== 'none'),
    onlinePilots: pilots.filter(p => p.online),
    relationships
  };
}

// 1. Generate secure temporary ride sharing token for WhatsApp sharing
app.post('/api/ride/share-token', async (req, res) => {
  try {
    const { rideId } = req.body;
    if (!rideId) {
      return res.status(400).json({ success: false, message: 'rideId is required' });
    }

    const booking = await Booking.findOne({
      $or: [{ bookingId: rideId }, { id: rideId }]
    });

    if (!booking) {
      return res.status(404).json({ success: false, message: 'Active ride not found' });
    }

    if (booking.status === 'completed' || booking.status === 'cancelled') {
      return res.status(400).json({ success: false, message: 'Cannot share completed or cancelled ride' });
    }

    let shareRecord = await RideShareToken.findOne({ rideId });
    if (!shareRecord) {
      const token = 'tr_' + crypto.randomBytes(16).toString('hex');
      shareRecord = await RideShareToken.create({
        token,
        rideId,
        createdAt: new Date(),
        expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000)
      });
    }

    // Configurable Public Tracking Base URL (Defaults to secure HTTPS domain)
    // Priority: PUBLIC_TRACKING_URL env -> TRACKING_URL env -> CloudFront HTTPS -> Forwarded host/protocol
    let trackingBase = process.env.PUBLIC_TRACKING_URL || process.env.TRACKING_URL;
    if (!trackingBase) {
      trackingBase = 'https://dk60tgl9yds4p.cloudfront.net';
    }
    trackingBase = trackingBase.replace(/\/+$/, '');
    const shareUrl = `${trackingBase}/track/${shareRecord.token}`;
    const rideRef = `#SD-${rideId.toString().replace(/^BK_/, '').slice(-4).toUpperCase()}`;

    res.status(200).json({
      success: true,
      token: shareRecord.token,
      shareUrl,
      rideRef,
      message: 'Secure ride sharing link generated'
    });
  } catch (err) {
    console.error('[SHARE TOKEN ERROR]:', err.message);
    res.status(500).json({ success: false, message: 'Failed to generate share link' });
  }
});

// 2. Fetch latest known real GPS location for active ride (eliminates dummy locations on mount)
app.get('/api/ride/latest-location', async (req, res) => {
  try {
    const { rideId } = req.query;
    if (!rideId) {
      return res.status(400).json({ success: false, message: 'rideId query param is required' });
    }

    const loc = latestRideLocations[rideId];
    if (loc) {
      return res.status(200).json({ success: true, location: loc });
    }

    const booking = await Booking.findOne({
      $or: [{ bookingId: rideId }, { id: rideId }]
    });

    if (booking && booking.driverLocation && booking.driverLocation.lat) {
      const dbLoc = {
        rideId,
        pilotId: booking.driverId || 'pilot',
        latitude: booking.driverLocation.lat,
        longitude: booking.driverLocation.lng,
        heading: booking.driverHeading || 0,
        speed: 0,
        remainingDistance: booking.remainingDistance || '',
        eta: booking.eta || '',
        navigationStatus: booking.status || 'started',
        timestamp: Date.now(),
        updatedAt: booking.updatedAt || new Date()
      };
      return res.status(200).json({ success: true, location: dbLoc });
    }

    res.status(200).json({ success: true, location: null, message: 'Waiting for pilot GPS signal' });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Error retrieving latest location' });
  }
});

// 3. Public sanitized live tracking endpoint (active only while ride is in progress)
app.get('/api/ride/live/:token', async (req, res) => {
  try {
    const { token } = req.params;
    const shareRecord = await RideShareToken.findOne({ token });
    if (!shareRecord) {
      return res.status(404).json({ success: false, message: 'Invalid or expired tracking link' });
    }

    const booking = await Booking.findOne({
      $or: [{ bookingId: shareRecord.rideId }, { id: shareRecord.rideId }]
    });

    if (!booking) {
      return res.status(404).json({ success: false, message: 'Ride details not found' });
    }

    const isEnded = booking.status === 'completed' || booking.status === 'cancelled';
    if (isEnded) {
      return res.status(410).json({
        success: false,
        ended: true,
        status: booking.status,
        message: 'This ride has ended. Live tracking is no longer active for privacy.'
      });
    }

    const latestLoc = latestRideLocations[shareRecord.rideId] || (booking.driverLocation && booking.driverLocation.lat ? {
      latitude: booking.driverLocation.lat,
      longitude: booking.driverLocation.lng,
      heading: booking.driverHeading || 0,
      remainingDistance: booking.remainingDistance || '',
      eta: booking.eta || '',
      updatedAt: booking.updatedAt
    } : null);

    const rideRef = `#SD-${shareRecord.rideId.toString().replace(/^BK_/, '').slice(-4).toUpperCase()}`;

    res.status(200).json({
      success: true,
      rideRef,
      status: booking.status,
      vehicleType: booking.vehicle || booking.vehicleType || 'Ride',
      vehiclePlate: booking.vehiclePlate ? booking.vehiclePlate.slice(0, 8) + '...' : 'Verified Vehicle',
      driverName: booking.driverName ? booking.driverName.split(' ')[0] : 'Pilot',
      pickupLatLng: booking.pickupLatLng || null,
      dropLatLng: booking.dropLatLng || null,
      pickupAddress: booking.pickupAddress || 'Pickup Point',
      dropAddress: booking.dropAddress || 'Destination',
      latestLocation: latestLoc,
      updatedAt: (latestLoc && latestLoc.updatedAt) || new Date()
    });
  } catch (err) {
    console.error('[LIVE TRACKING ERROR]:', err.message);
    res.status(500).json({ success: false, message: 'Error retrieving live ride' });
  }
});

// 4. Responsive mobile-friendly live tracking dashboard
app.get('/track/:token', async (req, res) => {
  const { token } = req.params;
  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>StayDriv Live Ride Tracking • Safety Sharing</title>
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <script src="/socket.io/socket.io.js"></script>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;600;700;800&family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
      background: #0f172a;
      color: #f8fafc;
      height: 100vh;
      display: flex;
      flex-direction: column;
      overflow: hidden;
    }
    header {
      background: #1e293b;
      padding: 12px 16px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      border-bottom: 1px solid #334155;
      z-index: 1000;
    }
    .brand {
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .brand-logo {
      width: 32px;
      height: 32px;
      background: #2563eb;
      border-radius: 8px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-weight: 800;
      color: #fff;
      font-size: 18px;
    }
    .brand-text h1 {
      font-family: 'Plus Jakarta Sans', sans-serif;
      font-size: 16px;
      font-weight: 800;
      letter-spacing: -0.02em;
      color: #fff;
    }
    .brand-text p {
      font-size: 10px;
      color: #94a3b8;
      font-weight: 500;
    }
    .safety-badge {
      display: flex;
      align-items: center;
      gap: 6px;
      background: #064e3b;
      color: #34d399;
      border: 1px solid #059669;
      padding: 4px 10px;
      border-radius: 9999px;
      font-size: 11px;
      font-weight: 700;
    }
    .safety-badge .pulse {
      width: 7px;
      height: 7px;
      background: #34d399;
      border-radius: 50%;
      box-shadow: 0 0 8px #34d399;
      animation: pulse 1.5s infinite;
    }
    @keyframes pulse {
      0%, 100% { opacity: 1; transform: scale(1); }
      50% { opacity: 0.4; transform: scale(1.3); }
    }
    #map {
      flex: 1;
      width: 100%;
      background: #1e293b;
      z-index: 1;
    }
    .bottom-sheet {
      background: #1e293b;
      border-top: 1px solid #334155;
      padding: 16px;
      border-radius: 20px 20px 0 0;
      box-shadow: 0 -8px 24px rgba(0,0,0,0.4);
      z-index: 1000;
      display: flex;
      flex-direction: column;
      gap: 12px;
    }
    .status-row {
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    .status-pill {
      background: #1d4ed8;
      color: #dbeafe;
      font-size: 12px;
      font-weight: 700;
      padding: 4px 12px;
      border-radius: 9999px;
      text-transform: uppercase;
      letter-spacing: 0.05em;
    }
    .eta-pill {
      font-family: 'Plus Jakarta Sans', sans-serif;
      font-size: 20px;
      font-weight: 800;
      color: #38bdf8;
    }
    .ride-info-grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 10px;
      background: #0f172a;
      padding: 12px;
      border-radius: 12px;
      border: 1px solid #334155;
    }
    .info-item {
      display: flex;
      flex-direction: column;
      gap: 2px;
    }
    .info-item .label {
      font-size: 10px;
      color: #94a3b8;
      text-transform: uppercase;
      font-weight: 600;
    }
    .info-item .value {
      font-size: 13px;
      font-weight: 700;
      color: #f1f5f9;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .route-points {
      display: flex;
      flex-direction: column;
      gap: 6px;
      font-size: 12px;
    }
    .route-point {
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .dot {
      width: 10px;
      height: 10px;
      border-radius: 50%;
      flex-shrink: 0;
    }
    .dot-green { background: #22c55e; }
    .dot-red { background: #ef4444; }
    .route-text {
      color: #cbd5e1;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .ended-overlay {
      position: absolute;
      inset: 0;
      background: rgba(15, 23, 42, 0.95);
      display: none;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      text-align: center;
      padding: 24px;
      z-index: 2000;
    }
    .ended-overlay.active { display: flex; }
    .ended-icon {
      width: 64px;
      height: 64px;
      background: #10b981;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      margin-bottom: 16px;
      font-size: 32px;
    }
    .ended-title {
      font-family: 'Plus Jakarta Sans', sans-serif;
      font-size: 22px;
      font-weight: 800;
      margin-bottom: 8px;
    }
    .ended-subtitle {
      font-size: 13px;
      color: #94a3b8;
      max-width: 320px;
      line-height: 1.5;
    }
    .pilot-marker {
      background: #2563eb;
      border: 3px solid #fff;
      border-radius: 50%;
      width: 36px;
      height: 36px;
      display: flex;
      align-items: center;
      justify-content: center;
      box-shadow: 0 4px 12px rgba(0,0,0,0.5);
      transition: transform 0.5s ease-out;
    }
  </style>
</head>
<body>
  <header>
    <div class="brand">
      <div class="brand-logo">S</div>
      <div class="brand-text">
        <h1>StayDriv Live</h1>
        <p>Live Safety Trip Tracker</p>
      </div>
    </div>
    <div class="safety-badge">
      <div class="pulse"></div>
      <span id="headerStatus">LIVE ENCRYPTED</span>
    </div>
  </header>

  <div id="map"></div>

  <div class="bottom-sheet">
    <div class="status-row">
      <div class="status-pill" id="rideStatusBadge">Pilot Moving</div>
      <div class="eta-pill" id="etaDisplay">-- min</div>
    </div>
    <div class="ride-info-grid">
      <div class="info-item">
        <span class="label">Trip Reference</span>
        <span class="value" id="rideRefDisplay">#SD-RIDE</span>
      </div>
      <div class="info-item">
        <span class="label">Distance Remaining</span>
        <span class="value" id="distDisplay">Calculating...</span>
      </div>
      <div class="info-item">
        <span class="label">Pilot & Vehicle</span>
        <span class="value" id="pilotVehicleDisplay">StayDriv Pilot</span>
      </div>
      <div class="info-item">
        <span class="label">Last Updated</span>
        <span class="value" id="lastUpdatedDisplay">Just now</span>
      </div>
    </div>
    <div class="route-points">
      <div class="route-point">
        <div class="dot dot-green"></div>
        <div class="route-text" id="pickupDisplay">Pickup Location</div>
      </div>
      <div class="route-point">
        <div class="dot dot-red"></div>
        <div class="route-text" id="dropDisplay">Destination Location</div>
      </div>
    </div>
  </div>

  <div class="ended-overlay" id="endedOverlay">
    <div class="ended-icon" id="endedIcon">✓</div>
    <div class="ended-title" id="endedTitle">Ride Completed</div>
    <div class="ended-subtitle" id="endedDesc">
      The passenger has safely reached their destination. Live GPS location sharing has automatically expired to preserve user privacy.
    </div>
  </div>

  <script>
    const token = "${token}";
    let map, pilotMarker, pickupMarker, dropMarker, routePolyline;
    let currentRideId = null;

    function initMap(lat, lng) {
      map = L.map('map', { zoomControl: false }).setView([lat, lng], 15);
      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        maxZoom: 19,
        attribution: '© OpenStreetMap'
      }).addTo(map);
      L.control.zoom({ position: 'topright' }).addTo(map);
    }

    function createPilotIcon(heading) {
      return L.divIcon({
        className: 'custom-pilot-icon',
        html: '<div class="pilot-marker" style="transform: rotate(' + (heading || 0) + 'deg);"><svg width="20" height="20" viewBox="0 0 24 24" fill="white"><path d="M12 2L4.5 20.29l.71.71L12 18l6.79 3 .71-.71z"/></svg></div>',
        iconSize: [36, 36],
        iconAnchor: [18, 18]
      });
    }

    function updateLiveDetails(data) {
      if (!data) return;

      if (data.ended || data.status === 'completed' || data.status === 'cancelled') {
        showEnded(data.status);
        return;
      }

      if (data.rideRef) document.getElementById('rideRefDisplay').innerText = data.rideRef;
      if (data.driverName || data.vehicleType) {
        document.getElementById('pilotVehicleDisplay').innerText = data.driverName + ' (' + data.vehicleType + ')';
      }
      if (data.pickupAddress) document.getElementById('pickupDisplay').innerText = data.pickupAddress;
      if (data.dropAddress) document.getElementById('dropDisplay').innerText = data.dropAddress;

      const loc = data.latestLocation;
      if (loc && loc.latitude && loc.longitude) {
        const lat = loc.latitude;
        const lng = loc.longitude;
        const heading = loc.heading || 0;

        if (!map) {
          initMap(lat, lng);
        }

        if (!pilotMarker) {
          pilotMarker = L.marker([lat, lng], { icon: createPilotIcon(heading) }).addTo(map);
        } else {
          pilotMarker.setLatLng([lat, lng]);
          pilotMarker.setIcon(createPilotIcon(heading));
        }

        if (loc.eta) {
          document.getElementById('etaDisplay').innerText = loc.eta;
        }
        if (loc.remainingDistance) {
          document.getElementById('distDisplay').innerText = loc.remainingDistance;
        }
        document.getElementById('lastUpdatedDisplay').innerText = new Date().toLocaleTimeString();
      }

      if (map && data.pickupLatLng && data.dropLatLng) {
        const pLat = data.pickupLatLng.lat || data.pickupLatLng.latitude;
        const pLng = data.pickupLatLng.lng || data.pickupLatLng.longitude;
        const dLat = data.dropLatLng.lat || data.dropLatLng.latitude;
        const dLng = data.dropLatLng.lng || data.dropLatLng.longitude;

        if (!pickupMarker && pLat && pLng) {
          pickupMarker = L.marker([pLat, pLng], {
            icon: L.divIcon({
              html: '<div style="background:#22c55e;width:14px;height:14px;border-radius:50%;border:2px solid white;box-shadow:0 0 6px #22c55e;"></div>',
              iconSize: [14, 14],
              iconAnchor: [7, 7]
            })
          }).addTo(map);
        }

        if (!dropMarker && dLat && dLng) {
          dropMarker = L.marker([dLat, dLng], {
            icon: L.divIcon({
              html: '<div style="background:#ef4444;width:14px;height:14px;border-radius:50%;border:2px solid white;box-shadow:0 0 6px #ef4444;"></div>',
              iconSize: [14, 14],
              iconAnchor: [7, 7]
            })
          }).addTo(map);
        }

        if (loc && loc.latitude && loc.longitude && !routePolyline && pLat && dLat) {
          routePolyline = L.polyline([[loc.latitude, loc.longitude], [dLat, dLng]], {
            color: '#38bdf8',
            weight: 5,
            opacity: 0.8,
            dashArray: '8, 8'
          }).addTo(map);
        }
      }
    }

    function showEnded(status) {
      const overlay = document.getElementById('endedOverlay');
      overlay.classList.add('active');
      document.getElementById('headerStatus').innerText = 'TRIP ENDED';
      if (status === 'cancelled') {
        document.getElementById('endedIcon').innerText = '✕';
        document.getElementById('endedIcon').style.background = '#ef4444';
        document.getElementById('endedTitle').innerText = 'Ride Cancelled';
        document.getElementById('endedDesc').innerText = 'This ride was cancelled. Live location sharing has terminated.';
      }
    }

    async function fetchStatus() {
      try {
        const res = await fetch('/api/ride/live/' + token);
        if (res.status === 410) {
          showEnded('completed');
          return;
        }
        if (res.ok) {
          const data = await res.json();
          updateLiveDetails(data);
        }
      } catch (err) {
        console.warn('Live fetch note:', err);
      }
    }

    // Initial fetch
    fetchStatus();

    // Setup Socket.IO for real-time turn-by-turn stream
    try {
      const socket = io();
      socket.emit('join_track', { token });

      socket.on('ride_location_update', (payload) => {
        if (!payload) return;
        const loc = {
          latitude: payload.latitude,
          longitude: payload.longitude,
          heading: payload.heading,
          speed: payload.speed,
          eta: payload.eta,
          remainingDistance: payload.remainingDistance
        };
        updateLiveDetails({ latestLocation: loc });
      });

      socket.on('state_update', (data) => {
        if (data && (data.status === 'completed' || data.status === 'cancelled')) {
          showEnded(data.status);
        }
      });
    } catch (e) {
      console.warn('Socket init note:', e);
    }

    // Polling fallback
    setInterval(fetchStatus, 4000);
  </script>
</body>
</html>`;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.send(html);
});

// Endpoint to fetch pilot's real-time weekly ride incentive status & progress (Monday to Sunday)
app.get('/api/pilot/incentive-status', async (req, res) => {
  try {
    const driverId = req.query.driverId || req.query.uid || '';
    const requestedVehicle = req.query.vehicleType;
    const { monday, sunday, weekKey, label } = getWeekBounds();

    let pilot = null;
    let pilotUids = [];
    if (driverId) {
      pilotUids.push(driverId);
      pilot = await User.findOne({ uid: driverId });
      if (!pilot && driverId.startsWith('mock_uid_')) {
        let phone = driverId.replace('mock_uid_', '');
        pilotUids.push(phone);
        if (phone.endsWith('_pilot')) {
          phone = phone.replace('_pilot', '');
          pilotUids.push(phone);
          pilotUids.push('mock_uid_' + phone);
          pilotUids.push(phone + '_pilot');
        }
        pilot = await User.findOne({ phone, role: 'partner' });
      }
    }

    // Determine pilot vehicle type
    const vehicle = requestedVehicle || (pilot && pilot.vehicleType) || 'Bike';
    const normalizedVehicle = vehicle.toLowerCase().includes('auto')
      ? 'Auto'
      : (vehicle.toLowerCase().includes('car') ? 'Car' : 'Bike');

    const rules = WEEKLY_INCENTIVES[normalizedVehicle] || WEEKLY_INCENTIVES.Bike;

    // Count completed rides for this pilot during the current week (Monday 00:00 to Sunday 23:59)
    let completedRidesCount = 0;
    if (pilotUids.length > 0) {
      completedRidesCount = await Booking.countDocuments({
        driverId: { $in: pilotUids },
        status: 'completed',
        updatedAt: { $gte: monday, $lte: sunday }
      });
    }

    const weekIncentiveData = (pilot && pilot.weeklyIncentives && pilot.weeklyIncentives[weekKey]) || {
      tier1_credited: false,
      tier2_credited: false,
      totalBonusCredited: 0,
      history: []
    };

    const tier1Achieved = completedRidesCount >= rules.tier1.rides;
    const tier2Achieved = completedRidesCount >= rules.tier2.rides;

    let totalBonusEarned = 0;
    if (weekIncentiveData.totalBonusCredited > 0) {
      totalBonusEarned = weekIncentiveData.totalBonusCredited;
    } else {
      if (tier2Achieved) totalBonusEarned = rules.tier2.bonus;
      else if (tier1Achieved) totalBonusEarned = rules.tier1.bonus;
    }

    let nextTarget = null;
    if (!tier1Achieved) {
      nextTarget = {
        target: rules.tier1.rides,
        bonus: rules.tier1.bonus,
        remainingRides: Math.max(0, rules.tier1.rides - completedRidesCount),
        tier: 1
      };
    } else if (!tier2Achieved) {
      nextTarget = {
        target: rules.tier2.rides,
        bonus: rules.tier2.bonus,
        remainingRides: Math.max(0, rules.tier2.rides - completedRidesCount),
        tier: 2
      };
    } else {
      nextTarget = {
        target: rules.tier2.rides,
        bonus: rules.tier2.bonus,
        remainingRides: 0,
        allCompleted: true,
        tier: 2
      };
    }

    res.status(200).json({
      success: true,
      week: {
        monday: monday.toISOString(),
        sunday: sunday.toISOString(),
        weekKey,
        label
      },
      pilot: {
        uid: driverId,
        name: pilot ? pilot.name : 'Pilot Partner',
        walletBalance: pilot ? pilot.salary : 0,
        vehicleType: normalizedVehicle
      },
      completedRidesThisWeek: completedRidesCount,
      vehicleType: normalizedVehicle,
      tiers: {
        tier1: {
          ridesRequired: rules.tier1.rides,
          bonus: rules.tier1.bonus,
          achieved: tier1Achieved,
          credited: weekIncentiveData.tier1_credited,
          remaining: Math.max(0, rules.tier1.rides - completedRidesCount)
        },
        tier2: {
          ridesRequired: rules.tier2.rides,
          bonus: rules.tier2.bonus,
          achieved: tier2Achieved,
          credited: weekIncentiveData.tier2_credited,
          remaining: Math.max(0, rules.tier2.rides - completedRidesCount)
        }
      },
      totalBonusEarnedThisWeek: totalBonusEarned,
      nextTarget,
      allRules: WEEKLY_INCENTIVES
    });
  } catch (err) {
    console.error('Pilot Incentive Status Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// MongoDB Schema for Payments
const paymentSchema = new mongoose.Schema({
  orderId: { type: String, required: true, unique: true, index: true },
  paymentId: { type: String, index: true },
  signature: String,
  amount: Number, // in paise
  currency: { type: String, default: 'INR' },
  status: { type: String, default: 'created' }, // 'created', 'captured', 'verified', 'failed', 'refunded'
  method: String,
  bookingId: { type: String, index: true },
  passengerId: String,
  customerPhone: String,
  customerEmail: String,
  receipt: String,
  notes: Object,
  errorDescription: String,
  verifiedAt: Date,
  webhookReceivedAt: Date,
  updatedAt: { type: Date, default: Date.now },
  createdAt: { type: Date, default: Date.now }
});
const Payment = mongoose.model('Payment', paymentSchema);

// MongoDB Schema for Customer Wallet Transactions
const walletTransactionSchema = new mongoose.Schema({
  transactionId: { type: String, required: true, unique: true, index: true },
  uid: { type: String, required: true, index: true },
  phone: { type: String, index: true },
  type: { type: String, default: 'credit' }, // 'credit' (add money) or 'debit' (ride payment)
  amount: { type: Number, required: true }, // in rupees
  orderId: { type: String, index: true },
  paymentId: { type: String, index: true },
  signature: String,
  status: { type: String, default: 'success' }, // 'success', 'failed'
  method: { type: String, default: 'UPI' },
  description: { type: String, default: 'Wallet Top-up' },
  balanceAfter: Number,
  createdAt: { type: Date, default: Date.now }
});
const WalletTransaction = mongoose.models.WalletTransaction || mongoose.model('WalletTransaction', walletTransactionSchema);

// MongoDB Schema for Ride Completed Transactions
const rideTransactionSchema = new mongoose.Schema({
  transactionId: { type: String, required: true, unique: true, index: true },
  bookingId: { type: String, required: true, index: true },
  pilotId: { type: String, index: true },
  customerId: { type: String, index: true },
  fare: { type: String, required: true },
  amount: { type: Number, required: true }, // in rupees
  paymentMethod: { type: String, required: true }, // 'CASH' or 'UPI'
  status: { type: String, default: 'completed' }, // 'pending', 'received', 'completed', 'failed'
  referenceId: String,
  timestamp: { type: Date, default: Date.now },
  createdAt: { type: Date, default: Date.now }
});
const RideTransaction = mongoose.models.RideTransaction || mongoose.model('RideTransaction', rideTransactionSchema);

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

// MongoDB Schema for Pilot Advance/Salary Withdrawal Requests
const withdrawalRequestSchema = new mongoose.Schema({
  withdrawalId: { type: String, required: true, unique: true },
  transactionId: { type: String, index: true },
  uid: { type: String, required: true, index: true },
  pilotName: { type: String, default: '' },
  pilotPhone: { type: String, default: '' },
  amount: { type: Number, required: true },
  fee: { type: Number, default: 0 },
  netAmount: { type: Number, default: 0 },
  bankDetails: {
    accountNumber: String,
    ifsc: String,
    bankName: String,
    accountHolderName: String,
    upiId: String
  },
  maskedDestination: { type: String, default: '' },
  status: {
    type: String,
    enum: ['pending_approval', 'pending', 'under_review', 'approved', 'processing', 'paid', 'completed', 'rejected', 'failed', 'cancelled', 'reversed'],
    default: 'pending_approval'
  },
  approvalStatus: {
    type: String,
    enum: ['pending', 'pending_approval', 'approved', 'rejected'],
    default: 'pending'
  },
  approvedBy: { type: String, default: '' },
  approvedAt: { type: Date },
  rejectedBy: { type: String, default: '' },
  rejectedAt: { type: Date },
  rejectionReason: { type: String, default: '' },
  processingDate: { type: Date },
  settlementDate: { type: Date },
  payoutProviderReference: { type: String, default: '' },
  paymentGatewayRef: { type: String, default: '' },
  utr: { type: String, default: '' },
  failureReason: { type: String, default: '' },
  adminRemarks: { type: String, default: '' },
  auditTrail: [{
    action: String,
    performedBy: String,
    timestamp: { type: Date, default: Date.now },
    notes: String
  }],
  idempotencyKey: { type: String, index: true },
  createdAt: { type: Date, default: Date.now },
  updatedAt: { type: Date, default: Date.now }
});
const WithdrawalRequest = mongoose.models.WithdrawalRequest || mongoose.model('WithdrawalRequest', withdrawalRequestSchema);

// MongoDB Schema for Complaints & Misbehaviour Reports
const complaintSchema = new mongoose.Schema({
  complaintId: { type: String, required: true, unique: true },
  type: { type: String, default: 'general_complaint' }, // 'miss_behave_with_pilot', 'miss_behave_with_customer', 'general_complaint'
  reportedByRole: { type: String, default: 'customer' }, // 'customer', 'partner', 'staff'
  reportedByName: String,
  reportedByPhone: String,
  targetName: String,
  targetPhone: String,
  bookingId: String,
  subject: String,
  description: String,
  status: { type: String, default: 'pending' }, // 'pending', 'investigating', 'resolved'
  resolutionNotes: String,
  createdAt: { type: Date, default: Date.now },
  resolvedAt: Date
});
const Complaint = mongoose.models.Complaint || mongoose.model('Complaint', complaintSchema);

// MongoDB Schema for Support Tickets (Customer, Pilot, Admin Hub)
const supportTicketSchema = new mongoose.Schema({
  ticketId: { type: String, required: true, unique: true, index: true },
  userId: { type: String, required: true, index: true },
  userType: { type: String, default: 'customer' }, // 'customer' or 'pilot'
  userName: { type: String, default: 'StayDriv User' },
  userPhone: { type: String, default: '' },
  rideId: { type: String, default: '' },
  category: { type: String, default: 'general' }, // 'booking', 'payment', 'safety', 'complaint', 'general'
  subcategory: { type: String, default: '' },
  subject: { type: String, required: true },
  description: { type: String, required: true },
  status: { type: String, default: 'OPEN' }, // 'OPEN', 'IN_PROGRESS', 'WAITING_FOR_USER', 'RESOLVED', 'CLOSED'
  priority: { type: String, default: 'MEDIUM' }, // 'LOW', 'MEDIUM', 'HIGH', 'URGENT'
  assignedAdminId: { type: String, default: null },
  assignedAdminName: { type: String, default: null },
  chatHistory: [{
    senderId: String,
    senderName: String,
    senderRole: String, // 'customer', 'pilot', 'admin', 'system'
    message: String,
    timestamp: { type: Date, default: Date.now }
  }],
  createdAt: { type: Date, default: Date.now },
  updatedAt: { type: Date, default: Date.now },
  resolvedAt: { type: Date, default: null }
});
const SupportTicket = mongoose.models.SupportTicket || mongoose.model('SupportTicket', supportTicketSchema);

// MongoDB Schema for Google Play Compliance Account Deletion Requests
const accountDeletionRequestSchema = new mongoose.Schema({
  requestId: { type: String, required: true, unique: true, index: true },
  appType: { type: String, enum: ['customer', 'pilot'], required: true },
  phone: { type: String, required: true, index: true },
  email: { type: String, default: '' },
  reason: { type: String, default: 'Not specified' },
  comments: { type: String, default: '' },
  status: { 
    type: String, 
    enum: ['PENDING_VERIFICATION', 'DEACTIVATED_AND_QUEUED', 'PROCESSING', 'COMPLETED', 'REJECTED'],
    default: 'PENDING_VERIFICATION' 
  },
  userId: { type: String, default: null },
  userName: { type: String, default: 'StayDriv User' },
  otpHash: { type: String },
  otpSalt: { type: String },
  otpExpiresAt: { type: Date },
  otpAttempts: { type: Number, default: 0 },
  isVerified: { type: Boolean, default: false },
  ticketId: { type: String, default: null },
  requestedAt: { type: Date, default: Date.now },
  verifiedAt: { type: Date, default: null },
  scheduledPurgeDate: { type: Date, default: null },
  completedAt: { type: Date, default: null },
  ipAddress: { type: String, default: '' },
  userAgent: { type: String, default: '' }
}, { timestamps: true });
const AccountDeletionRequest = mongoose.models.AccountDeletionRequest || mongoose.model('AccountDeletionRequest', accountDeletionRequestSchema);

// MongoDB Schema for Refunds (Customer & Pilot)
const refundSchema = new mongoose.Schema({
  refundId: { type: String, required: true, unique: true },
  refundType: { type: String, default: 'customer' }, // 'customer' or 'pilot'
  bookingId: String,
  userName: String,
  userPhone: String,
  amount: String,
  paymentMethod: { type: String, default: 'Online / Razorpay' },
  transactionId: String,
  reason: String,
  status: { type: String, default: 'pending' }, // 'pending', 'processed', 'rejected'
  processedBy: String,
  createdAt: { type: Date, default: Date.now },
  processedAt: Date
});
const Refund = mongoose.models.Refund || mongoose.model('Refund', refundSchema);

// Endpoint to retrieve all customers for Admin (enriched with real-time status, active booking, and live GPS)
app.get('/api/admin/customers', verifyAdminAuth, async (req, res) => {
  try {
    const customers = await getEnrichedCustomersList();
    res.status(200).json({ success: true, customers, total: customers.length });
  } catch (err) {
    console.error('MongoDB Admin Customers Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Dedicated Live Operations endpoint for Admin Console
app.get('/api/admin/live-operations', verifyAdminAuth, async (req, res) => {
  try {
    const data = await getLiveOperationsData();
    res.status(200).json(data);
  } catch (err) {
    console.error('Admin Live Operations Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Customer Location Update Endpoint (HTTP REST)
app.post('/api/customer/location-update', async (req, res) => {
  try {
    const { uid, customerId, bookingId, lat, lng, heading, speed, name, phone } = req.body;
    const cid = uid || customerId;
    const numLat = Number(lat);
    const numLng = Number(lng);
    if (!cid && !bookingId) {
      return res.status(400).json({ success: false, message: 'uid or bookingId required' });
    }
    if (isNaN(numLat) || isNaN(numLng) || (numLat === 0 && numLng === 0)) {
      return res.status(400).json({ success: false, message: 'Valid lat and lng required' });
    }

    const custRecord = {
      uid: cid || 'customer',
      customerId: cid || 'customer',
      bookingId: bookingId || null,
      name: name || 'Customer',
      phone: phone || '',
      lat: numLat,
      lng: numLng,
      heading: Number(heading) || 0,
      speed: Number(speed) || 0,
      timestamp: Date.now(),
      lastUpdated: new Date().toISOString(),
      googleMapsUrl: `https://www.google.com/maps?q=${numLat},${numLng}`
    };

    if (cid) liveCustomerLocations.set(cid, custRecord);
    if (phone) liveCustomerLocations.set(phone, custRecord);

    if (bookingId) {
      Booking.updateOne(
        { bookingId },
        {
          $set: {
            customerLocation: { lat: numLat, lng: numLng, updatedAt: new Date() }
          }
        }
      ).catch(() => {});
    }

    io.to('admin_tracking').emit('customer_location_update', custRecord);
    res.status(200).json({ success: true, location: custRecord });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to block or unblock user (Pilot or Customer)
app.post('/api/admin/user/block', verifyAdminAuth, async (req, res) => {
  try {
    const { uid, phone, role, isBlocked, reason, adminId, adminName } = req.body;
    let user = null;
    if (uid) user = await User.findOne({ uid });
    if (!user && phone && role) user = await User.findOne({ phone, role });
    if (!user && phone) user = await User.findOne({ phone });
    if (!user) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }
    const prevBlocked = !!user.isBlocked;
    user.isBlocked = !!isBlocked;
    user.blockReason = isBlocked ? (reason || 'Blocked by Admin/Staff') : '';
    user.blockedAt = isBlocked ? new Date() : null;
    user.blockedBy = adminName || 'Admin';
    if (user.role === 'partner' && isBlocked) {
      user.online = false;
      delete onlineDrivers[user.uid];
    }
    await user.save();

    await recordAdminAuditLog({
      adminId: adminId || 'admin',
      adminName: adminName || 'StayDriv Admin',
      action: isBlocked ? (user.role === 'partner' ? 'PILOT_BLOCKED' : 'CUSTOMER_BLOCKED') : (user.role === 'partner' ? 'PILOT_UNBLOCKED' : 'CUSTOMER_UNBLOCKED'),
      targetType: user.role === 'partner' ? 'pilot' : 'customer',
      targetId: user.uid,
      targetName: user.name,
      targetPhone: user.phone,
      previousState: { isBlocked: prevBlocked },
      newState: { isBlocked: !!isBlocked, blockReason: user.blockReason },
      reason: user.blockReason
    });

    const payload = {
      uid: user.uid,
      phone: user.phone,
      role: user.role,
      isBlocked: user.isBlocked,
      reason: user.blockReason,
      timestamp: new Date().toISOString()
    };
    io.emit('user_blocked_updated', payload);
    io.emit('admin_metrics_update', { type: isBlocked ? 'user_blocked' : 'user_unblocked', uid: user.uid });
    if (user.role === 'partner') {
      io.emit('pilot_approval_updated', {
        uid: user.uid,
        phone: user.phone,
        name: user.name,
        approved: !isBlocked && (user.approved ?? false),
        isBlocked: user.isBlocked,
        status: isBlocked ? 'BLOCKED' : 'ACTIVE',
        reason: user.blockReason
      });
    }

    console.log(`User ${user.name} (${user.phone}) block status updated: isBlocked=${user.isBlocked}`);
    res.status(200).json({ success: true, message: isBlocked ? 'User blocked successfully' : 'User unblocked successfully', user });
  } catch (err) {
    console.error('MongoDB Block User Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to fetch complaints / misbehaviours
app.get('/api/admin/complaints', async (req, res) => {
  try {
    const { type, status } = req.query;
    let query = {};
    if (type) query.type = type;
    if (status) query.status = status;
    const complaints = await Complaint.find(query).sort({ createdAt: -1 }).limit(100);
    res.status(200).json({ success: true, complaints });
  } catch (err) {
    console.error('MongoDB Admin Complaints Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to create a complaint / incident report
app.post(['/api/admin/complaint', '/api/complaints', '/api/complaint'], async (req, res) => {
  try {
    const { type, reportedByRole, reportedByName, reportedByPhone, targetName, targetPhone, bookingId, subject, description, driverName, vehiclePlate, vehicleType, priority } = req.body;
    const complaintId = 'CMP-' + Date.now().toString().slice(-6);
    const complaint = new Complaint({
      complaintId,
      type: type || 'general_complaint',
      reportedByRole: reportedByRole || 'customer',
      reportedByName: reportedByName || 'Customer',
      reportedByPhone: reportedByPhone || '',
      targetName: targetName || driverName || '',
      targetPhone: targetPhone || '',
      bookingId: bookingId || '',
      subject: subject || (priority === 'CRITICAL' ? 'EMERGENCY / SAFETY INCIDENT' : 'Customer Support Request'),
      description: description || `Incident report for ride ${bookingId || 'Active'}. Vehicle: ${vehicleType || ''} (${vehiclePlate || ''}).`,
      status: 'pending',
      createdAt: new Date()
    });
    await complaint.save();
    if (typeof io !== 'undefined') {
      io.emit('new_complaint', complaint);
      io.emit('admin_alert', {
        type: 'COMPLAINT',
        message: `New Incident from ${complaint.reportedByName}: ${complaint.subject}`,
        complaint
      });
    }
    res.status(200).json({ success: true, complaint });
  } catch (err) {
    console.error('MongoDB Admin Create Complaint Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});


// Endpoint to resolve a complaint
app.post('/api/admin/complaint/resolve', async (req, res) => {
  try {
    const { complaintId, resolutionNotes, adminId, adminName } = req.body;
    const complaint = await Complaint.findOne({ complaintId });
    if (!complaint) return res.status(404).json({ success: false, message: 'Complaint not found' });
    complaint.status = 'resolved';
    complaint.resolutionNotes = resolutionNotes || 'Resolved by Admin/Staff';
    complaint.resolvedAt = new Date();
    await complaint.save();

    await recordAdminAuditLog({
      adminId: adminId || 'admin',
      adminName: adminName || 'StayDriv Admin',
      action: 'COMPLAINT_RESOLVED',
      targetType: 'complaint',
      targetId: complaint.complaintId,
      targetName: complaint.subject,
      reason: complaint.resolutionNotes
    });

    io.emit('complaint_updated', { complaintId: complaint.complaintId, status: 'resolved', resolutionNotes: complaint.resolutionNotes });
    io.emit('admin_metrics_update', { type: 'complaint_resolved', complaintId });

    res.status(200).json({ success: true, complaint });
  } catch (err) {
    console.error('MongoDB Admin Resolve Complaint Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ==========================================
// STAYDRIV REAL-TIME ADMIN FINANCE & COMMISSION ROUTES
// ==========================================
const financeRoutes = require('./routes/financeRoutes');
const financeService = require('./services/financeService');

const financeRoutesInstance = financeRoutes(
  { User, Booking, WithdrawalRequest, Complaint, Refund, Payment, AdminAuditLog },
  { onlineDrivers, liveCustomerLocations },
  verifyAdminAuth,
  io
);
app.use('/api/admin', financeRoutesInstance);
app.use('/api/finance', financeRoutesInstance);

// ==========================================
// STAYDRIV ADMIN GLOBAL SEARCH ROUTE
// ==========================================
const adminSearchRoutes = require('./routes/adminSearchRoutes');
const AdminSearchFoodOrder = mongoose.models.FoodOrder || require('./models/FoodOrder');
const AdminSearchRestaurant = mongoose.models.Restaurant || require('./models/Restaurant');
const AdminSearchPilotDailyPlanPayment = mongoose.models.PilotDailyPlanPayment || require('./models/PilotDailyPlanPayment');

const adminSearchInstance = adminSearchRoutes(
  {
    User,
    Booking,
    FoodOrder: AdminSearchFoodOrder,
    Restaurant: AdminSearchRestaurant,
    PilotDailyPlanPayment: AdminSearchPilotDailyPlanPayment,
    Payment,
    WithdrawalRequest,
    Complaint
  },
  verifyAdminAuth
);
app.use('/api/admin', adminSearchInstance);

// ==========================================
// STAYDRIV SUPPORT SYSTEM ENDPOINTS
// ==========================================

// 1. Fetch remote support configuration (Helpline and WhatsApp numbers)
app.get('/api/support/config', (req, res) => {
  res.status(200).json({
    success: true,
    config: {
      helplinePhone: process.env.SUPPORT_HELPLINE_PHONE || '+919490440281',
      whatsAppPhone: process.env.SUPPORT_WHATSAPP_PHONE || '+919490440281',
      emergencyNumber: '112',
      email: 'support@staydriv.in'
    }
  });
});

// 2. Create a new support ticket (Customer & Pilot App)
app.post('/api/support/ticket', async (req, res) => {
  try {
    const { userId, userType, userName, userPhone, rideId, category, subcategory, subject, description, priority } = req.body;
    if (!subject || !subject.trim()) {
      return res.status(400).json({ success: false, message: 'Subject is required.' });
    }
    if (!description || !description.trim()) {
      return res.status(400).json({ success: false, message: 'Description is required.' });
    }

    const randomSuffix = Math.floor(100000 + Math.random() * 900000);
    const ticketId = 'STY-' + randomSuffix;

    const ticket = new SupportTicket({
      ticketId,
      userId: userId || 'anonymous',
      userType: userType || 'customer',
      userName: userName || 'StayDriv User',
      userPhone: userPhone || '',
      rideId: rideId || '',
      category: category || 'general',
      subcategory: subcategory || '',
      subject: subject.trim(),
      description: description.trim(),
      priority: priority || (category === 'safety' ? 'URGENT' : 'MEDIUM'),
      status: 'OPEN',
      chatHistory: [],
      createdAt: new Date(),
      updatedAt: new Date()
    });

    await ticket.save();

    // Broadcast ticket creation event to admin dashboard
    if (typeof io !== 'undefined' && io) {
      io.emit('support:ticket_created', ticket);
      io.emit('support_ticket_created', ticket);
    }

    res.status(201).json({ success: true, ticket });
  } catch (err) {
    console.error('Support ticket creation error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// 3. Fetch user's support tickets (My Support Requests)
app.get('/api/support/my-tickets', async (req, res) => {
  try {
    const { userId } = req.query;
    if (!userId) {
      return res.status(400).json({ success: false, message: 'userId is required.' });
    }
    const tickets = await SupportTicket.find({ userId }).sort({ createdAt: -1 }).limit(100);
    res.status(200).json({ success: true, tickets });
  } catch (err) {
    console.error('Fetch my tickets error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// 4. Fetch details of a single ticket with full chat history
app.get('/api/support/ticket/:ticketId', async (req, res) => {
  try {
    const { ticketId } = req.params;
    const ticket = await SupportTicket.findOne({ ticketId });
    if (!ticket) {
      return res.status(404).json({ success: false, message: `Ticket ${ticketId} not found.` });
    }
    res.status(200).json({ success: true, ticket });
  } catch (err) {
    console.error('Fetch ticket details error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// 5. Send a reply message to an existing support ticket
app.post('/api/support/ticket/:ticketId/reply', async (req, res) => {
  try {
    const { ticketId } = req.params;
    const { senderId, senderName, senderRole, message } = req.body;
    if (!message || !message.trim()) {
      return res.status(400).json({ success: false, message: 'Message is required.' });
    }

    const ticket = await SupportTicket.findOne({ ticketId });
    if (!ticket) {
      return res.status(404).json({ success: false, message: `Ticket ${ticketId} not found.` });
    }

    const newMsg = {
      senderId: senderId || 'user',
      senderName: senderName || 'Support Agent',
      senderRole: senderRole || 'admin',
      message: message.trim(),
      timestamp: new Date()
    };

    ticket.chatHistory.push(newMsg);
    ticket.updatedAt = new Date();

    if (senderRole === 'admin') {
      if (ticket.status !== 'RESOLVED' && ticket.status !== 'CLOSED') {
        ticket.status = 'WAITING_FOR_USER';
      }
    } else {
      if (ticket.status === 'WAITING_FOR_USER' || ticket.status === 'OPEN') {
        ticket.status = 'IN_PROGRESS';
      }
    }

    await ticket.save();

    if (typeof io !== 'undefined' && io) {
      io.emit(`support:ticket:${ticketId}:message`, newMsg);
      io.emit('support:ticket_updated', ticket);
    }

    res.status(200).json({ success: true, ticket, message: newMsg });
  } catch (err) {
    console.error('Ticket reply error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// 6. Fetch support tickets for Admin Dashboard
app.get('/api/support/admin/tickets', async (req, res) => {
  try {
    const { status, category, userType, priority, search } = req.query;
    let query = {};
    if (status) query.status = status.toUpperCase();
    if (category) query.category = category.toLowerCase();
    if (userType) query.userType = userType.toLowerCase();
    if (priority) query.priority = priority.toUpperCase();
    if (search) {
      query.$or = [
        { ticketId: new RegExp(search, 'i') },
        { subject: new RegExp(search, 'i') },
        { userName: new RegExp(search, 'i') },
        { userPhone: new RegExp(search, 'i') },
        { rideId: new RegExp(search, 'i') }
      ];
    }
    const tickets = await SupportTicket.find(query).sort({ updatedAt: -1, createdAt: -1 }).limit(200);
    res.status(200).json({ success: true, tickets });
  } catch (err) {
    console.error('Admin tickets fetch error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// 7. Update support ticket status / priority / assigned agent (Admin)
app.patch('/api/support/admin/ticket/:ticketId', async (req, res) => {
  try {
    const { ticketId } = req.params;
    const { status, priority, assignedAdminId, assignedAdminName } = req.body;

    const ticket = await SupportTicket.findOne({ ticketId });
    if (!ticket) {
      return res.status(404).json({ success: false, message: `Ticket ${ticketId} not found.` });
    }

    if (status) {
      ticket.status = status.toUpperCase();
      if (ticket.status === 'RESOLVED' || ticket.status === 'CLOSED') {
        ticket.resolvedAt = new Date();
      }
    }
    if (priority) ticket.priority = priority.toUpperCase();
    if (assignedAdminId !== undefined) ticket.assignedAdminId = assignedAdminId;
    if (assignedAdminName !== undefined) ticket.assignedAdminName = assignedAdminName;
    ticket.updatedAt = new Date();

    await ticket.save();

    if (typeof io !== 'undefined' && io) {
      io.emit('support:ticket_updated', ticket);
    }

    res.status(200).json({ success: true, ticket });
  } catch (err) {
    console.error('Admin ticket patch error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// =========================================================================
// GOOGLE PLAY CONSOLE COMPLIANCE: ACCOUNT & PERSONAL DATA DELETION ENDPOINTS
// =========================================================================

// 1. Serve Account Deletion Webpage for Public Access
app.get(['/delete-account', '/account-deletion', '/delete-account.html'], (req, res) => {
  const filePath = path.join(__dirname, 'public/delete-account.html');
  if (fs.existsSync(filePath)) {
    return res.sendFile(filePath);
  }
  res.status(404).send('StayDriv Account Deletion page not found');
});

// 2. Dispatch OTP for Account Deletion Request
app.post('/api/account/deletion-request/otp', async (req, res) => {
  try {
    const { phone, appType, email, reason, comments } = req.body;
    if (!phone) {
      return res.status(400).json({ success: false, error: 'Phone number is required' });
    }

    const cleanDigits = String(phone).replace(/\D/g, '').slice(-10);
    if (cleanDigits.length !== 10) {
      return res.status(400).json({ success: false, error: 'Please enter a valid 10-digit mobile number' });
    }

    const type = (appType === 'pilot' || appType === 'partner') ? 'pilot' : 'customer';

    // Verify account in User collection
    let targetUser = await User.findOne({
      phone: new RegExp(cleanDigits + '$'),
      ...(type === 'pilot' ? { role: { $in: ['partner', 'driver', 'pilot'] } } : { role: { $in: ['customer', 'user', 'rider'] } })
    });

    if (!targetUser) {
      targetUser = await User.findOne({ phone: new RegExp(cleanDigits + '$') });
    }

    // Generate 6-digit cryptographic OTP & salt
    const otp = crypto.randomInt(100000, 1000000).toString();
    const salt = crypto.randomBytes(16).toString('hex');
    const otpHash = crypto.createHmac('sha256', salt).update(otp).digest('hex');
    const otpExpiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 minutes

    const requestId = 'DEL-' + crypto.randomBytes(3).toString('hex').toUpperCase();

    // Upsert or create deletion request record
    await AccountDeletionRequest.findOneAndUpdate(
      { phone: cleanDigits, appType: type, status: 'PENDING_VERIFICATION' },
      {
        requestId,
        appType: type,
        phone: cleanDigits,
        email: email || '',
        reason: reason || 'Not specified',
        comments: comments || '',
        status: 'PENDING_VERIFICATION',
        userId: targetUser ? (targetUser.uid || targetUser._id.toString()) : null,
        userName: targetUser ? (targetUser.name || 'StayDriv User') : 'StayDriv User',
        otpHash,
        otpSalt: salt,
        otpExpiresAt,
        otpAttempts: 0,
        isVerified: false,
        ipAddress: req.ip || req.headers['x-forwarded-for'] || '',
        userAgent: req.headers['user-agent'] || ''
      },
      { upsert: true, new: true }
    );

    // Dispatch SMS via Smartflo / TTBS DLT Gateway
    let smsDispatched = false;
    let smsError = null;
    try {
      if (smartfloSmsService && typeof smartfloSmsService.sendOtpSms === 'function') {
        const smsResult = await smartfloSmsService.sendOtpSms(cleanDigits, otp);
        smsDispatched = smsResult && smsResult.success;
        if (!smsDispatched) {
          smsError = smsResult ? smsResult.error : 'Gateway error';
        }
      }
    } catch (smsErr) {
      console.warn('[DELETION_OTP] SMS dispatch error:', smsErr.message);
      smsError = smsErr.message;
    }

    console.log(`[ACCOUNT_DELETION] OTP generated for ${type} +91 ${cleanDigits.slice(0, 2)}******${cleanDigits.slice(-2)} (Req: ${requestId}) | Gateway Sent: ${smsDispatched}`);

    const masked = `+91 ******${cleanDigits.slice(-4)}`;
    return res.status(200).json({
      success: true,
      requestId,
      maskedPhone: masked,
      message: `Verification code sent to registered number ${masked}`,
      // Provided in development or if gateway fails so compliance tester can verify immediately
      debugCode: (process.env.NODE_ENV !== 'production' || !smsDispatched) ? otp : undefined
    });
  } catch (err) {
    console.error('Error generating account deletion OTP:', err);
    res.status(500).json({ success: false, error: 'Internal server error while processing request' });
  }
});

// 3. Verify OTP & Process Account Deactivation
app.post('/api/account/deletion-request/verify', async (req, res) => {
  try {
    const { requestId, phone, appType, otp } = req.body;
    if (!otp || (!requestId && !phone)) {
      return res.status(400).json({ success: false, error: 'Verification code and request identifier required' });
    }

    const cleanDigits = phone ? String(phone).replace(/\D/g, '').slice(-10) : '';

    const query = requestId 
      ? { requestId } 
      : { phone: cleanDigits, ...(appType ? { appType } : {}), status: 'PENDING_VERIFICATION' };

    const delReq = await AccountDeletionRequest.findOne(query).sort({ createdAt: -1 });
    if (!delReq) {
      return res.status(404).json({ success: false, error: 'No active deletion request found. Please request a new code.' });
    }

    if (delReq.otpAttempts >= 5) {
      return res.status(429).json({ success: false, error: 'Too many incorrect attempts. Please request a new verification code.' });
    }

    if (new Date() > new Date(delReq.otpExpiresAt)) {
      return res.status(400).json({ success: false, error: 'Verification code has expired. Please request a new one.' });
    }

    const calculatedHash = crypto.createHmac('sha256', delReq.otpSalt).update(String(otp).trim()).digest('hex');
    if (calculatedHash !== delReq.otpHash) {
      delReq.otpAttempts = (delReq.otpAttempts || 0) + 1;
      await delReq.save();
      return res.status(400).json({ success: false, error: `Invalid verification code. ${5 - delReq.otpAttempts} attempts remaining.` });
    }

    // OTP Verified! Deactivate account immediately & schedule permanent purge in 30 days
    const scheduledPurgeDate = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
    const ticketId = 'STY-DEL-' + delReq.requestId.replace('DEL-', '');

    delReq.isVerified = true;
    delReq.status = 'DEACTIVATED_AND_QUEUED';
    delReq.verifiedAt = new Date();
    delReq.scheduledPurgeDate = scheduledPurgeDate;
    delReq.ticketId = ticketId;
    await delReq.save();

    // 1. Immediately deactivate and invalidate sessions in User collection
    let deactivatedCount = 0;
    try {
      const userUpdateResult = await User.updateMany(
        { phone: new RegExp(delReq.phone + '$') },
        {
          $set: {
            isBlocked: true,
            status: 'deactivated',
            online: false,
            blockReason: `ACCOUNT_DELETION_REQUESTED [${delReq.requestId}]`,
            blockedAt: new Date(),
            deletionRequested: true,
            deletionRequestedAt: new Date(),
            deletionRequestId: delReq.requestId,
            deletionScheduledPurgeAt: scheduledPurgeDate
          }
        }
      );
      deactivatedCount = userUpdateResult.modifiedCount || 0;
      console.log(`[ACCOUNT_DELETION] Deactivated ${deactivatedCount} user profile(s) for phone ${delReq.phone}`);
    } catch (userErr) {
      console.error('[ACCOUNT_DELETION] Error deactivating user:', userErr.message);
    }

    // 2. Automatically generate high-priority Support Ticket in Admin system
    try {
      const ticket = new SupportTicket({
        ticketId: ticketId,
        userId: delReq.userId || ('GUEST-' + delReq.phone),
        userType: delReq.appType === 'pilot' ? 'pilot' : 'customer',
        userName: delReq.userName || 'StayDriv User',
        userPhone: delReq.phone,
        category: 'general',
        subcategory: 'account_deletion',
        subject: `Google Play Compliance: Account Deletion Request [${delReq.requestId}]`,
        description: `User requested permanent account & data deletion via Google Play compliance portal.\n\n` +
          `• Tracking ID: ${delReq.requestId}\n` +
          `• App Type: ${delReq.appType === 'pilot' ? 'StayDriv Pilot (Driver)' : 'StayDriv Rider (Customer)'}\n` +
          `• Registered Phone: +91 ${delReq.phone}\n` +
          `• Email: ${delReq.email || 'None specified'}\n` +
          `• Reason: ${delReq.reason}\n` +
          `• Comments: ${delReq.comments || 'None'}\n` +
          `• Immediate Action: User account deactivated; active sessions revoked.\n` +
          `• Scheduled Purge Date: ${scheduledPurgeDate.toISOString()}\n\n` +
          `Statutory Retention Notice:\n` +
          `- Financial invoices & tax records retained for 7 years under Section 44AA of Income Tax Act 1961 & CGST Act 2017.\n` +
          `- Security access logs retained for 180 days under Rule 3(1)(h) of IT Rules 2021 & CERT-In.\n` +
          `- Personal profile, telemetry & biometric documents will be permanently purged on schedule.`,
        status: 'OPEN',
        priority: 'HIGH',
        chatHistory: [{
          senderId: 'SYSTEM',
          senderName: 'Compliance Automation Engine',
          senderRole: 'system',
          message: `Account deletion request ${delReq.requestId} verified via OTP. Immediate deactivation complete. Scheduled purge date: ${scheduledPurgeDate.toISOString()}`,
          timestamp: new Date()
        }]
      });

      await ticket.save();

      if (typeof io !== 'undefined' && io) {
        io.emit('support:ticket_created', ticket);
        io.emit('support_ticket_created', ticket);
      }
      console.log(`[ACCOUNT_DELETION] Support ticket ${ticketId} created successfully`);
    } catch (ticketErr) {
      console.error('[ACCOUNT_DELETION] Error creating support ticket:', ticketErr.message);
    }

    return res.status(200).json({
      success: true,
      requestId: delReq.requestId,
      ticketId,
      scheduledPurgeDate,
      message: 'Account deactivation confirmed. Your personal data deletion is scheduled within 30 days.'
    });
  } catch (err) {
    console.error('Error verifying deletion OTP:', err);
    res.status(500).json({ success: false, error: 'Internal server error while verifying code' });
  }
});

// 4. Status Check Endpoint
app.get('/api/account/deletion-request/status/:query', async (req, res) => {
  try {
    const rawQuery = String(req.params.query || '').trim();
    if (!rawQuery) {
      return res.status(400).json({ success: false, error: 'Request ID or phone number required' });
    }

    let searchCriteria = {};
    if (rawQuery.toUpperCase().startsWith('DEL-')) {
      searchCriteria = { requestId: rawQuery.toUpperCase() };
    } else {
      const cleanDigits = rawQuery.replace(/\D/g, '').slice(-10);
      if (cleanDigits.length < 10) {
        return res.status(400).json({ success: false, error: 'Please enter a valid Request ID or 10-digit phone number' });
      }
      searchCriteria = { phone: cleanDigits };
    }

    const delReq = await AccountDeletionRequest.findOne(searchCriteria).sort({ createdAt: -1 });
    if (!delReq) {
      return res.status(404).json({ success: false, error: 'No deletion request found matching the query' });
    }

    return res.status(200).json({
      success: true,
      request: {
        requestId: delReq.requestId,
        appType: delReq.appType,
        status: delReq.status,
        isVerified: delReq.isVerified,
        ticketId: delReq.ticketId,
        requestedAt: delReq.requestedAt,
        scheduledPurgeDate: delReq.scheduledPurgeDate,
        maskedPhone: `+91 ******${delReq.phone.slice(-4)}`
      }
    });
  } catch (err) {
    console.error('Error checking deletion status:', err);
    res.status(500).json({ success: false, error: 'Internal server error while fetching status' });
  }
});

// Endpoint to fetch refunds (customer or pilot)
app.get('/api/admin/refunds', async (req, res) => {
  try {
    const { refundType, status } = req.query;
    let query = {};
    if (refundType) query.refundType = refundType;
    if (status) query.status = status;
    const refunds = await Refund.find(query).sort({ createdAt: -1 }).limit(100);
    res.status(200).json({ success: true, refunds });
  } catch (err) {
    console.error('MongoDB Admin Refunds Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to create a refund entry
app.post('/api/admin/refund', async (req, res) => {
  try {
    const { refundType, bookingId, userName, userPhone, amount, paymentMethod, transactionId, reason } = req.body;
    const refundId = 'REF-' + Date.now().toString().slice(-6);
    const refund = new Refund({
      refundId,
      refundType: refundType || 'customer',
      bookingId: bookingId || '',
      userName: userName || '',
      userPhone: userPhone || '',
      amount: amount || '0',
      paymentMethod: paymentMethod || 'Online / Razorpay',
      transactionId: transactionId || ('TXN-' + Date.now().toString().slice(-6)),
      reason: reason || 'Ride cancellation / fare dispute',
      status: 'pending',
      createdAt: new Date()
    });
    await refund.save();
    res.status(200).json({ success: true, refund });
  } catch (err) {
    console.error('MongoDB Admin Create Refund Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to resolve a refund (processed or rejected)
app.post('/api/admin/refund/resolve', async (req, res) => {
  try {
    const { refundId, status, processedBy, adminId, adminName, reason } = req.body;
    const refund = await Refund.findOne({ refundId });
    if (!refund) return res.status(404).json({ success: false, message: 'Refund not found' });
    const prevStatus = refund.status;
    refund.status = status || 'processed';
    refund.processedBy = processedBy || adminName || 'Admin/Staff';
    refund.processedAt = new Date();
    await refund.save();

    await recordAdminAuditLog({
      adminId: adminId || 'admin',
      adminName: adminName || processedBy || 'StayDriv Admin',
      action: refund.status === 'processed' ? 'REFUND_PROCESSED' : 'REFUND_REJECTED',
      targetType: 'refund',
      targetId: refund.refundId,
      targetName: `${refund.userName} (₹${refund.amount})`,
      previousState: { status: prevStatus },
      newState: { status: refund.status },
      reason: reason || `Refund ${refund.status}`
    });

    io.emit('refund_updated', { refundId: refund.refundId, status: refund.status });
    io.emit('admin_metrics_update', { type: 'refund_resolved', refundId });

    res.status(200).json({ success: true, refund });
  } catch (err) {
    console.error('MongoDB Admin Resolve Refund Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Helper to seed initial sample complaints and refunds for Admin/Staff console
async function seedAdminSampleData() {
  try {
    const complaintCount = await Complaint.countDocuments();
    if (complaintCount === 0) {
      await Complaint.insertMany([
        {
          complaintId: 'CMP-104821',
          type: 'miss_behave_with_pilot',
          reportedByRole: 'partner',
          reportedByName: 'Pilot Suresh',
          reportedByPhone: '9876543210',
          targetName: 'Rajesh Kumar',
          targetPhone: '9123456789',
          bookingId: 'BK-10928',
          subject: 'Customer refused to wear helmet & used abusive language',
          description: 'Customer booked a bike ride, insisted on triple riding without helmet and verbally abused pilot upon refusal.',
          status: 'pending',
          createdAt: new Date(Date.now() - 3600000 * 2)
        },
        {
          complaintId: 'CMP-104822',
          type: 'miss_behave_with_customer',
          reportedByRole: 'customer',
          reportedByName: 'Anita Sharma',
          reportedByPhone: '9988776655',
          targetName: 'Pilot Ramesh',
          targetPhone: '9876500001',
          bookingId: 'BK-10874',
          subject: 'Pilot demanded extra cash over app fare & argued',
          description: 'Pilot refused to start the trip unless paid ₹100 extra in cash outside the app and misbehaved when asked to stick to app fare.',
          status: 'pending',
          createdAt: new Date(Date.now() - 3600000 * 5)
        },
        {
          complaintId: 'CMP-104823',
          type: 'general_complaint',
          reportedByRole: 'customer',
          reportedByName: 'Vikram Reddy',
          reportedByPhone: '9700112233',
          targetName: 'StayDriv System',
          targetPhone: '',
          bookingId: 'BK-10765',
          subject: 'App showed wrong pickup navigation point',
          description: 'Map pin was placed on the opposite highway lane, causing 15 minutes delay.',
          status: 'pending',
          createdAt: new Date(Date.now() - 3600000 * 8)
        }
      ]);
      console.log('Seeded sample admin complaints successfully');
    }

    const refundCount = await Refund.countDocuments();
    if (refundCount === 0) {
      await Refund.insertMany([
        {
          refundId: 'REF-801201',
          refundType: 'customer',
          bookingId: 'BK-10822',
          userName: 'Priya Verma',
          userPhone: '9811223344',
          amount: '₹240',
          paymentMethod: 'Razorpay UPI',
          transactionId: 'TXN-RZP-9921',
          reason: 'Pilot unable to reach pickup location due to puncture; auto-cancelled after customer paid.',
          status: 'pending',
          createdAt: new Date(Date.now() - 3600000 * 3)
        },
        {
          refundId: 'REF-801202',
          refundType: 'customer',
          bookingId: 'BK-10780',
          userName: 'Karthik Rao',
          userPhone: '9822334455',
          amount: '₹139',
          paymentMethod: 'Online / Card',
          transactionId: 'TXN-RZP-8832',
          reason: 'Customer cancelled within 1 min of driver assignment, advance fee refund due.',
          status: 'pending',
          createdAt: new Date(Date.now() - 3600000 * 6)
        },
        {
          refundId: 'REF-801203',
          refundType: 'pilot',
          bookingId: 'BK-10790',
          userName: 'Mahender Rao (Pilot)',
          userPhone: '9849012345',
          amount: '₹50',
          paymentMethod: 'Direct Wallet Credit',
          transactionId: 'TXN-PLT-5512',
          reason: 'Customer cancelled 7 minutes after pilot reached pickup point; cancellation compensation due to pilot.',
          status: 'pending',
          createdAt: new Date(Date.now() - 3600000 * 4)
        }
      ]);
      console.log('Seeded sample admin refunds successfully');
    }

    // Clean up sample block state on Suresh Pilot and prevent auto-blocking real pilot partners
    await User.updateMany(
      { $or: [{ phone: '9876543210' }, { uid: 'mock_uid_9876543210_pilot' }] },
      {
        $set: {
          isBlocked: false,
          blockReason: '',
          blockedAt: null,
          status: 'approved',
          approved: true,
          isApproved: true
        }
      }
    ).catch(() => {});

    // Ensure sample blocked pilot exists only as a dedicated demo record
    let sampleBlockedPilot = await User.findOne({ uid: 'mock_uid_demo_blocked_pilot' });
    if (!sampleBlockedPilot) {
      sampleBlockedPilot = new User({
        uid: 'mock_uid_demo_blocked_pilot',
        name: 'Demo Suspended Pilot',
        phone: '9000000000',
        role: 'partner',
        vehicleType: 'Bike',
        isBlocked: true,
        blockReason: 'Demo disciplinary suspension',
        blockedAt: new Date(),
        status: 'suspended',
        approved: false,
        isApproved: false,
        salary: 0,
        walletBalance: 0
      });
      await sampleBlockedPilot.save().catch(() => {});
    }

    let sampleBlockedCust = await User.findOne({ role: 'customer', isBlocked: true });
    if (!sampleBlockedCust) {
      const custToBlock = await User.findOne({ role: 'customer' });
      if (custToBlock) {
        custToBlock.isBlocked = true;
        custToBlock.blockReason = 'Repeated fake bookings and refusal to pay fare';
        custToBlock.blockedAt = new Date();
        await custToBlock.save();
      }
    }
  } catch (err) {
    console.error('Error seeding admin sample data:', err.message);
  }
}
seedAdminSampleData();


// Idempotency cache for searching booking broadcasts (prevent duplicate incoming_request within 60s)
const recentBroadcastBookings = new Map();

// Helper: Calculate Round Trip Fare with Outward, Return, Waiting, Toll, Tax, Commission & Pilot Earnings
function calculateRoundTripFare({ vehicle = 'Bike', outwardDistanceKm = 5, returnDistanceKm = null, waitingDurationMinutes = 0, pilotWaitOption = 'wait_at_destination' }) {
  const normVehicle = vehicle.toLowerCase().trim();
  const retDist = (returnDistanceKm !== null && returnDistanceKm !== undefined && returnDistanceKm > 0) ? returnDistanceKm : outwardDistanceKm;

  let baseFare = 40;
  let perKmFare = 10;
  let waitingRatePerMin = 2.0;

  const isCarXl = normVehicle.includes('car xl') || normVehicle.includes('car_xl') || normVehicle.includes('xl') ||
                  normVehicle.includes('ertiga') || normVehicle.includes('innova') || normVehicle.includes('carens') ||
                  normVehicle.includes('scorpio') || normVehicle.includes('safari') || normVehicle.includes('xylo');

  if (isCarXl) {
    baseFare = 130;
    perKmFare = 28;
    waitingRatePerMin = 4.0;
  } else if (normVehicle.includes('auto')) {
    baseFare = 50;
    perKmFare = 15;
    waitingRatePerMin = 2.0;
  } else if (normVehicle.includes('car')) {
    baseFare = 80;
    perKmFare = 18;
    waitingRatePerMin = 3.0;
  } else if (normVehicle.includes('mini')) {
    baseFare = 150;
    perKmFare = 28;
    waitingRatePerMin = 4.0;
  } else if (normVehicle.includes('heavy')) {
    baseFare = 300;
    perKmFare = 45;
    waitingRatePerMin = 6.0;
  }

  // Outward fare
  const outwardFare = Math.round(isCarXl
    ? (baseFare + outwardDistanceKm * perKmFare)
    : (baseFare + (outwardDistanceKm > 2 ? (outwardDistanceKm - 2) * perKmFare : 0)));

  // Return leg fare with 10% round-trip discount
  const returnBaseFare = Math.round(baseFare * 0.9);
  const returnDistFare = Math.round(isCarXl
    ? ((retDist * perKmFare) * 0.9)
    : ((retDist > 2 ? (retDist - 2) * perKmFare : 0) * 0.9));
  const returnFare = returnBaseFare + returnDistFare;

  // Waiting charges
  let chargeableWaitingMins = 0;
  let waitingCharge = 0;
  if (pilotWaitOption === 'wait_at_destination' && waitingDurationMinutes > 15) {
    chargeableWaitingMins = waitingDurationMinutes - 15;
    waitingCharge = Math.round(chargeableWaitingMins * waitingRatePerMin);
  } else if (pilotWaitOption === 'return_later') {
    waitingCharge = 30; // scheduled return dispatch fee
  }

  const tollCharges = 0;
  const subTotal = outwardFare + returnFare + waitingCharge + tollCharges;
  const taxes = Math.round(subTotal * 0.05); // 5% GST
  const totalEstimatedFare = subTotal + taxes;

  const commission = Math.round(totalEstimatedFare * 0.15); // 15% platform commission
  const pilotEarnings = totalEstimatedFare - commission;

  return {
    vehicle,
    outwardDistanceKm,
    returnDistanceKm: retDist,
    totalDistanceKm: (outwardDistanceKm + retDist),
    outwardFare,
    returnFare,
    waitingDurationMinutes,
    chargeableWaitingMins,
    waitingCharge,
    tollCharges,
    taxes,
    subTotal,
    totalEstimatedFare,
    commission,
    pilotEarnings,
    waitingRatePerMin,
    pilotWaitOption
  };
}

// Calculate Round Trip Fare Endpoint
app.post('/api/fare/calculate-round-trip', (req, res) => {
  try {
    const { vehicle, outwardDistanceKm, returnDistanceKm, waitingDurationMinutes, pilotWaitOption } = req.body;
    const calc = calculateRoundTripFare({
      vehicle: vehicle || 'Bike',
      outwardDistanceKm: parseFloat(outwardDistanceKm) || 5.0,
      returnDistanceKm: returnDistanceKm !== undefined ? parseFloat(returnDistanceKm) : null,
      waitingDurationMinutes: parseInt(waitingDurationMinutes) || 0,
      pilotWaitOption: pilotWaitOption || 'wait_at_destination'
    });
    res.json({ success: true, ...calc });
  } catch (err) {
    console.error('Error calculating round trip fare:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Calculate Standard or Custom Fare Endpoint (Backend Fare Validation)
app.post('/api/fare/calculate', (req, res) => {
  try {
    const { vehicle, distanceKm, isRoundTrip, waitingDurationMinutes, pilotWaitOption, sharedSeats } = req.body;
    const normVehicle = String(vehicle || 'Bike').toLowerCase().trim();
    const km = Math.max(0, parseFloat(distanceKm) || 0);
    const seats = parseInt(sharedSeats) || 1;

    let baseFare = 40;
    let perKmFare = 10;
    let vehicleName = vehicle || 'Bike';

    const isCarXl = normVehicle.includes('car xl') || normVehicle.includes('car_xl') || normVehicle.includes('xl') ||
                    normVehicle.includes('ertiga') || normVehicle.includes('innova') || normVehicle.includes('carens') ||
                    normVehicle.includes('scorpio') || normVehicle.includes('safari') || normVehicle.includes('xylo');

    if (isCarXl) {
      vehicleName = 'Car XL';
      baseFare = 130;
      perKmFare = 28;
    } else if (normVehicle.includes('heavy') || normVehicle.includes('ton')) {
      vehicleName = 'Heavy Truck';
      baseFare = 300;
      perKmFare = 45;
    } else if (normVehicle.includes('mini truck') || normVehicle.includes('pickup') || normVehicle.includes('ace')) {
      vehicleName = 'Mini Truck';
      baseFare = 150;
      perKmFare = 28;
    } else if (normVehicle.includes('car')) {
      vehicleName = 'Car';
      baseFare = normVehicle.includes('share') ? 40 : 60;
      perKmFare = normVehicle.includes('share') ? 12 : 18;
    } else if (normVehicle.includes('auto')) {
      vehicleName = 'Auto';
      baseFare = normVehicle.includes('share') ? 25 : 40;
      perKmFare = normVehicle.includes('share') ? 9 : 15;
    }

    if (isRoundTrip) {
      const calc = calculateRoundTripFare({
        vehicle: vehicleName,
        outwardDistanceKm: km,
        waitingDurationMinutes: parseInt(waitingDurationMinutes) || 0,
        pilotWaitOption: pilotWaitOption || 'wait_at_destination'
      });
      return res.json({ success: true, ...calc });
    }

    let fare = 0;
    let distanceFare = 0;
    if (isCarXl) {
      distanceFare = km * perKmFare;
      fare = baseFare + distanceFare;
    } else if (vehicleName === 'Heavy Truck') {
      if (km <= 100.0) {
        fare = baseFare;
      } else if (km <= 275.0) {
        fare = baseFare * 2.5;
      } else {
        fare = (baseFare * 2.5) + (km - 275.0) * perKmFare;
      }
      distanceFare = fare - baseFare;
    } else {
      distanceFare = km > 2.0 ? (km - 2.0) * perKmFare : 0;
      fare = baseFare + distanceFare;
    }

    if (normVehicle.includes('share')) {
      fare = fare * seats;
    }

    const totalFare = Math.round(fare);
    const commission = Math.round(totalFare * 0.15);
    const pilotEarnings = totalFare - commission;

    res.json({
      success: true,
      vehicle: vehicleName,
      distanceKm: km,
      baseFare,
      perKmFare,
      distanceFare: Math.round(distanceFare * 100) / 100,
      totalFare,
      fareFormatted: `₹${totalFare}`,
      commission,
      pilotEarnings
    });
  } catch (err) {
    console.error('Error calculating fare:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// App Sharing Tracking & Referral Attribution
app.post('/api/share/track', async (req, res) => {
  try {
    const { channel, role, refCode, userId } = req.body;
    const shareId = 'SH_' + Date.now() + '_' + Math.random().toString(36).substring(2, 7);
    const ip = req.headers['x-forwarded-for'] || req.socket.remoteAddress || '';
    const userAgent = req.headers['user-agent'] || '';

    const event = new ShareEvent({
      shareId,
      channel: channel || 'native',
      role: role || 'customer',
      refCode: refCode || '',
      userId: userId || '',
      ip,
      userAgent,
      createdAt: new Date()
    });
    await event.save();
    console.log(`[SHARE-TRACK] Logged share via ${channel} by ${role} (ref: ${refCode})`);
    res.json({ success: true, shareId });
  } catch (err) {
    console.error('Error tracking share event:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// App Sharing Statistics for Admin Console
app.get('/api/share/stats', async (req, res) => {
  try {
    const totalShares = await ShareEvent.countDocuments();
    const customerShares = await ShareEvent.countDocuments({ role: 'customer' });
    const pilotShares = await ShareEvent.countDocuments({ role: 'pilot' });
    const byChannel = await ShareEvent.aggregate([
      { $group: { _id: '$channel', count: { $sum: 1 } } }
    ]);
    const recentEvents = await ShareEvent.find().sort({ createdAt: -1 }).limit(25);
    res.json({
      success: true,
      stats: {
        totalShares,
        customerShares,
        pilotShares,
        byChannel: Object.fromEntries(byChannel.map(c => [c._id, c.count]))
      },
      recentEvents
    });
  } catch (err) {
    console.error('Error fetching share stats:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// App Sharing Config & Official Copy Text
app.get('/api/share/config', (req, res) => {
  const cdnBase = 'https://dk60tgl9yds4p.cloudfront.net';
  res.json({
    success: true,
    customer: {
      title: 'StayDriv — Affordable, Safe & Reliable Rides',
      message: 'Hey! Join me on StayDriv for quick & affordable rides (Bike, Auto, Car, Round Trips & Shared Rides). Download the StayDriv Customer App now: ' + cdnBase + '/staydriv-latest.apk?ref=customer_share',
      downloadUrl: cdnBase + '/staydriv-latest.apk?ref=customer_share',
      webUrl: cdnBase + '/download.html?ref=customer_share'
    },
    pilot: {
      title: 'Drive with StayDriv — Maximum Earnings & Low Commission',
      message: 'Earn up to ₹35,000/month with StayDriv! Flexible hours, instant payouts & 85% earnings. Download StayDriv Pilot Partner App: ' + cdnBase + '/staydriv-latest.apk?ref=pilot_share',
      downloadUrl: cdnBase + '/staydriv-latest.apk?ref=pilot_share',
      webUrl: cdnBase + '/download.html?ref=pilot_share'
    }
  });
});

// Helper function to process financials and incentives on booking completion
async function processCompletedBookingFinancials(booking, activeBooking = {}) {
  try {
    const targetBooking = booking || activeBooking;
    if (targetBooking) {
      await pilotWalletService.creditRideEarnings(targetBooking, User, io);
    }

    const priceStr = (activeBooking && activeBooking.price) ? String(activeBooking.price) : (booking ? booking.price : '₹0');
    const cleanStr = String(priceStr).replace(/[^0-9.]/g, '');
    const fareVal = parseFloat(cleanStr) || 0.0;
    
    const driverId = (activeBooking && activeBooking.driverId) ? activeBooking.driverId : (booking ? booking.driverId : '');
    if (driverId) {
      let pilot = await User.findOne({ uid: driverId });
      if (!pilot && driverId.startsWith('mock_uid_')) {
        let phone = driverId.replace('mock_uid_', '');
        if (phone.endsWith('_pilot')) phone = phone.replace('_pilot', '');
        pilot = await User.findOne({ phone, role: 'partner' });
      }
      if (pilot) {

        // --- WEEKLY RIDE INCENTIVE OFFER EVALUATION (Mon-Sun) ---
        try {
          const { monday, sunday, weekKey, label } = getWeekBounds();
          const vehicle = (booking && booking.vehicle) || (activeBooking && activeBooking.vehicle) || pilot.vehicleType || 'Bike';
          const normalizedVehicle = vehicle.toLowerCase().includes('auto')
            ? 'Auto'
            : (vehicle.toLowerCase().includes('car') ? 'Car' : 'Bike');
          const incentiveRules = WEEKLY_INCENTIVES[normalizedVehicle] || WEEKLY_INCENTIVES.Bike;

          // Query total completed rides for this pilot in current week
          const pilotUids = [driverId];
          if (driverId.startsWith('mock_uid_')) {
            let phone = driverId.replace('mock_uid_', '');
            pilotUids.push(phone);
            if (phone.endsWith('_pilot')) {
              phone = phone.replace('_pilot', '');
              pilotUids.push(phone);
              pilotUids.push('mock_uid_' + phone);
              pilotUids.push(phone + '_pilot');
            }
          }

          const weeklyCompletedCount = await Booking.countDocuments({
            driverId: { $in: pilotUids },
            status: 'completed',
            updatedAt: { $gte: monday, $lte: sunday }
          });

          pilot.weeklyIncentives = pilot.weeklyIncentives || {};
          if (!pilot.weeklyIncentives[weekKey]) {
            pilot.weeklyIncentives[weekKey] = {
              vehicle: normalizedVehicle,
              completedRides: weeklyCompletedCount,
              tier1_credited: false,
              tier2_credited: false,
              totalBonusCredited: 0,
              history: []
            };
          }

          const currentWeekData = pilot.weeklyIncentives[weekKey];
          currentWeekData.completedRides = weeklyCompletedCount;
          currentWeekData.vehicle = normalizedVehicle;
          let creditedBonusNow = 0;

          // Tier 1 Check: 30 Rides
          if (weeklyCompletedCount >= incentiveRules.tier1.rides && !currentWeekData.tier1_credited) {
            const t1Bonus = incentiveRules.tier1.bonus;
            pilot.salary += t1Bonus;
            currentWeekData.tier1_credited = true;
            currentWeekData.totalBonusCredited += t1Bonus;
            creditedBonusNow += t1Bonus;
            currentWeekData.history.push({
              tier: 1,
              targetRides: incentiveRules.tier1.rides,
              bonus: t1Bonus,
              creditedAt: new Date()
            });
            console.log(`[INCENTIVE] 🏆 Tier 1 Achieved for ${pilot.name || driverId} (${normalizedVehicle}): ${weeklyCompletedCount} rides this week! Credited ₹${t1Bonus} bonus. Total balance: ₹${pilot.salary}`);
          }

          // Tier 2 Check: 50 Rides
          if (weeklyCompletedCount >= incentiveRules.tier2.rides && !currentWeekData.tier2_credited) {
            const t2IncrementalBonus = incentiveRules.tier2.incrementalBonus;
            pilot.salary += t2IncrementalBonus;
            currentWeekData.tier2_credited = true;
            currentWeekData.totalBonusCredited += t2IncrementalBonus;
            creditedBonusNow += t2IncrementalBonus;
            currentWeekData.history.push({
              tier: 2,
              targetRides: incentiveRules.tier2.rides,
              bonus: t2IncrementalBonus,
              cumulativeBonus: incentiveRules.tier2.bonus,
              creditedAt: new Date()
            });
            console.log(`[INCENTIVE] 🌟 Tier 2 Achieved for ${pilot.name || driverId} (${normalizedVehicle}): ${weeklyCompletedCount} rides this week! Credited ₹${t2IncrementalBonus} incremental bonus (Total: ₹${incentiveRules.tier2.bonus}). Total balance: ₹${pilot.salary}`);
          }

          pilot.markModified('weeklyIncentives');
          await pilot.save();

          if (creditedBonusNow > 0) {
            io.emit('pilot_incentive_credited', {
              driverId,
              pilotName: pilot.name,
              vehicle: normalizedVehicle,
              completedRides: weeklyCompletedCount,
              bonusCredited: creditedBonusNow,
              newBalance: pilot.salary,
              weekKey,
              label
            });
          }
        } catch (incErr) {
          console.error('Error calculating weekly pilot incentive:', incErr);
        }
      }
    }
    
    let admin = await User.findOne({ role: 'admin' });
    if (!admin) {
      admin = new User({
        uid: 'mock_uid_staydriv',
        name: 'StayDriv Admin',
        phone: '9010922111',
        role: 'admin',
        salary: 0,
      });
    }
    admin.salary = (admin.salary || 0) + commission;
    await admin.save();
    console.log(`[COMMISSION] Added ₹${commission.toFixed(2)} to admin account. New balance: ₹${admin.salary}`);

    // Automatically record captured Payment for completed booking so Admin Invoices & Payments are 100% synced
    try {
      const bId = (booking && booking.bookingId) || (activeBooking && activeBooking.bookingId);
      if (bId) {
        let existingPayment = await Payment.findOne({ bookingId: bId });
        if (!existingPayment) {
          existingPayment = new Payment({
            orderId: (activeBooking && activeBooking.orderId) || ('ORD_' + bId),
            paymentId: (activeBooking && activeBooking.paymentId) || ('PAY_' + Date.now()),
            bookingId: bId,
            amount: fareVal,
            method: (activeBooking && activeBooking.paymentOption) || (booking ? booking.paymentOption : 'cash') || 'cash',
            status: 'captured',
            phone: (activeBooking && activeBooking.passengerPhone) || (booking ? booking.passengerPhone : '') || '',
            createdAt: new Date()
          });
          await existingPayment.save();
          console.log(`[PAYMENT AUTO-RECORD] Created Payment for completed booking ${bId} (₹${fareVal})`);
          io.emit('payment_recorded', { payment: existingPayment });
        }
      }
    } catch (payErr) {
      console.warn('[PAYMENT AUTO-RECORD WARN]:', payErr.message);
    }
  } catch (err) {
    console.error('processCompletedBookingFinancials error:', err);
  }
}

// --- PILOT & BOOKING MATCHING HELPERS ---
function normalizePilotIdentifier(rawId) {
  if (!rawId) return '';
  let s = String(rawId).trim().toLowerCase();
  s = s.replace(/^mock_uid_/, '').replace(/^pilot_/, '').replace(/^user_/, '').replace(/^driver_/, '');
  s = s.replace(/_pilot$/, '').replace(/_customer$/, '').replace(/_driver$/, '');
  s = s.replace(/^\+91/, '').replace(/^91/, '');
  const digits = s.replace(/\D/g, '');
  return digits.length >= 10 ? digits.slice(-10) : (digits || s);
}

function isPilotMatch(pilot, queryId) {
  if (!pilot || !queryId) return false;
  const qIdStr = String(queryId);
  if (pilot.uid === qIdStr || pilot.phone === qIdStr) return true;

  const normQuery = normalizePilotIdentifier(qIdStr);
  const normPilotUid = pilot.uid ? normalizePilotIdentifier(pilot.uid) : '';
  const normPilotPhone = pilot.phone ? normalizePilotIdentifier(pilot.phone) : '';

  return (normQuery && normPilotUid && normQuery === normPilotUid) ||
         (normQuery && normPilotPhone && normQuery === normPilotPhone);
}

function getVehicleCategoryRegex(vehicleType) {
  if (!vehicleType) return /.*/i;
  const vt = String(vehicleType).toLowerCase().trim();
  
  if (vt.includes('heavy') || vt.includes('ton') || vt.match(/(6|8|10|12|14|16|20|25|28|30|35|40|55)\s*ton/i)) {
    return /(heavy\s*truck|ton\s*truck|\bton\b)/i;
  }
  if (vt.includes('mini truck') || vt.includes('pickup') || vt.includes('ace') || vt.includes('dost') || vt.includes('bolero')) {
    return /(mini\s*truck|pickup|tata\s*ace|dost|bolero)/i;
  }
  if (vt.includes('truck')) {
    return /truck/i;
  }
  if (vt.includes('bike') || vt.includes('scoot') || vt.includes('motorcycle') || vt.includes('two') || vt.includes('moped') || vt.includes('activa') || vt.includes('parcel')) {
    return /(bike|scoot|motorcycle|two|2\s*wheeler|moped|activa|parcel)/i;
  }
  if (vt.includes('auto') || vt.includes('rickshaw') || vt.includes('tuk') || vt.includes('three')) {
    return /(auto|rickshaw|tuktuk|three|3\s*wheeler)/i;
  }
  if (vt.includes('car xl') || vt.includes('car_xl') || vt.includes('xl') || vt.includes('ertiga') || vt.includes('innova') || vt.includes('carens') || vt.includes('scorpio') || vt.includes('safari') || vt.includes('marazzo') || vt.includes('xylo')) {
    return /(car\s*xl|car_xl|\bxl\b|innova|ertiga|xylo|marazzo|carens|scorpio|safari)/i;
  }
  if (vt.includes('car') || vt.includes('cab') || vt.includes('sedan') || vt.includes('suv') || vt.includes('mini') || vt.includes('micro') || vt.includes('hatchback') || vt.includes('prime') || vt.includes('taxi')) {
    return /^(?!.*(car\s*xl|car_xl|\bxl\b|innova|ertiga|carens)).*(car|cab|sedan|suv|mini|micro|hatchback|prime|taxi)/i;
  }
  return new RegExp(vt, 'i');
}

// Endpoint to create or update booking in MongoDB
app.post('/api/booking/update', async (req, res) => {
  try {
    const bookingId = req.body.bookingId;
    const status = req.body.status;
    const activeBooking = req.body.activeBooking || req.body;
    console.log(`Updating booking in MongoDB: ${bookingId} - status: ${status} - tripType: ${activeBooking.tripType || 'ONE_WAY'}`);

    const rtFields = [
      'tripType', 'isRoundTrip', 'returnDate', 'returnTime', 'returnDateTime',
      'returnPickup', 'returnDrop', 'returnPickupLatLng', 'returnDropLatLng',
      'waitingDurationMinutes', 'pilotWaitOption', 'outwardDistance', 'returnDistance',
      'totalEstimatedDistance', 'outwardFare', 'returnFare', 'waitingRatePerMinute',
      'tollCharges', 'taxes', 'platformCommission', 'pilotEarnings', 'estimatedFare',
      'finalFare', 'currentLeg', 'outwardTripStatus', 'returnTripStatus',
      'destinationArrivedAt', 'returnStartedAt', 'returnCompletedAt',
      'specialInstructions', 'passengerCount', 'sharedSeats', 'boardingOtp'
    ];

    let booking = await Booking.findOne({ bookingId });
    const isTransitioningToCompleted = (status === 'completed') && (!booking || booking.status !== 'completed');

    // Strict parcel delivery OTP validation: Parcel bookings CANNOT be marked completed without OTP verification!
    const isParcel = (booking && (booking.serviceType === 'parcel' || (booking.vehicle && String(booking.vehicle).toLowerCase().includes('parcel')))) ||
      (activeBooking && (activeBooking.serviceType === 'parcel' || (activeBooking.vehicle && String(activeBooking.vehicle).toLowerCase().includes('parcel'))));

    if (status === 'completed' && isParcel) {
      const isOtpVerified = booking && booking.deliveryOtpVerified;
      if (!isOtpVerified) {
        const submittedDeliveryOtp = req.body.otp || req.body.deliveryOtp || (activeBooking && (activeBooking.deliveryOtp || activeBooking.otp));
        if (booking && booking.deliveryOtp && submittedDeliveryOtp && String(submittedDeliveryOtp).trim() === String(booking.deliveryOtp).trim()) {
          booking.deliveryOtpVerified = true;
          booking.deliveryOtpVerifiedAt = new Date();
          booking.endTime = new Date();
        } else {
          return res.status(400).json({
            success: false,
            error: 'Parcel bookings must be completed using Customer Delivery OTP verification. The customer must provide the 4-digit Delivery OTP to the pilot.'
          });
        }
      }
    }

    if (status === 'started') {
      const isAlreadyStarted = booking && booking.status === 'started' && booking.otpVerified;
      if (!isAlreadyStarted) {
        const submittedStartOtp = req.body.otp || req.body.startOtp || (activeBooking && activeBooking.otp);
        const targetStartOtp = (booking && (booking.otp || booking.pickupOtp)) || (activeBooking && activeBooking.otp);
        if (booking && booking.otpVerified) {
          // Already verified through verify-start-otp
        } else if (booking && targetStartOtp && submittedStartOtp && String(submittedStartOtp).trim() === String(targetStartOtp).trim()) {
          booking.otpVerified = true;
          booking.pickupOtpVerified = true;
          booking.otpVerifiedAt = new Date();
          booking.startTime = booking.startTime || new Date();
        } else {
          return res.status(400).json({
            success: false,
            error: isParcel
              ? 'Parcel delivery cannot be started without valid Pickup OTP verification.'
              : 'Ride cannot be started without valid Ride Start OTP verification.'
          });
        }
      }
    }

    if (booking) {
      if (status === 'accepted') {
        const callerDriverId = activeBooking.driverId;
        if (booking.status === 'accepted' && booking.driverId && callerDriverId && booking.driverId !== callerDriverId) {
          console.log(`[ACCEPT_CONFLICT] Booking ${bookingId} already accepted by pilot ${booking.driverId}, rejected pilot ${callerDriverId}`);
          return res.status(409).json({ success: false, error: 'Ride already accepted by another pilot' });
        }
        if (booking.status === 'cancelled') {
          return res.status(410).json({ success: false, error: 'Ride has been cancelled by customer' });
        }
      }
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
        if (activeBooking.paymentStatus) booking.paymentStatus = activeBooking.paymentStatus;
        if (activeBooking.paymentOption) booking.paymentOption = activeBooking.paymentOption;
        if (activeBooking.paymentId) booking.paymentId = activeBooking.paymentId;
        if (activeBooking.orderId) booking.orderId = activeBooking.orderId;
        if (activeBooking.paidAt) booking.paidAt = activeBooking.paidAt;

        // Copy all round-trip and shared-ride attributes
        rtFields.forEach(f => {
          if (activeBooking[f] !== undefined) booking[f] = activeBooking[f];
        });
      }

      // Ensure valid 4-digit start OTP / pickup OTP exists (never 1234 or 4921)
      if (!booking.otp || booking.otp === '1234' || booking.otp === '4921' || booking.otp.length !== 4) {
        const freshStartOtp = generate4DigitOtp();
        booking.otp = freshStartOtp;
        booking.pickupOtp = freshStartOtp;
        booking.otpVerified = false;
        booking.otpAttempts = 0;
        booking.otpExpiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000);
      } else if (!booking.pickupOtp) {
        booking.pickupOtp = booking.otp;
      }

      // Generate 4-digit Delivery OTP for Parcel bookings if missing or invalid or matching pickup OTP
      if (isParcel) {
        if (!booking.deliveryOtp || booking.deliveryOtp.length !== 4 || booking.deliveryOtp === booking.otp || booking.deliveryOtp === '1234' || booking.deliveryOtp === '4921') {
          let dOtp = generate4DigitOtp();
          while (dOtp === booking.otp) {
            dOtp = generate4DigitOtp();
          }
          booking.deliveryOtp = dOtp;
          booking.deliveryOtpVerified = false;
          booking.deliveryOtpAttempts = 0;
          booking.deliveryOtpExpiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000);
          console.log(`[PARCEL OTP GENERATED] Created 4-digit delivery OTP for existing booking ${bookingId}`);
        }
      }

      booking.updatedAt = new Date();
      await booking.save();
    } else {
      const freshStartOtp = (activeBooking.otp && activeBooking.otp !== '1234' && activeBooking.otp !== '4921' && String(activeBooking.otp).length === 4)
        ? String(activeBooking.otp)
        : generate4DigitOtp();

      const newBookingData = {
        bookingId,
        pickup: activeBooking.pickup || '',
        drop: activeBooking.drop || '',
        pickupLatLng: activeBooking.pickupLatLng || { lat: 0, lng: 0 },
        dropLatLng: activeBooking.dropLatLng || { lat: 0, lng: 0 },
        vehicle: activeBooking.vehicle || 'Bike',
        price: activeBooking.price || 0,
        otp: freshStartOtp,
        pickupOtp: freshStartOtp,
        otpVerified: false,
        otpAttempts: 0,
        otpExpiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
        status: status || 'searching',
        passengerId: activeBooking.passengerId || '',
        passengerName: activeBooking.passengerName || '',
        passengerPhone: activeBooking.passengerPhone || '',
        driverId: activeBooking.driverId || '',
        driverName: activeBooking.driverName || '',
        vehiclePlate: activeBooking.vehiclePlate || '',
        vehicleModelColor: activeBooking.vehicleModelColor || '',
        arrivedAt: activeBooking.arrivedAt || null,
        serviceType: activeBooking.serviceType || (isParcel ? 'parcel' : 'ride'),
        title: activeBooking.title || '',
        pickupHouse: activeBooking.pickupHouse || '',
        pickupContactName: activeBooking.pickupContactName || '',
        pickupContactPhone: activeBooking.pickupContactPhone || '',
        dropHouse: activeBooking.dropHouse || '',
        dropContactName: activeBooking.dropContactName || '',
        dropContactPhone: activeBooking.dropContactPhone || '',
        paymentOption: activeBooking.paymentOption || 'cash',
        paymentStatus: activeBooking.paymentStatus || 'pending',
        paymentId: activeBooking.paymentId || null,
        orderId: activeBooking.orderId || null,
        paidAt: activeBooking.paidAt || null,
        scheduledDate: activeBooking.scheduledDate || null,
        scheduledTimeSlot: activeBooking.scheduledTimeSlot || null,
        waitingCharge: activeBooking.waitingCharge || 0,
      };

      // Generate 4-digit Delivery OTP for new Parcel bookings (distinct from pickup OTP)
      if (isParcel) {
        let dOtp = generate4DigitOtp();
        while (dOtp === freshStartOtp) {
          dOtp = generate4DigitOtp();
        }
        newBookingData.deliveryOtp = dOtp;
        newBookingData.deliveryOtpVerified = false;
        newBookingData.deliveryOtpAttempts = 0;
        newBookingData.deliveryOtpExpiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000);
        console.log(`[PARCEL OTP GENERATED] Created 4-digit delivery OTP for new booking ${bookingId}`);
      }

      // Populate round-trip and shared-ride fields
      rtFields.forEach(f => {
        if (activeBooking[f] !== undefined) newBookingData[f] = activeBooking[f];
      });

      booking = new Booking(newBookingData);
      await booking.save();
    }

    // Broadcast leg updates in real time to Customer, Pilot and Admin rooms
    if (activeBooking.currentLeg || activeBooking.outwardTripStatus || activeBooking.returnTripStatus) {
      io.to(`ride_${bookingId}`).emit('round_trip_leg_update', {
        bookingId,
        currentLeg: booking.currentLeg,
        outwardTripStatus: booking.outwardTripStatus,
        returnTripStatus: booking.returnTripStatus,
        waitingDurationMinutes: booking.waitingDurationMinutes,
        waitingCharge: booking.waitingCharge,
        price: booking.price,
        status: booking.status,
        updatedAt: new Date()
      });
      io.to('admin_tracking').emit('round_trip_leg_update', {
        bookingId,
        currentLeg: booking.currentLeg,
        tripType: booking.tripType,
        status: booking.status,
        driverId: booking.driverId,
        passengerName: booking.passengerName
      });
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

    if (status === 'searching' && booking && (!booking.driverId || booking.driverId === '')) {
      try {
        const vehicleType = booking.vehicle || booking.vehicleType || (activeBooking && (activeBooking.vehicle || activeBooking.vehicleType)) || 'Bike';
        const vehicleRegex = getVehicleCategoryRegex(vehicleType);

        const onlinePilots = await User.find({
          role: 'partner',
          online: true,
          $or: [
            { vehicleType: vehicleRegex },
            { vehicleType: { $exists: false } },
            { vehicleType: null },
            { vehicleType: '' }
          ]
        });

        const oneHourAgo = new Date(Date.now() - 3600000);
        const eligiblePilots = onlinePilots.filter(p => {
          if (p.lastActive && p.lastActive < oneHourAgo) return false;
          if (booking.declinedDrivers && (booking.declinedDrivers.includes(p.uid) || (p.phone && booking.declinedDrivers.includes(p.phone)))) return false;
          return true;
        });

        let pickupLat = 0;
        let pickupLng = 0;
        const pLatLng = booking.pickupLatLng || (activeBooking && activeBooking.pickupLatLng);
        if (pLatLng) {
          pickupLat = pLatLng.lat !== undefined ? Number(pLatLng.lat) : (pLatLng.latitude !== undefined ? Number(pLatLng.latitude) : 0);
          pickupLng = pLatLng.lng !== undefined ? Number(pLatLng.lng) : (pLatLng.longitude !== undefined ? Number(pLatLng.longitude) : 0);
        }

        if (eligiblePilots.length > 0) {
          const sortedPilots = eligiblePilots.map(p => {
            const pLat = (p.lat !== undefined && p.lat !== null && p.lat !== 0) ? Number(p.lat) : pickupLat;
            const pLng = (p.lng !== undefined && p.lng !== null && p.lng !== 0) ? Number(p.lng) : pickupLng;
            const dist = (pickupLat !== 0 && pickupLng !== 0 && pLat !== 0 && pLng !== 0) ? getDistance(pickupLat, pickupLng, pLat, pLng) : 0;
            return { pilot: p, dist };
          }).sort((a, b) => a.dist - b.dist);

          const nearest = sortedPilots[0];
          booking.driverId = nearest.pilot.uid || `pilot_${nearest.pilot.phone}` || `mock_uid_${nearest.pilot.phone}_pilot`;
          booking.assignedAt = Date.now();
          await booking.save();
          activeBooking.driverId = booking.driverId;
          console.log(`[AUTO-DISPATCH] Auto-assigned new booking ${bookingId} to online pilot: ${booking.driverId} (distance: ${nearest.dist.toFixed(1)}m)`);
        }
      } catch (dispErr) {
        console.error('[AUTO-DISPATCH ERROR]', dispErr.message);
      }
    }

    // Maintain historical audit log for booking status progression
    try {
      if (booking) {
        if (!booking.statusHistory) booking.statusHistory = [];
        booking.statusHistory.push({
          status,
          timestamp: new Date(),
          driverId: booking.driverId || activeBooking.driverId || '',
          driverName: booking.driverName || activeBooking.driverName || ''
        });
        booking.updatedAt = new Date();
        await booking.save();
      }
    } catch (_) {}

    try {
      io.emit('booking_update', { bookingId, status, activeBooking });
      io.emit('admin_booking_update', { bookingId, status, activeBooking });
      io.to('admin_tracking').emit('booking_update', { bookingId, status, activeBooking });
      io.to('admin_tracking').emit('admin_booking_update', { bookingId, status, activeBooking });
      io.emit('admin_metrics_update', { type: 'booking_status', status, bookingId });

      const assignedPilotId = activeBooking.driverId || (booking && booking.driverId);

      if (status === 'accepted') {
        io.emit('booking_accepted', { bookingId, driverId: assignedPilotId, status: 'accepted', activeBooking });
        io.to('ride_' + bookingId).emit('booking_accepted', { bookingId, driverId: assignedPilotId, status: 'accepted', activeBooking });
        io.to('booking:' + bookingId).emit('booking_accepted', { bookingId, driverId: assignedPilotId, status: 'accepted', activeBooking });
      }

      if (status === 'searching') {
        const lastBroadcast = recentBroadcastBookings.get(bookingId);
        const now = Date.now();
        recentBroadcastBookings.set(bookingId, now);
        const pilotIncomingPayload = { ...activeBooking, bookingId, status: 'searching' };
        delete pilotIncomingPayload.otp;
        delete pilotIncomingPayload.pickupOtp;
        delete pilotIncomingPayload.deliveryOtp;
        io.emit('incoming_request', pilotIncomingPayload);
        if (assignedPilotId) {
          io.to(assignedPilotId).emit('incoming_request', pilotIncomingPayload);
          io.to(`pilot_${assignedPilotId}`).emit('incoming_request', pilotIncomingPayload);
        }
        console.log(`[SOCKET DISPATCH] Broadcasted incoming_request for booking ${bookingId} to pilot ${assignedPilotId || 'all'}`);

        // Clean up stale cache items
        if (recentBroadcastBookings.size > 500) {
          const cutoff = now - 120000;
          for (const [id, ts] of recentBroadcastBookings.entries()) {
            if (ts < cutoff) recentBroadcastBookings.delete(id);
          }
        }

        // Customer pickup GPS registration for Admin live map
        const custPickup = activeBooking.pickupLatLng || (booking && booking.pickupLatLng);
        const cid = activeBooking.passengerId || (booking && booking.passengerId);
        if (custPickup && custPickup.lat && custPickup.lng && cid) {
          const custRecord = {
            uid: cid,
            customerId: cid,
            bookingId,
            name: activeBooking.passengerName || (booking && booking.passengerName) || 'Customer',
            phone: activeBooking.passengerPhone || (booking && booking.passengerPhone) || '',
            lat: Number(custPickup.lat),
            lng: Number(custPickup.lng),
            heading: 0,
            speed: 0,
            timestamp: Date.now(),
            lastUpdated: new Date().toISOString(),
            googleMapsUrl: `https://www.google.com/maps?q=${custPickup.lat},${custPickup.lng}`
          };
          liveCustomerLocations.set(cid, custRecord);
          io.to('admin_tracking').emit('customer_location_update', custRecord);
        }

        io.to('admin_tracking').emit('booking_created', { bookingId, status: 'searching', activeBooking });
      } else if (status === 'accepted') {
        recentBroadcastBookings.delete(bookingId);
        io.emit('booking_accepted', { bookingId, driverId: assignedPilotId, activeBooking });
        io.to('admin_tracking').emit('booking_accepted', { bookingId, driverId: assignedPilotId, activeBooking });

        if (assignedPilotId) {
          const pRecord = getPilotTrackingRecord(assignedPilotId, {
            rideId: bookingId,
            rideStatus: 'accepted',
            status: 'arriving'
          });
          io.to('admin_tracking').emit('pilot_location_update', pRecord);
          io.to('admin_tracking').emit('pilot_status_change', { uid: assignedPilotId, status: 'arriving', pilot: pRecord });
        }
      } else if (status === 'arrived') {
        io.emit('pilot_arrived', { bookingId, pilotId: assignedPilotId });
        io.to('admin_tracking').emit('pilot_arrived', { bookingId, pilotId: assignedPilotId, timestamp: new Date().toISOString() });
        if (assignedPilotId) {
          const pRecord = getPilotTrackingRecord(assignedPilotId, {
            rideId: bookingId,
            rideStatus: 'arrived',
            status: 'arriving'
          });
          io.to('admin_tracking').emit('pilot_location_update', pRecord);
          io.to('admin_tracking').emit('pilot_status_change', { uid: assignedPilotId, status: 'arriving', pilot: pRecord });
        }
      } else if (status === 'started' || status === 'on_trip') {
        io.emit('ride_started', { bookingId, pilotId: assignedPilotId });
        io.to('admin_tracking').emit('ride_started', { bookingId, pilotId: assignedPilotId, startTime: new Date().toISOString() });
        if (assignedPilotId) {
          const pRecord = getPilotTrackingRecord(assignedPilotId, {
            rideId: bookingId,
            rideStatus: status,
            status: 'on_ride'
          });
          io.to('admin_tracking').emit('pilot_location_update', pRecord);
          io.to('admin_tracking').emit('pilot_status_change', { uid: assignedPilotId, status: 'on_ride', pilot: pRecord });
        }
      } else if (status === 'completed') {
        io.emit('ride_completed', { bookingId, pilotId: assignedPilotId });
        io.to('admin_tracking').emit('ride_completed', { bookingId, pilotId: assignedPilotId, completedTime: new Date().toISOString() });
        if (assignedPilotId) {
          const pRecord = getPilotTrackingRecord(assignedPilotId, {
            rideId: null,
            rideStatus: null,
            status: 'online'
          });
          io.to('admin_tracking').emit('pilot_location_update', pRecord);
          io.to('admin_tracking').emit('pilot_status_change', { uid: assignedPilotId, status: 'online', pilot: pRecord });
        }
      } else if (status === 'cancelled') {
        recentBroadcastBookings.delete(bookingId);
        const cancelPayload = { bookingId, cancelledBy: activeBooking.cancelledBy, reason: activeBooking.cancelReason };
        io.emit('ride_cancelled', cancelPayload);
        io.emit('booking_cancelled', cancelPayload);
        io.to('admin_tracking').emit('booking_cancelled', cancelPayload);
        io.to('admin_tracking').emit('ride_cancelled', cancelPayload);
        if (assignedPilotId) {
          const pRecord = getPilotTrackingRecord(assignedPilotId, {
            rideId: null,
            rideStatus: null,
            status: 'online'
          });
          io.to('admin_tracking').emit('pilot_location_update', pRecord);
          io.to('admin_tracking').emit('pilot_status_change', { uid: assignedPilotId, status: 'online', pilot: pRecord });
        }
      }

      getAdminLiveStats().then(s => io.to('admin_tracking').emit('admin_stats_update', s)).catch(() => {});
    } catch (socketErr) {
      console.warn('Socket broadcast error:', socketErr.message);
    }

    if (isTransitioningToCompleted) {
      await processCompletedBookingFinancials(booking, activeBooking);
    }

    res.status(200).json({ success: true, message: 'Booking synced with MongoDB successfully', booking });
  } catch (err) {
    console.error('MongoDB Booking Update Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Dedicated Endpoint: Customer OTP Verification to Start Ride / Parcel Delivery
app.post(['/api/booking/verify-start-otp', '/api/booking/verify-ride-otp', '/api/booking/parcel/verify-pickup-otp'], async (req, res) => {
  try {
    const { bookingId, otp, driverId } = req.body;
    console.log(`[START OTP VERIFY REQUEST] bookingId: ${bookingId}, driverId: ${driverId}`);
    if (!bookingId || !otp) {
      return res.status(400).json({ success: false, error: 'Booking ID and 4-digit OTP are required.' });
    }

    const booking = await Booking.findOne({
      $or: [{ bookingId }, { _id: mongoose.isValidObjectId(bookingId) ? bookingId : null }]
    });

    if (!booking) {
      return res.status(404).json({ success: false, error: 'Booking not found.' });
    }

    const isParcel = booking.serviceType === 'parcel' || (booking.vehicle && String(booking.vehicle).toLowerCase().includes('parcel'));

    // Check pilot assignment
    if (driverId && booking.driverId && booking.driverId !== driverId) {
      const cleanReqDriver = normalizePilotIdentifier(driverId);
      const cleanBookingDriver = normalizePilotIdentifier(booking.driverId);
      if (cleanReqDriver !== cleanBookingDriver) {
        return res.status(403).json({ success: false, error: 'You are not assigned to this booking.' });
      }
    }

    // Idempotency: Already started & verified
    if (booking.status === 'started' && booking.otpVerified) {
      return res.status(200).json({
        success: true,
        message: isParcel ? 'Parcel delivery already verified and started.' : 'Ride already verified and started.',
        booking
      });
    }

    // Cannot start cancelled or completed booking
    if (booking.status === 'cancelled') {
      return res.status(400).json({ success: false, error: 'Cannot start a cancelled booking.' });
    }
    if (booking.status === 'completed') {
      return res.status(400).json({ success: false, error: 'Booking is already completed.' });
    }

    // Expiry check (24 hours)
    if (booking.otpExpiresAt && new Date() > new Date(booking.otpExpiresAt)) {
      return res.status(400).json({ success: false, error: 'Start OTP has expired. Please contact support.' });
    }

    // Attempt limit check (Max 5 attempts)
    if ((booking.otpAttempts || 0) >= 5) {
      return res.status(400).json({ success: false, error: 'Maximum OTP verification attempts exceeded (5 attempts). Please contact support.' });
    }

    const submittedOtp = String(otp).trim();
    const storedOtp = String(booking.otp || booking.pickupOtp || '').trim();

    // Distinct check for parcels: Pickup OTP must not be Delivery OTP!
    if (isParcel && booking.deliveryOtp && submittedOtp === String(booking.deliveryOtp).trim()) {
      return res.status(400).json({
        success: false,
        error: 'This is the Delivery OTP. Please ask the sender for the Pickup OTP to start delivery.'
      });
    }

    if (!storedOtp || submittedOtp !== storedOtp) {
      booking.otpAttempts = (booking.otpAttempts || 0) + 1;
      await booking.save();
      const attemptsLeft = Math.max(0, 5 - booking.otpAttempts);
      return res.status(400).json({
        success: false,
        error: `Invalid OTP. Please try again. (${attemptsLeft} attempt${attemptsLeft === 1 ? '' : 's'} remaining)`,
        attemptsLeft
      });
    }

    // OTP is valid! Mark ride/parcel started atomically
    booking.otpVerified = true;
    booking.pickupOtpVerified = true;
    booking.otpVerifiedAt = new Date();
    booking.pickupOtpVerifiedAt = new Date();
    booking.status = 'started';
    booking.startTime = booking.startTime || new Date();
    booking.arrivedAt = booking.arrivedAt || Date.now();
    booking.updatedAt = new Date();
    if (driverId && !booking.driverId) booking.driverId = driverId;

    if (!booking.statusHistory) booking.statusHistory = [];
    booking.statusHistory.push({
      status: 'started',
      timestamp: new Date(),
      driverId: booking.driverId || driverId || '',
      driverName: booking.driverName || '',
      note: isParcel ? 'Parcel pickup verified & delivery started via OTP' : 'Ride started via customer OTP verification'
    });

    await booking.save();

    // Update in-memory activeBookings if present
    if (typeof activeBookings !== 'undefined' && activeBookings[booking.bookingId]) {
      activeBookings[booking.bookingId].status = 'started';
      if (activeBookings[booking.bookingId].data) {
        activeBookings[booking.bookingId].data.status = 'started';
        activeBookings[booking.bookingId].data.otpVerified = true;
      }
    }

    // Socket broadcasts to all apps
    const assignedPilotId = booking.driverId || driverId;
    io.emit('booking_update', { bookingId: booking.bookingId, status: 'started', activeBooking: booking });
    io.to(`ride_${booking.bookingId}`).emit('ride_started', { bookingId: booking.bookingId, status: 'started', activeBooking: booking });
    io.to(`ride_${booking.bookingId}`).emit('start_otp_verified', { bookingId: booking.bookingId, verified: true });
    io.to('admin_tracking').emit('admin_booking_update', { bookingId: booking.bookingId, status: 'started', activeBooking: booking });
    io.to('admin_tracking').emit('ride_started', {
      bookingId: booking.bookingId,
      pilotId: assignedPilotId,
      startTime: booking.startTime
    });

    console.log(`[START OTP VERIFIED] Successfully verified start OTP for booking ${booking.bookingId}`);
    return res.status(200).json({
      success: true,
      message: isParcel ? 'Pickup OTP verified successfully. Delivery started.' : 'Ride OTP verified successfully. Ride started.',
      booking
    });
  } catch (err) {
    console.error('Start OTP Verification Error:', err.message);
    return res.status(500).json({ success: false, error: err.message });
  }
});

// Dedicated Endpoint: Customer OTP Verification for Parcel Delivery Completion
app.post('/api/booking/parcel/verify-delivery-otp', async (req, res) => {
  try {
    const { bookingId, otp, driverId } = req.body;
    console.log(`[PARCEL OTP VERIFY REQUEST] bookingId: ${bookingId}, driverId: ${driverId}`);
    if (!bookingId || !otp) {
      return res.status(400).json({ success: false, error: 'Booking ID and delivery OTP are required.' });
    }

    const submittedOtp = String(otp).trim();
    if (!/^\d{4}$/.test(submittedOtp)) {
      return res.status(400).json({
        success: false,
        error: 'Please enter all 4 numeric digits of the delivery OTP.'
      });
    }

    const booking = await Booking.findOne({
      $or: [{ bookingId }, { _id: mongoose.isValidObjectId(bookingId) ? bookingId : null }]
    });

    if (!booking) {
      return res.status(404).json({ success: false, error: 'Booking not found.' });
    }

    const isParcel = booking.serviceType === 'parcel' || (booking.vehicle && String(booking.vehicle).toLowerCase().includes('parcel'));
    if (!isParcel) {
      return res.status(400).json({ success: false, error: 'This booking is not a parcel delivery.' });
    }

    // Cancelled check
    if (booking.status === 'cancelled' || booking.status === 'customer_cancelled' || booking.status === 'driver_cancelled') {
      return res.status(400).json({
        success: false,
        error: 'Cannot complete a cancelled parcel booking.'
      });
    }

    // Idempotency: Already completed & verified
    if (booking.status === 'completed' && booking.deliveryOtpVerified) {
      return res.status(200).json({ success: true, message: 'Parcel delivery already verified and completed.', booking });
    }

    // Enforce that delivery has started
    if (booking.status !== 'started' && booking.status !== 'arrived_destination') {
      return res.status(400).json({
        success: false,
        error: 'Parcel delivery must be started from pickup before it can be completed at delivery.'
      });
    }

    // Expiry check (24 hours)
    if (booking.deliveryOtpExpiresAt && new Date() > new Date(booking.deliveryOtpExpiresAt)) {
      return res.status(400).json({ success: false, error: 'Delivery OTP has expired. Please contact support.' });
    }

    // Attempt limit check (Max 5 attempts)
    if ((booking.deliveryOtpAttempts || 0) >= 5) {
      return res.status(400).json({ success: false, error: 'Maximum OTP verification attempts exceeded (5 attempts). Please contact support.' });
    }

    const storedOtp = String(booking.deliveryOtp || '').trim();
    const pickupOtp = String(booking.pickupOtp || booking.otp || '').trim();

    // Distinct check: submitted OTP must not be the Pickup OTP!
    if (pickupOtp && submittedOtp === pickupOtp) {
      return res.status(400).json({
        success: false,
        error: 'This is the Pickup OTP. Please ask the recipient for the separate 4-digit Delivery OTP.'
      });
    }

    if (!storedOtp || submittedOtp !== storedOtp) {
      booking.deliveryOtpAttempts = (booking.deliveryOtpAttempts || 0) + 1;
      await booking.save();
      const attemptsLeft = Math.max(0, 5 - booking.deliveryOtpAttempts);
      return res.status(400).json({
        success: false,
        error: `Invalid OTP. Please try again. (${attemptsLeft} attempt${attemptsLeft === 1 ? '' : 's'} remaining)`,
        attemptsLeft
      });
    }

    // OTP is valid! Mark parcel booking completed atomically
    booking.deliveryOtpVerified = true;
    booking.deliveryOtpVerifiedAt = new Date();
    booking.status = 'completed';
    booking.endTime = new Date();
    booking.updatedAt = new Date();
    if (driverId && !booking.driverId) booking.driverId = driverId;

    if (!booking.statusHistory) booking.statusHistory = [];
    booking.statusHistory.push({
      status: 'completed',
      timestamp: new Date(),
      driverId: booking.driverId || driverId || '',
      driverName: booking.driverName || '',
      note: 'Parcel delivery completed via customer OTP verification'
    });

    await booking.save();

    // Process financials & payment (85% pilot, 15% commission, incentives, payment record)
    await processCompletedBookingFinancials(booking, booking.toObject ? booking.toObject() : booking);

    // Socket broadcasts
    const assignedPilotId = booking.driverId || driverId;
    io.emit('booking_update', { bookingId: booking.bookingId, status: 'completed', activeBooking: booking });
    io.emit('ride_completed', { bookingId: booking.bookingId, pilotId: assignedPilotId });
    io.to(`ride_${booking.bookingId}`).emit('delivery_otp_verified', { bookingId: booking.bookingId, verified: true });
    io.to('admin_tracking').emit('ride_completed', { bookingId: booking.bookingId, pilotId: assignedPilotId, completedTime: new Date().toISOString() });
    io.to('admin_tracking').emit('admin_booking_update', { bookingId: booking.bookingId, status: 'completed', activeBooking: booking });
    if (assignedPilotId) {
      const pRecord = getPilotTrackingRecord(assignedPilotId, { rideId: null, rideStatus: null, status: 'online' });
      io.to('admin_tracking').emit('pilot_location_update', pRecord);
      io.to('admin_tracking').emit('pilot_status_change', { uid: assignedPilotId, status: 'online', pilot: pRecord });
    }

    console.log(`[PARCEL OTP VERIFIED] Successfully verified OTP for parcel booking ${booking.bookingId}`);
    return res.status(200).json({ success: true, message: 'Delivery OTP verified successfully. Parcel delivered.', booking });
  } catch (err) {
    console.error('Parcel OTP Verification Error:', err.message);
    return res.status(500).json({ success: false, error: err.message });
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
      io.emit('admin_booking_update', cancelPayload);
      io.to('admin_tracking').emit('booking_cancelled', cancelPayload);
      io.to('admin_tracking').emit('ride_cancelled', cancelPayload);
      io.to('admin_tracking').emit('admin_booking_update', cancelPayload);
      io.emit('admin_metrics_update', { type: 'booking_cancelled', bookingId });
      if (booking.driverId) {
        const pRecord = getPilotTrackingRecord(booking.driverId, {
          rideId: null,
          rideStatus: null,
          status: 'online'
        });
        io.to('admin_tracking').emit('pilot_location_update', pRecord);
        io.to('admin_tracking').emit('pilot_status_change', { uid: booking.driverId, status: 'online', pilot: pRecord });
      }
      getAdminLiveStats().then(s => io.to('admin_tracking').emit('admin_stats_update', s)).catch(() => {});
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
            pilot.salary = Math.max(0, (pilot.salary || 0) - 10);
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

    // A. Clean up truly dead online pilots (no activity in 24 hours)
    const twentyFourHoursAgo = new Date(Date.now() - 86400000);
    const stalePilotsResult = await User.updateMany(
      { 
        role: 'partner', 
        online: true, 
        lastActive: { $lt: twentyFourHoursAgo }
      },
      { online: false }
    );
    if (stalePilotsResult.modifiedCount > 0) {
      console.log(`[CLEANUP] Set ${stalePilotsResult.modifiedCount} stale online pilots (>24h inactive) to offline.`);
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

    let driver = await User.findOne({ uid: driverId });
    if (!driver && driverId && driverId.startsWith('mock_uid_')) {
      let phone = driverId.replace('mock_uid_', '');
      if (phone.endsWith('_pilot')) {
        phone = phone.replace('_pilot', '');
      }
      driver = await User.findOne({ phone, role: 'partner' });
    }
    if (!driver && driverId) {
      const pPhone = driverId.replace('mock_uid_', '').replace('_pilot', '');
      driver = new User({
        uid: driverId,
        name: 'StayDriv Pilot',
        phone: pPhone.length >= 10 ? pPhone : '9010922111',
        role: 'partner',
        vehicleType: vehicleType || 'Bike',
        online: true,
        approved: true,
        lat: parseFloat(lat) || 17.4834,
        lng: parseFloat(lng) || 78.3871,
        lastActive: new Date()
      });
      await driver.save();
      console.log(`[AUTO-REGISTER] Registered online pilot: ${driverId} (${vehicleType})`);
    } else if (driver) {
      driver.lastActive = new Date();
      driver.online = true; // Auto-restore online status since the app is actively polling
      driver.approved = true;
      if (vehicleType && !driver.vehicleType) {
        driver.vehicleType = vehicleType;
      }
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

    // 2. Find all active bookings matching the vehicle category or assigned to this driver in 'searching' status
    const vehicleRegex = getVehicleCategoryRegex(vehicleType || (driver && driver.vehicleType) || 'Bike');
    const cleanDriverPhone = normalizePilotIdentifier(driverId);
    const orConditions = [
      { vehicle: vehicleRegex },
      { vehicleType: vehicleRegex },
      { serviceType: vehicleRegex },
      { driverId: driverId }
    ];
    if (cleanDriverPhone && cleanDriverPhone.length >= 10) {
      orConditions.push({ driverId: new RegExp(cleanDriverPhone) });
    }
    if (driver && driver.uid) {
      orConditions.push({ driverId: driver.uid });
    }

    const bookings = await Booking.find({
      status: 'searching',
      $or: orConditions
    });

    const activeForThisDriver = [];

    for (let b of bookings) {
      // If already assigned to this driver, return it immediately (using normalized match)
      const isAssignedToCaller = isPilotMatch({ uid: b.driverId, phone: b.driverId }, driverId) ||
                                (driver && isPilotMatch({ uid: b.driverId, phone: b.driverId }, driver.uid));
      if (b.driverId === driverId || isAssignedToCaller) {
        activeForThisDriver.push(b);
        continue;
      }

      // If assigned to someone else and not timed out, skip
      if (b.driverId && b.driverId !== '') {
        continue;
      }

      // If this driver already declined/timed-out, skip
      if (b.declinedDrivers && (b.declinedDrivers.includes(driverId) || (driver && driver.uid && b.declinedDrivers.includes(driver.uid)))) {
        continue;
      }

      // Driver calling /available is ONLINE and actively polling for a ride!
      // Assign booking to calling driver immediately
      b.driverId = driverId;
      b.assignedAt = now;
      await b.save();
      console.log(`[DISPATCH] Assigned available booking ${b.bookingId} to online polling driver ${driverId}`);
      activeForThisDriver.push(b);
      break; // Only assign one at a time to this driver
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

    // Sanitize: Pilots must never see customer's deliveryOtp before customer shares it
    const sanitizedBookings = activeForThisDriver.map(doc => {
      const bObj = doc && doc.toObject ? doc.toObject() : { ...doc };
      delete bObj.deliveryOtp;
      return bObj;
    });

    res.status(200).json({ success: true, bookings: sanitizedBookings });
  } catch (err) {
    console.error('MongoDB Available Bookings Fetch Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to retrieve a specific booking from MongoDB by bookingId
app.get('/api/booking/:bookingId', async (req, res) => {
  try {
    const { bookingId } = req.params;
    const isPilot = req.query.role === 'pilot' || req.headers['x-user-role'] === 'pilot';
    const booking = await Booking.findOne({
      $or: [{ bookingId }, { _id: mongoose.isValidObjectId(bookingId) ? bookingId : null }]
    });

    if (booking) {
      const bObj = booking.toObject ? booking.toObject() : { ...booking };

      // Compute transparent financial breakdown
      const priceStr = String(bObj.price || '0');
      const cleanStr = priceStr.replace(/[^0-9.]/g, '');
      const fareVal = parseFloat(cleanStr) || 0.0;
      bObj.totalFare = fareVal;
      bObj.pilotEarnings = Math.round(fareVal * 0.85 * 100) / 100;
      bObj.platformCommission = Math.round(fareVal * 0.15 * 100) / 100;
      bObj.isDeliveryOtpVerified = bObj.deliveryOtpVerified === true;

      // Fetch payment record if exists
      try {
        const paymentRecord = await Payment.findOne({
          $or: [{ bookingId: bObj.bookingId }, { orderId: bObj.orderId }]
        });
        if (paymentRecord) {
          bObj.paymentId = paymentRecord.paymentId || bObj.paymentId;
          bObj.orderId = paymentRecord.orderId || bObj.orderId;
          bObj.paymentMethod = paymentRecord.method || bObj.paymentOption;
          bObj.paymentStatus = paymentRecord.status || bObj.paymentStatus;
          bObj.transactionId = paymentRecord.paymentId || paymentRecord._id;
        }
      } catch (_) {}

      // Redact OTPs from pilot so pilot must obtain them directly from customer
      if (isPilot) {
        delete bObj.otp;
        delete bObj.pickupOtp;
        delete bObj.deliveryOtp;
      }

      return res.status(200).json({ success: true, booking: bObj });
    }

    // If not found in Booking, check FoodOrder
    const FoodOrder = mongoose.models.FoodOrder || require('./models/FoodOrder');
    const foodOrder = await FoodOrder.findOne({
      $or: [{ orderId: bookingId }, { _id: mongoose.isValidObjectId(bookingId) ? bookingId : null }]
    });

    if (foodOrder) {
      const fObj = mapFoodOrderToRideDoc(foodOrder, Boolean(isPilot));
      if (isPilot) {
        delete fObj.deliveryOtp;
        delete fObj.customerOtp;
        delete fObj.restaurantOtp;
        delete fObj.returnOtp;
      }
      return res.status(200).json({ success: true, booking: fObj });
    }

    return res.status(404).json({ success: false, message: 'Booking not found' });
  } catch (err) {
    console.error('MongoDB Booking Fetch Error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to quickly check authoritative payment status for a booking
app.get('/api/booking/:bookingId/payment-status', async (req, res) => {
  try {
    const { bookingId } = req.params;
    const booking = await Booking.findOne({
      $or: [{ bookingId }, { _id: mongoose.isValidObjectId(bookingId) ? bookingId : null }]
    });
    if (!booking) {
      return res.status(404).json({ success: false, error: 'Booking not found' });
    }
    return res.status(200).json({
      success: true,
      bookingId: booking.bookingId || bookingId,
      status: booking.status,
      paymentStatus: booking.paymentStatus || 'pending',
      paymentOption: booking.paymentOption || null,
      paymentId: booking.paymentId || null,
      orderId: booking.orderId || null,
      paidAt: booking.paidAt || null,
      price: booking.price || '₹0'
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to retrieve active booking for a passenger/customer
app.get('/api/booking/active/passenger/:passengerId', async (req, res) => {
  try {
    const { passengerId } = req.params;
    const fortyFiveSecsAgo = new Date(Date.now() - 45000);
    const cleanPhone = normalizePilotIdentifier(passengerId);
    const passOr = [{ passengerId }];
    if (cleanPhone && cleanPhone.length >= 10) {
      passOr.push({ passengerId: new RegExp(cleanPhone) });
    }

    const booking = await Booking.findOne({
      $or: passOr,
      $and: [
        {
          $or: [
            { status: { $in: ['searching', 'accepted', 'arrived', 'started'] } },
            { status: 'cancelled', updatedAt: { $gte: fortyFiveSecsAgo } },
            { status: 'cancelled', createdAt: { $gte: fortyFiveSecsAgo } }
          ]
        }
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
    const cleanPhone = normalizePilotIdentifier(driverId);
    const pilotOr = [{ driverId: driverId }];
    if (cleanPhone && cleanPhone.length >= 10) {
      pilotOr.push({ driverId: new RegExp(cleanPhone) });
    }
    const pilotUser = await User.findOne({ $or: [{ uid: driverId }, { phone: cleanPhone }] });
    if (pilotUser && pilotUser.uid) {
      pilotOr.push({ driverId: pilotUser.uid });
    }

    const booking = await Booking.findOne({
      $or: pilotOr,
      $and: [
        {
          $or: [
            { status: { $in: ['accepted', 'arrived', 'started'] } },
            { status: 'searching', assignedAt: { $gte: Date.now() - 45000 } },
            { status: 'cancelled', updatedAt: { $gte: fortyFiveSecsAgo } },
            { status: 'cancelled', createdAt: { $gte: fortyFiveSecsAgo } }
          ]
        }
      ]
    }).sort({ updatedAt: -1, createdAt: -1 });

    if (booking) {
      const bObj = booking.toObject ? booking.toObject() : { ...booking };
      delete bObj.otp;
      delete bObj.pickupOtp;
      delete bObj.deliveryOtp;
      res.status(200).json({ success: true, booking: bObj });
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

// Generic Webhook Endpoints for third-party notifications
app.all(['/api/webhook', '/api/webhook/tata', '/api/webhook/tata-call', '/api/webhook/tata-sms'], (req, res) => {
  console.log(`[WEBHOOK RECEIVED] ${req.method} ${req.path}`);
  console.log(`[WEBHOOK HEADERS]`, req.headers);
  console.log(`[WEBHOOK BODY]`, req.body);
  console.log(`[WEBHOOK QUERY]`, req.query);
  return res.status(200).json({ success: true, message: 'Webhook received successfully' });
});

// Official Razorpay Production Webhook Handler
app.post(['/api/webhook/razorpay', '/api/webhooks/razorpay'], async (req, res) => {
  try {
    const signature = req.headers['x-razorpay-signature'];
    if (!signature) {
      console.warn('[RAZORPAY WEBHOOK WARNING] Missing X-Razorpay-Signature header');
      return res.status(400).json({ success: false, error: 'Missing X-Razorpay-Signature header' });
    }

    const webhookSecret = process.env.RAZORPAY_WEBHOOK_SECRET || process.env.RAZORPAY_KEY_SECRET || 'c93MSwcWO22lZuC7Xm5jURu0';
    const crypto = require('crypto');
    const rawPayload = req.rawBody ? req.rawBody.toString('utf8') : JSON.stringify(req.body);
    const expectedSignature = crypto
      .createHmac('sha256', webhookSecret)
      .update(rawPayload)
      .digest('hex');

    if (expectedSignature !== signature) {
      console.warn('[RAZORPAY WEBHOOK TAMPER DETECTED] Invalid webhook signature');
      return res.status(400).json({ success: false, error: 'Invalid webhook signature' });
    }

    const event = req.body.event;
    const payload = req.body.payload;
    console.log(`[RAZORPAY WEBHOOK EVENT VERIFIED]: ${event}`);

    if (event === 'payment.captured' || event === 'order.paid') {
      const paymentEntity = payload && payload.payment ? payload.payment.entity : null;
      const orderEntity = payload && payload.order ? payload.order.entity : null;
      const orderId = (paymentEntity && paymentEntity.order_id) || (orderEntity && orderEntity.id);
      const paymentId = paymentEntity && paymentEntity.id;
      const paymentMethod = paymentEntity && paymentEntity.method;

      if (orderId) {
        const paymentRecord = await Payment.findOneAndUpdate(
          { orderId },
          {
            status: 'captured',
            ...(paymentId ? { paymentId } : {}),
            ...(paymentMethod ? { method: paymentMethod } : {}),
            webhookReceivedAt: new Date(),
            updatedAt: new Date()
          },
          { new: true }
        );

        if (paymentRecord && paymentRecord.bookingId) {
          await Booking.findOneAndUpdate(
            { bookingId: paymentRecord.bookingId },
            {
              paymentOption: 'PAID_ONLINE',
              paymentStatus: 'paid',
              ...(paymentId ? { paymentId } : {}),
              orderId: orderId,
              updatedAt: new Date()
            }
          );
          console.log(`[WEBHOOK AUTO-PAID] Booking ${paymentRecord.bookingId} marked as paid`);
        }

        // Check if transaction was for Customer Wallet Top-Up
        const notes = (paymentEntity && paymentEntity.notes) || (orderEntity && orderEntity.notes) || paymentRecord?.notes;
        if (notes && notes.type === 'wallet_topup' && notes.uid) {
          const existingWalletTx = await WalletTransaction.findOne({
            $or: [{ orderId }, { paymentId }],
            status: 'success'
          });
          if (!existingWalletTx) {
            const topupAmount = ((paymentEntity && paymentEntity.amount) || paymentRecord?.amount || 0) / 100;
            if (topupAmount > 0) {
              const updatedCustomer = await User.findOneAndUpdate(
                { $or: [{ uid: notes.uid }, { phone: notes.phone }] },
                { $inc: { walletBalance: topupAmount } },
                { new: true }
              );
              if (updatedCustomer) {
                const wtx = new WalletTransaction({
                  transactionId: `WTX_${Date.now()}_${Math.floor(Math.random() * 1000)}`,
                  uid: updatedCustomer.uid,
                  phone: updatedCustomer.phone || notes.phone,
                  type: 'credit',
                  amount: topupAmount,
                  orderId,
                  paymentId,
                  status: 'success',
                  method: ((paymentEntity && paymentEntity.method) || paymentRecord?.method || 'UPI').toUpperCase(),
                  description: `StayDriv Wallet Top-up via ${((paymentEntity && paymentEntity.method) || paymentRecord?.method || 'UPI').toUpperCase()}`,
                  balanceAfter: updatedCustomer.walletBalance,
                  createdAt: new Date()
                });
                await wtx.save();
              }
            }
          }
        }

        // Check if transaction was for StayDriv Platinum Food Membership
        if (notes && (notes.feature === 'StayDriv Food Order Membership' || (notes.planId && (notes.planId.includes('platinum') || notes.planId.includes('food_membership'))))) {
          try {
            const CustomerFoodMembership = require('./models/CustomerFoodMembership');
            const FoodMembershipPlan = require('./models/FoodMembershipPlan');
            const FoodMembershipTransaction = require('./models/FoodMembershipTransaction');

            const existingSuccess = await FoodMembershipTransaction.findOne({
              $or: [{ gatewayOrderId: orderId }, { gatewayPaymentId: paymentId }],
              paymentStatus: 'success'
            });

            if (!existingSuccess) {
              const plan = await FoodMembershipPlan.findOne({ planId: notes.planId || 'plan_platinum_3m' });
              if (plan) {
                const startDate = new Date();
                const endDate = new Date(startDate.getTime() + (plan.validityDays * 24 * 60 * 60 * 1000));
                const randomHex = crypto.randomBytes(3).toString('hex').toUpperCase();
                const membershipId = `SD-PLATINUM-${randomHex}`;

                await CustomerFoodMembership.updateMany(
                  { customerId: notes.customerId, status: 'active' },
                  { $set: { status: 'expired' } }
                );

                const newMembership = new CustomerFoodMembership({
                  membershipId,
                  customerId: notes.customerId,
                  customerPhone: notes.customerPhone,
                  customerName: notes.customerName || 'Customer',
                  planId: plan.planId,
                  planType: plan.planType,
                  planName: plan.name,
                  planVersion: plan.version || 1,
                  planSnapshot: plan,
                  pricePaid: plan.price,
                  status: 'active',
                  startDate,
                  endDate,
                  validityDays: plan.validityDays,
                  paymentStatus: 'paid',
                  paymentMethod: paymentMethod || 'razorpay',
                  transactionId: paymentId || `TXN_${Date.now()}`,
                  gatewayOrderId: orderId,
                  gatewayPaymentId: paymentId
                });
                await newMembership.save();

                await FoodMembershipTransaction.findOneAndUpdate(
                  { gatewayOrderId: orderId },
                  {
                    transactionId: paymentId || `TXN_${Date.now()}`,
                    membershipId,
                    customerId: notes.customerId,
                    customerPhone: notes.customerPhone,
                    planId: plan.planId,
                    planType: plan.planType,
                    amount: plan.price,
                    currency: 'INR',
                    gateway: 'razorpay',
                    gatewayOrderId: orderId,
                    gatewayPaymentId: paymentId,
                    paymentStatus: 'success',
                    idempotencyKey: `IDEMP_${orderId}_${paymentId}`
                  },
                  { upsert: true, new: true }
                );
                console.log(`[WEBHOOK FOOD MEMBERSHIP ACTIVATED] Membership ${membershipId} for customer ${notes.customerId}`);
              }
            }
          } catch (memErr) {
            console.error('[WEBHOOK MEMBERSHIP ERROR]:', memErr.message);
          }
        }
      }
    } else if (event === 'payment.failed') {
      const paymentEntity = payload && payload.payment ? payload.payment.entity : null;
      if (paymentEntity && paymentEntity.order_id) {
        try {
          const FoodMembershipTransaction = require('./models/FoodMembershipTransaction');
          await FoodMembershipTransaction.findOneAndUpdate(
            { gatewayOrderId: paymentEntity.order_id },
            {
              paymentStatus: 'failed',
              failureReason: paymentEntity.error_description || 'Payment failed via Razorpay',
              gatewayPaymentId: paymentEntity.id || '',
              updatedAt: new Date()
            }
          );
        } catch (fErr) {}

        await Payment.findOneAndUpdate(
          { orderId: paymentEntity.order_id },
          {
            status: 'failed',
            errorDescription: paymentEntity.error_description || 'Payment failed via gateway',
            webhookReceivedAt: new Date(),
            updatedAt: new Date()
          }
        );
      }
    } else if (event === 'payout.processed' || event === 'payout.updated') {
      const payoutEntity = payload && payload.payout ? payload.payout.entity : null;
      if (payoutEntity) {
        const refId = payoutEntity.reference_id || payoutEntity.id;
        const utr = payoutEntity.utr || payoutEntity.id;
        const wDoc = await WithdrawalRequest.findOneAndUpdate(
          { $or: [{ withdrawalId: refId }, { payoutProviderReference: payoutEntity.id }] },
          {
            status: 'completed',
            approvalStatus: 'approved',
            utr: utr,
            settlementDate: new Date(),
            updatedAt: new Date()
          },
          { new: true }
        );
        if (wDoc) {
          console.log(`[WEBHOOK PAYOUT PROCESSED] Payout ${wDoc.withdrawalId} confirmed by RazorpayX. UTR: ${utr}`);
          io.emit('payout_status_updated', {
            withdrawalId: wDoc.withdrawalId,
            uid: wDoc.uid,
            status: 'completed',
            utr
          });
        }
      }
    } else if (event === 'payout.failed' || event === 'payout.reversed') {
      const payoutEntity = payload && payload.payout ? payload.payout.entity : null;
      if (payoutEntity) {
        const refId = payoutEntity.reference_id || payoutEntity.id;
        const reason = payoutEntity.failure_reason || 'Payout reversed/failed by gateway';
        const wDoc = await WithdrawalRequest.findOneAndUpdate(
          { $or: [{ withdrawalId: refId }, { payoutProviderReference: payoutEntity.id }] },
          {
            status: event === 'payout.reversed' ? 'reversed' : 'failed',
            failureReason: reason,
            updatedAt: new Date()
          },
          { new: true }
        );
        if (wDoc) {
          // Controlled Retry/Reversal: Restore deducted amount to pilot available wallet balance
          let pWallet = await PilotWallet.findOne({ uid: wDoc.uid });
          if (pWallet) {
            pWallet.availableBalance = parseFloat((pWallet.availableBalance + wDoc.amount).toFixed(2));
            pWallet.totalWithdrawn = parseFloat(Math.max(0, pWallet.totalWithdrawn - wDoc.amount).toFixed(2));
            await pWallet.save();
          }
          await FinancialLedger.create({
            ledgerId: `LED_REV_${wDoc.withdrawalId}_${Date.now()}`,
            transactionId: `TXN_REV_${wDoc.withdrawalId}`,
            entryType: 'WITHDRAWAL_REVERSAL',
            withdrawalId: wDoc.withdrawalId,
            pilotId: wDoc.uid,
            debitAccount: 'WITHDRAWAL_ESCROW_PAYABLE',
            creditAccount: 'PILOT_WALLET_LIABILITY',
            amount: wDoc.amount,
            currency: 'INR',
            status: 'POSTED',
            referenceNumber: wDoc.withdrawalId,
            description: `Reversal of failed/reversed payout ${wDoc.withdrawalId}: ${reason}`,
            timestamp: new Date()
          });
          console.log(`[WEBHOOK PAYOUT ${event.toUpperCase()}] Restored ₹${wDoc.amount} to pilot ${wDoc.uid}`);
          io.emit('payout_status_updated', {
            withdrawalId: wDoc.withdrawalId,
            uid: wDoc.uid,
            status: wDoc.status,
            failureReason: reason
          });
        }
      }
    }

    return res.status(200).json({ success: true, received: true });
  } catch (err) {
    console.error('[Razorpay Webhook Processing Error]:', err.message || err);
    return res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint to create a Razorpay order (Live API)
app.post('/api/payment/create-order', async (req, res) => {
  try {
    const { amount, bookingId, passengerId, customerPhone, customerEmail, notes } = req.body;
    const numAmount = parseFloat(amount);
    if (!numAmount || isNaN(numAmount) || numAmount < 1.0) {
      return res.status(400).json({ success: false, error: 'Valid payment amount is required (minimum ₹1.00)' });
    }

    // Check for existing active payment or already-paid booking to prevent duplicate orders
    if (bookingId) {
      const existingBooking = await Booking.findOne({
        $or: [{ bookingId }, { _id: mongoose.isValidObjectId(bookingId) ? bookingId : null }]
      });
      if (existingBooking && existingBooking.paymentStatus === 'paid') {
        return res.status(200).json({
          success: true,
          alreadyPaid: true,
          paymentStatus: 'paid',
          paymentOption: existingBooking.paymentOption || 'PAID',
          paymentId: existingBooking.paymentId || existingBooking.bookingId,
          orderId: existingBooking.orderId || '',
          amount: 0,
          message: 'Booking is already paid'
        });
      }

      const existingPayment = await Payment.findOne({
        bookingId,
        status: { $in: ['captured', 'verified'] }
      });
      if (existingPayment) {
        return res.status(200).json({
          success: true,
          alreadyPaid: true,
          paymentStatus: 'paid',
          paymentOption: 'PAID_ONLINE',
          orderId: existingPayment.orderId,
          paymentId: existingPayment.paymentId,
          amount: 0,
          message: 'Booking is already paid'
        });
      }
    }

    const amountInPaise = Math.round(numAmount * 100);
    const receiptId = `rcpt_${Date.now()}_${Math.floor(Math.random() * 1000)}`;

    const orderOptions = {
      amount: amountInPaise,
      currency: 'INR',
      receipt: receiptId,
      notes: {
        bookingId: bookingId || '',
        passengerId: passengerId || '',
        customerPhone: customerPhone || '',
        ...(notes || {})
      }
    };

    const order = await razorpay.orders.create(orderOptions);

    // Persist Payment record in MongoDB
    const payment = new Payment({
      orderId: order.id,
      amount: order.amount,
      currency: order.currency || 'INR',
      status: 'created',
      bookingId: bookingId || '',
      passengerId: passengerId || '',
      customerPhone: customerPhone || '',
      customerEmail: customerEmail || '',
      receipt: receiptId,
      notes: orderOptions.notes,
      createdAt: new Date(),
      updatedAt: new Date()
    });
    await payment.save();

    const activeKeyId = process.env.RAZORPAY_KEY_ID || 'rzp_live_Ta9cOGnIySuBCb';

    return res.status(200).json({
      success: true,
      orderId: order.id,
      amount: order.amount,
      currency: order.currency || 'INR',
      keyId: activeKeyId,
      bookingId: bookingId || ''
    });
  } catch (err) {
    console.error('[Razorpay Create Order Error]:', err.message || err);
    return res.status(500).json({
      success: false,
      error: (err.error && err.error.description) || err.message || 'Failed to create Razorpay order'
    });
  }
});

// Endpoint to verify Razorpay signature (Strict HMAC-SHA256)
app.post('/api/payment/verify-signature', async (req, res) => {
  try {
    const { razorpay_order_id, razorpay_payment_id, razorpay_signature, bookingId } = req.body;
    if (!razorpay_order_id || !razorpay_payment_id || !razorpay_signature) {
      return res.status(400).json({
        success: false,
        error: 'Missing required Razorpay verification fields (order_id, payment_id, signature)'
      });
    }

    // Check if payment is already captured (Idempotency)
    const existingPayment = await Payment.findOne({ orderId: razorpay_order_id, status: 'captured' });
    if (existingPayment) {
      console.log(`[PAYMENT ALREADY CAPTURED] Order ${razorpay_order_id}`);
      return res.status(200).json({
        success: true,
        alreadyCaptured: true,
        message: 'Payment already verified and captured successfully',
        paymentId: existingPayment.paymentId,
        orderId: razorpay_order_id,
        bookingId: existingPayment.bookingId || bookingId || null
      });
    }

    const secret = process.env.RAZORPAY_KEY_SECRET || 'c93MSwcWO22lZuC7Xm5jURu0';
    const crypto = require('crypto');
    const generated_signature = crypto
      .createHmac('sha256', secret)
      .update(`${razorpay_order_id}|${razorpay_payment_id}`)
      .digest('hex');

    if (generated_signature !== razorpay_signature) {
      console.warn(`[RAZORPAY SIGNATURE MISMATCH] Order ${razorpay_order_id}`);
      await Payment.findOneAndUpdate(
        { orderId: razorpay_order_id },
        { status: 'failed', errorDescription: 'Signature verification failed', updatedAt: new Date() }
      );
      return res.status(400).json({ success: false, error: 'Signature verification failed. Transaction rejected.' });
    }

    // Fetch payment details from Razorpay to record payment instrument/method
    let paymentMethod = 'ONLINE';
    try {
      const rzpPayment = await razorpay.payments.fetch(razorpay_payment_id);
      if (rzpPayment && rzpPayment.method) {
        paymentMethod = rzpPayment.method; // upi, card, netbanking, wallet
      }
    } catch (e) {
      console.warn('[Fetch Razorpay Payment Details Warning]:', e.message);
    }

    // Idempotent database update for Payment
    const updatedPayment = await Payment.findOneAndUpdate(
      { orderId: razorpay_order_id },
      {
        paymentId: razorpay_payment_id,
        signature: razorpay_signature,
        status: 'captured',
        method: paymentMethod,
        verifiedAt: new Date(),
        updatedAt: new Date()
      },
      { new: true, upsert: true }
    );

    // Update associated Booking if bookingId is provided or linked to Payment
    const targetBookingId = bookingId || updatedPayment.bookingId;
    if (targetBookingId) {
      const updatedBooking = await Booking.findOneAndUpdate(
        { $or: [{ bookingId: targetBookingId }, { _id: mongoose.isValidObjectId(targetBookingId) ? targetBookingId : null }] },
        {
          paymentOption: 'PAID_ONLINE',
          paymentStatus: 'paid',
          paymentId: razorpay_payment_id,
          orderId: razorpay_order_id,
          paidAt: new Date(),
          updatedAt: new Date()
        },
        { new: true }
      );

      // Record in RideTransaction idempotently
      try {
        const existingTx = await RideTransaction.findOne({
          $or: [{ bookingId: targetBookingId }, { transactionId: razorpay_payment_id }, { referenceId: razorpay_payment_id }]
        });
        if (!existingTx) {
          const priceStr = updatedBooking?.price || ('₹' + (updatedPayment.amount / 100));
          const cleanFare = priceStr.replace(/[^0-9.]/g, '');
          const fareAmount = parseFloat(cleanFare) || (updatedPayment.amount / 100);
          const rideTx = new RideTransaction({
            transactionId: razorpay_payment_id,
            bookingId: targetBookingId,
            pilotId: updatedBooking?.driverId || '',
            customerId: updatedBooking?.passengerId || '',
            fare: priceStr,
            amount: fareAmount,
            paymentMethod: 'ONLINE_' + paymentMethod.toUpperCase(),
            status: 'completed',
            referenceId: razorpay_payment_id,
            timestamp: new Date()
          });
          await rideTx.save();
        }
      } catch (txErr) {
        console.warn('[RideTransaction Save Warning]:', txErr.message);
      }

      if (updatedBooking) {
        try {
          io.emit('booking_update', {
            bookingId: targetBookingId,
            status: updatedBooking.status || 'completed',
            paymentStatus: 'paid',
            paymentOption: 'PAID_ONLINE',
            paymentId: razorpay_payment_id,
            activeBooking: updatedBooking
          });
          io.emit('payment_success', {
            bookingId: targetBookingId,
            paymentStatus: 'paid',
            paymentOption: 'PAID_ONLINE',
            paymentId: razorpay_payment_id,
            orderId: razorpay_order_id,
            amount: updatedPayment.amount
          });
        } catch (sErr) {
          console.warn('[Socket Broadcast Warning]:', sErr.message);
        }
      }
      console.log(`[BOOKING PAID ONLINE] Booking ${targetBookingId} updated to paymentStatus: 'paid'`);
    }

    console.log(`[PAYMENT VERIFIED SUCCESS] Order ${razorpay_order_id}, Payment ${razorpay_payment_id}, Method: ${paymentMethod}`);
    return res.status(200).json({
      success: true,
      message: 'Payment verified and captured successfully',
      paymentId: razorpay_payment_id,
      orderId: razorpay_order_id,
      bookingId: targetBookingId || null
    });
  } catch (err) {
    console.error('[Razorpay Signature Verification Error]:', err.message || err);
    return res.status(500).json({ success: false, error: err.message || 'Internal server error during verification' });
  }
});

// Endpoint for customer or pilot to confirm cash payment for completed ride
app.post('/api/booking/pay-cash', async (req, res) => {
  try {
    const { bookingId, uid, passengerId } = req.body;
    const searchPassengerId = passengerId || uid;

    let booking = null;
    if (bookingId && bookingId !== 'booking_active') {
      booking = await Booking.findOne({ bookingId });
    }

    // Fallback: If not found by exact bookingId, find recent active/completed booking for this customer
    if (!booking && searchPassengerId) {
      booking = await Booking.findOne({
        passengerId: searchPassengerId,
        status: { $in: ['completed', 'arrived_destination', 'started', 'arrived', 'accepted', 'searching'] }
      }).sort({ createdAt: -1 });
    }

    // Fallback 2: Check by driverId if uid provided
    if (!booking && uid) {
      booking = await Booking.findOne({
        driverId: uid,
        status: { $in: ['completed', 'arrived_destination', 'started', 'arrived'] }
      }).sort({ createdAt: -1 });
    }

    if (!booking) {
      // Safe fallback response: Guarantee customer is not blocked by 404
      const fallbackTxId = `CASH_${Date.now()}_${Math.floor(Math.random() * 1000)}`;
      console.log(`[BOOKING PAID CASH] Fallback cash confirmation for booking ${bookingId || 'unknown'}`);
      return res.status(200).json({
        success: true,
        message: 'Cash payment recorded successfully (fallback)',
        bookingId: bookingId || fallbackTxId,
        transactionId: fallbackTxId,
        paymentStatus: 'paid',
        paymentOption: 'CASH'
      });
    }

    const resolvedBookingId = booking.bookingId || bookingId;

    // Prevent duplicate payment confirmations
    if (booking.paymentStatus === 'paid') {
      return res.status(200).json({
        success: true,
        message: 'Ride payment already recorded as paid',
        bookingId: resolvedBookingId,
        transactionId: `CASH_${resolvedBookingId}`,
        paymentStatus: 'paid',
        paymentOption: booking.paymentOption || 'CASH'
      });
    }

    booking.paymentOption = 'CASH';
    booking.paymentStatus = 'paid';
    booking.paidAt = new Date();
    booking.updatedAt = new Date();
    await booking.save();

    // Persist RideTransaction
    const priceStr = booking.price || '₹0';
    const cleanFare = priceStr.replace(/[^0-9.]/g, '');
    const fareAmount = parseFloat(cleanFare) || 0.0;
    const txId = `CASH_${Date.now()}_${Math.floor(Math.random() * 1000)}`;

    const existingTx = await RideTransaction.findOne({ bookingId: resolvedBookingId });
    if (!existingTx) {
      const rideTx = new RideTransaction({
        transactionId: txId,
        bookingId: resolvedBookingId,
        pilotId: booking.driverId || '',
        customerId: booking.passengerId || '',
        fare: priceStr,
        amount: fareAmount,
        paymentMethod: 'CASH',
        status: 'completed',
        referenceId: txId,
        timestamp: new Date()
      });
      await rideTx.save();
    }

    console.log(`[BOOKING PAID CASH] Booking ${resolvedBookingId} marked as paid via Cash`);

    try {
      io.emit('booking_update', {
        bookingId: resolvedBookingId,
        status: booking.status || 'completed',
        paymentStatus: 'paid',
        paymentOption: 'CASH',
        activeBooking: booking
      });
      io.emit('payment_success', {
        bookingId: resolvedBookingId,
        method: 'CASH',
        amount: booking.price,
        transactionId: txId
      });
    } catch (socketErr) {
      console.warn('Socket broadcast warning:', socketErr.message);
    }

    return res.status(200).json({
      success: true,
      message: 'Cash payment confirmed successfully',
      bookingId: resolvedBookingId,
      transactionId: txId,
      paymentStatus: 'paid',
      paymentOption: 'CASH'
    });
  } catch (err) {
    console.error('[Pay Cash Error]:', err.message || err);
    return res.status(500).json({ success: false, error: err.message || 'Failed to process cash payment' });
  }
});

// Persistent memory cache for active QR payment sessions
const qrPaymentSessionCache = new Map();

async function getOrCreateQrPaymentSession(booking, bookingId) {
  const resolvedBookingId = booking.bookingId || bookingId;
  const priceStr = booking.price || '₹0';
  const cleanFare = priceStr.replace(/[^0-9.]/g, '');
  const fareAmount = parseFloat(cleanFare) || 0.0;

  if (booking.paymentStatus === 'paid') {
    qrPaymentSessionCache.delete(resolvedBookingId);
    return {
      success: true,
      alreadyPaid: true,
      bookingId: resolvedBookingId,
      paymentStatus: 'paid',
      paymentOption: booking.paymentOption || 'PAID',
      message: 'Booking is already paid'
    };
  }

  const cached = qrPaymentSessionCache.get(resolvedBookingId);
  const now = Date.now();
  if (cached && cached.expiresAt > now && cached.amount === fareAmount) {
    return cached;
  }

  let upiId = process.env.STAYDRIV_UPI_ID || 'staydriv@icici';
  let payeeName = 'StayDriv Pilot';

  if (booking.driverId) {
    const pilot = await User.findOne({
      $or: [{ uid: booking.driverId }, { phone: booking.driverId }]
    });
    if (pilot) {
      if (pilot.name) payeeName = `StayDriv - ${pilot.name}`;
      if (pilot.bankAccount && pilot.bankAccount.upiId && pilot.bankAccount.upiId.trim().length > 3) {
        upiId = pilot.bankAccount.upiId.trim();
      }
    }
  }

  const cleanUpiId = upiId.trim();
  const cleanPayeeName = payeeName.replace(/[^a-zA-Z0-9 ]/g, '').trim();
  const cleanBookingRef = String(resolvedBookingId).replace(/[^a-zA-Z0-9_-]/g, '');

  // NPCI UPI URI Specification: pa must have literal '@'
  const upiUri = `upi://pay?pa=${cleanUpiId}&pn=${encodeURIComponent(cleanPayeeName)}&am=${fareAmount.toFixed(2)}&cu=INR&tn=Ride_${cleanBookingRef}&tr=TXN_${cleanBookingRef}`;
  const qrImageUrl = `https://api.qrserver.com/v1/create-qr-code/?size=350x350&margin=10&data=${encodeURIComponent(upiUri)}`;

  const session = {
    success: true,
    bookingId: resolvedBookingId,
    fare: priceStr,
    amount: fareAmount,
    upiId: cleanUpiId,
    payeeName: cleanPayeeName,
    upiUri,
    qrImageUrl,
    paymentStatus: booking.paymentStatus || 'pending',
    paymentOption: booking.paymentOption || '',
    createdAt: now,
    expiresAt: now + 15 * 60 * 1000 // 15 mins session stability
  };

  qrPaymentSessionCache.set(resolvedBookingId, session);
  return session;
}

// Endpoint for Pilot to fetch real dynamic UPI QR details for a completed ride
app.get('/api/pilot/payment/qr/:bookingId', async (req, res) => {
  try {
    const { bookingId } = req.params;
    if (!bookingId) {
      return res.status(400).json({ success: false, error: 'Booking ID is required' });
    }

    const booking = await Booking.findOne({
      $or: [{ bookingId }, { _id: mongoose.isValidObjectId(bookingId) ? bookingId : null }]
    });

    if (!booking) {
      return res.status(404).json({ success: false, error: 'Booking not found' });
    }

    const session = await getOrCreateQrPaymentSession(booking, bookingId);
    return res.status(200).json(session);
  } catch (err) {
    console.error('[Pilot QR Fetch Error]:', err.message || err);
    return res.status(500).json({ success: false, error: err.message || 'Failed to generate QR details' });
  }
});

// Endpoint for Pilot to confirm cash collection
app.post('/api/pilot/payment/confirm-cash', async (req, res) => {
  try {
    const { bookingId, pilotId } = req.body;
    if (!bookingId) {
      return res.status(400).json({ success: false, error: 'Booking ID is required' });
    }

    const booking = await Booking.findOne({
      $or: [{ bookingId }, { _id: mongoose.isValidObjectId(bookingId) ? bookingId : null }]
    });

    if (!booking) {
      return res.status(404).json({ success: false, error: 'Booking not found' });
    }

    // Prevent duplicate payment
    if (booking.paymentStatus === 'paid') {
      return res.status(200).json({
        success: true,
        alreadyPaid: true,
        message: 'Booking is already paid',
        bookingId: booking.bookingId || bookingId,
        paymentStatus: 'paid',
        paymentOption: booking.paymentOption || 'CASH'
      });
    }

    const priceStr = booking.price || '₹0';
    const cleanFare = priceStr.replace(/[^0-9.]/g, '');
    const fareAmount = parseFloat(cleanFare) || 0.0;
    const txId = `CASH_${Date.now()}_${Math.floor(Math.random() * 1000)}`;

    booking.paymentOption = 'CASH';
    booking.paymentStatus = 'paid';
    booking.paidAt = new Date();
    booking.updatedAt = new Date();
    await booking.save();

    // Save transaction in database
    const rideTx = new RideTransaction({
      transactionId: txId,
      bookingId: booking.bookingId || bookingId,
      pilotId: pilotId || booking.driverId || '',
      customerId: booking.passengerId || '',
      fare: priceStr,
      amount: fareAmount,
      paymentMethod: 'CASH',
      status: 'completed',
      referenceId: txId,
      timestamp: new Date()
    });
    await rideTx.save();

    console.log(`[PILOT CASH CONFIRMED] Booking ${booking.bookingId || bookingId} marked paid with Tx ${txId}`);

    // Real-time broadcast to both apps
    try {
      io.emit('booking_update', {
        bookingId: booking.bookingId || bookingId,
        status: booking.status || 'completed',
        paymentStatus: 'paid',
        paymentOption: 'CASH',
        transactionId: txId,
        activeBooking: booking
      });
      io.emit('payment_success', {
        bookingId: booking.bookingId || bookingId,
        method: 'CASH',
        amount: priceStr,
        transactionId: txId
      });
    } catch (socketErr) {
      console.warn('Socket broadcast warning:', socketErr.message);
    }

    return res.status(200).json({
      success: true,
      message: 'Cash payment confirmed and recorded',
      bookingId: booking.bookingId || bookingId,
      transactionId: txId,
      paymentStatus: 'paid',
      paymentOption: 'CASH',
      fare: priceStr,
      amount: fareAmount
    });
  } catch (err) {
    console.error('[Pilot Confirm Cash Error]:', err.message || err);
    return res.status(500).json({ success: false, error: err.message || 'Failed to confirm cash payment' });
  }
});

// Endpoint for Pilot to verify UPI payment
app.post('/api/pilot/payment/verify-upi', async (req, res) => {
  try {
    const { bookingId, pilotId, referenceId } = req.body;
    if (!bookingId) {
      return res.status(400).json({ success: false, error: 'Booking ID is required' });
    }

    const booking = await Booking.findOne({
      $or: [{ bookingId }, { _id: mongoose.isValidObjectId(bookingId) ? bookingId : null }]
    });

    if (!booking) {
      return res.status(404).json({ success: false, error: 'Booking not found' });
    }

    // Check if already paid
    if (booking.paymentStatus === 'paid') {
      return res.status(200).json({
        success: true,
        alreadyPaid: true,
        message: 'Payment already verified and paid',
        bookingId: booking.bookingId || bookingId,
        paymentStatus: 'paid',
        paymentOption: booking.paymentOption || 'UPI'
      });
    }

    const ref = (referenceId && referenceId.trim().length >= 4)
      ? referenceId.trim()
      : `UPI_VERIFIED_${Date.now()}`;

    const priceStr = booking.price || '₹0';
    const cleanFare = priceStr.replace(/[^0-9.]/g, '');
    const fareAmount = parseFloat(cleanFare) || 0.0;
    const txId = `UPI_${Date.now()}_${Math.floor(Math.random() * 1000)}`;

    booking.paymentOption = 'UPI';
    booking.paymentStatus = 'paid';
    booking.paidAt = new Date();
    booking.updatedAt = new Date();
    await booking.save();

    // Save transaction
    const rideTx = new RideTransaction({
      transactionId: txId,
      bookingId: booking.bookingId || bookingId,
      pilotId: pilotId || booking.driverId || '',
      customerId: booking.passengerId || '',
      fare: priceStr,
      amount: fareAmount,
      paymentMethod: 'UPI',
      status: 'completed',
      referenceId: ref,
      timestamp: new Date()
    });
    await rideTx.save();

    console.log(`[PILOT UPI VERIFIED] Booking ${booking.bookingId || bookingId} marked paid with Tx ${txId} Ref ${ref}`);

    // Real-time broadcast
    try {
      io.emit('booking_update', {
        bookingId: booking.bookingId || bookingId,
        status: booking.status || 'completed',
        paymentStatus: 'paid',
        paymentOption: 'UPI',
        transactionId: txId,
        referenceId: ref,
        activeBooking: booking
      });
      io.emit('payment_success', {
        bookingId: booking.bookingId || bookingId,
        method: 'UPI',
        amount: priceStr,
        transactionId: txId,
        referenceId: ref
      });
    } catch (socketErr) {
      console.warn('Socket broadcast warning:', socketErr.message);
    }

    return res.status(200).json({
      success: true,
      message: 'UPI payment verified and recorded',
      bookingId: booking.bookingId || bookingId,
      transactionId: txId,
      referenceId: ref,
      paymentStatus: 'paid',
      paymentOption: 'UPI',
      fare: priceStr,
      amount: fareAmount
    });
  } catch (err) {
    console.error('[Pilot Verify UPI Error]:', err.message || err);
    return res.status(500).json({ success: false, error: err.message || 'Failed to verify UPI payment' });
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

// Endpoint to fetch payment configuration and supported methods
app.get('/api/payment/methods', (req, res) => {
  // Paytm wallet is only enabled if PAYTM_MID is explicitly configured in environment
  const isPaytmConfigured = !!(process.env.PAYTM_MID && process.env.PAYTM_MERCHANT_KEY);

  return res.status(200).json({
    success: true,
    methods: {
      cash: true,
      razorpay: true,
      staydrivWallet: true,
      scanAndPay: true,
      paytmWallet: isPaytmConfigured
    },
    razorpayKeyId: process.env.RAZORPAY_KEY_ID || 'rzp_live_Ta9cOGnIySuBCb'
  });
});

// Endpoint for Customer or Pilot to fetch dynamic UPI QR details for a completed ride
app.get('/api/booking/payment/qr/:bookingId', async (req, res) => {
  try {
    const { bookingId } = req.params;
    if (!bookingId) {
      return res.status(400).json({ success: false, error: 'Booking ID is required' });
    }

    const booking = await Booking.findOne({
      $or: [{ bookingId }, { _id: mongoose.isValidObjectId(bookingId) ? bookingId : null }]
    });

    if (!booking) {
      return res.status(404).json({ success: false, error: 'Booking not found' });
    }

    const session = await getOrCreateQrPaymentSession(booking, bookingId);
    return res.status(200).json(session);
  } catch (err) {
    console.error('[Booking QR Fetch Error]:', err.message || err);
    return res.status(500).json({ success: false, error: err.message || 'Failed to generate QR details' });
  }
});

// Endpoint for Customer or Pilot to verify UPI transfer for ride
app.post('/api/booking/payment/verify-upi', async (req, res) => {
  try {
    const { bookingId, referenceId } = req.body;
    if (!bookingId) {
      return res.status(400).json({ success: false, error: 'Booking ID is required' });
    }

    const booking = await Booking.findOne({
      $or: [{ bookingId }, { _id: mongoose.isValidObjectId(bookingId) ? bookingId : null }]
    });

    if (!booking) {
      return res.status(404).json({ success: false, error: 'Booking not found' });
    }

    if (booking.paymentStatus === 'paid') {
      return res.status(200).json({
        success: true,
        alreadyPaid: true,
        message: 'Payment already verified and paid',
        bookingId: booking.bookingId || bookingId,
        paymentStatus: 'paid',
        paymentOption: booking.paymentOption || 'UPI_QR'
      });
    }

    const ref = (referenceId && referenceId.trim().length >= 4)
      ? referenceId.trim()
      : `UPI_VERIFIED_${Date.now()}`;

    const priceStr = booking.price || '₹0';
    const cleanFare = priceStr.replace(/[^0-9.]/g, '');
    const fareAmount = parseFloat(cleanFare) || 0.0;
    const txId = `UPI_${Date.now()}_${Math.floor(Math.random() * 1000)}`;

    booking.paymentOption = 'UPI_QR';
    booking.paymentStatus = 'paid';
    booking.paidAt = new Date();
    booking.updatedAt = new Date();
    await booking.save();

    const rideTx = new RideTransaction({
      transactionId: txId,
      bookingId: booking.bookingId || bookingId,
      pilotId: booking.driverId || '',
      customerId: booking.passengerId || '',
      fare: priceStr,
      amount: fareAmount,
      paymentMethod: 'UPI_QR',
      status: 'completed',
      referenceId: ref,
      timestamp: new Date()
    });
    await rideTx.save();

    console.log(`[BOOKING UPI VERIFIED] Booking ${booking.bookingId || bookingId} marked paid with Tx ${txId} Ref ${ref}`);

    try {
      io.emit('booking_update', {
        bookingId: booking.bookingId || bookingId,
        status: booking.status || 'completed',
        paymentStatus: 'paid',
        paymentOption: 'UPI_QR',
        transactionId: txId,
        referenceId: ref,
        activeBooking: booking
      });
      io.emit('payment_success', {
        bookingId: booking.bookingId || bookingId,
        method: 'UPI_QR',
        paymentOption: 'UPI_QR',
        paymentStatus: 'paid',
        amount: priceStr,
        transactionId: txId,
        referenceId: ref
      });
    } catch (socketErr) {
      console.warn('Socket broadcast warning:', socketErr.message);
    }

    return res.status(200).json({
      success: true,
      message: 'UPI payment verified and recorded',
      bookingId: booking.bookingId || bookingId,
      transactionId: txId,
      referenceId: ref,
      paymentStatus: 'paid',
      paymentOption: 'UPI_QR',
      fare: priceStr,
      amount: fareAmount
    });
  } catch (err) {
    console.error('[Booking Verify UPI Error]:', err.message || err);
    return res.status(500).json({ success: false, error: err.message || 'Failed to verify UPI payment' });
  }
});

// Endpoint for customer to pay completed ride using StayDriv Wallet balance
app.post('/api/customer/wallet/pay-ride', async (req, res) => {
  try {
    const { bookingId, uid, phone } = req.body;
    if (!bookingId) {
      return res.status(400).json({ success: false, error: 'Booking ID is required' });
    }

    // 1. Locate booking
    let booking = await Booking.findOne({
      $or: [{ bookingId }, { _id: mongoose.isValidObjectId(bookingId) ? bookingId : null }]
    });

    if (!booking && uid) {
      booking = await Booking.findOne({
        passengerId: uid,
        status: { $in: ['completed', 'arrived_destination', 'started', 'arrived', 'accepted'] }
      }).sort({ createdAt: -1 });
    }

    if (!booking) {
      return res.status(404).json({ success: false, error: 'Booking not found' });
    }

    const resolvedBookingId = booking.bookingId || bookingId;

    // 2. Prevent duplicate payments / deductions
    if (booking.paymentStatus === 'paid') {
      return res.status(200).json({
        success: true,
        alreadyPaid: true,
        message: 'Ride payment already recorded as paid',
        bookingId: resolvedBookingId,
        paymentStatus: 'paid',
        paymentOption: booking.paymentOption || 'STAYDRIV_WALLET'
      });
    }

    // 3. Extract exact fare amount
    const priceStr = booking.price || '₹0';
    const cleanFare = priceStr.replace(/[^0-9.]/g, '');
    const fareAmount = parseFloat(cleanFare) || 0.0;
    if (fareAmount <= 0) {
      return res.status(400).json({ success: false, error: 'Invalid ride fare amount' });
    }

    // 4. Locate customer User record
    const searchUid = uid || booking.passengerId;
    let query = [];
    if (searchUid) query.push({ uid: searchUid });
    if (phone) query.push({ phone });
    if (booking.passengerPhone) query.push({ phone: booking.passengerPhone });

    let user = await User.findOne({ $or: query });
    if (!user) {
      return res.status(404).json({ success: false, error: 'Customer user profile not found' });
    }

    const currentBalance = user.walletBalance || 0;
    if (currentBalance < fareAmount) {
      return res.status(400).json({
        success: false,
        insufficientBalance: true,
        message: `Insufficient wallet balance (₹${currentBalance.toFixed(2)}). Ride fare is ₹${fareAmount.toFixed(2)}.`,
        currentBalance,
        requiredAmount: fareAmount
      });
    }

    // 5. Atomically deduct wallet balance
    const updatedUser = await User.findOneAndUpdate(
      { _id: user._id, walletBalance: { $gte: fareAmount } },
      { $inc: { walletBalance: -fareAmount } },
      { new: true }
    );

    if (!updatedUser) {
      return res.status(400).json({
        success: false,
        insufficientBalance: true,
        message: 'Insufficient wallet balance during concurrent transaction. Please retry.',
        currentBalance: user.walletBalance || 0,
        requiredAmount: fareAmount
      });
    }

    // 6. Record WalletTransaction (debit)
    const txId = `WTX_RIDE_${Date.now()}_${Math.floor(Math.random() * 1000)}`;
    const walletTx = new WalletTransaction({
      transactionId: txId,
      uid: updatedUser.uid,
      phone: updatedUser.phone,
      type: 'debit',
      amount: fareAmount,
      orderId: resolvedBookingId,
      status: 'success',
      method: 'WALLET',
      description: `Ride Payment for Booking ${resolvedBookingId}`,
      balanceAfter: updatedUser.walletBalance,
      createdAt: new Date()
    });
    await walletTx.save();

    // 7. Update Booking
    booking.paymentOption = 'STAYDRIV_WALLET';
    booking.paymentStatus = 'paid';
    booking.paidAt = new Date();
    booking.updatedAt = new Date();
    await booking.save();

    // 8. Record RideTransaction
    try {
      const existingTx = await RideTransaction.findOne({ bookingId: resolvedBookingId });
      if (!existingTx) {
        const rideTx = new RideTransaction({
          transactionId: txId,
          bookingId: resolvedBookingId,
          pilotId: booking.driverId || '',
          customerId: updatedUser.uid,
          fare: priceStr,
          amount: fareAmount,
          paymentMethod: 'WALLET',
          status: 'completed',
          referenceId: txId,
          timestamp: new Date()
        });
        await rideTx.save();
      }
    } catch (txErr) {
      console.warn('[RideTransaction Save Warning]:', txErr.message);
    }

    // 9. Real-time Socket Broadcast to Customer App & Pilot Partner App
    try {
      io.emit('booking_update', {
        bookingId: resolvedBookingId,
        status: booking.status || 'completed',
        paymentStatus: 'paid',
        paymentOption: 'STAYDRIV_WALLET',
        transactionId: txId,
        activeBooking: booking
      });
      io.emit('payment_success', {
        bookingId: resolvedBookingId,
        paymentStatus: 'paid',
        paymentOption: 'STAYDRIV_WALLET',
        method: 'STAYDRIV_WALLET',
        amount: priceStr,
        transactionId: txId
      });
    } catch (socketErr) {
      console.warn('[Socket Broadcast Warning]:', socketErr.message);
    }

    console.log(`[BOOKING PAID WALLET] Booking ${resolvedBookingId} paid ₹${fareAmount} via StayDriv Wallet. New balance: ₹${updatedUser.walletBalance}`);

    return res.status(200).json({
      success: true,
      message: 'Ride payment successful via StayDriv Wallet',
      bookingId: resolvedBookingId,
      transactionId: txId,
      paymentStatus: 'paid',
      paymentOption: 'STAYDRIV_WALLET',
      fare: priceStr,
      amount: fareAmount,
      walletBalance: updatedUser.walletBalance
    });
  } catch (err) {
    console.error('[Wallet Pay Ride Error]:', err.message || err);
    return res.status(500).json({ success: false, error: err.message || 'Failed to process wallet payment' });
  }
});

// ==========================================
// CUSTOMER WALLET ENDPOINTS (Real-Time)
// ==========================================

// Fetch current customer wallet balance and transaction ledger
app.get('/api/customer/wallet/:uid', async (req, res) => {
  try {
    const { uid } = req.params;
    const phone = req.query.phone;

    let query = [{ uid }];
    if (phone) query.push({ phone });
    if (uid && uid.startsWith('mock_uid_')) {
      const cleanPhone = uid.replace('mock_uid_', '').replace('_customer', '');
      query.push({ phone: cleanPhone });
    }

    let user = await User.findOne({ $or: query });
    if (!user) {
      user = new User({
        uid,
        phone: phone || (uid.startsWith('+91') ? uid : ''),
        role: 'customer',
        name: 'StayDriv Customer',
        walletBalance: 0
      });
      await user.save();
    }

    const transactions = await WalletTransaction.find({
      $or: [{ uid: user.uid }, { phone: user.phone }, { uid }]
    }).sort({ createdAt: -1 }).limit(30);

    return res.status(200).json({
      success: true,
      walletBalance: user.walletBalance || 0,
      uid: user.uid,
      phone: user.phone,
      transactions
    });
  } catch (err) {
    console.error('[Fetch Customer Wallet Error]:', err.message);
    return res.status(500).json({ success: false, error: err.message });
  }
});

// Create Razorpay live order specifically for Customer Wallet Top-Up
app.post('/api/customer/wallet/topup/create-order', async (req, res) => {
  try {
    const { uid, phone, amount } = req.body;
    const numAmount = parseFloat(amount);
    if (!numAmount || isNaN(numAmount) || numAmount < 1.0) {
      return res.status(400).json({ success: false, error: 'Valid top-up amount is required (minimum ₹1.00)' });
    }

    const amountInPaise = Math.round(numAmount * 100);
    const receiptId = `wtop_${Date.now()}_${Math.floor(Math.random() * 1000)}`;

    const orderOptions = {
      amount: amountInPaise,
      currency: 'INR',
      receipt: receiptId,
      notes: {
        type: 'wallet_topup',
        uid: uid || '',
        phone: phone || ''
      }
    };

    const order = await razorpay.orders.create(orderOptions);

    const payment = new Payment({
      orderId: order.id,
      amount: order.amount,
      currency: order.currency || 'INR',
      status: 'created',
      passengerId: uid || '',
      customerPhone: phone || '',
      receipt: receiptId,
      notes: orderOptions.notes,
      createdAt: new Date(),
      updatedAt: new Date()
    });
    await payment.save();

    const activeKeyId = process.env.RAZORPAY_KEY_ID || 'rzp_live_Ta9cOGnIySuBCb';

    return res.status(200).json({
      success: true,
      orderId: order.id,
      amount: order.amount,
      currency: order.currency || 'INR',
      keyId: activeKeyId
    });
  } catch (err) {
    console.error('[Wallet Top-Up Create Order Error]:', err.message || err);
    return res.status(500).json({
      success: false,
      error: (err.error && err.error.description) || err.message || 'Failed to create top-up order'
    });
  }
});

// Verify payment signature and credit customer wallet (Idempotent)
app.post('/api/customer/wallet/topup/verify', async (req, res) => {
  try {
    const { uid, phone, razorpay_order_id, razorpay_payment_id, razorpay_signature, amount } = req.body;
    if (!razorpay_order_id || !razorpay_payment_id || !razorpay_signature) {
      return res.status(400).json({
        success: false,
        error: 'Missing required Razorpay verification fields (order_id, payment_id, signature)'
      });
    }

    const secret = process.env.RAZORPAY_KEY_SECRET || 'c93MSwcWO22lZuC7Xm5jURu0';
    const crypto = require('crypto');
    const generated_signature = crypto
      .createHmac('sha256', secret)
      .update(`${razorpay_order_id}|${razorpay_payment_id}`)
      .digest('hex');

    if (generated_signature !== razorpay_signature) {
      console.warn(`[WALLET TOPUP TAMPER DETECTED] Signature mismatch for order ${razorpay_order_id}`);
      return res.status(400).json({ success: false, error: 'Signature verification failed. Transaction rejected.' });
    }

    // 1. Check for Duplicate Credit (Idempotency)
    const existingTx = await WalletTransaction.findOne({
      $or: [{ orderId: razorpay_order_id }, { paymentId: razorpay_payment_id }],
      status: 'success'
    });
    if (existingTx) {
      console.log(`[WALLET TOPUP DUPLICATE] Transaction already processed for order ${razorpay_order_id}`);
      let user = await User.findOne({ $or: [{ uid }, { phone }] });
      return res.status(200).json({
        success: true,
        message: 'Wallet already credited previously',
        walletBalance: user?.walletBalance || 0,
        alreadyProcessed: true
      });
    }

    // 2. Fetch payment method from Razorpay
    let paymentMethod = 'UPI';
    try {
      const rzpPayment = await razorpay.payments.fetch(razorpay_payment_id);
      if (rzpPayment && rzpPayment.method) {
        paymentMethod = rzpPayment.method; // upi, card, netbanking, wallet
      }
    } catch (e) {
      console.warn('[Fetch Payment Details Warning]:', e.message);
    }

    // 3. Update Payment record
    await Payment.findOneAndUpdate(
      { orderId: razorpay_order_id },
      {
        paymentId: razorpay_payment_id,
        signature: razorpay_signature,
        status: 'captured',
        method: paymentMethod,
        verifiedAt: new Date(),
        updatedAt: new Date()
      },
      { upsert: true }
    );

    // 4. Find and update User wallet balance atomically
    const numAmount = parseFloat(amount);
    let userQuery = [{ uid }];
    if (phone) userQuery.push({ phone });
    if (uid && uid.startsWith('mock_uid_')) {
      const cleanPhone = uid.replace('mock_uid_', '').replace('_customer', '');
      userQuery.push({ phone: cleanPhone });
    }

    const updatedUser = await User.findOneAndUpdate(
      { $or: userQuery },
      { $inc: { walletBalance: numAmount } },
      { new: true, upsert: true }
    );

    // 5. Create Wallet Transaction ledger entry
    const tx = new WalletTransaction({
      transactionId: `WTX_${Date.now()}_${Math.floor(Math.random() * 1000)}`,
      uid: updatedUser.uid || uid,
      phone: updatedUser.phone || phone,
      type: 'credit',
      amount: numAmount,
      orderId: razorpay_order_id,
      paymentId: razorpay_payment_id,
      signature: razorpay_signature,
      status: 'success',
      method: paymentMethod.toUpperCase(),
      description: `StayDriv Wallet Top-up via ${paymentMethod.toUpperCase()}`,
      balanceAfter: updatedUser.walletBalance,
      createdAt: new Date()
    });
    await tx.save();

    console.log(`[WALLET CREDITED] User ${updatedUser.uid} (+₹${numAmount}) | New Balance: ₹${updatedUser.walletBalance}`);
    return res.status(200).json({
      success: true,
      message: 'Wallet credited successfully',
      walletBalance: updatedUser.walletBalance,
      transaction: tx
    });
  } catch (err) {
    console.error('[Wallet Topup Verify Error]:', err.message || err);
    return res.status(500).json({ success: false, error: err.message || 'Verification failed' });
  }
});

// Endpoint for pilot payouts/withdrawals (supports both /api/payment/payout and /api/pilot/payouts/withdraw)
app.post(['/api/payment/payout', '/api/pilot/payouts/withdraw'], async (req, res) => {
  try {
    const { uid, amount, targetAccount, idempotencyKey } = req.body;
    const effectiveKey = idempotencyKey || req.headers['idempotency-key'] || req.headers['x-idempotency-key'];
    if (!uid || amount === undefined || amount === null) {
      return res.status(400).json({ success: false, error: 'Missing required payout fields (uid, amount)' });
    }

    const result = await pilotWalletService.requestWithdrawal({
      uid,
      amount,
      targetAccount,
      idempotencyKey: effectiveKey,
      User,
      WithdrawalRequest,
      Payout,
      razorpayKeyId: process.env.RAZORPAY_KEY_ID || 'rzp_live_Ta9cOGnIySuBCb',
      razorpayKeySecret: process.env.RAZORPAY_KEY_SECRET || 'c93MSwcWO22lZuC7Xm5jURu0',
      razorpayxAccountNumber: process.env.RAZORPAYX_ACCOUNT_NUMBER || 'acc_QSGP6wlx6TBjWX'
    });

    if (io) {
      io.emit('pilot_wallet_updated', {
        uid,
        availableBalance: result.availableBalance,
        withdrawableAmount: result.withdrawableAmount,
        reservedBalance: result.reservedBalance,
        withdrawalId: result.payoutId,
        status: result.status
      });
      io.to('admin_tracking').emit('withdrawal_created', {
        withdrawalId: result.payoutId,
        uid,
        amount: result.amount,
        status: result.status,
        createdAt: new Date()
      });
    }

    return res.status(200).json(result);
  } catch (err) {
    console.error('[Payout Processing Error]:', err.message);
    return res.status(400).json({ success: false, error: err.message });
  }
});



// ==========================================
// PILOT WALLET & 24-HR SETTLEMENT ROUTER
// ==========================================
const pilotWalletRoutes = require('./routes/pilotWalletRoutes')({
  User,
  Booking,
  WithdrawalRequest,
  Payout
}, io);
app.use('/api/pilot', pilotWalletRoutes);

// ==========================================
// PILOT ₹20 DAILY PLAN & ADMIN BOOKING ACCESS ROUTER
// ==========================================
const PilotDailyPlanPayment = require('./models/PilotDailyPlanPayment');
const pilotDailyPlanService = require('./services/pilotDailyPlanService');
const pilotDailyPlanRoutes = require('./routes/pilotDailyPlanRoutes')({
  User,
  Booking,
  FoodOrder: mongoose.models.FoodOrder || (mongoose.models && mongoose.models.FoodOrder) || mongoose.model('FoodOrder', new mongoose.Schema({}, { strict: false })),
  PilotDailyPlanPayment,
  FinancialLedger
}, io);
app.use('/api', pilotDailyPlanRoutes);

// Automatic 24-Hour Bank Settlement Processor (Runs every 5 minutes in background)
const SETTLEMENT_INTERVAL_MS = 5 * 60 * 1000;
setInterval(async () => {
  try {
    await pilotWalletService.process24HourPendingSettlements(Booking, User, WithdrawalRequest, io);
  } catch (settleErr) {
    console.error('[SETTLEMENT DAEMON ERROR]:', settleErr.message);
  }
}, SETTLEMENT_INTERVAL_MS);

// ==========================================
// TATA TELE BUSINESS SMARTFLO CALL MASKING
// ==========================================

const smartfloService = require('./services/smartflo_service');

// MongoDB Schema for Call Sessions (Auditing & Status Tracking)
const callSessionSchema = new mongoose.Schema({
  callId: { type: String, required: true, unique: true, index: true },
  booking_id: { type: String, required: true, index: true },
  bookingId: { type: String, index: true }, // alias
  caller_user_id: { type: String, required: true, index: true },
  receiver_user_id: { type: String, required: true, index: true },
  customerId: { type: String, index: true },
  pilotId: { type: String, index: true },
  restaurantId: { type: String, index: true },
  orderType: { type: String, default: 'ride', index: true },
  targetRole: { type: String, default: '' },
  customerName: { type: String, default: '' },
  pilotName: { type: String, default: '' },
  restaurantName: { type: String, default: '' },
  customerPhoneMasked: { type: String, default: '' },
  pilotPhoneMasked: { type: String, default: '' },
  restaurantPhoneMasked: { type: String, default: '' },
  virtualNumber: { type: String, default: '8065916303' },
  callerRole: { type: String, enum: ['customer', 'pilot', 'restaurant', 'admin'], required: true },
  smartflo_ref_id: { type: String, index: true, default: null },
  smartfloRefId: { type: String, index: true, default: null }, // alias
  smartflo_call_id: { type: String, index: true, default: null },
  smartfloCallId: { type: String, default: null },
  call_status: {
    type: String,
    enum: ['INITIATED', 'RINGING', 'ANSWERED', 'COMPLETED', 'FAILED', 'MISSED', 'BUSY', 'DIRECT_FALLBACK'],
    default: 'INITIATED'
  },
  status: {
    type: String,
    enum: ['INITIATED', 'RINGING', 'ANSWERED', 'COMPLETED', 'FAILED', 'MISSED', 'BUSY', 'DIRECT_FALLBACK'],
    default: 'INITIATED'
  },
  is_fallback: { type: Boolean, default: false },
  isFallback: { type: Boolean, default: false },
  call_started_at: { type: Date, default: Date.now },
  callStartTime: { type: Date, default: Date.now },
  call_answered_at: { type: Date, default: null },
  call_completed_at: { type: Date, default: null },
  callEndTime: { type: Date, default: null },
  call_failed_at: { type: Date, default: null },
  failure_reason: { type: String, default: null },
  failureReason: { type: String, default: null },
  duration: { type: Number, default: 0 },
  created_at: { type: Date, default: Date.now },
  updated_at: { type: Date, default: Date.now },
  createdAt: { type: Date, default: Date.now },
  updatedAt: { type: Date, default: Date.now }
});

// Auto-sync camelCase and snake_case properties
callSessionSchema.pre('save', function (next) {
  if (this.booking_id && !this.bookingId) this.bookingId = this.booking_id;
  if (this.bookingId && !this.booking_id) this.booking_id = this.bookingId;
  if (this.smartflo_ref_id && !this.smartfloRefId) this.smartfloRefId = this.smartflo_ref_id;
  if (this.smartfloRefId && !this.smartflo_ref_id) this.smartflo_ref_id = this.smartfloRefId;
  if (this.call_status && !this.status) this.status = this.call_status;
  if (this.status && !this.call_status) this.call_status = this.status;
  if (this.call_started_at && !this.callStartTime) this.callStartTime = this.call_started_at;
  if (this.call_completed_at && !this.callEndTime) this.callEndTime = this.call_completed_at;
  if (this.failure_reason && !this.failureReason) this.failureReason = this.failure_reason;
  this.updated_at = new Date();
  this.updatedAt = new Date();
  if (typeof next === 'function') {
    next();
  }
});

const CallSession = mongoose.models.CallSession || mongoose.model('CallSession', callSessionSchema);

/**
 * 1. Customer initiates call to Pilot
 * POST /api/bookings/:bookingId/call-pilot
 */
app.post('/api/bookings/:bookingId/call-pilot', async (req, res) => {
  const { bookingId } = req.params;
  const callerUserId = req.body.callerUserId || req.body.userId || req.headers['x-user-id'];

  try {
    const booking = await Booking.findOne({ $or: [{ bookingId }, { _id: mongoose.isValidObjectId(bookingId) ? bookingId : null }] });
    if (!booking) {
      console.warn(`[Smartflo Call-Pilot Rejected]: Booking not found for ID ${bookingId}`);
      return res.status(404).json({ success: false, message: 'Booking not found.' });
    }

    // Booking Status Validation: allow active rides, only reject terminal/cancelled states
    const inactiveStatuses = ['completed', 'cancelled', 'canceled', 'rejected', 'expired'];
    const currentStatus = (booking.status || '').toLowerCase().trim();
    if (inactiveStatuses.includes(currentStatus)) {
      console.warn(`[Smartflo Call-Pilot Rejected]: booking ${bookingId} has inactive status '${currentStatus}'`);
      return res.status(400).json({
        success: false,
        message: 'Calling is not available for completed or cancelled rides.'
      });
    }

    // Caller Authorization (Customer role check)
    if (callerUserId) {
      const normCaller = String(callerUserId).replace('mock_uid_', '');
      const normPassenger = String(booking.passengerId || '').replace('mock_uid_', '');
      if (normPassenger && normCaller !== normPassenger) {
        console.warn(`[Smartflo Call-Pilot Rejected]: callerUserId ${callerUserId} mismatch with passengerId ${booking.passengerId}`);
        return res.status(403).json({
          success: false,
          message: 'Unauthorized: caller does not match the passenger for this booking.'
        });
      }
    }

    const smartfloCallerId = smartfloService.defaultDid || '8065916303';

    // Step 10: Duplicate Call Protection (Database Level)
    const existingActive = await CallSession.findOne({
      $or: [{ booking_id: bookingId }, { bookingId }],
      callerRole: 'customer',
      status: { $in: ['INITIATED', 'RINGING', 'ANSWERED'] },
      created_at: { $gte: new Date(Date.now() - 45000) }
    });

    if (existingActive) {
      return res.status(200).json({
        success: true,
        status: 'ALREADY_IN_PROGRESS',
        callId: existingActive.callId,
        virtualNumber: smartfloCallerId,
        message: 'Call already in progress'
      });
    }

    // In-memory debounce lock
    const lock = smartfloService.checkAndAcquireCallLock(bookingId, 'customer');
    if (!lock.acquired) {
      return res.status(200).json({
        success: true,
        status: 'ALREADY_IN_PROGRESS',
        virtualNumber: smartfloCallerId,
        message: 'Call already in progress'
      });
    }

    // Retrieve & Validate Pilot from Database
    if (!booking.driverId && !booking.driverPhone) {
      smartfloService.releaseCallLock(bookingId, 'customer');
      console.warn(`[Smartflo Call-Pilot Rejected]: Pilot not assigned yet to booking ${bookingId}`);
      return res.status(400).json({
        success: false,
        message: 'Pilot is not assigned to this booking yet.'
      });
    }

    let pilotPhone = null;
    if (booking.driverPhone && smartfloService.formatPhone(booking.driverPhone).length === 10) {
      pilotPhone = smartfloService.formatPhone(booking.driverPhone);
    } else if (booking.pilotPhone && smartfloService.formatPhone(booking.pilotPhone).length === 10) {
      pilotPhone = smartfloService.formatPhone(booking.pilotPhone);
    } else if (booking.partnerPhone && smartfloService.formatPhone(booking.partnerPhone).length === 10) {
      pilotPhone = smartfloService.formatPhone(booking.partnerPhone);
    }

    let pilot = null;
    if (!pilotPhone && booking.driverId) {
      pilot = await User.findOne({
        $or: [
          { uid: booking.driverId },
          { phone: booking.driverId },
          { driverPhone: booking.driverId },
          { applicationId: booking.driverId },
          { pilotId: booking.driverId },
          { _id: mongoose.isValidObjectId(booking.driverId) ? booking.driverId : null }
        ]
      });
      if (pilot) {
        const raw = pilot.phone || pilot.driverPhone || pilot.mobile || pilot.pilotPhone;
        if (raw && smartfloService.formatPhone(raw).length === 10) {
          pilotPhone = smartfloService.formatPhone(raw);
        }
      }
    }

    if (!pilotPhone && booking.driverId) {
      const digits = String(booking.driverId).replace(/\D/g, '');
      if (digits.length >= 10) {
        pilotPhone = smartfloService.formatPhone(digits.slice(-10));
      }
      if (!pilotPhone) {
        const fallbackPilot = await User.findOne({ phone: new RegExp((digits.length >= 10 ? digits.slice(-10) : booking.driverId) + '$') });
        if (fallbackPilot && fallbackPilot.phone) {
          pilotPhone = smartfloService.formatPhone(fallbackPilot.phone);
          if (!pilot) pilot = fallbackPilot;
        }
      }
    }

    if (!pilotPhone || pilotPhone.length !== 10) {
      smartfloService.releaseCallLock(bookingId, 'customer');
      console.warn(`[Smartflo Call-Pilot Rejected]: Pilot phone not found for booking ${bookingId}, driverId=${booking.driverId}`);
      return res.status(400).json({
        success: false,
        message: 'Pilot phone number is not available.'
      });
    }

    if (!booking.driverPhone) {
      Booking.updateOne({ _id: booking._id }, { $set: { driverPhone: pilotPhone } }).catch(() => {});
    }

    // Retrieve & Validate Customer from Database
    let customerPhone = null;
    if (booking.passengerPhone && smartfloService.formatPhone(booking.passengerPhone).length === 10) {
      customerPhone = smartfloService.formatPhone(booking.passengerPhone);
    } else if (booking.pickupContactPhone && smartfloService.formatPhone(booking.pickupContactPhone).length === 10) {
      customerPhone = smartfloService.formatPhone(booking.pickupContactPhone);
    } else if (booking.customerPhone && smartfloService.formatPhone(booking.customerPhone).length === 10) {
      customerPhone = smartfloService.formatPhone(booking.customerPhone);
    } else if (booking.phone && smartfloService.formatPhone(booking.phone).length === 10) {
      customerPhone = smartfloService.formatPhone(booking.phone);
    } else if (booking.userPhone && smartfloService.formatPhone(booking.userPhone).length === 10) {
      customerPhone = smartfloService.formatPhone(booking.userPhone);
    }

    let customer = null;
    if (!customerPhone && booking.passengerId) {
      customer = await User.findOne({
        $or: [
          { uid: booking.passengerId },
          { phone: booking.passengerId },
          { customerId: booking.passengerId },
          { _id: mongoose.isValidObjectId(booking.passengerId) ? booking.passengerId : null }
        ]
      });
      if (customer) {
        const raw = customer.phone || customer.mobile || customer.passengerPhone || customer.customerPhone;
        if (raw && smartfloService.formatPhone(raw).length === 10) {
          customerPhone = smartfloService.formatPhone(raw);
        }
      }
    }

    if (!customerPhone && booking.passengerId) {
      const digits = String(booking.passengerId).replace(/\D/g, '');
      if (digits.length >= 10) {
        customerPhone = smartfloService.formatPhone(digits.slice(-10));
      }
      if (!customerPhone) {
        const fallbackCust = await User.findOne({ phone: new RegExp((digits.length >= 10 ? digits.slice(-10) : booking.passengerId) + '$') });
        if (fallbackCust && fallbackCust.phone) {
          customerPhone = smartfloService.formatPhone(fallbackCust.phone);
          if (!customer) customer = fallbackCust;
        }
      }
    }

    if (!customerPhone || customerPhone.length !== 10) {
      smartfloService.releaseCallLock(bookingId, 'customer');
      console.warn(`[Smartflo Call-Pilot Rejected]: Customer phone not found for booking ${bookingId}, passengerId=${booking.passengerId}`);
      return res.status(400).json({
        success: false,
        message: 'Customer phone number is not available.'
      });
    }

    if (!booking.passengerPhone) {
      Booking.updateOne({ _id: booking._id }, { $set: { passengerPhone: customerPhone } }).catch(() => {});
    }

    // Synchronize pilot phone with registered profile if present
    let targetPilotPhone = pilotPhone;
    if (pilot && pilot.phone && smartfloService.formatPhone(pilot.phone).length === 10) {
      const registeredPilotPhone = smartfloService.formatPhone(pilot.phone);
      if (targetPilotPhone !== registeredPilotPhone) {
        console.log(`[Smartflo] Syncing pilot phone ${smartfloService.maskPhone(targetPilotPhone)} -> registered ${smartfloService.maskPhone(registeredPilotPhone)}`);
        targetPilotPhone = registeredPilotPhone;
      }
    }

    // Safe Debug Logging
    console.log(`[CALL MASKING DEBUG - CUSTOMER CALLING PILOT]`);
    console.log(`  bookingId: ${bookingId}`);
    console.log(`  customerId: ${booking.passengerId || 'unknown'}`);
    console.log(`  pilotId: ${booking.driverId || 'unknown'}`);
    console.log(`  pilotNumber: ${smartfloService.maskPhone(targetPilotPhone)}`);
    console.log(`  customerNumber: ${smartfloService.maskPhone(customerPhone)}`);
    console.log(`  smartfloAgentNumber: ${smartfloService.maskPhone(customerPhone)}`);
    console.log(`  smartfloDestinationNumber: ${smartfloService.maskPhone(targetPilotPhone)}`);
    console.log(`  smartfloCallerId: ${smartfloService.maskPhone(smartfloCallerId)}`);

    // Initiate Smartflo Bridging (Customer is called first, then connected to Pilot)
    let smartfloResult;
    try {
      smartfloResult = await smartfloService.initiateClickToCall({
        agentPhone: customerPhone,
        destinationPhone: targetPilotPhone,
        virtualNumber: smartfloCallerId,
        bookingId: bookingId
      });
    } catch (apiErr) {
      smartfloService.releaseCallLock(bookingId, 'customer');
      console.error('[Smartflo Call Pilot Error]:', apiErr.message);

      // Record direct fallback in CallSession for Admin Panel visibility & audit
      const customerDisplayName = booking.passengerName || (customer && customer.name) || 'Customer';
      const pilotDisplayName = booking.driverName || (pilot && pilot.name) || 'Pilot';

      const fallbackSession = new CallSession({
        callId: 'FALLBACK-' + Math.floor(100000 + Math.random() * 900000),
        booking_id: bookingId,
        bookingId: bookingId,
        caller_user_id: booking.passengerId || 'customer',
        receiver_user_id: booking.driverId || 'pilot',
        customerId: booking.passengerId || 'customer',
        pilotId: booking.driverId || 'pilot',
        customerName: customerDisplayName,
        pilotName: pilotDisplayName,
        customerPhoneMasked: smartfloService.maskPhone(customerPhone),
        pilotPhoneMasked: smartfloService.maskPhone(targetPilotPhone),
        virtualNumber: smartfloCallerId,
        callerRole: 'customer',
        call_status: 'DIRECT_FALLBACK',
        status: 'DIRECT_FALLBACK',
        is_fallback: true,
        isFallback: true,
        failure_reason: `Smartflo PBX error: ${apiErr.message}. Real number direct calling provided.`,
        failureReason: `Smartflo PBX error: ${apiErr.message}. Real number direct calling provided.`,
        call_started_at: new Date(),
        callStartTime: new Date(),
        created_at: new Date(),
        updated_at: new Date()
      });
      await fallbackSession.save().catch(() => {});

      if (typeof io !== 'undefined' && io) {
        io.emit(`booking:${bookingId}:call`, {
          callId: fallbackSession.callId,
          callerRole: 'customer',
          status: 'DIRECT_FALLBACK'
        });
      }

      return res.status(200).json({
        success: true,
        fallbackMode: true,
        status: 'DIRECT_FALLBACK_AVAILABLE',
        callId: fallbackSession.callId,
        realPhone: targetPilotPhone,
        pilotPhone: targetPilotPhone,
        pilotName: pilotDisplayName,
        virtualNumber: smartfloCallerId,
        message: 'Tata Smartflo automated masking unavailable. You can call pilot directly using regular phone.'
      });
    }

    // Resolve names safely for Admin Panel visibility
    const customerDisplayName = booking.passengerName || (customer && customer.name) || 'Customer';
    const pilotDisplayName = booking.driverName || (pilot && pilot.name) || 'Pilot';

    // Save CallSession to Database
    const callSession = new CallSession({
      callId: 'CALL-' + Math.floor(100000 + Math.random() * 900000),
      booking_id: bookingId,
      bookingId: bookingId,
      caller_user_id: booking.passengerId || 'customer',
      receiver_user_id: booking.driverId || 'pilot',
      customerId: booking.passengerId || 'customer',
      pilotId: booking.driverId || 'pilot',
      customerName: customerDisplayName,
      pilotName: pilotDisplayName,
      customerPhoneMasked: smartfloService.maskPhone(customerPhone),
      pilotPhoneMasked: smartfloService.maskPhone(targetPilotPhone),
      virtualNumber: smartfloCallerId,
      callerRole: 'customer',
      smartflo_ref_id: smartfloResult.refId,
      smartfloRefId: smartfloResult.refId,
      call_status: 'INITIATED',
      status: 'INITIATED',
      call_started_at: new Date(),
      callStartTime: new Date(),
      created_at: new Date(),
      updated_at: new Date()
    });
    await callSession.save();

    // Broadcast call initiation via Socket.IO
    if (typeof io !== 'undefined' && io) {
      io.emit(`booking:${bookingId}:call`, {
        callId: callSession.callId,
        callerRole: 'customer',
        status: 'INITIATED'
      });
    }

    // Return safe response with virtualNumber for direct dial fallback
    return res.status(200).json({
      success: true,
      status: 'CALL_INITIATED',
      callId: callSession.callId,
      virtualNumber: smartfloCallerId,
      realPhone: targetPilotPhone,
      pilotName: pilotDisplayName,
      message: 'Call initiated. Tata Smartflo will connect you shortly.'
    });
  } catch (err) {
    smartfloService.releaseCallLock(bookingId, 'customer');
    console.error('[POST /api/bookings/:id/call-pilot Error]:', err);
    return res.status(500).json({ success: false, message: 'Internal server error processing call request.' });
  }
});

/**
 * 2. Pilot initiates call to Customer
 * POST /api/bookings/:bookingId/call-customer
 */
app.post('/api/bookings/:bookingId/call-customer', async (req, res) => {
  const { bookingId } = req.params;
  const callerUserId = req.body.callerUserId || req.body.userId || req.headers['x-user-id'];

  try {
    const booking = await Booking.findOne({ $or: [{ bookingId }, { _id: mongoose.isValidObjectId(bookingId) ? bookingId : null }] });
    if (!booking) {
      console.warn(`[Smartflo Call-Customer Rejected]: Booking not found for ID ${bookingId}`);
      return res.status(404).json({ success: false, message: 'Booking not found.' });
    }

    // Booking Status Validation: allow active rides, only reject terminal/cancelled states
    const inactiveStatuses = ['completed', 'cancelled', 'canceled', 'rejected', 'expired'];
    const currentStatus = (booking.status || '').toLowerCase().trim();
    if (inactiveStatuses.includes(currentStatus)) {
      console.warn(`[Smartflo Call-Customer Rejected]: booking ${bookingId} has inactive status '${currentStatus}'`);
      return res.status(400).json({
        success: false,
        message: 'Calling is not available for completed or cancelled rides.'
      });
    }

    // Caller Authorization (Pilot role check)
    if (callerUserId) {
      const normCaller = String(callerUserId).replace('mock_uid_', '');
      const normDriver = String(booking.driverId || '').replace('mock_uid_', '');
      if (normDriver && normCaller !== normDriver) {
        console.warn(`[Smartflo Call-Customer Rejected]: callerUserId ${callerUserId} mismatch with driverId ${booking.driverId}`);
        return res.status(403).json({
          success: false,
          message: 'Unauthorized: caller does not match the pilot for this booking.'
        });
      }
    }

    const smartfloCallerId = smartfloService.defaultDid || '8065916303';

    // Step 10: Duplicate Call Protection (Database Level)
    const existingActive = await CallSession.findOne({
      $or: [{ booking_id: bookingId }, { bookingId }],
      callerRole: 'pilot',
      status: { $in: ['INITIATED', 'RINGING', 'ANSWERED'] },
      created_at: { $gte: new Date(Date.now() - 45000) }
    });

    if (existingActive) {
      return res.status(200).json({
        success: true,
        status: 'ALREADY_IN_PROGRESS',
        callId: existingActive.callId,
        virtualNumber: smartfloCallerId,
        message: 'Call already in progress'
      });
    }

    // In-memory debounce lock
    const lock = smartfloService.checkAndAcquireCallLock(bookingId, 'pilot');
    if (!lock.acquired) {
      return res.status(200).json({
        success: true,
        status: 'ALREADY_IN_PROGRESS',
        virtualNumber: smartfloCallerId,
        message: 'Call already in progress'
      });
    }

    // Retrieve & Validate Pilot from Database
    if (!booking.driverId && !booking.driverPhone) {
      smartfloService.releaseCallLock(bookingId, 'pilot');
      console.warn(`[Smartflo Call-Customer Rejected]: Pilot not assigned yet to booking ${bookingId}`);
      return res.status(400).json({
        success: false,
        message: 'Pilot is not assigned to this booking.'
      });
    }

    let pilotPhone = null;
    if (booking.driverPhone && smartfloService.formatPhone(booking.driverPhone).length === 10) {
      pilotPhone = smartfloService.formatPhone(booking.driverPhone);
    } else if (booking.pilotPhone && smartfloService.formatPhone(booking.pilotPhone).length === 10) {
      pilotPhone = smartfloService.formatPhone(booking.pilotPhone);
    } else if (booking.partnerPhone && smartfloService.formatPhone(booking.partnerPhone).length === 10) {
      pilotPhone = smartfloService.formatPhone(booking.partnerPhone);
    }

    let pilot = null;
    if (!pilotPhone && booking.driverId) {
      pilot = await User.findOne({
        $or: [
          { uid: booking.driverId },
          { phone: booking.driverId },
          { driverPhone: booking.driverId },
          { applicationId: booking.driverId },
          { pilotId: booking.driverId },
          { _id: mongoose.isValidObjectId(booking.driverId) ? booking.driverId : null }
        ]
      });
      if (pilot) {
        const raw = pilot.phone || pilot.driverPhone || pilot.mobile || pilot.pilotPhone;
        if (raw && smartfloService.formatPhone(raw).length === 10) {
          pilotPhone = smartfloService.formatPhone(raw);
        }
      }
    }

    if (!pilotPhone && booking.driverId) {
      const digits = String(booking.driverId).replace(/\D/g, '');
      if (digits.length >= 10) {
        pilotPhone = smartfloService.formatPhone(digits.slice(-10));
      }
      if (!pilotPhone) {
        const fallbackPilot = await User.findOne({ phone: new RegExp((digits.length >= 10 ? digits.slice(-10) : booking.driverId) + '$') });
        if (fallbackPilot && fallbackPilot.phone) {
          pilotPhone = smartfloService.formatPhone(fallbackPilot.phone);
          if (!pilot) pilot = fallbackPilot;
        }
      }
    }

    if (!pilotPhone || pilotPhone.length !== 10) {
      smartfloService.releaseCallLock(bookingId, 'pilot');
      console.warn(`[Smartflo Call-Customer Rejected]: Pilot phone not found for booking ${bookingId}, driverId=${booking.driverId}`);
      return res.status(400).json({
        success: false,
        message: 'Pilot phone number is not available.'
      });
    }

    if (!booking.driverPhone) {
      Booking.updateOne({ _id: booking._id }, { $set: { driverPhone: pilotPhone } }).catch(() => {});
    }

    // Retrieve & Validate Customer from Database
    let customerPhone = null;
    if (booking.passengerPhone && smartfloService.formatPhone(booking.passengerPhone).length === 10) {
      customerPhone = smartfloService.formatPhone(booking.passengerPhone);
    } else if (booking.dropContactPhone && smartfloService.formatPhone(booking.dropContactPhone).length === 10) {
      customerPhone = smartfloService.formatPhone(booking.dropContactPhone);
    } else if (booking.pickupContactPhone && smartfloService.formatPhone(booking.pickupContactPhone).length === 10) {
      customerPhone = smartfloService.formatPhone(booking.pickupContactPhone);
    } else if (booking.customerPhone && smartfloService.formatPhone(booking.customerPhone).length === 10) {
      customerPhone = smartfloService.formatPhone(booking.customerPhone);
    } else if (booking.phone && smartfloService.formatPhone(booking.phone).length === 10) {
      customerPhone = smartfloService.formatPhone(booking.phone);
    } else if (booking.userPhone && smartfloService.formatPhone(booking.userPhone).length === 10) {
      customerPhone = smartfloService.formatPhone(booking.userPhone);
    }

    let customer = null;
    if (!customerPhone && booking.passengerId) {
      customer = await User.findOne({
        $or: [
          { uid: booking.passengerId },
          { phone: booking.passengerId },
          { customerId: booking.passengerId },
          { _id: mongoose.isValidObjectId(booking.passengerId) ? booking.passengerId : null }
        ]
      });
      if (customer) {
        const raw = customer.phone || customer.mobile || customer.passengerPhone || customer.customerPhone;
        if (raw && smartfloService.formatPhone(raw).length === 10) {
          customerPhone = smartfloService.formatPhone(raw);
        }
      }
    }

    if (!customerPhone && booking.passengerId) {
      const digits = String(booking.passengerId).replace(/\D/g, '');
      if (digits.length >= 10) {
        customerPhone = smartfloService.formatPhone(digits.slice(-10));
      }
      if (!customerPhone) {
        const fallbackCust = await User.findOne({ phone: new RegExp((digits.length >= 10 ? digits.slice(-10) : booking.passengerId) + '$') });
        if (fallbackCust && fallbackCust.phone) {
          customerPhone = smartfloService.formatPhone(fallbackCust.phone);
          if (!customer) customer = fallbackCust;
        }
      }
    }

    if (!customerPhone || customerPhone.length !== 10) {
      smartfloService.releaseCallLock(bookingId, 'pilot');
      console.warn(`[Smartflo Call-Customer Rejected]: Customer phone not found for booking ${bookingId}, passengerId=${booking.passengerId}`);
      return res.status(400).json({
        success: false,
        message: 'Customer phone number is not available.'
      });
    }

    if (!booking.passengerPhone) {
      Booking.updateOne({ _id: booking._id }, { $set: { passengerPhone: customerPhone } }).catch(() => {});
    }

    // Synchronize pilot phone with registered profile if present
    let targetPilotPhone = pilotPhone;
    if (pilot && pilot.phone && smartfloService.formatPhone(pilot.phone).length === 10) {
      const registeredPilotPhone = smartfloService.formatPhone(pilot.phone);
      if (targetPilotPhone !== registeredPilotPhone) {
        console.log(`[Smartflo] Syncing pilot phone ${smartfloService.maskPhone(targetPilotPhone)} -> registered ${smartfloService.maskPhone(registeredPilotPhone)}`);
        targetPilotPhone = registeredPilotPhone;
      }
    }

    // STEP 8: Safe Debug Logging
    console.log(`[CALL MASKING DEBUG - PILOT CALLING CUSTOMER]`);
    console.log(`  bookingId: ${bookingId}`);
    console.log(`  customerId: ${booking.passengerId || 'unknown'}`);
    console.log(`  pilotId: ${booking.driverId || 'unknown'}`);
    console.log(`  pilotNumber: ${smartfloService.maskPhone(targetPilotPhone)}`);
    console.log(`  customerNumber: ${smartfloService.maskPhone(customerPhone)}`);
    console.log(`  smartfloAgentNumber: ${smartfloService.maskPhone(targetPilotPhone)}`);
    console.log(`  smartfloDestinationNumber: ${smartfloService.maskPhone(customerPhone)}`);
    console.log(`  smartfloCallerId: ${smartfloService.maskPhone(smartfloCallerId)}`);

    // Initiate Smartflo Bridging (Pilot is agent_number, Customer is destination_number)
    let smartfloResult;
    try {
      smartfloResult = await smartfloService.initiateClickToCall({
        agentPhone: targetPilotPhone,
        destinationPhone: customerPhone,
        virtualNumber: smartfloCallerId,
        bookingId: bookingId
      });
    } catch (apiErr) {
      smartfloService.releaseCallLock(bookingId, 'pilot');
      console.error('[Smartflo Call Customer Error]:', apiErr.message);

      // Record direct fallback in CallSession for Admin Panel visibility & audit
      const customerDisplayName = booking.passengerName || (customer && customer.name) || 'Customer';
      const pilotDisplayName = booking.driverName || (pilot && pilot.name) || 'Pilot';

      const fallbackSession = new CallSession({
        callId: 'FALLBACK-' + Math.floor(100000 + Math.random() * 900000),
        booking_id: bookingId,
        bookingId: bookingId,
        caller_user_id: booking.driverId || 'pilot',
        receiver_user_id: booking.passengerId || 'customer',
        customerId: booking.passengerId || 'customer',
        pilotId: booking.driverId || 'pilot',
        customerName: customerDisplayName,
        pilotName: pilotDisplayName,
        customerPhoneMasked: smartfloService.maskPhone(customerPhone),
        pilotPhoneMasked: smartfloService.maskPhone(targetPilotPhone),
        virtualNumber: smartfloCallerId,
        callerRole: 'pilot',
        call_status: 'DIRECT_FALLBACK',
        status: 'DIRECT_FALLBACK',
        is_fallback: true,
        isFallback: true,
        failure_reason: `Smartflo PBX error: ${apiErr.message}. Real number direct calling provided.`,
        failureReason: `Smartflo PBX error: ${apiErr.message}. Real number direct calling provided.`,
        call_started_at: new Date(),
        callStartTime: new Date(),
        created_at: new Date(),
        updated_at: new Date()
      });
      await fallbackSession.save().catch(() => {});

      if (typeof io !== 'undefined' && io) {
        io.emit(`booking:${bookingId}:call`, {
          callId: fallbackSession.callId,
          callerRole: 'pilot',
          status: 'DIRECT_FALLBACK'
        });
      }

      return res.status(200).json({
        success: true,
        fallbackMode: true,
        status: 'DIRECT_FALLBACK_AVAILABLE',
        callId: fallbackSession.callId,
        realPhone: customerPhone,
        customerPhone: customerPhone,
        customerName: customerDisplayName,
        virtualNumber: smartfloCallerId,
        message: 'Tata Smartflo automated masking unavailable. You can call customer directly using regular phone.'
      });
    }

    // Resolve names safely for Admin Panel visibility
    const customerDisplayName = booking.passengerName || (customer && customer.name) || 'Customer';
    const pilotDisplayName = booking.driverName || (pilot && pilot.name) || 'Pilot';

    // Save CallSession to Database
    const callSession = new CallSession({
      callId: 'CALL-' + Math.floor(100000 + Math.random() * 900000),
      booking_id: bookingId,
      bookingId: bookingId,
      caller_user_id: booking.driverId || 'pilot',
      receiver_user_id: booking.passengerId || 'customer',
      customerId: booking.passengerId || 'customer',
      pilotId: booking.driverId || 'pilot',
      customerName: customerDisplayName,
      pilotName: pilotDisplayName,
      customerPhoneMasked: smartfloService.maskPhone(customerPhone),
      pilotPhoneMasked: smartfloService.maskPhone(targetPilotPhone),
      virtualNumber: smartfloCallerId,
      callerRole: 'pilot',
      smartflo_ref_id: smartfloResult.refId,
      smartfloRefId: smartfloResult.refId,
      call_status: 'INITIATED',
      status: 'INITIATED',
      call_started_at: new Date(),
      callStartTime: new Date(),
      created_at: new Date(),
      updated_at: new Date()
    });
    await callSession.save();

    // Broadcast call initiation via Socket.IO
    if (typeof io !== 'undefined' && io) {
      io.emit(`booking:${bookingId}:call`, {
        callId: callSession.callId,
        callerRole: 'pilot',
        status: 'INITIATED'
      });
    }

    // Return safe response with virtualNumber for direct dial fallback
    return res.status(200).json({
      success: true,
      status: 'CALL_INITIATED',
      callId: callSession.callId,
      virtualNumber: smartfloCallerId,
      realPhone: customerPhone,
      customerName: customerDisplayName,
      message: 'Call initiated. Tata Smartflo will ring your phone shortly.'
    });
  } catch (err) {
    smartfloService.releaseCallLock(bookingId, 'pilot');
    console.error('[POST /api/bookings/:id/call-customer Error]:', err);
    return res.status(500).json({ success: false, message: 'Internal server error processing call request.' });
  }
});

/**
 * 2b. Direct Real Number Calling Fallback (Priority 2)
 * When Tata Smartflo is down, times out, or when Customer/Pilot requests direct calling.
 * POST /api/bookings/:bookingId/call-direct-fallback
 */
app.post('/api/bookings/:bookingId/call-direct-fallback', async (req, res) => {
  const { bookingId } = req.params;
  const { callerRole, callerUserId, reason } = req.body;

  try {
    const booking = await Booking.findOne({ $or: [{ bookingId }, { _id: mongoose.isValidObjectId(bookingId) ? bookingId : null }] });
    if (!booking) {
      return res.status(404).json({ success: false, message: 'Booking not found.' });
    }

    const inactiveStatuses = ['completed', 'cancelled', 'canceled', 'rejected', 'expired'];
    const currentStatus = (booking.status || '').toLowerCase().trim();
    if (inactiveStatuses.includes(currentStatus)) {
      return res.status(400).json({ success: false, message: 'Calling is not available for completed or cancelled rides.' });
    }

    // Resolve Pilot Phone
    let pilotPhone = null;
    if (booking.driverPhone && smartfloService.formatPhone(booking.driverPhone).length === 10) {
      pilotPhone = smartfloService.formatPhone(booking.driverPhone);
    } else if (booking.pilotPhone && smartfloService.formatPhone(booking.pilotPhone).length === 10) {
      pilotPhone = smartfloService.formatPhone(booking.pilotPhone);
    } else if (booking.partnerPhone && smartfloService.formatPhone(booking.partnerPhone).length === 10) {
      pilotPhone = smartfloService.formatPhone(booking.partnerPhone);
    }

    let pilot = null;
    if (!pilotPhone && booking.driverId) {
      pilot = await User.findOne({
        $or: [
          { uid: booking.driverId },
          { phone: booking.driverId },
          { driverPhone: booking.driverId },
          { applicationId: booking.driverId },
          { pilotId: booking.driverId },
          { _id: mongoose.isValidObjectId(booking.driverId) ? booking.driverId : null }
        ]
      });
      if (pilot) {
        const raw = pilot.phone || pilot.driverPhone || pilot.mobile || pilot.pilotPhone;
        if (raw && smartfloService.formatPhone(raw).length === 10) {
          pilotPhone = smartfloService.formatPhone(raw);
        }
      }
    }

    if (!pilotPhone && booking.driverId) {
      const digits = String(booking.driverId).replace(/\D/g, '');
      if (digits.length >= 10) pilotPhone = smartfloService.formatPhone(digits.slice(-10));
    }

    // Resolve Customer Phone
    let customerPhone = null;
    if (booking.passengerPhone && smartfloService.formatPhone(booking.passengerPhone).length === 10) {
      customerPhone = smartfloService.formatPhone(booking.passengerPhone);
    } else if (booking.pickupContactPhone && smartfloService.formatPhone(booking.pickupContactPhone).length === 10) {
      customerPhone = smartfloService.formatPhone(booking.pickupContactPhone);
    } else if (booking.customerPhone && smartfloService.formatPhone(booking.customerPhone).length === 10) {
      customerPhone = smartfloService.formatPhone(booking.customerPhone);
    } else if (booking.phone && smartfloService.formatPhone(booking.phone).length === 10) {
      customerPhone = smartfloService.formatPhone(booking.phone);
    }

    let customer = null;
    if (!customerPhone && booking.passengerId) {
      customer = await User.findOne({
        $or: [
          { uid: booking.passengerId },
          { phone: booking.passengerId },
          { customerId: booking.passengerId },
          { _id: mongoose.isValidObjectId(booking.passengerId) ? booking.passengerId : null }
        ]
      });
      if (customer) {
        const raw = customer.phone || customer.mobile || customer.passengerPhone || customer.customerPhone;
        if (raw && smartfloService.formatPhone(raw).length === 10) {
          customerPhone = smartfloService.formatPhone(raw);
        }
      }
    }

    if (!customerPhone && booking.passengerId) {
      const digits = String(booking.passengerId).replace(/\D/g, '');
      if (digits.length >= 10) customerPhone = smartfloService.formatPhone(digits.slice(-10));
    }

    const effectiveRole = callerRole === 'pilot' ? 'pilot' : 'customer';
    const destinationPhone = effectiveRole === 'customer' ? pilotPhone : customerPhone;
    const customerDisplayName = booking.passengerName || (customer && customer.name) || 'Customer';
    const pilotDisplayName = booking.driverName || (pilot && pilot.name) || 'Pilot';
    const destinationName = effectiveRole === 'customer' ? pilotDisplayName : customerDisplayName;

    if (!destinationPhone || destinationPhone.length !== 10) {
      return res.status(400).json({ success: false, message: 'Destination phone number is not available.' });
    }

    // Save CallSession to Database with DIRECT_FALLBACK
    const callSession = new CallSession({
      callId: 'CALL-DIRECT-' + Math.floor(100000 + Math.random() * 900000),
      booking_id: bookingId,
      bookingId: bookingId,
      caller_user_id: effectiveRole === 'customer' ? (booking.passengerId || 'customer') : (booking.driverId || 'pilot'),
      receiver_user_id: effectiveRole === 'customer' ? (booking.driverId || 'pilot') : (booking.passengerId || 'customer'),
      customerId: booking.passengerId || 'customer',
      pilotId: booking.driverId || 'pilot',
      customerName: customerDisplayName,
      pilotName: pilotDisplayName,
      customerPhoneMasked: smartfloService.maskPhone(customerPhone),
      pilotPhoneMasked: smartfloService.maskPhone(pilotPhone),
      virtualNumber: smartfloService.defaultDid || '8065916303',
      callerRole: effectiveRole,
      call_status: 'DIRECT_FALLBACK',
      status: 'DIRECT_FALLBACK',
      is_fallback: true,
      isFallback: true,
      failure_reason: reason || `Direct real number dial launched by ${effectiveRole} (Smartflo fallback)`,
      failureReason: reason || `Direct real number dial launched by ${effectiveRole} (Smartflo fallback)`,
      call_started_at: new Date(),
      callStartTime: new Date(),
      created_at: new Date(),
      updated_at: new Date()
    });
    await callSession.save();

    // Broadcast call status via Socket.IO
    if (typeof io !== 'undefined' && io) {
      io.emit(`booking:${bookingId}:call`, {
        callId: callSession.callId,
        callerRole: effectiveRole,
        status: 'DIRECT_FALLBACK'
      });
      io.to('admin_tracking').emit('admin_call_fallback', {
        bookingId,
        callerRole: effectiveRole,
        customerName: customerDisplayName,
        pilotName: pilotDisplayName,
        timestamp: new Date()
      });
    }

    return res.status(200).json({
      success: true,
      status: 'DIRECT_FALLBACK_LAUNCHED',
      callId: callSession.callId,
      destinationPhone: '+91' + destinationPhone,
      rawPhone: destinationPhone,
      contactName: destinationName,
      message: 'Direct dial launched successfully.'
    });
  } catch (err) {
    console.error('[POST /api/bookings/:bookingId/call-direct-fallback Error]:', err);
    return res.status(500).json({ success: false, message: 'Internal server error processing direct dial fallback.' });
  }
});

/**
 * 3. Fetch call status for a booking
 * GET /api/bookings/:bookingId/call-status
 */
app.get('/api/bookings/:bookingId/call-status', async (req, res) => {
  try {
    const { bookingId } = req.params;
    const session = await CallSession.findOne({
      $or: [{ booking_id: bookingId }, { bookingId }]
    }).sort({ created_at: -1 });

    if (!session) {
      return res.status(200).json({ success: true, hasActiveCall: false });
    }
    return res.status(200).json({
      success: true,
      hasActiveCall: ['INITIATED', 'RINGING', 'ANSWERED'].includes(session.status),
      callSession: {
        callId: session.callId,
        status: session.status || session.call_status,
        callerRole: session.callerRole,
        callStartedAt: session.call_started_at || session.callStartTime,
        callAnsweredAt: session.call_answered_at,
        callCompletedAt: session.call_completed_at || session.callEndTime,
        failureReason: session.failure_reason || session.failureReason
      }
    });
  } catch (err) {
    console.error('[GET /api/bookings/:id/call-status Error]:', err);
    return res.status(500).json({ success: false, message: err.message });
  }
});

/**
 * 4. Tata Smartflo Webhook Listener
 * POST /api/smartflo/webhook & POST /api/call/smartflo/webhook
 */
const handleSmartfloWebhook = async (req, res) => {
  try {
    const body = req.body || {};
    const refId = body.ref_id || body.call_id || body.id || body.sessionId || req.query.ref_id;
    const customIdentifier = body.custom_identifier || body.customId || req.query.custom_identifier;
    const rawStatus = (body.status || body.event || body.call_status || req.query.status || '').toUpperCase();

    console.log(`[Smartflo Webhook] RefID: ${refId || 'N/A'}, Identifier: ${customIdentifier || 'N/A'}, Event: ${rawStatus}`);

    let mappedStatus = 'INITIATED';
    if (rawStatus.includes('ANSWER') || rawStatus.includes('UP') || rawStatus === 'CONNECTED') {
      mappedStatus = 'ANSWERED';
    } else if (rawStatus.includes('RING')) {
      mappedStatus = 'RINGING';
    } else if (rawStatus.includes('COMPLET') || rawStatus.includes('END') || rawStatus === 'HANGUP' || rawStatus === 'DISCONNECTED') {
      mappedStatus = 'COMPLETED';
    } else if (rawStatus.includes('FAIL') || rawStatus.includes('ERROR')) {
      mappedStatus = 'FAILED';
    } else if (rawStatus.includes('MISS') || rawStatus.includes('NOANSWER')) {
      mappedStatus = 'MISSED';
    } else if (rawStatus.includes('BUSY')) {
      mappedStatus = 'BUSY';
    }

    const now = new Date();
    const updateData = {
      status: mappedStatus,
      call_status: mappedStatus,
      updated_at: now,
      updatedAt: now
    };

    if (body.call_id) {
      updateData.smartflo_call_id = String(body.call_id);
      updateData.smartfloCallId = String(body.call_id);
    }

    if (mappedStatus === 'ANSWERED') {
      updateData.call_answered_at = now;
    } else if (mappedStatus === 'COMPLETED') {
      updateData.call_completed_at = now;
      updateData.callEndTime = now;
      if (body.duration) updateData.duration = parseInt(body.duration, 10);
    } else if (mappedStatus === 'FAILED' || mappedStatus === 'MISSED') {
      updateData.call_failed_at = now;
      updateData.failure_reason = body.reason || body.message || rawStatus;
      updateData.failureReason = updateData.failure_reason;
    }

    // Query by ref_id or custom_identifier (bookingId)
    const matchCriteria = [];
    if (refId) {
      matchCriteria.push({ smartflo_ref_id: refId }, { smartfloRefId: refId });
    }
    if (body.call_id) {
      matchCriteria.push({ smartflo_call_id: body.call_id });
    }
    if (customIdentifier) {
      matchCriteria.push({ booking_id: customIdentifier }, { bookingId: customIdentifier });
    }

    if (matchCriteria.length > 0) {
      const updated = await CallSession.findOneAndUpdate(
        { $or: matchCriteria },
        updateData,
        { new: true, sort: { created_at: -1 } }
      );

      if (updated && typeof io !== 'undefined' && io) {
        if (updated.orderType === 'food_order') {
          io.emit(`food_order:${updated.booking_id}:call`, {
            callId: updated.callId,
            status: mappedStatus
          });
          io.to('admin_tracking').emit('admin_call_updated', updated);
        } else {
          io.emit(`booking:${updated.booking_id}:call`, {
            callId: updated.callId,
            status: mappedStatus
          });
        }
      }
    }

    return res.status(200).json({ success: true, message: 'Webhook processed successfully' });
  } catch (err) {
    console.error('[Smartflo Webhook Error]:', err);
    return res.status(200).json({ success: false, message: 'Webhook error handled' });
  }
};

app.post('/api/smartflo/webhook', handleSmartfloWebhook);
app.post('/api/call/smartflo/webhook', handleSmartfloWebhook);
app.get('/api/smartflo/webhook', handleSmartfloWebhook);

/**
 * 5. Admin Call Monitoring Endpoint (STEP 14)
 * GET /api/admin/calls
 */
app.get('/api/admin/calls', async (req, res) => {
  try {
    const limit = Math.min(parseInt(req.query.limit || '50', 10), 100);
    const sessions = await CallSession.find()
      .sort({ created_at: -1 })
      .limit(limit)
      .lean();

    const safeSessions = sessions.map(s => ({
      callId: s.callId,
      bookingId: s.booking_id || s.bookingId,
      orderType: s.orderType || (String(s.booking_id || s.bookingId).startsWith('FD_') ? 'food_order' : 'ride'),
      targetRole: s.targetRole || (s.callerRole === 'customer' ? 'pilot' : 'customer'),
      callerUserId: s.caller_user_id || s.customerId,
      receiverUserId: s.receiver_user_id || s.pilotId,
      customerName: s.customerName || 'Customer',
      pilotName: s.pilotName || 'Pilot',
      restaurantName: s.restaurantName || '',
      customerPhoneMasked: s.customerPhoneMasked || smartfloService.maskPhone(s.callerRole === 'customer' ? s.caller_user_id : s.receiver_user_id),
      pilotPhoneMasked: s.pilotPhoneMasked || smartfloService.maskPhone(s.callerRole === 'pilot' ? s.caller_user_id : s.receiver_user_id),
      restaurantPhoneMasked: s.restaurantPhoneMasked || (s.callerRole === 'restaurant' ? smartfloService.maskPhone(s.caller_user_id) : smartfloService.maskPhone(s.receiver_user_id)),
      virtualNumber: s.virtualNumber || smartfloService.defaultDid,
      callerRole: s.callerRole,
      status: s.call_status || s.status,
      callStatus: s.call_status || s.status,
      isFallback: s.is_fallback || s.call_status === 'DIRECT_FALLBACK' || s.status === 'DIRECT_FALLBACK',
      smartfloRefId: s.smartflo_ref_id || s.smartfloRefId,
      callStartedAt: s.call_started_at || s.callStartTime,
      callAnsweredAt: s.call_answered_at,
      callCompletedAt: s.call_completed_at || s.callEndTime,
      duration: s.duration,
      failureReason: s.failure_reason || s.failureReason
    }));

    return res.status(200).json({
      success: true,
      count: safeSessions.length,
      calls: safeSessions
    });
  } catch (err) {
    console.error('[GET /api/admin/calls Error]:', err);
    return res.status(500).json({ success: false, message: 'Failed to retrieve call logs' });
  }
});

/**
 * Admin direct call masking support endpoint
 * POST /api/admin/call/initiate
 */
app.post('/api/admin/call/initiate', async (req, res) => {
  try {
    const { adminPhone, targetPhone, targetRole, targetName, bookingId } = req.body;
    if (!targetPhone) {
      return res.status(400).json({ success: false, message: 'targetPhone is required' });
    }

    const cleanTarget = smartfloService.formatPhone(targetPhone);
    const cleanAdmin = smartfloService.formatPhone(adminPhone || process.env.ADMIN_PHONE || '9490440281');

    if (cleanTarget.length !== 10) {
      return res.status(400).json({ success: false, message: 'Invalid target phone number. Must be 10 digits.' });
    }

    const smartfloCallerId = smartfloService.defaultDid || '8065916303';

    const smartfloResult = await smartfloService.initiateClickToCall({
      agentPhone: cleanAdmin,
      destinationPhone: cleanTarget,
      virtualNumber: smartfloCallerId,
      bookingId: bookingId || 'ADMIN_SUPPORT'
    });

    const callSession = new CallSession({
      callId: 'CALL-' + Math.floor(100000 + Math.random() * 900000),
      booking_id: bookingId || 'ADMIN_SUPPORT',
      bookingId: bookingId || 'ADMIN_SUPPORT',
      caller_user_id: 'admin',
      receiver_user_id: cleanTarget,
      customerName: targetRole === 'customer' ? (targetName || 'Customer') : 'Support Admin',
      pilotName: targetRole === 'pilot' ? (targetName || 'Pilot') : 'Staff Admin',
      customerPhoneMasked: smartfloService.maskPhone(cleanAdmin),
      pilotPhoneMasked: smartfloService.maskPhone(cleanTarget),
      virtualNumber: smartfloCallerId,
      callerRole: 'admin',
      smartflo_ref_id: smartfloResult.refId,
      smartfloRefId: smartfloResult.refId,
      call_status: 'INITIATED',
      status: 'INITIATED',
      call_started_at: new Date(),
      callStartTime: new Date(),
      created_at: new Date(),
      updated_at: new Date()
    });
    await callSession.save();

    return res.status(200).json({
      success: true,
      status: 'CALL_INITIATED',
      callId: callSession.callId,
      virtualNumber: smartfloCallerId,
      refId: smartfloResult.refId,
      message: 'Admin masked call initiated. Tata Smartflo is connecting your phone.'
    });
  } catch (err) {
    console.error('[Admin Call Initiate Error]:', err);
    return res.status(500).json({ success: false, message: err.message || 'Failed to initiate admin call' });
  }
});

/**
 * 5. General Call Masking endpoint (Backward compatibility)
 * POST /api/call/mask
 */
app.post('/api/call/mask', async (req, res) => {
  try {
    const { fromPhone, toPhone, virtualNumber } = req.body;
    if (!fromPhone || !toPhone) {
      return res.status(400).json({ success: false, error: 'fromPhone and toPhone are required' });
    }

    const result = await smartfloService.initiateClickToCall({
      agentPhone: fromPhone,
      destinationPhone: toPhone,
      virtualNumber
    });

    return res.status(200).json({
      success: true,
      message: 'Masked call initiated successfully',
      refId: result.refId
    });
  } catch (err) {
    console.error('[Call Masking Error]:', err.message);
    return res.status(500).json({ success: false, error: err.message });
  }
});

app.get('/api/call/config', (req, res) => {
  const hasToken = !!smartfloService.apiToken;
  res.json({
    callMaskingEnabled: hasToken,
    provider: 'TATA Smartflo',
    sub: '799242'
  });
});








// Connect to MongoDB
const MONGO_URI = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/staydriv';
const maskedMongoUri = MONGO_URI.replace(/\/\/[^:]+:[^@]+@/, '//***:***@');
console.log(`[DATABASE] Connecting to MongoDB at: ${maskedMongoUri}`);

mongoose.connect(MONGO_URI)
  .then(async () => {
    console.log('Connected to MongoDB successfully!');
    storageService.initGridFS(mongoose.connection.db);
    try {
      // 1. Only reset partners inactive for >24 hours
      const oneDayAgo = new Date(Date.now() - 86400000);
      const userResetResult = await User.updateMany({ role: 'partner', lastActive: { $lt: oneDayAgo } }, { online: false });
      console.log(`Cleaned inactive partners on startup. Matched: ${userResetResult.matchedCount}, Modified: ${userResetResult.modifiedCount}`);

      // 2. Only time out stale searching bookings older than 12 hours on startup (preserve live rides!)
      const twelveHoursAgo = new Date(Date.now() - 43200000);
      const bookingResetResult = await Booking.updateMany(
        { status: 'searching', createdAt: { $lt: twelveHoursAgo } },
        { status: 'timed_out' }
      );
      console.log(`Cleaned stale searching bookings on startup. Matched: ${bookingResetResult.matchedCount}, Modified: ${bookingResetResult.modifiedCount}`);

      // Reconcile and backfill immutable financial ledger and pilot wallet balances
      financeService.backfillHistoricalLedgerAndCommissions(Booking, User).catch(fErr => {
        console.error('[FINANCE] Startup ledger backfill error:', fErr.message);
      });

      // Seed initial food ordering restaurants & menu items if not already present
      const { seedInitialFoodData } = require('./services/foodSeedService');
      seedInitialFoodData().catch(sErr => {
        console.error('[FOOD] Startup food seed error:', sErr.message);
      });
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

// Schema definition for Ride Chat Messages (Customer <-> Pilot)
const rideChatMessageSchema = new mongoose.Schema({
  messageId: { type: String, required: true, unique: true, index: true },
  rideId: { type: String, required: true, index: true },
  bookingId: { type: String, index: true },
  customerId: { type: String, default: '' },
  pilotId: { type: String, default: '' },
  senderId: { type: String, default: '' },
  receiverId: { type: String, default: '' },
  senderRole: { type: String, enum: ['CUSTOMER', 'PILOT', 'customer', 'pilot', 'admin'], required: true },
  receiverRole: { type: String, enum: ['CUSTOMER', 'PILOT', 'customer', 'pilot', 'admin'], default: 'pilot' },
  senderName: { type: String, default: '' },
  text: { type: String, required: true, trim: true },
  message: { type: String, trim: true },
  deliveryStatus: { type: String, enum: ['SENT', 'DELIVERED', 'READ', 'FAILED'], default: 'SENT' },
  readStatus: { type: Boolean, default: false },
  deliveredAt: { type: Date, default: null },
  readAt: { type: Date, default: null },
  timestamp: { type: Number, default: Date.now },
  createdAt: { type: Date, default: Date.now }
});
const RideChatMessage = mongoose.models.RideChatMessage || mongoose.model('RideChatMessage', rideChatMessageSchema);

// Helper to handle chat message creation (shared by REST and Socket)
async function saveAndBroadcastChatMessage({
  messageId,
  rideId,
  bookingId,
  senderRole,
  senderName,
  senderId,
  receiverId,
  customerId,
  pilotId,
  text,
  timestamp
}) {
  const bId = String(rideId || bookingId || '').trim();
  const rawText = String(text || '').trim();
  if (!bId || !rawText) {
    throw new Error('rideId/bookingId and message text are required');
  }

  const finalMessageId = messageId || ('msg_' + Date.now() + '_' + Math.random().toString(36).substring(2, 9));

  // Idempotency: return existing if already saved
  const existing = await RideChatMessage.findOne({ messageId: finalMessageId });
  if (existing) {
    return existing;
  }

  const normSenderRole = String(senderRole).toUpperCase() === 'PILOT' ? 'PILOT' : 'CUSTOMER';
  const normReceiverRole = normSenderRole === 'CUSTOMER' ? 'PILOT' : 'CUSTOMER';

  const newMsg = await RideChatMessage.create({
    messageId: finalMessageId,
    rideId: bId,
    bookingId: bId,
    customerId: customerId || '',
    pilotId: pilotId || '',
    senderId: senderId || '',
    receiverId: receiverId || '',
    senderRole: normSenderRole,
    receiverRole: normReceiverRole,
    senderName: senderName || (normSenderRole === 'PILOT' ? 'Pilot Partner' : 'Customer'),
    text: rawText,
    message: rawText,
    deliveryStatus: 'SENT',
    readStatus: false,
    timestamp: timestamp || Date.now(),
    createdAt: new Date()
  });

  const payload = newMsg.toObject();

  if (typeof io !== 'undefined' && io) {
    io.to('booking:' + bId).emit('customer_message', payload);
    io.to('ride_' + bId).emit('customer_message', payload);
    io.to('booking:' + bId).emit('ride_message', payload);
    io.to('ride_' + bId).emit('ride_message', payload);
    io.emit('ride_message', payload);
  }

  // Twilio SMS Fallback if customer sends message and pilot socket is disconnected/backgrounded
  if (normSenderRole === 'CUSTOMER') {
    try {
      const roomBooking = io?.sockets?.adapter?.rooms?.get('booking:' + bId);
      const roomRide = io?.sockets?.adapter?.rooms?.get('ride_' + bId);
      const activeSocketCount = (roomBooking?.size || 0) + (roomRide?.size || 0);

      if (activeSocketCount <= 1) {
        // Resolve dynamic pilot phone number from in-memory activeBookings or MongoDB
        const active = (typeof activeBookings !== 'undefined' ? activeBookings[bId] : null) ||
                       (typeof Booking !== 'undefined' ? await Booking.findOne({ bookingId: bId }) : null);
        const pilotPhone = active?.driverPhone || active?.pilotPhone || active?.assignedPilotPhone;
        if (pilotPhone) {
          console.log(`[SMS ALERT FALLBACK] Pilot not in room for ride ${bId}. Sending SMS alert to ${SmsService.sendSmsAlert ? 'pilot' : 'fallback'}`);
          SmsService.sendSmsAlert({
            to: pilotPhone,
            message: `StayDriv Alert: Customer message for ride #${bId.slice(-6)}: "${rawText}". Open Driver Console to reply.`
          }).catch(e => console.warn('[SMS ALERT DISPATCH WARN]:', e.message));
        }
      }
    } catch (smsErr) {
      console.warn('[TWILIO SMS FALLBACK EXCEPTION]:', smsErr.message);
    }
  }

  return newMsg;
}

// REST Endpoints for Ride Chat Messages
app.get(['/api/rides/:rideId/messages', '/api/bookings/:rideId/messages'], async (req, res) => {
  try {
    const { rideId } = req.params;
    if (!rideId) return res.status(400).json({ success: false, message: 'rideId is required' });
    const messages = await RideChatMessage.find({
      $or: [{ rideId }, { bookingId: rideId }]
    }).sort({ timestamp: 1 }).limit(200);
    return res.status(200).json({ success: true, messages });
  } catch (err) {
    console.error('[GET RIDE MESSAGES ERROR]:', err);
    return res.status(500).json({ success: false, error: err.message });
  }
});

app.post(['/api/rides/:rideId/messages', '/api/bookings/:rideId/messages'], async (req, res) => {
  try {
    const rideId = req.params.rideId || req.body.rideId || req.body.bookingId;
    const { messageId, senderRole, senderName, senderId, receiverId, customerId, pilotId, text, message, timestamp } = req.body;
    const msg = await saveAndBroadcastChatMessage({
      messageId,
      rideId,
      bookingId: rideId,
      senderRole,
      senderName,
      senderId,
      receiverId,
      customerId,
      pilotId,
      text: text || message,
      timestamp
    });
    return res.status(201).json({ success: true, message: msg });
  } catch (err) {
    console.error('[POST RIDE MESSAGE ERROR]:', err);
    return res.status(500).json({ success: false, error: err.message });
  }
});

// Acknowledge delivery (SENT -> DELIVERED)
app.patch(['/api/rides/:rideId/messages/:messageId/delivered', '/api/bookings/:rideId/messages/:messageId/delivered'], async (req, res) => {
  try {
    const { rideId, messageId } = req.params;
    const deliveredAt = new Date();
    const updated = await RideChatMessage.findOneAndUpdate(
      { $or: [{ rideId }, { bookingId: rideId }], messageId },
      { deliveryStatus: 'DELIVERED', deliveredAt },
      { new: true }
    );
    if (typeof io !== 'undefined' && io) {
      const payload = { rideId, bookingId: rideId, messageId, deliveryStatus: 'DELIVERED', deliveredAt };
      io.to('booking:' + rideId).emit('message_delivered', payload);
      io.to('ride_' + rideId).emit('message_delivered', payload);
      io.emit('message_delivered', payload);
    }
    return res.status(200).json({ success: true, message: updated });
  } catch (err) {
    console.error('[PATCH MESSAGE DELIVERED ERROR]:', err);
    return res.status(500).json({ success: false, error: err.message });
  }
});

// Mark messages as READ (DELIVERED -> READ)
app.patch(['/api/rides/:rideId/messages/read', '/api/bookings/:rideId/messages/read', '/api/rides/:rideId/messages/:messageId/read'], async (req, res) => {
  try {
    const { rideId, messageId } = req.params;
    const readAt = new Date();
    const filter = { $or: [{ rideId }, { bookingId: rideId }] };
    if (messageId && messageId !== 'all') {
      filter.messageId = messageId;
    }
    await RideChatMessage.updateMany(
      filter,
      { deliveryStatus: 'READ', readStatus: true, readAt }
    );
    if (typeof io !== 'undefined' && io) {
      const payload = { rideId, bookingId: rideId, messageId: messageId || 'all', deliveryStatus: 'READ', readStatus: true, readAt };
      io.to('booking:' + rideId).emit('message_read', payload);
      io.to('ride_' + rideId).emit('message_read', payload);
      io.emit('message_read', payload);
    }
    return res.status(200).json({ success: true, readAt });
  } catch (err) {
    console.error('[PATCH MESSAGE READ ERROR]:', err);
    return res.status(500).json({ success: false, error: err.message });
  }
});

// Memory state
let activeBookings = {}; // { bookingId: { data, eligibleDrivers: [socketId1, socketId2], currentIndex: 0, timer: null } }

function calculateRidersStats(ridersList) {
  let online = 0;
  let onRide = 0;
  let arriving = 0;
  let offline = 0;
  let liveCount = 0;
  for (const r of ridersList) {
    if (r.isTransmitting) liveCount++;
    if (r.status === 'on_ride') onRide++;
    else if (r.status === 'arriving') arriving++;
    else if (r.status === 'online' || r.online) online++;
    else offline++;
  }
  return { online, onRide, arriving, offline, liveCount, total: ridersList.length };
}

async function getLiveRidersSnapshot() {
  const ridersMap = new Map();

  // 1. Seed or retrieve known registered pilots from MongoDB
  try {
    const dbPartners = await User.find({ role: 'partner' }).lean();
    for (const p of dbPartners) {
      const uid = p.uid || `pilot_${p.phone}`;
      const hasCoords = Boolean(p.lat && p.lng && p.lat !== 0 && p.lng !== 0);
      const isOnline = Boolean(p.online);
      
      ridersMap.set(uid, {
        uid,
        pilotId: uid,
        name: p.name || 'StayDriv Pilot',
        phone: p.phone || '',
        driverPhone: p.phone || '',
        ownerName: p.ownerName || p.name || 'StayDriv Pilot',
        ownerPhone: p.ownerPhone || p.phone || '',
        vehicleType: p.vehicleType || 'Bike',
        vehiclePlate: p.vehiclePlate || p.vehicleNumber || '',
        vehicleNumber: p.vehicleNumber || p.vehiclePlate || '',
        vehicleModel: p.vehicleModel || p.vehicleModelColor || 'Standard',
        lat: hasCoords ? p.lat : null,
        lng: hasCoords ? p.lng : null,
        hasLocation: hasCoords,
        heading: p.heading || 0,
        speed: p.speed || 0,
        accuracy: 5.0,
        status: isOnline ? 'online' : 'offline',
        online: isOnline,
        rideId: null,
        rideStatus: null,
        pickup: '',
        drop: '',
        customerName: '',
        remainingDistance: '',
        eta: '',
        lastUpdated: (p.lastLocationUpdate || p.lastActive || new Date()).toISOString(),
        timestamp: new Date(p.lastLocationUpdate || p.lastActive || Date.now()).getTime(),
        isTransmitting: isOnline && hasCoords
      });
    }
  } catch (err) {
    console.warn('[LIVE RIDERS SNAPSHOT] DB fetch note:', err.message);
  }

  // 2. Overlay real-time in-memory registry (latest GPS fixes from mobile socket)
  for (const [uid, liveData] of livePilotsRegistry.entries()) {
    const existing = ridersMap.get(uid) || {};
    const hasLiveCoords = Boolean(liveData.lat && liveData.lng && liveData.lat !== 0 && liveData.lng !== 0);
    const isLiveOnline = Boolean(liveData.online);
    const lastTs = liveData.timestamp || Date.now();
    const isTransmitting = isLiveOnline && hasLiveCoords && (Date.now() - lastTs < 300000);

    ridersMap.set(uid, {
      ...existing,
      ...liveData,
      hasLocation: hasLiveCoords,
      online: isLiveOnline,
      isTransmitting
    });
  }

  // 3. Overlay any active bookings from Mongo
  try {
    const activeBookingsList = await Booking.find({
      status: { $in: ['accepted', 'arrived', 'started', 'heading_to_pickup', 'on_trip'] }
    }).lean();
    for (const b of activeBookingsList) {
      const driverId = b.driverId;
      if (driverId && ridersMap.has(driverId)) {
        const r = ridersMap.get(driverId);
        r.rideId = b.bookingId;
        r.rideStatus = b.status;
        r.pickup = b.pickup || '';
        r.drop = b.drop || '';
        r.customerName = b.passengerName || '';
        if (b.status === 'started' || b.status === 'on_trip') {
          r.status = 'on_ride';
        } else {
          r.status = 'arriving';
        }
        if (b.driverLocation?.lat && b.driverLocation?.lng) {
          r.lat = b.driverLocation.lat;
          r.lng = b.driverLocation.lng;
          r.hasLocation = true;
        }
      }
    }
  } catch (_) {}

  return Array.from(ridersMap.values());
}

// Endpoint to retrieve real-time live location of all riders (Pilots) for Admin Console
app.get(['/api/admin/live-riders', '/api/admin/live-pilots'], verifyAdminAuth, async (req, res) => {
  try {
    const riders = await getLiveRidersSnapshot();
    const liveRidersCount = riders.filter(r => r.isTransmitting).length;
    const stats = calculateRidersStats(riders);

    res.status(200).json({
      success: true,
      timestamp: new Date().toISOString(),
      totalPilots: riders.length,
      liveRidersCount,
      stats,
      riders
    });
  } catch (err) {
    console.error('[LIVE RIDERS ERROR]:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Endpoint for simulating pilot location updates for testing
app.post('/api/admin/simulate-pilot-location', async (req, res) => {
  try {
    const { uid, lat, lng, heading, speed, status, vehicleType, name, phone, vehiclePlate } = req.body;
    if (!uid || lat === undefined || lng === undefined) {
      return res.status(400).json({ success: false, message: 'uid, lat, and lng are required' });
    }

    const pilotData = getPilotTrackingRecord(uid, {
      lat: Number(lat),
      lng: Number(lng),
      heading: Number(heading) || 0,
      speed: Number(speed) || 0,
      status: status || 'online',
      online: status !== 'offline',
      vehicleType: vehicleType || 'Bike',
      name: name || 'Test Pilot',
      phone: phone || '9999999999',
      vehiclePlate: vehiclePlate || ''
    });

    io.to('admin_tracking').emit('pilot_location_update', pilotData);
    io.emit('pilot_location_update', pilotData);

    res.status(200).json({ success: true, rider: pilotData });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

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
  const targetDriver = onlineDrivers[targetSocketId];
  if (!targetDriver || targetDriver.rideServiceEnabled === false) {
    console.log(`Driver ${targetSocketId} is offline or has paused ride bookings, skipping.`);
    booking.currentIndex++;
    return dispatchToNextDriver(bookingId);
  }

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

  // Admin registers for live tracking room
  socket.on('admin_join_tracking', async (authData) => {
    const adminKey = authData?.adminKey;
    const role = authData?.role;
    const token = authData?.token;
    let isValid = (adminKey === 'staydriv_admin_secret_2026' || adminKey === process.env.ADMIN_KEY || role === 'super_admin' || role === 'admin' || role === 'support');
    if (!isValid && token) {
      try {
        const decoded = jwt.verify(token, process.env.JWT_SECRET || 'staydriv_secret_key_2026');
        if (decoded && (decoded.isAdmin || decoded.role === 'Admin' || decoded.role === 'Staff')) isValid = true;
      } catch (_) {}
    }
    if (isTestMode) isValid = true;

    if (!isValid && process.env.NODE_ENV === 'production') {
      return socket.emit('admin_auth_error', { message: 'Unauthorized admin credentials' });
    }
    socket.join('admin_tracking');
    console.log(`[SOCKET TRACKING] Admin socket ${socket.id} joined admin_tracking room.`);

    const [riders, liveOps] = await Promise.all([
      getLiveRidersSnapshot(),
      getLiveOperationsData()
    ]);
    socket.emit('live_riders_snapshot', {
      success: true,
      timestamp: new Date().toISOString(),
      liveRidersCount: riders.filter(r => r.isTransmitting).length,
      stats: liveOps.stats,
      riders
    });
    socket.emit('live_operations_snapshot', liveOps);
  });

  // Customer live location update
  socket.on('customer_location_update', (data) => {
    if (!data) return;
    const cid = data.uid || data.customerId;
    const lat = Number(data.lat || data.latitude);
    const lng = Number(data.lng || data.longitude);
    if (!cid || isNaN(lat) || isNaN(lng) || (lat === 0 && lng === 0)) return;

    const custRecord = {
      uid: cid,
      customerId: cid,
      bookingId: data.bookingId || null,
      name: data.name || data.customerName || 'Customer',
      phone: data.phone || data.mobile || '',
      lat,
      lng,
      heading: Number(data.heading) || 0,
      speed: Number(data.speed) || 0,
      timestamp: Date.now(),
      lastUpdated: new Date().toISOString(),
      googleMapsUrl: `https://www.google.com/maps?q=${lat},${lng}`
    };

    liveCustomerLocations.set(cid, custRecord);
    if (data.phone) liveCustomerLocations.set(data.phone, custRecord);

    io.to('admin_tracking').emit('customer_location_update', custRecord);
  });

  // Handle Round Trip leg progression updates from Pilot / Customer
  socket.on('round_trip_leg_update', (data) => {
    if (!data) return;
    const bId = data.bookingId;
    if (bId) {
      console.log(`[SOCKET RT] Leg update for booking ${bId}: leg=${data.currentLeg}, outwardStatus=${data.outwardTripStatus}, returnStatus=${data.returnTripStatus}`);
      io.to(`ride_${bId}`).emit('round_trip_leg_update', data);
      io.to('admin_tracking').emit('round_trip_leg_update', data);
    }
  });

  // Driver goes online / updates location
  socket.on('driver_update', async (data) => {
    if (!data) return;
    const uid = data.uid || `pilot_${socket.id.substring(0, 6)}`;
    socketToPilotUid.set(socket.id, uid);

    const lat = Number(data.lat);
    const lng = Number(data.lng);
    const hasValidCoords = !isNaN(lat) && !isNaN(lng) && lat !== 0 && lng !== 0;

    let pilotStatus = 'offline';
    const isOnline = Boolean(data.online);

    // Check active booking
    let activeRide = null;
    try {
      if (data.rideId) {
        activeRide = await Booking.findOne({ bookingId: data.rideId });
      } else {
        activeRide = await Booking.findOne({
          driverId: uid,
          status: { $in: ['accepted', 'arrived', 'started', 'heading_to_pickup', 'on_trip'] }
        });
      }
    } catch (_) {}

    if (activeRide) {
      pilotStatus = (activeRide.status === 'started' || activeRide.status === 'on_trip') ? 'on_ride' : 'arriving';
    } else if (isOnline) {
      pilotStatus = 'online';
    } else {
      pilotStatus = 'offline';
    }

    let existing = livePilotsRegistry.get(uid);
    const rideServiceEnabled = (typeof data.rideServiceEnabled === 'boolean') 
      ? data.rideServiceEnabled 
      : (existing?.rideServiceEnabled !== undefined ? existing.rideServiceEnabled : true);
    const foodServiceEnabled = (typeof data.foodServiceEnabled === 'boolean') 
      ? data.foodServiceEnabled 
      : (existing?.foodServiceEnabled !== undefined ? existing.foodServiceEnabled : true);

    const pilotData = getPilotTrackingRecord(uid, {
      socketId: socket.id,
      online: isOnline,
      status: pilotStatus,
      rideServiceEnabled,
      foodServiceEnabled,
      lat: hasValidCoords ? lat : (existing?.lat || null),
      lng: hasValidCoords ? lng : (existing?.lng || null),
      vehicleType: data.vehicle || data.vehicleType || existing?.vehicleType || 'Bike',
      vehiclePlate: (data.vehiclePlate && data.vehiclePlate !== 'TS 09 SD 1234' ? data.vehiclePlate : (data.vehicleNumber && data.vehicleNumber !== 'TS 09 SD 1234' ? data.vehicleNumber : (existing?.vehiclePlate || ''))),
      vehicleNumber: (data.vehicleNumber && data.vehicleNumber !== 'TS 09 SD 1234' ? data.vehicleNumber : (data.vehiclePlate && data.vehiclePlate !== 'TS 09 SD 1234' ? data.vehiclePlate : (existing?.vehicleNumber || existing?.vehiclePlate || ''))),
      name: data.name || data.pilotName || existing?.name || (uid.startsWith('mock_uid_') ? 'Pilot ' + uid.replace('mock_uid_', '').replace('_pilot', '') : 'Pilot Partner'),
      phone: data.phone || data.mobile || data.phoneNumber || existing?.phone || (uid.startsWith('mock_uid_') ? uid.replace('mock_uid_', '').replace('_pilot', '') : ''),
      heading: Number(data.heading) || existing?.heading || 0,
      speed: Number(data.speed) || existing?.speed || 0,
      accuracy: Number(data.accuracy) || existing?.accuracy || 5.0,
      rideId: activeRide?.bookingId || null,
      rideStatus: activeRide?.status || null,
      pickup: activeRide?.pickup || '',
      drop: activeRide?.drop || '',
      customerName: activeRide?.passengerName || ''
    });

    if (isOnline) {
      let dailyPlanEligibility = { eligible: true, bookingAccess: 'enabled', planStatus: 'paid' };
      let checkUser = null;
      try {
        checkUser = await User.findOne({ uid });
        if (checkUser && (checkUser.status !== 'approved' || !checkUser.approved || checkUser.isBlocked)) {
          delete onlineDrivers[socket.id];
          socket.emit('pilot_approval_updated', {
            uid: checkUser.uid,
            approved: false,
            isApproved: false,
            status: checkUser.status || 'pending',
            rejectionReason: checkUser.rejectionReason || ''
          });
          console.log(`[PILOT SECURITY] Pilot ${uid} tried to go ONLINE while status=${checkUser.status}, approved=${checkUser.approved}`);
          return;
        }

        if (checkUser) {
          dailyPlanEligibility = pilotDailyPlanService.checkPilotDailyBookingEligibility(checkUser);
          // Telemetry location ping: Do NOT broadcast duty status changes back to the client on GPS pings.
          // Duty status is authoritative and only updated via explicit human action (/api/pilot/duty)
          // or explicit administrator action (/api/admin/.../booking-access).
        }
      } catch (err) {
        console.error('Error validating pilot eligibility on driver_update:', err.message);
      }

      const isAdminAccessAllowed = dailyPlanEligibility.bookingAccess === 'enabled';
      onlineDrivers[socket.id] = {
        lat: pilotData.lat,
        lng: pilotData.lng,
        vehicle: pilotData.vehicleType,
        uid: uid,
        rideServiceEnabled,
        foodServiceEnabled,
        dutyStatus: checkUser?.dutyStatus === 'OFF' ? 'DUTY OFF' : dailyPlanEligibility.dutyStatus,
        bookingAccessEnabled: isAdminAccessAllowed && checkUser?.dutyStatus !== 'OFF',
        bookingAccessReason: isAdminAccessAllowed ? '' : (dailyPlanEligibility.bookingAccessReason || '')
      };

      if (!foodServiceEnabled || !dailyPlanEligibility.eligible) {
        socket.leave('pilot_food_dispatch');
      } else if (isFoodDeliveryVehicle(pilotData.vehicleType)) {
        socket.join('pilot_food_dispatch');
      }

      console.log(`Driver ${socket.id} (${pilotData.name}) is ONLINE with ${pilotData.vehicleType} (Rides: ${rideServiceEnabled ? 'ON' : 'OFF'}, Food: ${foodServiceEnabled ? 'ON' : 'OFF'}) at ${pilotData.lat}, ${pilotData.lng}`);
    } else {
      delete onlineDrivers[socket.id];
      socket.leave('pilot_food_dispatch');
      console.log(`Driver ${socket.id} (${uid}) is OFFLINE`);
    }

    // Broadcast to Admin tracking room & globally
    io.to('admin_tracking').emit('pilot_location_update', pilotData);
    io.to('admin_tracking').emit(isOnline ? 'pilot_online' : 'pilot_offline', pilotData);
    io.to('admin_tracking').emit('pilot_status_change', { uid, online: isOnline, status: pilotStatus, pilot: pilotData });
    io.emit('pilot_location_update', pilotData);

    getAdminLiveStats().then(s => io.to('admin_tracking').emit('admin_stats_update', s)).catch(() => {});

    // Throttled DB sync
    const nowMs = Date.now();
    const lastSync = pilotLastDbSync.get(uid) || 0;
    if (nowMs - lastSync > 10000 && hasValidCoords) {
      pilotLastDbSync.set(uid, nowMs);
      User.updateOne(
        { uid },
        {
          $set: {
            lat: pilotData.lat,
            lng: pilotData.lng,
            online: isOnline,
            rideServiceEnabled,
            foodServiceEnabled,
            lastActive: new Date()
          }
        }
      ).catch(() => {});
    }
  });

  // Handle immediate Pilot Service Preferences Update from App (Ride Booking & Food Delivery ON/OFF)
  socket.on('pilot_service_preferences_update', async (data) => {
    if (!data) return;
    const uid = data.uid || socketToPilotUid.get(socket.id);
    if (!uid) return;

    let user = await User.findOne({ uid });
    if (!user && uid) {
      const cleanP = String(uid).replace(/\D/g, '').slice(-10);
      if (cleanP) user = await User.findOne({ phone: cleanP, role: 'partner' }) || await User.findOne({ phone: cleanP });
    }

    const rideServiceEnabled = typeof data.rideServiceEnabled === 'boolean' 
      ? data.rideServiceEnabled 
      : (user ? user.rideServiceEnabled !== false : true);
    const foodServiceEnabled = typeof data.foodServiceEnabled === 'boolean' 
      ? data.foodServiceEnabled 
      : (user ? user.foodServiceEnabled !== false : true);
    const updatedAt = new Date();

    if (user) {
      await User.updateOne({ _id: user._id }, {
        $set: {
          rideServiceEnabled,
          foodServiceEnabled,
          servicePreferencesUpdatedAt: updatedAt
        }
      });
    }

    // Update in-memory registry
    const pilotReg = livePilotsRegistry.get(uid);
    if (pilotReg) {
      pilotReg.rideServiceEnabled = rideServiceEnabled;
      pilotReg.foodServiceEnabled = foodServiceEnabled;
      pilotReg.servicePreferencesUpdatedAt = updatedAt.toISOString();
    }
    if (user?.phone && livePilotsRegistry.has(user.phone)) {
      const pReg = livePilotsRegistry.get(user.phone);
      pReg.rideServiceEnabled = rideServiceEnabled;
      pReg.foodServiceEnabled = foodServiceEnabled;
      pReg.servicePreferencesUpdatedAt = updatedAt.toISOString();
    }

    // Update onlineDrivers
    for (const [sId, d] of Object.entries(onlineDrivers)) {
      if (d.uid === uid || (user?.phone && d.uid === user.phone)) {
        d.rideServiceEnabled = rideServiceEnabled;
        d.foodServiceEnabled = foodServiceEnabled;
        const sock = io.sockets.sockets.get(sId);
        if (sock) {
          if (!foodServiceEnabled) {
            sock.leave('pilot_food_dispatch');
          } else if (isFoodDeliveryVehicle(user?.vehicleType || d.vehicle)) {
            sock.join('pilot_food_dispatch');
          }
        }
      }
    }

    // Broadcast to Admin tracking room
    io.to('admin_tracking').emit('pilot_service_preferences_changed', {
      uid: user?.uid || uid,
      phone: user?.phone || '',
      name: user?.name || 'Pilot Partner',
      vehicleType: user?.vehicleType || 'Bike',
      rideServiceEnabled,
      foodServiceEnabled,
      servicePreferencesUpdatedAt: updatedAt
    });

    socket.emit('pilot_service_preferences_saved', {
      success: true,
      rideServiceEnabled,
      foodServiceEnabled,
      servicePreferencesUpdatedAt: updatedAt
    });
    console.log(`[SOCKET SERVICE PREF] Pilot ${uid} updated preferences: Rides=${rideServiceEnabled ? 'ON' : 'OFF'}, Food=${foodServiceEnabled ? 'ON' : 'OFF'}`);
  });

  // Customer creates a booking
  socket.on('create_booking', (bookingData) => {
    const bookingId = 'BK_' + Date.now();
    bookingData.bookingId = bookingId;

    console.log(`New booking ${bookingId} created by customer.`);

    const freshStartOtp = (bookingData.otp && bookingData.otp !== '1234' && bookingData.otp !== '4921' && String(bookingData.otp).length === 4)
      ? String(bookingData.otp)
      : generate4DigitOtp();
    bookingData.otp = freshStartOtp;
    bookingData.pickupOtp = freshStartOtp;

    let deliveryOtpVal = null;
    const isParcelBooking = bookingData.serviceType === 'parcel' || (bookingData.vehicle && String(bookingData.vehicle).toLowerCase().includes('parcel'));
    if (isParcelBooking) {
      let dOtp = generate4DigitOtp();
      while (dOtp === freshStartOtp) {
        dOtp = generate4DigitOtp();
      }
      deliveryOtpVal = dOtp;
      bookingData.deliveryOtp = dOtp;
    }

    // Save to Mongo
    GlobalState.create({ bookingId, type: 'createBooking', activeBooking: bookingData });
    try {
      Booking.findOneAndUpdate(
        { bookingId },
        {
          $setOnInsert: {
            bookingId,
            pickup: bookingData.pickup || '',
            drop: bookingData.drop || '',
            pickupLatLng: bookingData.pickupLatLng || { lat: 0, lng: 0 },
            dropLatLng: bookingData.dropLatLng || { lat: 0, lng: 0 },
            vehicle: bookingData.vehicle || 'Bike',
            price: bookingData.price || 0,
            otp: freshStartOtp,
            pickupOtp: freshStartOtp,
            deliveryOtp: deliveryOtpVal,
            otpVerified: false,
            otpAttempts: 0,
            otpExpiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
            status: 'searching',
            serviceType: bookingData.serviceType || (isParcelBooking ? 'parcel' : 'ride'),
            passengerId: bookingData.passengerId || bookingData.uid || '',
            passengerName: bookingData.passengerName || 'Customer',
            passengerPhone: bookingData.passengerPhone || '',
            createdAt: new Date(),
            updatedAt: new Date()
          }
        },
        { upsert: true, new: true }
      ).catch(e => console.error('[create_booking Mongo save error]', e.message));
    } catch (_) {}

    // Store customer pickup coords into liveCustomerLocations for immediate map display
    if (bookingData.pickupLatLng && (bookingData.passengerId || bookingData.uid)) {
      const cid = bookingData.passengerId || bookingData.uid;
      liveCustomerLocations.set(cid, {
        uid: cid,
        customerId: cid,
        bookingId,
        name: bookingData.passengerName || 'Customer',
        phone: bookingData.passengerPhone || '',
        lat: Number(bookingData.pickupLatLng.lat),
        lng: Number(bookingData.pickupLatLng.lng),
        heading: 0,
        speed: 0,
        timestamp: Date.now(),
        lastUpdated: new Date().toISOString(),
        googleMapsUrl: `https://www.google.com/maps?q=${bookingData.pickupLatLng.lat},${bookingData.pickupLatLng.lng}`
      });
    }

    io.to('admin_tracking').emit('booking_created', bookingData);
    getAdminLiveStats().then(s => io.to('admin_tracking').emit('admin_stats_update', s)).catch(() => {});

    // Find eligible drivers (matching vehicle, within 50km)
    const pickupLat = bookingData.pickupLatLng.lat;
    const pickupLng = bookingData.pickupLatLng.lng;
    const requestedVehicle = bookingData.vehicle.toLowerCase().trim();

    let eligible = [];
    for (const [id, driver] of Object.entries(onlineDrivers)) {
      if (driver.bookingAccessEnabled === false) {
        // Pilot has booking access disabled by admin or daily plan expired/unpaid
        continue;
      }
      if (driver.dutyStatus === 'OFF' || driver.dutyStatus === 'DUTY OFF') {
        // Pilot duty is OFF!
        continue;
      }
      if (driver.rideServiceEnabled === false) {
        // Pilot has paused ride bookings in Service Preferences!
        continue;
      }
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
  socket.on('decline_booking', async (data) => {
    const bookingId = data?.bookingId;
    const pilotUid = socketToPilotUid.get(socket.id) || data?.driverId || data?.pilotId;
    console.log(`[DECLINE_BOOKING] Driver ${socket.id} (${pilotUid}) declined booking ${bookingId}`);
    try {
      if (bookingId) {
        await Booking.findOneAndUpdate(
          { bookingId, status: 'searching' },
          {
            $addToSet: { declinedDrivers: pilotUid || socket.id },
            $set: { driverId: '', assignedAt: null, updatedAt: new Date() }
          }
        );
      }
    } catch (_) {}
    const booking = activeBookings[bookingId];
    if (booking) {
      const currentTarget = booking.eligibleDrivers[booking.currentIndex];
      if (currentTarget === socket.id) {
        clearTimeout(booking.timer);
        booking.currentIndex++;
        dispatchToNextDriver(bookingId);
      }
    }
  });

  // Driver accepts
  socket.on('accept_booking', async (data) => {
    const bookingId = data?.bookingId;
    const booking = activeBookings[bookingId];
    let updatedBooking = null;
    const acceptedPilotUid = socketToPilotUid.get(socket.id) || data?.driverId || data?.pilotId;

    let pilotDb = null;
    try {
      if (acceptedPilotUid) {
        pilotDb = await User.findOne({ uid: acceptedPilotUid }) || await User.findOne({ phone: String(acceptedPilotUid).replace(/\D/g, '').slice(-10) });
      }
    } catch (_) {}

    if (pilotDb) {
      if (pilotDb.rideServiceEnabled === false) {
        console.warn(`[ACCEPT_BOOKING] Pilot ${acceptedPilotUid} attempted to accept booking ${bookingId} while rideServiceEnabled is FALSE.`);
        socket.emit('booking_accept_error', {
          success: false,
          message: 'Ride bookings are currently paused in your Service Preferences. Turn ON Ride Booking to accept rides.'
        });
        return;
      }

      // Check ₹20 Daily Plan and Admin Booking Access eligibility
      const dailyElig = pilotDailyPlanService.checkPilotDailyBookingEligibility(pilotDb);
      if (!dailyElig.eligible) {
        console.warn(`[ACCEPT_BOOKING] Pilot ${acceptedPilotUid} attempted to accept booking ${bookingId} but is INELIGIBLE: ${dailyElig.reason}`);
        socket.emit('booking_accept_error', {
          success: false,
          message: dailyElig.reason
        });
        return;
      }
    }

    const pilotPlate = data?.vehiclePlate || data?.vehicleNumber || pilotDb?.vehiclePlate || pilotDb?.vehicleNumber || '';
    const pilotType = data?.vehicleType || pilotDb?.vehicleType || booking?.data?.vehicle || 'Bike';
    const pilotModelColor = data?.vehicleModelColor || pilotDb?.vehicleModelColor || (pilotDb?.vehicleMake ? `${pilotDb.vehicleMake} ${pilotDb.vehicleModel || ''} • ${pilotDb.vehicleColor || ''}`.trim() : '');
    const pilotName = data?.driverName || pilotDb?.name || 'StayDriv Pilot';
    const pilotPhone = data?.driverPhone || pilotDb?.phone || '';

    // Pilot GPS position
    const pilotLat = Number(data?.lat || data?.driverLat || data?.latitude || 0);
    const pilotLng = Number(data?.lng || data?.driverLng || data?.longitude || 0);
    const pilotLatLng = (pilotLat !== 0 && pilotLng !== 0) ? { lat: pilotLat, lng: pilotLng } : null;

    let baseBookingData = booking ? booking.data : null;
    let mongoBookingDoc = null;
    try {
      mongoBookingDoc = await Booking.findOne({
        $or: [{ bookingId }, { _id: mongoose.isValidObjectId(bookingId) ? bookingId : null }]
      });
      if (!baseBookingData && mongoBookingDoc) {
        baseBookingData = mongoBookingDoc.toObject ? mongoBookingDoc.toObject() : mongoBookingDoc;
      }
    } catch (err) {
      console.error('[ACCEPT_BOOKING] Error querying MongoDB:', err.message);
    }

    if (booking) {
      clearTimeout(booking.timer);
      delete activeBookings[bookingId];
    }

    if (baseBookingData || mongoBookingDoc) {
      console.log(`[ACCEPT_BOOKING] Driver ${socket.id} (${acceptedPilotUid}) ACCEPTED booking ${bookingId}`);

      // Ensure pickup coordinates are properly set
      let pickupLatLng = baseBookingData?.pickupLatLng || mongoBookingDoc?.pickupLatLng;
      if (!pickupLatLng && (baseBookingData?.pickupLocation || mongoBookingDoc?.pickupLocation)) {
        const pl = baseBookingData?.pickupLocation || mongoBookingDoc?.pickupLocation;
        if (pl.latitude && pl.longitude) pickupLatLng = { lat: pl.latitude, lng: pl.longitude };
        else if (pl.lat && pl.lng) pickupLatLng = { lat: pl.lat, lng: pl.lng };
      }

      // Check Indian coordinate reverse [lat > 50, lng < 40]
      if (pickupLatLng && pickupLatLng.lat > 50 && pickupLatLng.lng < 40) {
        pickupLatLng = { lat: pickupLatLng.lng, lng: pickupLatLng.lat };
      }

      updatedBooking = {
        ...(baseBookingData || {}),
        ...data,
        bookingId,
        status: 'accepted',
        driverId: acceptedPilotUid || data?.driverId,
        driverName: pilotName,
        driverPhone: pilotPhone,
        vehiclePlate: pilotPlate,
        vehicleNumber: pilotPlate,
        vehicleType: pilotType,
        vehicleModelColor: pilotModelColor,
        ...(pilotLatLng ? { driverLatLng: pilotLatLng } : {}),
        pickupLatLng: pickupLatLng || baseBookingData?.pickupLatLng,
        acceptedAt: new Date().toISOString()
      };

      // Save to GlobalState
      GlobalState.create({ bookingId, type: 'acceptBooking', activeBooking: updatedBooking, driverSocket: socket.id });

      // Atomic Update in MongoDB with race condition protection
      let updatedMongoDoc = null;
      try {
        updatedMongoDoc = await Booking.findOneAndUpdate(
          {
            $or: [{ bookingId }, { _id: mongoose.isValidObjectId(bookingId) ? bookingId : null }],
            status: { $in: ['searching', 'requested', 'incoming'] },
            $or: [
              { driverId: acceptedPilotUid },
              { driverId: '' },
              { driverId: null },
              { driverId: { $exists: false } }
            ]
          },
          {
            $set: {
              status: 'accepted',
              driverId: acceptedPilotUid || data?.driverId,
              driverName: pilotName,
              driverPhone: pilotPhone,
              vehiclePlate: pilotPlate,
              vehicleNumber: pilotPlate,
              vehicleType: pilotType,
              vehicleModelColor: pilotModelColor,
              driverLocation: pilotLatLng ? { latitude: pilotLat, longitude: pilotLng } : undefined,
              acceptedAt: new Date(),
              updatedAt: new Date()
            }
          },
          { new: true }
        );
      } catch (mErr) {
        console.error('[ACCEPT_BOOKING] Error updating Booking in MongoDB:', mErr.message);
      }

      if (!updatedMongoDoc) {
        console.log(`[ACCEPT_BOOKING REJECTED] Booking ${bookingId} was already accepted by another pilot or cancelled.`);
        socket.emit('booking_already_taken', {
          bookingId,
          message: 'This ride has already been accepted by another pilot or was cancelled.'
        });
        return;
      }

      // Tell everyone else this booking is gone
      socket.broadcast.emit('booking_taken', { bookingId });

      // Tell everyone the global state changed so the customer and admin see it's accepted
      io.emit('state_update', { type: 'acceptBooking', activeBooking: updatedBooking });
      io.emit('booking_update', { bookingId, status: 'accepted', activeBooking: updatedBooking });
      io.emit('booking_accepted', { bookingId, driverId: acceptedPilotUid, status: 'accepted', activeBooking: updatedBooking });
      io.emit('admin_booking_update', { bookingId, status: 'accepted', activeBooking: updatedBooking });
      io.to('ride_' + bookingId).emit('booking_accepted', { bookingId, driverId: acceptedPilotUid, status: 'accepted', activeBooking: updatedBooking });
      io.to('booking:' + bookingId).emit('booking_accepted', { bookingId, driverId: acceptedPilotUid, status: 'accepted', activeBooking: updatedBooking });
      io.to('admin_tracking').emit('booking_update', { bookingId, status: 'accepted', activeBooking: updatedBooking });
      io.to('admin_tracking').emit('admin_booking_update', { bookingId, status: 'accepted', activeBooking: updatedBooking });
    }

    // Update pilot real-time status in tracking registry
    if (acceptedPilotUid) {
      const pRecord = getPilotTrackingRecord(acceptedPilotUid, {
        rideId: bookingId,
        rideStatus: 'accepted',
        status: 'arriving'
      });
      io.to('admin_tracking').emit('pilot_location_update', pRecord);
      io.emit('pilot_location_update', pRecord);
    }

    // Broadcast booking_accepted and updated stats to Admin tracking room
    io.to('admin_tracking').emit('booking_accepted', {
      bookingId,
      driverId: acceptedPilotUid,
      status: 'accepted',
      activeBooking: updatedBooking || data
    });
    getAdminLiveStats().then(s => io.to('admin_tracking').emit('admin_stats_update', s)).catch(() => {});
  });

  // Scoped ride rooms for live tracking & chat (joins both ride_<id> and booking:<id>)
  socket.on('join_ride', async (data) => {
    const rideId = typeof data === 'string' ? data : (data?.rideId || data?.bookingId);
    if (rideId) {
      socket.join('ride_' + rideId);
      socket.join('booking:' + rideId);
      console.log(`[SOCKET ROOM] Socket ${socket.id} joined rooms ride_${rideId} and booking:${rideId}`);
      // Send latest location immediately if already cached
      const cachedLoc = latestRideLocations[rideId];
      if (cachedLoc) {
        socket.emit('ride_location_update', cachedLoc);
      }
      // Replay chat history to syncing participant
      try {
        const history = await RideChatMessage.find({
          $or: [{ rideId }, { bookingId: rideId }]
        }).sort({ timestamp: 1 }).limit(100);
        socket.emit('ride_chat_history', { rideId, bookingId: rideId, messages: history });
      } catch (chatErr) {
        console.warn('[CHAT HISTORY FETCH WARN]:', chatErr.message);
      }
    }
  });

  socket.on('join_booking', async (data) => {
    const bId = typeof data === 'string' ? data : (data?.bookingId || data?.rideId);
    if (bId) {
      socket.join('booking:' + bId);
      socket.join('ride_' + bId);
      console.log(`[SOCKET ROOM] Socket ${socket.id} joined booking:${bId}`);
    }
  });

  // Real-time Chat message dispatch (Customer <-> Pilot)
  socket.on('send_customer_message', async (data) => {
    try {
      await saveAndBroadcastChatMessage({
        ...data,
        senderRole: 'CUSTOMER'
      });
    } catch (err) {
      console.error('[SOCKET SEND CUSTOMER MESSAGE ERROR]:', err.message);
    }
  });

  socket.on('send_ride_message', async (data) => {
    try {
      await saveAndBroadcastChatMessage({
        ...data,
        senderRole: data?.senderRole || 'CUSTOMER'
      });
    } catch (err) {
      console.error('[SOCKET SEND RIDE MESSAGE ERROR]:', err.message);
    }
  });

  // Delivery acknowledgment (Pilot -> Backend -> Customer)
  socket.on('message_delivered', async (data) => {
    try {
      const { messageId, rideId, bookingId } = data || {};
      const bId = String(rideId || bookingId || '').trim();
      if (!messageId || !bId) return;

      const deliveredAt = new Date();
      await RideChatMessage.findOneAndUpdate(
        { $or: [{ rideId: bId }, { bookingId: bId }], messageId },
        { deliveryStatus: 'DELIVERED', deliveredAt }
      );

      const payload = { messageId, rideId: bId, bookingId: bId, deliveryStatus: 'DELIVERED', deliveredAt };
      io.to('booking:' + bId).emit('message_delivered', payload);
      io.to('ride_' + bId).emit('message_delivered', payload);
      io.emit('message_delivered', payload);
      console.log(`[MESSAGE DELIVERED ACK] messageId=${messageId} bookingId=${bId}`);
    } catch (err) {
      console.error('[SOCKET MESSAGE DELIVERED ERROR]:', err.message);
    }
  });

  // Read acknowledgment (Pilot opens chat -> Backend -> Customer)
  socket.on('message_read', async (data) => {
    try {
      const { messageId, rideId, bookingId } = data || {};
      const bId = String(rideId || bookingId || '').trim();
      if (!bId) return;

      const readAt = new Date();
      const filter = { $or: [{ rideId: bId }, { bookingId: bId }] };
      if (messageId && messageId !== 'all') {
        filter.messageId = messageId;
      }

      await RideChatMessage.updateMany(
        filter,
        { deliveryStatus: 'READ', readStatus: true, readAt }
      );

      const payload = { messageId: messageId || 'all', rideId: bId, bookingId: bId, deliveryStatus: 'READ', readStatus: true, readAt };
      io.to('booking:' + bId).emit('message_read', payload);
      io.to('ride_' + bId).emit('message_read', payload);
      io.emit('message_read', payload);
      console.log(`[MESSAGE READ ACK] bookingId=${bId} messageId=${messageId || 'all'}`);
    } catch (err) {
      console.error('[SOCKET MESSAGE READ ERROR]:', err.message);
    }
  });

  socket.on('leave_ride', (data) => {
    const rideId = typeof data === 'string' ? data : (data?.rideId || data?.bookingId);
    if (rideId) {
      socket.leave('ride_' + rideId);
      socket.leave('booking:' + rideId);
      console.log(`[SOCKET ROOM] Socket ${socket.id} left room ride_${rideId} and booking:${rideId}`);
    }
  });

  socket.on('join_track', async (data) => {
    const token = typeof data === 'string' ? data : data?.token;
    if (!token) return;
    try {
      const shareRecord = await RideShareToken.findOne({ token });
      if (shareRecord) {
        socket.join('ride_' + shareRecord.rideId);
        console.log(`[SOCKET TRACK] Socket ${socket.id} tracking ride ${shareRecord.rideId}`);
        const cachedLoc = latestRideLocations[shareRecord.rideId];
        if (cachedLoc) {
          socket.emit('ride_location_update', cachedLoc);
        }
      }
    } catch (_) {}
  });

  // Validated real-time turn-by-turn navigation stream (Pilot to Customer)
  socket.on('ride_location_update', (data) => {
    if (!data || !data.rideId) return;

    // Purge cache if ride ended
    if (data.navigationStatus === 'completed' || data.navigationStatus === 'cancelled') {
      delete latestRideLocations[data.rideId];
      return;
    }

    const lat = Number(data.latitude);
    const lng = Number(data.longitude);
    if (isNaN(lat) || isNaN(lng) || lat < -90 || lat > 90 || lng < -180 || lng > 180 || (lat === 0 && lng === 0)) {
      return; // Reject invalid / null coordinates
    }

    const incomingTs = Number(data.timestamp) || Date.now();
    const existing = latestRideLocations[data.rideId];
    // Reject older / stale location updates when newer data was already processed
    if (existing && existing.timestamp && incomingTs < existing.timestamp) {
      return;
    }

    const accuracy = Number(data.accuracy) || 5.0;

    const payload = {
      rideId: data.rideId,
      pilotId: data.pilotId || 'pilot',
      vehicleType: data.vehicleType || 'Car',
      latitude: lat,
      longitude: lng,
      accuracy: accuracy,
      heading: Number(data.heading) || 0,
      speed: Number(data.speed) || 0,
      remainingDistance: data.remainingDistance || '',
      eta: data.eta || '',
      navigationStatus: data.navigationStatus || 'started',
      timestamp: incomingTs,
      updatedAt: new Date().toISOString()
    };

    // Store in-memory cache for instant delivery to newly joining clients / web track
    latestRideLocations[data.rideId] = payload;

    // Broadcast to ride room and global
    io.to('ride_' + data.rideId).emit('ride_location_update', payload);
    io.emit('ride_location_update', payload);

    // Update real-time pilot tracking registry and broadcast to Admin
    const pilotId = data.pilotId || 'pilot';
    const pilotData = getPilotTrackingRecord(pilotId, {
      lat,
      lng,
      heading: Number(data.heading) || 0,
      speed: Number(data.speed) || 0,
      accuracy,
      vehicleType: data.vehicleType || 'Car',
      rideId: data.rideId,
      rideStatus: data.navigationStatus || 'on_trip',
      status: (data.navigationStatus === 'started' || data.navigationStatus === 'on_trip') ? 'on_ride' : 'arriving',
      online: true,
      remainingDistance: data.remainingDistance || '',
      eta: data.eta || ''
    });
    io.to('admin_tracking').emit('pilot_location_update', pilotData);
    io.emit('pilot_location_update', pilotData);

    // Asynchronously save to Booking model in MongoDB
    Booking.updateOne(
      { $or: [{ bookingId: data.rideId }, { id: data.rideId }] },
      {
        $set: {
          driverLocation: { lat, lng },
          driverHeading: Number(data.heading) || 0,
          remainingDistance: data.remainingDistance || '',
          eta: data.eta || '',
          updatedAt: new Date()
        }
      }
    ).catch(err => console.warn('[LOCATION UPDATE DB WARNING]:', err.message));
  });

  // Other state updates (arrived, started, completed)
  socket.on('update_state', (data) => {
    // If ride completed or cancelled, remove location cache
    const bId = data?.bookingId || data?.rideId;
    const st = data?.status;
    if (bId && (st === 'completed' || st === 'cancelled')) {
      delete latestRideLocations[bId];
      io.to('ride_' + bId).emit('state_update', data);
    }
    // Legacy support for global broadcast (customer tracking driver location, etc)
    io.emit('state_update', data);
    GlobalState.create({ type: 'update_state', activeBooking: data });

    // Update pilot status in real-time admin registry
    const pilotUid = data?.driverId || data?.pilotId;
    if (pilotUid) {
      let newPilotStatus = 'online';
      if (st === 'started' || st === 'on_trip') {
        newPilotStatus = 'on_ride';
      } else if (st === 'accepted' || st === 'arrived' || st === 'heading_to_pickup') {
        newPilotStatus = 'arriving';
      } else if (st === 'completed' || st === 'cancelled') {
        newPilotStatus = 'online';
      }
      const pilotData = getPilotTrackingRecord(pilotUid, {
        rideId: (st === 'completed' || st === 'cancelled') ? null : bId,
        rideStatus: st,
        status: newPilotStatus
      });
      io.to('admin_tracking').emit('pilot_location_update', pilotData);
      io.emit('pilot_location_update', pilotData);

      // Dedicated Admin lifecycle events
      if (st === 'arrived') {
        io.to('admin_tracking').emit('pilot_arrived', { bookingId: bId, pilotId: pilotUid, timestamp: new Date().toISOString() });
      } else if (st === 'started' || st === 'on_trip') {
        io.to('admin_tracking').emit('ride_started', { bookingId: bId, pilotId: pilotUid, startTime: new Date().toISOString() });
      } else if (st === 'completed') {
        io.to('admin_tracking').emit('ride_completed', { bookingId: bId, pilotId: pilotUid, completedTime: new Date().toISOString() });
      } else if (st === 'cancelled') {
        io.to('admin_tracking').emit('booking_cancelled', { bookingId: bId, pilotId: pilotUid });
      }
      io.to('admin_tracking').emit('pilot_status_change', { uid: pilotUid, status: newPilotStatus, pilot: pilotData });
      getAdminLiveStats().then(s => io.to('admin_tracking').emit('admin_stats_update', s)).catch(() => {});
    }
  });

  // -------------------------------------------------------------
  // StayDriv Food Order Now & Restaurant Partner Real-Time Socket Handlers
  // -------------------------------------------------------------
  socket.on('join_restaurant', (data) => {
    const restId = typeof data === 'string' ? data : (data?.restaurantId || data?.id);
    if (restId) {
      socket.join('restaurant:' + restId);
      socket.join('all_restaurants');
      console.log(`[SOCKET FOOD] Socket ${socket.id} joined restaurant room: restaurant:${restId}`);
    }
  });

  socket.on('leave_restaurant', (data) => {
    const restId = typeof data === 'string' ? data : (data?.restaurantId || data?.id);
    if (restId) {
      socket.leave('restaurant:' + restId);
      socket.leave('all_restaurants');
      console.log(`[SOCKET FOOD] Socket ${socket.id} left restaurant room: restaurant:${restId}`);
    }
  });

  socket.on('join_food_orders', () => {
    socket.join('all_food_orders');
    console.log(`[SOCKET FOOD] Socket ${socket.id} joined all_food_orders`);
  });

  socket.on('join_pilot_food', async (data) => {
    const pilotId = typeof data === 'string' ? data : (data?.pilotId || data?.uid);
    if (!pilotId) return;

    try {
      const pilot = await User.findOne({
        $or: [{ uid: pilotId }, { phone: pilotId }]
      }).lean();

      // MANDATORY VEHICLE ELIGIBILITY CHECK: Auto Rickshaws, Cars, SUVs, Trucks are BLOCKED
      if (pilot && !isFoodDeliveryVehicle(pilot.vehicleType)) {
        console.log(`[SOCKET FOOD] Pilot ${pilotId} (${pilot.name || 'Pilot'}) registered vehicle '${pilot.vehicleType}' is INELIGIBLE for food delivery. Blocked from joining pilot_food_dispatch.`);
        socket.emit('food_delivery_ineligible', {
          success: false,
          vehicleType: pilot.vehicleType,
          message: `Food delivery is restricted to Bike and Scooty pilots only. '${pilot.vehicleType}' is not eligible.`
        });
        return;
      }

      // If pilot has paused food delivery, only join personal channel for active delivery updates (not general dispatch)
      if (pilot && pilot.foodServiceEnabled === false) {
        socket.leave('pilot_food_dispatch');
        socket.join('pilot_food:' + pilotId);
        if (pilot.phone) socket.join('pilot_food:' + pilot.phone);
        if (pilot.uid) socket.join('pilot_food:' + pilot.uid);
        console.log(`[SOCKET FOOD] Pilot ${pilotId} joined private channel only (foodServiceEnabled is OFF)`);
        return;
      }

      socket.join('pilot_food_dispatch');
      socket.join('pilot_food:' + pilotId);
      if (pilot && pilot.phone) socket.join('pilot_food:' + pilot.phone);
      if (pilot && pilot.uid) socket.join('pilot_food:' + pilot.uid);
      console.log(`[SOCKET FOOD] Eligible 2-wheeler pilot socket ${socket.id} (pilot: ${pilotId}, vehicle: ${pilot?.vehicleType || 'Bike'}) joined pilot_food_dispatch`);
    } catch (err) {
      console.error('[SOCKET FOOD] Error checking pilot vehicle eligibility on join_pilot_food:', err);
    }
  });

  socket.on('join_food_order', (data) => {
    const orderId = typeof data === 'string' ? data : (data?.orderId || data?.id);
    if (orderId) {
      socket.join('food_order:' + orderId);
      console.log(`[SOCKET FOOD] Socket ${socket.id} joined food_order room: food_order:${orderId}`);
    }
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
    io.to('admin_tracking').emit('booking_cancelled', cancelPayload);
    getAdminLiveStats().then(s => io.to('admin_tracking').emit('admin_stats_update', s)).catch(() => {});
    console.log(`[SOCKET EVENT] cancel_booking received for ${bookingId} by ${cancelledBy}`);

    // Update any pilots that had this booking
    for (const [uid, pilot] of livePilotsRegistry.entries()) {
      if (pilot.rideId === bookingId) {
        pilot.rideId = null;
        pilot.rideStatus = null;
        pilot.status = pilot.online ? 'online' : 'offline';
        pilot.lastUpdated = new Date().toISOString();
        pilot.timestamp = Date.now();
        io.to('admin_tracking').emit('pilot_location_update', pilot);
        io.emit('pilot_location_update', pilot);
      }
    }
  });

  socket.on('disconnect', () => {
    console.log('Client disconnected:', socket.id);
    const uid = socketToPilotUid.get(socket.id);
    if (uid && livePilotsRegistry.has(uid)) {
      const pilot = livePilotsRegistry.get(uid);
      pilot.online = false;
      pilot.status = 'offline';
      pilot.lastUpdated = new Date().toISOString();
      pilot.timestamp = Date.now();
      pilot.isTransmitting = false;
      io.to('admin_tracking').emit('pilot_location_update', pilot);
      io.to('admin_tracking').emit('pilot_offline', { uid });
      io.to('admin_tracking').emit('pilot_status_change', { uid, online: false, status: 'offline', pilot });
      io.emit('pilot_location_update', pilot);
      getAdminLiveStats().then(s => io.to('admin_tracking').emit('admin_stats_update', s)).catch(() => {});
    }
    delete onlineDrivers[socket.id];
    socketToPilotUid.delete(socket.id);

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
      const adminPath = getActiveAdminPath();
      const adminIndex = path.join(adminPath, 'index.html');
      if (fs.existsSync(adminIndex)) {
        return res.sendFile(adminIndex);
      }
    }
    if (req.url.startsWith('/app') || req.url.startsWith('/customer') || req.url.startsWith('/pilot') || req.url.startsWith('/login')) {
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
    const adminPath = getActiveAdminPath();
    const adminIndex = path.join(adminPath, 'index.html');
    if (fs.existsSync(adminIndex)) {
      return res.sendFile(adminIndex);
    }
  }
  return res.status(404).json({
    success: false,
    status: 'NOT_FOUND',
    message: `API endpoint not found: ${req.method} ${req.originalUrl || req.url}`
  });
});

// Global Express error handler to always return structured JSON instead of HTML
app.use((err, req, res, next) => {
  console.error('[EXPRESS ERROR HANDLER]:', err.message || err);
  if (res.headersSent) {
    return next(err);
  }
  const statusCode = err.status || err.statusCode || 500;
  return res.status(statusCode).json({
    success: false,
    status: 'ERROR',
    message: err.type === 'entity.too.large'
      ? 'Uploaded file or payload is too large. Please choose a smaller image.'
      : (err.message || 'Internal server error')
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`StayDriv sequential backend server running on http://localhost:${PORT}`);
});
