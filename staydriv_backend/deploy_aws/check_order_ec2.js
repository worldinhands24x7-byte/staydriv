const { execSync } = require('child_process');
const fs = require('fs');

const ssmDoc = JSON.stringify({
  InstanceIds: ['i-0f8915ff46459c3b5'],
  DocumentName: 'AWS-RunShellScript',
  Parameters: {
    commands: [
      'cd /opt/staydriv && node -e "const mongoose = require(\'mongoose\'); require(\'dotenv\').config(); mongoose.connect(process.env.MONGODB_URI || \'mongodb://127.0.0.1:27017/staydriv\').then(async () => { const o = await mongoose.connection.db.collection(\'foodorders\').find().sort({createdAt:-1}).limit(3).toArray(); console.log(\'RECENT_ORDERS:\', JSON.stringify(o, null, 2)); const r = await mongoose.connection.db.collection(\'restaurants\').find({}).toArray(); console.log(\'RESTAURANTS:\', r.map(x => ({id: x._id, restaurantId: x.restaurantId, name: x.name, phone: x.phone}))); process.exit(0); });"'
    ]
  }
});
fs.writeFileSync('check_order.json', ssmDoc);
const cmdId = execSync('aws ssm send-command --cli-input-json file://check_order.json --region ap-south-2 --query Command.CommandId --output text', { 
  encoding: 'utf8',
  env: { ...process.env, PYTHONIOENCODING: 'utf-8', PYTHONUTF8: '1' }
}).trim();
console.log('Dispatched:', cmdId);
let attempts = 0;
while(attempts < 20) {
  execSync('timeout /t 3 > nul 2>&1 || ping 127.0.0.1 -n 4 > nul');
  attempts++;
  try {
    const invStr = execSync(`aws ssm get-command-invocation --command-id ${cmdId} --instance-id i-0f8915ff46459c3b5 --region ap-south-2 --output json`, { 
      encoding: 'utf8',
      env: { ...process.env, PYTHONIOENCODING: 'utf-8', PYTHONUTF8: '1' }
    });
    const inv = JSON.parse(invStr);
    if (inv.Status === 'Success' || inv.Status === 'Failed') {
      console.log('Status:', inv.Status);
      console.log('STDOUT:\n', inv.StandardOutputContent);
      console.log('STDERR:\n', inv.StandardErrorContent);
      break;
    }
  } catch(e) {}
}
