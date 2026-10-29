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
  const region = 'ap-south-2';
  const instanceId = run(`aws ec2 describe-instances --region ${region} --filters "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].InstanceId" --output text`, __dirname).trim().split(/\s+/)[0];
  console.log(`Active EC2 instance to provision: ${instanceId}`);

  const commands = [
    'echo "=== 1. RESOLVING APT LOCKS & INSTALLING NODE.JS 20 ==="',
    'killall apt apt-get dpkg 2>/dev/null || true',
    'rm -f /var/lib/dpkg/lock* /var/lib/apt/lists/lock /var/cache/apt/archives/lock',
    'dpkg --configure -a',
    'if ! command -v node &> /dev/null; then',
    '  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -',
    '  apt-get install -y nodejs',
    'fi',
    'node -v',
    'npm -v',
    'echo "=== 2. ENSURING DOCKER & MONGODB RUNNING ==="',
    'if ! command -v docker &> /dev/null; then',
    '  apt-get update -y && apt-get install -y docker.io',
    'fi',
    'systemctl enable docker --now',
    'if ! docker ps | grep -q staydriv-mongo; then',
    '  docker rm -f staydriv-mongo 2>/dev/null || true',
    '  docker run -d --name staydriv-mongo -p 27017:27017 --restart always mongo:7.0',
    'fi',
    'docker ps',
    'echo "=== 3. DOWNLOADING CORE BACKEND & INSTALLING DEPENDENCIES ==="',
    'mkdir -p /opt/staydriv /var/log/staydriv /opt/Staydriv_Admin/dist /opt/staydriv/public/admin',
    'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv_core_backend.tar.gz /tmp/staydriv_core_backend.tar.gz --region ap-south-2',
    'tar -xzf /tmp/staydriv_core_backend.tar.gz -C /opt/staydriv',
    'cd /opt/staydriv && npm install --omit=dev',
    'echo "=== 4. EXTRACTING UPDATED FOOD MODULES & ADMIN DIST ==="',
    'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv_food_backend.tar.gz /tmp/staydriv_food_backend.tar.gz --region ap-south-2',
    'tar -xzf /tmp/staydriv_food_backend.tar.gz -C /opt/staydriv',
    'aws s3 cp s3://staydriv-prod-assets-60345301/admin-dist.tar.gz /tmp/admin-dist.tar.gz --region ap-south-2',
    'rm -rf /opt/Staydriv_Admin/dist/* /opt/staydriv/public/admin/*',
    'tar -xzf /tmp/admin-dist.tar.gz -C /opt/Staydriv_Admin/dist',
    'tar -xzf /tmp/admin-dist.tar.gz -C /opt/staydriv/public/admin',
    'chmod -R 755 /opt/Staydriv_Admin/dist /opt/staydriv/public/admin',
    'echo "=== 5. SYNCING MOBILE BINARIES & ASSETS ==="',
    'mkdir -p /opt/staydriv/public/apk /opt/staydriv/public/aab /opt/staydriv/public/downloads',
    'aws s3 cp s3://staydriv-prod-assets-60345301/version.json /opt/staydriv/public/version.json --region ap-south-2 || true',
    'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv-combined.apk /opt/staydriv/public/staydriv-combined.apk --region ap-south-2 || true',
    'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv-combined.aab /opt/staydriv/public/staydriv-combined.aab --region ap-south-2 || true',
    'cp /opt/staydriv/public/staydriv-combined.apk /opt/staydriv/public/apk/staydriv-combined.apk || true',
    'cp /opt/staydriv/public/staydriv-combined.aab /opt/staydriv/public/aab/staydriv-combined.aab || true',
    'cp /opt/staydriv/public/staydriv-combined.apk /opt/staydriv/public/downloads/staydriv-combined.apk || true',
    'cp /opt/staydriv/public/staydriv-combined.aab /opt/staydriv/public/downloads/staydriv-combined.aab || true',
    'echo "=== 6. CREATING .env AND SYSTEMD SERVICE ==="',
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
    'echo "=== 7. VALIDATING JAVASCRIPT SYNTAX ==="',
    'node -c /opt/staydriv/server.js',
    'node -c /opt/staydriv/models/Restaurant.js',
    'node -c /opt/staydriv/models/FoodOrder.js',
    'node -c /opt/staydriv/models/FoodItem.js',
    'node -c /opt/staydriv/models/FoodConfig.js',
    'node -c /opt/staydriv/routes/foodRoutes.js',
    'node -c /opt/staydriv/services/foodSeedService.js',
    'node -c /opt/staydriv/services/pilotWalletService.js',
    'echo "=== 8. STARTING STAYDRIV SERVICE ==="',
    'systemctl daemon-reload',
    'systemctl enable staydriv',
    'systemctl restart staydriv',
    'sleep 5',
    'systemctl is-active staydriv',
    'echo "=== 9. VERIFYING LOCAL API ENDPOINTS ==="',
    'curl -s http://127.0.0.1:3000/api/health',
    'echo ""',
    'curl -s http://127.0.0.1:3000/api/food/restaurants | head -c 400',
    'echo ""'
  ];

  const ssmJsonPath = path.resolve(__dirname, 'ssm_provision.json');
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
      // in progress
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

  console.log('\n=== Invalidation CloudFront ===');
  const distId = 'E3I4T1HFZ2E6SJ';
  const invalidationRes = run(`aws cloudfront create-invalidation --distribution-id ${distId} --paths "/*" "/admin/*" "/api/food/*" --query Invalidation.Id --output text`, __dirname).trim();
  console.log(`CloudFront Invalidation created: ${invalidationRes}`);

  console.log('\n=== Testing CloudFront Health ===');
  const cdnHealth = run('curl -s https://dk60tgl9yds4p.cloudfront.net/api/health', __dirname);
  console.log(`CloudFront Health: ${cdnHealth}`);
}

main().catch(e => {
  console.error(e);
  process.exit(1);
});
