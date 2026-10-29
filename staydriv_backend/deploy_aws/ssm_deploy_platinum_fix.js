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
  console.log('DEPLOYING STAYDRIV PLATINUM ₹1 PAYMENT FIX TO AWS EC2');
  console.log('================================================================');

  const rootDir = path.resolve(__dirname, '..');
  const tempDir = path.resolve(__dirname, 'temp_platinum_deploy');
  if (fs.existsSync(tempDir)) {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
  fs.mkdirSync(tempDir, { recursive: true });

  // 1. Copy backend routes and services
  console.log('\n--- 1. Packaging backend food & membership modules ---');
  const routesDir = path.join(tempDir, 'routes');
  fs.mkdirSync(routesDir, { recursive: true });
  fs.copyFileSync(path.join(rootDir, 'routes', 'foodMembershipRoutes.js'), path.join(routesDir, 'foodMembershipRoutes.js'));
  fs.copyFileSync(path.join(rootDir, 'routes', 'foodRoutes.js'), path.join(routesDir, 'foodRoutes.js'));

  const servicesDir = path.join(tempDir, 'services');
  fs.mkdirSync(servicesDir, { recursive: true });
  fs.copyFileSync(path.join(rootDir, 'services', 'foodBillCalculationService.js'), path.join(servicesDir, 'foodBillCalculationService.js'));

  // Create tarball
  const backendTar = path.resolve(__dirname, 'staydriv_platinum_backend.tar.gz').replace(/\\/g, '/');
  run(`tar -czf "${backendTar}" .`, tempDir);
  console.log('Created staydriv_platinum_backend.tar.gz');

  // 2. Package Admin Console dist
  console.log('\n--- 2. Packaging Admin Console dist ---');
  const adminDistDir = path.resolve(__dirname, '..', '..', 'Staydriv_Admin', 'dist');
  const adminTar = path.resolve(__dirname, 'admin-dist.tar.gz').replace(/\\/g, '/');
  run(`tar -czf "${adminTar}" .`, adminDistDir);
  console.log('Created admin-dist.tar.gz');

  // 3. Upload artifacts to S3 deployment bucket
  console.log('\n--- 3. Uploading to S3 deployment bucket ---');
  run(`aws s3 cp "${backendTar}" s3://staydriv-prod-assets-60345301/staydriv_platinum_backend.tar.gz --region ap-south-2`, __dirname);
  run(`aws s3 cp "${adminTar}" s3://staydriv-prod-assets-60345301/admin-dist.tar.gz --region ap-south-2`, __dirname);

  // 4. Dispatch SSM Command to EC2
  console.log('\n--- 4. Executing deployment on EC2 instance i-090dbc33c50d882c6 ---');
  const ssmCommands = [
    'echo "=== 1. UPDATING SYSTEMD SERVICE WITH RAZORPAY ENVIRONMENT ==="',
    'if ! grep -q "RAZORPAY_KEY_ID" /etc/systemd/system/staydriv.service; then',
    '  sed -i \'/Environment=AWS_DEFAULT_REGION=ap-south-2/a Environment=RAZORPAY_KEY_ID=rzp_live_Ta9cOGnIySuBCb\\nEnvironment=RAZORPAY_KEY_SECRET=c93MSwcWO22lZuC7Xm5jURu0\' /etc/systemd/system/staydriv.service',
    'fi',
    'echo "RAZORPAY_KEY_ID=rzp_live_Ta9cOGnIySuBCb" > /opt/staydriv/.env',
    'echo "RAZORPAY_KEY_SECRET=c93MSwcWO22lZuC7Xm5jURu0" >> /opt/staydriv/.env',
    'echo "NODE_ENV=prod" >> /opt/staydriv/.env',
    'echo "PORT=3000" >> /opt/staydriv/.env',
    'chown ubuntu:ubuntu /opt/staydriv/.env',
    'systemctl daemon-reload',
    'echo "=== 2. DOWNLOADING AND EXTRACTING BACKEND CODE ==="',
    'aws s3 cp s3://staydriv-prod-assets-60345301/staydriv_platinum_backend.tar.gz /tmp/staydriv_platinum_backend.tar.gz --region ap-south-2',
    'tar -xzf /tmp/staydriv_platinum_backend.tar.gz -C /opt/staydriv',
    'echo "=== 3. DOWNLOADING AND EXTRACTING ADMIN CONSOLE ==="',
    'aws s3 cp s3://staydriv-prod-assets-60345301/admin-dist.tar.gz /tmp/admin-dist.tar.gz --region ap-south-2',
    'mkdir -p /opt/staydriv/public/admin',
    'tar -xzf /tmp/admin-dist.tar.gz -C /opt/staydriv/public/admin',
    'echo "=== 4. VERIFYING SYNTAX ==="',
    'node -c /opt/staydriv/routes/foodMembershipRoutes.js',
    'node -c /opt/staydriv/routes/foodRoutes.js',
    'echo "=== 5. RESTARTING STAYDRIV SERVICE ==="',
    'systemctl restart staydriv',
    'sleep 3',
    'systemctl is-active staydriv',
    'echo "=== 6. VERIFYING RAZORPAY ENVIRONMENT IN RUNNING PID ==="',
    'PID=$(pgrep -f "node /opt/staydriv/server.js" | head -n 1)',
    'tr "\\0" "\\n" < /proc/$PID/environ | grep -E "RAZORPAY|PORT|NODE_ENV"',
    'echo "=== 7. VERIFYING HEALTH API ==="',
    'curl -s http://127.0.0.1:3000/api/health'
  ];

  const jsonParam = JSON.stringify({
    InstanceIds: ['i-090dbc33c50d882c6'],
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
      const res = runOutput(`aws ssm get-command-invocation --command-id ${cmdId} --instance-id i-090dbc33c50d882c6 --region ap-south-2 --output json`, __dirname);
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
    const inv = runOutput(`aws cloudfront create-invalidation --distribution-id E3I4T1HFZ2E6SJ --paths "/api/food/membership/*" "/admin/*" "/api/health" --region ap-south-2 --output json`, __dirname);
    const invObj = JSON.parse(inv);
    console.log('CloudFront invalidation created:', invObj.Invalidation ? invObj.Invalidation.Id : inv);
  } catch (invErr) {
    console.warn('CloudFront invalidation note:', invErr.message);
  }

  // Cleanup local tarballs
  fs.rmSync(tempDir, { recursive: true, force: true });
  console.log('\n=== DEPLOYMENT COMPLETED SUCCESSFULLY ===');
}

deploy().catch(err => {
  console.error('\nDeployment error:', err);
  process.exit(1);
});
