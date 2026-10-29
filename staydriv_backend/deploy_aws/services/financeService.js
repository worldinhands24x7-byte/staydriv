const mongoose = require('mongoose');
const CommissionConfig = require('../models/CommissionConfig');
const FinancialLedger = require('../models/FinancialLedger');
const FounderPayout = require('../models/FounderPayout');

// Mask sensitive destination bank account / UPI ID
function maskDestination(accountNumber, ifsc, upiId) {
  if (upiId && upiId.includes('@')) {
    const parts = upiId.split('@');
    const user = parts[0];
    const maskedUser = user.length > 2 
      ? user[0] + '••••' + user.slice(-1) 
      : '••••';
    return `${maskedUser}@${parts[1]}`;
  }
  if (accountNumber && accountNumber.length >= 4) {
    const last4 = accountNumber.slice(-4);
    return `•••• •••• ${last4}${ifsc ? ' (' + ifsc + ')' : ''}`;
  }
  return '•••• (Masked)';
}

// Parse string/number price into clean float
function parseAmount(val) {
  if (typeof val === 'number') return isNaN(val) ? 0 : parseFloat(val.toFixed(2));
  if (!val) return 0;
  const cleaned = String(val).replace(/[^0-9.]/g, '');
  const parsed = parseFloat(cleaned);
  return isNaN(parsed) ? 0 : parseFloat(parsed.toFixed(2));
}

// 1. Get or create active commission config
async function getActiveCommissionConfig() {
  let config = await CommissionConfig.findOne({ isActive: true }).sort({ version: -1 });
  if (!config) {
    config = new CommissionConfig({
      configId: 'CFG_DEFAULT_V1',
      version: 1,
      defaultRate: 20.0,
      ratesByVehicle: {
        Bike: 20.0,
        Auto: 15.0,
        Car: 20.0,
        'Mini Truck': 12.0,
        '6 Ton Truck': 10.0
      },
      ratesByService: {
        ride: 20.0,
        delivery: 15.0,
        parcel: 15.0
      },
      taxRateGst: 5.0,
      gatewayFeeRate: 2.0,
      isActive: true,
      notes: 'Initial production commission configuration'
    });
    await config.save();
  }
  return config;
}

// 2. Calculate commission for a given booking
function calculateCommissionForBooking(booking, config) {
  const fare = parseAmount(booking.price);
  if (fare <= 0) {
    return {
      fare: 0,
      commissionRate: 0,
      commissionAmount: 0,
      pilotEarnings: 0,
      gatewayFee: 0,
      taxAmount: 0,
      netPilotPayable: 0,
      settlementStatus: 'NO_CHARGE'
    };
  }

  // Check if booking belongs to an active ₹20 daily plan pilot (0% StayDriv commission, 100% pilot earnings)
  const isOnlinePayment = booking.paymentOption && booking.paymentOption.toUpperCase() !== 'CASH';
  const isDailyPlan = booking.isDailyPlan === true ||
    (booking.driver && (
      booking.driver.dailyPlan?.planStatus === 'paid' &&
      booking.driver.dailyPlan?.expiresAt &&
      new Date() < new Date(booking.driver.dailyPlan.expiresAt)
    )) ||
    (typeof booking.platformCommission === 'number' && booking.platformCommission === 0 && booking.pilotEarnings > 0);

  if (isDailyPlan) {
    return {
      fare,
      commissionRate: 0,
      commissionAmount: 0,
      pilotEarnings: fare,
      gatewayFee: 0,
      taxAmount: 0,
      netPilotPayable: fare,
      isDailyPlanApplied: true,
      settlementStatus: isOnlinePayment ? 'SETTLED' : 'CASH_COLLECTED_BY_PILOT'
    };
  }

  // Determine rate by vehicle / service
  let rate = config.defaultRate || 20.0;
  const vehicle = booking.vehicle || 'Bike';
  const serviceType = (booking.serviceType || 'ride').toLowerCase();

  if (config.ratesByVehicle && config.ratesByVehicle[vehicle] !== undefined) {
    rate = config.ratesByVehicle[vehicle];
  } else if (config.ratesByService && config.ratesByService[serviceType] !== undefined) {
    rate = config.ratesByService[serviceType];
  }

  const commissionAmount = parseFloat(((fare * rate) / 100).toFixed(2));
  const taxAmount = parseFloat(((commissionAmount * (config.taxRateGst || 5.0)) / 100).toFixed(2));
  
  const gatewayFee = isOnlinePayment 
    ? parseFloat(((fare * (config.gatewayFeeRate || 2.0)) / 100).toFixed(2))
    : 0.0;

  const pilotEarnings = parseFloat((fare - commissionAmount).toFixed(2));
  const netPilotPayable = pilotEarnings;

  const settlementStatus = isOnlinePayment ? 'SETTLED' : 'CASH_COLLECTED_BY_PILOT';

  return {
    fare,
    commissionRate: rate,
    commissionAmount,
    pilotEarnings,
    gatewayFee,
    taxAmount,
    netPilotPayable,
    settlementStatus
  };
}

// 3. Post balanced double-entry ledger entries for completed booking
async function recordBookingSettlementLedger(booking, comm) {
  if (!booking || comm.fare <= 0) return;

  const bId = booking.bookingId || String(booking._id);
  const existingLedger = await FinancialLedger.findOne({ sourceBookingId: bId, entryType: 'PLATFORM_COMMISSION' });
  if (existingLedger) {
    return; // Idempotent check: already posted
  }

  const timestamp = booking.endTime || booking.createdAt || new Date();
  const pilotId = booking.driverId || 'PILOT_UNASSIGNED';
  const customerId = booking.passengerId || 'CUSTOMER';

  const entries = [];

  // Entry 1: Total Customer Fare Collection
  entries.push({
    ledgerId: `LED_COL_${bId}_${Date.now()}`,
    transactionId: `TXN_COL_${bId}`,
    entryType: 'BOOKING_FARE_REVENUE',
    sourceBookingId: bId,
    pilotId,
    customerId,
    debitAccount: comm.settlementStatus === 'SETTLED' ? 'PAYMENT_GATEWAY_RECEIVABLE' : 'PILOT_CASH_ESCROW',
    creditAccount: 'CUSTOMER_FARE_COLLECTIONS',
    amount: comm.fare,
    currency: 'INR',
    referenceNumber: booking.paymentId || booking.orderId || bId,
    description: `Customer fare for booking ${bId} (${booking.vehicle || 'Trip'})`,
    timestamp
  });

  // Entry 2: Platform Commission Earned
  entries.push({
    ledgerId: `LED_COM_${bId}_${Date.now()}`,
    transactionId: `TXN_COM_${bId}`,
    entryType: 'PLATFORM_COMMISSION',
    sourceBookingId: bId,
    pilotId,
    customerId,
    debitAccount: 'CUSTOMER_FARE_COLLECTIONS',
    creditAccount: 'FOUNDER_COMMISSION_REVENUE',
    amount: comm.commissionAmount,
    currency: 'INR',
    referenceNumber: bId,
    description: `Platform commission (${comm.commissionRate}%) on booking ${bId}`,
    timestamp
  });

  // Entry 3: Pilot Net Earnings Credit
  entries.push({
    ledgerId: `LED_EARN_${bId}_${Date.now()}`,
    transactionId: `TXN_EARN_${bId}`,
    entryType: 'PILOT_FARE_EARNING',
    sourceBookingId: bId,
    pilotId,
    customerId,
    debitAccount: 'CUSTOMER_FARE_COLLECTIONS',
    creditAccount: 'PILOT_WALLET_LIABILITY',
    amount: comm.pilotEarnings,
    currency: 'INR',
    referenceNumber: bId,
    description: `Pilot net fare credit for booking ${bId}`,
    timestamp
  });

  // Entry 4: Applicable GST Tax Provision
  if (comm.taxAmount > 0) {
    entries.push({
      ledgerId: `LED_TAX_${bId}_${Date.now()}`,
      transactionId: `TXN_TAX_${bId}`,
      entryType: 'TAX_LIABILITY',
      sourceBookingId: bId,
      pilotId,
      customerId,
      debitAccount: 'FOUNDER_COMMISSION_REVENUE',
      creditAccount: 'GST_TAX_PAYABLE',
      amount: comm.taxAmount,
      currency: 'INR',
      referenceNumber: bId,
      description: `GST statutory provision on booking ${bId}`,
      timestamp
    });
  }

  // Entry 5: Gateway processing fee provision
  if (comm.gatewayFee > 0) {
    entries.push({
      ledgerId: `LED_GW_${bId}_${Date.now()}`,
      transactionId: `TXN_GW_${bId}`,
      entryType: 'GATEWAY_FEE',
      sourceBookingId: bId,
      pilotId,
      customerId,
      debitAccount: 'GATEWAY_FEE_EXPENSE',
      creditAccount: 'PAYMENT_GATEWAY_RECEIVABLE',
      amount: comm.gatewayFee,
      currency: 'INR',
      referenceNumber: booking.paymentId || bId,
      description: `Payment gateway fee on booking ${bId}`,
      timestamp
    });
  }

  await FinancialLedger.insertMany(entries);
}

// 4. Backfill historical ledger and bookings (Safe, Run-Once/Idempotent)
async function backfillHistoricalLedgerAndCommissions(Booking, User) {
  try {
    const config = await getActiveCommissionConfig();
    const completedBookings = await Booking.find({ status: 'completed' });
    console.log(`[FINANCE SERVICE] Verifying double-entry ledger for ${completedBookings.length} completed bookings...`);

    let postedCount = 0;
    for (const b of completedBookings) {
      const bId = b.bookingId || String(b._id);
      const exists = await FinancialLedger.findOne({ sourceBookingId: bId });
      if (!exists) {
        const comm = calculateCommissionForBooking(b, config);
        await recordBookingSettlementLedger(b, comm);
        postedCount++;
      }
    }
    if (postedCount > 0) {
      console.log(`[FINANCE SERVICE] Backfilled ${postedCount} bookings into immutable Financial Ledger.`);
    }

    // Reconcile Pilot Wallets to match ledger earnings
    const pilots = await User.find({ role: 'partner' });
    for (const pilot of pilots) {
      const uid = pilot.uid;
      const earningsAgg = await FinancialLedger.aggregate([
        { $match: { pilotId: uid, entryType: 'PILOT_FARE_EARNING', status: 'POSTED' } },
        { $group: { _id: null, total: { $sum: '$amount' } } }
      ]);
      const totalEarnedFromLedger = earningsAgg[0] ? earningsAgg[0].total : 0;

      // Base salary/advance plus lifetime earnings (new pilots start at ₹0; existing balances are preserved)
      const currentSalary = typeof pilot.salary === 'number' ? pilot.salary : 0;
      const calculatedLifetime = Math.max(pilot.totalLifetimeEarnings || 0, totalEarnedFromLedger);
      const ledgerPlusSalary = parseFloat((currentSalary + totalEarnedFromLedger).toFixed(2));
      const calculatedWallet = (typeof pilot.walletBalance === 'number' && pilot.walletBalance > 0)
        ? Math.max(pilot.walletBalance, ledgerPlusSalary)
        : ledgerPlusSalary;

      if (pilot.walletBalance !== calculatedWallet || pilot.totalLifetimeEarnings !== calculatedLifetime) {
        pilot.walletBalance = calculatedWallet;
        pilot.totalLifetimeEarnings = calculatedLifetime;
        await pilot.save();
      }
    }
  } catch (err) {
    console.error('[FINANCE SERVICE] Error in backfillHistoricalLedgerAndCommissions:', err.message);
  }
}

// 5. Compute the 20 Real-Time Operational & Financial KPIs
async function getRealtimeKPIs(models, activeContext) {
  const { User, Booking, WithdrawalRequest, Complaint, Refund, Payment } = models;
  const { onlineDrivers, liveCustomerLocations } = activeContext;

  const now = new Date();
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const startOfWeek = new Date(now);
  startOfWeek.setDate(now.getDate() - now.getDay());
  startOfWeek.setHours(0, 0, 0, 0);
  const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  const startOfYear = new Date(now.getFullYear(), 0, 1);

  // Parallel Database Aggregations
  const [
    totalCustomers,
    totalPilots,
    activeBookingsDocs,
    completedRidesCount,
    cancelledRidesAgg,
    passengerBookingsCount,
    deliveryBookingsCount,
    allCompletedBookings,
    totalPilotWalletsAgg,
    withdrawalsStatsAgg,
    refundsStatsAgg,
    complaintsCount,
    failedPaymentsCount,
    config
  ] = await Promise.all([
    User.countDocuments({ role: 'customer' }),
    User.countDocuments({ role: 'partner' }),
    Booking.find({
      status: { $in: ['accepted', 'arrived', 'started', 'heading_to_pickup', 'on_trip', 'searching'] }
    }).select('bookingId vehicle status passengerName driverName price createdAt'),
    Booking.countDocuments({ status: 'completed' }),
    Booking.aggregate([
      { $match: { status: 'cancelled' } },
      { $group: { _id: '$cancelReason', count: { $sum: 1 } } }
    ]),
    Booking.countDocuments({
      $or: [
        { serviceType: { $in: ['ride', 'bike', 'auto', 'car', null] }, vehicle: { $nin: ['Mini Truck', '6 Ton Truck', 'Truck'] } },
        { serviceType: { $exists: false } }
      ]
    }),
    Booking.countDocuments({
      $or: [
        { serviceType: { $in: ['delivery', 'parcel'] } },
        { vehicle: { $in: ['Mini Truck', '6 Ton Truck', 'Truck'] } }
      ]
    }),
    Booking.find({ status: 'completed' }).select('bookingId price vehicle serviceType createdAt paymentOption'),
    User.aggregate([
      { $match: { role: 'partner' } },
      { $group: { _id: null, totalBalance: { $sum: '$walletBalance' }, avgBalance: { $avg: '$walletBalance' } } }
    ]),
    WithdrawalRequest.aggregate([
      {
        $group: {
          _id: '$status',
          count: { $sum: 1 },
          totalAmount: { $sum: '$amount' }
        }
      }
    ]),
    Refund.find().select('status amount'),
    Complaint.countDocuments({ status: { $ne: 'resolved' } }),
    Payment.countDocuments({ status: 'failed' }),
    getActiveCommissionConfig()
  ]);

  // Online / Busy / Available pilot breakdown
  const onlinePilotsCount = Object.keys(onlineDrivers || {}).length;
  const activeTripsCount = activeBookingsDocs.filter(b => b.status !== 'searching').length;
  const busyPilotsCount = Math.min(onlinePilotsCount, activeTripsCount);
  const availablePilotsCount = Math.max(0, onlinePilotsCount - busyPilotsCount);

  // Online / Active customer counts
  const activeCustomersCount = activeBookingsDocs.length;
  const liveCustGpsCount = (liveCustomerLocations && liveCustomerLocations.size) ? liveCustomerLocations.size : 0;
  const onlineCustomersCount = Math.max(activeCustomersCount, liveCustGpsCount);

  // Cancellation reasons breakdown
  const cancellationReasons = {};
  let totalCancelledCount = 0;
  for (const item of cancelledRidesAgg) {
    const reason = item._id || 'Unspecified / Rider Cancelled';
    cancellationReasons[reason] = item.count;
    totalCancelledCount += item.count;
  }

  // Financial calculations from completed bookings
  let totalPaymentsCollected = 0.0;
  let totalPilotEarnings = 0.0;
  let totalPlatformCommission = 0.0;

  // Daily, Weekly, Monthly, Yearly summaries
  const financialSummaries = {
    today: { grossRevenue: 0.0, commission: 0.0, pilotEarnings: 0.0, trips: 0 },
    week: { grossRevenue: 0.0, commission: 0.0, pilotEarnings: 0.0, trips: 0 },
    month: { grossRevenue: 0.0, commission: 0.0, pilotEarnings: 0.0, trips: 0 },
    year: { grossRevenue: 0.0, commission: 0.0, pilotEarnings: 0.0, trips: 0 }
  };

  for (const b of allCompletedBookings) {
    const comm = calculateCommissionForBooking(b, config);
    totalPaymentsCollected += comm.fare;
    totalPilotEarnings += comm.pilotEarnings;
    totalPlatformCommission += comm.commissionAmount;

    const bDate = new Date(b.createdAt || now);
    if (bDate >= startOfYear) {
      financialSummaries.year.grossRevenue += comm.fare;
      financialSummaries.year.commission += comm.commissionAmount;
      financialSummaries.year.pilotEarnings += comm.pilotEarnings;
      financialSummaries.year.trips += 1;
    }
    if (bDate >= startOfMonth) {
      financialSummaries.month.grossRevenue += comm.fare;
      financialSummaries.month.commission += comm.commissionAmount;
      financialSummaries.month.pilotEarnings += comm.pilotEarnings;
      financialSummaries.month.trips += 1;
    }
    if (bDate >= startOfWeek) {
      financialSummaries.week.grossRevenue += comm.fare;
      financialSummaries.week.commission += comm.commissionAmount;
      financialSummaries.week.pilotEarnings += comm.pilotEarnings;
      financialSummaries.week.trips += 1;
    }
    if (bDate >= startOfToday) {
      financialSummaries.today.grossRevenue += comm.fare;
      financialSummaries.today.commission += comm.commissionAmount;
      financialSummaries.today.pilotEarnings += comm.pilotEarnings;
      financialSummaries.today.trips += 1;
    }
  }

  // Format financial summaries
  for (const k of Object.keys(financialSummaries)) {
    financialSummaries[k].grossRevenue = parseFloat(financialSummaries[k].grossRevenue.toFixed(2));
    financialSummaries[k].commission = parseFloat(financialSummaries[k].commission.toFixed(2));
    financialSummaries[k].pilotEarnings = parseFloat(financialSummaries[k].pilotEarnings.toFixed(2));
  }

  // Total Pilot Wallet Balances
  const totalPilotWalletBalances = totalPilotWalletsAgg[0] ? parseFloat(totalPilotWalletsAgg[0].totalBalance.toFixed(2)) : 0.0;

  // Withdrawal Breakdown
  const withdrawalsBreakdown = {
    totalRequests: 0,
    totalRequestedAmount: 0.0,
    pending: 0,
    approved: 0,
    processing: 0,
    completed: 0,
    rejected: 0,
    failed: 0,
    reversed: 0
  };

  for (const w of withdrawalsStatsAgg) {
    const status = (w._id || 'pending').toLowerCase();
    withdrawalsBreakdown.totalRequests += w.count;
    withdrawalsBreakdown.totalRequestedAmount += (w.totalAmount || 0);
    if (withdrawalsBreakdown[status] !== undefined) {
      withdrawalsBreakdown[status] = w.count;
    }
  }

  // Refund / Dispute summary
  let pendingRefundsAmount = 0.0;
  let pendingRefundsCount = 0;
  for (const r of refundsStatsAgg) {
    if (r.status !== 'resolved' && r.status !== 'rejected') {
      pendingRefundsCount += 1;
      pendingRefundsAmount += parseAmount(r.amount);
    }
  }

  // Fleet Availability Ratio
  const fleetAvailabilityRatio = onlinePilotsCount > 0 
    ? Math.round((availablePilotsCount / onlinePilotsCount) * 100) 
    : 0;

  return {
    success: true,
    backendStatus: 'ONLINE',
    lastSyncTime: new Date().toISOString(),
    metrics: {
      // 1. Total registered customers
      totalCustomers,
      // 2. Customers currently online
      onlineCustomers: onlineCustomersCount,
      // 3. Customers with active rides
      activeCustomers: activeCustomersCount,
      // 4. Total registered pilots
      totalPilots,
      // 5. Pilots currently online
      onlinePilots: onlinePilotsCount,
      // 6. Pilots currently busy on rides
      busyPilots: busyPilotsCount,
      // 7. Pilots currently available for bookings
      availablePilots: availablePilotsCount,
      // 8. Active rides with booking IDs and status
      activeRides: activeTripsCount,
      activeRidesList: activeBookingsDocs.map(b => ({
        bookingId: b.bookingId,
        status: b.status,
        vehicle: b.vehicle,
        passengerName: b.passengerName,
        driverName: b.driverName,
        price: b.price,
        createdAt: b.createdAt
      })),
      // 9. Completed rides
      completedRides: completedRidesCount,
      // 10. Cancelled rides with reasons
      cancelledRides: totalCancelledCount,
      cancellationReasons,
      cancellationRate: (completedRidesCount + totalCancelledCount) > 0
        ? parseFloat(((totalCancelledCount / (completedRidesCount + totalCancelledCount)) * 100).toFixed(1))
        : 0.0,
      // 11. Total passenger ride bookings
      passengerBookingsCount,
      // 12. Total parcel and goods delivery bookings
      deliveryBookingsCount,
      // 13. Total customer payments collected
      totalPaymentsCollected: parseFloat(totalPaymentsCollected.toFixed(2)),
      // 14. Total pilot earnings
      totalPilotEarnings: parseFloat(totalPilotEarnings.toFixed(2)),
      // 15. Total platform commission earned
      totalPlatformCommission: parseFloat(totalPlatformCommission.toFixed(2)),
      // 16. Total pilot wallet balances
      totalPilotWalletBalances,
      // 17. Total withdrawal requests
      totalWithdrawalRequests: withdrawalsBreakdown.totalRequests,
      // 18. Status breakdown
      withdrawalsBreakdown,
      // 19. Refunds, payment failures, disputed transactions
      disputes: {
        pendingRefundsCount,
        pendingRefundsAmount: parseFloat(pendingRefundsAmount.toFixed(2)),
        unresolvedComplaintsCount: complaintsCount,
        failedPaymentsCount
      },
      // 20. Daily, weekly, monthly, yearly summaries
      financialSummaries,
      fleetAvailabilityRatio
    }
  };
}

// 6. Pilot Wallets Aggregation (Section 3.A)
async function getPilotWalletsList(User, Booking, WithdrawalRequest) {
  const config = await getActiveCommissionConfig();
  const pilots = await User.find({ role: 'partner' }).sort({ createdAt: -1 });

  const result = [];
  for (const pilot of pilots) {
    const uid = pilot.uid;

    // Fetch pilot's completed bookings
    const completedBookings = await Booking.find({
      $or: [{ driverId: uid }, { driverPhone: pilot.phone }],
      status: 'completed'
    });

    let ridesEarnings = 0.0;
    let deliveryEarnings = 0.0;
    let commissionDeducted = 0.0;

    for (const b of completedBookings) {
      const comm = calculateCommissionForBooking(b, config);
      const isDelivery = b.serviceType === 'delivery' || b.vehicle === 'Mini Truck' || b.vehicle === '6 Ton Truck';
      if (isDelivery) {
        deliveryEarnings += comm.pilotEarnings;
      } else {
        ridesEarnings += comm.pilotEarnings;
      }
      commissionDeducted += comm.commissionAmount;
    }

    // Fetch withdrawals for this pilot
    const withdrawals = await WithdrawalRequest.find({ uid }).sort({ createdAt: -1 });
    let totalWithdrawn = 0.0;
    let pendingWithdrawals = 0.0;
    let failedWithdrawals = 0.0;
    let lastTxnDate = completedBookings.length > 0 ? completedBookings[0].createdAt : pilot.createdAt;

    for (const w of withdrawals) {
      if (w.status === 'completed') {
        totalWithdrawn += (w.amount || 0);
      } else if (w.status === 'pending' || w.status === 'approved' || w.status === 'processing') {
        pendingWithdrawals += (w.amount || 0);
      } else if (w.status === 'failed' || w.status === 'rejected') {
        failedWithdrawals += (w.amount || 0);
      }
      if (w.createdAt && (!lastTxnDate || w.createdAt > lastTxnDate)) {
        lastTxnDate = w.createdAt;
      }
    }

    const availableBalance = typeof pilot.walletBalance === 'number' 
      ? pilot.walletBalance 
      : (typeof pilot.salary === 'number' ? pilot.salary : 0);
    const withdrawableBalance = Math.max(0, availableBalance - pendingWithdrawals);

    const bank = pilot.bankAccount || {};
    const maskedDest = maskDestination(bank.accountNumber, bank.ifsc, bank.upiId);

    result.push({
      pilotId: uid,
      name: pilot.name || 'Pilot Partner',
      phone: pilot.phone || '',
      vehicleType: pilot.vehicleType || 'Bike',
      vehiclePlate: pilot.vehiclePlate || pilot.vehicleNumber || 'Unassigned',
      ridesEarnings: parseFloat(ridesEarnings.toFixed(2)),
      deliveryEarnings: parseFloat(deliveryEarnings.toFixed(2)),
      totalEarnings: parseFloat((ridesEarnings + deliveryEarnings).toFixed(2)),
      commissionDeducted: parseFloat(commissionDeducted.toFixed(2)),
      otherDeductions: pilot.pendingCancellationCharge || 0.0,
      bonuses: 0.0,
      refundAdjustments: 0.0,
      availableBalance: parseFloat(availableBalance.toFixed(2)),
      pendingEarnings: 0.0,
      withdrawableBalance: parseFloat(withdrawableBalance.toFixed(2)),
      totalWithdrawn: parseFloat(totalWithdrawn.toFixed(2)),
      totalPendingWithdrawal: parseFloat(pendingWithdrawals.toFixed(2)),
      totalFailedWithdrawal: parseFloat(failedWithdrawals.toFixed(2)),
      maskedDestination: maskedDest,
      isApproved: !!pilot.approved,
      isBlocked: !!pilot.isBlocked,
      lastTransactionDate: lastTxnDate
    });
  }

  return result;
}

// 7. Withdrawals List with the exact 20 columns (Section 3.B)
async function getWithdrawalsList(WithdrawalRequest, queryParams = {}) {
  const { status, search, limit = 100, page = 1 } = queryParams;
  let filter = {};
  if (status && status !== 'all') {
    filter.status = status;
  }
  if (search) {
    filter.$or = [
      { withdrawalId: { $regex: search, $options: 'i' } },
      { pilotName: { $regex: search, $options: 'i' } },
      { pilotPhone: { $regex: search, $options: 'i' } },
      { uid: { $regex: search, $options: 'i' } },
      { transactionId: { $regex: search, $options: 'i' } }
    ];
  }

  const total = await WithdrawalRequest.countDocuments(filter);
  const skip = (Math.max(1, parseInt(page)) - 1) * parseInt(limit);
  const requests = await WithdrawalRequest.find(filter)
    .sort({ createdAt: -1 })
    .skip(skip)
    .limit(parseInt(limit));

  const items = requests.map(r => {
    const bank = r.bankDetails || {};
    const masked = r.maskedDestination || maskDestination(bank.accountNumber, bank.ifsc, bank.upiId);
    const fee = r.fee || 0.0;
    const netPayable = parseFloat(((r.amount || 0) - fee).toFixed(2));

    return {
      // 1. Transaction ID
      transactionId: r.transactionId || `TXN_${r.withdrawalId}`,
      // 2. Withdrawal Request ID
      withdrawalId: r.withdrawalId,
      // 3. Pilot ID
      pilotId: r.uid,
      // 4. Pilot Name
      pilotName: r.pilotName || 'Pilot Partner',
      // 5. Pilot Mobile Number
      pilotPhone: r.pilotPhone || '',
      // 6. Requested Amount
      requestedAmount: parseFloat((r.amount || 0).toFixed(2)),
      amount: parseFloat((r.amount || 0).toFixed(2)),
      // 7. Applicable Withdrawal Fee
      withdrawalFee: fee,
      // 8. Net Payable Amount
      netPayableAmount: netPayable,
      // 9. Request Date and Time
      requestDate: r.createdAt,
      // 10. Bank Account or UPI Destination (Masked)
      maskedDestination: masked,
      // 11. Payment Gateway or Bank Reference Number
      paymentGatewayRef: r.payoutProviderReference || r.paymentGatewayRef || 'N/A',
      // 12. UTR/RRN or transaction reference
      utr: r.utr || 'Pending settlement',
      // 13. Withdrawal Status
      status: r.status,
      // 14. Admin Approval Status
      approvalStatus: r.approvalStatus || (r.status === 'approved' || r.status === 'completed' || r.status === 'processing' ? 'approved' : (r.status === 'rejected' ? 'rejected' : 'pending')),
      // 15. Approved or Rejected By
      approvedOrRejectedBy: r.approvedBy || r.rejectedBy || 'Pending Review',
      // 16. Processing Date
      processingDate: r.processingDate || (r.status === 'processing' || r.status === 'completed' ? r.updatedAt : null),
      // 17. Actual Settlement Date
      actualSettlementDate: r.settlementDate || (r.status === 'completed' ? r.updatedAt : null),
      // 18. Rejection Reason
      rejectionReason: r.rejectionReason || null,
      // 19. Failure Reason
      failureReason: r.failureReason || null,
      // 20. Admin Remarks & Audit Trail
      adminRemarks: r.adminRemarks || '',
      auditTrail: r.auditTrail || []
    };
  });

  return { total, items, page: parseInt(page), limit: parseInt(limit) };
}

// 8. Process Withdrawal Workflow Action with Safe Double-Entry Ledger (Section 3.C)
async function processWithdrawalAction(models, withdrawalId, action, params, adminUser) {
  const { WithdrawalRequest, User } = models;
  const adminName = adminUser?.name || adminUser?.username || 'Admin';

  const w = await WithdrawalRequest.findOne({ withdrawalId });
  if (!w) {
    throw new Error(`Withdrawal request ${withdrawalId} not found.`);
  }

  const pilot = await User.findOne({ uid: w.uid });
  if (!pilot) {
    throw new Error(`Pilot account for withdrawal ${withdrawalId} not found.`);
  }

  const currentStatus = w.status;
  const amount = w.amount;

  switch (action) {
    case 'approve': {
      if (currentStatus !== 'pending_approval' && currentStatus !== 'pending' && currentStatus !== 'under_review') {
        throw new Error(`Cannot approve withdrawal in '${currentStatus}' status. Must be in Pending Approval.`);
      }

      w.status = 'approved';
      w.approvalStatus = 'approved';
      w.approvedBy = adminName;
      w.approvedAt = new Date();
      w.adminRemarks = params.remarks || 'Approved for payout processing';
      w.auditTrail.push({
        action: 'APPROVED',
        performedBy: adminName,
        timestamp: new Date(),
        notes: params.remarks || 'Request approved by Admin'
      });

      await w.save();
      break;
    }

    case 'reject': {
      if (currentStatus !== 'pending_approval' && currentStatus !== 'pending' && currentStatus !== 'under_review' && currentStatus !== 'approved') {
        throw new Error(`Cannot reject withdrawal in '${currentStatus}' status.`);
      }
      if (!params.reason || !params.reason.trim()) {
        throw new Error('Mandatory rejection reason must be provided when rejecting a withdrawal request.');
      }

      w.status = 'rejected';
      w.approvalStatus = 'rejected';
      w.rejectedBy = adminName;
      w.rejectedAt = new Date();
      w.rejectionReason = params.reason.trim();
      w.adminRemarks = params.remarks || `Rejected: ${params.reason.trim()}`;
      w.auditTrail.push({
        action: 'REJECTED',
        performedBy: adminName,
        timestamp: new Date(),
        notes: `Rejected: ${params.reason.trim()}`
      });

      // Release reserved escrow balance in PilotWallet back to withdrawable balance
      const PilotWallet = models.PilotWallet || mongoose.models.PilotWallet;
      if (PilotWallet) {
        const wallet = await PilotWallet.findOne({ uid: w.uid });
        if (wallet) {
          wallet.reservedBalance = Math.max(0, parseFloat(((wallet.reservedBalance || 0) - amount).toFixed(2)));
          wallet.lastTransactionAt = new Date();
          wallet.updatedAt = new Date();
          await wallet.save();
        }
      }

      // Reverse reserved funds in the ledger
      await FinancialLedger.create({
        ledgerId: `LED_REV_${w.withdrawalId}_${Date.now()}`,
        transactionId: `TXN_REV_${w.withdrawalId}`,
        entryType: 'WITHDRAWAL_REVERSAL',
        withdrawalId: w.withdrawalId,
        pilotId: w.uid,
        debitAccount: 'WITHDRAWAL_ESCROW_PAYABLE',
        creditAccount: 'PILOT_WALLET_LIABILITY',
        amount,
        currency: 'INR',
        referenceNumber: w.withdrawalId,
        description: `Reversal of reserved withdrawal ${w.withdrawalId} upon rejection (${params.reason.trim()})`,
        timestamp: new Date()
      });

      await w.save();
      break;
    }

    case 'initiate_payout': {
      if (currentStatus !== 'approved' && currentStatus !== 'pending_approval' && currentStatus !== 'pending') {
        throw new Error(`Only Approved requests can be initiated for payout. Current status: '${currentStatus}'`);
      }

      w.status = 'processing';
      w.processingDate = new Date();
      w.adminRemarks = params.remarks || 'Payout dispatched to payment provider';
      
      // Attempt RazorpayX Payout if credentials available
      const rzpKeyId = process.env.RAZORPAY_KEY_ID || 'rzp_live_Ta9cOGnIySuBCb';
      const rzpKeySecret = process.env.RAZORPAY_KEY_SECRET || 'c93MSwcWO22lZuC7Xm5jURu0';
      const rzpAcc = process.env.RAZORPAYX_ACCOUNT_NUMBER || 'acc_QSGP6wlx6TBjWX';
      let gatewayRef = params.gatewayRef || `POUT_RZP_${Date.now()}`;

      try {
        const authHeader = 'Basic ' + Buffer.from(rzpKeyId + ':' + rzpKeySecret).toString('base64');
        const bank = w.bankDetails || {};
        const dest = bank.upiId || bank.accountNumber || '';
        if (dest && rzpAcc) {
          // Contact & fund account check
          const contactRes = await fetch('https://api.razorpay.com/v1/contacts', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': authHeader },
            body: JSON.stringify({
              name: w.pilotName || 'Pilot Partner',
              contact: w.pilotPhone || '9876543210',
              type: 'employee',
              reference_id: w.uid
            })
          });
          if (contactRes.ok) {
            const cData = await contactRes.json();
            const fundPayload = dest.includes('@')
              ? { contact_id: cData.id, account_type: 'vpa', vpa: { address: dest } }
              : {
                  contact_id: cData.id,
                  account_type: 'bank_account',
                  bank_account: {
                    name: bank.accountHolderName || w.pilotName || 'Pilot Partner',
                    ifsc: bank.ifsc || 'HDFC0000001',
                    account_number: dest
                  }
                };
            const fRes = await fetch('https://api.razorpay.com/v1/fund_accounts', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json', 'Authorization': authHeader },
              body: JSON.stringify(fundPayload)
            });
            if (fRes.ok) {
              const fData = await fRes.json();
              const pRes = await fetch('https://api.razorpay.com/v1/payouts', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'Authorization': authHeader },
                body: JSON.stringify({
                  account_number: rzpAcc,
                  fund_account_id: fData.id,
                  amount: Math.round(amount * 100),
                  currency: 'INR',
                  mode: dest.includes('@') ? 'UPI' : 'NEFT',
                  purpose: 'payout',
                  queue_if_low_balance: true,
                  reference_id: w.withdrawalId
                })
              });
              if (pRes.ok) {
                const pData = await pRes.json();
                gatewayRef = pData.id || pData.utr || gatewayRef;
                w.utr = pData.utr || '';
              }
            }
          }
        }
      } catch (err) {
        console.warn('[RAZORPAYX PAYOUT NOTICE]:', err.message);
      }

      w.payoutProviderReference = gatewayRef;
      w.paymentGatewayRef = gatewayRef;
      w.auditTrail.push({
        action: 'PAYOUT_INITIATED',
        performedBy: adminName,
        timestamp: new Date(),
        notes: `Payout initiated via RazorpayX. Provider Ref: ${gatewayRef}`
      });
      await w.save();
      break;
    }

    case 'mark_completed': {
      if (currentStatus !== 'processing' && currentStatus !== 'approved') {
        throw new Error(`Cannot mark completed from '${currentStatus}'. Must be in Processing or Approved.`);
      }
      if (!params.utr || !params.utr.trim()) {
        throw new Error('Valid Bank UTR / Transaction Reference is required to verify actual settlement.');
      }

      w.status = 'paid';
      w.approvalStatus = 'approved';
      w.settlementDate = new Date();
      w.utr = params.utr.trim();
      w.payoutProviderReference = params.gatewayRef || w.payoutProviderReference || params.utr.trim();
      w.auditTrail.push({
        action: 'PAID',
        performedBy: adminName,
        timestamp: new Date(),
        notes: `Payout verified and settled. UTR: ${w.utr}`
      });

      // Atomically settle funds in PilotWallet: deduct from availableBalance and add to totalWithdrawn
      const PilotWallet = models.PilotWallet || mongoose.models.PilotWallet;
      if (PilotWallet) {
        const wallet = await PilotWallet.findOne({ uid: w.uid });
        if (wallet) {
          wallet.availableBalance = parseFloat(Math.max(0, (wallet.availableBalance || 0) - amount).toFixed(2));
          wallet.reservedBalance = Math.max(0, parseFloat(((wallet.reservedBalance || 0) - amount).toFixed(2)));
          wallet.totalWithdrawn = parseFloat(((wallet.totalWithdrawn || 0) + amount).toFixed(2));
          wallet.lastTransactionAt = new Date();
          wallet.updatedAt = new Date();
          await wallet.save();
        }
      }

      // Synchronize pilot user model
      pilot.walletBalance = parseFloat(Math.max(0, (pilot.walletBalance || 0) - amount).toFixed(2));
      if (typeof pilot.salary === 'number') {
        pilot.salary = parseFloat(Math.max(0, pilot.salary - amount).toFixed(2));
      }
      await pilot.save();

      // Post completed payout ledger entry
      await FinancialLedger.create({
        ledgerId: `LED_CMP_${w.withdrawalId}_${Date.now()}`,
        transactionId: `TXN_CMP_${w.withdrawalId}`,
        entryType: 'WITHDRAWAL_PAYOUT',
        withdrawalId: w.withdrawalId,
        pilotId: w.uid,
        debitAccount: 'WITHDRAWAL_ESCROW_PAYABLE',
        creditAccount: 'COMPANY_BANK_ACCOUNT',
        amount,
        currency: 'INR',
        referenceNumber: w.utr,
        description: `Completed bank settlement for pilot payout ${w.withdrawalId} (UTR: ${w.utr})`,
        timestamp: new Date()
      });

      await w.save();
      break;
    }

    case 'mark_failed': {
      if (currentStatus !== 'processing' && currentStatus !== 'approved') {
        throw new Error(`Only Processing or Approved requests can be marked as failed. Current status: '${currentStatus}'`);
      }

      w.status = 'failed';
      w.failureReason = params.reason || 'Payout transfer failed by bank/provider';
      w.auditTrail.push({
        action: 'PAYOUT_FAILED',
        performedBy: adminName,
        timestamp: new Date(),
        notes: `Failed: ${w.failureReason}`
      });

      // Release reserved escrow balance in PilotWallet back to withdrawable balance
      const PilotWallet = models.PilotWallet || mongoose.models.PilotWallet;
      if (PilotWallet) {
        const wallet = await PilotWallet.findOne({ uid: w.uid });
        if (wallet) {
          wallet.reservedBalance = Math.max(0, parseFloat(((wallet.reservedBalance || 0) - amount).toFixed(2)));
          wallet.lastTransactionAt = new Date();
          wallet.updatedAt = new Date();
          await wallet.save();
        }
      }

      // Reverse reserved escrow balance back to pilot wallet liability
      await FinancialLedger.create({
        ledgerId: `LED_FAIL_${w.withdrawalId}_${Date.now()}`,
        transactionId: `TXN_FAIL_${w.withdrawalId}`,
        entryType: 'WITHDRAWAL_REVERSAL',
        withdrawalId: w.withdrawalId,
        pilotId: w.uid,
        debitAccount: 'WITHDRAWAL_ESCROW_PAYABLE',
        creditAccount: 'PILOT_WALLET_LIABILITY',
        amount,
        currency: 'INR',
        referenceNumber: w.withdrawalId,
        description: `Reversal of failed withdrawal ${w.withdrawalId} (${w.failureReason})`,
        timestamp: new Date()
      });

      await w.save();
      break;
    }

    case 'retry': {
      if (currentStatus !== 'failed') {
        throw new Error(`Only Failed requests can be retried. Current status: '${currentStatus}'`);
      }

      w.status = 'approved';
      w.failureReason = '';
      w.auditTrail.push({
        action: 'RETRY_INITIATED',
        performedBy: adminName,
        timestamp: new Date(),
        notes: 'Retry initiated by Admin'
      });

      // Re-reserve funds
      await FinancialLedger.create({
        ledgerId: `LED_RTRY_${w.withdrawalId}_${Date.now()}`,
        transactionId: `TXN_RTRY_${w.withdrawalId}`,
        entryType: 'WITHDRAWAL_RESERVE',
        withdrawalId: w.withdrawalId,
        pilotId: w.uid,
        debitAccount: 'PILOT_WALLET_LIABILITY',
        creditAccount: 'WITHDRAWAL_ESCROW_PAYABLE',
        amount,
        currency: 'INR',
        referenceNumber: w.withdrawalId,
        description: `Re-reserving funds for retry of withdrawal ${w.withdrawalId}`,
        timestamp: new Date()
      });

      await w.save();
      break;
    }

    default:
      throw new Error(`Unsupported withdrawal action: ${action}`);
  }

  return { success: true, withdrawal: w };
}

// 9. Founder Financial Dashboard Summary (Section 4.C)
async function getFounderFinancialSummary(models, period = 'all') {
  const { Booking, User, WithdrawalRequest, Refund, Payment } = models;
  const config = await getActiveCommissionConfig();

  const now = new Date();
  let dateFilter = {};
  if (period === 'today') {
    dateFilter = { createdAt: { $gte: new Date(now.getFullYear(), now.getMonth(), now.getDate()) } };
  } else if (period === 'week') {
    const d = new Date(now);
    d.setDate(now.getDate() - 7);
    dateFilter = { createdAt: { $gte: d } };
  } else if (period === 'month') {
    dateFilter = { createdAt: { $gte: new Date(now.getFullYear(), now.getMonth(), 1) } };
  } else if (period === 'quarter') {
    const qMonth = Math.floor(now.getMonth() / 3) * 3;
    dateFilter = { createdAt: { $gte: new Date(now.getFullYear(), qMonth, 1) } };
  } else if (period === 'year') {
    dateFilter = { createdAt: { $gte: new Date(now.getFullYear(), 0, 1) } };
  }

  // Completed bookings in period
  const completedBookings = await Booking.find({ status: 'completed', ...dateFilter });
  const allBookings = await Booking.find(dateFilter);

  let grossBookingValue = 0.0;
  for (const b of allBookings) {
    grossBookingValue += parseAmount(b.price);
  }

  let completedBookingValue = 0.0;
  let grossCommissionEarned = 0.0;
  let commissionCollectedSettled = 0.0;
  let commissionPendingSettlement = 0.0;
  let pilotEarningsPayable = 0.0;
  let paymentGatewayFees = 0.0;
  let statutoryTaxGst = 0.0;

  for (const b of completedBookings) {
    const comm = calculateCommissionForBooking(b, config);
    completedBookingValue += comm.fare;
    grossCommissionEarned += comm.commissionAmount;
    pilotEarningsPayable += comm.pilotEarnings;
    paymentGatewayFees += comm.gatewayFee;
    statutoryTaxGst += comm.taxAmount;

    if (comm.settlementStatus === 'SETTLED') {
      commissionCollectedSettled += comm.commissionAmount;
    } else {
      commissionPendingSettlement += comm.commissionAmount;
    }
  }

  // Pilot wallet and withdrawal liabilities (current snapshot)
  const walletLiabilityAgg = await User.aggregate([
    { $match: { role: 'partner' } },
    { $group: { _id: null, total: { $sum: '$walletBalance' } } }
  ]);
  const pilotWalletLiabilities = walletLiabilityAgg[0] ? walletLiabilityAgg[0].total : 0.0;

  const pendingWithdrawalsAgg = await WithdrawalRequest.aggregate([
    { $match: { status: { $in: ['pending', 'approved', 'processing'] } } },
    { $group: { _id: null, total: { $sum: '$amount' } } }
  ]);
  const outstandingWithdrawalLiabilities = pendingWithdrawalsAgg[0] ? pendingWithdrawalsAgg[0].total : 0.0;

  const completedPayoutsAgg = await WithdrawalRequest.aggregate([
    { $match: { status: 'completed', ...dateFilter } },
    { $group: { _id: null, total: { $sum: '$amount' } } }
  ]);
  const pilotEarningsAlreadyPaid = completedPayoutsAgg[0] ? completedPayoutsAgg[0].total : 0.0;

  // Refunds and chargebacks
  const processedRefunds = await Refund.find({ status: 'processed', ...dateFilter });
  let refundsAndChargebacks = 0.0;
  for (const r of processedRefunds) {
    refundsAndChargebacks += parseAmount(r.amount);
  }

  // Unreconciled / Failed Payments
  const failedPaymentsAgg = await Payment.aggregate([
    { $match: { status: 'failed', ...dateFilter } },
    { $group: { _id: null, total: { $sum: '$amount' } } }
  ]);
  const unreconciledPaymentTransactions = failedPaymentsAgg[0] ? (failedPaymentsAgg[0].total / 100) : 0.0;

  // Actual cash received by company (Settled Commissions minus gateway fees minus paid distributions)
  const founderDistributionsAgg = await FounderPayout.aggregate([
    { $match: { status: 'SETTLED', ...dateFilter } },
    { $group: { _id: null, total: { $sum: '$amount' } } }
  ]);
  const totalFounderDistributions = founderDistributionsAgg[0] ? founderDistributionsAgg[0].total : 0.0;

  const totalActualCashReceived = Math.max(0, commissionCollectedSettled - paymentGatewayFees);
  const authorizedOperatingExpenses = 0.0;
  const netOperatingIncome = Math.max(0, grossCommissionEarned - statutoryTaxGst - paymentGatewayFees - authorizedOperatingExpenses);

  return {
    period,
    totals: {
      // 1. Total customer collections
      totalCustomerCollections: parseFloat(completedBookingValue.toFixed(2)),
      // 2. Gross booking value
      grossBookingValue: parseFloat(grossBookingValue.toFixed(2)),
      // 3. Completed and eligible booking value
      completedBookingValue: parseFloat(completedBookingValue.toFixed(2)),
      // 4. Gross platform commission earned
      grossCommissionEarned: parseFloat(grossCommissionEarned.toFixed(2)),
      // 5. Commission collected and settled
      commissionCollectedSettled: parseFloat(commissionCollectedSettled.toFixed(2)),
      // 6. Commission pending settlement
      commissionPendingSettlement: parseFloat(commissionPendingSettlement.toFixed(2)),
      // 7. Pilot earnings payable
      pilotEarningsPayable: parseFloat(pilotEarningsPayable.toFixed(2)),
      // 8. Pilot earnings already paid
      pilotEarningsAlreadyPaid: parseFloat(pilotEarningsAlreadyPaid.toFixed(2)),
      // 9. Pilot wallet liabilities
      pilotWalletLiabilities: parseFloat(pilotWalletLiabilities.toFixed(2)),
      // 10. Outstanding withdrawal liabilities
      outstandingWithdrawalLiabilities: parseFloat(outstandingWithdrawalLiabilities.toFixed(2)),
      // 11. Refunds and chargebacks
      refundsAndChargebacks: parseFloat(refundsAndChargebacks.toFixed(2)),
      // 12. Payment gateway fees
      paymentGatewayFees: parseFloat(paymentGatewayFees.toFixed(2)),
      // 13. Applicable taxes and statutory liabilities
      statutoryTaxGst: parseFloat(statutoryTaxGst.toFixed(2)),
      // 14. Authorized operating expenses
      authorizedOperatingExpenses: parseFloat(authorizedOperatingExpenses.toFixed(2)),
      // 15. Net operating income
      netOperatingIncome: parseFloat(netOperatingIncome.toFixed(2)),
      // 16. Unreconciled payment transactions
      unreconciledPaymentTransactions: parseFloat(unreconciledPaymentTransactions.toFixed(2)),
      // 17. Unsettled payment gateway transactions
      unsettledGatewayTransactions: parseFloat(commissionPendingSettlement.toFixed(2)),
      // 18. Total actual cash received by company
      totalActualCashReceived: parseFloat(totalActualCashReceived.toFixed(2)),
      totalFounderDistributions: parseFloat(totalFounderDistributions.toFixed(2))
    }
  };
}

module.exports = {
  maskDestination,
  parseAmount,
  getActiveCommissionConfig,
  calculateCommissionForBooking,
  recordBookingSettlementLedger,
  backfillHistoricalLedgerAndCommissions,
  getRealtimeKPIs,
  getPilotWalletsList,
  getWithdrawalsList,
  processWithdrawalAction,
  getFounderFinancialSummary
};
