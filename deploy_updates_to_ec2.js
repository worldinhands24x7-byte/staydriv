const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const INSTANCE_ID = 'i-022567dabce0647bc';
const REGION = 'ap-south-2';

const filesToDeploy = [
  {
    local: 'd:/staydriv/staydriv_backend/models/Otp.js',
    remote: '/opt/staydriv/models/Otp.js'
  },
  {
    local: 'd:/staydriv/staydriv_backend/models/OtpLog.js',
    remote: '/opt/staydriv/models/OtpLog.js'
  },
  {
    local: 'd:/staydriv/staydriv_backend/controllers/otpController.js',
    remote: '/opt/staydriv/controllers/otpController.js'
  },
  {
    local: 'd:/staydriv/staydriv_backend/services/smartfloSmsService.js',
    remote: '/opt/staydriv/services/smartfloSmsService.js'
  },
  {
    local: 'd:/staydriv/staydriv_backend/services/smsService.js',
    remote: '/opt/staydriv/services/smsService.js'
  },
  {
    local: 'd:/staydriv/staydriv_backend/routes/otp.js',
    remote: '/opt/staydriv/routes/otp.js'
  },
  {
    local: 'd:/staydriv/staydriv_backend/test_real_ttbs_otp_flow.js',
    remote: '/opt/staydriv/test_real_ttbs_otp_flow.js'
  }
];

function runSsm(commands) {
  const params = { commands };
  fs.writeFileSync('ssm_deploy.json', JSON.stringify(params));
  const sendOut = execSync(`aws ssm send-command --instance-ids ${INSTANCE_ID} --document-name AWS-RunShellScript --parameters file://ssm_deploy.json --region ${REGION} --output json`, {
    encoding: 'utf8',
    env: { ...process.env, PYTHONUTF8: '1', PYTHONIOENCODING: 'utf-8' }
  });
  const cmdId = JSON.parse(sendOut).Command.CommandId;
  console.log(`[SSM] Dispatched command ${cmdId}`);

  let done = false;
  let attempts = 0;
  while (!done && attempts < 15) {
    attempts++;
    execSync('powershell -Command "Start-Sleep -Seconds 2"');
    try {
      const invOut = execSync(`aws ssm get-command-invocation --command-id ${cmdId} --instance-id ${INSTANCE_ID} --region ${REGION} --output json`, {
        encoding: 'buffer',
        env: { ...process.env, PYTHONUTF8: '1', PYTHONIOENCODING: 'utf-8' }
      });
      const inv = JSON.parse(invOut.toString('utf8'));
      if (inv.Status === 'Success') {
        console.log(`[SSM SUCCESS]:\n${inv.StandardOutputContent}`);
        done = true;
        return inv.StandardOutputContent;
      } else if (inv.Status === 'Failed') {
        console.error(`[SSM FAILED]:\n${inv.StandardErrorContent || inv.StandardOutputContent}`);
        done = true;
        throw new Error('Command failed on EC2');
      }
    } catch (e) {
      if (e.message === 'Command failed on EC2') throw e;
    }
  }
}

async function main() {
  console.log('=== DEPLOYING UPDATED TTBS OTP BACKEND TO EC2 ===');
  
  for (const f of filesToDeploy) {
    console.log(`Uploading ${path.basename(f.remote)}...`);
    const content = fs.readFileSync(f.local, 'utf8');
    const b64 = Buffer.from(content).toString('base64');
    const remoteDir = path.posix.dirname(f.remote);
    
    runSsm([
      `mkdir -p ${remoteDir}`,
      `echo "${b64}" | base64 -d > ${f.remote}`,
      `chown ubuntu:ubuntu ${f.remote}`,
      `ls -lh ${f.remote}`
    ]);
  }

  console.log('Restarting staydriv service on EC2...');
  runSsm([
    'systemctl restart staydriv',
    'systemctl is-active staydriv',
    'tail -n 15 /var/log/staydriv/app.log'
  ]);

  console.log('Running test suite on EC2...');
  runSsm([
    'cd /opt/staydriv && node test_real_ttbs_otp_flow.js'
  ]);

  console.log('=== DEPLOYMENT AND VERIFICATION COMPLETE! ===');
}

main().catch(err => {
  console.error('Deployment error:', err);
  process.exit(1);
});
