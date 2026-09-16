# StayDriv 🚗💨

**StayDriv** is a full-stack ride-booking and delivery platform featuring real-time passenger booking, driver-matching algorithms, live GPS tracking via WebSockets, in-app Razorpay payments, automated SMS/OTP verification, and an interactive real-time simulator.

---

## 🏗️ Project Architecture

```
staydriv/
├── staydriv_backend/            # Node.js + Express + Socket.IO Backend API
│   ├── server.js                # Main API & Socket server (Port 3000)
│   ├── db.js                    # Database connector (Supports MySQL & MongoDB)
│   ├── staydriv_mysql_schema.sql # Complete MySQL database schema & tables
│   ├── public/                  # Live simulator (combined.html), APK download portal, Web app
│   └── services/                # Tata SMS, Smartflo Calling & Razorpay services
├── staydriv_app/                # Flutter Cross-Platform Mobile Application (Android & Web)
│   └── lib/                     # Screens, State management, Ride booking & live tracking
├── Staydriv_Admin/              # React + Vite TypeScript Admin Management Dashboard
├── deploy_ec2.sh                # 1-Click Automated AWS EC2 Deployment Script (with MySQL)
├── AWS_EC2_DEPLOYMENT_GUIDE.md  # Detailed AWS EC2 Deployment Manual
└── README.md                    # Complete Project & Deployment Guide
```

---

## 🐬 MySQL Database Configuration

StayDriv includes full MySQL database support and a ready-to-run schema file: [`staydriv_backend/staydriv_mysql_schema.sql`](file:///d:/staydriv/staydriv_backend/staydriv_mysql_schema.sql).

### 1. The Production Environment File (`staydriv_backend/.env`)

Configure your `.env` file on your server:

```env
PORT=3000

# ==============================================================================
# Database Configuration (MySQL / AWS RDS MySQL)
# ==============================================================================
DB_TYPE=mysql
MYSQL_HOST=127.0.0.1
MYSQL_PORT=3306
MYSQL_USER=staydriv_user
MYSQL_PASSWORD=your_secure_password
MYSQL_DATABASE=staydriv_db

# (Optional fallback / dual-mode MongoDB connection)
MONGO_URI=mongodb://127.0.0.1:27017/staydriv

# ==============================================================================
# Razorpay Production Keys
# ==============================================================================
RAZORPAY_KEY_ID=rzp_live_xxxxxxxxxxxxxx
RAZORPAY_KEY_SECRET=your_production_secret

# ==============================================================================
# Google Maps API Key
# ==============================================================================
GOOGLE_MAPS_API_KEY=AIzaSyxxxxxxxxxxxxxxxxxxxxxxx

# ==============================================================================
# TATA Smartflo Calling Gateway
# ==============================================================================
TATA_SMARTFLO_JWT_TOKEN=your_jwt_token
TATA_SMARTFLO_BASE_URL=https://cloudphone.tatateleservices.com

# ==============================================================================
# TATA DLT SMS Gateway Configuration
# ==============================================================================
TATA_SMS_USER=your_sms_user
TATA_SMS_PASS=your_sms_pass
TATA_SMS_SENDER=SRL
TATA_SMS_PE_ID=your_pe_id
TATA_SMS_TEMPLATE_ID=your_template_id
TATA_SMS_GATEWAY_URL=https://ttbssmsgw.tatatel.co.in/campaignService/campaigns/qs
```

---

### 2. Setting Up MySQL on Your Server

#### A. If Using Local MySQL on EC2:
The automated script `./deploy_ec2.sh` installs MySQL automatically. To create your database and user:

```bash
# Open MySQL terminal
sudo mysql

# Run the following SQL commands:
CREATE DATABASE IF NOT EXISTS staydriv_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'staydriv_user'@'localhost' IDENTIFIED BY 'your_secure_password';
GRANT ALL PRIVILEGES ON staydriv_db.* TO 'staydriv_user'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

Then import the pre-built StayDriv schema:
```bash
mysql -u staydriv_user -p staydriv_db < /home/ubuntu/staydriv/staydriv_backend/staydriv_mysql_schema.sql
```

#### B. If Using AWS RDS MySQL:
1. In AWS RDS, create a MySQL 8.0 instance.
2. In your Security Group, allow inbound traffic on port `3306` from your EC2 Security Group.
3. Import the schema into RDS:
   ```bash
   mysql -h your-rds-endpoint.rds.amazonaws.com -u staydriv_user -p staydriv_db < staydriv_mysql_schema.sql
   ```
4. Set `MYSQL_HOST=your-rds-endpoint.rds.amazonaws.com` in `staydriv_backend/.env`.

---

## 📍 Where You Have to Change Configurations

When deploying to AWS EC2, you only need to modify **2 files**:

### 1. Backend Server Credentials (`staydriv_backend/.env`)
Set your MySQL database password, Razorpay keys, Google Maps API key, and Tata SMS credentials as shown in the `.env` section above.

### 2. Flutter Mobile App Backend URL (`staydriv_app/lib/core/network_config.dart`)
On your development machine, open [`staydriv_app/lib/core/network_config.dart`](file:///d:/staydriv/staydriv_app/lib/core/network_config.dart) at line 6:

```dart
// Line 6:
// Point to your EC2 domain or Elastic IP:
static const String defaultHttpsTunnelUrl = 'https://api.yourdomain.com';
// OR (if using EC2 IP directly without a domain):
// static const String defaultHttpsTunnelUrl = 'http://<YOUR-EC2-PUBLIC-IP>:3000';
```

Then build your production APK:
```bash
cd staydriv_app
flutter build apk --release
```
The resulting APK is ready at: `staydriv_app/build/app/outputs/flutter-apk/app-release.apk`.

---

## 🚀 AWS EC2 Step-by-Step Deployment Guide

### Step 1: Launch an AWS EC2 Instance
1. Open the [AWS EC2 Console](https://console.aws.amazon.com/ec2).
2. Click **Launch Instances**:
   - **Name**: `staydriv-backend`
   - **OS**: **Ubuntu 24.04 LTS** or **Ubuntu 22.04 LTS** (64-bit x86).
   - **Instance Type**: `t3.small` or `t3.medium` (Minimum 2 GB RAM recommended).
   - **Key Pair**: Download your `.pem` key (e.g., `staydriv.pem`).
   - **Storage**: 20 GB gp3 SSD.
3. In **Security Group Inbound Rules**, open:
   - **SSH (Port 22)**: Source `0.0.0.0/0` (or `My IP`)
   - **HTTP (Port 80)**: Source `0.0.0.0/0`
   - **HTTPS (Port 443)**: Source `0.0.0.0/0`
   - **Custom TCP (Port 3000)**: Source `0.0.0.0/0`
   - **MySQL (Port 3306)**: Only needed if accessing MySQL remotely
4. Click **Launch Instance** and allocate an **Elastic IP** so the IP remains static.

---

### Step 2: Connect to EC2 via SSH
```bash
ssh -i staydriv.pem ubuntu@<YOUR-EC2-PUBLIC-IP>
```

---

### Step 3: Clone Repository and Run 1-Click Setup
Inside your EC2 terminal:
```bash
# 1. Clone the project from GitHub
git clone https://github.com/worldinhands24x7-byte/staydriv.git
cd staydriv

# 2. Make deployment script executable and run
chmod +x deploy_ec2.sh
./deploy_ec2.sh
```

**What `deploy_ec2.sh` automatically does:**
- Installs **MySQL 8.0 Server** and imports [`staydriv_mysql_schema.sql`](file:///d:/staydriv/staydriv_backend/staydriv_mysql_schema.sql)
- Installs **Node.js 20 LTS** & **npm**
- Installs **PM2** process manager globally
- Installs all backend dependencies (including `mysql2`)
- Starts `server.js` on port 3000 under PM2 with auto-restart on crashes and system reboots

---

### Step 4: Configure Production `.env`
```bash
cd /home/ubuntu/staydriv/staydriv_backend
cp .env.example .env
nano .env
```
*(Enter your real database password, Razorpay keys, Google Maps key, and SMS credentials. Save with `Ctrl + O` and `Enter`, exit with `Ctrl + X`)*.

Restart the backend server with PM2:
```bash
pm2 restart staydriv-api
```

Verify backend health:
```bash
curl http://localhost:3000/api/health
# Output: {"status":"ok","timestamp":"...","uptime":...}
```

---

### Step 5: Setup Nginx Reverse Proxy & Free SSL (HTTPS)

1. Create Nginx site configuration:
   ```bash
   sudo nano /etc/nginx/sites-available/staydriv
   ```
2. Paste this configuration (replace `api.yourdomain.com` with your domain or EC2 Public IP):
   ```nginx
   server {
       listen 80;
       server_name api.yourdomain.com;

       client_max_body_size 30M;

       location / {
           proxy_pass http://127.0.0.1:3000;
           proxy_http_version 1.1;

           # WebSocket support for Socket.IO live driver tracking
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
3. Enable and test Nginx:
   ```bash
   sudo ln -sf /etc/nginx/sites-available/staydriv /etc/nginx/sites-enabled/
   sudo rm -f /etc/nginx/sites-enabled/default
   sudo nginx -t
   sudo systemctl restart nginx
   ```
4. *(If using a domain name)* Obtain a free SSL certificate:
   ```bash
   sudo apt install -y certbot python3-certbot-nginx
   sudo certbot --nginx -d api.yourdomain.com
   ```

---

### Step 6: Accessing Your Live Platform

- **Backend Health Check**: `https://api.yourdomain.com/api/health`
- **Live Simulator**: `https://api.yourdomain.com/combined.html`
- **Customer APK Download**: `https://api.yourdomain.com/staydriv.apk`

---

## 🛠️ Essential Maintenance Commands

| Action | Command |
| :--- | :--- |
| **Check server status** | `pm2 status` |
| **View real-time logs** | `pm2 logs staydriv-api` |
| **Restart backend** | `pm2 restart staydriv-api` |
| **Check MySQL status** | `sudo systemctl status mysql` |
| **Access MySQL CLI** | `sudo mysql -u staydriv_user -p staydriv_db` |
| **Restart Nginx** | `sudo systemctl restart nginx` |
| **Pull code updates** | `cd /home/ubuntu/staydriv && git pull origin main && pm2 restart staydriv-api` |

---

## 📄 License & Ownership
Developed for **World In Hands / StayDriv**.
