const { execSync } = require('child_process');
const fs = require('fs');

const env = { ...process.env, PYTHONIOENCODING: 'utf-8', PYTHONUTF8: '1' };

const instanceId = execSync('aws ec2 describe-instances --region ap-south-2 --filters "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].InstanceId" --output text', { encoding: 'utf8', env }).trim().split(/\s+/)[0];
console.log('Running instance:', instanceId);

const nodeScript = `
const mongoose = require('mongoose');
require('dotenv').config({ path: '/opt/staydriv/.env' });
const mongoUri = process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/staydriv';
mongoose.connect(mongoUri).then(async () => {
  const FoodOrder = mongoose.model('FoodOrder', new mongoose.Schema({}, { strict: false }));
  const FinancialLedger = mongoose.model('FinancialLedger', new mongoose.Schema({}, { strict: false }));
  const delO = await FoodOrder.deleteMany({ customerId: 'cust_prod_test_01' });
  const delL = await FinancialLedger.deleteMany({ orderId: /^FD_179255/ });
  console.log('Deleted test orders:', delO.deletedCount, 'Deleted test ledger entries:', delL.deletedCount);
  process.exit(0);
}).catch(e => { console.error(e); process.exit(1); });
`;

const commands = [
  'cd /opt/staydriv',
  `cat << 'EOF' > /opt/staydriv/clean_test_order.js\n${nodeScript}\nEOF`,
  'NODE_PATH=/opt/staydriv/node_modules node /opt/staydriv/clean_test_order.js',
  'rm -f /opt/staydriv/clean_test_order.js'
];

fs.writeFileSync('ssm_clean_test.json', JSON.stringify({
  InstanceIds: [instanceId],
  DocumentName: 'AWS-RunShellScript',
  Parameters: { commands }
}));

const cmdId = execSync('aws ssm send-command --cli-input-json file://ssm_clean_test.json --region ap-south-2 --query Command.CommandId --output text', { encoding: 'utf8', env }).trim();
console.log('Command ID:', cmdId);

let attempts = 0;
while (attempts < 20) {
  execSync('timeout /t 2 > nul 2>&1 || ping 127.0.0.1 -n 3 > nul');
  attempts++;
  try {
    const invStr = execSync(`aws ssm get-command-invocation --command-id ${cmdId} --instance-id ${instanceId} --region ap-south-2 --output json`, { encoding: 'utf8', env });
    const inv = JSON.parse(invStr);
    if (inv.Status === 'Success' || inv.Status === 'Failed') {
      console.log('Status:', inv.Status);
      console.log('Output:', inv.StandardOutputContent);
      break;
    }
  } catch (e) {}
}
