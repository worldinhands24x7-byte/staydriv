const { execSync } = require('child_process');

try {
  const out = execSync('aws ssm get-command-invocation --command-id 6af39e52-7b33-4f1d-9179-5c92c1c3570c --instance-id i-0a572a3ce93094e82 --region ap-south-2 --output json', {
    env: { ...process.env, PYTHONUTF8: '1', PYTHONIOENCODING: 'utf-8' }
  });
  const data = JSON.parse(out);
  console.log('STATUS:', data.Status);
  console.log('STDOUT:', data.StandardOutputContent ? data.StandardOutputContent.slice(-400) : '');
  console.log('STDERR:', data.StandardErrorContent ? data.StandardErrorContent.slice(-400) : '');
} catch (e) {
  console.error('Error:', e.message);
}
