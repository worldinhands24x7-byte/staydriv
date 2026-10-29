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

  const jsonFile = 'ssm_deploy_exact_locations.json';
  fs.writeFileSync(jsonFile, jsonParam);

  const cmdId = exec(`aws ssm send-command --cli-input-json file://${jsonFile} --region ${region} --query Command.CommandId --output text`).trim();
  console.log(`SSM Command dispatched: ${cmdId} to instance ${targetId}`);

  let attempts = 0;
  while (attempts < 50) {
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

  'echo "=== 3. SYNCING FLUTTER WEB APP ==="',
  'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv_web_app.tar.gz /tmp/staydriv_web_app.tar.gz --region ap-south-2',
  'tar -xzf /tmp/staydriv_web_app.tar.gz -C /opt/staydriv/public/',
  'chmod -R 755 /opt/staydriv/public',

  'echo "=== 4. VALIDATING NODE SYNTAX ==="',
  'node -c /opt/staydriv/server.js',
  'node -c /opt/staydriv/models/Restaurant.js',
  'node -c /opt/staydriv/models/FoodOrder.js',
  'node -c /opt/staydriv/routes/foodRoutes.js',

  'echo "=== 5. RESTARTING STAYDRIV SERVICE ==="',
  'systemctl daemon-reload',
  'systemctl restart staydriv',
  'sleep 4',
  'systemctl is-active staydriv',

  'echo "=== 6. VERIFYING HEALTH & FOOD API ==="',
  'curl -s http://127.0.0.1:3000/api/health',
  'echo ""',
  'curl -s http://127.0.0.1:3000/api/food/restaurants | head -c 300',
  'echo ""',
  'curl -s -H "x-admin-key: staydriv_admin_secret_2026" "http://127.0.0.1:3000/api/food/admin/restaurants?status=all" | head -c 300',
  'echo ""'
];

async function deploy() {
  console.log('Deploying exact map location and navigation updates to EC2...');
  const inv = runSsm(commands);
  if (!inv || inv.Status !== 'Success') {
    console.error('Deployment failed or timed out!');
    process.exit(1);
  }

  console.log('\n=== 7. INVALIDATING CLOUDFRONT CACHE ===');
  try {
    const invId = exec('aws cloudfront create-invalidation --distribution-id E3I4T1HFZ2E6SJ --paths "/*" --query Invalidation.Id --output text').trim();
    console.log(`CloudFront invalidation initiated: ${invId}`);
  } catch (e) {
    console.warn('CloudFront invalidation warning:', e.message);
  }

  console.log('\n========================================================');
  console.log('   PRODUCTION DEPLOYMENT COMPLETED SUCCESSFULLY!');
  console.log('========================================================');
}

deploy();
