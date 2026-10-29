
const mongoose = require('mongoose');
mongoose.connect('mongodb://localhost:27017/staydriv').then(async () => {
  const FoodOrder = mongoose.models.FoodOrder || mongoose.model('FoodOrder', new mongoose.Schema({}, { strict: false }));
  const o = await FoodOrder.findOne({ orderId: 'FD_1792505663535_B6CF29' }).lean();
  console.log('ORDER DATA:', JSON.stringify(o, null, 2));
  process.exit(0);
}).catch(e => {
  console.error(e);
  process.exit(1);
});
