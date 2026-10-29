const http = require('http');

function postJson(path, body) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const options = {
      hostname: '127.0.0.1',
      port: 3000,
      path: path,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(data),
      },
      timeout: 10000,
    };
    const req = http.request(options, (res) => {
      let raw = '';
      res.on('data', chunk => raw += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(raw) });
        } catch (e) {
          resolve({ status: res.statusCode, raw });
        }
      });
    });
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

function getJson(path, headers = {}) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: '127.0.0.1',
      port: 3000,
      path: path,
      method: 'GET',
      headers: headers,
      timeout: 10000,
    };
    const req = http.request(options, (res) => {
      let raw = '';
      res.on('data', chunk => raw += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(raw) });
        } catch (e) {
          resolve({ status: res.statusCode, raw });
        }
      });
    });
    req.on('error', reject);
    req.end();
  });
}

async function runTest() {
  console.log('=== TEST 1: SIMULATE 3-SCREEN REGISTRATION DATA PERSISTENCE ===');
  const testPhone = '9876543210';
  const testUid = `mock_uid_${testPhone}_pilot`;

  // 1. Simulate document upload
  console.log('\n[Step 1] Uploading documents to /api/upload...');
  const dummyBase64 = Buffer.from('FAKE_IMAGE_DATA_FOR_TESTING').toString('base64');
  const uploadRes = await postJson('/api/upload', {
    uid: testUid,
    fileName: 'rc_front.jpg',
    fileData: dummyBase64,
    documentType: 'rcFront',
    mimeType: 'image/jpeg',
  });
  console.log('Upload Result:', uploadRes.status, uploadRes.data);
  const rcFrontUrl = uploadRes.data?.url || '/api/files/test_rc_front';

  // 2. Submit Screen 1, 2, 3 complete registration
  console.log('\n[Step 2] Submitting complete pilot registration to /api/partner/update...');
  const regPayload = {
    uid: testUid,
    name: 'Suresh Pilot',
    ownerName: 'Suresh Owner',
    driverName: 'Suresh Pilot',
    phone: testPhone,
    ownerPhone: testPhone,
    driverPhone: testPhone,
    role: 'partner',
    vehicleType: 'Car',
    vehiclePlate: 'TS 09 SD 9999',
    vehicleModelColor: 'White Sedan',
    dob: '15/08/1992',
    online: false,
    approved: false,
    isApproved: false,
    isDocumentVerified: false,
    photo: '/api/files/test_photo',
    aadhaarFront: '/api/files/test_aadhaar_front',
    aadhaarBack: '/api/files/test_aadhaar_back',
    panFront: '/api/files/test_pan_front',
    panBack: '/api/files/test_pan_back',
    licenseFront: '/api/files/test_license_front',
    licenseBack: '/api/files/test_license_back',
    rcFront: rcFrontUrl,
    rcBack: '/api/files/test_rc_back',
    fitness: '/api/files/test_fitness',
    permit: '/api/files/test_permit',
  };

  const regRes = await postJson('/api/partner/update', regPayload);
  console.log('Registration Result:', regRes.status, regRes.data);

  // 3. Verify pilot appears in Admin Panel API
  console.log('\n[Step 3] Verifying pilot in Admin Panel API (/api/admin/drivers)...');
  const adminRes = await getJson('/api/admin/drivers', {
    'x-admin-key': 'staydriv_admin_secret_2026',
  });

  if (Array.isArray(adminRes.data)) {
    const found = adminRes.data.find(d => d.phone === testPhone || d.uid === testUid);
    if (found) {
      console.log('SUCCESS: Pilot found in Admin Panel!');
      console.log({
        uid: found.uid,
        name: found.name,
        driverName: found.driverName,
        ownerName: found.ownerName,
        phone: found.phone,
        vehicleType: found.vehicleType,
        vehiclePlate: found.vehiclePlate,
        status: found.status,
        documents: found.documents ? Object.keys(found.documents) : 'none',
        rcFront: found.rcFront,
        aadhaarFront: found.aadhaarFront,
        licenseFront: found.licenseFront,
        panFront: found.panFront,
      });
    } else {
      console.log('Pilot not found in drivers array. Total drivers:', adminRes.data.length);
    }
  } else {
    console.log('Admin drivers response:', adminRes.status, adminRes.data);
  }

  console.log('\n=== TEST COMPLETE ===');
}

runTest().catch(console.error);
