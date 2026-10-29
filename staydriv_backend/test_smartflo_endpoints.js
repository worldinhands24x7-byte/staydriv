// test_smartflo_endpoints.js
require('dotenv').config();
const smartfloService = require('./services/smartflo_service');
const assert = require('assert');

async function runTests() {
  console.log('--- STARTING SMARTFLO CALL MASKING VERIFICATION SUITE ---');

  // 1. Test formatPhone
  console.log('1. Testing formatPhone...');
  assert.strictEqual(smartfloService.formatPhone('9876543210'), '9876543210');
  assert.strictEqual(smartfloService.formatPhone('+919876543210'), '9876543210');
  assert.strictEqual(smartfloService.formatPhone('09876543210'), '9876543210');
  assert.strictEqual(smartfloService.formatPhone('+91 98765-43210'), '9876543210');
  assert.strictEqual(smartfloService.formatPhone(''), '');
  console.log('  ✓ formatPhone passed');

  // 2. Test maskPhone (STEP 12: e.g. 98******21)
  console.log('2. Testing maskPhone (98******21 format)...');
  assert.strictEqual(smartfloService.maskPhone('9876543221'), '98******21');
  assert.strictEqual(smartfloService.maskPhone('+919490440281'), '94******81');
  assert.strictEqual(smartfloService.maskPhone('123'), '******');
  console.log('  ✓ maskPhone passed');

  // 3. Test intelligent token & key resolution
  console.log('3. Testing intelligent token and key resolution...');
  const token = smartfloService.apiToken;
  assert(token.startsWith('eyJ'), 'apiToken must resolve to the valid JWT starting with eyJ');
  const key = smartfloService.apiKey;
  assert(!key.startsWith('eyJ'), 'apiKey must resolve to the key identifier, not the JWT');
  console.log('  ✓ token & key resolution passed');

  // 4. Test idempotency checkAndAcquireCallLock (STEP 10)
  console.log('4. Testing idempotency checkAndAcquireCallLock...');
  const bookingId = 'booking_test_verify';
  const role = 'customer';
  
  const firstAcquire = smartfloService.checkAndAcquireCallLock(bookingId, role);
  assert.strictEqual(firstAcquire.acquired, true, 'First call lock must be acquired');

  const secondAcquire = smartfloService.checkAndAcquireCallLock(bookingId, role);
  assert.strictEqual(secondAcquire.acquired, false, 'Immediate duplicate call must be blocked');
  assert(secondAcquire.retryAfter > 0, 'Retry-after must be positive');

  smartfloService.releaseCallLock(bookingId, role);
  const thirdAcquire = smartfloService.checkAndAcquireCallLock(bookingId, role);
  assert.strictEqual(thirdAcquire.acquired, true, 'Lock should be acquirable after release');
  smartfloService.releaseCallLock(bookingId, role);
  console.log('  ✓ checkAndAcquireCallLock (idempotency) passed');

  // 5. Test initiateClickToCall validation
  console.log('5. Testing initiateClickToCall phone number validation...');
  try {
    await smartfloService.initiateClickToCall({
      agentPhone: '123',
      destinationPhone: '9876543210'
    });
    assert.fail('Should have thrown on invalid agent phone number');
  } catch (err) {
    assert(err.message.includes('Invalid agent or destination phone number'));
    console.log('  ✓ initiateClickToCall invalid agent validation passed');
  }

  // 6. Test Live Tata Smartflo API integration (STEP 3 & STEP 4)
  console.log('6. Testing Live Tata Smartflo Click-to-Call API call...');
  try {
    const liveResult = await smartfloService.initiateClickToCall({
      agentPhone: '9876500001',
      destinationPhone: '9876500002',
      bookingId: 'BK_TEST_VERIFY_999'
    });
    console.log('  Smartflo response:', liveResult.statusCode, liveResult.refId, liveResult.message);
    assert.strictEqual(liveResult.success, true);
    assert(liveResult.refId, 'refId must be returned by Tata Smartflo');
    console.log('  ✓ Live Tata Smartflo Click-to-Call API passed!');
  } catch (err) {
    console.error('  Live API test error:', err.message);
    throw err;
  }

  console.log('--- ALL SMARTFLO TESTS PASSED SUCCESSFULLY! ---');
}

runTests().catch(err => {
  console.error('Test suite failed:', err);
  process.exit(1);
});
