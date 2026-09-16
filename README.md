# StayDriv 🚗💨

**StayDriv** is a full-stack ride booking and delivery platform featuring real-time passenger booking, driver matching, live GPS tracking, in-app Razorpay payments, automated SMS/OTP verification, and an interactive simulation and admin dashboard.

---

## 🏗️ Project Architecture

```
staydriv/
├── staydriv_backend/        # Node.js + Express + Socket.IO + MongoDB Backend API
│   ├── server.js            # Main API & Socket server (Port 3000)
│   ├── public/              # Live simulator (combined.html), APK download portal, Web app
│   └── services/            # SMS, Tata Smartflo calling & Razorpay services
├── staydriv_app/            # Flutter Cross-Platform Mobile Application (Android & Web)
│   └── lib/                 # Screens, State management, Ride booking & live tracking
├── Staydriv_Admin/          # React + Vite TypeScript Admin Management Dashboard
├── deploy_ec2.sh            # 1-Click Automated AWS EC2 Deployment Script
├── AWS_EC2_DEPLOYMENT_GUIDE.md # Complete Step-by-Step AWS EC2 Deployment Manual
└── README.md                # Project Overview & Quick Reference
```

---

## 🚀 AWS EC2 Deployment (Step-by-Step)

For a complete walkthrough with screenshots and troubleshooting, see the dedicated [AWS_EC2_DEPLOYMENT_GUIDE.md](file:///d:/staydriv/AWS_EC2_DEPLOYMENT_GUIDE.md).

### Quick 3-Step EC2 Launch

1. **Launch an EC2 Instance**:
   - OS: **Ubuntu 24.04 / 22.04 LTS** (Instance: `t3.small` or `t3.medium`).
   - Security Group Ports: Open **22** (SSH), **80** (HTTP), **443** (HTTPS), and **3000** (Custom TCP).

2. **Clone and Run Setup Script on EC2**:
   ```bash
   ssh -i your-key.pem ubuntu@<EC2-PUBLIC-IP>
   git clone https://github.com/worldinhands24x7-byte/staydriv.git
   cd staydriv
   chmod +x deploy_ec2.sh
   ./deploy_ec2.sh
   ```

3. **Configure Production Credentials**:
   ```bash
   cd staydriv/staydriv_backend
   cp .env.example .env
   nano .env # Enter your Razorpay, MongoDB, and SMS credentials
   pm2 restart staydriv-api
   ```

---

## 📍 Where You Have to Change Configurations

When moving from local development to AWS EC2, you only need to change **2 places**:

### 1. Backend Server Environment (`staydriv_backend/.env`)
Set production credentials:
- `MONGO_URI`: `mongodb://127.0.0.1:27017/staydriv` (or your MongoDB Atlas connection string)
- `RAZORPAY_KEY_ID` & `RAZORPAY_KEY_SECRET`: Production keys
- `GOOGLE_MAPS_API_KEY`: Production Google Maps API key
- `TATA_SMS_*`: Tata DLT SMS gateway credentials

### 2. Flutter Mobile App Backend URL (`staydriv_app/lib/core/network_config.dart`)
Line 6 in `staydriv_app/lib/core/network_config.dart`:
```dart
// Change from local/tunnel URL to your EC2 domain or Elastic IP:
static const String defaultHttpsTunnelUrl = 'https://api.yourdomain.com';
// OR:
// static const String defaultHttpsTunnelUrl = 'http://<YOUR-EC2-PUBLIC-IP>:3000';
```
Then compile the release APK:
```bash
cd staydriv_app
flutter build apk --release
```

---

## 🛠️ Local Development Quickstart

### Backend
```bash
cd staydriv_backend
npm install
node server.js # Starts on port 3000
```

### Mobile App (Flutter)
```bash
cd staydriv_app
flutter pub get
flutter run
```

### Admin Dashboard
```bash
cd Staydriv_Admin
npm install
npm run dev
```

---

## 📄 License & Team
Developed for World In Hands / StayDriv.
