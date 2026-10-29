const { execSync } = require('child_process');
const fs = require('fs');

const nodeScript = [
  'const mongoose = require("mongoose");',
  'require("dotenv").config({ path: "/opt/staydriv/.env" });',
  'const mongoUri = process.env.MONGODB_URI || "mongodb://127.0.0.1:27017/staydriv";',
  'mongoose.connect(mongoUri).then(async () => {',
  '  const Restaurant = mongoose.model("Restaurant", new mongoose.Schema({}, { strict: false }));',
  '  const FoodItem = mongoose.model("FoodItem", new mongoose.Schema({}, { strict: false }));',
  '  const dummyIds = ["REST_PARADISE_01", "REST_CHUTNEYS_02", "REST_BAWARCHI_03", "REST_PISTA_04", "REST_PIZZA_05", "REST_BURGER_06", "REST_REDDRAGON_07"];',
  '  const delR = await Restaurant.deleteMany({',
  '    $or: [',
  '      { isDummy: true },',
  '      { restaurantId: { $in: dummyIds } }',
  '    ]',
  '  });',
  '  const delI = await FoodItem.deleteMany({',
  '    $or: [',
  '      { isDummy: true },',
  '      { restaurantId: { $in: dummyIds } }',
  '    ]',
  '  });',
  '  console.log("Purged dummy restaurants:", delR.deletedCount, "Purged dummy items:", delI.deletedCount);',
  '  const remaining = await Restaurant.find({}, "restaurantId name isApproved status").lean();',
  '  console.log("Remaining genuine restaurants count:", remaining.length);',
  '  remaining.forEach(r => console.log("  -", r.restaurantId, r.name, "| approved:", r.isApproved, "| status:", r.status));',
  '  process.exit(0);',
  '}).catch(e => { console.error(e); process.exit(1); });'
].join('\n');

const commands = [
  'cd /opt/staydriv',
  `cat << 'EOF' > /opt/staydriv/purge_dummy.js\n${nodeScript}\nEOF`,
  'NODE_PATH=/opt/staydriv/node_modules node /opt/staydriv/purge_dummy.js',
  'rm -f /opt/staydriv/purge_dummy.js'
];

const jsonParam = JSON.stringify({
  InstanceIds: ['i-090dbc33c50d882c6'],
  DocumentName: 'AWS-RunShellScript',
  Parameters: { commands }
});

fs.writeFileSync('ssm_purge.json', jsonParam);

const cmdId = execSync('aws ssm send-command --cli-input-json file://ssm_purge.json --region ap-south-2 --query Command.CommandId --output text', {
  encoding: 'utf8',
  env: { ...process.env, PYTHONIOENCODING: 'utf-8', PYTHONUTF8: '1' }
}).trim();

console.log('Dispatched command:', cmdId);

let attempts = 0;
while (attempts < 30) {
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
      if (inv.StandardErrorContent) console.error('STDERR:\n', inv.StandardErrorContent);
      break;
    }
  } catch (e) {}
}
