const { execSync } = require('child_process');
const fs = require('fs');

function exec(cmd) {
  return execSync(cmd, {
    env: { ...process.env, PYTHONIOENCODING: 'utf-8', PYTHONUTF8: '1' },
    encoding: 'utf8'
  });
}

function runSsm(commandList, instanceId = 'i-0e7a1246bad471fff', region = 'ap-south-2') {
  const jsonParam = JSON.stringify({
    InstanceIds: [instanceId],
    DocumentName: 'AWS-RunShellScript',
    Parameters: { commands: commandList }
  });

  fs.writeFileSync('ssm_sync_public.json', jsonParam);

  const cmdId = exec(`aws ssm send-command --cli-input-json file://ssm_sync_public.json --region ${region} --query Command.CommandId --output text`).trim();
  console.log(`SSM Command dispatched: ${cmdId}`);

  let attempts = 0;
  while (attempts < 30) {
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
  'echo "=== 1. DOWNLOADING VERSION 1.0.100 BINARIES ON EC2 ==="',
  'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv-combined.apk /opt/staydriv/public/staydriv-combined.apk --region ap-south-2',
  'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv-combined.aab /opt/staydriv/public/staydriv-combined.aab --region ap-south-2',
  'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv-latest.apk /opt/staydriv/public/staydriv-latest.apk --region ap-south-2',
  'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv-latest.aab /opt/staydriv/public/staydriv-latest.aab --region ap-south-2',
  'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv-v1.0.100.apk /opt/staydriv/public/staydriv-v1.0.100.apk --region ap-south-2',
  'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv-v1.0.100.aab /opt/staydriv/public/staydriv-v1.0.100.aab --region ap-south-2',
  'aws s3 cp s3://staydriv-prod-assets-60345301/version.json /opt/staydriv/public/version.json --region ap-south-2',
  'mkdir -p /opt/staydriv/public/apk /opt/staydriv/public/aab /opt/staydriv/public/downloads',
  'cp /opt/staydriv/public/staydriv-combined.apk /opt/staydriv/public/apk/staydriv-combined.apk',
  'cp /opt/staydriv/public/staydriv-combined.aab /opt/staydriv/public/aab/staydriv-combined.aab',
  'cp /opt/staydriv/public/staydriv-combined.apk /opt/staydriv/public/downloads/staydriv-combined.apk',
  'chown -R ubuntu:ubuntu /opt/staydriv/public',
  'chmod -R 755 /opt/staydriv/public',
  'ls -lh /opt/staydriv/public/staydriv-combined*'
];

runSsm(commands);
