const mongoose = require('mongoose');

async function cleanDummy() {
  await mongoose.connect('mongodb://localhost:27017/staydriv');
  const Restaurant = mongoose.models.Restaurant || mongoose.model('Restaurant', new mongoose.Schema({}, { strict: false }));
  const FoodItem = mongoose.models.FoodItem || mongoose.model('FoodItem', new mongoose.Schema({}, { strict: false }));
  
  const dummyIds = [
    'REST_PARADISE_01', 'REST_CHUTNEYS_02', 'REST_BAWARCHI_03', 
    'REST_PISTA_04', 'REST_PIZZA_05', 'REST_BURGER_06', 'REST_CHINESE_07'
  ];
  const rRes = await Restaurant.deleteMany({
    $or: [
      { restaurantId: { $in: dummyIds } },
      { name: { $regex: 'Test Bistro', $options: 'i' } }
    ]
  });
  const iRes = await FoodItem.deleteMany({
    $or: [
      { restaurantId: { $in: dummyIds } }
    ]
  });
  console.log('Deleted dummy restaurants:', rRes.deletedCount);
  console.log('Deleted dummy items:', iRes.deletedCount);

  const remaining = await Restaurant.find({}).lean();
  console.log('Remaining Genuine Restaurants:', remaining.map(r => r.name));
  process.exit(0);
}

cleanDummy().catch(err => {
  console.error(err);
  process.exit(1);
});
