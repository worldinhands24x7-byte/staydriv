const { execSync } = require('child_process');
const fs = require('fs');

const ssmDoc = JSON.stringify({
  InstanceIds: ['i-01f8041ff05d9a7db'],
  DocumentName: 'AWS-RunShellScript',
  Parameters: {
    commands: [
      'cat /var/lib/cloud/instance/scripts/* 2>/dev/null || cat /var/lib/cloud/instance/user-data.txt 2>/dev/null'
    ]
  }
});
fs.writeFileSync('ssm_userdata.json', ssmDoc);
const cmdId = execSync('aws ssm send-command --cli-input-json file://ssm_userdata.json --region ap-south-2 --query Command.CommandId --output text', { 
  encoding: 'utf8',
  env: { ...process.env, PYTHONIOENCODING: 'utf-8', PYTHONUTF8: '1' }
}).trim();
console.log('Dispatched:', cmdId);
let attempts = 0;
while(attempts < 20) {
  execSync('timeout /t 3 > nul 2>&1 || ping 127.0.0.1 -n 4 > nul');
  attempts++;
  try {
    const invStr = execSync(`aws ssm get-command-invocation --command-id ${cmdId} --instance-id i-01f8041ff05d9a7db --region ap-south-2 --output json`, { 
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
