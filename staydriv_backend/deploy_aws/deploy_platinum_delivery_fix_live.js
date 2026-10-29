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
  console.log('DEPLOYING PLATINUM FREE DELIVERY & PILOT EARNINGS TO AWS EC2');
  console.log('================================================================\n');

  // Detect running instance
  const instanceId = runOutput('aws ec2 describe-instances --region ap-south-2 --filters Name=instance-state-name,Values=running --query "Reservations[*].Instances[*].InstanceId" --output text').trim().split(/\s+/)[0];
  console.log('Target EC2 Instance:', instanceId);
  if (!instanceId || !instanceId.startsWith('i-')) {
    throw new Error('No running EC2 instance detected in ap-south-2');
  }

  const rootDir = path.resolve(__dirname, '..');
  const tempDir = path.resolve(__dirname, 'temp_platinum_pkg');
  if (fs.existsSync(tempDir)) {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
  fs.mkdirSync(tempDir, { recursive: true });

  // 1. Package backend files
  console.log('\n--- 1. Packaging backend modules ---');
  const routesDir = path.join(tempDir, 'routes');
  fs.mkdirSync(routesDir, { recursive: true });
  fs.copyFileSync(path.join(rootDir, 'routes', 'foodMembershipRoutes.js'), path.join(routesDir, 'foodMembershipRoutes.js'));
  fs.copyFileSync(path.join(rootDir, 'routes', 'foodRoutes.js'), path.join(routesDir, 'foodRoutes.js'));

  const servicesDir = path.join(tempDir, 'services');
  fs.mkdirSync(servicesDir, { recursive: true });
  fs.copyFileSync(path.join(rootDir, 'services', 'foodBillCalculationService.js'), path.join(servicesDir, 'foodBillCalculationService.js'));
  fs.copyFileSync(path.join(rootDir, 'services', 'pilotWalletService.js'), path.join(servicesDir, 'pilotWalletService.js'));

  const modelsDir = path.join(tempDir, 'models');
  fs.mkdirSync(modelsDir, { recursive: true });
  fs.copyFileSync(path.join(rootDir, 'models', 'FoodOrder.js'), path.join(modelsDir, 'FoodOrder.js'));

  const backendTar = path.resolve(__dirname, 'staydriv_platinum_backend.tar.gz').replace(/\\/g, '/');
  run(`tar -czf "${backendTar}" .`, tempDir);
  console.log('Created staydriv_platinum_backend.tar.gz');

  // 2. Package Flutter Web build
  console.log('\n--- 2. Packaging Flutter Web build ---');
  const webBuildDir = path.resolve(__dirname, '..', '..', 'staydriv_app', 'build', 'web');
  const webTar = path.resolve(__dirname, 'staydriv_web_app.tar.gz').replace(/\\/g, '/');
  run(`tar -czf "${webTar}" .`, webBuildDir);
  console.log('Created staydriv_web_app.tar.gz');

  // 3. Upload to S3
  console.log('\n--- 3. Uploading tarballs and web assets to S3 ---');
  run(`aws s3 cp "${backendTar}" s3://staydriv-prod-assets-60345301/staydriv_platinum_backend.tar.gz --region ap-south-2`);
  run(`aws s3 cp "${webTar}" s3://staydriv-prod-assets-60345301/staydriv_web_app.tar.gz --region ap-south-2`);
  run(`aws s3 sync "${webBuildDir.replace(/\\/g, '/')}" s3://staydriv-prod-assets-60345301/ --region ap-south-2 --delete --exclude "apk/*" --exclude "aab/*" --exclude "downloads/*" --exclude "*.tar.gz"`);

  // 4. Dispatch SSM to EC2
  console.log(`\n--- 4. Executing deployment on EC2 instance ${instanceId} ---`);
  const ssmCommands = [
    'echo "=== 1. EXTRACTING BACKEND PLATINUM MODULES ==="',
    'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv_platinum_backend.tar.gz /tmp/staydriv_platinum_backend.tar.gz --region ap-south-2',
    'tar -xzf /tmp/staydriv_platinum_backend.tar.gz -C /opt/staydriv',
    'echo "=== 2. EXTRACTING UPDATED FLUTTER WEB APP ==="',
    'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv_web_app.tar.gz /tmp/staydriv_web_app.tar.gz --region ap-south-2',
    'mkdir -p /opt/staydriv/public',
    'tar -xzf /tmp/staydriv_web_app.tar.gz -C /opt/staydriv/public',
    'chown -R ubuntu:ubuntu /opt/staydriv',
    'echo "=== 3. VERIFYING SYNTAX ==="',
    'node -c /opt/staydriv/routes/foodMembershipRoutes.js',
    'node -c /opt/staydriv/routes/foodRoutes.js',
    'node -c /opt/staydriv/services/foodBillCalculationService.js',
    'node -c /opt/staydriv/services/pilotWalletService.js',
    'echo "=== 4. RESTARTING STAYDRIV SERVICE ==="',
    'systemctl daemon-reload',
    'systemctl restart staydriv',
    'sleep 4',
    'systemctl is-active staydriv',
    'echo "=== 5. CHECKING HEALTH API ==="',
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
    const inv = runOutput(`aws cloudfront create-invalidation --distribution-id E3I4T1HFZ2E6SJ --paths "/api/food/*" "/api/food/membership/*" "/*" --region ap-south-2 --output json`, __dirname);
    const invObj = JSON.parse(inv);
    console.log('CloudFront invalidation created:', invObj.Invalidation ? invObj.Invalidation.Id : inv);
  } catch (invErr) {
    console.warn('CloudFront invalidation note:', invErr.message);
  }

  // Cleanup local tarballs
  fs.rmSync(tempDir, { recursive: true, force: true });
  console.log('\n=== LIVE AWS DEPLOYMENT COMPLETED SUCCESSFULLY ===');
}

deploy().catch(err => {
  console.error('\nDeployment error:', err);
  process.exit(1);
});
