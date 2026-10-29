const { execSync } = require('child_process');
const fs = require('fs');

const script = `
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
`;

fs.writeFileSync('check_order_snippet.js', script);

const cmd = {
  commands: [
    'export PATH=$PATH:/usr/local/bin:/usr/bin:~/.nvm/versions/node/$(ls ~/.nvm/versions/node 2>/dev/null | tail -n 1)/bin',
    'export NODE_PATH=/opt/staydriv/node_modules',
    `cat << 'EOF' > /tmp/check_order.js\n${script}\nEOF`,
    'node /tmp/check_order.js'
  ]
};

fs.writeFileSync('ssm_check_order.json', JSON.stringify(cmd, null, 2));

try {
  const res = execSync('aws ssm send-command --instance-ids i-090dbc33c50d882c6 --document-name AWS-RunShellScript --parameters file://ssm_check_order.json --region ap-south-2 --output json').toString();
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
        if (j.StandardErrorContent) console.log('STDERR:\n', j.StandardErrorContent);
      }
    } catch (e) {
      console.error('Poll error:', e.message);
    }
  }, 2000);
} catch (e) {
  console.error('Execution error:', e.message);
}
