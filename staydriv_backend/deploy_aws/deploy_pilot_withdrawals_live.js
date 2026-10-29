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
  console.log('DEPLOYING PILOT WITHDRAWAL CONFIRMATION & ADMIN MANAGEMENT LIVE');
  console.log('================================================================\n');

  // Detect running EC2 instance
  const instanceId = runOutput('aws ec2 describe-instances --region ap-south-2 --filters Name=instance-state-name,Values=running --query "Reservations[*].Instances[*].InstanceId" --output text').trim().split(/\s+/)[0];
  console.log('Target EC2 Instance:', instanceId);
  if (!instanceId || !instanceId.startsWith('i-')) {
    throw new Error('No running EC2 instance detected in ap-south-2');
  }

  const rootDir = path.resolve(__dirname, '..');
  const tempDir = path.resolve(__dirname, 'temp_withdrawal_pkg');
  if (fs.existsSync(tempDir)) {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
  fs.mkdirSync(tempDir, { recursive: true });

  // 1. Package backend modules
  console.log('\n--- 1. Packaging backend modules ---');
  fs.copyFileSync(path.join(rootDir, 'server.js'), path.join(tempDir, 'server.js'));

  const routesDir = path.join(tempDir, 'routes');
  fs.mkdirSync(routesDir, { recursive: true });
  fs.copyFileSync(path.join(rootDir, 'routes', 'pilotWalletRoutes.js'), path.join(routesDir, 'pilotWalletRoutes.js'));
  fs.copyFileSync(path.join(rootDir, 'routes', 'financeRoutes.js'), path.join(routesDir, 'financeRoutes.js'));

  const servicesDir = path.join(tempDir, 'services');
  fs.mkdirSync(servicesDir, { recursive: true });
  fs.copyFileSync(path.join(rootDir, 'services', 'pilotWalletService.js'), path.join(servicesDir, 'pilotWalletService.js'));
  fs.copyFileSync(path.join(rootDir, 'services', 'financeService.js'), path.join(servicesDir, 'financeService.js'));

  const backendTar = path.resolve(__dirname, 'staydriv_withdrawal_backend.tar.gz').replace(/\\/g, '/');
  run(`tar -czf "${backendTar}" .`, tempDir);
  console.log('Created staydriv_withdrawal_backend.tar.gz');

  // 2. Package Admin Console build
  console.log('\n--- 2. Packaging Admin Console build ---');
  const adminDistDir = path.resolve(__dirname, '..', '..', 'Staydriv_Admin', 'dist');
  const adminTar = path.resolve(__dirname, 'admin_dist.tar.gz').replace(/\\/g, '/');
  run(`tar -czf "${adminTar}" .`, adminDistDir);
  console.log('Created admin_dist.tar.gz');

  // 3. Package Flutter Web build
  console.log('\n--- 3. Packaging Flutter Web build ---');
  const webBuildDir = path.resolve(__dirname, '..', '..', 'staydriv_app', 'build', 'web');
  const webTar = path.resolve(__dirname, 'staydriv_web_app.tar.gz').replace(/\\/g, '/');
  run(`tar -czf "${webTar}" .`, webBuildDir);
  console.log('Created staydriv_web_app.tar.gz');

  // 4. Upload to S3
  console.log('\n--- 4. Uploading tarballs and web assets to S3 ---');
  run(`aws s3 cp "${backendTar}" s3://staydriv-prod-assets-60345301/staydriv_withdrawal_backend.tar.gz --region ap-south-2`);
  run(`aws s3 cp "${adminTar}" s3://staydriv-prod-assets-60345301/admin_dist.tar.gz --region ap-south-2`);
  run(`aws s3 cp "${webTar}" s3://staydriv-prod-assets-60345301/staydriv_web_app.tar.gz --region ap-south-2`);
  run(`aws s3 sync "${webBuildDir.replace(/\\/g, '/')}" s3://staydriv-prod-assets-60345301/ --region ap-south-2 --delete --exclude "apk/*" --exclude "aab/*" --exclude "downloads/*" --exclude "*.tar.gz"`);
  run(`aws s3 sync "${adminDistDir.replace(/\\/g, '/')}" s3://staydriv-prod-assets-60345301/admin/ --region ap-south-2 --delete`);

  // 5. Dispatch SSM to EC2
  console.log(`\n--- 5. Executing deployment on EC2 instance ${instanceId} ---`);
  const ssmCommands = [
    'echo "=== 1. EXTRACTING BACKEND WITHDRAWAL MODULES ==="',
    'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv_withdrawal_backend.tar.gz /tmp/staydriv_withdrawal_backend.tar.gz --region ap-south-2',
    'tar -xzf /tmp/staydriv_withdrawal_backend.tar.gz -C /opt/staydriv',
    'echo "=== 2. EXTRACTING UPDATED ADMIN CONSOLE ==="',
    'aws s3 cp s3://staydriv-prod-assets-60345301/admin_dist.tar.gz /tmp/admin_dist.tar.gz --region ap-south-2',
    'mkdir -p /opt/Staydriv_Admin/dist /opt/staydriv/public/admin',
    'tar -xzf /tmp/admin_dist.tar.gz -C /opt/Staydriv_Admin/dist',
    'tar -xzf /tmp/admin_dist.tar.gz -C /opt/staydriv/public/admin',
    'echo "=== 3. EXTRACTING UPDATED FLUTTER WEB APP ==="',
    'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv_web_app.tar.gz /tmp/staydriv_web_app.tar.gz --region ap-south-2',
    'mkdir -p /opt/staydriv/public',
    'tar -xzf /tmp/staydriv_web_app.tar.gz -C /opt/staydriv/public',
    'chown -R ubuntu:ubuntu /opt/staydriv /opt/Staydriv_Admin',
    'echo "=== 4. VERIFYING SYNTAX ==="',
    'node -c /opt/staydriv/server.js',
    'node -c /opt/staydriv/routes/pilotWalletRoutes.js',
    'node -c /opt/staydriv/routes/financeRoutes.js',
    'node -c /opt/staydriv/services/pilotWalletService.js',
    'node -c /opt/staydriv/services/financeService.js',
    'echo "=== 5. RESTARTING STAYDRIV SERVICE ==="',
    'systemctl daemon-reload',
    'systemctl restart staydriv',
    'sleep 4',
    'systemctl is-active staydriv',
    'echo "=== 6. CHECKING HEALTH & WITHDRAWALS API ==="',
    'curl -s http://127.0.0.1:3000/api/health',
    'echo ""',
    'curl -s -H "x-admin-key: staydriv_admin_secret_2026" "http://127.0.0.1:3000/api/admin/withdrawals" | head -c 300'
  ];

  const jsonParam = JSON.stringify({
    InstanceIds: [instanceId],
    DocumentName: 'AWS-RunShellScript',
    Parameters: { commands: ssmCommands }
  });
  fs.writeFileSync(path.join(__dirname, 'ssm_deploy_withdrawal_param.json'), jsonParam);

  const cmdId = runOutput(`aws ssm send-command --cli-input-json file://ssm_deploy_withdrawal_param.json --region ap-south-2 --query Command.CommandId --output text`, __dirname).trim();
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

  // 6. Invalidate CloudFront
  console.log('\n--- 6. Invalidating CloudFront Cache ---');
  try {
    const inv = runOutput(`aws cloudfront create-invalidation --distribution-id E3I4T1HFZ2E6SJ --paths "/admin/*" "/admin" "/*" "/api/pilot/*" "/api/admin/*" --region ap-south-2 --output json`, __dirname);
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
