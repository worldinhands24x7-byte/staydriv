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
  const backendDir = path.resolve(__dirname, '..');
  const adminDir = path.resolve(__dirname, '..', '..', 'Staydriv_Admin');
  const stageDir = path.resolve(__dirname, 'temp_stage_backend');

  console.log('====================================================');
  console.log(' 1. PACKAGING COMPLETE PRODUCTION BACKEND          ');
  console.log('====================================================');

  if (fs.existsSync(stageDir)) {
    fs.rmSync(stageDir, { recursive: true, force: true });
  }
  fs.mkdirSync(stageDir, { recursive: true });

  // Copy server.js, package.json, package-lock.json
  ['server.js', 'package.json', 'package-lock.json'].forEach(f => {
    const src = path.join(backendDir, f);
    if (fs.existsSync(src)) {
      fs.copyFileSync(src, path.join(stageDir, f));
      console.log(`  Copied root file: ${f}`);
    }
  });

  // Copy folders: models, routes, services, controllers
  ['models', 'routes', 'services', 'controllers'].forEach(folder => {
    const src = path.join(backendDir, folder);
    if (fs.existsSync(src)) {
      fs.cpSync(src, path.join(stageDir, folder), { recursive: true });
      console.log(`  Copied directory: ${folder}/`);
    }
  });

  // Ensure an empty public directory exists for static mounts
  fs.mkdirSync(path.join(stageDir, 'public'), { recursive: true });

  // Create complete backend tarball
  const completeBackendTar = path.resolve(__dirname, 'staydriv_complete_backend.tar.gz').replace(/\\/g, '/');
  run(`tar -czf "${completeBackendTar}" .`, stageDir);
  console.log(`Created: ${completeBackendTar} (${(fs.statSync(completeBackendTar).size / 1024).toFixed(1)} KB)`);

  // Cleanup stage dir
  fs.rmSync(stageDir, { recursive: true, force: true });

  console.log('\n====================================================');
  console.log(' 2. PACKAGING STAYDRIV_ADMIN CONSOLE DIST          ');
  console.log('====================================================');
  const adminDistDir = path.join(adminDir, 'dist');
  const adminTar = path.resolve(__dirname, 'admin-dist.tar.gz').replace(/\\/g, '/');
  run(`tar -czf "${adminTar}" .`, adminDistDir);
  console.log(`Created: ${adminTar} (${(fs.statSync(adminTar).size / 1024).toFixed(1)} KB)`);

  console.log('\n====================================================');
  console.log(' 3. UPLOADING ARTIFACTS TO S3 DEPLOYMENT BUCKET    ');
  console.log('====================================================');
  run(`aws s3 cp "${completeBackendTar}" s3://staydriv-prod-assets-60345301/staydriv_complete_backend.tar.gz --region ap-south-2`, __dirname);
  run(`aws s3 cp "${adminTar}" s3://staydriv-prod-assets-60345301/admin-dist.tar.gz --region ap-south-2`, __dirname);
  console.log('Uploaded artifacts to S3 successfully.');

  console.log('\n====================================================');
  console.log(' 4. EXECUTING PROVISION & DEPLOY ON EC2            ');
  console.log('====================================================');
  const region = 'ap-south-2';
  const instanceId = run(`aws ec2 describe-instances --region ${region} --filters "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].InstanceId" --output text`, __dirname).trim().split(/\s+/)[0];
  console.log(`Target running EC2 instance: ${instanceId}`);

  const commands = [
    'echo "=== 1. ENSURING DOCKER & MONGODB RUNNING ==="',
    'systemctl enable docker --now',
    'if ! docker ps | grep -q staydriv-mongo; then',
    '  docker rm -f staydriv-mongo 2>/dev/null || true',
    '  docker run -d --name staydriv-mongo -p 27017:27017 --restart always mongo:7.0',
    'fi',
    'docker ps',
    'echo "=== 2. EXTRACTING COMPLETE BACKEND & INSTALLING NPM DEPENDENCIES ==="',
    'mkdir -p /opt/staydriv /var/log/staydriv /opt/Staydriv_Admin/dist /opt/staydriv/public/admin',
    'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv_complete_backend.tar.gz /tmp/staydriv_complete_backend.tar.gz --region ap-south-2',
    'tar -xzf /tmp/staydriv_complete_backend.tar.gz -C /opt/staydriv',
    'cd /opt/staydriv && npm install --omit=dev',
    'echo "=== 3. EXTRACTING ADMIN CONSOLE DIST ==="',
    'aws s3 cp s3://staydriv-prod-assets-60345301/admin-dist.tar.gz /tmp/admin-dist.tar.gz --region ap-south-2',
    'rm -rf /opt/Staydriv_Admin/dist/* /opt/staydriv/public/admin/*',
    'tar -xzf /tmp/admin-dist.tar.gz -C /opt/Staydriv_Admin/dist',
    'tar -xzf /tmp/admin-dist.tar.gz -C /opt/staydriv/public/admin',
    'chmod -R 755 /opt/Staydriv_Admin/dist /opt/staydriv/public/admin',
    'echo "=== 4. CONFIGURING ENVIRONMENT & SYSTEMD SERVICE ==="',
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
    'chown -R ubuntu:ubuntu /opt/staydriv /var/log/staydriv',
    'echo "=== 5. VALIDATING JAVASCRIPT SYNTAX ==="',
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
    'echo "=== 6. STARTING STAYDRIV SERVICE ==="',
    'systemctl daemon-reload',
    'systemctl enable staydriv',
    'systemctl restart staydriv',
    'sleep 6',
    'systemctl is-active staydriv',
    'echo "=== 7. VERIFYING LOCAL API ENDPOINTS ==="',
    'curl -s http://127.0.0.1:3000/api/health',
    'echo ""',
    'curl -s http://127.0.0.1:3000/api/food/restaurants | head -c 400',
    'echo ""',
    'curl -s -H "x-admin-key: staydriv_admin_secret_2026" "http://127.0.0.1:3000/api/food/admin/restaurants?status=all" | head -c 400',
    'echo ""'
  ];

  const ssmJsonPath = path.resolve(__dirname, 'ssm_deploy_complete.json');
  fs.writeFileSync(ssmJsonPath, JSON.stringify({
    InstanceIds: [instanceId],
    DocumentName: 'AWS-RunShellScript',
    Parameters: { commands }
  }));

  const cmdId = run(`aws ssm send-command --cli-input-json file://${ssmJsonPath.replace(/\\/g, '/')} --region ${region} --query Command.CommandId --output text`, __dirname).trim();
  console.log(`SSM Command sent with ID: ${cmdId}`);

  let attempts = 0;
  let finalInv = null;
  while (attempts < 60) {
    run('ping 127.0.0.1 -n 5 > nul || timeout /t 4 > nul');
    attempts++;
    try {
      const invStr = run(`aws ssm get-command-invocation --command-id ${cmdId} --instance-id ${instanceId} --region ${region} --output json`, __dirname);
      const inv = JSON.parse(invStr);
      if (inv.Status === 'Success' || inv.Status === 'Failed' || inv.Status === 'Cancelled' || inv.Status === 'TimedOut') {
        finalInv = inv;
        break;
      }
    } catch (e) {
      // wait
    }
  }

  if (!finalInv) {
    throw new Error('SSM command timed out');
  }

  console.log(`\nSSM Execution Status: ${finalInv.Status}`);
  if (finalInv.StandardOutputContent) {
    console.log('--- REMOTE STDOUT ---');
    console.log(finalInv.StandardOutputContent);
  }
  if (finalInv.StandardErrorContent) {
    console.log('--- REMOTE STDERR ---');
    console.log(finalInv.StandardErrorContent);
  }

  if (finalInv.Status !== 'Success') {
    throw new Error(`SSM failed: ${finalInv.Status}`);
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
  console.error('\n❌ Deployment failed:', err);
  process.exit(1);
});
