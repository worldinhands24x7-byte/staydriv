const { execSync } = require('child_process');
const fs = require('fs');

function exec(cmd) {
  return execSync(cmd, {
    env: { ...process.env, PYTHONIOENCODING: 'utf-8', PYTHONUTF8: '1' },
    encoding: 'utf8'
  });
}

function runSsm(commandList, instanceId = 'i-0e7a1246bad471fff', region = 'ap-south-2') {
  const jsonParam = JSON.stringify({
    InstanceIds: [instanceId],
    DocumentName: 'AWS-RunShellScript',
    Parameters: { commands: commandList }
  });

  fs.writeFileSync('ssm_deploy_update.json', jsonParam);

  const cmdId = exec(`aws ssm send-command --cli-input-json file://ssm_deploy_update.json --region ${region} --query Command.CommandId --output text`).trim();
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
  'echo "=== 1. EXTRACTING UPDATED BACKEND FILES ==="',
  'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv_backend_update.tar.gz /tmp/staydriv_backend_update.tar.gz --region ap-south-2',
  'tar -xzf /tmp/staydriv_backend_update.tar.gz -C /opt/staydriv/',
  'chown -R ubuntu:ubuntu /opt/staydriv',
  'echo "=== 2. CHECKING SYNTAX ==="',
  'node -c /opt/staydriv/server.js',
  'node -c /opt/staydriv/routes/foodRoutes.js',
  'node -c /opt/staydriv/routes/pilotWalletRoutes.js',
  'node -c /opt/staydriv/services/pilotWalletService.js',
  'echo "=== 3. RESTARTING STAYDRIV SERVICE ==="',
  'systemctl daemon-reload',
  'systemctl restart staydriv',
  'sleep 3',
  'systemctl is-active staydriv',
  'echo "=== 4. TESTING HEALTH & ENDPOINTS ==="',
  'curl -s http://127.0.0.1:3000/health',
  'echo ""',
  'curl -s http://127.0.0.1:3000/api/food/restaurants | head -c 200',
  'echo ""'
];

runSsm(commands);
