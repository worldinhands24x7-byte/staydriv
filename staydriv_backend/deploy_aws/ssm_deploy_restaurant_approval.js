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

  fs.writeFileSync('ssm_deploy_approval.json', jsonParam);

  const cmdId = exec(`aws ssm send-command --cli-input-json file://ssm_deploy_approval.json --region ${region} --query Command.CommandId --output text`).trim();
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
  'node -c /opt/staydriv/models/Restaurant.js',
  'node -c /opt/staydriv/routes/foodRoutes.js',
  'echo "=== 4. RESTARTING STAYDRIV SERVICE ==="',
  'systemctl daemon-reload',
  'systemctl restart staydriv',
  'sleep 3',
  'systemctl is-active staydriv',
  'echo "=== 5. CHECKING HEALTH & ADMIN RESTAURANTS API ==="',
  'curl -s http://127.0.0.1:3000/api/health',
  'echo ""',
  'curl -s -H "x-admin-key: staydriv_admin_secret_2026" "http://127.0.0.1:3000/api/food/admin/restaurants?status=all" | head -c 400',
  'echo ""'
];

runSsm(commands);
