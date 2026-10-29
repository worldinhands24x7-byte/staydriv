/**
 * test_restaurant_settlements_e2e.js
 * Comprehensive End-to-End Verification Test for Restaurant Sales & Settlements
 * 
 * Verifies:
 * 1. Restaurant bank account submission & masking (status: pending_verification)
 * 2. Admin bank account verification (status: verified)
 * 3. Accurate sales, commission (15%), and net payout calculation for delivered orders
 * 4. Admin settlement batch initiation (status: processing)
 * 5. Admin settlement confirmation with Bank UTR recording & Financial Ledger posting
 * 6. Idempotency on repeated settlement confirmation (zero duplicate ledger rows)
 * 7. Settlement failure handling & safe balance retention
 */

const mongoose = require('mongoose');
const http = require('http');
const express = require('express');

const MONGO_URI = 'mongodb://127.0.0.1:27017/staydriv';

async function runTest() {
  console.log('================================================================');
  console.log('STARTING RESTAURANT SETTLEMENTS & PAYOUT LIFECYCLE E2E TEST');
  console.log('================================================================');

  let passedTests = 0;
  let totalTests = 0;

  function assert(condition, message) {
    totalTests++;
    if (condition) {
      console.log(`[PASS] ${message}`);
      passedTests++;
    } else {
      console.error(`[FAIL] ${message}`);
      throw new Error(`Assertion failed: ${message}`);
    }
  }

  // Connect to DB
  await mongoose.connect(MONGO_URI);
  console.log('Connected to MongoDB local instance');

  // Load models
  const Restaurant = require('./models/Restaurant');
  const FoodOrder = require('./models/FoodOrder');
  const RestaurantSettlement = require('./models/RestaurantSettlement');
  const FinancialLedger = require('./models/FinancialLedger');

  // Setup express test server
  const app = express();
  app.use(express.json());
  
  const foodRoutes = require('./routes/foodRoutes');
  app.use('/api/food', foodRoutes);

  const server = http.createServer(app);
  await new Promise(resolve => server.listen(0, resolve));
  const port = server.address().port;
  const baseUrl = `http://127.0.0.1:${port}/api/food`;
  console.log(`Test API running on ${baseUrl}`);

  try {
    const testRestId = `REST_SETTLE_TEST_${Date.now()}`;
    const testPhone = '9876543210';

    // 1. Create a test restaurant with 15% commission
    await Restaurant.deleteMany({ restaurantId: testRestId });
    await FoodOrder.deleteMany({ restaurantId: testRestId });
    await RestaurantSettlement.deleteMany({ restaurantId: testRestId });

    const restaurant = await Restaurant.create({
      restaurantId: testRestId,
      name: 'Spice Junction Hub',
      phone: testPhone,
      email: 'spicejunction@test.com',
      address: 'Main Road, Banjara Hills, Hyderabad, 500001',
      lat: 17.3850,
      lng: 78.4867,
      location: { type: 'Point', coordinates: [78.4867, 17.3850] },
      commissionRate: 15.0,
      status: 'approved',
      approvalStatus: 'approved',
      isActive: true,
      isOpen: true,
      pendingSettlement: 0,
      totalSettled: 0
    });
    console.log(`Created test restaurant: ${restaurant.name} (${restaurant.restaurantId})`);

    // 2. Submit Beneficiary Bank Details via Partner Endpoint
    console.log('\n--- Step 1: Partner submits Bank Details ---');
    const bankRes = await fetch(`${baseUrl}/restaurant/${testRestId}/bank-details`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        accountHolderName: 'Spice Junction Hospitality LLP',
        accountNumber: '912010045678912',
        confirmAccountNumber: '912010045678912',
        ifscCode: 'UTIB0000123',
        bankName: 'Axis Bank',
        accountType: 'Current',
        upiId: 'spicejunction@axisbank'
      })
    }).then(r => r.json());

    assert(bankRes.success === true, 'Bank details submitted successfully');
    assert(bankRes.restaurant.bankAccountMasked === '•••• •••• 8912', `Account number correctly masked: ${bankRes.restaurant.bankAccountMasked}`);
    assert(bankRes.restaurant.bankVerificationStatus === 'pending_verification', 'Status set to pending_verification');

    // 3. Admin Verifies Bank Details
    console.log('\n--- Step 2: Admin verifies Bank Details ---');
    const verifyRes = await fetch(`${baseUrl}/admin/restaurants/${testRestId}/verify-bank`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        status: 'verified',
        verifiedBy: 'AdminTester'
      })
    }).then(r => r.json());

    assert(verifyRes.success === true, 'Admin verified bank details');
    assert(verifyRes.restaurant.bankVerificationStatus === 'verified', 'Restaurant bank status is now verified');

    // 4. Create Delivered Orders to generate sales
    console.log('\n--- Step 3: Simulate 2 Delivered Orders ---');
    // Order 1: Subtotal ₹400
    const order1 = await FoodOrder.create({
      orderId: `FD_SETTLE_${Date.now()}_1`,
      customerId: 'CUST_TEST_1',
      customerName: 'Rahul Sharma',
      customerPhone: '9999999991',
      deliveryAddress: 'Flat 402, High View Apartments, Hyderabad',
      restaurantId: testRestId,
      restaurantName: restaurant.name,
      items: [{ itemId: 'item_1', name: 'Paneer Biryani', quantity: 2, price: 200 }],
      subtotal: 400,
      itemTotal: 400,
      packagingCharge: 20,
      tax: 20,
      deliveryFee: 40,
      totalAmount: 480,
      paymentStatus: 'paid',
      orderStatus: 'delivered',
      settlementStatus: 'unsettled',
      deliveredAt: new Date()
    });

    // Order 2: Subtotal ₹600
    const order2 = await FoodOrder.create({
      orderId: `FD_SETTLE_${Date.now()}_2`,
      customerId: 'CUST_TEST_2',
      customerName: 'Priya Patel',
      customerPhone: '9999999992',
      deliveryAddress: 'House 12, Road 5, Jubilee Hills, Hyderabad',
      restaurantId: testRestId,
      restaurantName: restaurant.name,
      items: [{ itemId: 'item_2', name: 'Chicken Biryani', quantity: 2, price: 300 }],
      subtotal: 600,
      itemTotal: 600,
      packagingCharge: 30,
      tax: 30,
      deliveryFee: 50,
      totalAmount: 710,
      paymentStatus: 'paid',
      orderStatus: 'delivered',
      settlementStatus: 'unsettled',
      deliveredAt: new Date()
    });

    console.log(`Created 2 delivered orders: ₹400 subtotal and ₹600 subtotal`);

    // 5. Query Restaurant Partner Overview
    console.log('\n--- Step 4: Check Restaurant Partner Settlements Overview ---');
    const restOverviewRes = await fetch(`${baseUrl}/restaurant/settlements/overview?restaurantId=${testRestId}`).then(r => r.json());
    assert(restOverviewRes.success === true, 'Fetched restaurant settlements overview');
    
    // Total gross sales from food = 400 + 600 = 1000
    assert(restOverviewRes.overview.totalSales === 1000, `Gross food sales = ₹1000 (got ₹${restOverviewRes.overview.totalSales})`);
    
    // Platform commission at 15% of 1000 = 150
    assert(restOverviewRes.overview.platformCommissionAmount === 150, `Platform fee at 15% = ₹150 (got ₹${restOverviewRes.overview.platformCommissionAmount})`);
    
    // Net earnings = 1000 - 150 = 850
    assert(restOverviewRes.overview.netEarnings === 850, `Net earnings = ₹850 (got ₹${restOverviewRes.overview.netEarnings})`);
    assert(restOverviewRes.overview.pendingSettlement === 850, `Pending payout = ₹850 (got ₹${restOverviewRes.overview.pendingSettlement})`);
    assert(restOverviewRes.overview.unsettledOrdersCount === 2, 'Unsettled delivered orders count is 2');

    // 6. Admin Checks Overview
    console.log('\n--- Step 5: Check Admin Settlements Overview ---');
    const adminOverviewRes = await fetch(`${baseUrl}/admin/settlements/overview`).then(r => r.json());
    assert(adminOverviewRes.success === true, 'Fetched admin settlements overview');
    console.log('adminOverviewRes restaurants:', (adminOverviewRes.restaurants || []).map(r => `${r.restaurantId} (${r.status})`));
    const adminRest = adminOverviewRes.restaurants.find(r => r.restaurantId === testRestId);
    assert(Boolean(adminRest), 'Admin overview includes test restaurant');
    assert(adminRest.pendingSettlement === 850, `Admin sees pending payout of ₹850 (got ₹${adminRest.pendingSettlement})`);

    // 7. Admin Initiates Settlement Payout Batch
    console.log('\n--- Step 6: Admin Initiates Settlement Batch ---');
    const initRes = await fetch(`${baseUrl}/admin/restaurants/${testRestId}/initiate-settlement`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        notes: 'Weekly automated payout batch W42',
        initiatedBy: 'AdminTester'
      })
    }).then(r => r.json());

    assert(initRes.success === true, 'Settlement batch initiated successfully');
    const settlementId = initRes.settlement.settlementId;
    assert(Boolean(settlementId), `Settlement ID generated: ${settlementId}`);
    assert(initRes.settlement.status === 'processing', 'Settlement status is processing');
    assert(initRes.settlement.grossSales === 1000, `Gross sales = ₹1000 (got ₹${initRes.settlement.grossSales})`);
    assert(initRes.settlement.totalCommission === 150, `Commission = ₹150 (got ₹${initRes.settlement.totalCommission})`);
    assert(initRes.settlement.netPayable === 850, `Net payable = ₹850 (got ₹${initRes.settlement.netPayable})`);
    assert(initRes.settlement.orderIds.length === 2, 'Settlement encompasses 2 delivered orders');

    // Verify orders are in settlement_initiated
    const updatedOrder1 = await FoodOrder.findOne({ orderId: order1.orderId });
    assert(updatedOrder1.settlementStatus === 'settlement_initiated', 'Order 1 transitioned to settlement_initiated');

    // 8. Admin Confirms Settlement with Bank UTR & Posts to Ledger
    console.log('\n--- Step 7: Admin Confirms Settlement with Bank UTR ---');
    const testUtr = `AXIS${Date.now()}`;
    const confirmRes = await fetch(`${baseUrl}/admin/settlements/${settlementId}/confirm`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        payoutReference: testUtr,
        remarks: 'Processed via Axis Corporate NetBanking CMS',
        settledBy: 'AdminFinanceLead'
      })
    }).then(r => r.json());

    assert(confirmRes.success === true, 'Settlement confirmed successfully');
    assert(confirmRes.settlement.status === 'paid', 'Settlement status is paid');
    assert(confirmRes.settlement.payoutReference === testUtr, `UTR saved: ${confirmRes.settlement.payoutReference}`);

    // Verify Financial Ledger Entry
    const ledgerEntry = await FinancialLedger.findOne({ settlementId });
    assert(Boolean(ledgerEntry), 'Double-entry financial ledger record created');
    assert(ledgerEntry.entryType === 'RESTAURANT_PAYOUT_SETTLEMENT', `Ledger entryType is RESTAURANT_PAYOUT_SETTLEMENT (got ${ledgerEntry.entryType})`);
    assert(ledgerEntry.amount === 850, `Ledger amount is ₹850 (got ₹${ledgerEntry.amount})`);
    assert(ledgerEntry.referenceNumber === testUtr, 'Ledger entry contains bank UTR reference');

    // Verify Restaurant Balance Updates
    const updatedRest = await Restaurant.findOne({ restaurantId: testRestId });
    assert(updatedRest.totalSettled === 850, `Restaurant totalSettled updated to ₹850 (got ₹${updatedRest.totalSettled})`);
    assert(updatedRest.pendingSettlement === 0, `Restaurant pendingSettlement reset to ₹0 (got ₹${updatedRest.pendingSettlement})`);

    // Verify Orders are Marked Settled
    const finalOrder1 = await FoodOrder.findOne({ orderId: order1.orderId });
    console.log('finalOrder1:', finalOrder1 ? { orderId: finalOrder1.orderId, settlementStatus: finalOrder1.settlementStatus, settlementId: finalOrder1.settlementId } : 'null');
    console.log('settlement orderIds from confirm:', confirmRes.settlement?.orderIds);
    assert(finalOrder1.settlementStatus === 'settled', `Order 1 settlementStatus is settled (got ${finalOrder1.settlementStatus})`);

    // 9. Idempotency Check on Repeat Confirmation
    console.log('\n--- Step 8: Test Idempotency on Repeat Confirmation ---');
    const repeatConfirmRes = await fetch(`${baseUrl}/admin/settlements/${settlementId}/confirm`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        payoutReference: testUtr,
        settledBy: 'AdminFinanceLead'
      })
    }).then(r => r.json());

    assert(repeatConfirmRes.success === true, 'Repeat confirmation returns success gracefully');
    const ledgerCount = await FinancialLedger.countDocuments({ settlementId });
    assert(ledgerCount === 1, `Exactly 1 ledger record exists after repeat confirmation (got ${ledgerCount})`);

    // 10. Settlement Failure Handling Test
    console.log('\n--- Step 9: Test Failure Handling & Safe Balance Retention ---');
    // Create new order for ₹500
    const order3 = await FoodOrder.create({
      orderId: `FD_SETTLE_${Date.now()}_3`,
      customerId: 'CUST_TEST_3',
      customerName: 'Suresh Raina',
      customerPhone: '9999999993',
      deliveryAddress: 'Villa 18, Green Meadows, Gachibowli, Hyderabad',
      restaurantId: testRestId,
      restaurantName: restaurant.name,
      items: [{ itemId: 'item_3', name: 'Mutton Biryani', quantity: 1, price: 500 }],
      subtotal: 500,
      itemTotal: 500,
      packagingCharge: 20,
      tax: 20,
      deliveryFee: 40,
      totalAmount: 580,
      paymentStatus: 'paid',
      orderStatus: 'delivered',
      settlementStatus: 'unsettled',
      deliveredAt: new Date()
    });

    // Initiate new settlement (500 - 15% = 425)
    const initFailRes = await fetch(`${baseUrl}/admin/restaurants/${testRestId}/initiate-settlement`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ initiatedBy: 'AdminTester' })
    }).then(r => r.json());

    assert(initFailRes.success === true, 'Second settlement initiated');
    const failSettleId = initFailRes.settlement.settlementId;

    // Fail this settlement
    const failRes = await fetch(`${baseUrl}/admin/settlements/${failSettleId}/fail`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        failureReason: 'Beneficiary bank account reported frozen',
        failedBy: 'AdminBankOps'
      })
    }).then(r => r.json());

    assert(failRes.success === true, 'Settlement marked as failed');
    assert(failRes.settlement.status === 'failed', 'Status is failed');
    assert(failRes.settlement.failureReason === 'Beneficiary bank account reported frozen', 'Failure reason recorded');

    // Verify order rolled back to unsettled
    const rolledBackOrder = await FoodOrder.findOne({ orderId: order3.orderId });
    assert(rolledBackOrder.settlementStatus === 'unsettled', 'Order rolled back to unsettled');

    // Verify restaurant pending balance retains ₹425
    const restAfterFail = await Restaurant.findOne({ restaurantId: testRestId });
    assert(restAfterFail.pendingSettlement === 425, `Pending settlement retained at ₹425 (got ₹${restAfterFail.pendingSettlement})`);

    console.log('\n================================================================');
    console.log(`ALL TESTS PASSED: ${passedTests}/${totalTests}`);
    console.log('RESTAURANT SALES & SETTLEMENTS SYSTEM IS 100% OPERATIONAL');
    console.log('================================================================');

    // Clean up test data
    await Restaurant.deleteMany({ restaurantId: testRestId });
    await FoodOrder.deleteMany({ restaurantId: testRestId });
    await RestaurantSettlement.deleteMany({ restaurantId: testRestId });
    await FinancialLedger.deleteMany({ settlementId: { $in: [settlementId, failSettleId] } });

  } catch (err) {
    console.error('Test execution failed:', err);
    process.exit(1);
  } finally {
    server.close();
    await mongoose.disconnect();
  }
}

runTest();
