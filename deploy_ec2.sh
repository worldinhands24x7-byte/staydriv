#!/bin/bash
# ==============================================================================
# StayDriv - AWS EC2 Automated Deployment Script (Ubuntu 22.04 / 24.04 LTS)
# ==============================================================================
# Usage:
#   chmod +x deploy_ec2.sh
#   ./deploy_ec2.sh
# ==============================================================================

set -e

echo "🚀 Starting StayDriv AWS EC2 Production Setup..."

# 1. Update system packages
echo "📦 [1/6] Updating system packages..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git build-essential nginx ufw gnupg

# 2. Install Node.js 20 LTS
echo "🟢 [2/6] Installing Node.js 20 LTS..."
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt install -y nodejs
fi
echo "Node version: $(node -v)"
echo "NPM version: $(npm -v)"

# 3. Install PM2 process manager
echo "⚡ [3/6] Installing PM2..."
sudo npm install -g pm2

# 4. Install MongoDB Community Edition (if not using remote Atlas)
echo "🍃 [4/6] Setting up MongoDB..."
if ! command -v mongod &> /dev/null; then
    curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
       sudo gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor --yes
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/7.0 multiverse" | \
       sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
    sudo apt update
    sudo apt install -y mongodb-org || echo "⚠️ MongoDB install via repo skipped, will verify local service"
    sudo systemctl daemon-reload
    sudo systemctl enable mongod --now || echo "Notice: Ensure MongoDB or Atlas is configured."
fi

# 5. Setup Backend Dependencies
echo "📂 [5/6] Setting up staydriv_backend..."
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
BACKEND_DIR="$SCRIPT_DIR/staydriv_backend"

if [ ! -d "$BACKEND_DIR" ]; then
    echo "❌ Error: staydriv_backend directory not found at $BACKEND_DIR"
    exit 1
fi

cd "$BACKEND_DIR"

if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        echo "📝 Creating .env from .env.example..."
        cp .env.example .env
        echo "⚠️ IMPORTANT: Edit $BACKEND_DIR/.env with your production credentials!"
    fi
fi

echo "📦 Installing npm dependencies..."
npm install --production

# 6. Start / Restart application with PM2
echo "🔄 [6/6] Launching backend server with PM2..."
pm2 delete staydriv-api 2>/dev/null || true
pm2 start server.js --name "staydriv-api" --time
pm2 save
pm2 startup systemd -u $USER --hp $HOME 2>/dev/null || true

echo "=============================================================================="
echo "✅ StayDriv Backend is successfully running with PM2!"
echo "   Status: pm2 status"
echo "   Logs:   pm2 logs staydriv-api"
echo "=============================================================================="
