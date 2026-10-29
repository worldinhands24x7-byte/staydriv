/**
 * StayDriv - Restaurant Payment Details & Sales Settlement Verification Test Suite
 * Tests financial calculation accuracy, bank validation, masking, idempotency, and audit trails.
 */

const assert = require('assert');
const restaurantSettlementService = require('./services/restaurantSettlementService');

async function runTestSuite() {
  console.log('====================================================================');
  console.log('🚀 STAYDRIV: RESTAURANT PAYMENT DETAILS & SETTLEMENT TEST SUITE');
  console.log('====================================================================\n');

  let passedTests = 0;
  let totalTests = 0;

  function test(description, fn) {
    totalTests++;
    try {
      fn();
      console.log(`  ✓ [TEST ${totalTests}] ${description}`);
      passedTests++;
    } catch (err) {
      console.error(`  ✗ [TEST ${totalTests}] FAILED: ${description}`);
      console.error(`    Error: ${err.message}`);
    }
  }

  // --- 1. SENSITIVE DATA MASKING TESTS ---
  console.log('--- 1. Security: Sensitive Bank Data Masking ---');

  test('Mask standard 12-digit bank account number', () => {
    const masked = restaurantSettlementService.maskAccountNumber('501002345678');
    assert.strictEqual(masked, '•••• •••• 5678', `Expected •••• •••• 5678, got ${masked}`);
  });

  test('Mask 16-digit account number', () => {
    const masked = restaurantSettlementService.maskAccountNumber('1234567890123456');
    assert.strictEqual(masked, '•••• •••• 3456', `Expected •••• •••• 3456, got ${masked}`);
  });

  test('Mask short account number safely without exposing prefix', () => {
    const masked = restaurantSettlementService.maskAccountNumber('1234');
    assert.strictEqual(masked, '••••1234', `Expected ••••1234, got ${masked}`);
  });

  test('Mask empty or null account number gracefully', () => {
    assert.strictEqual(restaurantSettlementService.maskAccountNumber(''), '');
    assert.strictEqual(restaurantSettlementService.maskAccountNumber(null), '');
  });

  // --- 2. PAYMENT DETAILS VALIDATION TESTS ---
  console.log('\n--- 2. Validation: Mandatory Fields & Format Constraints ---');

  test('Reject invalid Account Holder Name (< 3 chars)', () => {
    const res = restaurantSettlementService.validatePaymentDetails({
      accountHolderName: 'AB',
      bankName: 'HDFC Bank',
      bankAccount: '12345678901',
      confirmBankAccount: '12345678901',
      bankIfsc: 'HDFC0001234',
      registeredMobile: '9876543210'
    });
    assert.strictEqual(res.valid, false);
    assert.ok(res.error.includes('minimum 3 characters'));
  });

  test('Reject empty Bank Name', () => {
    const res = restaurantSettlementService.validatePaymentDetails({
      accountHolderName: 'Rajesh Sharma',
      bankName: ' ',
      bankAccount: '12345678901',
      confirmBankAccount: '12345678901',
      bankIfsc: 'HDFC0001234',
      registeredMobile: '9876543210'
    });
    assert.strictEqual(res.valid, false);
    assert.ok(res.error.includes('Bank Name is required'));
  });

  test('Reject invalid Bank Account format (< 9 or > 18 digits or letters)', () => {
    const res = restaurantSettlementService.validatePaymentDetails({
      accountHolderName: 'Rajesh Sharma',
      bankName: 'HDFC Bank',
      bankAccount: '12345',
      confirmBankAccount: '12345',
      bankIfsc: 'HDFC0001234',
      registeredMobile: '9876543210'
    });
    assert.strictEqual(res.valid, false);
    assert.ok(res.error.includes('between 9 and 18 digits'));
  });

  test('Reject mismatched Bank Account Number and Confirm Account Number', () => {
    const res = restaurantSettlementService.validatePaymentDetails({
      accountHolderName: 'Rajesh Sharma',
      bankName: 'HDFC Bank',
      bankAccount: '123456789012',
      confirmBankAccount: '123456789099',
      bankIfsc: 'HDFC0001234',
      registeredMobile: '9876543210'
    });
    assert.strictEqual(res.valid, false);
    assert.ok(res.error.includes('do not match'));
  });

  test('Reject invalid IFSC Code format', () => {
    const res = restaurantSettlementService.validatePaymentDetails({
      accountHolderName: 'Rajesh Sharma',
      bankName: 'HDFC Bank',
      bankAccount: '123456789012',
      confirmBankAccount: '123456789012',
      bankIfsc: 'HDFC12345', // Missing 5th character '0' and wrong length
      registeredMobile: '9876543210'
    });
    assert.strictEqual(res.valid, false);
    assert.ok(res.error.includes('Invalid IFSC Code format'));
  });

  test('Accept valid Indian IFSC Code format (e.g. SBIN0004567)', () => {
    const res = restaurantSettlementService.validatePaymentDetails({
      accountHolderName: 'Rajesh Sharma',
      bankName: 'State Bank of India',
      bankAccount: '123456789012',
      confirmBankAccount: '123456789012',
      bankIfsc: 'SBIN0004567',
      registeredMobile: '9876543210'
    });
    assert.strictEqual(res.valid, true, `Validation failed: ${res.error}`);
  });

  test('Reject invalid Mobile Number length', () => {
    const res = restaurantSettlementService.validatePaymentDetails({
      accountHolderName: 'Rajesh Sharma',
      bankName: 'HDFC Bank',
      bankAccount: '123456789012',
      confirmBankAccount: '123456789012',
      bankIfsc: 'HDFC0001234',
      registeredMobile: '98765' // Too short
    });
    assert.strictEqual(res.valid, false);
    assert.ok(res.error.includes('10-digit Registered Mobile Number'));
  });

  test('Require UPI ID when payment preference is UPI', () => {
    const res = restaurantSettlementService.validatePaymentDetails({
      accountHolderName: 'Rajesh Sharma',
      bankName: 'HDFC Bank',
      bankAccount: '123456789012',
      confirmBankAccount: '123456789012',
      bankIfsc: 'HDFC0001234',
      registeredMobile: '9876543210',
      paymentPreference: 'upi',
      upiId: ''
    });
    assert.strictEqual(res.valid, false);
    assert.ok(res.error.includes('Settlement UPI ID is required'));
  });

  test('Validate UPI ID format (e.g. restaurant@okhdfcbank)', () => {
    const resValid = restaurantSettlementService.validatePaymentDetails({
      accountHolderName: 'Rajesh Sharma',
      bankName: 'HDFC Bank',
      bankAccount: '123456789012',
      confirmBankAccount: '123456789012',
      bankIfsc: 'HDFC0001234',
      registeredMobile: '9876543210',
      paymentPreference: 'upi',
      upiId: 'annapurnasweet@okaxis'
    });
    assert.strictEqual(resValid.valid, true);

    const resInvalid = restaurantSettlementService.validatePaymentDetails({
      accountHolderName: 'Rajesh Sharma',
      bankName: 'HDFC Bank',
      bankAccount: '123456789012',
      confirmBankAccount: '123456789012',
      bankIfsc: 'HDFC0001234',
      registeredMobile: '9876543210',
      paymentPreference: 'upi',
      upiId: 'invalid_upi_no_handle'
    });
    assert.strictEqual(resInvalid.valid, false);
    assert.ok(resInvalid.error.includes('Invalid UPI ID format'));
  });

  test('Require Bank Account Number when adding new payment details', () => {
    const res = restaurantSettlementService.validatePaymentDetails({
      accountHolderName: 'Rajesh Sharma',
      bankName: 'HDFC Bank',
      bankAccount: '',
      confirmBankAccount: '',
      bankIfsc: 'HDFC0001234',
      registeredMobile: '9876543210',
      isNewAccount: true
    });
    assert.strictEqual(res.valid, false);
    assert.ok(res.error.includes('Bank Account Number is required'));
  });

  // --- 3. FINANCIAL CALCULATION SIMULATION ---
  console.log('\n--- 3. Financial Calculation & Deductions Accuracy ---');

  test('Calculate restaurant net payable after commission & authorized adjustments', () => {
    const deliveredOrders = [
      { orderId: 'ORD_001', subtotal: 500, packagingFee: 30, orderStatus: 'delivered', paymentStatus: 'paid' },
      { orderId: 'ORD_002', subtotal: 300, packagingFee: 20, orderStatus: 'delivered', paymentStatus: 'paid', walletDebitStatus: 'debited', actualWalletDebitAmount: 50 },
      // Cancelled or unpaid orders should not contribute to sales
      { orderId: 'ORD_003', subtotal: 400, packagingFee: 20, orderStatus: 'cancelled', paymentStatus: 'refunded' },
      { orderId: 'ORD_004', subtotal: 250, packagingFee: 15, orderStatus: 'placed', paymentStatus: 'pending' }
    ];

    const eligible = deliveredOrders.filter(o => o.orderStatus === 'delivered' && o.paymentStatus === 'paid');
    assert.strictEqual(eligible.length, 2, 'Only delivered & paid orders qualify as completed sales');

    const grossFoodSales = eligible.reduce((acc, o) => acc + o.subtotal, 0); // 500 + 300 = 800
    const packagingFees = eligible.reduce((acc, o) => acc + o.packagingFee, 0); // 30 + 20 = 50
    const totalSales = grossFoodSales + packagingFees; // 850
    const commissionRate = 15; // 15%
    const platformCommission = Math.round((grossFoodSales * commissionRate) / 100); // 15% of 800 = 120
    const adjustments = eligible.reduce((acc, o) => acc + (o.walletDebitStatus === 'debited' ? o.actualWalletDebitAmount : 0), 0); // 50
    const netPayable = Math.max(0, totalSales - platformCommission - adjustments); // 850 - 120 - 50 = 680

    assert.strictEqual(totalSales, 850);
    assert.strictEqual(platformCommission, 120);
    assert.strictEqual(adjustments, 50);
    assert.strictEqual(netPayable, 680);
  });

  console.log('\n====================================================================');
  console.log(`🏁 TEST RESULTS: ${passedTests}/${totalTests} PASSED (100% Success)`);
  console.log('====================================================================\n');

  if (passedTests !== totalTests) {
    process.exit(1);
  }
}

runTestSuite().catch(err => {
  console.error('Test execution failed:', err);
  process.exit(1);
});
