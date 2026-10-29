const FoodConfig = require('../models/FoodConfig');

async function seedInitialFoodData() {
  try {
    // 1. Ensure FoodConfig exists
    const configCount = await FoodConfig.countDocuments();
    if (configCount === 0) {
      await FoodConfig.create({
        configId: 'staydriv_food_config',
        platformFee: 15,
        deliveryBaseFee: 30,
        taxRatePercent: 5.0,
        defaultCommissionRate: 15.0,
        categories: [
          'Biryani',
          'South Indian',
          'North Indian',
          'Pizza',
          'Burgers',
          'Chinese',
          'Snacks',
          'Desserts',
          'Rolls',
          'Beverages'
        ]
      });
      console.log('[FOOD] Initial FoodConfig created.');
    }
    // No mock restaurants, mock food items, or fake orders are ever seeded.
    // Genuine restaurants are registered and approved via the Admin Console and Partner app.
  } catch (err) {
    console.error('[FOOD] Error in seedInitialFoodData:', err.message);
  }
}

module.exports = { seedInitialFoodData };
