const { execSync } = require('child_process');
const fs = require('fs');

function exec(cmd) {
  return execSync(cmd, {
    env: { ...process.env, PYTHONIOENCODING: 'utf-8', PYTHONUTF8: '1' },
    encoding: 'utf8'
  });
}

function runSsm(commandList, instanceId = 'i-0f8915ff46459c3b5', region = 'ap-south-2') {
  const jsonParam = JSON.stringify({
    InstanceIds: [instanceId],
    DocumentName: 'AWS-RunShellScript',
    Parameters: { commands: commandList }
  });

  fs.writeFileSync('ssm_deploy_food.json', jsonParam);

  const cmdId = exec(`aws ssm send-command --cli-input-json file://ssm_deploy_food.json --region ${region} --query Command.CommandId --output text`).trim();
  console.log(`SSM Command dispatched: ${cmdId}`);

  let attempts = 0;
  while (attempts < 30) {
    execSync('timeout /t 3 > nul 2>&1 || ping 127.0.0.1 -n 4 > nul');
    attempts++;
    try {
      const invStr = exec(`aws ssm get-command-invocation --command-id ${cmdId} --instance-id ${instanceId} --region ${region} --output json`);
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
      // Still in progress
    }
  }
}

const commands = [
  'echo "=== 1. EXTRACTING FOOD BACKEND MODULES ==="',
  'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv_food_backend.tar.gz /tmp/staydriv_food_backend.tar.gz --region ap-south-2',
  'mkdir -p /opt/staydriv/models /opt/staydriv/routes /opt/staydriv/services',
  'tar -xzf /tmp/staydriv_food_backend.tar.gz -C /opt/staydriv/',
  'chown -R ubuntu:ubuntu /opt/staydriv',
  'echo "=== 2. EXTRACTING ADMIN CONSOLE WITH FOOD SECTION ==="',
  'aws s3 cp s3://staydriv-prod-assets-60345301/admin-dist.tar.gz /tmp/admin-dist.tar.gz --region ap-south-2',
  'mkdir -p /opt/Staydriv_Admin/dist /opt/staydriv/public/admin',
  'tar -xzf /tmp/admin-dist.tar.gz -C /opt/Staydriv_Admin/dist',
  'tar -xzf /tmp/admin-dist.tar.gz -C /opt/staydriv/public/admin',
  'chmod -R 755 /opt/Staydriv_Admin/dist /opt/staydriv/public/admin',
  'echo "=== 3. SYNCING VERSION & MOBILE BINARIES ==="',
  'aws s3 cp s3://staydriv-prod-assets-60345301/version.json /opt/staydriv/public/version.json --region ap-south-2',
  'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv-combined.apk /opt/staydriv/public/staydriv-combined.apk --region ap-south-2',
  'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv-combined.aab /opt/staydriv/public/staydriv-combined.aab --region ap-south-2',
  'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv-latest.apk /opt/staydriv/public/staydriv-latest.apk --region ap-south-2',
  'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv-latest.aab /opt/staydriv/public/staydriv-latest.aab --region ap-south-2',
  'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv-v1.0.91.apk /opt/staydriv/public/staydriv-v1.0.91.apk --region ap-south-2',
  'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv-v1.0.91.aab /opt/staydriv/public/staydriv-v1.0.91.aab --region ap-south-2',
  'mkdir -p /opt/staydriv/public/apk /opt/staydriv/public/aab /opt/staydriv/public/downloads',
  'cp /opt/staydriv/public/staydriv-combined.apk /opt/staydriv/public/apk/staydriv-combined.apk',
  'cp /opt/staydriv/public/staydriv-combined.aab /opt/staydriv/public/aab/staydriv-combined.aab',
  'cp /opt/staydriv/public/staydriv-combined.apk /opt/staydriv/public/downloads/staydriv-combined.apk',
  'chown -R ubuntu:ubuntu /opt/staydriv/public',
  'echo "=== 4. TESTING NODE SYNTAX ==="',
  'node -c /opt/staydriv/server.js',
  'node -c /opt/staydriv/routes/foodRoutes.js',
  'node -c /opt/staydriv/services/foodSeedService.js',
  'echo "=== 5. RESTARTING STAYDRIV SERVICE ==="',
  'systemctl daemon-reload',
  'systemctl restart staydriv',
  'sleep 4',
  'systemctl is-active staydriv',
  'echo "=== 6. VERIFYING HEALTH & FOOD ENDPOINTS ==="',
  'curl -s http://127.0.0.1:3000/api/health',
  'echo ""',
  'curl -s http://127.0.0.1:3000/api/food/categories',
  'echo ""',
  'curl -s http://127.0.0.1:3000/api/food/restaurants | head -c 250',
  'echo ""',
  'curl -s -H "x-admin-key: staydriv_admin_secret_2026" http://127.0.0.1:3000/api/food/admin/stats',
  'echo ""',
  'echo "=== 7. VERIFYING ADMIN CONSOLE SERVING ==="',
  'curl -s -I http://127.0.0.1:3000/admin | head -n 5'
];

runSsm(commands);
