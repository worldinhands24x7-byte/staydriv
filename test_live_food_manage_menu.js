// Automated End-to-End Test for Manage Menu, Pricing, Availability, Soft-Delete & OTP Handover
const https = require('https');

const BASE_URL = 'https://dk60tgl9yds4p.cloudfront.net';

function request(method, path, body = null) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, BASE_URL);
    const options = {
      method,
      hostname: url.hostname,
      port: 443,
      path: url.pathname + url.search,
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'StayDriv-E2E-Tester/1.0'
      }
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        let parsed;
        try {
          parsed = JSON.parse(data);
        } catch (_) {
          parsed = data;
        }
        resolve({ status: res.statusCode, data: parsed });
      });
    });

    req.on('error', reject);
    if (body) {
      req.write(JSON.stringify(body));
    }
    req.end();
  });
}

async function runTests() {
  console.log('================================================================');
  console.log('🚀 RUNNING END-TO-END VERIFICATION ON LIVE PRODUCTION CLOUDFRONT');
  console.log(`🌐 Base URL: ${BASE_URL}`);
  console.log('================================================================\n');

  let passed = 0;
  let failed = 0;

  function assert(condition, message) {
    if (condition) {
      console.log(`✅ [PASS] ${message}`);
      passed++;
    } else {
      console.error(`❌ [FAIL] ${message}`);
      failed++;
    }
  }

  try {
    // Step 1: Fetch active restaurants
    console.log('--- STEP 1: Fetching Active Restaurants ---');
    const restRes = await request('GET', '/api/food/restaurants?lat=17.4855&lng=78.3976');
    assert(restRes.status === 200 && Array.isArray(restRes.data.restaurants), 'Restaurants fetched successfully');
    
    let targetRestaurant = restRes.data.restaurants[0];
    if (!targetRestaurant) {
      // Fetch via admin
      const adminRest = await request('GET', '/api/food/admin/restaurants');
      targetRestaurant = (adminRest.data.restaurants || [])[0];
    }
    assert(targetRestaurant && targetRestaurant.restaurantId, `Target restaurant found: ${targetRestaurant?.name || 'N/A'} (ID: ${targetRestaurant?.restaurantId})`);
    const restaurantId = targetRestaurant.restaurantId;

    // Step 2: Add a new Food Item
    console.log('\n--- STEP 2: Adding a New Food Item to Menu ---');
    const uniqueDishName = `Special Hyderabadi Royal Dum Biryani ${Date.now()}`;
    const newItemPayload = {
      name: uniqueDishName,
      category: 'Biryani Special',
      price: 380,
      discountPrice: 320,
      prepTime: '25 mins',
      description: 'Slow-cooked aromatic basmati rice layered with marinated tender chicken and royal spices.',
      imageUrl: 'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8',
      isVeg: false,
      isAvailable: true
    };

    const addRes = await request('POST', `/api/food/partner/${restaurantId}/menu`, newItemPayload);
    assert(addRes.status === 201 && addRes.data.success, `Food item added: "${uniqueDishName}" (Status: ${addRes.status})`);
    const createdItem = addRes.data.item;
    assert(createdItem && createdItem.itemId, `Item created with ID: ${createdItem?.itemId}`);
    assert(createdItem.discountPrice === 320, `Item has correct discountPrice: ₹${createdItem.discountPrice}`);
    assert(createdItem.prepTime === '25 mins', `Item has correct prepTime: ${createdItem.prepTime}`);
    const itemId = createdItem.itemId;

    // Step 3: Prevent duplicate active dish submission
    console.log('\n--- STEP 3: Duplicate Dish Name Prevention ---');
    const dupRes = await request('POST', `/api/food/partner/${restaurantId}/menu`, newItemPayload);
    assert(dupRes.status === 400 && !dupRes.data.success, `Duplicate submission rejected with status 400: "${dupRes.data.message}"`);

    // Step 4: Verify item in Menu API
    console.log('\n--- STEP 4: Verifying Item in Partner Menu API ---');
    const menuRes = await request('GET', `/api/food/partner/${restaurantId}/menu`);
    const menuList = menuRes.data.menuItems || menuRes.data.menu || [];
    assert(menuRes.status === 200 && Array.isArray(menuList), 'Partner menu retrieved successfully');
    const fetchedItem = menuList.find(i => i.itemId === itemId);
    assert(fetchedItem && fetchedItem.name === uniqueDishName, `Created item found in partner menu`);
    assert(fetchedItem.price === 380 && fetchedItem.discountPrice === 320, `Pricing matches: Normal ₹${fetchedItem.price}, Discount ₹${fetchedItem.discountPrice}`);

    // Step 5: Edit Item Details
    console.log('\n--- STEP 5: Editing Food Item Details ---');
    const updatePayload = {
      name: uniqueDishName,
      category: 'Royal Biryani Specials',
      price: 399,
      discountPrice: 349,
      prepTime: '30 mins',
      description: 'Updated signature recipe with pure saffron and crispy golden fried onions.',
      imageUrl: 'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8',
      isVeg: false,
      isAvailable: true
    };
    const editRes = await request('PUT', `/api/food/partner/${restaurantId}/menu/${itemId}`, updatePayload);
    assert(editRes.status === 200 && editRes.data.success, `Food item edited successfully (Status: ${editRes.status})`);
    assert(editRes.data.item.price === 399, `Updated price is ₹${editRes.data.item.price}`);
    assert(editRes.data.item.discountPrice === 349, `Updated discountPrice is ₹${editRes.data.item.discountPrice}`);
    assert(editRes.data.item.prepTime === '30 mins', `Updated prepTime is ${editRes.data.item.prepTime}`);

    // Step 6: Real-time In-Stock / Out-of-Stock Toggle
    console.log('\n--- STEP 6: Real-Time Availability Toggle ---');
    const availOffRes = await request('PATCH', `/api/food/partner/${restaurantId}/menu/${itemId}/availability`, { isAvailable: false });
    assert(availOffRes.status === 200 && availOffRes.data.item.isAvailable === false, 'Item toggled to Out of Stock');

    const availOnRes = await request('PATCH', `/api/food/partner/${restaurantId}/menu/${itemId}/availability`, { isAvailable: true });
    assert(availOnRes.status === 200 && availOnRes.data.item.isAvailable === true, 'Item toggled back to In Stock');

    // Step 7: Soft-delete / Archiving
    console.log('\n--- STEP 7: Safe Soft-Delete / Archiving Food Item ---');
    const delRes = await request('DELETE', `/api/food/partner/${restaurantId}/menu/${itemId}`);
    assert(delRes.status === 200 && delRes.data.success, `Item soft-deleted successfully: "${delRes.data.message}"`);

    // Step 8: Verify item removed from Active Menu
    console.log('\n--- STEP 8: Verifying Item Excluded from Active Customer Menu ---');
    const menuAfterDel = await request('GET', `/api/food/partner/${restaurantId}/menu`);
    const afterList = menuAfterDel.data.menuItems || menuAfterDel.data.menu || [];
    const existsInPartner = afterList.some(i => i.itemId === itemId);
    assert(!existsInPartner, 'Soft-deleted item is excluded from active partner menu');

    const custMenuAfterDel = await request('GET', `/api/food/restaurants/${restaurantId}`);
    const existsInCustomer = (custMenuAfterDel.data.restaurant?.menu || []).some(i => i.itemId === itemId);
    assert(!existsInCustomer, 'Soft-deleted item is excluded from customer restaurant details');

    // Step 9: Order Verification with Customer OTP and Restaurant OTP
    console.log('\n--- STEP 9: Food Order Placement with Dual OTP Generation ---');
    // Re-enable or create a clean orderable item
    const orderItemPayload = {
      name: `Order Verification Item ${Date.now()}`,
      category: 'Starters',
      price: 150,
      discountPrice: 130,
      prepTime: '15 mins',
      imageUrl: 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c',
      isVeg: true,
      isAvailable: true
    };
    const orderDishRes = await request('POST', `/api/food/partner/${restaurantId}/menu`, orderItemPayload);
    const orderDishId = orderDishRes.data.item.itemId;

    const orderPayload = {
      customerId: 'CUST_TEST_E2E',
      customerName: 'Aarav Sharma',
      customerPhone: '9876543210',
      deliveryAddress: 'Flat 402, Lotus Towers, Madhapur, Hyderabad',
      deliveryLatLng: { lat: 17.4483, lng: 78.3915 },
      deliveryInstructions: 'Ring doorbell twice. Handover food at doorstep.',
      restaurantId: restaurantId,
      items: [
        {
          itemId: orderDishId,
          name: orderItemPayload.name,
          price: 130,
          quantity: 2,
          isVeg: true
        }
      ],
      paymentMethod: 'online'
    };

    const placeOrderRes = await request('POST', '/api/food/orders', orderPayload);
    assert(placeOrderRes.status === 201 && placeOrderRes.data.success, `Order placed successfully: ID ${placeOrderRes.data.order?.orderId}`);
    const placedOrder = placeOrderRes.data.order;
    assert(placedOrder && placedOrder.customerOtp && placedOrder.customerOtp.length === 4, `Customer OTP generated: ${placedOrder?.customerOtp}`);
    assert(placedOrder && placedOrder.restaurantOtp && placedOrder.restaurantOtp.length === 4, `Restaurant OTP generated: ${placedOrder?.restaurantOtp}`);
    assert(placedOrder && placedOrder.customerOtp !== placedOrder.restaurantOtp, `Customer OTP (${placedOrder?.customerOtp}) and Restaurant OTP (${placedOrder?.restaurantOtp}) are distinct`);

    // Clean up temporary order dish
    await request('DELETE', `/api/food/partner/${restaurantId}/menu/${orderDishId}`);

    // Step 10: Admin Search by OTP
    console.log('\n--- STEP 10: Admin Orders Query with OTP Search ---');
    const adminOrdersRes = await request('GET', `/api/food/admin/orders?search=${placedOrder.customerOtp}`);
    assert(adminOrdersRes.status === 200, 'Admin orders search endpoint responded with 200');
    const foundOrderByOtp = (adminOrdersRes.data.orders || []).find(o => o.orderId === placedOrder.orderId);
    assert(foundOrderByOtp != null, `Admin search by Customer OTP (${placedOrder.customerOtp}) located order ${placedOrder.orderId}`);
    assert(foundOrderByOtp.restaurantOtp === placedOrder.restaurantOtp, `Admin order displays Restaurant OTP: ${foundOrderByOtp?.restaurantOtp}`);

    console.log('\n================================================================');
    console.log(`SUMMARY: ${passed} PASSED, ${failed} FAILED`);
    console.log('================================================================');

    if (failed > 0) {
      process.exit(1);
    } else {
      process.exit(0);
    }
  } catch (err) {
    console.error('Test execution failed with error:', err);
    process.exit(1);
  }
}

runTests();
