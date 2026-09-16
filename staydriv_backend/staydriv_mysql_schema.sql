-- ==============================================================================
-- StayDriv - Complete MySQL Database Schema (MySQL 8.0+ / AWS RDS MySQL)
-- ==============================================================================
-- To create the database and tables:
--   mysql -u root -p < staydriv_mysql_schema.sql
-- ==============================================================================

CREATE DATABASE IF NOT EXISTS staydriv_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE staydriv_db;

-- ------------------------------------------------------------------------------
-- 1. USERS & PILOTS TABLE
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uid VARCHAR(128) UNIQUE NOT NULL,
  name VARCHAR(255) DEFAULT '',
  phone VARCHAR(32) NOT NULL,
  role ENUM('customer', 'partner', 'admin') DEFAULT 'customer',
  vehicleType VARCHAR(64) DEFAULT NULL,
  online BOOLEAN DEFAULT FALSE,
  approved BOOLEAN DEFAULT FALSE,
  adminType VARCHAR(64) DEFAULT NULL,
  lat DOUBLE DEFAULT NULL,
  lng DOUBLE DEFAULT NULL,
  vehiclePlate VARCHAR(64) DEFAULT NULL,
  vehicleModelColor VARCHAR(128) DEFAULT NULL,
  photo TEXT DEFAULT NULL,
  aadhaarFront TEXT DEFAULT NULL,
  aadhaarBack TEXT DEFAULT NULL,
  licenseFront TEXT DEFAULT NULL,
  licenseBack TEXT DEFAULT NULL,
  rcFront TEXT DEFAULT NULL,
  rcBack TEXT DEFAULT NULL,
  fitness TEXT DEFAULT NULL,
  permit TEXT DEFAULT NULL,
  salary DECIMAL(10,2) DEFAULT 5000.00,
  pendingCancellationCharge DECIMAL(10,2) DEFAULT 0.00,
  lastActive DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  createdAt DATETIME DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_phone_role (phone, role),
  INDEX idx_online_role (role, online),
  INDEX idx_location (lat, lng)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------------------------
-- 2. BOOKINGS & RIDES TABLE
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bookings (
  id INT AUTO_INCREMENT PRIMARY KEY,
  bookingId VARCHAR(128) UNIQUE NOT NULL,
  pickup VARCHAR(500) DEFAULT '',
  `drop` VARCHAR(500) DEFAULT '',
  pickupLatLng JSON DEFAULT NULL,
  dropLatLng JSON DEFAULT NULL,
  vehicle VARCHAR(64) DEFAULT '',
  price VARCHAR(64) DEFAULT '',
  otp VARCHAR(16) DEFAULT '',
  status VARCHAR(64) DEFAULT 'searching',
  passengerId VARCHAR(128) DEFAULT '',
  passengerName VARCHAR(255) DEFAULT '',
  passengerPhone VARCHAR(32) DEFAULT '',
  driverId VARCHAR(128) DEFAULT NULL,
  driverName VARCHAR(255) DEFAULT NULL,
  vehiclePlate VARCHAR(64) DEFAULT NULL,
  vehicleModelColor VARCHAR(128) DEFAULT NULL,
  arrivedAt BIGINT DEFAULT NULL,
  assignedAt BIGINT DEFAULT NULL,
  declinedDrivers JSON DEFAULT NULL,
  serviceType VARCHAR(64) DEFAULT 'ride',
  title VARCHAR(255) DEFAULT '',
  pickupHouse VARCHAR(255) DEFAULT '',
  pickupContactName VARCHAR(255) DEFAULT '',
  pickupContactPhone VARCHAR(32) DEFAULT '',
  dropHouse VARCHAR(255) DEFAULT '',
  dropContactName VARCHAR(255) DEFAULT '',
  dropContactPhone VARCHAR(32) DEFAULT '',
  paymentOption VARCHAR(64) DEFAULT 'cash',
  scheduledDate VARCHAR(64) DEFAULT NULL,
  scheduledTimeSlot VARCHAR(64) DEFAULT NULL,
  waitingCharge DECIMAL(10,2) DEFAULT 0.00,
  distance VARCHAR(64) DEFAULT '',
  createdAt DATETIME DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_passenger (passengerId),
  INDEX idx_driver (driverId),
  INDEX idx_status (status),
  INDEX idx_createdAt (createdAt)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------------------------
-- 3. PAYMENTS TABLE (Razorpay)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS payments (
  id INT AUTO_INCREMENT PRIMARY KEY,
  orderId VARCHAR(128) UNIQUE NOT NULL,
  paymentId VARCHAR(128) DEFAULT NULL,
  signature VARCHAR(500) DEFAULT NULL,
  amount INT NOT NULL, -- Amount in Paise
  status ENUM('created', 'verified', 'failed') DEFAULT 'created',
  createdAt DATETIME DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_orderId (orderId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------------------------
-- 4. PAYOUTS TABLE
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS payouts (
  id INT AUTO_INCREMENT PRIMARY KEY,
  payoutId VARCHAR(128) UNIQUE NOT NULL,
  uid VARCHAR(128) NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  targetAccount VARCHAR(128) DEFAULT '',
  status ENUM('processed', 'failed') DEFAULT 'processed',
  createdAt DATETIME DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_uid (uid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------------------------
-- 5. OTP VERIFICATION TABLE
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS otps (
  id INT AUTO_INCREMENT PRIMARY KEY,
  mobile VARCHAR(32) NOT NULL,
  otp VARCHAR(16) NOT NULL,
  expireAt DATETIME NOT NULL,
  createdAt DATETIME DEFAULT CURRENT_TIMESTAMP,
  updatedAt DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_mobile (mobile),
  INDEX idx_expireAt (expireAt)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
