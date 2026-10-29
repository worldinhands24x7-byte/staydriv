const mongoose = require('mongoose');

// Authoritative Duty and Guarantee Messages
const DUTY_ON_MESSAGE = "Your duty is ON. You are eligible to receive bookings, subject to availability and vehicle eligibility.";
const DUTY_OFF_MESSAGE = "Your duty is currently OFF. Please contact the Admin to enable booking access.";
const EARNINGS_GUARANTEE_STATEMENT = "100% booking earnings – no StayDriv commission deduction.";

// Helper to determine the start and end of today in local/IST time
function getTodayBounds() {
  const now = new Date();
  const start = new Date(now.getFullYear(), now.month || now.getMonth(), now.getDate(), 0, 0, 0, 0);
  const end = new Date(now.getFullYear(), now.month || now.getMonth(), now.getDate(), 23, 59, 59, 999);
  return { start, end };
}

/**
 * Evaluates whether a pilot is eligible to receive ride and food-delivery bookings
 * according to the strict rules of the ₹20 Daily Plan:
 * 1. Payment successful + plan valid + pilot approved + admin duty ON = ELIGIBLE
 * 2. Payment pending or failed = NOT ELIGIBLE
 * 3. Daily plan expired = NOT ELIGIBLE until payment is renewed successfully
 * 4. Admin booking duty OFF / disabled = NOT ELIGIBLE, even if the daily fee is paid
 * 5. Pilot or vehicle verification not approved or blocked = NOT ELIGIBLE
 * 6. Once eligible, the pilot receives 100% of eligible ride and food-delivery earnings
 * 7. A pilot must never be assigned a booking if the eligibility checks fail.
 */
function checkPilotDailyBookingEligibility(pilot) {
  if (!pilot) {
    return {
      eligible: false,
      reason: 'Pilot record not found',
      dutyStatus: 'DUTY OFF',
      dutyMessage: DUTY_OFF_MESSAGE,
      bookingAccess: 'disabled',
      planStatus: 'none',
      statement: EARNINGS_GUARANTEE_STATEMENT
    };
  }

  // 1. Role verification
  if (pilot.role && pilot.role !== 'partner') {
    return {
      eligible: false,
      reason: 'User is not a registered StayDriv partner/pilot',
      dutyStatus: 'DUTY OFF',
      dutyMessage: DUTY_OFF_MESSAGE,
      bookingAccess: 'disabled',
      planStatus: 'none',
      statement: EARNINGS_GUARANTEE_STATEMENT
    };
  }

  // 2. Blocked / Suspended status check
  if (pilot.isBlocked) {
    return {
      eligible: false,
      reason: `Pilot account is suspended: ${pilot.blockReason || 'Contact support'}`,
      dutyStatus: 'DUTY OFF',
      dutyMessage: DUTY_OFF_MESSAGE,
      bookingAccess: 'disabled',
      planStatus: 'suspended',
      statement: EARNINGS_GUARANTEE_STATEMENT
    };
  }

  // 3. Document / Account approval check
  const isApproved = pilot.status === 'approved' ||
                     pilot.partnerStatus === 'approved' ||
                     pilot.partnerApprovalStatus === 'approved' ||
                     pilot.approved === true ||
                     pilot.isApproved === true;
  if (!isApproved) {
    return {
      eligible: false,
      reason: 'Pilot registration documents are pending admin approval',
      dutyStatus: 'DUTY OFF',
      dutyMessage: DUTY_OFF_MESSAGE,
      bookingAccess: 'disabled',
      planStatus: 'pending_approval',
      statement: EARNINGS_GUARANTEE_STATEMENT
    };
  }

  // 4. Daily Plan Payment & Expiry verification
  const dailyPlan = pilot.dailyPlan || {};
  const planStatus = dailyPlan.planStatus || 'none';
  const expiresAt = dailyPlan.expiresAt ? new Date(dailyPlan.expiresAt) : null;
  const now = new Date();

  const isAccessEnabled = Boolean(
    pilot.bookingAccess?.enabled === true || 
    pilot.bookingAccess?.status === 'enabled' || 
    pilot.adminBookingEnabled === true
  );
  const currentAccessStatus = isAccessEnabled ? 'enabled' : 'disabled';
  const rawDisabledReason = pilot.bookingAccess?.disabledReason || '';
  const cleanDisabledReason = (isAccessEnabled || /eligible for 100% earnings/i.test(rawDisabledReason))
    ? ''
    : rawDisabledReason;

  if (planStatus !== 'paid') {
    return {
      eligible: false,
      reason: planStatus === 'expired' 
        ? 'Daily ₹20 plan has expired. Please renew to receive bookings.' 
        : 'Daily ₹20 plan fee has not been paid. Pay ₹20 to activate 100% earnings.',
      dutyStatus: 'DUTY OFF',
      dutyMessage: DUTY_OFF_MESSAGE,
      bookingAccess: currentAccessStatus,
      bookingAccessStatus: currentAccessStatus,
      bookingAccessEnabled: isAccessEnabled,
      bookingAccessReason: cleanDisabledReason,
      disabledReason: cleanDisabledReason,
      planStatus: planStatus === 'expired' ? 'expired' : 'none',
      statement: EARNINGS_GUARANTEE_STATEMENT
    };
  }

  if (!expiresAt || now >= expiresAt) {
    return {
      eligible: false,
      reason: 'Daily ₹20 plan has expired. Please renew to activate bookings.',
      dutyStatus: 'DUTY OFF',
      dutyMessage: DUTY_OFF_MESSAGE,
      bookingAccess: currentAccessStatus,
      bookingAccessStatus: currentAccessStatus,
      bookingAccessEnabled: isAccessEnabled,
      bookingAccessReason: cleanDisabledReason,
      disabledReason: cleanDisabledReason,
      planStatus: 'expired',
      statement: EARNINGS_GUARANTEE_STATEMENT
    };
  }

  // 5. Admin-Controlled Booking Access & Pilot Duty Status check (DUTY ON / DUTY OFF)
  const isBookingEnabled = isAccessEnabled && pilot.dutyStatus !== 'OFF' && pilot.dutyStatus !== 'DUTY OFF';
  if (!isBookingEnabled) {
    const disabledReason = cleanDisabledReason || DUTY_OFF_MESSAGE;
    return {
      eligible: false,
      reason: disabledReason,
      dutyStatus: 'DUTY OFF',
      dutyMessage: DUTY_OFF_MESSAGE,
      bookingAccess: currentAccessStatus,
      bookingAccessStatus: currentAccessStatus,
      bookingAccessEnabled: isAccessEnabled,
      bookingAccessReason: cleanDisabledReason,
      disabledReason: cleanDisabledReason,
      planStatus: 'paid',
      statement: EARNINGS_GUARANTEE_STATEMENT,
      expiresAt
    };
  }

  // All mandatory eligibility conditions satisfied
  return {
    eligible: true,
    reason: 'Daily plan active (100% earnings)',
    dutyStatus: 'DUTY ON',
    dutyMessage: DUTY_ON_MESSAGE,
    bookingAccess: 'enabled',
    bookingAccessStatus: 'enabled',
    bookingAccessEnabled: true,
    bookingAccessReason: '',
    disabledReason: '',
    planStatus: 'paid',
    statement: EARNINGS_GUARANTEE_STATEMENT,
    expiresAt
  };
}

/**
 * Checks if pilot is on an active, paid ₹20 daily plan for 100% earnings calculation
 */
function isPilotOnActiveDailyPlan(pilot) {
  if (!pilot) return false;
  const dailyPlan = pilot.dailyPlan;
  if (!dailyPlan) return false;
  if (dailyPlan.planStatus !== 'paid') return false;
  if (!dailyPlan.expiresAt) return false;
  return new Date() < new Date(dailyPlan.expiresAt);
}

/**
 * Get comprehensive daily plan status & today's earnings for pilot console
 */
async function getPilotDailyPlanStatus(pilotUidOrPhone, models) {
  const { User, Booking, FoodOrder, PilotDailyPlanPayment } = models;
  
  // Find pilot
  let pilot = await User.findOne({ uid: pilotUidOrPhone });
  if (!pilot && String(pilotUidOrPhone).includes('_')) {
    const clean = String(pilotUidOrPhone).replace(/\D/g, '').slice(-10);
    if (clean) pilot = await User.findOne({ phone: clean, role: 'partner' }) || await User.findOne({ phone: clean });
  }
  if (!pilot) {
    const clean = String(pilotUidOrPhone).replace(/\D/g, '').slice(-10);
    if (clean) pilot = await User.findOne({ phone: clean, role: 'partner' }) || await User.findOne({ phone: clean });
  }

  if (!pilot) {
    return {
      success: false,
      message: 'Pilot record not found'
    };
  }

  const pUid = pilot.uid;
  const pPhone = pilot.phone || (pilot.uid ? pilot.uid.replace(/\D/g, '').slice(-10) : '');
  const now = new Date();

  // Find latest payment record
  let latestPayment = null;
  if (PilotDailyPlanPayment) {
    latestPayment = await PilotDailyPlanPayment.findOne({
      $or: [{ pilotId: pUid }, { pilotPhone: pPhone }]
    }).sort({ paidAt: -1, createdAt: -1 });
  }

  // Determine plan status
  let planStatus = pilot.dailyPlan?.planStatus || (latestPayment ? latestPayment.status || latestPayment.paymentStatus : 'none');
  let paidAt = pilot.dailyPlan?.paidAt || latestPayment?.paidAt || null;
  let expiresAt = pilot.dailyPlan?.expiresAt || latestPayment?.expiresAt || null;

  if (planStatus === 'paid' && expiresAt && now >= new Date(expiresAt)) {
    planStatus = 'expired';
    if (pilot.dailyPlan) {
      pilot.dailyPlan.planStatus = 'expired';
      await User.updateOne({ _id: pilot._id }, { $set: { 'dailyPlan.planStatus': 'expired' } }).catch(() => {});
    }
    if (latestPayment && latestPayment.paymentStatus === 'paid') {
      latestPayment.paymentStatus = 'expired';
      await latestPayment.save().catch(() => {});
    }
  }

  const transactionId = pilot.dailyPlan?.transactionId || latestPayment?.transactionId || '';
  const bookingAccessStatus = (pilot.bookingAccess?.enabled === true || pilot.bookingAccess?.status === 'enabled' || pilot.adminBookingEnabled === true) 
    ? 'enabled' 
    : 'disabled';
  const rawBookingReason = pilot.bookingAccess?.disabledReason || '';
  const bookingAccessReason = (bookingAccessStatus === 'enabled' || /eligible for 100% earnings/i.test(rawBookingReason))
    ? ''
    : rawBookingReason;

  // Calculate Today's Ride Earnings (00:00 to 23:59:59)
  const { start, end } = getTodayBounds();
  let todayRideEarnings = 0.0;
  if (Booking) {
    const todayRides = await Booking.find({
      $or: [{ driverId: pUid }, { driverId: pPhone }, { driverPhone: pPhone }],
      status: 'completed',
      createdAt: { $gte: start, $lte: end }
    }).lean();

    for (const r of todayRides) {
      // 100% of fare is credited to pilot on ₹20 daily plan
      const fare = parseFloat(String(r.price || '0').replace(/[^0-9.]/g, '')) || 0.0;
      todayRideEarnings += (typeof r.pilotEarnings === 'number' ? r.pilotEarnings : fare);
    }
  }

  // Calculate Today's Food Delivery Earnings
  let todayFoodEarnings = 0.0;
  if (FoodOrder) {
    const todayOrders = await FoodOrder.find({
      $or: [{ deliveryPartnerId: pUid }, { deliveryPartnerPhone: pPhone }],
      orderStatus: 'delivered',
      createdAt: { $gte: start, $lte: end }
    }).lean();

    for (const o of todayOrders) {
      const fee = Number(o.pilotDeliveryEarnings || o.pilot_delivery_earnings || o.baseDeliveryFee || o.originalDeliveryFee || 0);
      todayFoodEarnings += fee;
    }
  }

  const totalEarningsToday = parseFloat((todayRideEarnings + todayFoodEarnings).toFixed(2));

  const isDutyActive = bookingAccessStatus === 'enabled' && planStatus === 'paid' && pilot.dutyStatus !== 'OFF' && pilot.dutyStatus !== 'DUTY OFF';
  const dutyStatus = isDutyActive ? 'DUTY ON' : 'DUTY OFF';
  const dutyMessage = isDutyActive ? DUTY_ON_MESSAGE : (bookingAccessReason || DUTY_OFF_MESSAGE);

  return {
    success: true,
    pilotId: pUid,
    pilotName: pilot.name || 'Pilot Partner',
    pilotPhone: pPhone,
    vehicleType: pilot.vehicleType || 'Bike',
    dailyPlanPrice: 20.0,
    planStatus,
    paidAt,
    expiresAt,
    transactionId,
    dutyStatus,
    pilotDutyStatus: isDutyActive ? 'ON' : 'OFF',
    dutyMessage,
    dutyOnMessage: DUTY_ON_MESSAGE,
    dutyOffMessage: DUTY_OFF_MESSAGE,
    bookingAccessStatus,
    bookingAccessEnabled: (bookingAccessStatus === 'enabled'),
    adminBookingEnabled: (bookingAccessStatus === 'enabled'),
    bookingAccessReason,
    todayRideEarnings: parseFloat(todayRideEarnings.toFixed(2)),
    todayFoodEarnings: parseFloat(todayFoodEarnings.toFixed(2)),
    totalEarningsToday,
    commissionRate: 0.0,
    statement: EARNINGS_GUARANTEE_STATEMENT,
    commissionDeductionNotice: EARNINGS_GUARANTEE_STATEMENT
  };
}

/**
 * Record pilot's successful ₹20 daily fee payment
 */
async function recordPilotDailyPayment(payload, models, io) {
  const { User, PilotDailyPlanPayment, FinancialLedger } = models;
  const { pilotUidOrPhone, paymentMethod = 'UPI', transactionId, gatewayPaymentId, gatewayOrderId, adminOverride = false } = payload;

  // Resolve pilot user
  let pilot = await User.findOne({ uid: pilotUidOrPhone });
  if (!pilot) {
    const clean = String(pilotUidOrPhone).replace(/\D/g, '').slice(-10);
    if (clean) pilot = await User.findOne({ phone: clean, role: 'partner' }) || await User.findOne({ phone: clean });
  }

  if (!pilot) {
    throw new Error('Pilot partner account not found');
  }

  const pUid = pilot.uid || `pilot_${pilot.phone}`;
  const pPhone = pilot.phone || String(pilotUidOrPhone).replace(/\D/g, '').slice(-10);
  const now = new Date();

  // Idempotency check: prevent duplicate charges for the same valid payment period
  if (pilot.dailyPlan && pilot.dailyPlan.planStatus === 'paid' && pilot.dailyPlan.expiresAt) {
    const currentExpiry = new Date(pilot.dailyPlan.expiresAt);
    if (now < currentExpiry && !adminOverride) {
      console.log(`[DAILY PLAN IDEMPOTENCY] Pilot ${pUid} already has active plan until ${currentExpiry.toISOString()}`);
      return {
        success: true,
        message: 'Daily plan is already active for this period.',
        isDuplicate: true,
        dailyPlan: pilot.dailyPlan
      };
    }
  }

  const txnId = transactionId || `TXN_DP_${Date.now()}_${Math.floor(1000 + Math.random() * 9000)}`;
  const expiresAt = new Date(now.getTime() + 24 * 60 * 60 * 1000); // Exactly 24-hour period

  // Save to separate PilotDailyPlanPayment register
  let paymentRecord = null;
  if (PilotDailyPlanPayment) {
    paymentRecord = await PilotDailyPlanPayment.create({
      pilotId: pUid,
      pilotName: pilot.name || 'Pilot Partner',
      pilotPhone: pPhone,
      vehicleType: pilot.vehicleType || 'Bike',
      amount: 20,
      currency: 'INR',
      paymentStatus: 'paid',
      transactionId: txnId,
      gatewayPaymentId: gatewayPaymentId || '',
      gatewayOrderId: gatewayOrderId || '',
      paymentMethod,
      paidAt: now,
      expiresAt,
      bookingAccessStatus: (pilot.bookingAccess?.enabled === true) ? 'enabled' : 'disabled',
      adminStartStopStatus: (pilot.bookingAccess?.enabled === true) ? 'START' : 'NONE',
      adminReason: 'Daily ₹20 fee paid successfully',
      auditHistory: [{
        action: 'PAYMENT_RECEIVED',
        changedBy: 'PILOT_APP',
        reason: 'Successful ₹20 daily fee payment',
        timestamp: now
      }],
      notes: '₹20 Daily Plan - 100% Ride & Food Earnings'
    });
  }

  // Update pilot User model
  pilot.dailyPlan = {
    planStatus: 'paid',
    paidAt: now,
    expiresAt,
    amount: 20,
    transactionId: txnId,
    gatewayPaymentId: gatewayPaymentId || '',
    lastPaymentId: txnId
  };
  await pilot.save();

  // Record in FinancialLedger under separate daily-plan revenue account
  if (FinancialLedger) {
    await FinancialLedger.create({
      ledgerId: `LED_DP_${txnId}_${Date.now()}`,
      transactionId: txnId,
      entryType: 'PILOT_DAILY_PLAN_FEE',
      sourceBookingId: txnId,
      pilotId: pUid,
      customerId: 'PILOT_PARTNER',
      debitAccount: 'PILOT_DAILY_FEE_COLLECTION',
      creditAccount: 'FOUNDER_DAILY_PLAN_REVENUE',
      amount: 20.0,
      currency: 'INR',
      status: 'SETTLED',
      referenceNumber: txnId,
      description: `Daily ₹20 pilot plan fee paid by ${pilot.name} (${pPhone}). Guaranteed 100% booking earnings.`,
      timestamp: now
    }).catch(err => console.error('[DAILY PLAN LEDGER ERROR]:', err.message));
  }

  // Real-time broadcasts
  if (io) {
    const payloadOut = {
      pilotId: pUid,
      phone: pPhone,
      planStatus: 'paid',
      paidAt: now.toISOString(),
      expiresAt: expiresAt.toISOString(),
      transactionId: txnId,
      dailyPlanPrice: 20.0,
      bookingAccess: pilot.bookingAccess?.status || 'disabled'
    };

    io.emit('pilot_daily_plan_updated', payloadOut);
    io.to('admin_tracking').emit('admin_daily_plan_payment', {
      ...payloadOut,
      paymentRecord
    });
  }

  console.log(`[DAILY PLAN PAID] Pilot ${pUid} (${pPhone}) paid ₹20 fee. Plan valid until ${expiresAt.toISOString()}`);

  return {
    success: true,
    message: 'Daily ₹20 plan activated successfully for 24 hours with 100% earnings guaranteed.',
    dailyPlan: pilot.dailyPlan,
    paymentRecord
  };
}

/**
 * Admin Start/Stop Booking Access Control
/**
 * Admin DUTY ON / DUTY OFF Control
 * The Admin Console has exclusive authority to change duty status for pilots on the ₹20 plan.
 */
async function updateAdminBookingAccess({ pilotId, action, reason, adminId, adminName }, models, io) {
  const { User, PilotDailyPlanPayment } = models;
  
  if (!pilotId) {
    throw new Error('Pilot identifier is required');
  }

  const rawAction = String(action || '').trim().toUpperCase();
  const isEnable = rawAction === 'ENABLE' || rawAction === 'ENABLED' || rawAction === 'ENABLE_ACCESS' || rawAction === 'DUTY_ON' || rawAction === 'START' || rawAction === 'ON';
  const isDisable = rawAction === 'DISABLE' || rawAction === 'DISABLED' || rawAction === 'DISABLE_ACCESS' || rawAction === 'DUTY_OFF' || rawAction === 'STOP' || rawAction === 'OFF';

  if (!isEnable && !isDisable) {
    throw new Error("Invalid action. Must be 'ENABLE' or 'DISABLE'");
  }

  // Disabling booking access requires a mandatory reason
  if (isDisable && (!reason || !reason.trim())) {
    throw new Error('A reason is mandatory when disabling pilot booking access.');
  }

  // Find pilot by UID, MongoDB ObjectId, or Phone number
  let pilot = null;
  if (pilotId) {
    pilot = await User.findOne({ uid: pilotId });
    if (!pilot && mongoose.isValidObjectId(pilotId)) {
      pilot = await User.findById(pilotId);
    }
    if (!pilot) {
      const clean = String(pilotId).replace(/\D/g, '').slice(-10);
      if (clean && clean.length === 10) {
        pilot = await User.findOne({ phone: clean, role: { $in: ['partner', 'pilot', 'driver'] } }) || await User.findOne({ phone: clean });
      }
    }
  }

  if (!pilot) {
    throw new Error(`Pilot with ID '${pilotId}' not found.`);
  }

  const now = new Date();
  const operator = adminName || adminId || 'StayDriv Admin';

  if (isEnable) {
    // 1. Lift block/suspension when Administrator enables booking access
    if (pilot.isBlocked) {
      pilot.isBlocked = false;
      pilot.blockReason = '';
      pilot.blockedAt = null;
      if (pilot.status === 'suspended' || pilot.status === 'blocked') {
        pilot.status = 'approved';
      }
      if (pilot.approved === false || pilot.isApproved === false) {
        pilot.approved = true;
        pilot.isApproved = true;
      }
    }

    // Set Booking Access to Enabled
    pilot.bookingAccess = {
      status: 'enabled',
      enabled: true,
      disabledReason: '',
      updatedBy: operator,
      updatedAt: now,
      history: [
        ...(pilot.bookingAccess?.history || []),
        { action: 'BOOKING_ACCESS_ENABLED', adminId: operator, reason: reason || 'Booking access enabled by admin', timestamp: now }
      ]
    };
    pilot.adminBookingEnabled = true;

    // Grant or renew active 24-hr daily plan if missing or expired so pilot is immediately dispatchable
    const expires24h = new Date(now.getTime() + 24 * 60 * 60 * 1000);
    const dailyPlan = pilot.dailyPlan || {};
    const isPlanPaid = dailyPlan.planStatus === 'paid' && dailyPlan.expiresAt && now < new Date(dailyPlan.expiresAt);
    if (!isPlanPaid) {
      pilot.dailyPlan = {
        planStatus: 'paid',
        paidAt: now,
        expiresAt: expires24h,
        amount: 20,
        transactionId: `TXN-ADM-${Date.now().toString().slice(-6)}`,
        gatewayPaymentId: 'ADMIN_OVERRIDE'
      };
    }

    // Admin enables booking access permission. Pilot Duty status remains human-controlled.
    if (pilot.dutyStatus === 'ON') {
      pilot.online = true;
    }
  } else {
    // DISABLE BOOKING ACCESS / DUTY OFF
    pilot.bookingAccess = {
      status: 'disabled',
      enabled: false,
      disabledReason: reason.trim() || 'Duty switched OFF by Admin',
      updatedBy: operator,
      updatedAt: now,
      history: [
        ...(pilot.bookingAccess?.history || []),
        { action: 'BOOKING_ACCESS_DISABLED', adminId: operator, reason: reason.trim() || 'Duty switched OFF by Admin', timestamp: now }
      ]
    };
    pilot.adminBookingEnabled = false;
    pilot.dutyStatus = 'OFF';
    pilot.online = false;
  }

  if (typeof pilot.markModified === 'function') {
    pilot.markModified('bookingAccess');
    pilot.markModified('dailyPlan');
  }
  if (typeof pilot.save === 'function') {
    await pilot.save();
  }
  if (User && typeof User.updateOne === 'function' && pilot._id) {
    await User.updateOne(
      { _id: pilot._id },
      {
        $set: {
          bookingAccess: pilot.bookingAccess,
          adminBookingEnabled: pilot.adminBookingEnabled,
          dailyPlan: pilot.dailyPlan,
          dutyStatus: pilot.dutyStatus,
          online: pilot.online
        }
      }
    );
  }

  const isAccessEnabled = pilot.bookingAccess.status === 'enabled';
  const isDutyActive = isAccessEnabled && (pilot.dutyStatus === 'ON' || pilot.dutyStatus === 'DUTY ON');

  // Update latest payment records in the register
  if (PilotDailyPlanPayment) {
    await PilotDailyPlanPayment.updateMany(
      {
        $or: [{ pilotId: pilot.uid }, { pilotPhone: pilot.phone }],
        paymentStatus: 'paid'
      },
      {
        $set: {
          bookingAccessStatus: pilot.bookingAccess.status,
          dutyStatus: isDutyActive ? 'DUTY ON' : 'DUTY OFF',
          adminStartStopStatus: isAccessEnabled ? 'ENABLED' : 'DISABLED',
          adminReason: isAccessEnabled ? (reason || 'Booking access enabled by admin') : reason.trim(),
          adminUpdatedBy: operator,
          adminUpdatedAt: now
        },
        $push: {
          auditHistory: {
            action: isAccessEnabled ? 'BOOKING_ACCESS_ENABLED' : 'BOOKING_ACCESS_DISABLED',
            changedBy: operator,
            reason: isAccessEnabled ? (reason || 'Booking access enabled by admin') : reason.trim(),
            timestamp: now
          }
        }
      }
    );
  }

  // Update in-memory online dispatch driver status if pilot is connected
  try {
    if (typeof global !== 'undefined' && global.onlineDrivers) {
      for (const [sId, d] of Object.entries(global.onlineDrivers)) {
        if (d.uid === pilot.uid || (pilot.phone && String(d.uid).includes(pilot.phone))) {
          d.bookingAccessEnabled = isAccessEnabled;
          d.dutyStatus = isDutyActive ? 'DUTY ON' : 'DUTY OFF';
          if (!isAccessEnabled) {
            delete global.onlineDrivers[sId];
          }
        }
      }
    }
  } catch (_) {}

  // Real-time broadcast to Pilot Console and Admin Console
  if (io) {
    const eventPayload = {
      uid: pilot.uid,
      pilotId: pilot.uid,
      phone: pilot.phone,
      pilotName: pilot.name,
      bookingAccessStatus: pilot.bookingAccess.status,
      bookingAccessEnabled: isAccessEnabled,
      bookingAccessReason: pilot.bookingAccess.disabledReason || '',
      dutyStatus: isDutyActive ? 'DUTY ON' : 'DUTY OFF',
      pilotDutyStatus: isDutyActive ? 'ON' : 'OFF',
      dutyMessage: isDutyActive ? DUTY_ON_MESSAGE : DUTY_OFF_MESSAGE,
      bookingAccess: pilot.bookingAccess,
      action: isAccessEnabled ? 'BOOKING_ACCESS_ENABLED' : 'BOOKING_ACCESS_DISABLED',
      reason: isAccessEnabled ? '' : (pilot.bookingAccess.disabledReason || reason.trim()),
      updatedBy: operator,
      statement: EARNINGS_GUARANTEE_STATEMENT,
      timestamp: now.toISOString()
    };

    io.emit('pilot_booking_access_changed', eventPayload);
    io.emit('pilot_booking_access_status', eventPayload);
    io.emit('pilot_duty_status_changed', eventPayload);
    io.to('admin_tracking').emit('admin_pilot_booking_access_updated', eventPayload);
  }

  console.log(`[ADMIN BOOKING ACCESS] Pilot ${pilot.uid} access set to ${isAccessEnabled ? 'ENABLED' : 'DISABLED'} by ${operator}. Reason: ${reason || 'N/A'}`);

  return {
    success: true,
    bookingAccessStatus: pilot.bookingAccess.status,
    bookingAccessEnabled: isAccessEnabled,
    bookingAccessReason: isAccessEnabled ? '' : (pilot.bookingAccess.disabledReason || reason.trim()),
    dutyStatus: isDutyActive ? 'DUTY ON' : 'DUTY OFF',
    pilotDutyStatus: isDutyActive ? 'ON' : 'OFF',
    dutyMessage: isDutyActive ? DUTY_ON_MESSAGE : DUTY_OFF_MESSAGE,
    message: isAccessEnabled 
      ? `Booking access enabled for pilot ${pilot.name}. Pilot may now switch duty ON.` 
      : `Booking access disabled for pilot ${pilot.name}. Reason: ${reason}`,
    bookingAccess: pilot.bookingAccess
  };
}

/**
 * Pilot-controlled DUTY ON / DUTY OFF toggle
 * Subject to admin booking permission and daily plan validity
 */
async function togglePilotDuty(payload, models, io) {
  const { User, PilotDailyPlanPayment } = models;
  const { dutyStatus } = payload;
  const targetUid = payload.uid || payload.pilotId;

  let pilot = await User.findOne({ uid: targetUid });
  if (!pilot) {
    const clean = String(targetUid).replace(/\D/g, '').slice(-10);
    if (clean) pilot = await User.findOne({ phone: clean, role: 'partner' }) || await User.findOne({ phone: clean });
  }

  if (!pilot) {
    throw new Error(`Pilot '${targetUid}' not found in database.`);
  }

  const normDuty = String(dutyStatus || '').toUpperCase();
  const isTurnOn = normDuty === 'ON' || normDuty === 'DUTY ON';
  const now = new Date();

  if (isTurnOn) {
    // 1. Verification status check
    const isApproved = pilot.status === 'approved' ||
                       pilot.partnerStatus === 'approved' ||
                       pilot.approved === true ||
                       pilot.isApproved === true;
    if (!isApproved) {
      throw new Error(`Cannot turn Duty ON: Pilot account is pending document verification.`);
    }

    // 2. Disciplinary status check
    if (pilot.isBlocked || pilot.status === 'suspended') {
      throw new Error(`Cannot turn Duty ON: Pilot account is currently suspended.`);
    }

    // 3. Admin booking access check
    const bookingAccess = pilot.bookingAccess || {};
    const isBookingEnabled = bookingAccess.enabled === true || bookingAccess.status === 'enabled' || pilot.adminBookingEnabled === true;
    if (!isBookingEnabled) {
      const rawReason = bookingAccess.disabledReason || '';
      const reason = (!rawReason || /eligible for 100% earnings/i.test(rawReason))
        ? 'Your booking access is currently disabled by the Admin.'
        : rawReason;
      throw new Error(`Your booking access is currently disabled by the Admin: ${reason}`);
    }

    // 4. Daily ₹20 plan check
    let dailyPlan = pilot.dailyPlan || {};
    let isPaid = dailyPlan.planStatus === 'paid';
    let expiresAt = dailyPlan.expiresAt ? new Date(dailyPlan.expiresAt) : null;

    if ((!isPaid || !expiresAt || now >= expiresAt) && PilotDailyPlanPayment) {
      const latestPayment = await PilotDailyPlanPayment.findOne({
        $or: [{ pilotId: pilot.uid }, { pilotPhone: pilot.phone }],
        $or: [{ status: { $in: ['paid', 'PAID'] } }, { paymentStatus: { $in: ['paid', 'PAID'] } }]
      }).sort({ paidAt: -1, createdAt: -1 });
      if (latestPayment && latestPayment.expiresAt && now < new Date(latestPayment.expiresAt)) {
        isPaid = true;
        expiresAt = new Date(latestPayment.expiresAt);
      }
    }

    if (!isPaid || !expiresAt || now >= expiresAt) {
      throw new Error(`Daily ₹20 plan is required or expired. Please pay ₹20 daily plan to activate duty.`);
    }

    // 5. Vehicle assignment check
    const hasVehicle = pilot.vehicleType || pilot.vehicle?.type || pilot.selectedVehicle || pilot.vehicle;
    if (!hasVehicle) {
      throw new Error(`Cannot turn Duty ON: Required vehicle details are incomplete.`);
    }

    pilot.dutyStatus = 'ON';
    pilot.online = true;
    pilot.lastActive = now;
  } else {
    // Turning Duty OFF
    pilot.dutyStatus = 'OFF';
    pilot.online = false;
    pilot.lastActive = now;
  }

  if (typeof pilot.markModified === 'function') {
    pilot.markModified('dutyStatus');
  }
  if (typeof pilot.save === 'function') {
    await pilot.save();
  }
  if (User && typeof User.updateOne === 'function' && pilot._id) {
    await User.updateOne(
      { _id: pilot._id },
      {
        $set: {
          dutyStatus: pilot.dutyStatus,
          online: pilot.online,
          lastActive: now
        }
      }
    );
  }

  // Update in-memory online dispatch driver status if pilot is connected
  try {
    if (typeof global !== 'undefined' && global.onlineDrivers) {
      for (const [sId, d] of Object.entries(global.onlineDrivers)) {
        if (d.uid === pilot.uid || (pilot.phone && String(d.uid).includes(pilot.phone))) {
          d.dutyStatus = isTurnOn ? 'ON' : 'OFF';
          d.bookingAccessEnabled = isTurnOn;
          if (!isTurnOn) {
            delete global.onlineDrivers[sId];
          }
        }
      }
    }
  } catch (_) {}

  // Emit real-time events
  const isAccessCurrentlyEnabled = Boolean(
    pilot.bookingAccess?.enabled === true ||
    pilot.bookingAccess?.status === 'enabled' ||
    pilot.adminBookingEnabled === true
  );
  const rawReason = pilot.bookingAccess?.disabledReason || '';
  const cleanReason = (isAccessCurrentlyEnabled || /eligible for 100% earnings/i.test(rawReason))
    ? ''
    : rawReason;

  if (io) {
    const eventPayload = {
      uid: pilot.uid,
      pilotId: pilot.uid,
      pilotPhone: pilot.phone,
      dutyStatus: isTurnOn ? 'DUTY ON' : 'DUTY OFF',
      pilotDutyStatus: isTurnOn ? 'ON' : 'OFF',
      online: isTurnOn,
      bookingAccessStatus: isAccessCurrentlyEnabled ? 'enabled' : 'disabled',
      bookingAccessEnabled: isAccessCurrentlyEnabled,
      bookingAccessReason: cleanReason,
      reason: cleanReason,
      dutyMessage: isTurnOn ? DUTY_ON_MESSAGE : DUTY_OFF_MESSAGE,
      statement: EARNINGS_GUARANTEE_STATEMENT,
      timestamp: now.toISOString()
    };
    io.emit('pilot_duty_status_changed', eventPayload);
    io.emit('driver_status_changed', {
      uid: pilot.uid,
      online: isTurnOn,
      dutyStatus: isTurnOn ? 'ON' : 'OFF',
      bookingAccessEnabled: isAccessCurrentlyEnabled,
      bookingAccessStatus: isAccessCurrentlyEnabled ? 'enabled' : 'disabled',
      bookingAccessReason: cleanReason
    });
    io.to('admin_tracking').emit('admin_pilot_duty_status_updated', eventPayload);
  }

  return {
    success: true,
    dutyStatus: isTurnOn ? 'DUTY ON' : 'DUTY OFF',
    pilotDutyStatus: isTurnOn ? 'ON' : 'OFF',
    online: isTurnOn,
    bookingAccessStatus: isAccessCurrentlyEnabled ? 'enabled' : 'disabled',
    bookingAccessEnabled: isAccessCurrentlyEnabled,
    bookingAccessReason: cleanReason,
    dutyMessage: isTurnOn ? DUTY_ON_MESSAGE : DUTY_OFF_MESSAGE,
    statement: EARNINGS_GUARANTEE_STATEMENT
  };
}

module.exports = {
  DUTY_ON_MESSAGE,
  DUTY_OFF_MESSAGE,
  EARNINGS_GUARANTEE_STATEMENT,
  checkPilotDailyBookingEligibility,
  isPilotOnActiveDailyPlan,
  getPilotDailyPlanStatus,
  recordPilotDailyPayment,
  updateAdminBookingAccess,
  togglePilotDuty,
  getTodayBounds
};

