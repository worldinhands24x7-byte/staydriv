const { execSync } = require('child_process');
const fs = require('fs');

const params = {
  commands: [
    'echo "=== SERVICE STATUS ==="',
    'systemctl is-active staydriv',
    'echo "=== LS /opt/staydriv ==="',
    'ls -la /opt/staydriv',
    'echo "=== RECENT APP LOGS ==="',
    'tail -n 35 /var/log/staydriv/app.log 2>/dev/null || journalctl -u staydriv -n 35 --no-pager'
  ]
};

fs.writeFileSync('ssm_params.json', JSON.stringify(params));
const sendOut = execSync('aws ssm send-command --instance-ids i-022567dabce0647bc --document-name AWS-RunShellScript --parameters file://ssm_params.json --region ap-south-2 --output json', { encoding: 'utf8' });
const cmdId = JSON.parse(sendOut).Command.CommandId;
console.log('Dispatched command to ap-south-2:', cmdId);

let attempts = 0;
const interval = setInterval(() => {
  attempts++;
  try {
    const invOut = execSync(`aws ssm get-command-invocation --command-id ${cmdId} --instance-id i-022567dabce0647bc --region ap-south-2 --output json`, { encoding: 'utf8' });
    const inv = JSON.parse(invOut);
    if (inv.Status === 'Success' || inv.Status === 'Failed' || attempts > 10) {
      clearInterval(interval);
      console.log('Status:', inv.Status);
      console.log('Output:\n', inv.StandardOutputContent);
      if (inv.StandardErrorContent) console.error('Error:\n', inv.StandardErrorContent);
    }
  } catch (err) {
    if (attempts > 10) {
      clearInterval(interval);
      console.error(err.message);
    }
  }
}, 1500);
