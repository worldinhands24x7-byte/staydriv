const express = require('express');
const router = express.Router();
const pilotDailyPlanService = require('../services/pilotDailyPlanService');

module.exports = function(models, io) {
  const { User, Booking, FoodOrder, PilotDailyPlanPayment, FinancialLedger } = models;

  // 1. GET /api/pilot/daily-plan/:uid
  // Returns status, 24-hr expiry, price (₹20), today's ride/food earnings, and booking access
  router.get('/pilot/daily-plan/:uid', async (req, res) => {
    try {
      const { uid } = req.params;
      const status = await pilotDailyPlanService.getPilotDailyPlanStatus(uid, {
        User,
        Booking,
        FoodOrder,
        PilotDailyPlanPayment
      });

      if (!status.success) {
        return res.status(404).json(status);
      }

      return res.status(200).json(status);
    } catch (err) {
      console.error('[API /api/pilot/daily-plan/:uid Error]:', err.message);
      return res.status(500).json({ success: false, message: err.message });
    }
  });

  // 2. POST /api/pilot/daily-plan/pay
  // Pilot pays ₹20 daily fee (prevents duplicates for the same active period)
  router.post('/pilot/daily-plan/pay', async (req, res) => {
    try {
      const {
        pilotUidOrPhone,
        uid,
        phone,
        paymentMethod = 'UPI',
        transactionId,
        gatewayPaymentId,
        gatewayOrderId,
        adminOverride = false
      } = req.body;

      const effectiveId = pilotUidOrPhone || uid || phone;
      if (!effectiveId) {
        return res.status(400).json({ success: false, message: 'Pilot UID or phone is required' });
      }

      const result = await pilotDailyPlanService.recordPilotDailyPayment(
        {
          pilotUidOrPhone: effectiveId,
          paymentMethod,
          transactionId,
          gatewayPaymentId,
          gatewayOrderId,
          adminOverride
        },
        { User, PilotDailyPlanPayment, FinancialLedger },
        io
      );

      return res.status(200).json(result);
    } catch (err) {
      console.error('[API /api/pilot/daily-plan/pay Error]:', err.message);
      return res.status(500).json({ success: false, message: err.message });
    }
  });

  // 3. GET /api/admin/pilot-daily-plans
  // Admin dedicated register for ₹20 daily plan payments with search, filters, and KPIs
  router.get('/admin/pilot-daily-plans', async (req, res) => {
    try {
      const {
        search = '',
        vehicleType = 'all',
        paymentStatus = 'all',
        bookingAccess = 'all',
        date = '',
        page = 1,
        limit = 50
      } = req.query;

      const now = new Date();
      const { start: todayStart, end: todayEnd } = pilotDailyPlanService.getTodayBounds();

      // Auto-expire any records where expiresAt has passed
      if (PilotDailyPlanPayment) {
        await PilotDailyPlanPayment.updateMany(
          { paymentStatus: 'paid', expiresAt: { $lte: now } },
          { $set: { paymentStatus: 'expired' } }
        ).catch(() => {});
      }

      // Build Query
      const query = {};

      if (search && search.trim()) {
        const s = search.trim();
        query.$or = [
          { pilotName: { $regex: s, $options: 'i' } },
          { pilotId: { $regex: s, $options: 'i' } },
          { pilotPhone: { $regex: s, $options: 'i' } },
          { transactionId: { $regex: s, $options: 'i' } }
        ];
      }

      if (vehicleType && vehicleType !== 'all') {
        query.vehicleType = { $regex: new RegExp(`^${vehicleType}$`, 'i') };
      }

      if (paymentStatus && paymentStatus !== 'all') {
        query.paymentStatus = paymentStatus.toLowerCase();
      }

      if (bookingAccess && bookingAccess !== 'all') {
        query.bookingAccessStatus = bookingAccess.toLowerCase();
      }

      if (date) {
        const targetDate = new Date(date);
        if (!isNaN(targetDate.getTime())) {
          const dStart = new Date(targetDate.getFullYear(), targetDate.getMonth(), targetDate.getDate(), 0, 0, 0, 0);
          const dEnd = new Date(targetDate.getFullYear(), targetDate.getMonth(), targetDate.getDate(), 23, 59, 59, 999);
          query.paidAt = { $gte: dStart, $lte: dEnd };
        }
      }

      const pageNum = Math.max(1, parseInt(page) || 1);
      const limitNum = Math.min(200, Math.max(1, parseInt(limit) || 50));
      const skip = (pageNum - 1) * limitNum;

      const [payments, totalCount] = await Promise.all([
        PilotDailyPlanPayment.find(query)
          .sort({ paidAt: -1, createdAt: -1 })
          .skip(skip)
          .limit(limitNum)
          .lean(),
        PilotDailyPlanPayment.countDocuments(query)
      ]);

      // Calculate Summary Metrics
      // 1. Daily payment totals today (₹ sum)
      const todayPayments = await PilotDailyPlanPayment.find({
        paymentStatus: { $in: ['paid', 'expired'] },
        paidAt: { $gte: todayStart, $lte: todayEnd }
      }).lean();

      const dailyPaymentTotals = todayPayments.reduce((acc, p) => acc + (p.amount || 20), 0);
      
      // 2. Distinct pilots who paid today
      const distinctPilotsToday = new Set(todayPayments.map(p => p.pilotPhone || p.pilotId)).size;

      // 3. Active paid pilots (unexpired)
      const activePaidPilots = await PilotDailyPlanPayment.countDocuments({
        paymentStatus: 'paid',
        expiresAt: { $gt: now }
      });

      // 4. Expired or unpaid registered pilots
      const totalRegisteredPilots = await User.countDocuments({ role: 'partner' });
      const expiredOrUnpaidPilots = Math.max(0, totalRegisteredPilots - activePaidPilots);

      return res.status(200).json({
        success: true,
        summary: {
          dailyPaymentTotals: parseFloat(dailyPaymentTotals.toFixed(2)),
          pilotsPaidToday: distinctPilotsToday,
          activePaidPilots,
          expiredUnpaidPilots,
          totalRegisteredPilots
        },
        pagination: {
          total: totalCount,
          page: pageNum,
          pages: Math.ceil(totalCount / limitNum),
          limit: limitNum
        },
        payments: payments.map(p => ({
          _id: p._id,
          pilotId: p.pilotId,
          pilotName: p.pilotName,
          pilotPhone: p.pilotPhone,
          vehicleType: p.vehicleType,
          paidAt: p.paidAt,
          amount: p.amount || 20,
          currency: p.currency || 'INR',
          transactionId: p.transactionId,
          paymentStatus: (p.paymentStatus === 'paid' && now >= new Date(p.expiresAt)) ? 'expired' : p.paymentStatus,
          expiresAt: p.expiresAt,
          bookingAccessStatus: p.bookingAccessStatus || 'disabled',
          adminStartStopStatus: p.adminStartStopStatus || 'NONE',
          adminReason: p.adminReason || '',
          adminUpdatedBy: p.adminUpdatedBy || '',
          adminUpdatedAt: p.adminUpdatedAt || null
        }))
      });
    } catch (err) {
      console.error('[API /api/admin/pilot-daily-plans Error]:', err.message);
      return res.status(500).json({ success: false, message: err.message });
    }
  });

  // 4. GET /api/admin/pilot-daily-plans/export
  // Export register to CSV format
  router.get('/admin/pilot-daily-plans/export', async (req, res) => {
    try {
      const payments = await PilotDailyPlanPayment.find()
        .sort({ paidAt: -1 })
        .limit(2000)
        .lean();

      const headers = [
        'Pilot ID',
        'Pilot Name',
        'Registered Mobile Number',
        'Vehicle Type',
        'Payment Date & Time',
        'Payment Amount (INR)',
        'Transaction ID',
        'Payment Status',
        'Plan Expiry',
        'Booking Access Status',
        'Admin Action Status',
        'Admin Reason'
      ];

      const rows = payments.map(p => [
        `"${p.pilotId || ''}"`,
        `"${p.pilotName || ''}"`,
        `"${p.pilotPhone || ''}"`,
        `"${p.vehicleType || ''}"`,
        `"${p.paidAt ? new Date(p.paidAt).toISOString() : ''}"`,
        p.amount || 20,
        `"${p.transactionId || ''}"`,
        `"${p.paymentStatus || ''}"`,
        `"${p.expiresAt ? new Date(p.expiresAt).toISOString() : ''}"`,
        `"${p.bookingAccessStatus || 'disabled'}"`,
        `"${p.adminStartStopStatus || 'NONE'}"`,
        `"${(p.adminReason || '').replace(/"/g, '""')}"`
      ]);

      const csvContent = [headers.join(','), ...rows.map(r => r.join(','))].join('\n');

      res.setHeader('Content-Type', 'text/csv');
      res.setHeader('Content-Disposition', `attachment; filename=staydriv_daily_plan_payments_${Date.now()}.csv`);
      return res.status(200).send(csvContent);
    } catch (err) {
      console.error('[API Export Daily Plan Error]:', err.message);
      return res.status(500).json({ success: false, message: err.message });
    }
  });

  // 5. POST /api/admin/pilot-daily-plans/:pilotId/booking-access
  // Admin-Only Start/Stop Booking Access Control with reason requirement on Stop
  router.post('/admin/pilot-daily-plans/:pilotId/booking-access', async (req, res) => {
    try {
      const { pilotId } = req.params;
      const { action, reason = '', adminId, adminName } = req.body;

      if (!action || (action !== 'START' && action !== 'STOP')) {
        return res.status(400).json({ success: false, message: "Action must be 'START' or 'STOP'" });
      }

      if (action === 'STOP' && (!reason || !reason.trim())) {
        return res.status(400).json({ success: false, message: 'A reason is mandatory when stopping booking access.' });
      }

      const result = await pilotDailyPlanService.updateAdminBookingAccess(
        {
          pilotId,
          action,
          reason,
          adminId: adminId || req.user?.uid || 'ADMIN',
          adminName: adminName || req.user?.name || 'StayDriv Admin'
        },
        { User, PilotDailyPlanPayment },
        io
      );

      return res.status(200).json(result);
    } catch (err) {
      console.error('[API Admin Booking Access Error]:', err.message);
      return res.status(400).json({ success: false, message: err.message });
    }
  });

  return router;
};
