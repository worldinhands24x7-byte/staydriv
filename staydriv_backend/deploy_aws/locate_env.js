const { execSync } = require('child_process');
const fs = require('fs');

const ssmDoc = JSON.stringify({
  InstanceIds: ['i-01f8041ff05d9a7db'],
  DocumentName: 'AWS-RunShellScript',
  Parameters: {
    commands: [
      'export PATH=$PATH:/usr/local/bin:/usr/bin:~/.nvm/versions/node/$(ls ~/.nvm/versions/node 2>/dev/null | tail -1)/bin:/home/ubuntu/.nvm/versions/node/$(ls /home/ubuntu/.nvm/versions/node 2>/dev/null | tail -1)/bin',
      'echo "Finding node:"',
      'find / -name "node" -type f -executable 2>/dev/null | head -n 10',
      'echo "Checking systemd services:"',
      'ls -la /etc/systemd/system/*staydriv* /lib/systemd/system/*staydriv* 2>/dev/null || echo "None"',
      'echo "Checking PM2:"',
      'which pm2 || find / -name "pm2" -type f 2>/dev/null | head -n 5',
      'echo "Checking cloud-init:"',
      'tail -n 25 /var/log/cloud-init-output.log 2>/dev/null || echo "No cloud init"'
    ]
  }
});
fs.writeFileSync('ssm_locate.json', ssmDoc);
const cmdId = execSync('aws ssm send-command --cli-input-json file://ssm_locate.json --region ap-south-2 --query Command.CommandId --output text', { 
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
      console.log('STDERR:\n', inv.StandardErrorContent);
      break;
    }
  } catch(e) {}
}
