const express = require('express');
const mongoose = require('mongoose');
const assert = require('assert');
const http = require('http');

require('dotenv').config();

const Restaurant = require('./models/Restaurant');
const FoodOrder = require('./models/FoodOrder');
const RestaurantSettlement = require('./models/RestaurantSettlement');
const foodRoutes = require('./routes/foodRoutes');

async function testEndpoint() {
  console.log('Connecting to MongoDB...');
  await mongoose.connect(process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/staydriv');

  const app = express();
  app.use(express.json());
  app.use('/api/food', foodRoutes);

  const server = app.listen(0);
  const port = server.address().port;
  console.log(`Test server running on port ${port}`);

  const testRestId = `REST_BREAKDOWN_TEST_${Date.now()}`;
  await Restaurant.create({
    restaurantId: testRestId,
    name: 'Breakdown Test Kitchen',
    status: 'approved',
    isOpen: true,
    lat: 17.44,
    lng: 78.38,
    address: 'Madhapur, Hyderabad',
    phone: '9876543210',
    commissionRate: 15.0
  });

  // 1. Delivered order
  await FoodOrder.create({
    orderId: `FD_DELIV_${Date.now()}`,
    customerId: 'CUST_1',
    customerName: 'Priya Sharma',
    customerPhone: '9876543210',
    deliveryAddress: 'Flat 101, Test Residency',
    restaurantId: testRestId,
    restaurantName: 'Breakdown Test Kitchen',
    items: [{ itemId: 'item1', name: 'Paneer Butter Masala', price: 250, quantity: 2, isVeg: true }],
    subtotal: 500,
    packagingFee: 30,
    totalAmount: 560,
    paymentMethod: 'online',
    paymentStatus: 'paid',
    orderStatus: 'delivered',
    deliveryPartnerId: 'PILOT_101',
    deliveryPartnerName: 'Ramesh Pilot',
    deliveredAt: new Date()
  });

  // 2. Returned order (Customer refused / not reachable)
  await FoodOrder.create({
    orderId: `FD_RET_CUST_${Date.now()}`,
    customerId: 'CUST_2',
    customerName: 'Rahul Verma',
    customerPhone: '9876543211',
    deliveryAddress: 'Flat 202, Test Tower',
    restaurantId: testRestId,
    restaurantName: 'Breakdown Test Kitchen',
    items: [{ itemId: 'item2', name: 'Veg Biryani Special', price: 300, quantity: 1, isVeg: true }],
    subtotal: 300,
    packagingFee: 20,
    totalAmount: 350,
    paymentMethod: 'online',
    paymentStatus: 'paid',
    orderStatus: 'returned_to_restaurant',
    returnReason: 'Customer phone switched off & address locked',
    returnNotes: 'Returned to restaurant and 4-digit OTP verified',
    returnOtpVerified: true,
    deliveryPartnerId: 'PILOT_102',
    deliveryPartnerName: 'Kiran Pilot',
    returnedAt: new Date()
  });

  // 3. Returned order (Restaurant fault)
  await FoodOrder.create({
    orderId: `FD_RET_FAULT_${Date.now()}`,
    customerId: 'CUST_3',
    customerName: 'Anil Kumar',
    customerPhone: '9876543212',
    deliveryAddress: 'Flat 303, Test Residency',
    restaurantId: testRestId,
    restaurantName: 'Breakdown Test Kitchen',
    items: [{ itemId: 'item3', name: 'Chicken Biryani', price: 350, quantity: 1, isVeg: false }],
    subtotal: 350,
    packagingFee: 20,
    totalAmount: 400,
    paymentMethod: 'online',
    paymentStatus: 'paid',
    orderStatus: 'returned_to_restaurant',
    returnReason: 'Wrong item sent by restaurant - customer ordered Veg Biryani',
    returnOtpVerified: true,
    deliveryPartnerId: 'PILOT_103',
    deliveryPartnerName: 'Vijay Pilot',
    returnedAt: new Date()
  });

  // Make HTTP request to /api/food/partner/:restaurantId/sales-breakdown
  const res = await fetch(`http://127.0.0.1:${port}/api/food/partner/${testRestId}/sales-breakdown`);
  const data = await res.json();

  assert.strictEqual(data.success, true);
  assert.strictEqual(data.orders.length, 3);

  const delivOrder = data.orders.find(o => o.orderId.includes('FD_DELIV_'));
  assert.strictEqual(delivOrder.orderStatus, 'Delivered');
  assert.strictEqual(delivOrder.isReturned, false);
  assert.strictEqual(delivOrder.isPayable, true);
  assert.strictEqual(delivOrder.grossAmount, 530);
  assert.strictEqual(delivOrder.commission, 75);
  assert.strictEqual(delivOrder.netAmount, 455);
  assert.strictEqual(delivOrder.settlementStatus, 'pending');

  const retCustOrder = data.orders.find(o => o.orderId.includes('FD_RET_CUST_'));
  assert.strictEqual(retCustOrder.orderStatus, 'Returned to Restaurant');
  assert.strictEqual(retCustOrder.isReturned, true);
  assert.strictEqual(retCustOrder.isPayable, true);
  assert.strictEqual(retCustOrder.returnReason, 'Customer phone switched off & address locked');
  assert.strictEqual(retCustOrder.pilotName, 'Kiran Pilot');
  assert.strictEqual(retCustOrder.grossAmount, 320);
  assert.strictEqual(retCustOrder.commission, 45);
  assert.strictEqual(retCustOrder.netAmount, 275);
  assert.strictEqual(retCustOrder.settlementStatus, 'pending');

  const retFaultOrder = data.orders.find(o => o.orderId.includes('FD_RET_FAULT_'));
  assert.strictEqual(retFaultOrder.orderStatus, 'Returned to Restaurant');
  assert.strictEqual(retFaultOrder.isReturned, true);
  assert.strictEqual(retFaultOrder.isPayable, false);
  assert.strictEqual(retFaultOrder.netAmount, 0);
  assert.strictEqual(retFaultOrder.settlementStatus, 'not_payable');
  assert.ok(retFaultOrder.payableReason.includes('quality') || retFaultOrder.payableReason.includes('Non-payable'));

  console.log('✓ Delivered order verified: netAmount = ₹455, status = Delivered, settlement = pending');
  console.log('✓ Returned (customer non-delivery) verified: netAmount = ₹275, status = Returned to Restaurant, returnReason, pilotName, settlement = pending');
  console.log('✓ Returned (restaurant fault) verified: netAmount = ₹0, status = Returned to Restaurant, settlement = not_payable');

  // Test summary API as well
  const sumRes = await fetch(`http://127.0.0.1:${port}/api/food/partner/${testRestId}/settlements/summary`);
  const sumData = await sumRes.json();
  assert.strictEqual(sumData.success, true);
  assert.strictEqual(sumData.summary.completedOrdersCount, 1);
  assert.strictEqual(sumData.summary.returnedOrdersCount, 1);
  assert.strictEqual(sumData.summary.nonPayableOrdersCount, 1);
  // Total payable sales = (500 + 30) + (300 + 20) = 850
  assert.strictEqual(sumData.summary.totalSales, 850);
  // Commission = (500 + 300) * 15% = 800 * 0.15 = 120
  assert.strictEqual(sumData.summary.platformCommissionAmount, 120);
  // Net earnings = 850 - 120 = 730
  assert.strictEqual(sumData.summary.netEarnings, 730);
  assert.strictEqual(sumData.summary.pendingSettlement, 730);
  console.log('✓ Summary cards reconciliation verified: 1 Delivered, 1 Returned Payable, 1 Non-Payable, Net = ₹730, Pending = ₹730');

  // Clean up test data
  await FoodOrder.deleteMany({ restaurantId: testRestId });
  await Restaurant.deleteOne({ restaurantId: testRestId });

  server.close();
  await mongoose.disconnect();
  console.log('\n🎉 ALL PARTNER SALES BREAKDOWN ENDPOINT TESTS PASSED SUCCESSFULLY!');
}

testEndpoint().catch(err => {
  console.error('Test error:', err);
  process.exit(1);
});
