const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

function run(cmd, cwd = process.cwd()) {
  console.log(`> [${cwd}] ${cmd}`);
  return execSync(cmd, {
    cwd,
    env: { ...process.env, PYTHONIOENCODING: 'utf-8', PYTHONUTF8: '1' },
    encoding: 'utf8'
  });
}

async function main() {
  const rootDir = path.resolve(__dirname, '..');
  const adminDir = path.resolve(__dirname, '..', '..', 'Staydriv_Admin');
  const tempDir = path.resolve(__dirname, 'temp_food_pkg');

  console.log('====================================================');
  console.log(' 1. PREPARING FOOD BACKEND MODULES FOR DEPLOYMENT   ');
  console.log('====================================================');

  if (fs.existsSync(tempDir)) {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
  fs.mkdirSync(tempDir, { recursive: true });

  // Models
  const modelsDir = path.join(tempDir, 'models');
  fs.mkdirSync(modelsDir, { recursive: true });
  fs.readdirSync(path.join(rootDir, 'models')).forEach(f => {
    if (f.endsWith('.js')) {
      fs.copyFileSync(path.join(rootDir, 'models', f), path.join(modelsDir, f));
      console.log(`  Copied model: models/${f}`);
    }
  });

  // Routes
  const routesDir = path.join(tempDir, 'routes');
  fs.mkdirSync(routesDir, { recursive: true });
  fs.readdirSync(path.join(rootDir, 'routes')).forEach(f => {
    if (f.endsWith('.js')) {
      fs.copyFileSync(path.join(rootDir, 'routes', f), path.join(routesDir, f));
      console.log(`  Copied route: routes/${f}`);
    }
  });

  // Services
  const servicesDir = path.join(tempDir, 'services');
  fs.mkdirSync(servicesDir, { recursive: true });
  fs.readdirSync(path.join(rootDir, 'services')).forEach(f => {
    if (f.endsWith('.js')) {
      fs.copyFileSync(path.join(rootDir, 'services', f), path.join(servicesDir, f));
      console.log(`  Copied service: services/${f}`);
    }
  });

  // Server.js
  if (fs.existsSync(path.join(rootDir, 'server.js'))) {
    fs.copyFileSync(path.join(rootDir, 'server.js'), path.join(tempDir, 'server.js'));
    console.log('  Copied server.js');
  }

  // Also sync to deploy_aws local directories
  ['models', 'routes', 'services'].forEach(dirName => {
    const targetDir = path.join(__dirname, dirName);
    fs.mkdirSync(targetDir, { recursive: true });
    fs.cpSync(path.join(tempDir, dirName), targetDir, { recursive: true });
  });

  // Create tarball
  const backendTar = path.resolve(__dirname, 'staydriv_food_backend.tar.gz').replace(/\\/g, '/');
  run(`tar -czf "${backendTar}" .`, tempDir);
  console.log(`Created: ${backendTar} (${(fs.statSync(backendTar).size / 1024).toFixed(1)} KB)`);

  // Cleanup temp dir
  fs.rmSync(tempDir, { recursive: true, force: true });

  console.log('\n====================================================');
  console.log(' 2. PACKAGING STAYDRIV_ADMIN CONSOLE DIST          ');
  console.log('====================================================');
  const adminDistDir = path.join(adminDir, 'dist');
  if (!fs.existsSync(adminDistDir)) {
    throw new Error('Admin dist dir does not exist! Run npm run build first.');
  }
  const adminTar = path.resolve(__dirname, 'admin-dist.tar.gz').replace(/\\/g, '/');
  run(`tar -czf "${adminTar}" .`, adminDistDir);
  console.log(`Created: ${adminTar} (${(fs.statSync(adminTar).size / 1024).toFixed(1)} KB)`);

  console.log('\n====================================================');
  console.log(' 3. UPLOADING ARTIFACTS TO AWS S3                  ');
  console.log('====================================================');
  run(`aws s3 cp "${backendTar}" s3://staydriv-prod-assets-60345301/staydriv_food_backend.tar.gz --region ap-south-2`, __dirname);
  run(`aws s3 cp "${adminTar}" s3://staydriv-prod-assets-60345301/admin-dist.tar.gz --region ap-south-2`, __dirname);
  console.log('Uploaded backend and admin bundles to S3 successfully.');

  console.log('\n====================================================');
  console.log(' 4. DISPATCHING SSM COMMAND TO EC2 i-090dbc33c50d882c6');
  console.log('====================================================');
  const commands = [
    'echo "=== 0. ENSURING DOCKER MONGO & CORE BACKEND INSTALLED ==="',
    'systemctl enable docker --now',
    'if ! docker ps | grep -q staydriv-mongo; then',
    '  docker rm -f staydriv-mongo 2>/dev/null || true',
    '  docker run -d --name staydriv-mongo -p 27017:27017 --restart always mongo:7.0',
    'fi',
    'mkdir -p /opt/staydriv /var/log/staydriv /opt/Staydriv_Admin/dist /opt/staydriv/public/admin',
    'if [ ! -f /opt/staydriv/package.json ]; then',
    '  aws s3 cp s3://staydriv-prod-assets-60345301/staydriv_core_backend.tar.gz /tmp/staydriv_core_backend.tar.gz --region ap-south-2',
    '  tar -xzf /tmp/staydriv_core_backend.tar.gz -C /opt/staydriv',
    'fi',
    'if [ ! -d /opt/staydriv/node_modules ]; then',
    '  cd /opt/staydriv && npm install --omit=dev',
    'fi',
    'cat << \'EOF\' > /opt/staydriv/.env',
    'PORT=3000',
    'NODE_ENV=prod',
    'MONGODB_URI=mongodb://127.0.0.1:27017/staydriv',
    'RAZORPAY_KEY_ID=rzp_live_Ta9cOGnIySuBCb',
    'RAZORPAY_KEY_SECRET=c93MSwcWO22lZuC7Xm5jURu0',
    'AWS_DEFAULT_REGION=ap-south-2',
    'S3_BUCKET=staydriv-prod-assets-60345301',
    'ADMIN_KEY=staydriv_admin_secret_2026',
    'EOF',
    'cat << \'EOF\' > /etc/systemd/system/staydriv.service',
    '[Unit]',
    'Description=StayDriv Backend Service',
    'After=network.target docker.service',
    '',
    '[Service]',
    'Type=simple',
    'User=ubuntu',
    'WorkingDirectory=/opt/staydriv',
    'Environment=PORT=3000',
    'Environment=NODE_ENV=prod',
    'Environment=MONGODB_URI=mongodb://127.0.0.1:27017/staydriv',
    'Environment=AWS_DEFAULT_REGION=ap-south-2',
    'Environment=S3_BUCKET=staydriv-prod-assets-60345301',
    'Environment=RAZORPAY_KEY_ID=rzp_live_Ta9cOGnIySuBCb',
    'Environment=RAZORPAY_KEY_SECRET=c93MSwcWO22lZuC7Xm5jURu0',
    'ExecStart=/usr/bin/node /opt/staydriv/server.js',
    'Restart=always',
    'RestartSec=5',
    'StandardOutput=append:/var/log/staydriv/app.log',
    'StandardError=append:/var/log/staydriv/error.log',
    '',
    '[Install]',
    'WantedBy=multi-user.target',
    'EOF',
    'echo "=== 1. EXTRACTING FOOD BACKEND MODULES ==="',
    'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv_food_backend.tar.gz /tmp/staydriv_food_backend.tar.gz --region ap-south-2',
    'mkdir -p /opt/staydriv/models /opt/staydriv/routes /opt/staydriv/services',
    'tar -xzf /tmp/staydriv_food_backend.tar.gz -C /opt/staydriv/',
    'chown -R ubuntu:ubuntu /opt/staydriv /var/log/staydriv',
    'echo "=== 2. EXTRACTING ADMIN CONSOLE DIST ==="',
    'aws s3 cp s3://staydriv-prod-assets-60345301/admin-dist.tar.gz /tmp/admin-dist.tar.gz --region ap-south-2',
    'mkdir -p /opt/Staydriv_Admin/dist /opt/staydriv/public/admin',
    'rm -rf /opt/Staydriv_Admin/dist/* /opt/staydriv/public/admin/*',
    'tar -xzf /tmp/admin-dist.tar.gz -C /opt/Staydriv_Admin/dist',
    'tar -xzf /tmp/admin-dist.tar.gz -C /opt/staydriv/public/admin',
    'chmod -R 755 /opt/Staydriv_Admin/dist /opt/staydriv/public/admin',
    'echo "=== 3. VALIDATING JAVASCRIPT SYNTAX ==="',
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
    'echo "=== 4. PURGING DUMMIES & CHECKING RESTAURANTS IN PROD MONGO ==="',
    'NODE_PATH=/opt/staydriv/node_modules node -e \'',
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
    '  console.log("Deleted dummies: restaurants:", delR.deletedCount, "items:", delI.deletedCount);',
    '  const approved = await Restaurant.find({ isApproved: true, status: "approved" });',
    '  console.log("Approved restaurants found:", approved.length);',
    '  for (const r of approved) {',
    '    console.log("Restaurant:", r.restaurantId, r.name, "| coords:", r.lat, r.lng, "| address:", r.address);',
    '  }',
    '  process.exit(0);',
    '}).catch(e => { console.error(e); process.exit(1); });',
    '\'',
    'echo "=== 5. RESTARTING STAYDRIV BACKEND SERVICE ==="',
    'systemctl daemon-reload',
    'systemctl restart staydriv',
    'sleep 8',
    'systemctl is-active staydriv',
    'echo "=== 6. VERIFYING LOCAL API ENDPOINTS ==="',
    'curl -s http://127.0.0.1:3000/api/health',
    'echo ""',
    'curl -s http://127.0.0.1:3000/api/food/restaurants | head -c 400',
    'echo ""',
    'curl -s -H "x-admin-key: staydriv_admin_secret_2026" "http://127.0.0.1:3000/api/food/admin/restaurants?status=all" | head -c 400',
    'echo ""'
  ];

  // Dynamically find running EC2 instance
  const region = 'ap-south-2';
  const instanceId = run(`aws ec2 describe-instances --region ${region} --filters "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].InstanceId" --output text`, __dirname).trim().split(/\s+/)[0];
  console.log(`Discovered active EC2 instance: ${instanceId}`);
  if (!instanceId) {
    throw new Error('No running EC2 instance found!');
  }
  const ssmJsonPath = path.resolve(__dirname, 'ssm_deploy_full.json');
  fs.writeFileSync(ssmJsonPath, JSON.stringify({
    InstanceIds: [instanceId],
    DocumentName: 'AWS-RunShellScript',
    Parameters: { commands }
  }));

  const cmdId = run(`aws ssm send-command --cli-input-json file://${ssmJsonPath.replace(/\\/g, '/')} --region ${region} --query Command.CommandId --output text`, __dirname).trim();
  console.log(`SSM Command sent with ID: ${cmdId}`);

  let attempts = 0;
  let finalInv = null;
  while (attempts < 45) {
    execSync('timeout /t 3 > nul 2>&1 || ping 127.0.0.1 -n 4 > nul');
    attempts++;
    try {
      const invStr = run(`aws ssm get-command-invocation --command-id ${cmdId} --instance-id ${instanceId} --region ${region} --output json`, __dirname);
      const inv = JSON.parse(invStr);
      if (inv.Status === 'Success' || inv.Status === 'Failed' || inv.Status === 'Cancelled' || inv.Status === 'TimedOut') {
        finalInv = inv;
        break;
      }
    } catch (e) {
      // still running
    }
  }

  if (!finalInv) {
    throw new Error('SSM command timed out polling invocation');
  }

  console.log(`\nSSM Deployment Status: ${finalInv.Status}`);
  if (finalInv.StandardOutputContent) {
    console.log('--- REMOTE STDOUT ---');
    console.log(finalInv.StandardOutputContent);
  }
  if (finalInv.StandardErrorContent) {
    console.log('--- REMOTE STDERR ---');
    console.log(finalInv.StandardErrorContent);
  }

  if (finalInv.Status !== 'Success') {
    throw new Error(`SSM Deployment Failed with status: ${finalInv.Status}`);
  }

  console.log('\n====================================================');
  console.log(' 5. INVALIDATING CLOUDFRONT CDN DISTRIBUTION       ');
  console.log('====================================================');
  const distId = 'E3I4T1HFZ2E6SJ';
  const invalidationRes = run(`aws cloudfront create-invalidation --distribution-id ${distId} --paths "/*" "/admin/*" "/api/food/*" --query Invalidation.Id --output text`, __dirname).trim();
  console.log(`CloudFront Invalidation created: ${invalidationRes}`);

  console.log('\n====================================================');
  console.log(' 6. LIVE VERIFICATION FROM CLOUDFRONT              ');
  console.log('====================================================');
  const cdnHealth = run('curl -s https://dk60tgl9yds4p.cloudfront.net/api/health', __dirname);
  console.log(`CloudFront Health: ${cdnHealth}`);

  const cdnRestaurants = run('curl -s https://dk60tgl9yds4p.cloudfront.net/api/food/restaurants', __dirname);
  console.log(`CloudFront Restaurants snippet: ${cdnRestaurants.slice(0, 300)}...`);

  console.log('\n DEPLOYMENT COMPLETED SUCCESSFULLY!');
}

main().catch(err => {
  console.error('\n❌ Deployment script failed:', err);
  process.exit(1);
});
