const { execSync } = require('child_process');
const fs = require('fs');

const nodeScript = `
const mongoose = require("mongoose");
require("dotenv").config({ path: "/opt/staydriv/.env" });
const mongoUri = process.env.MONGODB_URI || "mongodb://127.0.0.1:27017/staydriv";
mongoose.connect(mongoUri).then(async () => {
  const FoodOrder = mongoose.model("FoodOrder", new mongoose.Schema({}, { strict: false }));
  const del = await FoodOrder.deleteMany({ customerId: "cust_prod_test_01" });
  console.log("Cleaned test orders on EC2:", del.deletedCount);
  process.exit(0);
}).catch(e => { console.error(e); process.exit(1); });
`;

const commands = [
  'cd /opt/staydriv',
  `cat << 'EOF' > /opt/staydriv/clean_test_order.js\n${nodeScript}\nEOF`,
  'NODE_PATH=/opt/staydriv/node_modules node /opt/staydriv/clean_test_order.js',
  'rm -f /opt/staydriv/clean_test_order.js'
];

const jsonParam = JSON.stringify({
  InstanceIds: ['i-090dbc33c50d882c6'],
  DocumentName: 'AWS-RunShellScript',
  Parameters: { commands }
});

fs.writeFileSync('ssm_clean_test.json', jsonParam);

const cmdId = execSync('aws ssm send-command --cli-input-json file://ssm_clean_test.json --region ap-south-2 --query Command.CommandId --output text', {
  encoding: 'utf8',
  env: { ...process.env, PYTHONIOENCODING: 'utf-8', PYTHONUTF8: '1' }
}).trim();

console.log('Dispatched clean command:', cmdId);

let attempts = 0;
while (attempts < 20) {
  execSync('timeout /t 2 > nul 2>&1 || ping 127.0.0.1 -n 3 > nul');
  attempts++;
  try {
    const invStr = execSync(`aws ssm get-command-invocation --command-id ${cmdId} --instance-id i-090dbc33c50d882c6 --region ap-south-2 --output json`, {
      encoding: 'utf8',
      env: { ...process.env, PYTHONIOENCODING: 'utf-8', PYTHONUTF8: '1' }
    });
    const inv = JSON.parse(invStr);
    if (inv.Status === 'Success' || inv.Status === 'Failed') {
      console.log('Status:', inv.Status);
      console.log('STDOUT:\n', inv.StandardOutputContent);
      break;
    }
  } catch (e) {}
}
