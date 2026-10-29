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
  console.log('DEPLOYING TATA SMARTFLO FOOD CALL MASKING SYSTEM TO LIVE AWS');
  console.log('================================================================\n');

  // Detect running instance
  const instanceId = runOutput('aws ec2 describe-instances --region ap-south-2 --filters Name=instance-state-name,Values=running --query "Reservations[*].Instances[*].InstanceId" --output text').trim().split(/\s+/)[0];
  console.log('Target EC2 Instance:', instanceId);
  if (!instanceId || !instanceId.startsWith('i-')) {
    throw new Error('No running EC2 instance detected in ap-south-2');
  }

  const rootDir = path.resolve(__dirname, '..');
  const tempDir = path.resolve(__dirname, 'temp_smartflo_calling_pkg');
  if (fs.existsSync(tempDir)) {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
  fs.mkdirSync(tempDir, { recursive: true });

  // 1. Package backend files
  console.log('\n--- 1. Packaging backend modules ---');
  fs.copyFileSync(path.join(rootDir, 'server.js'), path.join(tempDir, 'server.js'));

  const routesDir = path.join(tempDir, 'routes');
  fs.mkdirSync(routesDir, { recursive: true });
  fs.copyFileSync(path.join(rootDir, 'routes', 'foodRoutes.js'), path.join(routesDir, 'foodRoutes.js'));

  const servicesDir = path.join(tempDir, 'services');
  fs.mkdirSync(servicesDir, { recursive: true });
  fs.copyFileSync(path.join(rootDir, 'services', 'smartflo_service.js'), path.join(servicesDir, 'smartflo_service.js'));

  const modelsDir = path.join(tempDir, 'models');
  fs.mkdirSync(modelsDir, { recursive: true });
  fs.copyFileSync(path.join(rootDir, 'models', 'FoodOrder.js'), path.join(modelsDir, 'FoodOrder.js'));

  const backendTar = path.resolve(__dirname, 'staydriv_smartflo_backend.tar.gz').replace(/\\/g, '/');
  run(`tar -czf "${backendTar}" .`, tempDir);
  console.log('Created staydriv_smartflo_backend.tar.gz');

  // 2. Package Flutter Web build
  console.log('\n--- 2. Packaging Flutter Web build ---');
  const webBuildDir = path.resolve(__dirname, '..', '..', 'staydriv_app', 'build', 'web');
  const webTar = path.resolve(__dirname, 'staydriv_web_app.tar.gz').replace(/\\/g, '/');
  run(`tar -czf "${webTar}" .`, webBuildDir);
  console.log('Created staydriv_web_app.tar.gz');

  // 3. Package Admin Console build
  console.log('\n--- 3. Packaging StayDriv Admin Console dist ---');
  const adminDistDir = path.resolve(__dirname, '..', '..', 'Staydriv_Admin', 'dist');
  const adminTar = path.resolve(__dirname, 'staydriv_admin_dist.tar.gz').replace(/\\/g, '/');
  run(`tar -czf "${adminTar}" .`, adminDistDir);
  console.log('Created staydriv_admin_dist.tar.gz');

  // 4. Upload to S3
  console.log('\n--- 4. Uploading tarballs and web assets to S3 ---');
  run(`aws s3 cp "${backendTar}" s3://staydriv-prod-assets-60345301/staydriv_smartflo_backend.tar.gz --region ap-south-2`);
  run(`aws s3 cp "${webTar}" s3://staydriv-prod-assets-60345301/staydriv_web_app.tar.gz --region ap-south-2`);
  run(`aws s3 cp "${adminTar}" s3://staydriv-prod-assets-60345301/staydriv_admin_dist.tar.gz --region ap-south-2`);
  run(`aws s3 sync "${webBuildDir.replace(/\\/g, '/')}" s3://staydriv-prod-assets-60345301/ --region ap-south-2 --delete --exclude "apk/*" --exclude "aab/*" --exclude "downloads/*" --exclude "*.tar.gz"`);

  // 5. Dispatch SSM to EC2
  console.log(`\n--- 5. Executing deployment on EC2 instance ${instanceId} ---`);
  const ssmCommands = [
    'echo "=== 1. EXTRACTING SMARTFLO BACKEND MODULES ==="',
    'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv_smartflo_backend.tar.gz /tmp/staydriv_smartflo_backend.tar.gz --region ap-south-2',
    'tar -xzf /tmp/staydriv_smartflo_backend.tar.gz -C /opt/staydriv',
    'echo "=== 2. EXTRACTING UPDATED FLUTTER WEB APP ==="',
    'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv_web_app.tar.gz /tmp/staydriv_web_app.tar.gz --region ap-south-2',
    'mkdir -p /opt/staydriv/public',
    'tar -xzf /tmp/staydriv_web_app.tar.gz -C /opt/staydriv/public',
    'echo "=== 3. EXTRACTING UPDATED ADMIN CONSOLE ==="',
    'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv_admin_dist.tar.gz /tmp/staydriv_admin_dist.tar.gz --region ap-south-2',
    'mkdir -p /opt/Staydriv_Admin/dist /opt/staydriv/public/admin',
    'tar -xzf /tmp/staydriv_admin_dist.tar.gz -C /opt/Staydriv_Admin/dist',
    'tar -xzf /tmp/staydriv_admin_dist.tar.gz -C /opt/staydriv/public/admin',
    'chown -R ubuntu:ubuntu /opt/staydriv /opt/Staydriv_Admin',
    'echo "=== 4. VERIFYING SYNTAX ==="',
    'node -c /opt/staydriv/server.js',
    'node -c /opt/staydriv/routes/foodRoutes.js',
    'node -c /opt/staydriv/services/smartflo_service.js',
    'node -c /opt/staydriv/models/FoodOrder.js',
    'echo "=== 5. RESTARTING STAYDRIV SERVICE ==="',
    'systemctl daemon-reload',
    'systemctl restart staydriv',
    'sleep 4',
    'systemctl is-active staydriv',
    'echo "=== 6. CHECKING HEALTH API ==="',
    'curl -s http://127.0.0.1:3000/api/health'
  ];

  const jsonParam = JSON.stringify({
    InstanceIds: [instanceId],
    DocumentName: 'AWS-RunShellScript',
    Parameters: { commands: ssmCommands }
  });
  fs.writeFileSync(path.join(__dirname, 'ssm_smartflo_calling_param.json'), jsonParam);

  const cmdId = runOutput(`aws ssm send-command --cli-input-json file://ssm_smartflo_calling_param.json --region ap-south-2 --query Command.CommandId --output text`, __dirname).trim();
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
    const inv = runOutput(`aws cloudfront create-invalidation --distribution-id E3I4T1HFZ2E6SJ --paths "/api/food/*" "/api/admin/*" "/admin/*" "/*" --region ap-south-2 --output json`, __dirname);
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
