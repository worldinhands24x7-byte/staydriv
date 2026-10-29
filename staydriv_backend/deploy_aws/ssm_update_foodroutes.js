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

  fs.writeFileSync('ssm_cmd.json', jsonParam);

  const cmdId = exec(`aws ssm send-command --cli-input-json file://ssm_cmd.json --region ${region} --query Command.CommandId --output text`).trim();
  console.log(`SSM Command dispatched: ${cmdId}`);

  let attempts = 0;
  while (attempts < 20) {
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
  'systemctl list-units --type=service | grep -i stay || true',
  'systemctl restart staydriv || pkill -f "/opt/staydriv/server.js"',
  'sleep 2',
  'ps aux | grep -E "node /opt/staydriv"',
  'curl -s http://localhost:3000/api/food/partner/by-phone/9849012345'
];

runSsm(commands);
