const express = require('express');
const router = express.Router();
const pilotWalletService = require('../services/pilotWalletService');

module.exports = function(models, io) {
  const { User, Booking, WithdrawalRequest, Payout } = models;

  // Helper to extract UID from request (params, query, body, or auth headers)
  function getEffectiveUid(req) {
    return req.params.uid || req.query.uid || req.body.uid || req.headers['x-pilot-uid'] || (req.user && req.user.uid);
  }

  // 1. GET /api/pilot/wallet (or /api/pilot/wallet/:uid)
  const handleGetWallet = async (req, res) => {
    try {
      const uid = getEffectiveUid(req);
      if (!uid) {
        return res.status(400).json({ success: false, error: 'Missing pilot uid parameter.' });
      }

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

      const wallet = await pilotWalletService.getOrCreatePilotWallet(uid, pilot || {});

      // Fetch recent payouts / withdrawal transactions for this pilot across any UID/phone variant
      const pilotUids = [uid];
      const cleanPhone = (wallet.phone || pilot?.phone || pilot?.phoneNumber || uid).replace(/\D/g, '').slice(-10);
      if (cleanPhone) {
        pilotUids.push(cleanPhone, `pilot_${cleanPhone}`, `mock_uid_${cleanPhone}_pilot`, `mock_uid_${cleanPhone}`);
      }
      const withdrawals = await WithdrawalRequest.find({
        $or: [
          { uid: { $in: pilotUids } },
          { pilotPhone: cleanPhone },
          { pilotPhone: `pilot_${cleanPhone}` }
        ]
      })
      .sort({ createdAt: -1 })
      .limit(30);

      const avail = Number(wallet.availableBalance || 0);
      const resBal = Number(wallet.reservedBalance || 0);
      const withAmt = Math.max(0, parseFloat((avail - resBal).toFixed(2)));

      return res.status(200).json({
        success: true,
        uid: wallet.uid,
        pilotName: wallet.pilotName,
        phone: wallet.phone,
        availableBalance: avail,
        reservedBalance: resBal,
        withdrawableAmount: withAmt,
        pendingSettlement: wallet.pendingSettlement || 0,
        totalEarnings: wallet.totalEarnings || 0,
        totalWithdrawn: wallet.totalWithdrawn || 0,
        currency: wallet.currency || 'INR',
        bankAccount: {
          accountHolderName: wallet.bankAccount?.accountHolderName || '',
          maskedAccountNumber: wallet.bankAccount?.maskedAccountNumber || pilotWalletService.maskTargetAccount(wallet.bankAccount?.accountNumber, wallet.bankAccount?.ifsc, wallet.bankAccount?.upiId),
          ifsc: wallet.bankAccount?.ifsc || '',
          bankName: wallet.bankAccount?.bankName || '',
          upiId: wallet.bankAccount?.upiId || '',
          isVerified: wallet.bankAccount?.isVerified || false
        },
        withdrawals,
        updatedAt: wallet.updatedAt
      });
    } catch (err) {
      console.error('[GET /api/pilot/wallet Error]:', err.message);
      return res.status(500).json({ success: false, error: err.message });
    }
  };

  router.get('/wallet', handleGetWallet);
  router.get('/wallet/:uid', handleGetWallet);

  // 2. GET /api/pilot/earnings (or /api/pilot/earnings/:uid)
  const handleGetEarnings = async (req, res) => {
    try {
      const uid = getEffectiveUid(req);
      if (!uid) {
        return res.status(400).json({ success: false, error: 'Missing pilot uid parameter.' });
      }

      let pilot = await User.findOne({ uid });
      if (!pilot && uid.startsWith('mock_uid_')) {
        let phone = uid.replace('mock_uid_', '');
        if (phone.endsWith('_pilot')) phone = phone.replace('_pilot', '');
        pilot = await User.findOne({ phone, role: 'partner' });
      }

      const wallet = await pilotWalletService.getOrCreatePilotWallet(uid, pilot || {});

      // Fetch completed rides for this pilot
      const pilotUids = [uid];
      if (uid.startsWith('mock_uid_')) {
        let phone = uid.replace('mock_uid_', '');
        pilotUids.push(phone);
        if (phone.endsWith('_pilot')) {
          phone = phone.replace('_pilot', '');
          pilotUids.push(phone);
          pilotUids.push('mock_uid_' + phone);
          pilotUids.push(phone + '_pilot');
        }
      }

      const completedRides = await Booking.find({
        driverId: { $in: pilotUids },
        status: 'completed'
      })
      .sort({ updatedAt: -1, createdAt: -1 })
      .limit(50);

      const formattedRides = completedRides.map(b => ({
        bookingId: b.bookingId,
        serviceType: b.serviceType || 'ride',
        vehicle: b.vehicle || 'Bike',
        fare: b.finalFare || parseFloat(String(b.price || '0').replace(/[^0-9.]/g, '')) || 0,
        pilotEarnings: b.pilotEarnings || parseFloat(((b.finalFare || 0) * 0.85).toFixed(2)),
        platformCommission: b.platformCommission || parseFloat(((b.finalFare || 0) * 0.15).toFixed(2)),
        settlementStatus: b.settlementStatus || 'pending_settlement',
        settlementEligibleAt: b.settlementEligibleAt,
        settledAt: b.settledAt,
        payoutReference: b.payoutReference || '',
        pickup: b.pickup,
        drop: b.drop,
        passengerName: b.passengerName,
        completedAt: b.updatedAt || b.createdAt
      }));

      // Also include delivered FoodOrders
      try {
        const FoodOrder = mongoose.models.FoodOrder || require('../models/FoodOrder');
        const foodOrders = await FoodOrder.find({
          $or: [
            { deliveryPartnerId: { $in: pilotUids } },
            { deliveryPartnerPhone: { $in: pilotUids } }
          ],
          orderStatus: 'delivered'
        }).sort({ deliveredAt: -1, createdAt: -1 }).limit(50);

        for (const f of foodOrders) {
          formattedRides.push({
            bookingId: f.orderId,
            serviceType: 'food',
            vehicle: 'Food Delivery',
            fare: f.deliveryFee || 0,
            pilotEarnings: f.deliveryFee || 0,
            platformCommission: 0,
            settlementStatus: f.settlementStatus || 'pending_settlement',
            settlementEligibleAt: f.settlementEligibleAt,
            settledAt: f.settledAt,
            payoutReference: f.payoutReference || '',
            pickup: f.restaurantName ? `${f.restaurantName}, ${f.restaurantAddress || ''}`.trim() : (f.restaurantAddress || 'Restaurant'),
            drop: f.deliveryAddress || 'Customer Address',
            passengerName: f.customerName || 'Customer',
            completedAt: f.deliveredAt || f.updatedAt || f.createdAt
          });
        }

        // Sort combined list descending
        formattedRides.sort((a, b) => new Date(b.completedAt).getTime() - new Date(a.completedAt).getTime());
      } catch (err) {
        console.warn('Notice: Pilot earnings food orders query:', err.message);
      }

      // Fetch withdrawal requests and normalize legacy statuses
      const withdrawals = await WithdrawalRequest.find({ uid })
        .sort({ createdAt: -1 })
        .limit(30);

      const normalizedWithdrawals = withdrawals.map(w => {
        let normStatus = (w.status || 'pending_approval').toLowerCase();
        if (normStatus === 'pending') normStatus = 'pending_approval';
        if (normStatus === 'completed') normStatus = 'paid';
        return {
          withdrawalId: w.withdrawalId,
          transactionId: w.transactionId || `TXN_${w.withdrawalId}`,
          amount: w.amount,
          fee: w.fee || 0,
          netAmount: w.netAmount || w.amount,
          status: normStatus,
          approvalStatus: w.approvalStatus || 'pending',
          maskedDestination: w.maskedDestination || pilotWalletService.maskTargetAccount(w.bankDetails?.accountNumber, w.bankDetails?.ifsc, w.bankDetails?.upiId),
          utr: w.utr || '',
          payoutProviderReference: w.payoutProviderReference || '',
          rejectionReason: w.rejectionReason || '',
          failureReason: w.failureReason || '',
          adminRemarks: w.adminRemarks || '',
          createdAt: w.createdAt,
          updatedAt: w.updatedAt
        };
      });

      const reserved = Number(wallet.reservedBalance || 0);
      const available = Number(wallet.availableBalance || 0);
      const withdrawable = Math.max(0, parseFloat((available - reserved).toFixed(2)));
      const pendingRides = Number(wallet.pendingSettlement || 0);
      const totalPending = parseFloat((reserved + pendingRides).toFixed(2));

      return res.status(200).json({
        success: true,
        uid: wallet.uid,
        pilotName: wallet.pilotName,
        pilotPhone: wallet.phone,
        totalEarnings: wallet.totalEarnings,
        availableBalance: available,
        withdrawableAmount: withdrawable,
        reservedBalance: reserved,
        pendingAmount: totalPending,
        pendingSettlement: pendingRides,
        pendingWithdrawals: reserved,
        withdrawnAmount: Number(wallet.totalWithdrawn || 0),
        bankAccount: {
          accountHolderName: wallet.bankAccount?.accountHolderName || '',
          maskedAccountNumber: wallet.bankAccount?.maskedAccountNumber || pilotWalletService.maskTargetAccount(wallet.bankAccount?.accountNumber, wallet.bankAccount?.ifsc, wallet.bankAccount?.upiId),
          ifsc: wallet.bankAccount?.ifsc || '',
          bankName: wallet.bankAccount?.bankName || '',
          upiId: wallet.bankAccount?.upiId || '',
          isVerified: wallet.bankAccount?.isVerified || false
        },
        completedRides: formattedRides,
        withdrawals: normalizedWithdrawals
      });
    } catch (err) {
      console.error('[GET /api/pilot/earnings Error]:', err.message);
      return res.status(500).json({ success: false, error: err.message });
    }
  };

  router.get('/earnings', handleGetEarnings);
  router.get('/earnings/:uid', handleGetEarnings);

  // 3. GET /api/pilot/payouts (or /api/pilot/payouts/:uid)
  const handleGetPayouts = async (req, res) => {
    try {
      const uid = getEffectiveUid(req);
      if (!uid) {
        return res.status(400).json({ success: false, error: 'Missing pilot uid parameter.' });
      }

      const payouts = await WithdrawalRequest.find({ uid })
        .sort({ createdAt: -1 })
        .limit(50);

      return res.status(200).json({
        success: true,
        count: payouts.length,
        payouts: payouts.map(p => {
          let normStatus = (p.status || 'pending_approval').toLowerCase();
          if (normStatus === 'pending') normStatus = 'pending_approval';
          if (normStatus === 'completed') normStatus = 'paid';
          return {
            payoutId: p.withdrawalId,
            withdrawalId: p.withdrawalId,
            transactionId: p.transactionId || `TXN_${p.withdrawalId}`,
            amount: p.amount,
            status: normStatus,
            targetAccount: p.maskedDestination || p.bankDetails?.upiId || '•••• (Bank)',
            payoutReference: p.payoutProviderReference || p.utr || p.withdrawalId,
            utr: p.utr || '',
            failureReason: p.failureReason || '',
            rejectionReason: p.rejectionReason || '',
            createdAt: p.createdAt,
            settlementDate: p.settlementDate || p.updatedAt
          };
        })
      });
    } catch (err) {
      console.error('[GET /api/pilot/payouts Error]:', err.message);
      return res.status(500).json({ success: false, error: err.message });
    }
  };

  router.get('/payouts', handleGetPayouts);
  router.get('/payouts/:uid', handleGetPayouts);

  // 4. POST /api/pilot/payouts/withdraw (and aliases) - Instant Advance Withdrawal Request
  router.post(['/payouts/withdraw', '/withdraw', '/withdrawals/create'], async (req, res) => {
    try {
      const { uid, amount, targetAccount, idempotencyKey, bankDetails, bankAccount } = req.body;
      const effectiveKey = idempotencyKey || req.headers['idempotency-key'] || req.headers['x-idempotency-key'];
      if (!uid || amount === undefined || amount === null) {
        return res.status(400).json({ success: false, error: 'Missing uid or amount' });
      }

      // If bank details provided, link to wallet
      const bObj = bankDetails || (typeof bankAccount === 'object' ? bankAccount : null);
      if (bObj && (bObj.accountNumber || bObj.upiId)) {
        let pilotUser = await User.findOne({ uid });
        const wallet = await pilotWalletService.getOrCreatePilotWallet(uid, pilotUser || {});
        wallet.bankAccount = wallet.bankAccount || {};
        if (bObj.accountNumber) wallet.bankAccount.accountNumber = bObj.accountNumber;
        if (bObj.ifsc) wallet.bankAccount.ifsc = bObj.ifsc;
        if (bObj.accountHolderName) wallet.bankAccount.accountHolderName = bObj.accountHolderName;
        if (bObj.bankName) wallet.bankAccount.bankName = bObj.bankName;
        if (bObj.upiId) wallet.bankAccount.upiId = bObj.upiId;
        wallet.bankAccount.isVerified = true;
        await wallet.save();
      }

      const effectiveTarget = targetAccount ||
        (typeof bankAccount === 'string' ? bankAccount : null) ||
        req.body.upiId ||
        req.body.destination ||
        (bObj ? (bObj.accountNumber || bObj.upiId) : null);

      const result = await pilotWalletService.requestWithdrawal({
        uid,
        amount,
        targetAccount: effectiveTarget,
        idempotencyKey: effectiveKey,
        User,
        WithdrawalRequest,
        Payout,
        razorpayKeyId: process.env.RAZORPAY_KEY_ID || 'rzp_live_Ta9cOGnIySuBCb',
        razorpayKeySecret: process.env.RAZORPAY_KEY_SECRET || 'c93MSwcWO22lZuC7Xm5jURu0',
        razorpayxAccountNumber: process.env.RAZORPAYX_ACCOUNT_NUMBER || 'acc_QSGP6wlx6TBjWX'
      });

      if (io) {
        io.emit('pilot_wallet_updated', {
          uid,
          availableBalance: result.availableBalance,
          withdrawableAmount: result.withdrawableAmount,
          reservedBalance: result.reservedBalance,
          withdrawalId: result.payoutId,
          status: result.status
        });
        io.to('admin_tracking').emit('withdrawal_created', {
          withdrawalId: result.payoutId,
          uid,
          amount: result.amount,
          status: result.status,
          createdAt: new Date()
        });
      }

      return res.status(200).json(result);
    } catch (err) {
      console.error('[POST /api/pilot/payouts/withdraw Error]:', err.message);
      return res.status(400).json({ success: false, error: err.message });
    }
  });

  // 5. POST /api/pilot/bank-account/save - Link / update verified bank details
  router.post('/bank-account/save', async (req, res) => {
    try {
      const { uid, accountNumber, confirmAccountNumber, ifsc, bankName, accountHolderName, upiId } = req.body;
      if (!uid) {
        return res.status(400).json({ success: false, error: 'Missing pilot uid parameter.' });
      }

      const cleanAcc = (accountNumber || '').trim();
      const cleanConfirm = (confirmAccountNumber || '').trim();
      const cleanIfsc = (ifsc || '').trim().toUpperCase();
      const cleanUpi = (upiId || '').trim();

      if (!cleanAcc && !cleanUpi) {
        return res.status(400).json({ success: false, error: 'Please enter a Bank Account Number or a valid UPI ID.' });
      }

      if (cleanAcc) {
        if (cleanConfirm && cleanAcc !== cleanConfirm) {
          return res.status(400).json({ success: false, error: 'Bank Account Number and Confirm Account Number do not match.' });
        }
        if (cleanAcc.length < 9 || cleanAcc.length > 18) {
          return res.status(400).json({ success: false, error: 'Account number must be between 9 and 18 digits.' });
        }
        if (!cleanIfsc || cleanIfsc.length !== 11) {
          return res.status(400).json({ success: false, error: 'Please enter a valid 11-character Indian Financial System Code (IFSC).' });
        }
      }

      if (cleanUpi && !cleanUpi.includes('@')) {
        return res.status(400).json({ success: false, error: 'Invalid UPI ID format. (e.g. mobile@upi or name@bank)' });
      }

      let pilot = await User.findOne({ uid });
      if (!pilot && uid.startsWith('mock_uid_')) {
        let phone = uid.replace('mock_uid_', '');
        if (phone.endsWith('_pilot')) phone = phone.replace('_pilot', '');
        pilot = await User.findOne({ phone, role: 'partner' });
      }

      const wallet = await pilotWalletService.getOrCreatePilotWallet(uid, pilot || {});

      const masked = pilotWalletService.maskTargetAccount(cleanAcc, cleanIfsc, cleanUpi);
      wallet.bankAccount = {
        accountHolderName: (accountHolderName || '').trim() || pilot?.name || wallet.pilotName || 'Pilot Partner',
        accountNumber: cleanAcc,
        maskedAccountNumber: masked,
        ifsc: cleanIfsc,
        bankName: (bankName || '').trim() || (cleanIfsc ? `${cleanIfsc.slice(0, 4)} Bank` : 'Linked Account'),
        upiId: cleanUpi,
        isVerified: true,
        verifiedAt: new Date()
      };
      wallet.updatedAt = new Date();
      await wallet.save();

      if (pilot) {
        pilot.bankAccount = wallet.bankAccount;
        await pilot.save();
      }

      console.log(`[BANK LINKED] Saved bank details for pilot ${uid} (${masked})`);
      return res.status(200).json({
        success: true,
        message: 'Bank account details successfully linked and verified.',
        bankAccount: {
          accountHolderName: wallet.bankAccount.accountHolderName,
          maskedAccountNumber: masked,
          ifsc: wallet.bankAccount.ifsc,
          bankName: wallet.bankAccount.bankName,
          upiId: wallet.bankAccount.upiId,
          isVerified: true
        }
      });
    } catch (err) {
      console.error('[POST /api/pilot/bank-account/save Error]:', err.message);
      return res.status(500).json({ success: false, error: err.message });
    }
  });

  // 6. POST /api/pilot/settlements/process-now - Trigger 24-hr pending settlements check
  router.post('/settlements/process-now', async (req, res) => {
    try {
      const result = await pilotWalletService.process24HourPendingSettlements(Booking, User, WithdrawalRequest, io);
      return res.status(200).json({
        success: true,
        message: `Processed 24-hour settlements: ${result.count} bookings settled. Total amount: ₹${result.totalSettled}`,
        ...result
      });
    } catch (err) {
      console.error('[POST /api/pilot/settlements/process-now Error]:', err.message);
      return res.status(500).json({ success: false, error: err.message });
    }
  });

  return router;
};
