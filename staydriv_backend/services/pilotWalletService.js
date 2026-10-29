const mongoose = require('mongoose');
const PilotWallet = require('../models/PilotWallet');
const FinancialLedger = require('../models/FinancialLedger');

// Helper to mask account number or UPI ID
function maskTargetAccount(accountNumber, ifsc, upiId) {
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

// 1. Get or Create Pilot Wallet
async function getOrCreatePilotWallet(uid, pilotData = {}) {
  let wallet = await PilotWallet.findOne({ uid });
  if (!wallet && uid && uid.startsWith('mock_uid_')) {
    let phone = uid.replace('mock_uid_', '');
    if (phone.endsWith('_pilot')) phone = phone.replace('_pilot', '');
    if (phone) wallet = await PilotWallet.findOne({ phone });
  }
  if (!wallet && pilotData.phone) {
    const cleanPhone = String(pilotData.phone).replace(/\D/g, '').slice(-10);
    if (cleanPhone) wallet = await PilotWallet.findOne({ phone: cleanPhone });
  }

  if (!wallet) {
    const initialBalance = typeof pilotData.walletBalance === 'number'
      ? pilotData.walletBalance
      : (typeof pilotData.salary === 'number' ? pilotData.salary : 0.0);
    const initialEarnings = typeof pilotData.totalLifetimeEarnings === 'number'
      ? pilotData.totalLifetimeEarnings
      : 0.0;

    wallet = await PilotWallet.findOneAndUpdate(
      { uid },
      {
        $setOnInsert: {
          uid,
          phone: pilotData.phone || '',
          pilotName: pilotData.name || 'Pilot Partner',
          availableBalance: initialBalance,
          pendingSettlement: 0.0,
          totalEarnings: initialEarnings,
          totalWithdrawn: 0.0,
          bankAccount: pilotData.bankAccount || {
            accountHolderName: pilotData.name || '',
            accountNumber: '',
            maskedAccountNumber: '',
            ifsc: '',
            bankName: '',
            upiId: 'pilot@okaxis',
            isVerified: true
          }
        }
      },
      { new: true, upsert: true }
    );
  }
  return wallet;
}

// 2. Automatically Credit Ride Earnings to Pilot Wallet (85% net fare, pending 24-hr settlement)
async function creditRideEarnings(booking, User, io) {
  if (!booking) return null;

  const bId = booking.bookingId || String(booking._id);
  // Strict Idempotency Check: prevent duplicate credits
  if (booking.financialsProcessed === true) {
    console.log(`[WALLET IDEMPOTENCY] Booking ${bId} financials already processed. Skipping duplicate credit.`);
    return null;
  }

  const existingLedger = await FinancialLedger.findOne({
    sourceBookingId: bId,
    entryType: 'PILOT_FARE_EARNING'
  });
  if (existingLedger) {
    console.log(`[WALLET IDEMPOTENCY] FinancialLedger entry already exists for booking ${bId}. Skipping.`);
    booking.financialsProcessed = true;
    await booking.save();
    return null;
  }

  const priceStr = String(booking.price || '₹0').replace(/[^0-9.]/g, '');
  const fareVal = parseFloat(priceStr) || 0.0;
  if (fareVal <= 0) return null;

  const driverId = booking.driverId || '';

  if (!driverId) {
    console.warn(`[WALLET WARNING] Completed booking ${bId} has no driverId.`);
    return null;
  }

  // Find pilot user in MongoDB
  let pilot = await User.findOne({ uid: driverId });
  if (!pilot && driverId.startsWith('mock_uid_')) {
    let phone = driverId.replace('mock_uid_', '');
    if (phone.endsWith('_pilot')) phone = phone.replace('_pilot', '');
    pilot = await User.findOne({ phone, role: 'partner' });
  }

  // Check if pilot is on active ₹20 daily plan (100% ride & food earnings guarantee without StayDriv commission)
  const isDailyPlanPaid = pilot?.dailyPlan?.planStatus === 'paid' && 
                          pilot?.dailyPlan?.expiresAt && 
                          (new Date() < new Date(pilot.dailyPlan.expiresAt) || (booking.createdAt && new Date(booking.createdAt) < new Date(pilot.dailyPlan.expiresAt)));

  const commission = isDailyPlanPaid ? 0.0 : parseFloat((fareVal * 0.15).toFixed(2));
  const pilotEarnings = isDailyPlanPaid ? fareVal : parseFloat((fareVal * 0.85).toFixed(2));

  // Get or initialize Pilot Wallet
  const wallet = await getOrCreatePilotWallet(driverId, pilot || {});

  // 24-Hour Settlement Window Calculation
  const completedAt = booking.updatedAt || new Date();
  const settlementEligibleAt = new Date(completedAt.getTime() + 24 * 60 * 60 * 1000);

  // Credit into Wallet: mark as pending settlement
  wallet.pendingSettlement = parseFloat((wallet.pendingSettlement + pilotEarnings).toFixed(2));
  wallet.totalEarnings = parseFloat((wallet.totalEarnings + pilotEarnings).toFixed(2));
  wallet.lastTransactionAt = new Date();
  wallet.updatedAt = new Date();
  await wallet.save();

  // Synchronize pilot user model
  if (pilot) {
    pilot.totalLifetimeEarnings = wallet.totalEarnings;
    pilot.walletBalance = wallet.availableBalance;
    pilot.salary = wallet.availableBalance;
    await pilot.save();
  }

  // Mark Booking as processed and pending settlement
  booking.financialsProcessed = true;
  booking.earningsCreditedAt = new Date();
  booking.pilotEarnings = pilotEarnings;
  booking.platformCommission = commission;
  booking.finalFare = fareVal;
  booking.settlementStatus = 'pending_settlement';
  booking.settlementEligibleAt = settlementEligibleAt;
  await booking.save();

  // Double-Entry Financial Ledger
  const timestamp = new Date();
  const ledgerDesc = isDailyPlanPaid
    ? `Pilot 100% net earnings (₹${fareVal}) on ₹20 Daily Plan for booking ${bId} pending 24-hr settlement`
    : `Pilot net earnings (85% of ₹${fareVal}) for booking ${bId} pending 24-hr settlement`;

  await FinancialLedger.create({
    ledgerId: `LED_EARN_${bId}_${Date.now()}`,
    transactionId: `TXN_EARN_${bId}`,
    entryType: 'PILOT_FARE_EARNING',
    sourceBookingId: bId,
    pilotId: driverId,
    customerId: booking.passengerId || 'CUSTOMER',
    debitAccount: 'CUSTOMER_FARE_COLLECTIONS',
    creditAccount: 'PILOT_PENDING_SETTLEMENT',
    amount: pilotEarnings,
    currency: 'INR',
    status: 'PENDING_SETTLEMENT',
    referenceNumber: bId,
    description: ledgerDesc,
    timestamp
  });

  // Credit Admin Platform Commission (only if commission > 0)
  let admin = await User.findOne({ role: 'admin' });
  if (admin && commission > 0) {
    admin.salary = parseFloat(((admin.salary || 0) + commission).toFixed(2));
    await admin.save();
  }

  console.log(`[WALLET CREDIT] Booking ${bId}: Credited ₹${pilotEarnings} to pilot ${driverId} (100% Plan: ${isDailyPlanPaid}). Commission: ₹${commission}`);

  // Real-time Socket.IO Broadcast
  if (io) {
    io.emit('pilot_wallet_updated', {
      uid: driverId,
      bookingId: bId,
      creditedAmount: pilotEarnings,
      availableBalance: wallet.availableBalance,
      pendingSettlement: wallet.pendingSettlement,
      totalEarnings: wallet.totalEarnings,
      settlementEligibleAt: settlementEligibleAt.toISOString()
    });

    io.emit('admin_financial_update', {
      type: 'RIDE_EARNING_CREDITED',
      bookingId: bId,
      fare: fareVal,
      pilotEarnings,
      commission
    });
  }

  return {
    fare: fareVal,
    pilotEarnings,
    commission,
    settlementEligibleAt,
    wallet
  };
}

// 2b. Automatically Credit Food Delivery Earnings to Pilot Wallet (100% of deliveryFee, pending 24-hr settlement)
async function creditFoodDeliveryEarnings(order, User, io) {
  if (!order) return null;

  const oId = order.orderId || String(order._id);
  // Strict Idempotency Check: prevent duplicate credits
  if (order.financialsProcessed === true) {
    console.log(`[WALLET IDEMPOTENCY] FoodOrder ${oId} financials already processed. Skipping duplicate credit.`);
    return null;
  }

  const existingLedger = await FinancialLedger.findOne({
    sourceBookingId: oId,
    entryType: { $in: ['PILOT_FOOD_DELIVERY_EARNING', 'PLATFORM_FUNDED_DELIVERY_EXPENSE'] }
  });
  if (existingLedger) {
    console.log(`[WALLET IDEMPOTENCY] FinancialLedger entry already exists for food order ${oId}. Skipping.`);
    order.financialsProcessed = true;
    await order.save();
    return null;
  }

  // Extract full pilot delivery earning (guaranteeing pilot never bears loss on Platinum free deliveries)
  let feeVal = 0;
  for (const candidate of [
    order.pilotDeliveryEarnings,
    order.pilot_delivery_earnings,
    order.pilotEarnings,
    order.originalDeliveryFee,
    order.baseDeliveryFee,
    order.pilotDeliveryFee,
    order.staydrivFundedDeliveryAmount
  ]) {
    const num = parseFloat(candidate);
    if (!isNaN(num) && num > 0) {
      feeVal = num;
      break;
    }
  }
  if (feeVal <= 0) {
    const dFee = parseFloat(order.deliveryFee);
    feeVal = (!isNaN(dFee) && dFee > 0) ? dFee : 30.0;
  }
  const driverId = order.deliveryPartnerId || '';

  if (!driverId) {
    console.warn(`[WALLET WARNING] Completed food order ${oId} has no deliveryPartnerId.`);
    return null;
  }

  const UserModel = (typeof User !== 'undefined' && User) || mongoose.models.User || (mongoose.models && mongoose.models.User ? mongoose.model('User') : mongoose.model('User', new mongoose.Schema({}, { strict: false }), 'users'));

  // Find pilot user in MongoDB
  let pilot = await UserModel.findOne({ uid: driverId });
  if (!pilot && driverId.startsWith('mock_uid_')) {
    let phone = driverId.replace('mock_uid_', '');
    if (phone.endsWith('_pilot')) phone = phone.replace('_pilot', '');
    pilot = await UserModel.findOne({ phone, role: 'partner' });
  }
  if (!pilot) {
    const cleanPhone = driverId.replace(/\D/g, '').slice(-10);
    if (cleanPhone) {
      pilot = await UserModel.findOne({ phone: new RegExp(cleanPhone + '$'), role: 'partner' });
    }
  }

  // Get or initialize Pilot Wallet
  const wallet = await getOrCreatePilotWallet(driverId, pilot || {});

  // 24-Hour Settlement Window Calculation
  const completedAt = order.deliveredAt || new Date();
  const settlementEligibleAt = new Date(completedAt.getTime() + 24 * 60 * 60 * 1000);

  // Credit into Wallet: mark as pending settlement
  wallet.pendingSettlement = parseFloat((wallet.pendingSettlement + feeVal).toFixed(2));
  wallet.totalEarnings = parseFloat((wallet.totalEarnings + feeVal).toFixed(2));
  wallet.lastTransactionAt = new Date();
  wallet.updatedAt = new Date();
  await wallet.save();

  // Synchronize pilot user model
  if (pilot) {
    pilot.totalLifetimeEarnings = wallet.totalEarnings;
    pilot.walletBalance = wallet.availableBalance;
    pilot.salary = wallet.availableBalance;
    await pilot.save();
  }

  // Mark FoodOrder as processed and pending settlement
  order.financialsProcessed = true;
  order.earningsCreditedAt = new Date();
  order.pilotEarnings = feeVal;
  order.settlementStatus = 'pending_settlement';
  order.settlementEligibleAt = settlementEligibleAt;
  await order.save();

  // Determine whether delivery was platform-funded by StayDriv (Platinum free delivery)
  const isPlatformFunded = order.isPlatinumDelivery === true ||
                           order.fundingSource === 'staydriv' ||
                           (typeof order.staydrivFundedDeliveryAmount === 'number' && order.staydrivFundedDeliveryAmount > 0);

  const entryType = isPlatformFunded ? 'PLATFORM_FUNDED_DELIVERY_EXPENSE' : 'PILOT_FOOD_DELIVERY_EARNING';
  const debitAccount = isPlatformFunded ? 'STAYDRIV_PLATFORM_DELIVERY_EXPENSE' : 'CUSTOMER_FOOD_DELIVERY_COLLECTIONS';
  const ledgerDescription = isPlatformFunded
    ? `StayDriv platform-funded free delivery for Platinum member (${order.customerName || 'Customer'}). Full fare ₹${feeVal} credited to pilot for order ${oId}`
    : `Pilot net food delivery earnings (₹${feeVal}) for order ${oId} pending 24-hr settlement`;

  // Double-Entry Financial Ledger
  const timestamp = new Date();
  await FinancialLedger.create({
    ledgerId: `LED_FOOD_${oId}_${Date.now()}`,
    transactionId: `TXN_FOOD_${oId}`,
    entryType,
    sourceBookingId: oId,
    pilotId: driverId,
    customerId: order.customerId || 'CUSTOMER',
    debitAccount,
    creditAccount: 'PILOT_PENDING_SETTLEMENT',
    amount: feeVal,
    currency: 'INR',
    status: 'PENDING_SETTLEMENT',
    referenceNumber: oId,
    description: ledgerDescription,
    auditDetails: {
      orderId: oId,
      customerId: order.customerId,
      membershipId: order.membershipId || null,
      isPlatinumDelivery: Boolean(order.isPlatinumDelivery),
      fundingSource: isPlatformFunded ? 'staydriv' : 'customer',
      originalDeliveryFee: order.originalDeliveryFee || feeVal,
      customerDeliveryFee: order.customerDeliveryFee || 0,
      staydrivFundedDeliveryAmount: isPlatformFunded ? feeVal : 0,
      pilotEarnings: feeVal
    },
    timestamp
  });

  console.log(`[WALLET CREDIT] FoodOrder ${oId}: Credited full fare ₹${feeVal} to pilot ${driverId} (Funding: ${isPlatformFunded ? 'StayDriv Platform' : 'Customer'}).`);

  // Real-time Socket.IO Broadcast
  if (io) {
    io.emit('pilot_wallet_updated', {
      uid: driverId,
      orderId: oId,
      creditedAmount: feeVal,
      availableBalance: wallet.availableBalance,
      pendingSettlement: wallet.pendingSettlement,
      totalEarnings: wallet.totalEarnings,
      settlementEligibleAt: settlementEligibleAt.toISOString()
    });

    io.emit('admin_financial_update', {
      type: 'FOOD_DELIVERY_EARNING',
      orderId: oId,
      pilotId: driverId,
      deliveryEarnings: feeVal,
      timestamp
    });
  }

  return { success: true, creditedAmount: feeVal, wallet };
}

// 3. Process 24-Hour Eligible Settlements (Scheduler function)
async function process24HourPendingSettlements(Booking, User, WithdrawalRequest, io) {
  const now = new Date();
  // Find all completed bookings with pending settlement whose 24-hr window has passed
  const eligibleBookings = await Booking.find({
    status: 'completed',
    settlementStatus: 'pending_settlement',
    settlementEligibleAt: { $lte: now },
    refunded: { $ne: true },
    disputed: { $ne: true }
  });

  if (!eligibleBookings || eligibleBookings.length === 0) {
    return { count: 0, totalSettled: 0.0 };
  }

  console.log(`[24H SETTLEMENT] Found ${eligibleBookings.length} eligible bookings ready for 24-hour bank settlement.`);

  let totalSettled = 0.0;
  let settledCount = 0;

  for (const b of eligibleBookings) {
    try {
      const bId = b.bookingId || String(b._id);
      const earnings = b.pilotEarnings || parseFloat((parseFloat(String(b.price || '0').replace(/[^0-9.]/g, '')) * 0.85).toFixed(2));
      const driverId = b.driverId;

      if (!driverId || earnings <= 0) continue;

      let pilot = await User.findOne({ uid: driverId });
      if (!pilot && driverId.startsWith('mock_uid_')) {
        let phone = driverId.replace('mock_uid_', '');
        if (phone.endsWith('_pilot')) phone = phone.replace('_pilot', '');
        pilot = await User.findOne({ phone, role: 'partner' });
      }

      const wallet = await getOrCreatePilotWallet(driverId, pilot || {});

      // Deduct from pending settlement and add to available balance (or direct payout)
      wallet.pendingSettlement = Math.max(0, parseFloat((wallet.pendingSettlement - earnings).toFixed(2)));
      wallet.availableBalance = parseFloat((wallet.availableBalance + earnings).toFixed(2));
      wallet.updatedAt = new Date();
      await wallet.save();

      if (pilot) {
        pilot.walletBalance = wallet.availableBalance;
        pilot.salary = wallet.availableBalance;
        await pilot.save();
      }

      // Mark Booking as Paid / Settled
      b.settlementStatus = 'paid';
      b.settledAt = new Date();
      const settlementRef = `STAYDRIV_SETTLE_${bId}_${Date.now()}`;
      b.payoutReference = settlementRef;
      await b.save();

      // Create Payout/Settlement Ledger Record
      await FinancialLedger.create({
        ledgerId: `LED_SETTLE_${bId}_${Date.now()}`,
        transactionId: `TXN_SETTLE_${bId}`,
        entryType: 'PILOT_WALLET_CREDIT',
        sourceBookingId: bId,
        pilotId: driverId,
        debitAccount: 'PILOT_PENDING_SETTLEMENT',
        creditAccount: 'PILOT_WALLET_LIABILITY',
        amount: earnings,
        currency: 'INR',
        status: 'POSTED',
        referenceNumber: settlementRef,
        description: `24-hour settlement completed for booking ${bId}. Transferred ₹${earnings} to available wallet balance.`,
        timestamp: new Date()
      });

      totalSettled += earnings;
      settledCount++;

      console.log(`[24H SETTLEMENT] Settled booking ${bId}: ₹${earnings} credited to available balance for pilot ${driverId}`);

      if (io) {
        io.emit('pilot_settlement_completed', {
          uid: driverId,
          bookingId: bId,
          settledAmount: earnings,
          availableBalance: wallet.availableBalance,
          pendingSettlement: wallet.pendingSettlement,
          payoutReference: settlementRef,
          settledAt: b.settledAt
        });
      }
    } catch (err) {
      console.error(`[24H SETTLEMENT ERROR] Error settling booking ${b.bookingId}:`, err.message);
    }
  }

  // Also settle completed food orders whose 24-hr settlement window has passed
  try {
    const FoodOrderModel = mongoose.models.FoodOrder || require('../models/FoodOrder');
    const eligibleFoodOrders = await FoodOrderModel.find({
      orderStatus: 'delivered',
      settlementStatus: 'pending_settlement',
      settlementEligibleAt: { $lte: now }
    });

    if (eligibleFoodOrders && eligibleFoodOrders.length > 0) {
      console.log(`[24H SETTLEMENT] Found ${eligibleFoodOrders.length} eligible food deliveries ready for 24-hour bank settlement.`);
      for (const o of eligibleFoodOrders) {
        try {
          const oId = o.orderId || String(o._id);
          const earnings = parseFloat(o.pilotEarnings || o.originalDeliveryFee || o.deliveryFee) || 40.0;
          const driverId = o.deliveryPartnerId;

          if (!driverId || earnings <= 0) continue;

          let pilot = await User.findOne({ uid: driverId });
          if (!pilot && driverId.startsWith('mock_uid_')) {
            let phone = driverId.replace('mock_uid_', '');
            if (phone.endsWith('_pilot')) phone = phone.replace('_pilot', '');
            pilot = await User.findOne({ phone, role: 'partner' });
          }

          const wallet = await getOrCreatePilotWallet(driverId, pilot || {});

          wallet.pendingSettlement = Math.max(0, parseFloat((wallet.pendingSettlement - earnings).toFixed(2)));
          wallet.availableBalance = parseFloat((wallet.availableBalance + earnings).toFixed(2));
          wallet.updatedAt = new Date();
          await wallet.save();

          if (pilot) {
            pilot.walletBalance = wallet.availableBalance;
            pilot.salary = wallet.availableBalance;
            await pilot.save();
          }

          o.settlementStatus = 'paid';
          o.settledAt = new Date();
          const settlementRef = `STAYDRIV_FOOD_SETTLE_${oId}_${Date.now()}`;
          o.payoutReference = settlementRef;
          await o.save();

          await FinancialLedger.create({
            ledgerId: `LED_FOOD_SETTLE_${oId}_${Date.now()}`,
            transactionId: `TXN_FOOD_SETTLE_${oId}`,
            entryType: 'PILOT_WALLET_CREDIT',
            sourceBookingId: oId,
            pilotId: driverId,
            debitAccount: 'PILOT_PENDING_SETTLEMENT',
            creditAccount: 'PILOT_WALLET_LIABILITY',
            amount: earnings,
            currency: 'INR',
            status: 'POSTED',
            referenceNumber: settlementRef,
            description: `Settlement completed for food delivery ${oId}. Transferred ₹${earnings} to available wallet balance.`,
            timestamp: new Date()
          });

          totalSettled += earnings;
          settledCount++;

          console.log(`[24H SETTLEMENT] Settled food order ${oId}: ₹${earnings} credited to available balance for pilot ${driverId}`);

          if (io) {
            io.emit('pilot_settlement_completed', {
              uid: driverId,
              orderId: oId,
              settledAmount: earnings,
              availableBalance: wallet.availableBalance,
              pendingSettlement: wallet.pendingSettlement,
              payoutReference: settlementRef,
              settledAt: o.settledAt
            });
          }
        } catch (foodSettleErr) {
          console.error(`[24H SETTLEMENT ERROR] Error settling food order ${o.orderId}:`, foodSettleErr.message);
        }
      }
    }
  } catch (foodFindErr) {
    console.warn('[24H SETTLEMENT] Food order settlement check skipped:', foodFindErr.message);
  }

  return { count: settledCount, totalSettled: parseFloat(totalSettled.toFixed(2)) };
}

// 4. Request Instant Cashout / Advance Withdrawal (Atomic Escrow Reservation & Pending Approval)
async function requestWithdrawal({
  uid,
  amount,
  targetAccount,
  idempotencyKey,
  User,
  WithdrawalRequest,
  Payout,
  razorpayKeyId,
  razorpayKeySecret,
  razorpayxAccountNumber
}) {
  const amtVal = parseFloat(amount);
  if (isNaN(amtVal) || amtVal <= 0) {
    throw new Error('Invalid withdrawal amount. Must be greater than zero.');
  }

  // Strict Idempotency Check: prevent duplicate requests on network retries or multi-taps
  if (idempotencyKey && WithdrawalRequest) {
    const existing = await WithdrawalRequest.findOne({ idempotencyKey });
    if (existing) {
      console.log(`[WITHDRAWAL IDEMPOTENCY] Returning existing request ${existing.withdrawalId} for key ${idempotencyKey}`);
      let normStatus = (existing.status || 'pending_approval').toLowerCase();
      if (normStatus === 'pending') normStatus = 'pending_approval';
      if (normStatus === 'completed') normStatus = 'paid';
      return {
        success: true,
        payoutId: existing.withdrawalId,
        withdrawalId: existing.withdrawalId,
        amount: existing.amount,
        status: normStatus,
        targetAccount: existing.maskedDestination,
        message: `Withdrawal request already registered (Ref: ${existing.withdrawalId}). Status: ${normStatus}.`,
        idempotent: true
      };
    }
  }

  // Find Pilot
  let pilot = await User.findOne({ uid });
  if (!pilot && uid.startsWith('mock_uid_')) {
    let phone = uid.replace('mock_uid_', '');
    if (phone.endsWith('_pilot')) phone = phone.replace('_pilot', '');
    pilot = await User.findOne({ phone, role: 'partner' });
  }
  if (!pilot) {
    let digits = (uid || '').replace(/\D/g, '');
    if (digits.length >= 10) {
      digits = digits.slice(-10);
      pilot = await User.findOne({ $or: [{ phone: digits }, { phoneNumber: digits }, { driverPhone: digits }, { uid: `pilot_${digits}` }] });
    }
  }

  const wallet = await getOrCreatePilotWallet(uid, pilot || {});

  // Calculate withdrawable balance = availableBalance - reservedBalance
  const currentReserved = Number(wallet.reservedBalance || 0);
  const currentAvailable = Number(wallet.availableBalance || 0);
  const withdrawable = Math.max(0, parseFloat((currentAvailable - currentReserved).toFixed(2)));

  if (withdrawable < amtVal) {
    throw new Error(`Insufficient withdrawable balance. Withdrawable Now: ₹${withdrawable.toFixed(2)}, Requested: ₹${amtVal.toFixed(2)}`);
  }

  // Determine Target Bank Account / UPI
  const destination = (targetAccount || '').trim() ||
    wallet.bankAccount?.upiId ||
    wallet.bankAccount?.accountNumber ||
    pilot?.bankAccount?.upiId ||
    pilot?.bankAccount?.accountNumber;

  if (!destination) {
    throw new Error('No destination bank account or UPI ID provided. Please link your bank details first.');
  }

  const payoutId = 'POUT_' + Date.now() + '_' + Math.floor(1000 + Math.random() * 9000);
  const maskedDest = maskTargetAccount(destination, wallet.bankAccount?.ifsc, destination);

  // Atomically Reserve Funds in Escrow:
  // Funds are held in escrow for review/payout. Do NOT deduct from availableBalance or add to totalWithdrawn until payment is confirmed!
  wallet.reservedBalance = parseFloat((currentReserved + amtVal).toFixed(2));
  wallet.lastTransactionAt = new Date();
  wallet.updatedAt = new Date();
  await wallet.save();

  // Save to WithdrawalRequest with status: 'pending_approval'
  if (WithdrawalRequest) {
    const wDoc = new WithdrawalRequest({
      withdrawalId: payoutId,
      transactionId: `TXN_${payoutId}`,
      uid,
      pilotName: pilot?.name || wallet.pilotName || 'Pilot Partner',
      pilotPhone: (pilot?.phone || pilot?.phoneNumber || wallet.phone || uid).replace(/\D/g, '').slice(-10) || wallet.phone || uid,
      amount: amtVal,
      fee: 0.0,
      netAmount: amtVal,
      bankDetails: {
        accountNumber: wallet.bankAccount?.accountNumber || '',
        ifsc: wallet.bankAccount?.ifsc || '',
        bankName: wallet.bankAccount?.bankName || '',
        accountHolderName: wallet.bankAccount?.accountHolderName || '',
        upiId: destination.includes('@') ? destination : ''
      },
      maskedDestination: maskedDest,
      status: 'pending_approval',
      approvalStatus: 'pending',
      payoutProviderReference: '',
      utr: '',
      failureReason: '',
      adminRemarks: 'Pending admin/finance approval',
      auditTrail: [{
        action: 'SUBMITTED',
        performedBy: pilot?.name || wallet.pilotName || 'Pilot Partner',
        timestamp: new Date(),
        notes: `Withdrawal advance requested of ₹${amtVal.toFixed(2)} to ${maskedDest}`
      }],
      idempotencyKey: idempotencyKey || payoutId,
      createdAt: new Date(),
      updatedAt: new Date()
    });
    await wDoc.save();
  }

  // Save to legacy Payout collection for compatibility
  if (Payout) {
    const payoutDoc = new Payout({
      payoutId,
      uid,
      amount: amtVal,
      targetAccount: maskedDest,
      status: 'pending_approval',
      createdAt: new Date()
    });
    await payoutDoc.save();
  }

  // Post Double-Entry Ledger: Escrow Reservation
  await FinancialLedger.create({
    ledgerId: `LED_WTH_${payoutId}_${Date.now()}`,
    transactionId: `TXN_${payoutId}`,
    entryType: 'WITHDRAWAL_RESERVE',
    withdrawalId: payoutId,
    pilotId: uid,
    debitAccount: 'PILOT_WALLET_LIABILITY',
    creditAccount: 'WITHDRAWAL_ESCROW_PAYABLE',
    amount: amtVal,
    currency: 'INR',
    status: 'RESERVED',
    referenceNumber: payoutId,
    description: `Funds reserved for pilot advance withdrawal of ₹${amtVal.toFixed(2)} to ${maskedDest}`,
    timestamp: new Date()
  });

  return {
    success: true,
    payoutId,
    withdrawalId: payoutId,
    amount: amtVal,
    availableBalance: wallet.availableBalance,
    withdrawableAmount: parseFloat((wallet.availableBalance - wallet.reservedBalance).toFixed(2)),
    reservedBalance: wallet.reservedBalance,
    newBalance: parseFloat((wallet.availableBalance - wallet.reservedBalance).toFixed(2)),
    status: 'pending_approval',
    targetAccount: maskedDest,
    message: `Withdrawal request for ₹${amtVal.toFixed(2)} submitted successfully (Ref: ${payoutId}). Status: Pending Approval.`
  };
}

module.exports = {
  getOrCreatePilotWallet,
  creditRideEarnings,
  creditFoodDeliveryEarnings,
  process24HourPendingSettlements,
  requestWithdrawal,
  maskTargetAccount
};
