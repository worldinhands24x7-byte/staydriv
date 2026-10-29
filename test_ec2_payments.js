const mongoose = require('mongoose');
const http = require('http');

async function run() {
  await mongoose.connect('mongodb://127.0.0.1:27017/staydriv');

  const userSchema = new mongoose.Schema({
    uid: String,
    role: String,
    name: String,
    phone: String,
    walletBalance: { type: Number, default: 0 }
  }, { strict: false });

  const bookingSchema = new mongoose.Schema({
    bookingId: String,
    passengerId: String,
    passengerName: String,
    passengerPhone: String,
    driverId: String,
    driverName: String,
    driverPhone: String,
    price: String,
    status: String,
    paymentStatus: String,
    paymentOption: String,
    paidAt: Date,
    updatedAt: Date
  }, { strict: false });

  const User = mongoose.models.User || mongoose.model('User', userSchema);
  const Booking = mongoose.models.Booking || mongoose.model('Booking', bookingSchema);

  const testUid = 'CUST_WALLET_TEST_' + Date.now();
  const testBookingId = 'BK_PAY_TEST_' + Date.now();

  console.log(`Setting up Customer ${testUid} with ₹250.00 wallet balance...`);
  const cust = new User({
    uid: testUid,
    role: 'customer',
    name: 'Wallet Tester',
    phone: '9876543210',
    walletBalance: 250.00
  });
  await cust.save();

  console.log(`Setting up Ride Booking ${testBookingId} with fare ₹150.00...`);
  const b = new Booking({
    bookingId: testBookingId,
    passengerId: testUid,
    passengerName: 'Wallet Tester',
    passengerPhone: '9876543210',
    driverId: 'PILOT_TEST',
    driverName: 'Test Pilot',
    driverPhone: '9876543211',
    price: '₹150',
    status: 'completed',
    paymentStatus: 'pending'
  });
  await b.save();

  function makePost(path, body) {
    return new Promise((resolve, reject) => {
      const data = JSON.stringify(body);
      const req = http.request({
        hostname: 'localhost',
        port: 3000,
        path: path,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(data)
        }
      }, (res) => {
        let respData = '';
        res.on('data', chunk => respData += chunk);
        res.on('end', () => resolve({ status: res.statusCode, body: JSON.parse(respData) }));
      });
      req.on('error', reject);
      req.write(data);
      req.end();
    });
  }

  // 1. Pay ride with wallet
  console.log('\n--- STEP 1: Pay Ride with StayDriv Wallet (₹150) ---');
  const payRes = await makePost('/api/customer/wallet/pay-ride', {
    bookingId: testBookingId,
    uid: testUid
  });
  console.log('Wallet Pay Status:', payRes.status, payRes.body);

  // Check balance after payment
  const userAfter = await User.findOne({ uid: testUid });
  console.log(`User balance after payment: ₹${userAfter.walletBalance} (Expected: ₹100.00)`);
  if (userAfter.walletBalance !== 100) throw new Error('Balance mismatch');

  // Check booking status
  const bookingAfter = await Booking.findOne({ bookingId: testBookingId });
  console.log(`Booking status: ${bookingAfter.paymentStatus}, option: ${bookingAfter.paymentOption}`);
  if (bookingAfter.paymentStatus !== 'paid' || bookingAfter.paymentOption !== 'STAYDRIV_WALLET') {
    throw new Error('Booking not marked paid with wallet');
  }

  // 2. Duplicate wallet payment attempt
  console.log('\n--- STEP 2: Duplicate Wallet Payment Attempt (Should Block) ---');
  const dupWalletRes = await makePost('/api/customer/wallet/pay-ride', {
    bookingId: testBookingId,
    uid: testUid
  });
  console.log('Duplicate Wallet Pay Status:', dupWalletRes.status, dupWalletRes.body);
  const userAfterDup = await User.findOne({ uid: testUid });
  console.log(`User balance after duplicate attempt: ₹${userAfterDup.walletBalance} (Must still be ₹100.00)`);
  if (userAfterDup.walletBalance !== 100) throw new Error('Duplicate wallet deduction occurred!');

  // 3. Duplicate cash payment attempt on already paid booking
  console.log('\n--- STEP 3: Duplicate Cash Payment Attempt on Paid Ride (Should Block) ---');
  const dupCashRes = await makePost('/api/booking/pay-cash', {
    bookingId: testBookingId,
    uid: testUid
  });
  console.log('Duplicate Cash Status:', dupCashRes.status, dupCashRes.body);
  if (dupCashRes.body.paymentStatus !== 'paid') throw new Error('Cash duplicate failed');

  // 4. Test Dynamic QR creation and verification for a second booking
  console.log('\n--- STEP 4: Test Dynamic QR and UPI Verification Flow ---');
  const testQrBookingId = 'BK_QR_TEST_' + Date.now();
  const b2 = new Booking({
    bookingId: testQrBookingId,
    passengerId: testUid,
    passengerName: 'Wallet Tester',
    passengerPhone: '9876543210',
    driverId: 'PILOT_TEST',
    driverName: 'Test Pilot',
    driverPhone: '9876543211',
    price: '₹120',
    status: 'completed',
    paymentStatus: 'pending'
  });
  await b2.save();

  const upiVerifyRes = await makePost('/api/booking/payment/verify-upi', {
    bookingId: testQrBookingId,
    referenceId: 'UPI_REF_987654321012'
  });
  console.log('UPI Verify Status:', upiVerifyRes.status, upiVerifyRes.body);
  const b2After = await Booking.findOne({ bookingId: testQrBookingId });
  console.log(`Booking 2 status: ${b2After.paymentStatus}, option: ${b2After.paymentOption}`);
  if (b2After.paymentStatus !== 'paid' || b2After.paymentOption !== 'UPI_QR') {
    throw new Error('QR UPI payment not verified');
  }

  // 5. Duplicate UPI verification attempt
  console.log('\n--- STEP 5: Duplicate UPI Verify Attempt (Should Block) ---');
  const dupUpiRes = await makePost('/api/booking/payment/verify-upi', {
    bookingId: testQrBookingId,
    referenceId: 'UPI_REF_987654321012'
  });
  console.log('Duplicate UPI Status:', dupUpiRes.status, dupUpiRes.body);
  if (dupUpiRes.body.alreadyPaid !== true) throw new Error('Duplicate UPI verify allowed');

  console.log('\n✓ ALL LIVE EC2 PAYMENT OPTION AND DUPLICATION TESTS PASSED!');
  process.exit(0);
}

run().catch(err => {
  console.error('Test execution error:', err);
  process.exit(1);
});
