const crypto = require('crypto');
const Restaurant = require('../models/Restaurant');
const FoodOrder = require('../models/FoodOrder');
const RestaurantSettlement = require('../models/RestaurantSettlement');
const FinancialLedger = require('../models/FinancialLedger');

/**
 * Mask bank account number: displays only the last 4 digits
 * e.g., '123456789012' -> '•••• •••• 9012'
 */
function maskAccountNumber(accountNumber) {
  if (!accountNumber) return '';
  const clean = accountNumber.toString().replace(/\s+/g, '');
  if (clean.length <= 4) return '••••' + clean;
  const last4 = clean.slice(-4);
  return '•••• •••• ' + last4;
}

/**
 * Validates payment details format and business constraints
 */
function validatePaymentDetails(data, options = {}) {
  const {
    accountHolderName,
    bankName,
    bankAccount,
    confirmBankAccount,
    bankIfsc,
    accountType,
    registeredMobile,
    upiId,
    paymentPreference,
    isNewAccount = false
  } = data;

  const mustProvideAcc = isNewAccount || options.isNewAccount;

  if (!accountHolderName || accountHolderName.trim().length < 3) {
    return { valid: false, error: 'Valid Account Holder Name (minimum 3 characters) is required' };
  }

  if (!bankName || bankName.trim().length < 2) {
    return { valid: false, error: 'Bank Name is required' };
  }

  const cleanAcc = (bankAccount || '').toString().trim();
  const cleanConfirmAcc = (confirmBankAccount || '').toString().trim();

  // If new account or account number is provided
  if (mustProvideAcc && !cleanAcc) {
    return { valid: false, error: 'Bank Account Number is required for new payment details' };
  }

  if (cleanAcc) {
    if (!/^\d{9,18}$/.test(cleanAcc)) {
      return { valid: false, error: 'Bank Account Number must be between 9 and 18 digits' };
    }

    if (!cleanConfirmAcc) {
      return { valid: false, error: 'Please confirm your Bank Account Number' };
    }

    if (cleanAcc !== cleanConfirmAcc) {
      return { valid: false, error: 'Bank Account Number and Confirm Account Number do not match' };
    }
  }

  const cleanIfsc = (bankIfsc || '').toString().trim().toUpperCase();
  if (!cleanIfsc) {
    return { valid: false, error: 'IFSC Code is required' };
  }
  // Standard Indian IFSC regex: 4 letters, 0, 6 alphanumeric
  if (!/^[A-Z]{4}0[A-Z0-9]{6}$/.test(cleanIfsc)) {
    return { valid: false, error: 'Invalid IFSC Code format (e.g., HDFC0001234, SBIN0004567)' };
  }

  const cleanMobile = (registeredMobile || '').toString().replace(/\D/g, '').slice(-10);
  if (!cleanMobile || cleanMobile.length !== 10) {
    return { valid: false, error: '10-digit Registered Mobile Number is required for payout verification' };
  }

  const cleanPref = (paymentPreference || 'bank_transfer').toString().toLowerCase();
  if (cleanPref === 'upi' && (!upiId || !upiId.trim())) {
    return { valid: false, error: 'Settlement UPI ID is required when payment preference is UPI' };
  }

  if (upiId && upiId.trim()) {
    const cleanUpi = upiId.trim();
    if (!/^[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z]{2,64}$/.test(cleanUpi)) {
      return { valid: false, error: 'Invalid UPI ID format (e.g., restaurant@okhdfcbank, name@upi)' };
    }
  }

  const validAccTypes = ['Savings', 'Current', 'savings', 'current'];
  if (accountType && !validAccTypes.includes(accountType)) {
    return { valid: false, error: 'Account Type must be Savings or Current' };
  }

  return { valid: true };
}

/**
 * Evaluates whether an order (delivered or returned) is eligible for restaurant payment.
 * Returns: { isPayable: boolean, reason: string, isReturned: boolean }
 */
function evaluateRestaurantOrderPayability(order) {
  const status = (order.orderStatus || '').toLowerCase();
  const isReturned = status === 'returned_to_restaurant' || 
                     status === 'return_closed' || 
                     status === 'delivery_failed_reported' ||
                     status === 'return_to_restaurant' ||
                     status === 'return_arrived_at_restaurant' ||
                     status === 'return_otp_pending' ||
                     status.includes('returned') ||
                     status.includes('failed');
  const isDelivered = status === 'delivered';

  if (!isDelivered && !isReturned) {
    return {
      isPayable: false,
      reason: 'Order is not in delivered or return-verified status.',
      isReturned: false
    };
  }

  // Check if return was attributed to restaurant fault
  const cancelBy = (order.cancelledBy || '').toLowerCase();
  const returnReason = (order.returnReason || '').toLowerCase();
  const returnNotes = (order.returnNotes || '').toLowerCase();

  const isRestaurantFault = 
    cancelBy === 'restaurant' ||
    returnReason.includes('wrong item') ||
    returnReason.includes('quality issue') ||
    returnReason.includes('spoiled') ||
    returnReason.includes('stale') ||
    returnReason.includes('restaurant fault') ||
    returnReason.includes('restaurant_fault') ||
    returnNotes.includes('restaurant fault') ||
    order.isRestaurantFault === true;

  if (isRestaurantFault) {
    return {
      isPayable: false,
      reason: 'Non-payable: Return attributed to restaurant preparation/quality issue.',
      isReturned: true
    };
  }

  // If order was cancelled without food preparation
  if (order.foodPrepared === false || order.orderStatus === 'cancelled') {
    return {
      isPayable: false,
      reason: 'Non-payable: Order cancelled before food preparation was completed.',
      isReturned: isReturned
    };
  }

  // Returned orders where food was prepared and returned due to customer not receiving / customer unreachable / refused
  if (isReturned) {
    return {
      isPayable: true,
      reason: 'Payable: Food prepared & returned safely due to customer non-delivery.',
      isReturned: true
    };
  }

  // Successfully delivered orders
  return {
    isPayable: true,
    reason: 'Payable: Successfully delivered to customer.',
    isReturned: false
  };
}

/**
 * Calculates authoritative restaurant sales, commissions, and net earnings.
 * Includes both delivered orders and eligible returned orders (customer non-delivery).
 * Non-payable orders (restaurant fault) are strictly excluded from payout.
 */
async function calculateRestaurantSales(restaurantId) {
  const restaurant = await Restaurant.findOne({ restaurantId }).lean();
  if (!restaurant) {
    throw new Error('Restaurant not found');
  }

  // Fetch delivered and returned orders
  const orders = await FoodOrder.find({
    restaurantId,
    orderStatus: {
      $in: [
        'delivered',
        'returned_to_restaurant',
        'RETURNED_TO_RESTAURANT',
        'return_closed',
        'RETURN_CLOSED',
        'delivery_failed_reported',
        'return_to_restaurant',
        'return_arrived_at_restaurant',
        'return_otp_pending'
      ]
    }
  }).sort({ returnedAt: -1, deliveredAt: -1, createdAt: -1 }).lean();

  let grossFoodSales = 0;
  let totalPackagingFees = 0;
  let totalAdjustments = 0;
  let deliveredOrdersCount = 0;
  let returnedOrdersCount = 0;
  let nonPayableOrdersCount = 0;
  const eligiblePayableOrders = [];

  orders.forEach(o => {
    const payability = evaluateRestaurantOrderPayability(o);
    const sub = o.subtotal || 0;
    const pack = o.packagingFee || 0;

    if (payability.isPayable) {
      grossFoodSales += sub;
      totalPackagingFees += pack;
      eligiblePayableOrders.push(o);

      if (payability.isReturned) {
        returnedOrdersCount++;
      } else {
        deliveredOrdersCount++;
      }

      if (o.walletDebitStatus === 'debited' && o.actualWalletDebitAmount > 0) {
        totalAdjustments += o.actualWalletDebitAmount;
      }
    } else {
      nonPayableOrdersCount++;
    }
  });

  const totalSales = grossFoodSales + totalPackagingFees;
  const commissionRate = restaurant.commissionRate != null ? restaurant.commissionRate : 15.0;
  // Platform commission is calculated on food subtotal
  const platformCommissionAmount = Math.round((grossFoodSales * commissionRate) / 100);
  const netEarnings = Math.max(0, totalSales - platformCommissionAmount - totalAdjustments);

  // Fetch all existing settlements
  const settlements = await RestaurantSettlement.find({ restaurantId }).sort({ createdAt: -1 }).lean();
  
  let amountPaid = 0;
  let processingAmount = 0;
  let settledOrderIds = new Set();

  settlements.forEach(s => {
    if (s.status === 'paid') {
      amountPaid += (s.netPayable || s.amountPaid || 0);
      (s.orderIds || []).forEach(id => settledOrderIds.add(id));
    } else if (s.status === 'processing') {
      processingAmount += (s.netPayable || 0);
      (s.orderIds || []).forEach(id => settledOrderIds.add(id));
    }
  });

  // Calculate unsettled delivered + eligible returned orders
  const unsettledOrders = eligiblePayableOrders.filter(o => !settledOrderIds.has(o.orderId));
  let unsettledGross = 0;
  let unsettledAdjustments = 0;
  unsettledOrders.forEach(o => {
    unsettledGross += (o.subtotal || 0) + (o.packagingFee || 0);
    if (o.walletDebitStatus === 'debited' && o.actualWalletDebitAmount > 0) {
      unsettledAdjustments += o.actualWalletDebitAmount;
    }
  });
  const unsettledCommission = Math.round(((unsettledOrders.reduce((acc, o) => acc + (o.subtotal || 0), 0)) * commissionRate) / 100);
  const calculatedPending = Math.max(0, unsettledGross - unsettledCommission - unsettledAdjustments);

  const pendingSettlement = Math.max(0, netEarnings - amountPaid - processingAmount);

  const lastPaidSettlement = settlements.find(s => s.status === 'paid');

  return {
    restaurantId: restaurant.restaurantId,
    restaurantName: restaurant.name,
    commissionRate,
    totalSales,
    grossFoodSales,
    totalPackagingFees,
    totalAdjustments,
    completedOrdersCount: deliveredOrdersCount,
    returnedOrdersCount,
    totalEligibleOrdersCount: eligiblePayableOrders.length,
    nonPayableOrdersCount,
    platformCommissionAmount,
    netEarnings,
    amountPaid,
    processingAmount,
    pendingSettlement,
    unsettledOrdersCount: unsettledOrders.length,
    lastSettlementDate: lastPaidSettlement ? lastPaidSettlement.settledAt : null,
    bankVerificationStatus: restaurant.bankVerificationStatus || 'unverified',
    paymentDetails: {
      accountHolderName: restaurant.bankHolderName || '',
      bankName: restaurant.bankName || '',
      bankAccountMasked: restaurant.bankAccountMasked || maskAccountNumber(restaurant.bankAccount),
      bankIfsc: restaurant.bankIfsc || '',
      accountType: restaurant.accountType || 'Current',
      registeredMobile: restaurant.registeredMobile || restaurant.phone || '',
      upiId: restaurant.upiId || '',
      paymentPreference: restaurant.paymentPreference || 'bank_transfer',
      bankVerificationStatus: restaurant.bankVerificationStatus || 'unverified',
      bankVerifiedAt: restaurant.bankVerifiedAt || null,
      bankRejectionReason: restaurant.bankRejectionReason || ''
    }
  };
}

/**
 * Initiates a new settlement for eligible unsettled delivered and returned orders
 */
async function initiateSettlement({ restaurantId, adminUser = 'Admin', notes = '' }) {
  const restaurant = await Restaurant.findOne({ restaurantId });
  if (!restaurant) {
    throw new Error('Restaurant not found');
  }

  if (!restaurant.bankAccount && !restaurant.upiId) {
    throw new Error('Restaurant has not submitted payment details. Cannot initiate settlement.');
  }

  const summary = await calculateRestaurantSales(restaurantId);
  if (summary.pendingSettlement <= 0) {
    throw new Error('No pending earnings available for settlement (Pending Balance is ₹0).');
  }

  // Find all delivered and eligible returned orders not yet in a paid or processing settlement
  const settlements = await RestaurantSettlement.find({
    restaurantId,
    status: { $in: ['paid', 'processing'] }
  }).lean();

  const alreadySettledOrderIds = new Set();
  settlements.forEach(s => {
    (s.orderIds || []).forEach(id => alreadySettledOrderIds.add(id));
  });

  const candidateOrders = await FoodOrder.find({
    restaurantId,
    orderStatus: {
      $in: [
        'delivered',
        'returned_to_restaurant',
        'RETURNED_TO_RESTAURANT',
        'return_closed',
        'RETURN_CLOSED'
      ]
    },
    orderId: { $nin: Array.from(alreadySettledOrderIds) }
  }).lean();

  const eligibleOrders = candidateOrders.filter(o => evaluateRestaurantOrderPayability(o).isPayable);

  let grossSales = 0;
  let foodSubtotal = 0;
  let packagingFee = 0;
  let totalAdjustments = 0;
  const orderIds = [];

  eligibleOrders.forEach(o => {
    foodSubtotal += (o.subtotal || 0);
    packagingFee += (o.packagingFee || 0);
    grossSales += (o.subtotal || 0) + (o.packagingFee || 0);
    orderIds.push(o.orderId);
    if (o.walletDebitStatus === 'debited' && o.actualWalletDebitAmount > 0) {
      totalAdjustments += o.actualWalletDebitAmount;
    }
  });

  const commissionRate = restaurant.commissionRate != null ? restaurant.commissionRate : 15.0;
  const totalCommission = Math.round((foodSubtotal * commissionRate) / 100);
  const netPayable = Math.max(0, grossSales - totalCommission - totalAdjustments);

  if (netPayable <= 0) {
    throw new Error('Calculated net settlement amount is ₹0.');
  }

  const randomHex = crypto.randomBytes(3).toString('hex').toUpperCase();
  const settlementId = `SETTLE_${restaurantId}_${Date.now()}_${randomHex}`;

  const payoutProvider = (process.env.RAZORPAYX_KEY_ID && process.env.RAZORPAYX_KEY_SECRET) ? 'razorpayx' : 'manual_bank_transfer';

  const newSettlement = new RestaurantSettlement({
    settlementId,
    restaurantId,
    restaurantName: restaurant.name,
    periodStart: eligibleOrders.length > 0 ? eligibleOrders[eligibleOrders.length - 1].deliveredAt || new Date() : new Date(),
    periodEnd: new Date(),
    orderIds,
    ordersCount: orderIds.length,
    grossSales,
    totalCommission,
    commissionRate,
    totalAdjustments,
    netPayable,
    amountPaid: 0,
    status: 'processing',
    paymentMethod: restaurant.paymentPreference || 'bank_transfer',
    bankDetails: {
      accountHolderName: restaurant.bankHolderName || '',
      bankName: restaurant.bankName || '',
      accountNumberMasked: restaurant.bankAccountMasked || maskAccountNumber(restaurant.bankAccount),
      ifscCode: restaurant.bankIfsc || '',
      accountType: restaurant.accountType || 'Current',
      upiId: restaurant.upiId || '',
      registeredMobile: restaurant.registeredMobile || restaurant.phone || ''
    },
    payoutProvider,
    initiatedBy: adminUser,
    initiatedAt: new Date(),
    notes,
    auditLog: [
      {
        action: 'SETTLEMENT_INITIATED',
        actor: adminUser,
        timestamp: new Date(),
        note: `Initiated settlement of ₹${netPayable} for ${orderIds.length} completed orders.`
      }
    ]
  });

  await newSettlement.save();
  return newSettlement;
}

/**
 * Confirms payment settlement with mandatory UTR / Payout reference
 * Updates restaurant earnings and writes immutable FinancialLedger records
 */
async function confirmSettlement({ settlementId, payoutReference, adminUser = 'Admin', remarks = '' }) {
  if (!payoutReference || !payoutReference.trim()) {
    throw new Error('Valid Bank UTR / Transaction Reference is mandatory to confirm settlement');
  }

  const settlement = await RestaurantSettlement.findOne({ settlementId });
  if (!settlement) {
    throw new Error('Settlement not found');
  }

  // Idempotency: if already paid, return without duplicate ledger rows
  if (settlement.status === 'paid') {
    return { settlement, alreadyPaid: true };
  }

  const cleanUtr = payoutReference.trim();
  const now = new Date();

  settlement.status = 'paid';
  settlement.payoutReference = cleanUtr;
  settlement.amountPaid = settlement.netPayable;
  settlement.settledAt = now;
  settlement.settledBy = adminUser;
  if (remarks) {
    settlement.notes = (settlement.notes ? settlement.notes + ' | ' : '') + remarks;
  }

  settlement.auditLog.push({
    action: 'SETTLEMENT_CONFIRMED_PAID',
    actor: adminUser,
    timestamp: now,
    note: `Settlement confirmed with UTR: ${cleanUtr}. Amount ₹${settlement.netPayable} marked as Paid.`
  });

  await settlement.save();

  // Update restaurant cumulative settled earnings
  await Restaurant.findOneAndUpdate(
    { restaurantId: settlement.restaurantId },
    {
      $inc: { settledEarnings: settlement.netPayable, totalSettled: settlement.netPayable },
      updatedAt: now
    }
  );

  // Mark all encompassed orders as settled
  const targetOrderIds = Array.from(settlement.orderIds || []);
  if (targetOrderIds.length > 0) {
    await FoodOrder.updateMany(
      { orderId: { $in: targetOrderIds } },
      {
        $set: {
          settlementStatus: 'settled',
          settlementId: settlement.settlementId
        }
      }
    );
  }

  // Record double-entry transaction in FinancialLedger
  try {
    const randomHex = crypto.randomBytes(3).toString('hex').toUpperCase();
    const ledgerEntry = new FinancialLedger({
      ledgerId: `LEDGER_REST_${Date.now()}_${randomHex}`,
      transactionId: cleanUtr,
      entryType: 'RESTAURANT_PAYOUT_SETTLEMENT',
      restaurantId: settlement.restaurantId,
      settlementId: settlement.settlementId,
      debitAccount: 'STAYDRIV_ESCROW_OPERATING_ACCOUNT',
      creditAccount: `RESTAURANT_${settlement.restaurantId}_PAYOUT`,
      amount: settlement.netPayable,
      currency: 'INR',
      status: 'POSTED',
      referenceNumber: cleanUtr,
      description: `Settlement payout for ${settlement.restaurantName} (${settlement.settlementId}) - ${settlement.ordersCount} orders`,
      auditDetails: {
        settlementId: settlement.settlementId,
        restaurantId: settlement.restaurantId,
        grossSales: settlement.grossSales,
        commission: settlement.totalCommission,
        netPayable: settlement.netPayable,
        confirmedBy: adminUser,
        confirmedAt: now
      },
      timestamp: now
    });
    await ledgerEntry.save();
  } catch (ledgerErr) {
    console.warn('[RESTAURANT SETTLEMENT] Financial ledger logging note (non-fatal):', ledgerErr.message);
  }

  return { settlement, alreadyPaid: false };
}

/**
 * Marks settlement as failed with reason, keeping amount in pending settlement
 */
async function failSettlement({ settlementId, failureReason, adminUser = 'Admin' }) {
  const settlement = await RestaurantSettlement.findOne({ settlementId });
  if (!settlement) {
    throw new Error('Settlement not found');
  }

  if (settlement.status === 'paid') {
    throw new Error('Cannot fail a settlement that has already been marked as Paid.');
  }

  const reason = failureReason || 'Bank account invalid, name mismatch, or transfer rejected by gateway';
  const now = new Date();

  settlement.status = 'failed';
  settlement.failureReason = reason;
  settlement.auditLog.push({
    action: 'SETTLEMENT_FAILED',
    actor: adminUser,
    timestamp: now,
    note: `Settlement marked failed: ${reason}. Amount retained in pending settlement.`
  });

  await settlement.save();

  // Rollback encompassed orders to unsettled
  const targetOrderIds = Array.from(settlement.orderIds || []);
  if (targetOrderIds.length > 0) {
    await FoodOrder.updateMany(
      { orderId: { $in: targetOrderIds } },
      {
        $set: {
          settlementStatus: 'unsettled',
          settlementId: ''
        }
      }
    );
  }

  return settlement;
}

module.exports = {
  maskAccountNumber,
  validatePaymentDetails,
  evaluateRestaurantOrderPayability,
  calculateRestaurantSales,
  initiateSettlement,
  confirmSettlement,
  failSettlement
};
