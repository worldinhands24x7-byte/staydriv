const https = require('https');

const BASE_URL = 'https://dk60tgl9yds4p.cloudfront.net';

function request(method, path, body = null, headers = {}) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, BASE_URL);
    const reqHeaders = {
      'Content-Type': 'application/json',
      'User-Agent': 'StayDriv-E2E-Tester',
      ...headers
    };

    const req = https.request(url, {
      method,
      headers: reqHeaders,
      timeout: 10000
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          resolve({ status: res.statusCode, data: json });
        } catch (e) {
          resolve({ status: res.statusCode, raw: data });
        }
      });
    });

    req.on('error', reject);
    req.on('timeout', () => {
      req.destroy();
      reject(new Error('Request timed out'));
    });

    if (body) {
      req.write(JSON.stringify(body));
    }
    req.end();
  });
}

async function runTests() {
  console.log('====================================================');
  console.log('🚀 RUNNING PRODUCTION E2E VERIFICATION FOR MANAGE MENU');
  console.log(`Target: ${BASE_URL}`);
  console.log('====================================================\n');

  // Step 1: Discover an active restaurant
  console.log('Step 1: Finding an approved restaurant...');
  const restRes = await request('GET', '/api/food/restaurants');
  if (!restRes.data || !restRes.data.restaurants || restRes.data.restaurants.length === 0) {
    throw new Error('No restaurants returned from /api/food/restaurants');
  }
  const restaurant = restRes.data.restaurants[0];
  const restaurantId = restaurant.restaurantId;
  console.log(`✅ Using Restaurant: "${restaurant.name}" (ID: ${restaurantId})\n`);

  // Step 2: Add a new food item with discountPrice & prepTime
  const uniqueSuffix = Date.now();
  const testDishName = `Signature Dum Biryani ${uniqueSuffix}`;
  console.log(`Step 2: Adding new dish "${testDishName}" with discountPrice & prepTime...`);
  const addRes = await request('POST', `/api/food/partner/${restaurantId}/menu`, {
    name: testDishName,
    category: 'Biryani',
    description: 'Slow-cooked royal biryani with fragrant basmati and aromatic spices.',
    price: 360,
    discountPrice: 310,
    isVeg: false,
    isAvailable: true,
    imageUrl: 'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=800&auto=format&fit=crop&q=80',
    prepTime: '25 mins',
    isBestseller: true,
    isRecommended: true
  });

  if (addRes.status !== 201 || !addRes.data.success || !addRes.data.item) {
    console.error('Add Item Failed:', addRes);
    throw new Error(`Failed to add menu item: ${JSON.stringify(addRes.data)}`);
  }
  const createdItem = addRes.data.item;
  const itemId = createdItem.itemId;
  console.log(`✅ Dish created successfully: ItemId: ${itemId}, Price: ₹${createdItem.price}, Discount: ₹${createdItem.discountPrice}, Prep: ${createdItem.prepTime}\n`);

  // Step 3: Prevent duplicate dish submission with same name
  console.log('Step 3: Testing duplicate dish prevention with identical name...');
  const dupRes = await request('POST', `/api/food/partner/${restaurantId}/menu`, {
    name: testDishName,
    category: 'Biryani',
    price: 360,
    discountPrice: 310,
    isVeg: false
  });
  if (dupRes.status === 400 && dupRes.data.success === false) {
    console.log(`✅ Duplicate correctly rejected with 400: "${dupRes.data.message}"\n`);
  } else {
    throw new Error(`Duplicate was NOT rejected as expected! Status: ${dupRes.status}`);
  }

  // Step 4: Verify Customer App Menu sees the new dish
  console.log('Step 4: Verifying Customer App menu reflects new dish and discountPrice...');
  const custMenuRes = await request('GET', `/api/food/restaurants/${restaurantId}`);
  if (custMenuRes.status !== 200 || !custMenuRes.data.success) {
    throw new Error('Failed to fetch restaurant details for customer');
  }
  const foundInCustomer = custMenuRes.data.menuItems.find(i => i.itemId === itemId);
  if (!foundInCustomer) {
    throw new Error('Dish not found in customer menu items list');
  }
  console.log(`✅ Dish visible in customer menu: ${foundInCustomer.name}, Price: ₹${foundInCustomer.price}, Discount: ₹${foundInCustomer.discountPrice}\n`);

  // Step 5: Edit the dish details (without creating duplicates)
  console.log('Step 5: Editing dish details (price, discountPrice, prepTime)...');
  const updatedDishName = `Signature Dum Biryani ${uniqueSuffix} (Special)`;
  const editRes = await request('PUT', `/api/food/partner/${restaurantId}/menu/${itemId}`, {
    name: updatedDishName,
    category: 'Biryani',
    price: 390,
    discountPrice: 330,
    prepTime: '20 mins',
    description: 'Updated slow-cooked royal biryani with saffron and tender meat.'
  });
  if (editRes.status !== 200 || !editRes.data.success) {
    throw new Error(`Failed to edit dish: ${JSON.stringify(editRes.data)}`);
  }
  console.log(`✅ Dish updated successfully: ${editRes.data.item.name}, Price: ₹${editRes.data.item.price}, Discount: ₹${editRes.data.item.discountPrice}\n`);

  // Step 6: Test Real-Time Availability Toggle & Cart Validation
  console.log('Step 6: Testing Real-time Out-of-Stock toggle & Cart Protection...');
  // Toggle Out of Stock
  const oosRes = await request('PATCH', `/api/food/partner/${restaurantId}/menu/${itemId}/availability`, {
    isAvailable: false
  });
  if (oosRes.status !== 200 || !oosRes.data.success || oosRes.data.item.isAvailable !== false) {
    throw new Error(`Failed to toggle dish to Out of Stock: ${JSON.stringify(oosRes.data)}`);
  }
  console.log('✅ Marked dish as Out of Stock');

  // Attempt to validate cart with Out of Stock item
  const oosCartRes = await request('POST', '/api/food/validate-cart', {
    restaurantId,
    items: [{ itemId, quantity: 2, name: updatedDishName }]
  });
  if (oosCartRes.status === 400 && oosCartRes.data.success === false && oosCartRes.data.message.includes('out of stock')) {
    console.log(`✅ Cart validation blocked out-of-stock item: "${oosCartRes.data.message}"`);
  } else {
    throw new Error(`Cart validation did not block out of stock item! Status: ${oosCartRes.status}, Data: ${JSON.stringify(oosCartRes.data)}`);
  }

  // Toggle back to In Stock
  const inStockRes = await request('PATCH', `/api/food/partner/${restaurantId}/menu/${itemId}/availability`, {
    isAvailable: true
  });
  if (inStockRes.status !== 200 || !inStockRes.data.success || inStockRes.data.item.isAvailable !== true) {
    throw new Error(`Failed to toggle dish back In Stock: ${JSON.stringify(inStockRes.data)}`);
  }
  console.log('✅ Toggled dish back In Stock');

  // Re-verify cart validation passes
  const validCartRes = await request('POST', '/api/food/validate-cart', {
    restaurantId,
    items: [{ itemId, quantity: 2, name: updatedDishName }]
  });
  if (validCartRes.status === 200 && validCartRes.data.success && validCartRes.data.totalAmount > 0) {
    console.log(`✅ Cart validation passed when In Stock: Subtotal: ₹${validCartRes.data.subtotal}, Grand Total: ₹${validCartRes.data.totalAmount}\n`);
  } else {
    throw new Error(`Cart validation failed unexpectedly: ${JSON.stringify(validCartRes.data)}`);
  }

  // Step 7: Safe Soft-Delete / Archiving
  console.log('Step 7: Testing Safe Soft-Delete (Archive)...');
  const delRes = await request('DELETE', `/api/food/partner/${restaurantId}/menu/${itemId}`);
  if (delRes.status !== 200 || !delRes.data.success) {
    throw new Error(`Failed to soft-delete item: ${JSON.stringify(delRes.data)}`);
  }
  console.log(`✅ Soft-delete response: "${delRes.data.message}"`);

  // Verify item is removed from partner active menu
  const partnerMenuAfterDel = await request('GET', `/api/food/partner/${restaurantId}/menu`);
  const stillInPartner = partnerMenuAfterDel.data.menuItems.find(i => i.itemId === itemId);
  if (stillInPartner) {
    throw new Error('Deleted item still appears in partner menu!');
  }
  console.log('✅ Item confirmed removed from Partner Menu list');

  // Verify item is removed from customer menu
  const custMenuAfterDel = await request('GET', `/api/food/restaurants/${restaurantId}`);
  const stillInCust = custMenuAfterDel.data.menuItems.find(i => i.itemId === itemId);
  if (stillInCust) {
    throw new Error('Deleted item still appears in customer menu!');
  }
  console.log('✅ Item confirmed removed from Customer Menu list');

  // Verify cart validation rejects deleted item
  const delCartRes = await request('POST', '/api/food/validate-cart', {
    restaurantId,
    items: [{ itemId, quantity: 1, name: updatedDishName }]
  });
  if (delCartRes.status === 400 && delCartRes.data.message.includes('no longer available')) {
    console.log(`✅ Cart validation blocked deleted item: "${delCartRes.data.message}"\n`);
  } else {
    throw new Error(`Cart validation did not block deleted item! Status: ${delCartRes.status}`);
  }

  console.log('====================================================');
  console.log('🎉 ALL 7 E2E VERIFICATION STEPS PASSED SUCCESSFULLY!');
  console.log('====================================================');
}

runTests().catch(err => {
  console.error('\n❌ E2E TEST FAILED:', err.message);
  process.exit(1);
});
