const { execSync } = require('child_process');
const fs = require('fs');

const instanceId = 'i-0a8cfb22fc40c7591';
const region = 'ap-south-2';

const commands = [
  'echo "=== Installing AWS CLI v2 ==="',
  'if ! command -v aws &> /dev/null; then',
  '  curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"',
  '  unzip -q -o /tmp/awscliv2.zip -d /tmp',
  '  /tmp/aws/install --update',
  '  rm -rf /tmp/aws /tmp/awscliv2.zip',
  'fi',
  'aws --version'
];

const ssmDoc = JSON.stringify({
  InstanceIds: [instanceId],
  DocumentName: 'AWS-RunShellScript',
  Parameters: { commands }
});
fs.writeFileSync('ssm_awscli.json', ssmDoc);
const cmdId = execSync(`aws ssm send-command --cli-input-json file://ssm_awscli.json --region ${region} --query Command.CommandId --output text`, { encoding: 'utf8' }).trim();
console.log('Dispatched AWS CLI install:', cmdId);

let attempts = 0;
while(attempts < 30) {
  execSync('timeout /t 3 > nul 2>&1 || ping 127.0.0.1 -n 4 > nul');
  attempts++;
  try {
    const invStr = execSync(`aws ssm get-command-invocation --command-id ${cmdId} --instance-id ${instanceId} --region ${region} --output json`, { encoding: 'utf8' });
    const inv = JSON.parse(invStr);
    if (inv.Status === 'Success' || inv.Status === 'Failed' || inv.Status === 'TimedOut') {
      console.log('Status:', inv.Status);
      console.log('STDOUT:\n', inv.StandardOutputContent);
      console.log('STDERR:\n', inv.StandardErrorContent);
      break;
    }
  } catch(e) {}
}
