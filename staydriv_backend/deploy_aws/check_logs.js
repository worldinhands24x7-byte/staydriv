const { execSync } = require('child_process');
const fs = require('fs');

const ssmDoc = JSON.stringify({
  InstanceIds: ['i-0f8915ff46459c3b5'],
  DocumentName: 'AWS-RunShellScript',
  Parameters: {
    commands: [
      'grep -i "/api/food/partner" /var/log/staydriv/app.log | tail -n 50'
    ]
  }
});
fs.writeFileSync('check_logs.json', ssmDoc);
const cmdId = execSync('aws ssm send-command --cli-input-json file://check_logs.json --region ap-south-2 --query Command.CommandId --output text', { 
  encoding: 'utf8',
  env: { ...process.env, PYTHONIOENCODING: 'utf-8', PYTHONUTF8: '1' }
}).trim();
console.log('Dispatched:', cmdId);
let attempts = 0;
while(attempts < 20) {
  execSync('timeout /t 2 > nul 2>&1 || ping 127.0.0.1 -n 3 > nul');
  attempts++;
  try {
    const invStr = execSync(`aws ssm get-command-invocation --command-id ${cmdId} --instance-id i-0f8915ff46459c3b5 --region ap-south-2 --output json`, { 
      encoding: 'utf8',
      env: { ...process.env, PYTHONIOENCODING: 'utf-8', PYTHONUTF8: '1' }
    });
    const inv = JSON.parse(invStr);
    if (inv.Status === 'Success' || inv.Status === 'Failed') {
      console.log('Status:', inv.Status);
      console.log('STDOUT:\n', inv.StandardOutputContent);
      break;
    }
  } catch(e) {}
}
