const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const rootDir = __dirname;
const tempDir = path.join(rootDir, 'temp_pack_backend');

if (fs.existsSync(tempDir)) {
  fs.rmSync(tempDir, { recursive: true, force: true });
}
fs.mkdirSync(tempDir, { recursive: true });

// Models
const modelsDir = path.join(tempDir, 'models');
fs.mkdirSync(modelsDir, { recursive: true });
fs.readdirSync(path.join(rootDir, 'models')).forEach(f => {
  if (f.endsWith('.js')) {
    fs.copyFileSync(path.join(rootDir, 'models', f), path.join(modelsDir, f));
  }
});

// Routes
const routesDir = path.join(tempDir, 'routes');
fs.mkdirSync(routesDir, { recursive: true });
fs.readdirSync(path.join(rootDir, 'routes')).forEach(f => {
  if (f.endsWith('.js')) {
    fs.copyFileSync(path.join(rootDir, 'routes', f), path.join(routesDir, f));
  }
});

// Services
const servicesDir = path.join(tempDir, 'services');
fs.mkdirSync(servicesDir, { recursive: true });
fs.readdirSync(path.join(rootDir, 'services')).forEach(f => {
  if (f.endsWith('.js')) {
    fs.copyFileSync(path.join(rootDir, 'services', f), path.join(servicesDir, f));
  }
});

// Server.js
if (fs.existsSync(path.join(rootDir, 'server.js'))) {
  fs.copyFileSync(path.join(rootDir, 'server.js'), path.join(tempDir, 'server.js'));
}

const tarOutput = path.join(rootDir, 'staydriv_food_backend.tar.gz');
execSync(`tar -czf "${tarOutput}" .`, { cwd: tempDir, stdio: 'inherit' });
console.log(`Created: ${tarOutput} (${(fs.statSync(tarOutput).size / 1024).toFixed(1)} KB)`);

fs.rmSync(tempDir, { recursive: true, force: true });
console.log('Packaging complete!');
