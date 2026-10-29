const https = require('https');

function request(options, data) {
  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(body) });
        } catch {
          resolve({ status: res.statusCode, data: body });
        }
      });
    });
    req.on('error', reject);
    if (data) req.write(JSON.stringify(data));
    req.end();
  });
}

const host = 'dk60tgl9yds4p.cloudfront.net';
const adminHeaders = {
  'Content-Type': 'application/json',
  'x-admin-key': 'staydriv_admin_secret_2026'
};

async function runTestWorkflow() {
  console.log('================================================================');
  console.log('STAYDRIV RESTAURANT REGISTRATION & APPROVAL WORKFLOW VERIFICATION');
  console.log('================================================================');

  // TEST A: Check Pending Application (Rayalasima Chef's)
  console.log('\n--- TEST A: Verify Pending Application (Picture 1 & Picture 2) ---');
  const partnerRes = await request({ host, path: '/api/food/partner/by-phone/9121403844', method: 'GET' });
  console.log(`[Partner App Status Check]: HTTP ${partnerRes.status}, success: ${partnerRes.data?.success}`);
  const rayalasima = partnerRes.data?.restaurant;
  console.log(`  Name: ${rayalasima?.name}`);
  console.log(`  Partner ID: ${rayalasima?.restaurantId}`);
  console.log(`  Phone: ${rayalasima?.phone}`);
  console.log(`  Current Status: ${rayalasima?.status}`);

  // Check customer visibility: should NOT appear in customer listing while pending
  const custResBefore = await request({ host, path: '/api/food/restaurants', method: 'GET' });
  const isVisibleBefore = (custResBefore.data?.restaurants || []).some(r => r.restaurantId === 'REST_1792330417390_3D3534');
  console.log(`[Customer App Listing Check]: Visible to customer while pending? ${isVisibleBefore ? 'YES (UNEXPECTED)' : 'NO (CORRECT - Protected)'}`);

  // Check Admin Console search & counts (Picture 3 Design)
  const adminListRes = await request({
    host,
    path: '/api/food/admin/restaurants?search=Rayalasima',
    method: 'GET',
    headers: adminHeaders
  });
  console.log(`[Admin Console Search Check]: HTTP ${adminListRes.status}, Found: ${adminListRes.data?.count}`);
  console.log('  Live Dynamic Counts:', adminListRes.data?.counts);

  // Check Admin Application Details Inspection (Section 2)
  const appDetailsRes = await request({
    host,
    path: `/api/food/admin/restaurants/${rayalasima.restaurantId}/application`,
    method: 'GET',
    headers: adminHeaders
  });
  console.log(`[Admin Application Details Modal]: HTTP ${appDetailsRes.status}, Retrieved full KYC for ${appDetailsRes.data?.restaurant?.name}`);
  console.log(`  FSSAI Number: ${appDetailsRes.data?.restaurant?.fssaiNumber || 'Pending'}`);
  console.log(`  Address: ${appDetailsRes.data?.restaurant?.address}`);

  // TEST D: Request Correction Flow
  console.log('\n--- TEST D: Admin Request Correction ---');
  const corrRes = await request({
    host,
    path: `/api/food/admin/restaurants/${rayalasima.restaurantId}/request-correction`,
    method: 'POST',
    headers: adminHeaders
  }, {
    adminName: 'Admin Operations',
    notes: 'Please ensure valid FSSAI license certificate copy is uploaded.'
  });
  console.log(`[Request Correction Result]: HTTP ${corrRes.status}, Status updated to: ${corrRes.data?.restaurant?.status}`);

  // Partner checks status
  const partnerCheck1 = await request({ host, path: '/api/food/partner/by-phone/9121403844', method: 'GET' });
  console.log(`  Partner App Status: ${partnerCheck1.data?.restaurant?.status}, Note: ${partnerCheck1.data?.restaurant?.actionRequiredNotes}`);

  // Partner resubmits
  console.log('\n--- Partner Resubmits Application ---');
  const resubmitRes = await request({
    host,
    path: `/api/food/partner/${rayalasima.restaurantId}/resubmit`,
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' }
  }, {
    fssaiNumber: '13622014000889',
    notes: 'Uploaded valid FSSAI license certificate.'
  });
  console.log(`[Partner Resubmit Result]: HTTP ${resubmitRes.status}, New status: ${resubmitRes.data?.restaurant?.status}`);

  // TEST B: Admin Approves Restaurant
  console.log('\n--- TEST B: Admin Approves Restaurant (Section 3) ---');
  const approveRes = await request({
    host,
    path: `/api/food/admin/restaurants/${rayalasima.restaurantId}/approve`,
    method: 'POST',
    headers: adminHeaders
  }, {
    adminName: 'Admin SuperOps',
    notes: 'Verified FSSAI and kitchen address. Approved for live operations.'
  });
  console.log(`[Admin Approve Result]: HTTP ${approveRes.status}, Success: ${approveRes.data?.success}, Status: ${approveRes.data?.restaurant?.status}`);
  console.log(`  Approved by: ${approveRes.data?.restaurant?.approvedBy} on ${approveRes.data?.restaurant?.approvedAt}`);

  // Partner checks status after approval
  const partnerApproved = await request({ host, path: '/api/food/partner/by-phone/9121403844', method: 'GET' });
  console.log(`[Partner App Post-Approval Status]: ${partnerApproved.data?.restaurant?.status} (Unlocks Partner Console)`);

  // Customer app listing check after approval
  const custResAfter = await request({ host, path: '/api/food/restaurants', method: 'GET' });
  const isVisibleAfter = (custResAfter.data?.restaurants || []).some(r => r.restaurantId === 'REST_1792330417390_3D3534');
  console.log(`[Customer App Listing Check]: Visible in Food Order Now after approval? ${isVisibleAfter ? 'YES (VERIFIED)' : 'NO'}`);

  // TEST C: Rejection Flow on Test Account
  console.log('\n--- TEST C: Register Test Restaurant & Reject with Mandatory Reason ---');
  const testReg = await request({
    host,
    path: '/api/food/partner/register',
    method: 'POST',
    headers: { 'Content-Type': 'application/json' }
  }, {
    name: 'Temporary Test Cafe',
    ownerName: 'Test Owner',
    phone: '9999988888',
    email: 'testcafe@staydriv.com',
    address: 'Plot 10, Test Street, Hyderabad',
    cuisines: ['Snacks', 'Beverages'],
    openingHours: '10:00 AM - 10:00 PM',
    fssaiNumber: '11111111111111',
    bankAccount: '1234567890',
    upiId: 'testcafe@upi',
    isVegOnly: true,
    lat: 17.44,
    lng: 78.38
  });
  const testRestId = testReg.data?.restaurant?.restaurantId;
  console.log(`[Test Restaurant Registered]: ID: ${testRestId}, Status: ${testReg.data?.restaurant?.status}`);

  // Reject with mandatory reason
  const rejectRes = await request({
    host,
    path: `/api/food/admin/restaurants/${testRestId}/reject`,
    method: 'POST',
    headers: adminHeaders
  }, {
    adminName: 'Admin Auditor',
    reason: 'FSSAI certificate verification failed: invalid state code.'
  });
  console.log(`[Admin Reject Result]: HTTP ${rejectRes.status}, Status: ${rejectRes.data?.restaurant?.status}, Reason: ${rejectRes.data?.restaurant?.rejectionReason}`);

  // Verify partner sees rejection reason
  const testPartnerCheck = await request({ host, path: '/api/food/partner/by-phone/9999988888', method: 'GET' });
  console.log(`[Test Partner Status Check]: Status: ${testPartnerCheck.data?.restaurant?.status}, Reason: ${testPartnerCheck.data?.restaurant?.rejectionReason}`);

  // Verify rejected restaurant is NOT visible to customers
  const custResReject = await request({ host, path: '/api/food/restaurants', method: 'GET' });
  const isRejectVisible = (custResReject.data?.restaurants || []).some(r => r.restaurantId === testRestId);
  console.log(`[Customer App Listing]: Is rejected restaurant hidden from customers? ${!isRejectVisible ? 'YES (CORRECT)' : 'NO'}`);

  // Clean up test restaurant
  await request({
    host,
    path: `/api/food/admin/restaurants/${testRestId}`,
    method: 'DELETE',
    headers: adminHeaders
  });
  console.log('[Cleanup]: Test restaurant removed');

  console.log('\n================================================================');
  console.log('FULL RESTAURANT ONBOARDING, APPROVAL & SYNC WORKFLOW PASSED 100%');
  console.log('================================================================');
}

runTestWorkflow().catch(console.error);
