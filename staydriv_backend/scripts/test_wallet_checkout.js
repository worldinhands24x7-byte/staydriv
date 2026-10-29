const mongoose = require('mongoose');
const http = require('http');

function request(options, data) {
  return new Promise((resolve, reject) => {
    const req = http.request(options, (res) => {
      let body = '';
      res.on('data', (chunk) => body += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(body);
          resolve({ status: res.statusCode, body: parsed });
        } catch (e) {
          resolve({ status: res.statusCode, raw: body });
        }
      });
    });
    req.on('error', reject);
    if (data) {
      req.write(typeof data === 'string' ? data : JSON.stringify(data));
    }
    req.end();
  });
}

async function testWallet() {
  console.log('--- TESTING WALLET CHECKOUT & ATOMIC LEDGER ---');
  await mongoose.connect('mongodb://127.0.0.1:27017/staydriv');

  const User = mongoose.model('User', new mongoose.Schema({
    uid: String,
    userId: String,
    name: String,
    phone: String,
    phoneNumber: String,
    walletBalance: { type: Number, default: 0 },
    role: String
  }, { strict: false }));

  const WalletTransaction = mongoose.model('WalletTransaction', new mongoose.Schema({
    transactionId: String,
    uid: String,
    userId: String,
    phone: String,
    amount: Number,
    type: String,
    category: String,
    description: String,
    referenceId: String,
    status: String,
    balanceAfter: Number
  }, { strict: false }));

  const testUserId = 'TEST_WALLET_USER_' + Date.now();
  
  // 1. Create user with 0 wallet balance
  await User.create({
    uid: testUserId,
    userId: testUserId,
    name: 'Wallet Tester',
    phone: '9000000001',
    phoneNumber: '9000000001',
    walletBalance: 0,
    role: 'customer'
  });

  // 2. Try placing wallet order with insufficient balance
  const failOrderRes = await request({
    hostname: 'localhost',
    port: 3000,
    path: '/api/food/orders',
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
  }, {
    restaurantId: 'REST_PARADISE_01',
    customerId: testUserId,
    customerName: 'Wallet Tester',
    customerPhone: '9000000001',
    items: [{ itemId: 'ITEM_PARADISE_01', quantity: 1 }],
    deliveryAddress: {
      address: 'Plot 42, Hitech City, Hyderabad',
      latitude: 17.4483,
      longitude: 78.3915
    },
    paymentMethod: 'wallet',
    idempotencyKey: 'TEST_WALLET_FAIL_' + Date.now()
  });

  console.log('Insufficient balance rejection:', failOrderRes.status, failOrderRes.body.message);
  if (failOrderRes.status === 400 && failOrderRes.body.message.toLowerCase().includes('insufficient staydriv wallet balance')) {
    console.log('[PASS] Wallet check successfully prevented order on insufficient balance');
  } else {
    console.error('[FAIL] Expected 400 insufficient balance, got:', failOrderRes.body);
    process.exit(1);
  }

  // 3. Top up user wallet to ₹1000
  await User.updateOne({ uid: testUserId }, { $set: { walletBalance: 1000 } });

  // 4. Place wallet order with ₹1000 balance
  const successOrderRes = await request({
    hostname: 'localhost',
    port: 3000,
    path: '/api/food/orders',
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
  }, {
    restaurantId: 'REST_PARADISE_01',
    customerId: testUserId,
    customerName: 'Wallet Tester',
    customerPhone: '9000000001',
    items: [{ itemId: 'ITEM_PARADISE_01', quantity: 1 }],
    deliveryAddress: {
      address: 'Plot 42, Hitech City, Hyderabad',
      latitude: 17.4483,
      longitude: 78.3915
    },
    paymentMethod: 'wallet',
    idempotencyKey: 'TEST_WALLET_SUCCESS_' + Date.now()
  });

  console.log('Order with wallet result:', successOrderRes.status, successOrderRes.body.success, 'Order ID:', successOrderRes.body.order?.orderId);
  if (successOrderRes.status === 201 && successOrderRes.body.success) {
    console.log('[PASS] Order successfully placed with wallet');
  } else {
    console.error('[FAIL] Order placement with wallet failed:', successOrderRes.body);
    process.exit(1);
  }

  // 5. Verify updated wallet balance and ledger transaction
  const updatedUser = await User.findOne({ uid: testUserId });
  console.log('Updated user wallet balance:', updatedUser.walletBalance);
  if (updatedUser.walletBalance < 1000) {
    console.log(`[PASS] Wallet atomically debited. Remaining balance: ₹${updatedUser.walletBalance}`);
  } else {
    console.error('[FAIL] Wallet was not debited!');
    process.exit(1);
  }

  const tx = await WalletTransaction.findOne({ uid: testUserId, type: 'debit' });
  if (tx && tx.type === 'debit') {
    console.log(`[PASS] WalletTransaction ledger record created: ₹${tx.amount} debited, txId: ${tx.transactionId}`);
  } else {
    console.error('[FAIL] WalletTransaction ledger entry missing or invalid:', tx);
    process.exit(1);
  }

  // Cleanup
  await User.deleteOne({ uid: testUserId });
  await WalletTransaction.deleteMany({ uid: testUserId });
  await mongoose.disconnect();

  console.log('ALL WALLET CHECKOUT TESTS PASSED!');
  process.exit(0);
}

testWallet().catch(err => {
  console.error(err);
  process.exit(1);
});
