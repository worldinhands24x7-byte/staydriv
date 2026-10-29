const { execSync } = require('child_process');
const fs = require('fs');

const INSTANCE_ID = 'i-0732ea9b317396a96';
const REGION = 'ap-south-2';

const verifyCommands = [
  'echo "=== SERVICE STATUS ==="',
  'systemctl is-active staydriv',
  'echo "=== HEALTH CHECK ==="',
  'curl -s http://127.0.0.1:3000/api/health',
  'echo ""',
  'echo "=== SHARE STATS ==="',
  'curl -s http://127.0.0.1:3000/api/share/stats',
  'echo ""',
  'echo "=== ROUND TRIP FARE VALIDATOR ==="',
  'curl -s -X POST -H "Content-Type: application/json" -d \'{"vehicleType":"Car","outwardDistanceKm":14,"returnDistanceKm":14,"pilotWaitOption":"pilot_wait","waitingMinutes":25}\' http://127.0.0.1:3000/api/fare/calculate-round-trip',
  'echo ""',
  'echo "=== ADMIN CONSOLE HTML ==="',
  'curl -s http://127.0.0.1:3000/admin | head -n 12',
  'echo ""',
  'echo "=== VERSION METADATA ==="',
  'curl -s http://127.0.0.1:3000/version.json',
  'echo ""'
];

fs.writeFileSync('d:/staydriv/ssm_verify_cmds.json', JSON.stringify({ commands: verifyCommands }));

const res = execSync(
  `aws ssm send-command --instance-ids ${INSTANCE_ID} --document-name AWS-RunShellScript --parameters file://d:/staydriv/ssm_verify_cmds.json --region ${REGION} --output json`,
  { encoding: 'utf8' }
);
const cmdId = JSON.parse(res).Command.CommandId;
console.log('Dispatched verification Command ID:', cmdId);

// Wait 6 seconds and fetch output
Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 6000);

const out = execSync(
  `aws ssm get-command-invocation --command-id ${cmdId} --instance-id ${INSTANCE_ID} --region ${REGION} --output json`,
  { encoding: 'utf8' }
);
const data = JSON.parse(out);
console.log('STATUS:', data.Status);
console.log('\n--- OUTPUT ---');
console.log(data.StandardOutputContent);
