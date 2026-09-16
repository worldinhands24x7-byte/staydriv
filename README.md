# StayDriv 🚗💨

**StayDriv** is a full-stack ride-booking and delivery platform featuring real-time passenger booking, driver-matching algorithms, live GPS tracking via WebSockets, in-app Razorpay payments, automated SMS/OTP verification, and an interactive real-time simulator.

---

## 🏗️ Project Architecture

```
staydriv/
├── staydriv_backend/        # Node.js + Express + Socket.IO + MongoDB Backend API
│   ├── server.js            # Main API & Socket server (Port 3000)
│   ├── public/              # Live simulator (combined.html), APK download portal, Web app
│   └── services/            # Tata SMS, Smartflo Calling & Razorpay services
├── staydriv_app/            # Flutter Cross-Platform Mobile Application (Android & Web)
│   └── lib/                 # Screens, State management, Ride booking & live tracking
├── Staydriv_Admin/          # React + Vite TypeScript Admin Management Dashboard
├── deploy_ec2.sh            # 1-Click Automated AWS EC2 Deployment Script
├── AWS_EC2_DEPLOYMENT_GUIDE.md # Detailed AWS EC2 Deployment Manual
└── README.md                # Complete Project & Deployment Guide
```

---

## 🗄️ Database Architecture: Which Database to Use?

### What Database Is Used?
The StayDriv backend (`server.js`, models, ride matching, and location queries) is **100% written and optimized for MongoDB (Mongoose)**.

### Can We Use MySQL or PostgreSQL?
- **For Deployment Right Now: Use MongoDB.**  
  All schemas (`User`, `Booking`, `Otp`), geospatial queries (`pickupLatLng`, `dropLatLng`), and real-time ride tracking are already programmed in MongoDB. Using MongoDB requires **0 code rewrites** and works out-of-the-box.
- **If You Choose a SQL Database in the Future: Choose PostgreSQL over MySQL.**  
  Ride-hailing apps (like Uber and Lyft) rely on **PostGIS** in PostgreSQL for fast distance calculations, radius searches for nearby drivers, and geofencing. MySQL's GIS engine is much more limited for real-time driver tracking. Migrating to PostgreSQL would require rewriting backend queries into SQL/Prisma.

### How to Set Up MongoDB for EC2 (2 Options):

#### Option A: Local MongoDB on the Same EC2 Instance (Recommended, $0 Cost)
Our deployment script automatically installs and runs MongoDB Community Edition on your EC2 instance.
In `staydriv_backend/.env`:
```env
MONGO_URI=mongodb://127.0.0.1:27017/staydriv
```

#### Option B: MongoDB Atlas (Cloud Managed)
If you prefer not to manage database storage on EC2:
1. Create a free cluster at [mongodb.com/atlas](https://www.mongodb.com/atlas).
2. Whitelist your EC2 IP (or `0.0.0.0/0`).
3. Set your connection string in `staydriv_backend/.env`:
```env
MONGO_URI=mongodb+srv://<username>:<password>@cluster0.xxxxx.mongodb.net/staydriv?retryWrites=true&w=majority
```

---

## 📍 Where You Have to Change Configurations

When deploying to AWS EC2, you only need to modify **2 files**:

### 1. Backend Server Credentials (`staydriv_backend/.env`)

On your EC2 instance, copy `.env.example` to `.env` and fill in your keys:

```bash
cd staydriv/staydriv_backend
cp .env.example .env
nano .env
```

Set your configuration:
```env
PORT=3000

# Database Connection (Local or Atlas)
MONGO_URI=mongodb://127.0.0.1:27017/staydriv

# Razorpay Production Keys
RAZORPAY_KEY_ID=rzp_live_xxxxxxxxxxxxxx
RAZORPAY_KEY_SECRET=your_production_secret

# Google Maps API Key
GOOGLE_MAPS_API_KEY=AIzaSyxxxxxxxxxxxxxxxxxxxxxxx

# TATA Smartflo Calling Gateway
TATA_SMARTFLO_JWT_TOKEN=your_jwt_token
TATA_SMARTFLO_BASE_URL=https://cloudphone.tatateleservices.com

# TATA DLT SMS Gateway Configuration
TATA_SMS_USER=your_sms_user
TATA_SMS_PASS=your_sms_pass
TATA_SMS_SENDER=SRL
TATA_SMS_PE_ID=your_pe_id
TATA_SMS_TEMPLATE_ID=your_template_id
TATA_SMS_GATEWAY_URL=https://ttbssmsgw.tatatel.co.in/campaignService/campaigns/qs
```

---

### 2. Mobile App Backend URL (`staydriv_app/lib/core/network_config.dart`)

On your **local development machine** where you build Flutter:

Open [`staydriv_app/lib/core/network_config.dart`](file:///d:/staydriv/staydriv_app/lib/core/network_config.dart) at line 6:

```dart
// REPLACE the temporary Cloudflare tunnel with your EC2 Domain or Public IP:
static const String defaultHttpsTunnelUrl = 'https://api.yourdomain.com';
// OR (if using EC2 Public IP directly without a domain name):
// static const String defaultHttpsTunnelUrl = 'http://<YOUR-EC2-PUBLIC-IP>:3000';
```

Then build your final production APK:
```bash
cd staydriv_app
flutter build apk --release
```

The APK will be generated at:
`staydriv_app/build/app/outputs/flutter-apk/app-release.apk`

---

## 🚀 AWS EC2 Step-by-Step Deployment Guide

### Step 1: Launch an AWS EC2 Instance
1. Go to the [AWS EC2 Console](https://console.aws.amazon.com/ec2).
2. Click **Launch Instances**:
   - **Name**: `staydriv-backend`
   - **OS**: **Ubuntu 24.04 LTS** or **Ubuntu 22.04 LTS** (64-bit x86).
   - **Instance Type**: `t3.small` or `t3.medium` (Minimum 2 GB RAM recommended).
   - **Key Pair**: Choose an existing `.pem` key or create a new one (e.g., `staydriv.pem`).
   - **Storage**: 20 GB gp3 SSD.
3. Configure **Security Group** Inbound Rules:
   - **SSH (Port 22)**: Source `My IP` (or `0.0.0.0/0`)
   - **HTTP (Port 80)**: Source `0.0.0.0/0`
   - **HTTPS (Port 443)**: Source `0.0.0.0/0`
   - **Custom TCP (Port 3000)**: Source `0.0.0.0/0`
4. Click **Launch Instance**.
5. *(Recommended)* Under **EC2** → **Elastic IPs**, allocate an Elastic IP and associate it with this instance so the public IP never changes across reboots.

---

### Step 2: Connect to EC2 via SSH
In PowerShell or Terminal:
```bash
# Set key permissions (Linux/Mac only; Windows users can skip this chmod line)
chmod 400 staydriv.pem

# SSH into the server
ssh -i staydriv.pem ubuntu@<YOUR-EC2-PUBLIC-IP>
```

---

### Step 3: Clone Repository and Run 1-Click Setup
Inside your EC2 terminal:
```bash
# 1. Clone the project from GitHub
git clone https://github.com/worldinhands24x7-byte/staydriv.git
cd staydriv

# 2. Make script executable and run
chmod +x deploy_ec2.sh
./deploy_ec2.sh
```

**What `deploy_ec2.sh` automatically installs and configures:**
- Updates system packages
- Installs **Node.js 20 LTS** & **npm**
- Installs **PM2** process manager globally
- Installs and starts **MongoDB Community Edition 7.0**
- Installs all npm backend dependencies
- Starts `server.js` on port 3000 with auto-restart on crashes and system reboots

---

### Step 4: Configure Production `.env`
```bash
cd /home/ubuntu/staydriv/staydriv_backend
cp .env.example .env
nano .env # Enter your real Razorpay, Google Maps, and SMS credentials
```
*(Press `Ctrl + O` and `Enter` to save, `Ctrl + X` to exit)*.

Restart the backend to load new credentials:
```bash
pm2 restart staydriv-api
```

Verify backend health:
```bash
curl http://localhost:3000/api/health
# Response: {"status":"ok","timestamp":"...","uptime":...}
```

---

### Step 5: Setup Nginx Reverse Proxy & Free SSL (HTTPS)

This connects standard HTTP (Port 80) and HTTPS (Port 443) to your Node.js backend on Port 3000 with WebSocket support for live driver tracking.

1. Create the Nginx configuration:
   ```bash
   sudo nano /etc/nginx/sites-available/staydriv
   ```
2. Paste the configuration below (replace `api.yourdomain.com` with your domain or EC2 Public IP):
   ```nginx
   server {
       listen 80;
       server_name api.yourdomain.com; # Or your EC2 Public IP

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

### Step 6: Accessing Your Application

Once deployed, access your live services:
- **Backend Health Check**: `https://api.yourdomain.com/api/health`
- **Live Simulator**: `https://api.yourdomain.com/combined.html`
- **Customer APK Download**: `https://api.yourdomain.com/staydriv.apk`

---

## 🛠️ Essential PM2 & Server Commands

| Action | Command |
| :--- | :--- |
| **Check server status** | `pm2 status` |
| **View real-time logs** | `pm2 logs staydriv-api` |
| **Restart backend** | `pm2 restart staydriv-api` |
| **Stop backend** | `pm2 stop staydriv-api` |
| **Check MongoDB status** | `sudo systemctl status mongod` |
| **Restart Nginx** | `sudo systemctl restart nginx` |
| **Deploy code updates** | `cd /home/ubuntu/staydriv && git pull origin main && pm2 restart staydriv-api` |

---

## 📄 License & Ownership
Developed for **World In Hands / StayDriv**.
