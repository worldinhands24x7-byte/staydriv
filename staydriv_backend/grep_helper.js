const fs = require('fs');
const content = fs.readFileSync('d:/stitch_staydriv_unified_mobility_platform/staydriv_app/lib/features/dashboard/screens/home_screen.dart', 'utf8');

const lines = content.split('\n');
lines.forEach((line, idx) => {
  if (line.toLowerCase().includes('approved')) {
    console.log(`${idx + 1}: ${line.trim()}`);
  }
});
