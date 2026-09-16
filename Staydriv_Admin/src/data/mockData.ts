// StayDriv Admin Panel Simulation Pre-populated Dataset

export interface Customer {
  uid: string;
  name: string;
  email: string;
  phone: string;
  status: 'active' | 'blocked';
  walletBalance: number;
  createdAt: string;
}

export interface Partner {
  uid: string;
  name: string;
  email: string;
  phone: string;
  vehicleType: 'Bike' | 'Auto' | 'Car' | 'Mini Truck' | 'Truck';
  vehiclePlate: string;
  vehicleModelColor: string;
  status: 'pending' | 'approved' | 'rejected' | 'suspended';
  rating: number;
  earnings: number;
  totalTrips: number;
  totalDeliveries: number;
  documents: {
    aadhaarFront: string;
    aadhaarBack: string;
    drivingLicenseFront: string;
    drivingLicenseBack: string;
    rcFront: string;
    rcBack: string;
    profilePhoto: string;
    fitness?: string;
    permit?: string;
  };
  walletBalance: number;
  createdAt: string;
}

export interface Booking {
  bookingId: string;
  customerId: string;
  customerName: string;
  pickup: string;
  drop: string;
  pickupLatLng: { lat: number; lng: number };
  dropLatLng: { lat: number; lng: number };
  vehicle: 'Bike' | 'Auto' | 'Car';
  price: string;
  otp: string;
  status: 'requested' | 'accepted' | 'arriving' | 'started' | 'completed' | 'cancelled';
  driverId: string | null;
  driverName: string | null;
  vehiclePlate: string | null;
  vehicleModelColor: string | null;
  paymentOption: 'UPI' | 'Card' | 'Wallet' | 'Cash';
  createdAt: string;
}

export interface Delivery {
  bookingId: string;
  customerId: string;
  customerName: string;
  pickup: string;
  drop: string;
  pickupLatLng: { lat: number; lng: number };
  dropLatLng: { lat: number; lng: number };
  vehicle: 'Bike' | 'Auto' | 'Mini Truck' | 'Truck';
  price: string;
  otp: string;
  status: 'requested' | 'accepted' | 'arriving' | 'started' | 'completed' | 'cancelled';
  driverId: string | null;
  driverName: string | null;
  vehiclePlate: string | null;
  vehicleModelColor: string | null;
  paymentOption: 'UPI' | 'Card' | 'Wallet' | 'Cash';
  goodsType: string;
  weight: string;
  pickupContactName: string;
  pickupContactPhone: string;
  dropContactName: string;
  dropContactPhone: string;
  createdAt: string;
}

export interface Payment {
  transactionId: string;
  bookingId?: string;
  amount: number;
  paymentMethod: 'UPI' | 'Card' | 'Wallet' | 'Cash';
  status: 'pending' | 'completed' | 'failed';
  type: 'ride_fare' | 'delivery_fare' | 'commission' | 'withdrawal';
  userId: string;
  userRole: 'customer' | 'partner';
  createdAt: string;
}

export interface SupportTicket {
  ticketId: string;
  creatorId: string;
  creatorName: string;
  creatorRole: 'customer' | 'partner';
  subject: string;
  category: 'ride_issue' | 'payment_issue' | 'app_bug' | 'safety';
  message: string;
  status: 'open' | 'assigned' | 'resolved';
  assignedTo: string | null;
  chatHistory: Array<{
    senderId: string;
    senderName: string;
    message: string;
    timestamp: string;
  }>;
  createdAt: string;
}

export interface PromoCode {
  code: string;
  discountPercentage: number;
  maxDiscount: number;
  minBookingValue: number;
  expiryDate: string;
  status: 'active' | 'inactive';
  usageCount: number;
}

export interface AdminUser {
  uid: string;
  email: string;
  name: string;
  role: 'super_admin' | 'admin' | 'support' | 'finance';
  status: 'active' | 'inactive';
  createdAt: string;
}

export interface AuditLog {
  logId: string;
  adminId: string;
  adminEmail: string;
  action: string;
  details: string;
  ipAddress: string;
  timestamp: string;
}

export const mockAdminUsers: AdminUser[] = [
  { uid: 'adm_0', email: 'staydriv@gmail.com', name: 'StayDriv Admin', role: 'super_admin', status: 'active', createdAt: '2026-01-01T10:00:00Z' },
  { uid: 'adm_1', email: 'super@staydriv.com', name: 'Alok Mishra', role: 'super_admin', status: 'active', createdAt: '2026-01-01T10:00:00Z' },
  { uid: 'adm_2', email: 'ops@staydriv.com', name: 'Varun Sharma', role: 'admin', status: 'active', createdAt: '2026-02-15T11:30:00Z' },
  { uid: 'adm_3', email: 'support@staydriv.com', name: 'Neha Patil', role: 'support', status: 'active', createdAt: '2026-03-01T09:00:00Z' },
  { uid: 'adm_4', email: 'finance@staydriv.com', name: 'Rohan Gupta', role: 'finance', status: 'active', createdAt: '2026-03-10T14:00:00Z' },
];

export const mockCustomers: Customer[] = [
  { uid: 'cust_1', name: 'Aarav Mehta', email: 'aarav.mehta@gmail.com', phone: '9876543210', status: 'active', walletBalance: 450.50, createdAt: '2026-04-01T08:23:11Z' },
  { uid: 'cust_2', name: 'Ananya Roy', email: 'ananya.roy@yahoo.com', phone: '8123456789', status: 'active', walletBalance: 120.00, createdAt: '2026-04-05T12:44:50Z' },
  { uid: 'cust_3', name: 'Kabir Singh', email: 'kabir.singh@gmail.com', phone: '7012345678', status: 'blocked', walletBalance: 0.00, createdAt: '2026-04-10T15:10:00Z' },
  { uid: 'cust_4', name: 'Diya Iyer', email: 'diya.iyer@outlook.com', phone: '9001122334', status: 'active', walletBalance: 1820.00, createdAt: '2026-04-20T10:05:32Z' },
  { uid: 'cust_5', name: 'Vivaan Kapoor', email: 'vivaan.k@gmail.com', phone: '9887766554', status: 'active', walletBalance: 75.00, createdAt: '2026-05-02T16:50:18Z' },
];

export const mockPartners: Partner[] = [
  {
    uid: 'drv_1',
    name: 'Ramesh Kumar',
    email: 'ramesh.drv@gmail.com',
    phone: '7790123456',
    vehicleType: 'Car',
    vehiclePlate: 'TS 09 SD 1234',
    vehicleModelColor: 'Black Hyundai Verna',
    status: 'approved',
    rating: 4.8,
    earnings: 28500.00,
    totalTrips: 142,
    totalDeliveries: 0,
    documents: {
      profilePhoto: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150',
      aadhaarFront: 'Aadhaar Card Front (Verified)',
      aadhaarBack: 'Aadhaar Card Back (Verified)',
      drivingLicenseFront: 'Driving License Front (Verified)',
      drivingLicenseBack: 'Driving License Back (Verified)',
      rcFront: 'RC Front (Verified)',
      rcBack: 'RC Back (Verified)',
      fitness: 'Fitness Certificate (Verified)',
      permit: 'Commercial Permit (Verified)',
    },
    walletBalance: 2450.00,
    createdAt: '2026-04-02T09:15:00Z',
  },
  {
    uid: 'drv_2',
    name: 'Suresh Raina',
    email: 'suresh.raina@yahoo.com',
    phone: '8890123457',
    vehicleType: 'Bike',
    vehiclePlate: 'AP 39 BK 9876',
    vehicleModelColor: 'Red Honda Shine',
    status: 'approved',
    rating: 4.5,
    earnings: 14200.00,
    totalTrips: 98,
    totalDeliveries: 45,
    documents: {
      profilePhoto: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150',
      aadhaarFront: 'Aadhaar Card Front (Verified)',
      aadhaarBack: 'Aadhaar Card Back (Verified)',
      drivingLicenseFront: 'Driving License Front (Verified)',
      drivingLicenseBack: 'Driving License Back (Verified)',
      rcFront: 'RC Front (Verified)',
      rcBack: 'RC Back (Verified)',
    },
    walletBalance: 120.00,
    createdAt: '2026-04-10T11:00:00Z',
  },
  {
    uid: 'drv_3',
    name: 'Manpreet Singh',
    email: 'manpreet.truck@outlook.com',
    phone: '9910123458',
    vehicleType: 'Mini Truck',
    vehiclePlate: 'HR 55 TR 4321',
    vehicleModelColor: 'White Tata Ace',
    status: 'pending',
    rating: 0.0,
    earnings: 0.00,
    totalTrips: 0,
    totalDeliveries: 0,
    documents: {
      profilePhoto: 'https://images.unsplash.com/photo-1628157582853-a796fa650a6a?w=150',
      aadhaarFront: 'Aadhaar Card Front Image File',
      aadhaarBack: 'Aadhaar Card Back Image File',
      drivingLicenseFront: 'Driving License Front Image File',
      drivingLicenseBack: 'Driving License Back Image File',
      rcFront: 'Vehicle RC Book Front Page',
      rcBack: 'Vehicle RC Book Back Page',
      fitness: 'Vehicle Fitness Cert File',
      permit: 'National Carriage Permit',
    },
    walletBalance: 0.00,
    createdAt: '2026-05-28T14:30:00Z',
  },
  {
    uid: 'drv_4',
    name: 'Abdul Rehman',
    email: 'abdul.rickshaw@gmail.com',
    phone: '9812345679',
    vehicleType: 'Auto',
    vehiclePlate: 'DL 1R AB 5678',
    vehicleModelColor: 'Green-Yellow Piaggio Ape',
    status: 'suspended',
    rating: 3.9,
    earnings: 9800.00,
    totalTrips: 76,
    totalDeliveries: 12,
    documents: {
      profilePhoto: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=150',
      aadhaarFront: 'Aadhaar Front File',
      aadhaarBack: 'Aadhaar Back File',
      drivingLicenseFront: 'DL Front File',
      drivingLicenseBack: 'DL Back File',
      rcFront: 'RC Front File',
      rcBack: 'RC Back File',
    },
    walletBalance: -450.00,
    createdAt: '2026-04-15T15:20:00Z',
  },
];

export const mockBookings: Booking[] = [
  {
    bookingId: 'BK_1001',
    customerId: 'cust_1',
    customerName: 'Aarav Mehta',
    pickup: 'Kukatpally, Hyderabad',
    drop: 'Miyapur Metro Station, Hyderabad',
    pickupLatLng: { lat: 17.4855, lng: 78.3976 },
    dropLatLng: { lat: 17.4968, lng: 78.3820 },
    vehicle: 'Car',
    price: '₹350.00',
    otp: '4921',
    status: 'completed',
    driverId: 'drv_1',
    driverName: 'Ramesh Kumar',
    vehiclePlate: 'TS 09 SD 1234',
    vehicleModelColor: 'Black Hyundai Verna',
    paymentOption: 'UPI',
    createdAt: '2026-05-31T09:15:00Z',
  },
  {
    bookingId: 'BK_1002',
    customerId: 'cust_2',
    customerName: 'Ananya Roy',
    pickup: 'Gachibowli DLF Phase 2, Hyderabad',
    drop: 'Inorbit Mall, Hitech City, Hyderabad',
    pickupLatLng: { lat: 17.4483, lng: 78.3496 },
    dropLatLng: { lat: 17.4346, lng: 78.3825 },
    vehicle: 'Bike',
    price: '₹120.00',
    otp: '8814',
    status: 'completed',
    driverId: 'drv_2',
    driverName: 'Suresh Raina',
    vehiclePlate: 'AP 39 BK 9876',
    vehicleModelColor: 'Red Honda Shine',
    paymentOption: 'Wallet',
    createdAt: '2026-05-31T10:30:00Z',
  },
  {
    bookingId: 'BK_1003',
    customerId: 'cust_4',
    customerName: 'Diya Iyer',
    pickup: 'Secunderabad Railway Station, Hyderabad',
    drop: 'Jubilee Hills Checkpost, Hyderabad',
    pickupLatLng: { lat: 17.4344, lng: 78.5015 },
    dropLatLng: { lat: 17.4326, lng: 78.4072 },
    vehicle: 'Car',
    price: '₹480.00',
    otp: '2359',
    status: 'started',
    driverId: 'drv_1',
    driverName: 'Ramesh Kumar',
    vehiclePlate: 'TS 09 SD 1234',
    vehicleModelColor: 'Black Hyundai Verna',
    paymentOption: 'Card',
    createdAt: '2026-05-31T13:00:00Z',
  },
  {
    bookingId: 'BK_1004',
    customerId: 'cust_5',
    customerName: 'Vivaan Kapoor',
    pickup: 'Charminar, Hyderabad',
    drop: 'Golconda Fort, Hyderabad',
    pickupLatLng: { lat: 17.3616, lng: 78.4747 },
    dropLatLng: { lat: 17.3833, lng: 78.4011 },
    vehicle: 'Auto',
    price: '₹220.00',
    otp: '7104',
    status: 'requested',
    driverId: null,
    driverName: null,
    vehiclePlate: null,
    vehicleModelColor: null,
    paymentOption: 'Cash',
    createdAt: '2026-05-31T13:15:00Z',
  },
];

export const mockDeliveries: Delivery[] = [
  {
    bookingId: 'DL_2001',
    customerId: 'cust_1',
    customerName: 'Aarav Mehta',
    pickup: 'Kondapur Main Road, Hyderabad',
    drop: 'Gachibowli Outer Ring Road, Hyderabad',
    pickupLatLng: { lat: 17.4622, lng: 78.3568 },
    dropLatLng: { lat: 17.4258, lng: 78.3414 },
    vehicle: 'Mini Truck',
    price: '₹950.00',
    otp: '1092',
    status: 'completed',
    driverId: 'drv_2', // Mock driver delivering
    driverName: 'Suresh Raina',
    vehiclePlate: 'AP 39 BK 9876',
    vehicleModelColor: 'Red Honda Shine',
    paymentOption: 'UPI',
    goodsType: 'Office Furniture (Chairs & Table)',
    weight: '120 kg',
    pickupContactName: 'Aarav Mehta',
    pickupContactPhone: '9876543210',
    dropContactName: 'Shyam Sundar',
    dropContactPhone: '9900887766',
    createdAt: '2026-05-31T08:00:00Z',
  },
  {
    bookingId: 'DL_2002',
    customerId: 'cust_4',
    customerName: 'Diya Iyer',
    pickup: 'Nampally Bazar, Hyderabad',
    drop: 'Banjara Hills Road No 10, Hyderabad',
    pickupLatLng: { lat: 17.3912, lng: 78.4682 },
    dropLatLng: { lat: 17.4144, lng: 78.4326 },
    vehicle: 'Truck',
    price: '₹2400.00',
    otp: '5641',
    status: 'requested',
    driverId: null,
    driverName: null,
    vehiclePlate: null,
    vehicleModelColor: null,
    paymentOption: 'UPI',
    goodsType: 'Apparel Carton Boxes (Bulk)',
    weight: '650 kg',
    pickupContactName: 'Sandeep Tex',
    pickupContactPhone: '9848012345',
    dropContactName: 'Mall Manager',
    dropContactPhone: '9848056789',
    createdAt: '2026-05-31T13:10:00Z',
  },
];

export const mockPayments: Payment[] = [
  { transactionId: 'TXN_9901', bookingId: 'BK_1001', amount: 350.00, paymentMethod: 'UPI', status: 'completed', type: 'ride_fare', userId: 'cust_1', userRole: 'customer', createdAt: '2026-05-31T09:20:00Z' },
  { transactionId: 'TXN_9902', bookingId: 'BK_1001', amount: 70.00, paymentMethod: 'Wallet', status: 'completed', type: 'commission', userId: 'drv_1', userRole: 'partner', createdAt: '2026-05-31T09:20:00Z' },
  { transactionId: 'TXN_9903', bookingId: 'BK_1002', amount: 120.00, paymentMethod: 'Wallet', status: 'completed', type: 'ride_fare', userId: 'cust_2', userRole: 'customer', createdAt: '2026-05-31T10:45:00Z' },
  { transactionId: 'TXN_9904', bookingId: 'DL_2001', amount: 950.00, paymentMethod: 'UPI', status: 'completed', type: 'delivery_fare', userId: 'cust_1', userRole: 'customer', createdAt: '2026-05-31T09:00:00Z' },
  { transactionId: 'TXN_9905', amount: 1500.00, paymentMethod: 'UPI', status: 'pending', type: 'withdrawal', userId: 'drv_1', userRole: 'partner', createdAt: '2026-05-30T18:00:00Z' },
  { transactionId: 'TXN_9906', amount: 3000.00, paymentMethod: 'UPI', status: 'completed', type: 'withdrawal', userId: 'drv_2', userRole: 'partner', createdAt: '2026-05-29T11:00:00Z' },
];

export const mockSupportTickets: SupportTicket[] = [
  {
    ticketId: 'TCK_3001',
    creatorId: 'cust_1',
    creatorName: 'Aarav Mehta',
    creatorRole: 'customer',
    subject: 'Charged extra fare on completed ride',
    category: 'payment_issue',
    message: 'The ride BK_1001 estimated ₹320, but I was charged ₹350 at the end. Why the difference of ₹30?',
    status: 'assigned',
    assignedTo: 'adm_3',
    chatHistory: [
      { senderId: 'cust_1', senderName: 'Aarav Mehta', message: 'The ride BK_1001 estimated ₹320, but I was charged ₹350 at the end. Why the difference of ₹30?', timestamp: '2026-05-31T09:30:00Z' },
      { senderId: 'adm_3', senderName: 'Neha Patil', message: 'Hello Aarav, looking into your ride. It seems there was a traffic wait time adjustment of 6 minutes added by the fare calculator. Let me double-check the route logs.', timestamp: '2026-05-31T09:45:00Z' },
    ],
    createdAt: '2026-05-31T09:30:00Z',
  },
  {
    ticketId: 'TCK_3002',
    creatorId: 'drv_4',
    creatorName: 'Abdul Rehman',
    creatorRole: 'partner',
    subject: 'Account suspended unexpectedly',
    category: 'safety',
    message: 'My partner account was suspended this morning. I did not commit any violation, please help me reactivate it.',
    status: 'open',
    assignedTo: null,
    chatHistory: [
      { senderId: 'drv_4', senderName: 'Abdul Rehman', message: 'My partner account was suspended this morning. I did not commit any violation, please help me reactivate it.', timestamp: '2026-05-31T11:00:00Z' },
    ],
    createdAt: '2026-05-31T11:00:00Z',
  },
];

export const mockPromoCodes: PromoCode[] = [
  { code: 'STAYDRIV50', discountPercentage: 50, maxDiscount: 100, minBookingValue: 150, expiryDate: '2026-06-30', status: 'active', usageCount: 421 },
  { code: 'FIRSTDELIVERY', discountPercentage: 20, maxDiscount: 200, minBookingValue: 500, expiryDate: '2026-07-15', status: 'active', usageCount: 95 },
  { code: 'MONSOONOFF', discountPercentage: 15, maxDiscount: 50, minBookingValue: 100, expiryDate: '2026-05-15', status: 'inactive', usageCount: 650 },
];

export const mockAuditLogs: AuditLog[] = [
  { logId: 'LOG_8001', adminId: 'adm_1', adminEmail: 'super@staydriv.com', action: 'SYSTEM_START', details: 'Admin panel initialized in simulation mode.', ipAddress: '192.168.1.1', timestamp: '2026-05-31T08:00:00Z' },
  { logId: 'LOG_8002', adminId: 'adm_2', adminEmail: 'ops@staydriv.com', action: 'SUSPEND_PARTNER', details: 'Suspended driver partner Abdul Rehman (drv_4) due to low rating.', ipAddress: '192.168.1.5', timestamp: '2026-05-31T11:05:00Z' },
];

export const mockConfig = {
  commissionPercent: 20,
  baseFares: {
    Bike: 40,
    Auto: 60,
    Car: 100,
    'Mini Truck': 250,
    Truck: 600,
  },
  perKmRates: {
    Bike: 8,
    Auto: 12,
    Car: 18,
    'Mini Truck': 35,
    Truck: 75,
  },
  cancellationCharges: {
    customer: 30,
    partner: 50,
  },
  referralRewards: {
    referrer: 100,
    referee: 50,
  },
  serviceAreas: [
    { name: 'Hyderabad Central (GHMC)', active: true },
    { name: 'Secunderabad', active: true },
    { name: 'Cyberabad Zone (Gachibowli/Madhapur)', active: true },
    { name: 'Hyderabad Outskirts (ORR Bounds)', active: false },
  ],
};
