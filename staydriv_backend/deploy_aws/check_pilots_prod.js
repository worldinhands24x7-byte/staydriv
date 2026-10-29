const { execSync } = require('child_process');
const fs = require('fs');

function exec(cmd) {
  return execSync(cmd, {
    env: { ...process.env, PYTHONIOENCODING: 'utf-8', PYTHONUTF8: '1' },
    encoding: 'utf8'
  });
}

const instanceId = 'i-0a8cfb22fc40c7591';

const commands = [
  'cd /opt/staydriv',
  `node -e '
const mongoose = require("mongoose");
require("dotenv").config({ path: "/opt/staydriv/.env" });
mongoose.connect(process.env.MONGODB_URI || "mongodb://127.0.0.1:27017/staydriv").then(async () => {
  const res = await mongoose.connection.db.collection("users").deleteMany({ phone: "9999999999" });
  console.log("Deleted rogue test users:", res.deletedCount);
  process.exit(0);
}).catch(e => { console.error(e); process.exit(1); });
'`
];

const jsonParam = JSON.stringify({
  InstanceIds: [instanceId],
  DocumentName: 'AWS-RunShellScript',
  Parameters: { commands }
});

fs.writeFileSync('ssm_check_pilots.json', jsonParam);

const cmdId = exec(`aws ssm send-command --cli-input-json file://ssm_check_pilots.json --region ap-south-2 --query Command.CommandId --output text`).trim();
console.log(`Dispatched: ${cmdId}`);

let attempts = 0;
while (attempts < 20) {
  execSync('timeout /t 3 > nul 2>&1 || ping 127.0.0.1 -n 4 > nul');
  attempts++;
  try {
    const invStr = exec(`aws ssm get-command-invocation --command-id ${cmdId} --instance-id ${instanceId} --region ap-south-2 --output json`);
    const inv = JSON.parse(invStr);
    if (inv.Status === 'Success' || inv.Status === 'Failed' || inv.Status === 'Cancelled') {
      console.log('Status:', inv.Status);
      if (inv.StandardOutputContent) console.log(inv.StandardOutputContent);
      if (inv.StandardErrorContent) console.error(inv.StandardErrorContent);
      break;
    }
  } catch (e) {}
}
