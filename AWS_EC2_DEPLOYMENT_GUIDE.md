# StayDriv - AWS EC2 Production Deployment Guide

This guide provides a zero-error, step-by-step walkthrough to deploy the **StayDriv** backend, database, and live simulator on an **AWS EC2 (Ubuntu)** instance.

---

## 📋 Table of Contents
1. [Prerequisites & EC2 Instance Setup](#1-prerequisites--ec2-instance-setup)
2. [Security Group Configuration (Port Opening)](#2-security-group-configuration)
3. [Connect to EC2 and Clone Project](#3-connect-to-ec2-and-clone-project)
4. [Where You Have to Change Configurations](#4-where-you-have-to-change-configurations)
5. [Automated One-Command Deployment](#5-automated-one-command-deployment)
6. [Manual Step-by-Step Commands](#6-manual-step-by-step-commands)
7. [Nginx Reverse Proxy & SSL (HTTPS) Setup](#7-nginx-reverse-proxy--ssl-setup)
8. [Connecting Flutter App to EC2](#8-connecting-flutter-app-to-ec2)
9. [Maintenance & Useful Commands](#9-maintenance--useful-commands)

---

## 1. Prerequisites & EC2 Instance Setup

1. Log into your **[AWS Management Console](https://console.aws.amazon.com/)**.
2. Navigate to **EC2** → **Launch Instances**.
3. Configure the instance:
   - **Name**: `staydriv-production`
   - **OS / AMI**: **Ubuntu 24.04 LTS** or **Ubuntu 22.04 LTS (64-bit x86)**
   - **Instance Type**: `t3.small` or `t3.medium` (recommended: minimum 2 GB RAM for Node.js + MongoDB + Socket.IO)
   - **Key Pair**: Create or choose an existing `.pem` key pair (e.g., `staydriv-key.pem`) and download it.
   - **Storage**: Minimum 20 GB gp3 SSD.
4. Click **Launch Instance**.
5. Once launched, allocate and associate an **Elastic IP** to your instance so the public IP remains permanent across reboots.

---

## 2. Security Group Configuration

Under **EC2** → **Security Groups** → Edit **Inbound Rules** for your instance:

| Type | Protocol | Port Range | Source | Description |
| :--- | :--- | :--- | :--- | :--- |
| **SSH** | TCP | `22` | `My IP` (or `0.0.0.0/0`) | Secure terminal access |
| **HTTP** | TCP | `80` | `0.0.0.0/0` | Web traffic / Simulator / Certbot |
| **HTTPS** | TCP | `443` | `0.0.0.0/0` | Secure SSL traffic for Mobile App & API |
| **Custom TCP** | TCP | `3000` | `0.0.0.0/0` | (Optional) Direct backend port testing |

---

## 3. Connect to EC2 and Clone Project

Open PowerShell or your terminal on your computer:

```bash
# 1. Set key permission (Linux / Mac)
chmod 400 staydriv-key.pem

# 2. SSH into your EC2 instance (replace with your Elastic IP)
ssh -i staydriv-key.pem ubuntu@<YOUR-EC2-PUBLIC-IP>
```

Once connected inside the EC2 terminal, clone your GitHub repository:

```bash
# Clone to /var/www/staydriv or home directory
git clone https://github.com/worldinhands24x7-byte/staydriv.git
cd staydriv
```

---

## 4. Where You Have to Change Configurations

There are only **two files** you need to customize for your AWS environment:

### Change 1: Backend Environment Variables (`staydriv_backend/.env`)

On the EC2 server, navigate to `staydriv_backend` and create your production `.env` file:

```bash
cd /home/ubuntu/staydriv/staydriv_backend
cp .env.example .env
nano .env
```

Set the values for your production environment:

```env
PORT=3000

# MongoDB: Use local MongoDB or MongoDB Atlas connection string
MONGO_URI=mongodb://127.0.0.1:27017/staydriv

# Payment Gateway
RAZORPAY_KEY_ID=rzp_live_xxxxxxxxxxxxxx
RAZORPAY_KEY_SECRET=your_production_secret

# Google Maps API Key
GOOGLE_MAPS_API_KEY=AIzaSyxxxxxxxxxxxxxxxxxxxxxxx

# TATA Smartflo Calling Gateway
TATA_SMARTFLO_JWT_TOKEN=your_jwt_token_here
TATA_SMARTFLO_BASE_URL=https://cloudphone.tatateleservices.com

# TATA DLT SMS Gateway Configuration
TATA_SMS_USER=your_sms_user
TATA_SMS_PASS=your_sms_pass
TATA_SMS_SENDER=SRL
TATA_SMS_PE_ID=your_pe_id
TATA_SMS_TEMPLATE_ID=your_template_id
TATA_SMS_GATEWAY_URL=https://ttbssmsgw.tatatel.co.in/campaignService/campaigns/qs
```

*(Press `Ctrl + O` then `Enter` to save, and `Ctrl + X` to exit `nano`)*.

---

### Change 2: Mobile App Backend URL (`staydriv_app/lib/core/network_config.dart`)

On your **local development machine** (where you build Flutter):

Open [`staydriv_app/lib/core/network_config.dart`](file:///d:/staydriv/staydriv_app/lib/core/network_config.dart):

```dart
// Line 6:
// REPLACE the Cloudflare tunnel with your EC2 Domain or Public IP:
static const String defaultHttpsTunnelUrl = 'https://api.yourdomain.com';
// OR (if without domain initially):
// static const String defaultHttpsTunnelUrl = 'http://<YOUR-EC2-PUBLIC-IP>:3000';
```

Then rebuild the APK:
```bash
cd d:\staydriv\staydriv_app
flutter build apk --release
```

---

## 5. Automated One-Command Deployment

We included an automated deployment script `deploy_ec2.sh` in the repository root. To run it on EC2:

```bash
cd /home/ubuntu/staydriv
chmod +x deploy_ec2.sh
./deploy_ec2.sh
```

This single command automatically:
1. Updates Ubuntu packages.
2. Installs **Node.js 20 LTS** and **npm**.
3. Installs **PM2** process manager globally.
4. Installs and starts **MongoDB Community Edition**.
5. Installs all npm dependencies inside `staydriv_backend`.
6. Launches the server under PM2 with auto-restart on crashes or system reboots.

---

## 6. Manual Step-by-Step Commands

If you prefer to run the setup commands manually, execute the following sequentially:

### Step 6.1: Install Node.js 20 LTS & Build Tools
```bash
sudo apt update && sudo apt upgrade -y
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs build-essential nginx
sudo npm install -g pm2
```

### Step 6.2: Install and Start MongoDB
```bash
sudo apt install -y gnupg curl
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
   sudo gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor --yes
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/7.0 multiverse" | \
   sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
sudo apt update
sudo apt install -y mongodb-org
sudo systemctl enable mongod
sudo systemctl start mongod
```

### Step 6.3: Install Backend Dependencies & Start Server
```bash
cd /home/ubuntu/staydriv/staydriv_backend
npm install --production

# Start with PM2
pm2 start server.js --name "staydriv-api" --time
pm2 save
pm2 startup
```

Verify backend is running:
```bash
curl http://localhost:3000/api/health
# Output: {"status":"ok","timestamp":"...","uptime":...}
```

---

## 7. Nginx Reverse Proxy & SSL Setup

Using Nginx forwards traffic from standard HTTP (Port 80) and HTTPS (Port 443) to your Node.js application on port 3000, supporting WebSockets (Socket.IO) and file uploads.

### Step 7.1: Create Nginx Configuration
```bash
sudo nano /etc/nginx/sites-available/staydriv
```

Paste the following configuration (replace `api.yourdomain.com` with your actual domain or EC2 Public IP):

```nginx
server {
    listen 80;
    server_name api.yourdomain.com; # Or your EC2 Public IP

    # Allow photo / document uploads up to 30MB
    client_max_body_size 30M;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;

        # WebSocket support (Required for Socket.IO live driver tracking)
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Step 7.2: Enable Site and Restart Nginx
```bash
sudo ln -sf /etc/nginx/sites-available/staydriv /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx
```

### Step 7.3: Install Free HTTPS Certificate (Certbot)
If you have pointed your domain name (e.g., `api.yourdomain.com`) to your EC2 Elastic IP:

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d api.yourdomain.com
```
Certbot automatically secures your server and configures auto-renewal!

---

## 8. Connecting Flutter App to EC2

After your EC2 server is live:
1. Open [`staydriv_app/lib/core/network_config.dart`](file:///d:/staydriv/staydriv_app/lib/core/network_config.dart)
2. Update `defaultHttpsTunnelUrl`:
   ```dart
   static const String defaultHttpsTunnelUrl = 'https://api.yourdomain.com';
   ```
3. Build the final Android APK:
   ```bash
   flutter clean
   flutter pub get
   flutter build apk --release
   ```
4. Copy the compiled APK (`build/app/outputs/flutter-apk/app-release.apk`) to `staydriv_backend/public/staydriv.apk` on your EC2 server so users can download it directly from your web portal at `https://api.yourdomain.com/staydriv.apk`.

---

## 9. Maintenance & Useful Commands

| Task | Command |
| :--- | :--- |
| **Check PM2 status** | `pm2 status` |
| **View live backend logs** | `pm2 logs staydriv-api` |
| **Restart backend server** | `pm2 restart staydriv-api` |
| **Stop backend server** | `pm2 stop staydriv-api` |
| **Check MongoDB status** | `sudo systemctl status mongod` |
| **Check Nginx status** | `sudo systemctl status nginx` |
| **Update code from GitHub** | `git pull origin main && pm2 restart staydriv-api` |
