const { execSync } = require('child_process');
const fs = require('fs');

const ssmDoc = JSON.stringify({
  InstanceIds: ['i-090dbc33c50d882c6'],
  DocumentName: 'AWS-RunShellScript',
  Parameters: {
    commands: [
      'systemctl status staydriv --no-pager',
      'journalctl -u staydriv -n 50 --no-pager'
    ]
  }
});
fs.writeFileSync('ssm_status.json', ssmDoc);
const cmdId = execSync('aws ssm send-command --cli-input-json file://ssm_status.json --region ap-south-2 --query Command.CommandId --output text', { 
  encoding: 'utf8',
  env: { ...process.env, PYTHONIOENCODING: 'utf-8', PYTHONUTF8: '1' }
}).trim();
console.log('Dispatched:', cmdId);
let attempts = 0;
while(attempts < 20) {
  execSync('timeout /t 3 > nul 2>&1 || ping 127.0.0.1 -n 4 > nul');
  attempts++;
  try {
    const invStr = execSync(`aws ssm get-command-invocation --command-id ${cmdId} --instance-id i-090dbc33c50d882c6 --region ap-south-2 --output json`, { 
      encoding: 'utf8',
      env: { ...process.env, PYTHONIOENCODING: 'utf-8', PYTHONUTF8: '1' }
    });
    const inv = JSON.parse(invStr);
    if (inv.Status === 'Success' || inv.Status === 'Failed') {
      console.log('Status:', inv.Status);
      console.log('STDOUT:\n', inv.StandardOutputContent);
      console.log('STDERR:\n', inv.StandardErrorContent);
      break;
    }
  } catch(e) {}
}
