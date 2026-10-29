/**
 * StayDriv Food Delivery Pilot Eligibility Service
 * 
 * STRICT RULE: Only approved, active, online Bike and Scooty pilots
 * can be assigned to food delivery orders.
 * Auto Rickshaw, Car, Mini, Sedan, SUV, Van, Truck, and all other vehicle types
 * are strictly prohibited from food delivery.
 */

const mongoose = require('mongoose');

// Canonical list of allowed 2-wheeler aliases for food delivery
const ALLOWED_FOOD_DELIVERY_VEHICLE_NORMALIZED = new Set([
  'bike',
  'motorcycle',
  'scooty',
  'scooter',
  '2wheeler',
  'twowheeler',
  'two-wheeler',
  'two wheeler'
]);

// Explicit list of forbidden vehicle substrings
const FORBIDDEN_VEHICLE_SUBSTRINGS = [
  'auto',
  'rickshaw',
  'car',
  'sedan',
  'suv',
  'mini',
  'truck',
  'van',
  'ace',
  'pickup',
  'bus',
  'tempo'
];

/**
 * Normalizes vehicle type string to lowercase alphanumeric representation
 * @param {string} vehicleType 
 * @returns {string}
 */
function normalizeVehicleType(vehicleType) {
  if (!vehicleType || typeof vehicleType !== 'string') return '';
  return vehicleType.trim().toLowerCase().replace(/[\s_-]+/g, '');
}

/**
 * Synchronous check whether a vehicle type string qualifies for food delivery
 * @param {string} vehicleType 
 * @returns {boolean}
 */
function isFoodDeliveryVehicle(vehicleType) {
  if (!vehicleType || typeof vehicleType !== 'string') return false;
  
  const rawLower = vehicleType.trim().toLowerCase();
  
  // 1. Check forbidden substrings first (Auto, Rickshaw, Car, SUV, etc.)
  for (const forbidden of FORBIDDEN_VEHICLE_SUBSTRINGS) {
    if (rawLower.includes(forbidden)) {
      return false;
    }
  }

  // 2. Normalize and check against allowed 2-wheeler set
  const normalized = normalizeVehicleType(vehicleType);
  if (
    normalized === 'bike' ||
    normalized === 'motorcycle' ||
    normalized === 'scooty' ||
    normalized === 'scooter' ||
    normalized === '2wheeler' ||
    normalized === 'twowheeler'
  ) {
    return true;
  }

  return false;
}

/**
 * Comprehensive eligibility evaluation for a pilot record
 * @param {object} pilot Pilot user document/object from MongoDB
 * @param {object} options Optional validation flags { requireOnline, checkActiveRide, submittedVehicleType }
 * @returns {{ eligible: boolean, reason?: string, normalizedVehicle?: string }}
 */
function isEligibleForFoodDelivery(pilot, options = {}) {
  const {
    requireOnline = false,
    checkActiveRide = false,
    submittedVehicleType = null,
    checkFoodServiceEnabled = false
  } = options;

  if (!pilot) {
    return { eligible: false, reason: 'Pilot record not found' };
  }

  // 1. Role verification
  if (pilot.role && pilot.role !== 'partner') {
    return { eligible: false, reason: `Invalid role '${pilot.role}'. Must be a registered partner/pilot.` };
  }

  // 2. Approval status verification
  const isApproved = pilot.status === 'approved' ||
                     pilot.partnerStatus === 'approved' ||
                     pilot.partnerApprovalStatus === 'approved' ||
                     pilot.approved === true ||
                     pilot.isApproved === true;
  if (!isApproved) {
    return { eligible: false, reason: `Pilot account is not approved (status: '${pilot.partnerStatus || pilot.status || 'pending'}')` };
  }

  // 2b. Admin-Controlled Duty Status and Booking Access check
  const isDutyOff = pilot.dutyStatus === 'OFF' || pilot.dutyStatus === 'DUTY OFF' ||
                    (pilot.bookingAccess && (pilot.bookingAccess.enabled === false || pilot.bookingAccess.status === 'disabled'));
  if (isDutyOff) {
    return {
      eligible: false,
      reason: pilot.bookingAccess?.disabledReason || 'Your duty is currently OFF. Please contact the Admin to enable booking access.'
    };
  }

  // 2c. Mandatory ₹20 Daily Plan Payment and Expiry check
  const dPlan = pilot.dailyPlan || {};
  if (dPlan.planStatus !== 'paid') {
    return {
      eligible: false,
      reason: dPlan.planStatus === 'expired' 
        ? 'Daily ₹20 plan has expired. Please renew to receive food delivery orders.' 
        : 'Daily ₹20 plan fee has not been paid. Pay ₹20 to activate 100% earnings.'
    };
  }
  if (!dPlan.expiresAt || new Date() >= new Date(dPlan.expiresAt)) {
    return {
      eligible: false,
      reason: 'Daily ₹20 plan has expired. Please renew to receive food delivery orders.'
    };
  }

  // 3. Mandatory registered vehicle verification from DB
  const registeredVehicle = pilot.vehicleType || pilot.vehicleSubtype || '';
  if (!isFoodDeliveryVehicle(registeredVehicle)) {
    return {
      eligible: false,
      reason: `Ineligible vehicle type '${registeredVehicle || 'Unknown'}'. Food delivery is restricted exclusively to Bike and Scooty pilots. Auto Rickshaws and Cars are not permitted.`,
      registeredVehicle
    };
  }

  // 4. If a client submitted a vehicle type that contradicts their registered bike, reject
  if (submittedVehicleType && !isFoodDeliveryVehicle(submittedVehicleType)) {
    return {
      eligible: false,
      reason: `Submitted vehicle '${submittedVehicleType}' does not match food delivery requirements.`
    };
  }

  // 5. Online availability check (if requested)
  const isOnline = pilot.online === true || pilot.isOnline === true;
  if (requireOnline && !isOnline) {
    return { eligible: false, reason: 'Pilot is currently offline' };
  }

  // 5b. Food delivery availability toggle check
  if (checkFoodServiceEnabled && pilot.foodServiceEnabled === false) {
    return {
      eligible: false,
      reason: 'Food delivery is currently turned OFF in your Service Preferences. Turn ON Food Delivery to accept orders.'
    };
  }

  // 6. Active ride conflict check (if requested)
  if (checkActiveRide && pilot.currentRideId && pilot.currentRideStatus) {
    const inactiveStatuses = ['completed', 'cancelled', 'none', 'delivered', ''];
    if (!inactiveStatuses.includes(pilot.currentRideStatus)) {
      return { eligible: false, reason: `Pilot is currently engaged in active ride/assignment: ${pilot.currentRideId}` };
    }
  }

  return {
    eligible: true,
    normalizedVehicle: normalizeVehicleType(registeredVehicle),
    pilotId: pilot.phoneNumber || pilot.phone || pilot.uid || (pilot._id ? pilot._id.toString() : ''),
    name: pilot.name,
    vehicleType: pilot.vehicleType
  };
}

/**
 * Calculates straight line distance in km between two GPS coordinates (Haversine)
 */
function calculateDistanceKm(lat1, lon1, lat2, lon2) {
  if (!lat1 || !lon1 || !lat2 || !lon2) return null;
  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return Math.round(R * c * 10) / 10;
}

/**
 * Finds all online, approved, Bike and Scooty pilots within radius of a restaurant
 * @param {number} restaurantLat 
 * @param {number} restaurantLng 
 * @param {number} maxRadiusKm 
 * @returns {Promise<Array>}
 */
async function findNearbyEligibleFoodPilots(restaurantLat, restaurantLng, maxRadiusKm = 10) {
  try {
    const User = mongoose.models.User;
    if (!User) return [];
    
    // Find all approved online partners with food delivery enabled
    const pilots = await User.find({
      role: 'partner',
      online: true,
      foodServiceEnabled: { $ne: false },
      $or: [{ status: 'approved' }, { approved: true }, { isApproved: true }]
    }).lean();

    const eligiblePilots = [];

    for (const p of pilots) {
      // Must have food delivery enabled
      if (p.foodServiceEnabled === false) {
        continue;
      }

      // Must be a bike or scooty
      if (!isFoodDeliveryVehicle(p.vehicleType)) {
        continue;
      }

      // Check current ride engagement
      if (p.currentRideId && p.currentRideStatus) {
        const inactive = ['completed', 'cancelled', 'none', 'delivered', ''];
        if (!inactive.includes(p.currentRideStatus)) {
          continue;
        }
      }

      let distanceKm = null;
      if (restaurantLat && restaurantLng && p.lat && p.lng) {
        distanceKm = calculateDistanceKm(restaurantLat, restaurantLng, p.lat, p.lng);
        if (distanceKm !== null && distanceKm > maxRadiusKm) {
          continue; // Outside pickup radius
        }
      }

      eligiblePilots.push({
        uid: p.uid,
        name: p.name,
        phone: p.phone,
        vehicleType: p.vehicleType,
        vehiclePlate: p.vehiclePlate || p.vehicleNumber || '',
        vehicleModelColor: p.vehicleModelColor || '',
        lat: p.lat,
        lng: p.lng,
        distanceKm,
        online: p.online
      });
    }

    // Sort by nearest distance first
    eligiblePilots.sort((a, b) => {
      if (a.distanceKm === null) return 1;
      if (b.distanceKm === null) return -1;
      return a.distanceKm - b.distanceKm;
    });

    return eligiblePilots;
  } catch (err) {
    console.error('[FOOD PILOT ELIGIBILITY] Error finding nearby pilots:', err);
    return [];
  }
}

module.exports = {
  isFoodDeliveryVehicle,
  normalizeVehicleType,
  isEligibleForFoodDelivery,
  calculateDistanceKm,
  findNearbyEligibleFoodPilots,
  ALLOWED_FOOD_DELIVERY_VEHICLE_NORMALIZED,
  FORBIDDEN_VEHICLE_SUBSTRINGS
};
