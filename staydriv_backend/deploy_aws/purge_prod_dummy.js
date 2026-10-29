const { execSync } = require('child_process');
const fs = require('fs');

function exec(cmd) {
  return execSync(cmd, {
    env: { ...process.env, PYTHONIOENCODING: 'utf-8', PYTHONUTF8: '1' },
    encoding: 'utf8'
  });
}

function getRunningInstanceId() {
  const out = exec('aws ec2 describe-instances --region ap-south-2 --filters "Name=instance-state-name,Values=running" "Name=tag:Name,Values=staydriv-prod-asg-instance" --query "Reservations[0].Instances[0].InstanceId" --output text').trim();
  return out;
}

const instanceId = getRunningInstanceId();
console.log('Target Instance:', instanceId);

const commands = [
  'cd /opt/staydriv',
  `node -e '
const mongoose = require("mongoose");
require("dotenv").config({ path: "/opt/staydriv/.env" });
const mongoUri = process.env.MONGODB_URI || "mongodb://127.0.0.1:27017/staydriv";
mongoose.connect(mongoUri).then(async () => {
  const Restaurant = mongoose.model("Restaurant", new mongoose.Schema({}, { strict: false }));
  const FoodItem = mongoose.model("FoodItem", new mongoose.Schema({}, { strict: false }));
  const dummyIds = ["REST_PARADISE_01", "REST_CHUTNEYS_02", "REST_BAWARCHI_03", "REST_PISTA_04", "REST_PIZZA_05", "REST_BURGER_06", "REST_REDDRAGON_07"];
  const delR = await Restaurant.deleteMany({
    $or: [
      { isDummy: true },
      { restaurantId: { $in: dummyIds } }
    ]
  });
  const delI = await FoodItem.deleteMany({
    $or: [
      { isDummy: true },
      { restaurantId: { $in: dummyIds } }
    ]
  });
  console.log("Purged dummy restaurants:", delR.deletedCount, "Purged dummy items:", delI.deletedCount);
  const remaining = await Restaurant.find({}, "restaurantId name isApproved status").lean();
  console.log("Remaining genuine restaurants in prod DB count:", remaining.length);
  remaining.forEach(r => console.log("  -", r.restaurantId, r.name, "| approved:", r.isApproved, "| status:", r.status));
  process.exit(0);
}).catch(e => { console.error(e); process.exit(1); });
'`
];

const jsonParam = JSON.stringify({
  InstanceIds: [instanceId],
  DocumentName: 'AWS-RunShellScript',
  Parameters: { commands }
});

fs.writeFileSync('ssm_purge.json', jsonParam);

const cmdId = exec(`aws ssm send-command --cli-input-json file://ssm_purge.json --region ap-south-2 --query Command.CommandId --output text`).trim();
console.log(`Dispatched: ${cmdId}`);

let attempts = 0;
while (attempts < 30) {
  execSync('timeout /t 3 > nul 2>&1 || ping 127.0.0.1 -n 4 > nul');
  attempts++;
  try {
    const invStr = exec(`aws ssm get-command-invocation --command-id ${cmdId} --instance-id ${instanceId} --region ap-south-2 --output json`);
    const inv = JSON.parse(invStr);
    if (inv.Status === 'Success' || inv.Status === 'Failed' || inv.Status === 'Cancelled') {
      console.log('Status:', inv.Status);
      if (inv.StandardOutputContent) console.log(inv.StandardOutputContent);
      if (inv.StandardErrorContent) console.error(inv.StandardErrorContent);
      break;
    }
  } catch (e) {}
}
