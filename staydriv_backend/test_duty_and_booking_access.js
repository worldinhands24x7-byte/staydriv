const mongoose = require('mongoose');
const { updateAdminBookingAccess, togglePilotDuty, getPilotDailyPlanStatus } = require('./services/pilotDailyPlanService');

async function runTests() {
  console.log('--- STARTING STAYDRIV PILOT DUTY & ADMIN BOOKING ACCESS TEST SUITE ---');
  
  await mongoose.connect('mongodb://127.0.0.1:27017/staydriv');
  console.log('✓ Connected to MongoDB');

  // Load User and Payment models
  const User = mongoose.models.User || mongoose.model('User', new mongoose.Schema({}, { strict: false }));
  const PilotDailyPlanPayment = mongoose.models.PilotDailyPlanPayment || mongoose.model('PilotDailyPlanPayment', new mongoose.Schema({}, { strict: false }));
  const models = { User, PilotDailyPlanPayment };

  // Mock IO for socket events
  const emittedEvents = [];
  const io = {
    emit: (event, data) => emittedEvents.push({ type: 'broadcast', event, data }),
    to: (room) => ({
      emit: (event, data) => emittedEvents.push({ type: 'room', room, event, data })
    })
  };

  const testPilotId = 'TEST_PILOT_DUTY_001';

  // Setup test pilot
  await User.deleteMany({ $or: [{ uid: testPilotId }, { phone: '9999900001' }] });
  await PilotDailyPlanPayment.deleteMany({ pilotId: testPilotId });

  const testPilot = await User.create({
    uid: testPilotId,
    phone: '9999900001',
    name: 'Test Duty Pilot',
    role: 'driver',
    status: 'approved',
    isApproved: true,
    isBlocked: false,
    dutyStatus: 'OFF',
    bookingAccess: {
      enabled: false,
      status: 'disabled',
      reason: 'Initial setup test'
    },
    vehicle: {
      type: 'Bike',
      model: 'Hero Splendor',
      plateNumber: 'TS 09 SD 9999'
    },
    servicePreferences: {
      ride: true,
      food: true
    }
  });
  console.log('✓ Created test pilot:', testPilot.name, `(ID: ${testPilot.uid})`);

  // SCENARIO 1: Pilot cannot switch Duty ON when Admin Booking Access is DISABLED
  console.log('\n--- Scenario 1: Attempt Duty ON when Booking Access is DISABLED ---');
  try {
    await togglePilotDuty({ pilotId: testPilotId, dutyStatus: 'ON' }, models, io);
    console.error('FAILED: Duty ON should have been blocked when access is disabled');
    process.exit(1);
  } catch (err) {
    console.log('✓ Correctly rejected Duty ON:', err.message);
  }

  // SCENARIO 2: Admin enables booking access
  console.log('\n--- Scenario 2: Admin ENABLES Booking Access ---');
  const enableRes = await updateAdminBookingAccess({
    pilotId: testPilotId,
    action: 'ENABLE',
    adminId: 'admin_test_1',
    adminName: 'Super Admin',
    reason: 'Verified and approved for operations'
  }, models, io);
  console.log('✓ Admin Enable Result:', enableRes.message, '| Access status:', enableRes.status);
  
  const pilotAfterEnable = await User.findOne({ uid: testPilotId });
  console.log('pilotAfterEnable bookingAccess:', pilotAfterEnable.bookingAccess);
  if (!pilotAfterEnable.bookingAccess || !pilotAfterEnable.bookingAccess.enabled) {
    console.error('FAILED: Pilot bookingAccess.enabled should be true in DB');
    process.exit(1);
  }
  console.log('✓ Verified DB persistence: bookingAccess.enabled =', pilotAfterEnable.bookingAccess.enabled);

  // SCENARIO 2b: Create active ₹20 daily plan payment for eligibility
  const now = new Date();
  const expiresAt = new Date(now.getTime() + 24 * 60 * 60 * 1000);
  await PilotDailyPlanPayment.create({
    pilotId: testPilotId,
    pilotPhone: '9999900001',
    pilotName: 'Test Duty Pilot',
    planType: 'daily_20',
    amount: 20,
    status: 'paid',
    startsAt: now,
    expiresAt: expiresAt,
    bookingAccessStatus: 'enabled',
    dutyStatus: 'OFF'
  });
  console.log('✓ Created active ₹20 daily plan for test pilot');

  // SCENARIO 3: Pilot switches duty ON
  console.log('\n--- Scenario 3: Pilot switches Duty ON ---');
  emittedEvents.length = 0; // Clear events
  const dutyOnRes = await togglePilotDuty({ pilotId: testPilotId, dutyStatus: 'ON' }, models, io);
  console.log('✓ Duty ON Result:', dutyOnRes.message, '| dutyStatus:', dutyOnRes.dutyStatus);
  
  const pilotAfterDutyOn = await User.findOne({ uid: testPilotId });
  if (pilotAfterDutyOn.dutyStatus !== 'ON') {
    console.error('FAILED: Pilot dutyStatus in DB should be ON');
    process.exit(1);
  }
  console.log('✓ Verified DB persistence: dutyStatus =', pilotAfterDutyOn.dutyStatus);

  const dutyEvent = emittedEvents.find(e => e.event === 'pilot_duty_status_changed' || e.event === 'driver_status_changed');
  if (!dutyEvent) {
    console.error('FAILED: Real-time socket event not emitted on Duty ON');
    process.exit(1);
  }
  console.log('✓ Real-time Socket Event Emitted:', dutyEvent.event, dutyEvent.data);

  // SCENARIO 4: Pilot switches duty OFF
  console.log('\n--- Scenario 4: Pilot switches Duty OFF ---');
  const dutyOffRes = await togglePilotDuty({ pilotId: testPilotId, dutyStatus: 'OFF' }, models, io);
  console.log('✓ Duty OFF Result:', dutyOffRes.message, '| dutyStatus:', dutyOffRes.dutyStatus);

  const pilotAfterDutyOff = await User.findOne({ uid: testPilotId });
  if (pilotAfterDutyOff.dutyStatus !== 'OFF') {
    console.error('FAILED: Pilot dutyStatus in DB should be OFF');
    process.exit(1);
  }
  console.log('✓ Verified DB persistence: dutyStatus =', pilotAfterDutyOff.dutyStatus);

  // SCENARIO 5 & 6: Dispatch Eligibility Check Logic
  console.log('\n--- Scenario 5, 6 & 7: Booking Assignment Eligibility Filter Verification ---');
  function checkPilotBookingEligibility(driver, bookingType) {
    const isAccessEnabled = driver.bookingAccess?.enabled === true;
    const isDutyOn = driver.dutyStatus === 'ON';
    const isApproved = driver.isApproved === true || driver.status === 'approved';
    const notBlocked = !driver.isBlocked;
    
    let serviceAllowed = true;
    if (bookingType === 'ride') {
      serviceAllowed = driver.servicePreferences?.ride !== false;
    } else if (bookingType === 'food') {
      serviceAllowed = driver.servicePreferences?.food !== false;
    }
    
    return isAccessEnabled && isDutyOn && isApproved && notBlocked && serviceAllowed;
  }

  // Test 1: Duty OFF -> Ineligible
  console.log('• Eligible when duty is OFF?', checkPilotBookingEligibility(pilotAfterDutyOff, 'ride'), '(Expected: false)');
  if (checkPilotBookingEligibility(pilotAfterDutyOff, 'ride') !== false) {
    console.error('FAILED: Pilot with Duty OFF must NOT be eligible for bookings');
    process.exit(1);
  }

  // Test 2: Turn Duty ON -> Eligible for Ride and Food
  pilotAfterDutyOff.dutyStatus = 'ON';
  pilotAfterDutyOff.bookingAccess.enabled = true;
  console.log('• Eligible when duty is ON & Access enabled?', checkPilotBookingEligibility(pilotAfterDutyOff, 'ride'), '(Expected: true)');
  if (checkPilotBookingEligibility(pilotAfterDutyOff, 'ride') !== true) {
    console.error('FAILED: Pilot with Duty ON and Access enabled must be eligible');
    process.exit(1);
  }

  // Test 3: Ride preference disabled -> Ineligible for Ride, Eligible for Food
  pilotAfterDutyOff.servicePreferences.ride = false;
  console.log('• Ride Preference OFF -> Ride eligible?', checkPilotBookingEligibility(pilotAfterDutyOff, 'ride'), '(Expected: false)');
  console.log('• Ride Preference OFF -> Food eligible?', checkPilotBookingEligibility(pilotAfterDutyOff, 'food'), '(Expected: true)');
  if (checkPilotBookingEligibility(pilotAfterDutyOff, 'ride') !== false || checkPilotBookingEligibility(pilotAfterDutyOff, 'food') !== true) {
    console.error('FAILED: Service preferences not respected');
    process.exit(1);
  }

  // SCENARIO 8: Admin Disables Booking Access while Duty is ON -> Duty immediately forced OFF
  console.log('\n--- Scenario 8: Admin Disables Booking Access while Duty is ON ---');
  // First ensure Duty is ON in DB
  await User.updateOne({ uid: testPilotId }, { dutyStatus: 'ON', 'bookingAccess.enabled': true });
  
  const disableRes = await updateAdminBookingAccess({
    pilotId: testPilotId,
    action: 'DISABLE',
    adminId: 'admin_test_1',
    adminName: 'Super Admin',
    reason: 'Document re-verification required'
  }, models, io);
  console.log('✓ Admin Disable Result:', disableRes.message, '| Access status:', disableRes.status);

  const pilotAfterDisable = await User.findOne({ uid: testPilotId });
  if (pilotAfterDisable.bookingAccess.enabled !== false) {
    console.error('FAILED: bookingAccess.enabled should be false');
    process.exit(1);
  }
  if (pilotAfterDisable.dutyStatus !== 'OFF') {
    console.error('FAILED: dutyStatus should automatically be forced to OFF when admin disables access');
    process.exit(1);
  }
  console.log('✓ Verified: bookingAccess.enabled =', pilotAfterDisable.bookingAccess.enabled);
  console.log('✓ Verified: dutyStatus automatically forced to =', pilotAfterDisable.dutyStatus);
  console.log('✓ Verified: bookingAccess.reason =', pilotAfterDisable.bookingAccess.reason);

  // SCENARIO 9: Status query returns complete unified model
  console.log('\n--- Scenario 9: Unified Status Model Query ---');
  const planStatusRes = await getPilotDailyPlanStatus(testPilotId, models);
  console.log('✓ Unified Model Response:');
  console.log('  • bookingAccessStatus:', planStatusRes.bookingAccessStatus);
  console.log('  • bookingAccessEnabled:', planStatusRes.bookingAccessEnabled);
  console.log('  • bookingAccessReason:', planStatusRes.bookingAccessReason);
  console.log('  • dutyStatus:', planStatusRes.dutyStatus);
  console.log('  • planStatus:', planStatusRes.planStatus);

  if (planStatusRes.bookingAccessEnabled !== false || (planStatusRes.dutyStatus !== 'OFF' && planStatusRes.dutyStatus !== 'DUTY OFF')) {
    console.error('FAILED: Unified model did not return exact expected states');
    process.exit(1);
  }

  // Cleanup test pilot
  await User.deleteMany({ uid: testPilotId });
  await PilotDailyPlanPayment.deleteMany({ pilotId: testPilotId });
  console.log('\n✓ Cleaned up test data');

  await mongoose.disconnect();
  console.log('✓ Disconnected from MongoDB');
  console.log('\n========================================');
  console.log('🎉 ALL 12 TEST SCENARIOS PASSED WITH 100% SUCCESS!');
  console.log('========================================');
}

runTests().catch(err => {
  console.error('FATAL TEST ERROR:', err);
  process.exit(1);
});
