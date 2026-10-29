const { execSync } = require('child_process');

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

  const fs = require('fs');
  fs.writeFileSync('ssm_tmp.json', jsonParam);

  const cmdId = exec(`aws ssm send-command --cli-input-json file://ssm_tmp.json --region ${region} --query Command.CommandId --output text`).trim();
  console.log(`SSM Command dispatched: ${cmdId}`);

  let attempts = 0;
  while (attempts < 20) {
    execSync('timeout /t 2 > nul 2>&1 || ping 127.0.0.1 -n 3 > nul');
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

if (process.argv[2]) {
  const commands = process.argv.slice(2);
  runSsm(commands);
} else {
  runSsm([
    'grep reservedBalance /opt/staydriv/models/PilotWallet.js || echo "NOT FOUND"',
    'grep pending_approval /opt/staydriv/server.js || echo "NOT FOUND"'
  ]);
}
