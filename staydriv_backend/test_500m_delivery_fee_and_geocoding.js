const assert = require('assert');
const mongoose = require('mongoose');
const { calculateFoodBill, calculateDistanceKm } = require('./services/foodBillCalculationService');
const { geocodeAddress } = require('./services/geocodingService');
const Restaurant = require('./models/Restaurant');
const FoodItem = require('./models/FoodItem');
const FoodConfig = require('./models/FoodConfig');

const MONGO_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/staydriv';

async function run() {
  console.log('========================================================================');
  console.log('🧪 VERIFYING 500M DELIVERY FEE & RESTAURANT GEOCODING ACCURACY');
  console.log('========================================================================');

  await mongoose.connect(MONGO_URI);

  // 1. Check Distance Calculation between Hill Stone Restaurant (Gajularamaram) and Customer Address (Balaji Layout)
  // Hill Stone in Sri Balaji Layout: 17.5229502, 78.4221778
  // Customer in Balaji Layout Main Rd: 17.5250000, 78.4230000 (~300-500 meters away)
  const restLat = 17.5229502;
  const restLng = 78.4221778;
  const custLat = 17.5250000;
  const custLng = 78.4230000;

  const distKm = calculateDistanceKm(custLat, custLng, restLat, restLng);
  console.log(`Calculated real distance: ${distKm.toFixed(3)} km (${Math.round(distKm * 1000)} meters)`);
  assert(distKm < 1.0, 'Real distance between Gajularamaram restaurant and Balaji layout customer should be < 1 km');

  // 2. Setup mock restaurant in DB with accurate Gajularamaram coordinates
  const testRestId = `REST_HILL_STONE_TEST_${Date.now()}`;
  await Restaurant.deleteOne({ restaurantId: testRestId });
  const rest = await Restaurant.create({
    restaurantId: testRestId,
    name: 'Hill Stone Restaurant',
    phone: '9988776655',
    address: 'Plot No: 129, 3rd Floor, X’ Road, Sri Balaji Layout, Gajularamaram, Hyderabad, Telangana 500117',
    lat: restLat,
    lng: restLng,
    status: 'approved',
    isOpen: true,
    deliveryFee: 30
  });

  const testItemId = `ITEM_BIRYANI_${Date.now()}`;
  await FoodItem.create({
    itemId: testItemId,
    restaurantId: testRestId,
    name: 'Special Chicken Biryani',
    category: 'Biryani',
    price: 250,
    isAvailable: true
  });

  // 3. Calculate Bill for 500m customer order without platinum membership
  const billNonMember = await calculateFoodBill({
    restaurantId: testRestId,
    items: [{ itemId: testItemId, quantity: 1 }],
    deliveryAddress: 'Balaji Layout Main Rd, Sri Balaji Layout, HAL Colony, Gajularamaram, Hyderabad, Telangana 500055',
    deliveryLatLng: { lat: custLat, lng: custLng },
    customerId: 'CUST_REGULAR_NON_MEMBER',
    customerPhone: '9849011223',
    paymentMethod: 'online'
  });

  console.log('\n--- BILL BREAKDOWN FOR REGULAR CUSTOMER (500M) ---');
  console.log(`- Subtotal: ₹${billNonMember.subtotal}`);
  console.log(`- Distance: ${billNonMember.distanceKm} km (${billNonMember.distanceText})`);
  console.log(`- Packaging Fee: ₹${billNonMember.packagingFee}`);
  console.log(`- Original Delivery Fee: ₹${billNonMember.originalDeliveryFee}`);
  console.log(`- Customer Delivery Fee: ₹${billNonMember.customerDeliveryFee}`);
  console.log(`- Platform Fee: ₹${billNonMember.platformFee}`);
  console.log(`- Taxes: ₹${billNonMember.taxes}`);
  console.log(`- Grand Total: ₹${billNonMember.grandTotal}`);

  assert.strictEqual(billNonMember.customerDeliveryFee, 30, `Regular customer delivery fee for 500m must be base ₹30, got ₹${billNonMember.customerDeliveryFee}`);
  assert.strictEqual(billNonMember.originalDeliveryFee, 30, `Original delivery fee must be ₹30, got ₹${billNonMember.originalDeliveryFee}`);
  assert(billNonMember.distanceKm < 1.0, `distanceKm should be < 1.0 km, got ${billNonMember.distanceKm}`);
  console.log('✅ [PASS] Regular customer 500m delivery is charged base ₹30 (NOT the erroneous ₹121)!');

  // 4. Calculate Bill for Platinum member
  const billPlatinum = await calculateFoodBill({
    restaurantId: testRestId,
    items: [{ itemId: testItemId, quantity: 1 }],
    deliveryAddress: 'Balaji Layout Main Rd, Sri Balaji Layout, HAL Colony, Gajularamaram, Hyderabad, Telangana 500055',
    deliveryLatLng: { lat: custLat, lng: custLng },
    customerId: 'CUST_PLATINUM_MEMBER',
    customerPhone: '9490440281', // existing platinum user in db
    paymentMethod: 'online'
  });

  console.log('\n--- BILL BREAKDOWN FOR PLATINUM MEMBER (500M) ---');
  console.log(`- Customer Delivery Fee: ₹${billPlatinum.customerDeliveryFee} (Free Delivery Benefit)`);
  console.log(`- Original Delivery Fee: ₹${billPlatinum.originalDeliveryFee}`);
  console.log(`- StayDriv Funded Amount: ₹${billPlatinum.staydrivFundedDeliveryAmount}`);
  console.log(`- Pilot Earnings: ₹${billPlatinum.pilotEarnings}`);
  assert.strictEqual(billPlatinum.customerDeliveryFee, 0, 'Platinum member should get free delivery');
  assert.strictEqual(billPlatinum.pilotEarnings, 30, 'Pilot receives full ₹30 delivery fee');
  console.log('✅ [PASS] Platinum member receives ₹0 delivery fee while pilot is paid full ₹30!');

  // 4. Test Geocoding resolution for Hill Stone Restaurant address
  const geoResult = await geocodeAddress('Plot No: 129, 3rd Floor, X’ Road, Sri Balaji Layout, Gajularamaram, Hyderabad, Telangana 500117');
  console.log('\n--- GEOCODING RESOLUTION RESULT ---');
  console.log('Geocoded address:', geoResult ? geoResult.formattedAddress : 'null');
  console.log('Coordinates:', geoResult ? `${geoResult.lat}, ${geoResult.lng}` : 'null');
  assert(geoResult && geoResult.lat && geoResult.lng, 'Geocoding must resolve coordinates');
  assert(geoResult.lat > 17.5 && geoResult.lat < 17.6, 'Latitude must be in northern Hyderabad / Gajularamaram zone (~17.52 - 17.54)');
  console.log('✅ [PASS] Geocoding correctly locates restaurant in Gajularamaram area!');

  // Cleanup
  await Restaurant.deleteOne({ restaurantId: testRestId });
  await FoodItem.deleteOne({ itemId: testItemId });
  await mongoose.disconnect();

  console.log('\n========================================================================');
  console.log('🎉 ALL 500M DELIVERY FEE & GEOCODING TESTS PASSED SUCCESSFULLY!');
  console.log('========================================================================');
}

run().catch(err => {
  console.error('❌ Test failed:', err);
  process.exit(1);
});
