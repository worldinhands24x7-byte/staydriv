const { execSync } = require('child_process');
const fs = require('fs');

const id = 'i-0a8cfb22fc40c7591';
const region = 'ap-south-2';

const commands = [
  'systemctl is-active staydriv || true',
  'ls -1 /opt/staydriv/models',
  'ls -1 /opt/staydriv/routes',
  'ls -1 /opt/staydriv/services',
  'curl -s http://127.0.0.1:3000/api/health',
  'echo ""',
  'curl -s http://127.0.0.1:3000/api/food/restaurants | head -c 200',
  'echo ""'
];

const param = JSON.stringify({
  InstanceIds: [id],
  DocumentName: 'AWS-RunShellScript',
  Parameters: { commands }
});

fs.writeFileSync('ssm_check_status.json', param);
const cmdId = execSync('aws ssm send-command --cli-input-json file://ssm_check_status.json --region ' + region + ' --query Command.CommandId --output text', {
  env: { ...process.env, PYTHONIOENCODING: 'utf-8', PYTHONUTF8: '1' }
}).toString().trim();
console.log('Dispatched:', cmdId);

let done = false;
for (let i = 0; i < 30; i++) {
  execSync('timeout /t 3 > nul 2>&1 || ping 127.0.0.1 -n 4 > nul');
  try {
    const inv = JSON.parse(execSync('aws ssm get-command-invocation --command-id ' + cmdId + ' --instance-id ' + id + ' --region ' + region + ' --output json', {
      env: { ...process.env, PYTHONIOENCODING: 'utf-8', PYTHONUTF8: '1' }
    }).toString());
    if (inv.Status === 'Success' || inv.Status === 'Failed') {
      console.log('Status:', inv.Status);
      console.log(inv.StandardOutputContent);
      if (inv.StandardErrorContent) console.log(inv.StandardErrorContent);
      done = true;
      break;
    }
  } catch (e) {}
}
if (!done) console.log('Timed out');
