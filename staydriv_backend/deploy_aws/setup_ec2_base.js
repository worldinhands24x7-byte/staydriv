const { execSync } = require('child_process');
const fs = require('fs');

const instanceId = 'i-0a8cfb22fc40c7591';
const region = 'ap-south-2';

const commands = [
  'echo "=== 1. WAITING FOR UNATTENDED-UPGRADES / DPKG TO FINISH ==="',
  'while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do echo "Waiting for apt lock..."; sleep 3; done',
  'echo "Lock clear. Configuring pending packages..."',
  'dpkg --configure -a',
  'echo "=== 2. INSTALLING AWS CLI AND NODE.JS 20 ==="',
  'apt-get update -y',
  'apt-get install -y awscli curl unzip',
  'curl -fsSL https://deb.nodesource.com/setup_20.x | bash -',
  'apt-get install -y nodejs',
  'echo "Versions installed:"',
  'aws --version',
  'node -v',
  'npm -v'
];

const ssmDoc = JSON.stringify({
  InstanceIds: [instanceId],
  DocumentName: 'AWS-RunShellScript',
  Parameters: { commands }
});
fs.writeFileSync('ssm_base.json', ssmDoc);
const cmdId = execSync(`aws ssm send-command --cli-input-json file://ssm_base.json --region ${region} --query Command.CommandId --output text`, { encoding: 'utf8' }).trim();
console.log('Dispatched base setup command:', cmdId);

let attempts = 0;
while(attempts < 40) {
  execSync('timeout /t 4 > nul 2>&1 || ping 127.0.0.1 -n 5 > nul');
  attempts++;
  try {
    const invStr = execSync(`aws ssm get-command-invocation --command-id ${cmdId} --instance-id ${instanceId} --region ${region} --output json`, { encoding: 'utf8' });
    const inv = JSON.parse(invStr);
    if (inv.Status === 'Success' || inv.Status === 'Failed' || inv.Status === 'TimedOut' || inv.Status === 'Cancelled') {
      console.log('Status:', inv.Status);
      console.log('STDOUT:\n', inv.StandardOutputContent);
      console.log('STDERR:\n', inv.StandardErrorContent);
      break;
    }
  } catch(e) {}
}
