const { execSync } = require('child_process');
const fs = require('fs');

const script = `
const mongoose = require('mongoose');
mongoose.connect('mongodb://localhost:27017/staydriv').then(async () => {
  const User = mongoose.models.User || mongoose.model('User', new mongoose.Schema({}, { strict: false }));
  const u = await User.find({
    $or: [
      { phone: { $regex: '9490440281' } },
      { phoneNumber: { $regex: '9490440281' } },
      { uid: { $regex: '9490440281' } }
    ]
  }).lean();
  console.log('USER RECORDS FOR 9490440281:', JSON.stringify(u, null, 2));
  process.exit(0);
}).catch(e => {
  console.error(e);
  process.exit(1);
});
`;

const cmd = {
  commands: [
    'export PATH=$PATH:/usr/local/bin:/usr/bin:~/.nvm/versions/node/$(ls ~/.nvm/versions/node 2>/dev/null | tail -n 1)/bin',
    'export NODE_PATH=/opt/staydriv/node_modules',
    `cat << 'EOF' > /tmp/check_user.js\n${script}\nEOF`,
    'node /tmp/check_user.js'
  ]
};

fs.writeFileSync('ssm_check_user.json', JSON.stringify(cmd, null, 2));
const res = execSync('aws ssm send-command --instance-ids i-090dbc33c50d882c6 --document-name AWS-RunShellScript --parameters file://ssm_check_user.json --region ap-south-2 --output json').toString();
const cmdId = JSON.parse(res).Command.CommandId;
console.log('Sent SSM command:', cmdId);

let attempts = 0;
const poll = setInterval(() => {
  attempts++;
  try {
    const out = execSync(`aws ssm get-command-invocation --command-id ${cmdId} --instance-id i-090dbc33c50d882c6 --region ap-south-2 --output json`).toString();
    const j = JSON.parse(out);
    if (j.Status === 'Success' || j.Status === 'Failed' || attempts > 10) {
      clearInterval(poll);
      console.log('Status:', j.Status);
      console.log('STDOUT:\n', j.StandardOutputContent);
    }
  } catch (e) {}
}, 2000);
