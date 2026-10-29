const { execSync } = require('child_process');
const fs = require('fs');

function exec(cmd) {
  return execSync(cmd, {
    env: { ...process.env, PYTHONIOENCODING: 'utf-8', PYTHONUTF8: '1' },
    encoding: 'utf8'
  });
}

function getRunningInstanceId(region = 'ap-south-2') {
  try {
    const id = exec(`aws ec2 describe-instances --region ${region} --filters "Name=instance-state-name,Values=running" "Name=tag:Name,Values=staydriv-prod-asg-instance" --query "Reservations[0].Instances[0].InstanceId" --output text`).trim();
    if (id && id !== 'None' && id.startsWith('i-')) return id;
  } catch (e) {
    console.error('Failed to auto-detect running instance:', e.message);
  }
  return 'i-0a8cfb22fc40c7591';
}

function runSsm(commandList, instanceId = null, region = 'ap-south-2') {
  const targetId = instanceId || getRunningInstanceId(region);
  const jsonParam = JSON.stringify({
    InstanceIds: [targetId],
    DocumentName: 'AWS-RunShellScript',
    Parameters: { commands: commandList }
  });

  fs.writeFileSync('ssm_deploy_failed_delivery.json', jsonParam);

  const cmdId = exec(`aws ssm send-command --cli-input-json file://ssm_deploy_failed_delivery.json --region ${region} --query Command.CommandId --output text`).trim();
  console.log(`SSM Command dispatched: ${cmdId} to instance ${targetId}`);

  let attempts = 0;
  while (attempts < 40) {
    execSync('timeout /t 3 > nul 2>&1 || ping 127.0.0.1 -n 4 > nul');
    attempts++;
    try {
      const invStr = exec(`aws ssm get-command-invocation --command-id ${cmdId} --instance-id ${targetId} --region ${region} --output json`);
      const inv = JSON.parse(invStr);
      if (inv.Status === 'Success' || inv.Status === 'Failed' || inv.Status === 'Cancelled' || inv.Status === 'TimedOut') {
        console.log(`Status: ${inv.Status}`);
        if (inv.StandardOutputContent) {
          console.log('--- STDOUT ---');
          console.log(inv.StandardOutputContent);
        }
        if (inv.StandardErrorContent) {
          console.log('--- STDERR ---');
          console.log(inv.StandardErrorContent);
        }
        return inv;
      }
    } catch (e) {
      // In progress
    }
  }
}

const commands = [
  'echo "=== 1. SYNCING BACKEND FOOD MODULES ==="',
  'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv_food_backend.tar.gz /tmp/staydriv_food_backend.tar.gz --region ap-south-2',
  'mkdir -p /opt/staydriv/models /opt/staydriv/routes /opt/staydriv/services',
  'tar -xzf /tmp/staydriv_food_backend.tar.gz -C /opt/staydriv/',
  'chown -R ubuntu:ubuntu /opt/staydriv',
  'echo "=== 2. SYNCING ADMIN CONSOLE DIST ==="',
  'aws s3 cp s3://staydriv-prod-assets-60345301/admin-dist.tar.gz /tmp/admin-dist.tar.gz --region ap-south-2',
  'mkdir -p /opt/Staydriv_Admin/dist /opt/staydriv/public/admin',
  'rm -rf /opt/Staydriv_Admin/dist/* /opt/staydriv/public/admin/*',
  'tar -xzf /tmp/admin-dist.tar.gz -C /opt/Staydriv_Admin/dist',
  'tar -xzf /tmp/admin-dist.tar.gz -C /opt/staydriv/public/admin',
  'chmod -R 755 /opt/Staydriv_Admin/dist /opt/staydriv/public/admin',
  'echo "=== 3. VALIDATING NODE SYNTAX ==="',
  'node -c /opt/staydriv/server.js',
  'node -c /opt/staydriv/models/Restaurant.js',
  'node -c /opt/staydriv/models/FoodOrder.js',
  'node -c /opt/staydriv/models/FoodItem.js',
  'node -c /opt/staydriv/models/FoodConfig.js',
  'node -c /opt/staydriv/models/FinancialLedger.js',
  'node -c /opt/staydriv/models/RestaurantSettlement.js',
  'node -c /opt/staydriv/routes/foodRoutes.js',
  'node -c /opt/staydriv/routes/foodMembershipRoutes.js',
  'node -c /opt/staydriv/routes/pilotWalletRoutes.js',
  'node -c /opt/staydriv/services/foodSeedService.js',
  'node -c /opt/staydriv/services/foodBillCalculationService.js',
  'node -c /opt/staydriv/services/foodDeliveryEligibilityService.js',
  'node -c /opt/staydriv/services/pilotWalletService.js',
  'node -c /opt/staydriv/services/restaurantSettlementService.js',
  'cd /opt/staydriv',
  'echo "=== 4. NORMALIZING PILOT USER & PURGING DUMMY RESTAURANTS ==="',
  'node -e \'',
  'const mongoose = require("mongoose");',
  'require("dotenv").config({ path: "/opt/staydriv/.env" });',
  'const mongoUri = process.env.MONGODB_URI || "mongodb://127.0.0.1:27017/staydriv";',
  'mongoose.connect(mongoUri).then(async () => {',
  '  const User = mongoose.model("User", new mongoose.Schema({}, { strict: false }));',
  '  await User.updateOne({ uid: "pilot_9490440281" }, { $set: { phone: "9490440281", phoneNumber: "9490440281", driverPhone: "9490440281", approved: true, isApproved: true, status: "approved", vehicleType: "Bike" } });',
  '  const Restaurant = mongoose.model("Restaurant", new mongoose.Schema({}, { strict: false }));',
  '  const FoodItem = mongoose.model("FoodItem", new mongoose.Schema({}, { strict: false }));',
  '  const delR = await Restaurant.deleteMany({',
  '    $or: [',
  '      { isDummy: true },',
  '      { restaurantId: { $in: ["REST_PARADISE_01", "REST_CHUTNEYS_02", "REST_BAWARCHI_03", "REST_PISTA_04", "REST_PIZZA_05", "REST_BURGER_06", "REST_REDDRAGON_07"] } }',
  '    ]',
  '  });',
  '  const delI = await FoodItem.deleteMany({',
  '    $or: [',
  '      { isDummy: true },',
  '      { restaurantId: { $in: ["REST_PARADISE_01", "REST_CHUTNEYS_02", "REST_BAWARCHI_03", "REST_PISTA_04", "REST_PIZZA_05", "REST_BURGER_06", "REST_REDDRAGON_07"] } }',
  '    ]',
  '  });',
  '  console.log("Purged dummy restaurants:", delR.deletedCount, "Purged dummy items:", delI.deletedCount);',
  '  const p = await User.findOne({ uid: "pilot_9490440281" }, "uid phone phoneNumber approved status vehicleType").lean();',
  '  console.log("Pilot 9490440281 status:", JSON.stringify(p));',
  '  process.exit(0);',
  '}).catch(e => { console.error(e); process.exit(1); });',
  '\'',
  'echo "=== 5. RESTARTING STAYDRIV SERVICE ==="',
  'systemctl daemon-reload',
  'systemctl restart staydriv',
  'sleep 3',
  'systemctl is-active staydriv',
  'echo "=== 6. VERIFYING HEALTH & RESTAURANTS API ==="',
  'curl -s http://127.0.0.1:3000/api/health',
  'echo ""',
  'curl -s http://127.0.0.1:3000/api/food/restaurants | head -c 400',
  'echo ""',
  'curl -s -H "x-admin-key: staydriv_admin_secret_2026" "http://127.0.0.1:3000/api/food/admin/restaurants?status=all" | head -c 400',
  'echo ""',
  'echo "=== 7. VERIFYING SETTLEMENTS OVERVIEW API ==="',
  'curl -s http://127.0.0.1:3000/api/food/admin/settlements/overview | head -c 400',
  'echo ""'
];

runSsm(commands);
