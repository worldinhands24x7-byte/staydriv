const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const localtunnel = require('localtunnel');

const PORT = 3000;
const PUBLIC_DIR = path.join(__dirname, 'public');
const CONFIG_FILE = path.join(PUBLIC_DIR, 'active_tunnel.json');

function saveActiveUrl(url) {
  try {
    if (!fs.existsSync(PUBLIC_DIR)) {
      fs.mkdirSync(PUBLIC_DIR, { recursive: true });
    }
    const data = {
      url: url,
      timestamp: new Date().toISOString(),
      status: 'active'
    };
    fs.writeFileSync(CONFIG_FILE, JSON.stringify(data, null, 2));
    console.log(`[TUNNEL] Saved active URL to ${CONFIG_FILE}`);
  } catch (e) {
    console.error('[TUNNEL] Error saving active URL:', e.message);
  }
}

function startCloudflared() {
  console.log('[TUNNEL] Launching Cloudflare Tunnel for 4G/5G mobile cellular reachability...');
  const cloudflaredBin = path.join(__dirname, 'cloudflared.exe');
  
  if (!fs.existsSync(cloudflaredBin)) {
    console.log('[TUNNEL] cloudflared.exe not found, falling back to localtunnel...');
    return startLocaltunnel();
  }

  const child = spawn(cloudflaredBin, ['tunnel', '--url', `http://localhost:${PORT}`]);
  let capturedUrl = null;

  child.stderr.on('data', (data) => {
    const output = data.toString();
    console.log('[cloudflared]', output.trim());
    const match = output.match(/https:\/\/[a-zA-Z0-9-]+\.trycloudflare\.com/);
    if (match && !capturedUrl) {
      capturedUrl = match[0];
      console.log('\n==================================================');
      console.log(`[TUNNEL ACTIVE] 5G Cellular URL: ${capturedUrl}`);
      console.log('==================================================\n');
      saveActiveUrl(capturedUrl);
    }
  });

  child.on('close', (code) => {
    console.log(`[cloudflared] Process exited with code ${code}. Restarting in 5 seconds...`);
    setTimeout(startCloudflared, 5000);
  });
}

function startLocaltunnel() {
  console.log('[TUNNEL] Starting localtunnel fallback...');
  localtunnel({ port: PORT }).then((tunnel) => {
    console.log(`[TUNNEL ACTIVE] localtunnel URL: ${tunnel.url}`);
    saveActiveUrl(tunnel.url);
    tunnel.on('close', () => {
      console.log('[localtunnel] Closed. Restarting in 5 seconds...');
      setTimeout(startLocaltunnel, 5000);
    });
  }).catch((err) => {
    console.error('[localtunnel] Error:', err.message);
    setTimeout(startLocaltunnel, 10000);
  });
}

startCloudflared();
