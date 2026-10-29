const express = require('express');

/**
 * Escapes special characters for safe regular expression generation.
 * Prevents ReDoS attacks and regex syntax errors from user input.
 */
function escapeRegex(text) {
  if (!text || typeof text !== 'string') return '';
  return text.trim().replace(/[-[\]{}()*+?.,\\^$|#\s]/g, '\\$&');
}

/**
 * Builds the Admin Global Search router.
 * Accepts database models and authentication middleware.
 */
module.exports = function createAdminSearchRoutes(models, verifyAdminAuth) {
  const router = express.Router();
  const {
    User,
    Booking,
    FoodOrder,
    Restaurant,
    PilotDailyPlanPayment,
    Payment,
    WithdrawalRequest,
    Complaint
  } = models;

  /**
   * GET /api/admin/global-search
   * Query params:
   *   q: string (Search query, min 1 char)
   *   module: string (Optional filter, e.g. 'all', 'pilots', 'customers', 'rides', 'food_orders', 'restaurants', 'daily_plans', 'payments', 'withdrawals', 'complaints')
   *   limit: number (Max results per module, default 10, max 25)
   */
  router.get('/global-search', verifyAdminAuth, async (req, res) => {
    try {
      const rawQuery = (req.query.q || req.query.query || '').trim();
      const selectedModule = (req.query.module || 'all').toLowerCase();
      const perModuleLimit = Math.min(Math.max(parseInt(req.query.limit, 10) || 8, 1), 25);

      if (!rawQuery) {
        return res.status(200).json({
          success: true,
          query: '',
          totalMatches: 0,
          groupedResults: {},
          results: []
        });
      }

      // Safe Regex construction (case-insensitive)
      const sanitized = escapeRegex(rawQuery);
      const searchRegex = new RegExp(sanitized, 'i');
      
      // Digits-only regex for exact or partial phone / ID matching
      const digitsOnly = rawQuery.replace(/\D/g, '');
      const digitsRegex = digitsOnly.length >= 3 ? new RegExp(digitsOnly) : null;

      const results = [];
      const grouped = {
        pilots: [],
        customers: [],
        rides: [],
        food_orders: [],
        restaurants: [],
        daily_plans: [],
        payments: [],
        withdrawals: [],
        complaints: []
      };

      const tasks = [];

      // 1. SEARCH PILOTS / DRIVERS
      if (selectedModule === 'all' || selectedModule === 'pilots') {
        tasks.push(
          (async () => {
            try {
              if (!User) return;
              const pilotOr = [
                { name: searchRegex },
                { phone: searchRegex },
                { uid: searchRegex },
                { applicationId: searchRegex },
                { vehiclePlate: searchRegex },
                { vehicleNumber: searchRegex },
                { licenseNumber: searchRegex },
                { vehicleType: searchRegex },
                { status: searchRegex },
                { dutyStatus: searchRegex }
              ];
              if (digitsRegex) {
                pilotOr.push({ phone: digitsRegex });
                pilotOr.push({ aadhaarNumber: digitsRegex });
              }

              const pilots = await User.find({
                $and: [
                  {
                    $or: [
                      { role: { $in: ['partner', 'pilot', 'driver'] } },
                      { vehiclePlate: { $exists: true, $ne: '' } },
                      { applicationId: { $exists: true, $ne: '' } },
                      { vehicleType: { $exists: true, $ne: '' } }
                    ]
                  },
                  { $or: pilotOr }
                ]
              })
                .select('-password -otp -token -documents -__v')
                .limit(perModuleLimit)
                .lean();

              pilots.forEach(p => {
                const isApproved = Boolean(p.approved || p.isApproved || String(p.status).toUpperCase() === 'APPROVED');
                const duty = p.dutyStatus || (p.online ? 'DUTY ON' : 'DUTY OFF');
                const bookingAccess = (p.bookingAccess && p.bookingAccess.status) || (p.adminBookingEnabled ? 'ENABLED' : 'DISABLED');

                // Determine matching context snippet
                let matchContext = `Phone: ${p.phone || 'N/A'}`;
                if (p.vehiclePlate && searchRegex.test(p.vehiclePlate)) matchContext = `Plate: ${p.vehiclePlate}`;
                else if (p.applicationId && searchRegex.test(p.applicationId)) matchContext = `App ID: ${p.applicationId}`;
                else if (p.name && searchRegex.test(p.name)) matchContext = `Pilot Name: ${p.name}`;
                else if (p.vehicleType && searchRegex.test(p.vehicleType)) matchContext = `Vehicle: ${p.vehicleType}`;

                const item = {
                  id: `pilot_${p._id}`,
                  recordId: p.uid || p.applicationId || String(p._id),
                  title: p.name || 'Unnamed Pilot',
                  subtitle: `${p.vehicleType || 'Vehicle'} • ${p.vehiclePlate || 'No Plate'} • 📞 ${p.phone || 'N/A'}`,
                  module: 'pilots',
                  moduleLabel: 'Pilot / Driver',
                  matchContext,
                  status: isApproved ? (duty === 'DUTY ON' ? 'DUTY ON' : 'APPROVED') : (p.status || 'PENDING'),
                  statusType: isApproved ? 'success' : (p.isBlocked ? 'error' : 'warning'),
                  date: p.createdAt || p.submittedAt || null,
                  targetTab: 'pilot-management',
                  filterParam: p.phone || p.name || p.uid || '',
                  rawDetails: {
                    phone: p.phone,
                    vehicleType: p.vehicleType,
                    vehiclePlate: p.vehiclePlate,
                    dutyStatus: duty,
                    bookingAccess,
                    walletBalance: p.walletBalance || 0
                  }
                };
                grouped.pilots.push(item);
                results.push(item);
              });
            } catch (err) {
              console.error('Admin Global Search - Pilot Error:', err.message);
            }
          })()
        );
      }

      // 2. SEARCH CUSTOMERS
      if (selectedModule === 'all' || selectedModule === 'customers') {
        tasks.push(
          (async () => {
            try {
              if (!User) return;
              const customerOr = [
                { name: searchRegex },
                { phone: searchRegex },
                { uid: searchRegex },
                { email: searchRegex }
              ];
              if (digitsRegex) customerOr.push({ phone: digitsRegex });

              const customers = await User.find({
                $and: [
                  {
                    $or: [
                      { role: 'customer' },
                      { role: { $exists: false } },
                      { role: null }
                    ]
                  },
                  {
                    role: { $nin: ['partner', 'pilot', 'driver', 'admin', 'super_admin'] }
                  },
                  { $or: customerOr }
                ]
              })
                .select('-password -otp -token -documents -__v')
                .limit(perModuleLimit)
                .lean();

              customers.forEach(c => {
                let matchContext = `Phone: ${c.phone || 'N/A'}`;
                if (c.email && searchRegex.test(c.email)) matchContext = `Email: ${c.email}`;
                else if (c.uid && searchRegex.test(c.uid)) matchContext = `Customer ID: ${c.uid}`;
                else if (c.name && searchRegex.test(c.name)) matchContext = `Customer: ${c.name}`;

                const item = {
                  id: `customer_${c._id}`,
                  recordId: c.uid || String(c._id),
                  title: c.name || 'StayDriv Customer',
                  subtitle: `Customer • 📞 ${c.phone || 'N/A'}${c.email ? ` • ${c.email}` : ''}`,
                  module: 'customers',
                  moduleLabel: 'Customer',
                  matchContext,
                  status: c.isBlocked ? 'BLOCKED' : 'ACTIVE',
                  statusType: c.isBlocked ? 'error' : 'success',
                  date: c.createdAt || null,
                  targetTab: 'customers',
                  filterParam: c.phone || c.name || c.uid || '',
                  rawDetails: {
                    phone: c.phone,
                    email: c.email,
                    walletBalance: c.walletBalance || 0,
                    activeRideId: c.currentRideId || ''
                  }
                };
                grouped.customers.push(item);
                results.push(item);
              });
            } catch (err) {
              console.error('Admin Global Search - Customer Error:', err.message);
            }
          })()
        );
      }

      // 3. SEARCH BOOKINGS (Rides, Bike, Auto, Car, Parcel, Truck)
      if (selectedModule === 'all' || selectedModule === 'rides') {
        tasks.push(
          (async () => {
            try {
              if (!Booking) return;
              const bookingOr = [
                { bookingId: searchRegex },
                { id: searchRegex },
                { passengerName: searchRegex },
                { passengerPhone: searchRegex },
                { customerName: searchRegex },
                { customerPhone: searchRegex },
                { driverName: searchRegex },
                { driverPhone: searchRegex },
                { vehicle: searchRegex },
                { vehicleType: searchRegex },
                { tripType: searchRegex },
                { status: searchRegex },
                { pickupAddress: searchRegex },
                { destinationAddress: searchRegex },
                { pickupLocation: searchRegex },
                { destinationLocation: searchRegex }
              ];
              if (digitsRegex) {
                bookingOr.push({ passengerPhone: digitsRegex });
                bookingOr.push({ driverPhone: digitsRegex });
              }

              const bookings = await Booking.find({ $or: bookingOr })
                .select('-otp -pickupOtp -deliveryOtp -__v')
                .sort({ createdAt: -1 })
                .limit(perModuleLimit)
                .lean();

              bookings.forEach(b => {
                const bId = b.bookingId || b.id || String(b._id);
                const vehicle = b.vehicle || b.vehicleType || 'Ride';
                const fare = b.fare || b.finalFare || b.amount || 0;
                const status = (b.status || 'unknown').toUpperCase();
                const isParcel = /parcel|delivery|courier|truck/i.test(vehicle) || /delivery/i.test(b.tripType || '');

                let matchContext = `Booking ID: ${bId}`;
                if (b.passengerName && searchRegex.test(b.passengerName)) matchContext = `Passenger: ${b.passengerName}`;
                else if (b.driverName && searchRegex.test(b.driverName)) matchContext = `Pilot: ${b.driverName}`;
                else if (b.passengerPhone && searchRegex.test(b.passengerPhone)) matchContext = `Customer Phone: ${b.passengerPhone}`;
                else if (b.driverPhone && searchRegex.test(b.driverPhone)) matchContext = `Pilot Phone: ${b.driverPhone}`;
                else if (b.pickupAddress && searchRegex.test(b.pickupAddress)) matchContext = `Pickup: ${b.pickupAddress.slice(0, 30)}...`;

                const item = {
                  id: `booking_${b._id}`,
                  recordId: bId,
                  title: `${bId} (${vehicle})`,
                  subtitle: `Customer: ${b.passengerName || b.customerName || 'N/A'} • Pilot: ${b.driverName || 'Unassigned'} • ₹${fare}`,
                  module: 'rides',
                  moduleLabel: isParcel ? 'Delivery / Parcel' : 'Ride Booking',
                  matchContext,
                  status,
                  statusType: status === 'COMPLETED' ? 'success' : (status === 'CANCELLED' ? 'error' : 'info'),
                  date: b.createdAt || null,
                  targetTab: isParcel ? 'deliveries' : 'rides',
                  filterParam: bId,
                  rawDetails: {
                    bookingId: bId,
                    customer: b.passengerName || b.customerName,
                    customerPhone: b.passengerPhone,
                    driver: b.driverName,
                    driverPhone: b.driverPhone,
                    vehicle,
                    fare,
                    pickup: b.pickupAddress || b.pickupLocation,
                    destination: b.destinationAddress || b.destinationLocation
                  }
                };
                grouped.rides.push(item);
                results.push(item);
              });
            } catch (err) {
              console.error('Admin Global Search - Booking Error:', err.message);
            }
          })()
        );
      }

      // 4. SEARCH FOOD ORDERS
      if (selectedModule === 'all' || selectedModule === 'food_orders') {
        tasks.push(
          (async () => {
            try {
              if (!FoodOrder) return;
              const orderOr = [
                { orderId: searchRegex },
                { customerName: searchRegex },
                { customerPhone: searchRegex },
                { restaurantName: searchRegex },
                { restaurantPhone: searchRegex },
                { deliveryPartnerName: searchRegex },
                { deliveryPartnerPhone: searchRegex },
                { orderStatus: searchRegex },
                { paymentStatus: searchRegex },
                { couponCode: searchRegex },
                { razorpayOrderId: searchRegex },
                { razorpayPaymentId: searchRegex }
              ];
              if (digitsRegex) {
                orderOr.push({ customerPhone: digitsRegex });
                orderOr.push({ restaurantPhone: digitsRegex });
                orderOr.push({ deliveryPartnerPhone: digitsRegex });
              }

              const orders = await FoodOrder.find({ $or: orderOr })
                .select('-customerOtp -deliveryOtp -restaurantOtp -returnOtp -razorpaySignature -__v')
                .sort({ createdAt: -1 })
                .limit(perModuleLimit)
                .lean();

              orders.forEach(o => {
                const total = o.finalPayable || o.totalAmount || 0;
                const status = (o.orderStatus || 'placed').toUpperCase();

                let matchContext = `Order ID: ${o.orderId}`;
                if (o.restaurantName && searchRegex.test(o.restaurantName)) matchContext = `Restaurant: ${o.restaurantName}`;
                else if (o.customerName && searchRegex.test(o.customerName)) matchContext = `Customer: ${o.customerName}`;
                else if (o.customerPhone && searchRegex.test(o.customerPhone)) matchContext = `Customer Phone: ${o.customerPhone}`;
                else if (o.deliveryPartnerName && searchRegex.test(o.deliveryPartnerName)) matchContext = `Delivery Partner: ${o.deliveryPartnerName}`;
                else if (o.couponCode && searchRegex.test(o.couponCode)) matchContext = `Coupon: ${o.couponCode}`;

                const item = {
                  id: `order_${o._id}`,
                  recordId: o.orderId,
                  title: `Food #${o.orderId} • ${o.restaurantName || 'Restaurant'}`,
                  subtitle: `Customer: ${o.customerName || 'N/A'} • Pilot: ${o.deliveryPartnerName || 'Unassigned'} • ₹${total}`,
                  module: 'food_orders',
                  moduleLabel: 'Food Order',
                  matchContext,
                  status,
                  statusType: status === 'DELIVERED' ? 'success' : (status === 'CANCELLED' || status === 'REJECTED' ? 'error' : 'warning'),
                  date: o.createdAt || null,
                  targetTab: 'food-orders',
                  filterParam: o.orderId,
                  rawDetails: {
                    orderId: o.orderId,
                    restaurant: o.restaurantName,
                    customer: o.customerName,
                    customerPhone: o.customerPhone,
                    deliveryPartner: o.deliveryPartnerName,
                    total,
                    paymentStatus: o.paymentStatus,
                    itemsCount: Array.isArray(o.items) ? o.items.length : 0
                  }
                };
                grouped.food_orders.push(item);
                results.push(item);
              });
            } catch (err) {
              console.error('Admin Global Search - FoodOrder Error:', err.message);
            }
          })()
        );
      }

      // 5. SEARCH RESTAURANTS
      if (selectedModule === 'all' || selectedModule === 'restaurants') {
        tasks.push(
          (async () => {
            try {
              if (!Restaurant) return;
              const restOr = [
                { restaurantId: searchRegex },
                { name: searchRegex },
                { ownerName: searchRegex },
                { phone: searchRegex },
                { address: searchRegex },
                { cuisines: searchRegex },
                { status: searchRegex },
                { fssaiNumber: searchRegex },
                { gstNumber: searchRegex }
              ];
              if (digitsRegex) restOr.push({ phone: digitsRegex });

              const restaurants = await Restaurant.find({ $or: restOr })
                .select('-bankAccount -fssaiDocUrl -panDocUrl -gstDocUrl -__v')
                .limit(perModuleLimit)
                .lean();

              restaurants.forEach(r => {
                const status = (r.status || 'pending').toUpperCase();
                let matchContext = `Restaurant: ${r.name}`;
                if (r.phone && searchRegex.test(r.phone)) matchContext = `Phone: ${r.phone}`;
                else if (r.ownerName && searchRegex.test(r.ownerName)) matchContext = `Owner: ${r.ownerName}`;
                else if (r.address && searchRegex.test(r.address)) matchContext = `Address: ${r.address.slice(0, 30)}...`;

                const item = {
                  id: `rest_${r._id}`,
                  recordId: r.restaurantId || String(r._id),
                  title: r.name || 'Unnamed Restaurant',
                  subtitle: `Owner: ${r.ownerName || 'N/A'} • 📞 ${r.phone || 'N/A'} • ${Array.isArray(r.cuisines) ? r.cuisines.slice(0, 3).join(', ') : ''}`,
                  module: 'restaurants',
                  moduleLabel: 'Restaurant Partner',
                  matchContext,
                  status,
                  statusType: status === 'APPROVED' ? 'success' : (status === 'PENDING' ? 'warning' : 'error'),
                  date: r.createdAt || null,
                  targetTab: 'food-orders',
                  filterParam: r.name || r.restaurantId,
                  rawDetails: {
                    restaurantId: r.restaurantId,
                    name: r.name,
                    phone: r.phone,
                    address: r.address,
                    isOpen: r.isOpen,
                    rating: r.rating
                  }
                };
                grouped.restaurants.push(item);
                results.push(item);
              });
            } catch (err) {
              console.error('Admin Global Search - Restaurant Error:', err.message);
            }
          })()
        );
      }

      // 6. SEARCH DAILY ₹20 PILOT PLANS
      if (selectedModule === 'all' || selectedModule === 'daily_plans') {
        tasks.push(
          (async () => {
            try {
              if (!PilotDailyPlanPayment) return;
              const planOr = [
                { transactionId: searchRegex },
                { gatewayPaymentId: searchRegex },
                { gatewayOrderId: searchRegex },
                { pilotName: searchRegex },
                { pilotPhone: searchRegex },
                { pilotId: searchRegex },
                { vehicleType: searchRegex },
                { paymentStatus: searchRegex },
                { dutyStatus: searchRegex },
                { bookingAccessStatus: searchRegex }
              ];
              if (digitsRegex) planOr.push({ pilotPhone: digitsRegex });

              const plans = await PilotDailyPlanPayment.find({ $or: planOr })
                .sort({ paidAt: -1 })
                .limit(perModuleLimit)
                .lean();

              plans.forEach(pl => {
                const status = (pl.paymentStatus || 'paid').toUpperCase();
                let matchContext = `Txn: ${pl.transactionId}`;
                if (pl.pilotPhone && searchRegex.test(pl.pilotPhone)) matchContext = `Pilot Phone: ${pl.pilotPhone}`;
                else if (pl.pilotName && searchRegex.test(pl.pilotName)) matchContext = `Pilot: ${pl.pilotName}`;
                else if (pl.bookingAccessStatus && searchRegex.test(pl.bookingAccessStatus)) matchContext = `Access: ${pl.bookingAccessStatus}`;

                const item = {
                  id: `plan_${pl._id}`,
                  recordId: pl.transactionId,
                  title: `₹${pl.amount || 20} Plan • ${pl.pilotName || 'Pilot'}`,
                  subtitle: `Phone: ${pl.pilotPhone} • ${pl.vehicleType || 'Vehicle'} • Duty: ${pl.dutyStatus || 'DUTY OFF'} • Access: ${pl.bookingAccessStatus || 'disabled'}`,
                  module: 'daily_plans',
                  moduleLabel: 'Pilot ₹20 Plan',
                  matchContext,
                  status,
                  statusType: status === 'PAID' ? 'success' : (status === 'EXPIRED' ? 'warning' : 'error'),
                  date: pl.paidAt || pl.createdAt || null,
                  targetTab: 'daily-pilot-plan',
                  filterParam: pl.pilotPhone || pl.transactionId,
                  rawDetails: {
                    transactionId: pl.transactionId,
                    pilotName: pl.pilotName,
                    pilotPhone: pl.pilotPhone,
                    amount: pl.amount,
                    expiresAt: pl.expiresAt,
                    dutyStatus: pl.dutyStatus,
                    bookingAccess: pl.bookingAccessStatus
                  }
                };
                grouped.daily_plans.push(item);
                results.push(item);
              });
            } catch (err) {
              console.error('Admin Global Search - DailyPlan Error:', err.message);
            }
          })()
        );
      }

      // 7. SEARCH PAYMENTS & TRANSACTIONS
      if (selectedModule === 'all' || selectedModule === 'payments') {
        tasks.push(
          (async () => {
            try {
              if (!Payment) return;
              const payOr = [
                { orderId: searchRegex },
                { paymentId: searchRegex },
                { bookingId: searchRegex },
                { customerPhone: searchRegex },
                { customerEmail: searchRegex },
                { status: searchRegex },
                { method: searchRegex }
              ];
              if (digitsRegex) payOr.push({ customerPhone: digitsRegex });

              const payments = await Payment.find({ $or: payOr })
                .select('-signature -notes -__v')
                .sort({ createdAt: -1 })
                .limit(perModuleLimit)
                .lean();

              payments.forEach(py => {
                const amountInRupees = py.amount ? (py.amount / 100).toFixed(2) : '0.00';
                const status = (py.status || 'created').toUpperCase();

                let matchContext = `Txn: ${py.paymentId || py.orderId}`;
                if (py.bookingId && searchRegex.test(py.bookingId)) matchContext = `Booking ID: ${py.bookingId}`;
                else if (py.customerPhone && searchRegex.test(py.customerPhone)) matchContext = `Customer: ${py.customerPhone}`;

                const item = {
                  id: `pay_${py._id}`,
                  recordId: py.paymentId || py.orderId,
                  title: `Payment ₹${amountInRupees} (${py.method || 'Online'})`,
                  subtitle: `Order: ${py.orderId}${py.bookingId ? ` • Booking: ${py.bookingId}` : ''}${py.customerPhone ? ` • 📞 ${py.customerPhone}` : ''}`,
                  module: 'payments',
                  moduleLabel: 'Payment Transaction',
                  matchContext,
                  status,
                  statusType: status === 'CAPTURED' || status === 'VERIFIED' ? 'success' : (status === 'REFUNDED' ? 'warning' : 'error'),
                  date: py.createdAt || null,
                  targetTab: 'ledger',
                  filterParam: py.paymentId || py.orderId || py.bookingId,
                  rawDetails: {
                    orderId: py.orderId,
                    paymentId: py.paymentId,
                    bookingId: py.bookingId,
                    amount: amountInRupees,
                    method: py.method,
                    customerPhone: py.customerPhone
                  }
                };
                grouped.payments.push(item);
                results.push(item);
              });
            } catch (err) {
              console.error('Admin Global Search - Payment Error:', err.message);
            }
          })()
        );
      }

      // 8. SEARCH WITHDRAWALS
      if (selectedModule === 'all' || selectedModule === 'withdrawals') {
        tasks.push(
          (async () => {
            try {
              if (!WithdrawalRequest) return;
              const withOr = [
                { requestId: searchRegex },
                { pilotName: searchRegex },
                { pilotPhone: searchRegex },
                { pilotId: searchRegex },
                { status: searchRegex },
                { utr: searchRegex }
              ];
              if (digitsRegex) withOr.push({ pilotPhone: digitsRegex });

              const withdrawals = await WithdrawalRequest.find({ $or: withOr })
                .sort({ createdAt: -1 })
                .limit(perModuleLimit)
                .lean();

              withdrawals.forEach(w => {
                const status = (w.status || 'pending').toUpperCase();
                let matchContext = `Req ID: ${w.requestId || w._id}`;
                if (w.pilotPhone && searchRegex.test(w.pilotPhone)) matchContext = `Phone: ${w.pilotPhone}`;
                else if (w.pilotName && searchRegex.test(w.pilotName)) matchContext = `Pilot: ${w.pilotName}`;

                const item = {
                  id: `with_${w._id}`,
                  recordId: w.requestId || String(w._id),
                  title: `Withdrawal ₹${w.amount || 0} • ${w.pilotName || 'Pilot'}`,
                  subtitle: `Phone: ${w.pilotPhone || 'N/A'} • Status: ${status}${w.utr ? ` • UTR: ${w.utr}` : ''}`,
                  module: 'withdrawals',
                  moduleLabel: 'Pilot Withdrawal',
                  matchContext,
                  status,
                  statusType: status === 'APPROVED' || status === 'COMPLETED' ? 'success' : (status === 'PENDING' ? 'warning' : 'error'),
                  date: w.createdAt || null,
                  targetTab: 'withdrawals',
                  filterParam: w.pilotPhone || w.requestId || w.pilotName,
                  rawDetails: {
                    requestId: w.requestId,
                    pilotName: w.pilotName,
                    pilotPhone: w.pilotPhone,
                    amount: w.amount,
                    status
                  }
                };
                grouped.withdrawals.push(item);
                results.push(item);
              });
            } catch (err) {
              console.error('Admin Global Search - Withdrawal Error:', err.message);
            }
          })()
        );
      }

      // 9. SEARCH COMPLAINTS & DISPUTES
      if (selectedModule === 'all' || selectedModule === 'complaints') {
        tasks.push(
          (async () => {
            try {
              if (!Complaint) return;
              const compOr = [
                { complaintId: searchRegex },
                { reportedByName: searchRegex },
                { reportedByPhone: searchRegex },
                { targetName: searchRegex },
                { targetPhone: searchRegex },
                { bookingId: searchRegex },
                { subject: searchRegex },
                { description: searchRegex },
                { status: searchRegex }
              ];
              if (digitsRegex) {
                compOr.push({ reportedByPhone: digitsRegex });
                compOr.push({ targetPhone: digitsRegex });
              }

              const complaints = await Complaint.find({ $or: compOr })
                .sort({ createdAt: -1 })
                .limit(perModuleLimit)
                .lean();

              complaints.forEach(cp => {
                const status = (cp.status || 'pending').toUpperCase();
                let matchContext = `Complaint ID: ${cp.complaintId}`;
                if (cp.bookingId && searchRegex.test(cp.bookingId)) matchContext = `Booking ID: ${cp.bookingId}`;
                else if (cp.subject && searchRegex.test(cp.subject)) matchContext = `Subject: ${cp.subject}`;
                else if (cp.reportedByName && searchRegex.test(cp.reportedByName)) matchContext = `Reported By: ${cp.reportedByName}`;

                const item = {
                  id: `comp_${cp._id}`,
                  recordId: cp.complaintId || String(cp._id),
                  title: `${cp.complaintId}: ${cp.subject || 'Complaint'}`,
                  subtitle: `Reported by: ${cp.reportedByName || 'User'} (${cp.reportedByPhone || 'N/A'})${cp.targetName ? ` vs ${cp.targetName}` : ''}`,
                  module: 'complaints',
                  moduleLabel: 'Support / Dispute',
                  matchContext,
                  status,
                  statusType: status === 'RESOLVED' ? 'success' : (status === 'PENDING' ? 'warning' : 'info'),
                  date: cp.createdAt || null,
                  targetTab: 'disputes',
                  filterParam: cp.complaintId || cp.bookingId || cp.reportedByPhone,
                  rawDetails: {
                    complaintId: cp.complaintId,
                    reportedBy: cp.reportedByName,
                    reportedByPhone: cp.reportedByPhone,
                    subject: cp.subject,
                    bookingId: cp.bookingId
                  }
                };
                grouped.complaints.push(item);
                results.push(item);
              });
            } catch (err) {
              console.error('Admin Global Search - Complaint Error:', err.message);
            }
          })()
        );
      }

      // Execute all search tasks concurrently
      await Promise.allSettled(tasks);

      // Sort results by relevance: exact recordId matches first, then prefix, then date
      results.sort((a, b) => {
        const aRecordMatch = a.recordId && a.recordId.toLowerCase() === rawQuery.toLowerCase();
        const bRecordMatch = b.recordId && b.recordId.toLowerCase() === rawQuery.toLowerCase();
        if (aRecordMatch && !bRecordMatch) return -1;
        if (!aRecordMatch && bRecordMatch) return 1;

        const aTitleMatch = a.title && a.title.toLowerCase().startsWith(rawQuery.toLowerCase());
        const bTitleMatch = b.title && b.title.toLowerCase().startsWith(rawQuery.toLowerCase());
        if (aTitleMatch && !bTitleMatch) return -1;
        if (!aTitleMatch && bTitleMatch) return 1;

        const aTime = a.date ? new Date(a.date).getTime() : 0;
        const bTime = b.date ? new Date(b.date).getTime() : 0;
        return bTime - aTime;
      });

      return res.status(200).json({
        success: true,
        query: rawQuery,
        totalMatches: results.length,
        groupedResults: grouped,
        results
      });
    } catch (error) {
      console.error('Admin Global Search Endpoint Failure:', error);
      return res.status(500).json({
        success: false,
        message: 'Internal server error processing global search',
        error: error.message
      });
    }
  });

  return router;
};
