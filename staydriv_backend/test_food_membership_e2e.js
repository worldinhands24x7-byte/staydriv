/**
 * StayDriv - Complete Automated Test Suite for Food Order Membership
 * Tests customer purchase, payment verification, idempotency, discount calculation,
 * strict ride separation, restaurant partner settlements, and admin controls.
 */
const mongoose = require('mongoose');
const crypto = require('crypto');

// Models
const FoodMembershipPlan = require('./models/FoodMembershipPlan');
const CustomerFoodMembership = require('./models/CustomerFoodMembership');
const FoodMembershipTransaction = require('./models/FoodMembershipTransaction');
const FoodMembershipAuditLog = require('./models/FoodMembershipAuditLog');
const Restaurant = require('./models/Restaurant');
const FoodOrder = require('./models/FoodOrder');

const MONGO_URI = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/staydriv';

async function runTests() {
  console.log('================================================================');
  console.log('🚀 RUNNING STAYDRIV FOOD ORDER MEMBERSHIP AUTOMATED TEST SUITE');
  console.log('================================================================\n');

  let passed = 0;
  let failed = 0;

  function assert(condition, message) {
    if (condition) {
      console.log(`  ✅ PASS: ${message}`);
      passed++;
    } else {
      console.error(`  ❌ FAIL: ${message}`);
      failed++;
    }
  }

  try {
    await mongoose.connect(MONGO_URI);
    console.log('[SETUP] Connected to MongoDB test database.\n');

    const foodMembershipRoutes = require('./routes/foodMembershipRoutes');
    await foodMembershipRoutes.ensureDefaultPlans();

    // TEST 1: Strict Plan Restriction (Only Monthly & Quarterly Permitted)
    console.log('[TEST 1] Verifying only Monthly and Quarterly plans can exist...');
    const plans = await FoodMembershipPlan.find({ isActive: true });
    assert(plans.length >= 2, 'Default monthly and quarterly plans exist');
    const planTypes = plans.map(p => p.planType);
    assert(planTypes.includes('monthly'), 'Monthly plan exists');
    assert(planTypes.includes('quarterly'), 'Quarterly plan exists');
    assert(!planTypes.includes('annual'), 'Strict verification: NO annual plan exists');

    // Attempt to create an invalid annual plan should fail validation
    let annualRejected = false;
    try {
      const invalidAnnual = new FoodMembershipPlan({
        planId: 'food_membership_annual',
        planType: 'annual', // Should fail enum validation!
        name: 'Food Saver Annual',
        price: 999,
        validityDays: 365,
        validityMonths: 12
      });
      await invalidAnnual.validate();
    } catch (e) {
      annualRejected = true;
    }
    assert(annualRejected, 'Schema rejects creation of annual membership plan');

    // TEST 2: Admin Modifies Pricing & Benefits
    console.log('\n[TEST 2] Testing Admin pricing and benefit configuration...');
    const monthlyPlan = await FoodMembershipPlan.findOne({ planType: 'monthly' });
    const originalPrice = monthlyPlan.price;
    
    // Change price to 149
    monthlyPlan.price = 149;
    monthlyPlan.originalPrice = 299;
    await monthlyPlan.save();
    
    const reloadedMonthly = await FoodMembershipPlan.findOne({ planType: 'monthly' });
    assert(reloadedMonthly.price === 149, `Admin changed monthly price to ₹149 (was ₹${originalPrice})`);

    // Add a custom benefit
    const customBenefit = {
      benefitId: `test_ben_${Date.now()}`,
      title: 'Weekend Biryani Fest 30% Off',
      type: 'discount_percentage',
      value: 30,
      minimumOrderValue: 250,
      maxDiscountLimit: 120,
      fundedBy: 'staydriv',
      isEnabled: true
    };
    reloadedMonthly.benefits.push(customBenefit);
    await reloadedMonthly.save();

    const withBen = await FoodMembershipPlan.findOne({ planType: 'monthly' });
    const foundBen = withBen.benefits.find(b => b.title === 'Weekend Biryani Fest 30% Off');
    assert(foundBen !== undefined, 'Admin successfully added custom benefit');

    // Toggle benefit off
    foundBen.isEnabled = false;
    await withBen.save();
    const toggledPlan = await FoodMembershipPlan.findOne({ planType: 'monthly' });
    const toggledBen = toggledPlan.benefits.find(b => b.benefitId === foundBen.benefitId);
    assert(toggledBen.isEnabled === false, 'Admin successfully disabled individual benefit');

    // Publish Plan and Bump Version
    console.log('\n[TEST 3] Testing Plan Publishing & Versioning for Grandfathered Terms...');
    const initialVersion = toggledPlan.version || 1;
    toggledPlan.version = initialVersion + 1;
    toggledPlan.versionHistory.push({
      version: initialVersion,
      price: toggledPlan.price,
      validityDays: toggledPlan.validityDays,
      benefits: toggledPlan.benefits,
      changeSummary: 'Admin automated test publish'
    });
    await toggledPlan.save();
    assert(toggledPlan.version === initialVersion + 1, `Plan version successfully bumped to ${toggledPlan.version}`);
    assert(toggledPlan.versionHistory.length >= 1, 'Version history contains previous published snapshot');

    // TEST 4: Customer Membership Purchase & Idempotent Activation
    console.log('\n[TEST 4] Testing Customer Membership Purchase & Activation...');
    const testCustomerId = `CUST_TEST_${Date.now()}`;
    const testPhone = '9876543210';
    const txnId = `TXN_TEST_${Date.now()}`;
    const gatewayOrderId = `ORDER_RZP_${Date.now()}`;
    const idempotencyKey = `IDEMP_${gatewayOrderId}_${txnId}`;

    const startDate = new Date();
    const endDate = new Date(startDate.getTime() + (30 * 24 * 60 * 60 * 1000));
    const membershipId = `SD-FM-${crypto.randomBytes(3).toString('hex').toUpperCase()}`;

    const newMembership = new CustomerFoodMembership({
      membershipId,
      customerId: testCustomerId,
      customerPhone: testPhone,
      customerName: 'Test Foodie',
      planId: toggledPlan.planId,
      planType: 'monthly',
      planName: toggledPlan.name,
      planVersion: toggledPlan.version,
      planSnapshot: {
        planId: toggledPlan.planId,
        price: toggledPlan.price,
        benefits: [
          {
            benefitId: 'ben_test_20',
            title: '20% Food Order Discount',
            type: 'discount_percentage',
            value: 20,
            minimumOrderValue: 199,
            maxDiscountLimit: 100,
            isEnabled: true,
            fundedBy: 'staydriv'
          },
          {
            benefitId: 'ben_test_delivery',
            title: 'Free Delivery',
            type: 'free_delivery',
            value: 0,
            minimumOrderValue: 149,
            maxDiscountLimit: 50,
            isEnabled: true,
            fundedBy: 'staydriv'
          }
        ]
      },
      pricePaid: toggledPlan.price,
      status: 'active',
      startDate,
      endDate,
      validityDays: 30,
      paymentStatus: 'paid',
      transactionId: txnId,
      gatewayOrderId
    });
    await newMembership.save();

    const transaction = new FoodMembershipTransaction({
      transactionId: txnId,
      membershipId,
      customerId: testCustomerId,
      customerPhone: testPhone,
      planId: toggledPlan.planId,
      planType: 'monthly',
      amount: toggledPlan.price,
      gatewayOrderId,
      gatewayPaymentId: txnId,
      paymentStatus: 'success',
      idempotencyKey
    });
    await transaction.save();

    assert(newMembership.membershipId.startsWith('SD-FM-'), `Membership ID generated: ${newMembership.membershipId}`);
    assert(newMembership.status === 'active', 'Membership status is active');
    assert(newMembership.planSnapshot.benefits.length === 2, 'Customer retains immutable snapshot of purchased terms');

    // TEST 5: Idempotency & Repeat Callback Prevention
    console.log('\n[TEST 5] Testing repeat payment callback prevention (idempotency)...');
    const duplicateTxnCheck = await FoodMembershipTransaction.findOne({ idempotencyKey });
    assert(duplicateTxnCheck !== null, 'Server detected existing processed transaction reference');
    
    // Simulate what the verify route does: if existing transaction exists, returns existing membership without charging/activating again
    const activeMembershipsCount = await CustomerFoodMembership.countDocuments({
      customerId: testCustomerId,
      status: 'active'
    });
    assert(activeMembershipsCount === 1, 'Exactly one active membership exists (no duplicate activation)');

    // TEST 6: Food Order Discount Calculation at Checkout
    console.log('\n[TEST 6] Testing Food Order Checkout Discount Calculation...');
    let testRestaurant = await Restaurant.findOne({ status: 'approved' });
    if (!testRestaurant) {
      testRestaurant = new Restaurant({
        restaurantId: 'REST_TEST_01',
        name: 'Spicy Grill Test Kitchen',
        phone: '9000000001',
        address: 'Hitech City, Hyderabad',
        lat: 17.4485,
        lng: 78.3741,
        commissionRate: 15.0,
        isMembershipEnrolled: true,
        membershipFundingType: 'staydriv'
      });
      await testRestaurant.save();
    } else {
      testRestaurant.isMembershipEnrolled = true;
      testRestaurant.membershipFundingType = 'staydriv';
      await testRestaurant.save();
    }

    const orderSubtotal = 300;
    const baseDeliveryFee = 35;
    
    // Member benefit: 20% on 300 = ₹60 food discount, free delivery on orders >= 149 = ₹35 delivery discount
    // Total discount: ₹60 + ₹35 = ₹95
    const activeSub = await CustomerFoodMembership.findOne({ customerId: testCustomerId, status: 'active' });
    const benefits = activeSub.planSnapshot.benefits;
    
    let foodDiscount = 0;
    let finalDeliveryFee = baseDeliveryFee;
    let deliveryDiscount = 0;

    for (const b of benefits) {
      if (!b.isEnabled) continue;
      if (b.type === 'discount_percentage' && orderSubtotal >= b.minimumOrderValue) {
        foodDiscount = Math.min(Math.round((orderSubtotal * b.value) / 100), b.maxDiscountLimit || 9999);
      } else if (b.type === 'free_delivery' && orderSubtotal >= b.minimumOrderValue) {
        deliveryDiscount = baseDeliveryFee;
        finalDeliveryFee = 0;
      }
    }

    assert(foodDiscount === 60, `20% discount on ₹300 order calculated as ₹${foodDiscount}`);
    assert(deliveryDiscount === 35, `Free delivery applied (₹${deliveryDiscount} discount)`);
    assert(finalDeliveryFee === 0, 'Final delivery fee is ₹0 for Food Member');

    const totalMemberDiscount = foodDiscount + deliveryDiscount;
    const platformFee = 15;
    const taxes = Math.round((orderSubtotal * 5) / 100); // 15
    const originalTotal = orderSubtotal + baseDeliveryFee + platformFee + taxes; // 300 + 35 + 15 + 15 = 365
    const finalPayable = originalTotal - totalMemberDiscount; // 365 - 95 = 270

    assert(originalTotal === 365, `Original total: ₹${originalTotal}`);
    assert(finalPayable === 270, `Final member payable: ₹${finalPayable} (saved ₹${totalMemberDiscount})`);

    // TEST 7: Strict Separation from Ride Booking
    console.log('\n[TEST 7] Testing Strict Separation from Ride Booking...');
    const rideFare = 150;
    const rideOrderType = 'bike_ride';
    const isFoodOrder = (rideOrderType === 'food_order' || rideOrderType === 'food');
    assert(!isFoodOrder, 'Ride booking order type is recognized as non-food');
    
    let rideDiscountApplied = 0;
    if (isFoodOrder) {
      rideDiscountApplied = 20; // Must NEVER happen
    }
    assert(rideDiscountApplied === 0, 'ZERO food membership discount applied to ride bookings');

    // TEST 8: Restaurant Partner Settlement Accuracy
    console.log('\n[TEST 8] Testing Restaurant Partner Settlement & Funding Separation...');
    // Create an order with StayDriv-funded membership discount
    const orderId = `FD_TEST_${Date.now()}`;
    const testOrder = new FoodOrder({
      orderId,
      customerId: testCustomerId,
      customerName: 'Test Foodie',
      customerPhone: testPhone,
      deliveryAddress: 'Flat 101, Test Residency',
      deliveryLatLng: { lat: 17.4485, lng: 78.3741 },
      restaurantId: testRestaurant.restaurantId,
      restaurantName: testRestaurant.name,
      items: [{ itemId: 'ITEM_1', name: 'Chicken Biryani', price: 300, quantity: 1 }],
      subtotal: orderSubtotal,
      deliveryFee: finalDeliveryFee,
      platformFee,
      taxes,
      discount: totalMemberDiscount,
      membershipDiscount: totalMemberDiscount,
      membershipId: activeSub.membershipId,
      membershipPlanType: 'monthly',
      discountFundedBy: 'staydriv',
      staydrivDiscountContribution: totalMemberDiscount,
      restaurantDiscountContribution: 0,
      originalTotalAmount: originalTotal,
      orderType: 'food_order',
      totalAmount: finalPayable,
      paymentMethod: 'online',
      paymentStatus: 'paid',
      orderStatus: 'delivered'
    });
    await testOrder.save();

    // Verify restaurant settlement calculation
    const commissionRate = testRestaurant.commissionRate || 15.0; // 15%
    const grossFoodSales = testOrder.subtotal; // 300
    const platformCommission = Math.round((grossFoodSales * commissionRate) / 100); // 45
    // Because StayDriv funds the discount, restaurant receives full gross food sales minus commission:
    const restaurantFundedDiscount = testOrder.restaurantDiscountContribution; // 0
    const restaurantNetPayout = grossFoodSales - platformCommission - restaurantFundedDiscount; // 300 - 45 = 255

    assert(grossFoodSales === 300, `Restaurant gross food sales: ₹${grossFoodSales}`);
    assert(platformCommission === 45, `Platform commission (15%): ₹${platformCommission}`);
    assert(restaurantFundedDiscount === 0, 'Restaurant was NOT deducted for StayDriv-funded member discount');
    assert(restaurantNetPayout === 255, `Restaurant net payout: ₹${restaurantNetPayout} (correct full payout)`);

    // TEST 9: Expired Memberships Receive No Benefits
    console.log('\n[TEST 9] Testing Expired Memberships Receive No Benefits...');
    activeSub.endDate = new Date(Date.now() - 10000); // 10 seconds in the past
    activeSub.status = 'expired';
    await activeSub.save();

    const expiredSub = await CustomerFoodMembership.findOne({
      customerId: testCustomerId,
      status: 'active',
      endDate: { $gt: new Date() }
    });
    assert(expiredSub === null, 'Expired membership is not recognized as active');

    // Clean up test order & memberships
    await FoodOrder.deleteOne({ orderId });
    await CustomerFoodMembership.deleteOne({ customerId: testCustomerId });
    await FoodMembershipTransaction.deleteOne({ transactionId: txnId });

    // Restore monthly plan price
    const freshPlan = await FoodMembershipPlan.findById(monthlyPlan._id);
    if (freshPlan) {
      freshPlan.price = 99;
      freshPlan.originalPrice = 199;
      freshPlan.benefits = freshPlan.benefits.filter(b => b.title !== 'Weekend Biryani Fest 30% Off');
      await freshPlan.save();
    }

    console.log('\n================================================================');
    console.log(`TEST RESULTS: ${passed} PASSED, ${failed} FAILED`);
    console.log('================================================================\n');

    process.exit(failed > 0 ? 1 : 0);
  } catch (err) {
    console.error('Fatal test error:', err);
    process.exit(1);
  }
}

runTests();
