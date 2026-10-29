const { execSync } = require('child_process');
const fs = require('fs');

const script = `
const mongoose = require('mongoose');
mongoose.connect('mongodb://localhost:27017/staydriv').then(async () => {
  const Restaurant = mongoose.models.Restaurant || mongoose.model('Restaurant', new mongoose.Schema({}, { strict: false }));
  const rests = await Restaurant.find({}).lean();
  console.log('TOTAL RESTAURANTS IN DB:', rests.length);
  rests.forEach(r => {
    console.log({
      restaurantId: r.restaurantId,
      name: r.name,
      phone: r.phone,
      status: r.status,
      isOpen: r.isOpen,
      createdAt: r.createdAt
    });
  });

  const FoodOrder = mongoose.models.FoodOrder || mongoose.model('FoodOrder', new mongoose.Schema({}, { strict: false }));
  const orders = await FoodOrder.find({}).sort({ createdAt: -1 }).limit(20).lean();
  console.log('RECENT FOOD ORDERS COUNT:', orders.length);
  orders.forEach(o => {
    console.log({
      orderId: o.orderId,
      restaurantName: o.restaurantName,
      customerName: o.customerName,
      customerPhone: o.customerPhone,
      deliveryPartnerName: o.deliveryPartnerName,
      deliveryPartnerPhone: o.deliveryPartnerPhone,
      orderStatus: o.orderStatus,
      createdAt: o.createdAt
    });
  });

  process.exit(0);
}).catch(e => {
  console.error(e);
  process.exit(1);
});
`;

const cmd = {
  commands: [
    'export PATH=$PATH:/usr/local/bin:/usr/bin:~/.nvm/versions/node/$(ls ~/.nvm/versions/node 2>/dev/null | tail -n 1)/bin',
    'export NODE_PATH=/opt/staydriv/node_modules',
    `cat << 'EOF' > /tmp/list_food_data.js\n${script}\nEOF`,
    'node /tmp/list_food_data.js'
  ]
};

fs.writeFileSync('ssm_list_food_data.json', JSON.stringify(cmd, null, 2));
const res = execSync('aws ssm send-command --instance-ids i-090dbc33c50d882c6 --document-name AWS-RunShellScript --parameters file://ssm_list_food_data.json --region ap-south-2 --output json').toString();
const cmdId = JSON.parse(res).Command.CommandId;
console.log('Sent SSM command:', cmdId);

let attempts = 0;
const poll = setInterval(() => {
  attempts++;
  try {
    const out = execSync(`aws ssm get-command-invocation --command-id ${cmdId} --instance-id i-090dbc33c50d882c6 --region ap-south-2 --output json`).toString();
    const j = JSON.parse(out);
    if (j.Status === 'Success' || j.Status === 'Failed' || attempts > 10) {
      clearInterval(poll);
      console.log('Status:', j.Status);
      console.log('STDOUT:\n', j.StandardOutputContent);
    }
  } catch (e) {}
}, 2000);
