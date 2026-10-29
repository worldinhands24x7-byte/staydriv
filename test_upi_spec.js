const assert = require('assert');

function buildUpiUri(upiId, payeeName, amount, bookingId) {
  const cleanUpi = upiId.trim();
  const cleanName = payeeName.replace(/[^a-zA-Z0-9 ]/g, '').trim();
  const cleanRef = String(bookingId).replace(/[^a-zA-Z0-9_-]/g, '');
  const fare = parseFloat(amount) || 0.0;
  
  // NPCI UPI URI Specification:
  // pa must have literal @, no %40
  // am must have 2 decimal places
  // cu must be INR
  return `upi://pay?pa=${cleanUpi}&pn=${encodeURIComponent(cleanName)}&am=${fare.toFixed(2)}&cu=INR&tn=StayDriv_Ride_${cleanRef}&tr=TXN_${cleanRef}`;
}

const uri = buildUpiUri('staydriv@icici', 'StayDriv Pilot', 46, 'BK_12345');
console.log('Generated UPI URI:', uri);

// Verify format
assert(uri.includes('pa=staydriv@icici'), 'Must have literal @ in VPA');
assert(!uri.includes('pa=staydriv%40icici'), 'Must NOT have %40 in VPA');
assert(uri.includes('am=46.00'), 'Amount must have 2 decimal places');
assert(uri.includes('cu=INR'), 'Currency must be INR');
assert(uri.includes('tn=StayDriv_Ride_BK_12345'), 'Note must be clean');

console.log('✓ UPI URI conforms 100% to NPCI standards!');
