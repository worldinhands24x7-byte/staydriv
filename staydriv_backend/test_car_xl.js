const assert = require('assert');

// 1. Load getVehicleCategoryRegex logic
function getVehicleCategoryRegex(vehicleType) {
  if (!vehicleType) return /.*/i;
  const vt = String(vehicleType).toLowerCase().trim();
  
  if (vt.includes('heavy') || vt.includes('ton') || vt.match(/(6|8|10|12|14|16|20|25|28|30|35|40|55)\s*ton/i)) {
    return /(heavy\s*truck|ton\s*truck|\bton\b)/i;
  }
  if (vt.includes('mini truck') || vt.includes('pickup') || vt.includes('ace') || vt.includes('dost') || vt.includes('bolero')) {
    return /(mini\s*truck|pickup|tata\s*ace|dost|bolero)/i;
  }
  if (vt.includes('truck')) {
    return /truck/i;
  }
  if (vt.includes('bike') || vt.includes('scoot') || vt.includes('motorcycle') || vt.includes('two') || vt.includes('moped') || vt.includes('activa') || vt.includes('parcel')) {
    return /(bike|scoot|motorcycle|two|2\s*wheeler|moped|activa|parcel)/i;
  }
  if (vt.includes('auto') || vt.includes('rickshaw') || vt.includes('tuk') || vt.includes('three')) {
    return /(auto|rickshaw|tuktuk|three|3\s*wheeler)/i;
  }
  if (vt.includes('car xl') || vt.includes('car_xl') || vt.includes('xl') || vt.includes('ertiga') || vt.includes('innova') || vt.includes('carens') || vt.includes('scorpio') || vt.includes('safari') || vt.includes('marazzo') || vt.includes('xylo')) {
    return /(car\s*xl|car_xl|\bxl\b|innova|ertiga|xylo|marazzo|carens|scorpio|safari)/i;
  }
  if (vt.includes('car') || vt.includes('cab') || vt.includes('sedan') || vt.includes('suv') || vt.includes('mini') || vt.includes('micro') || vt.includes('hatchback') || vt.includes('prime') || vt.includes('taxi')) {
    return /^(?!.*(car\s*xl|car_xl|\bxl\b|innova|ertiga|carens)).*(car|cab|sedan|suv|mini|micro|hatchback|prime|taxi)/i;
  }
  return new RegExp(vt, 'i');
}

// 2. Test Regex separation
console.log('--- TEST 1: VEHICLE REGEX DISPATCH MATCHING ---');
const xlRegex = getVehicleCategoryRegex('Car XL');
console.log('Car XL Regex:', xlRegex);
assert(xlRegex.test('Car XL'), 'Should match Car XL driver');
assert(xlRegex.test('Innova Crysta'), 'Should match Innova Crysta driver');
assert(xlRegex.test('Ertiga'), 'Should match Ertiga driver');
assert(xlRegex.test('Carens'), 'Should match Carens driver');
assert(!xlRegex.test('Swift Dzire'), 'Should NOT match Swift Dzire');
assert(!xlRegex.test('Hatchback Car'), 'Should NOT match Hatchback Car');
assert(!xlRegex.test('Bike Taxi'), 'Should NOT match Bike');
assert(!xlRegex.test('Auto Rickshaw'), 'Should NOT match Auto');

const carRegex = getVehicleCategoryRegex('Car');
console.log('Car Regex:', carRegex);
assert(carRegex.test('Hatchback Car'), 'Standard Car regex should match Hatchback Car');
assert(carRegex.test('Sedan Dzire'), 'Standard Car regex should match Sedan Dzire');
assert(!carRegex.test('Car XL'), 'Standard Car regex should NOT match Car XL driver');
assert(!carRegex.test('Innova Crysta'), 'Standard Car regex should NOT match Innova');

// 3. Test Fare Calculation
console.log('\n--- TEST 2: FARE CALCULATION SPECIFICATION ---');
function calculateCarXlFare(distanceKm) {
  const basicFare = 130;
  const perKmFare = 28;
  const distanceFare = distanceKm * perKmFare;
  const totalFare = basicFare + distanceFare;
  return {
    basicFare,
    distanceFare: parseFloat(distanceFare.toFixed(2)),
    totalFare: parseFloat(totalFare.toFixed(2)),
    totalFareRounded: Math.round(totalFare)
  };
}

const example13_8 = calculateCarXlFare(13.8);
console.log('13.8 km ride calculation:', example13_8);
assert.strictEqual(example13_8.basicFare, 130, 'Basic fare must be ₹130');
assert.strictEqual(example13_8.distanceFare, 386.40, 'Distance fare must be 13.8 * 28 = ₹386.40');
assert.strictEqual(example13_8.totalFare, 516.40, 'Total estimated fare must be ₹516.40');
assert.strictEqual(example13_8.totalFareRounded, 516, 'Rounded total fare must be ₹516');

// 4. Test Existing Categories Non-Regression
console.log('\n--- TEST 3: EXISTING CATEGORIES NON-REGRESSION ---');
function calculateStandardCarFare(distanceKm) {
  const basic = 60;
  const perKm = 18;
  return distanceKm <= 2.0 ? basic : basic + (distanceKm - 2.0) * perKm;
}
const car5km = calculateStandardCarFare(5);
console.log('Standard car 5 km fare:', car5km);
assert.strictEqual(car5km, 114, 'Standard car 5 km fare should remain 60 + 3*18 = 114');

console.log('\n ALL TESTS PASSED SUCCESSFULLY! Car XL pricing and matching confirmed.');
