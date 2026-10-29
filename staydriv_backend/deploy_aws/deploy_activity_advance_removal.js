const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

function run(cmd, cwd) {
  console.log('Running:', cmd);
  return execSync(cmd, {
    cwd: cwd || __dirname,
    stdio: 'inherit',
    env: { ...process.env, PYTHONIOENCODING: 'utf-8', PYTHONUTF8: '1' }
  });
}

function runOutput(cmd, cwd) {
  return execSync(cmd, {
    cwd: cwd || __dirname,
    env: { ...process.env, PYTHONIOENCODING: 'utf-8', PYTHONUTF8: '1' },
    encoding: 'utf8'
  });
}

async function deploy() {
  console.log('================================================================');
  console.log('DEPLOYING PILOT CONSOLE ACTIVITY UPDATE TO LIVE AWS');
  console.log('================================================================\n');

  // Detect running instance
  const instanceId = runOutput('aws ec2 describe-instances --region ap-south-2 --filters Name=instance-state-name,Values=running --query "Reservations[*].Instances[*].InstanceId" --output text').trim().split(/\s+/)[0];
  console.log('Target EC2 Instance:', instanceId);
  if (!instanceId || !instanceId.startsWith('i-')) {
    throw new Error('No running EC2 instance detected in ap-south-2');
  }

  const webBuildDir = path.resolve(__dirname, '..', '..', 'staydriv_app', 'build', 'web');
  if (!fs.existsSync(path.join(webBuildDir, 'main.dart.js'))) {
    throw new Error('Flutter web build not found at: ' + webBuildDir);
  }

  // 1. Sync to local staydriv_backend/public
  console.log('\n--- 1. Syncing build files to local backend public folder ---');
  const backendPublicDir = path.resolve(__dirname, '..', 'public');
  if (!fs.existsSync(backendPublicDir)) {
    fs.mkdirSync(backendPublicDir, { recursive: true });
  }
  // Copy files
  fs.cpSync(webBuildDir, backendPublicDir, { recursive: true, force: true });
  console.log('Copied build files to', backendPublicDir);

  // 2. Package Flutter Web build
  console.log('\n--- 2. Packaging Flutter Web build ---');
  const webTar = path.resolve(__dirname, 'staydriv_web_app.tar.gz').replace(/\\/g, '/');
  if (fs.existsSync(webTar)) {
    fs.unlinkSync(webTar);
  }
  run(`tar -czf "${webTar}" .`, webBuildDir);
  console.log('Created staydriv_web_app.tar.gz');

  // 3. Upload to S3
  console.log('\n--- 3. Uploading web tarball and assets to S3 ---');
  run(`aws s3 cp "${webTar}" s3://staydriv-prod-assets-60345301/staydriv_web_app.tar.gz --region ap-south-2`);
  run(`aws s3 sync "${webBuildDir.replace(/\\/g, '/')}" s3://staydriv-prod-assets-60345301/ --region ap-south-2 --delete --exclude "apk/*" --exclude "aab/*" --exclude "downloads/*" --exclude "*.tar.gz"`);

  // 4. Dispatch SSM to EC2
  console.log(`\n--- 4. Executing deployment on EC2 instance ${instanceId} ---`);
  const ssmCommands = [
    'echo "=== EXTRACTING UPDATED FLUTTER WEB APP ==="',
    'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv_web_app.tar.gz /tmp/staydriv_web_app.tar.gz --region ap-south-2',
    'mkdir -p /opt/staydriv/public',
    'tar -xzf /tmp/staydriv_web_app.tar.gz -C /opt/staydriv/public',
    'chown -R ubuntu:ubuntu /opt/staydriv/public',
    'echo "=== VERIFYING WEB ASSETS ON EC2 ==="',
    'ls -lh /opt/staydriv/public/main.dart.js',
    'echo "=== CHECKING SYSTEM STATUS ==="',
    'systemctl is-active staydriv',
    'curl -s http://127.0.0.1:3000/api/health'
  ];

  const jsonParam = JSON.stringify({
    InstanceIds: [instanceId],
    DocumentName: 'AWS-RunShellScript',
    Parameters: { commands: ssmCommands }
  });
  fs.writeFileSync(path.join(__dirname, 'ssm_deploy_param.json'), jsonParam);

  const cmdId = runOutput(`aws ssm send-command --cli-input-json file://ssm_deploy_param.json --region ap-south-2 --query Command.CommandId --output text`, __dirname).trim();
  console.log('SSM Command dispatched:', cmdId);

  // Poll for completion
  let finished = false;
  for (let i = 0; i < 40; i++) {
    execSync('timeout /t 3 > nul 2>&1 || ping 127.0.0.1 -n 4 > nul');
    try {
      const res = runOutput(`aws ssm get-command-invocation --command-id ${cmdId} --instance-id ${instanceId} --region ap-south-2 --output json`, __dirname);
      const obj = JSON.parse(res);
      if (obj.Status === 'Success' || obj.Status === 'Failed') {
        console.log('\nStatus:', obj.Status);
        console.log('--- STDOUT ---\n', obj.StandardOutputContent);
        if (obj.StandardErrorContent) {
          console.log('--- STDERR ---\n', obj.StandardErrorContent);
        }
        finished = true;
        if (obj.Status === 'Failed') {
          throw new Error('SSM command failed on EC2');
        }
        break;
      } else {
        process.stdout.write('.');
      }
    } catch (e) {
      if (e.message && e.message.includes('SSM command failed')) throw e;
    }
  }

  if (!finished) {
    console.warn('\nSSM command timed out waiting for completion.');
  }

  // 5. Invalidate CloudFront
  console.log('\n--- 5. Invalidating CloudFront Cache ---');
  try {
    const inv = runOutput(`aws cloudfront create-invalidation --distribution-id E3I4T1HFZ2E6SJ --paths "/main.dart.js" "/index.html" "/flutter_service_worker.js" "/*" --region ap-south-2 --output json`, __dirname);
    const invObj = JSON.parse(inv);
    console.log('CloudFront invalidation created:', invObj.Invalidation ? invObj.Invalidation.Id : inv);
  } catch (invErr) {
    console.warn('CloudFront invalidation note:', invErr.message);
  }

  console.log('\n=== LIVE AWS DEPLOYMENT COMPLETED SUCCESSFULLY ===');
}

deploy().catch(err => {
  console.error('\nDeployment error:', err);
  process.exit(1);
});
