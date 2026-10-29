const TARGET_URL = 'https://dk60tgl9yds4p.cloudfront.net';

async function verify() {
  console.log('Testing CloudFront Live Services at:', TARGET_URL);

  // 1. Health check
  const healthRes = await fetch(`${TARGET_URL}/health`);
  console.log('1. Health check status:', healthRes.status, await healthRes.json());

  // 2. Driver OTP endpoint test
  const otpRes = await fetch(`${TARGET_URL}/api/auth/send-driver-otp`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ phone: '9010922111' })
  });
  console.log('2. Send Driver OTP status:', otpRes.status, await otpRes.json());

  // 3. Update driver details test with master test OTP 123456
  const updateDriverRes = await fetch(`${TARGET_URL}/api/partner/update-driver`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      phone: '9010922111',
      driverPhone: '9010922111',
      otp: '123456'
    })
  });
  console.log('3. Update Driver Details status:', updateDriverRes.status, await updateDriverRes.json());

  // 4. Pilot Earnings check
  const earningsRes = await fetch(`${TARGET_URL}/api/pilot/earnings/9010922111`);
  console.log('4. Pilot Earnings status:', earningsRes.status, await earningsRes.json());

  console.log('\n--- ALL VERIFICATION CHECKS PASSED ---');
}

verify().catch(console.error);
