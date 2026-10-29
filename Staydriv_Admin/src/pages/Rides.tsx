import React, { useState } from 'react';
import { useDatabase } from '../context/DatabaseContext';
import { 
  Search, Eye, AlertCircle, Ban, Compass, CheckCircle, X, 
  Repeat, Clock, Users, Navigation, MapPin, ArrowRight, ShieldCheck, DollarSign, Calendar
} from 'lucide-react';

export const Rides: React.FC = () => {
  const { bookings, partners, assignDriver, cancelBooking, config } = useDatabase();
  const [searchTerm, setSearchTerm] = useState(() => {
    const auto = sessionStorage.getItem('admin_auto_filter');
    if (auto) {
      sessionStorage.removeItem('admin_auto_filter');
      return auto;
    }
    return '';
  });

  React.useEffect(() => {
    const handleSearchNav = (e: any) => {
      if (e.detail?.filter && (e.detail?.tab === 'rides' || !e.detail?.tab)) {
        setSearchTerm(e.detail.filter);
      }
    };
    window.addEventListener('admin:search-navigate', handleSearchNav);
    return () => window.removeEventListener('admin:search-navigate', handleSearchNav);
  }, []);
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [tripTypeFilter, setTripTypeFilter] = useState<string>('all');
  const [selectedRide, setSelectedRide] = useState<any | null>(null);
  const [showAssignPanel, setShowAssignPanel] = useState(false);

  // Filtered list
  const filteredRides = bookings.filter(b => {
    const termLower = searchTerm.toLowerCase();
    const matchesSearch = 
      b.bookingId.toLowerCase().includes(termLower) ||
      b.customerName.toLowerCase().includes(termLower) ||
      ((b as any).passengerPhone && String((b as any).passengerPhone).includes(searchTerm)) ||
      (b.driverPhone && String(b.driverPhone).includes(searchTerm)) ||
      (b.driverName && b.driverName.toLowerCase().includes(termLower)) ||
      (b.vehicle && b.vehicle.toLowerCase().includes(termLower)) ||
      (b.tripType && b.tripType.toLowerCase().includes(termLower));

    if (statusFilter !== 'all') {
      if (statusFilter === 'requested' || statusFilter === 'searching') {
        if (b.status !== 'requested' && b.status !== 'searching') return false;
      } else if (statusFilter === 'started' || statusFilter === 'in_progress') {
        if (b.status !== 'started' && b.status !== 'in_progress') return false;
      } else if (b.status !== statusFilter) {
        return false;
      }
    }

    if (tripTypeFilter === 'round_trip') {
      return b.isRoundTrip || b.tripType === 'ROUND_TRIP' || b.tripType === 'round_trip';
    }
    if (tripTypeFilter === 'one_way') {
      return !b.isRoundTrip && b.tripType !== 'ROUND_TRIP' && b.tripType !== 'SHARE_AUTO' && b.tripType !== 'SHARE_CAR';
    }
    if (tripTypeFilter === 'shared') {
      return b.tripType === 'SHARE_AUTO' || b.tripType === 'SHARE_CAR' || b.vehicle === 'Share Auto' || b.vehicle === 'Share Car';
    }
    return true;
  });

  const getStatusBadgeClass = (status: string) => {
    switch (status) {
      case 'searching':
      case 'requested': return 'badge-requested';
      case 'accepted': return 'badge-accepted';
      case 'arriving':
      case 'arrived': return 'badge-accepted';
      case 'started':
      case 'in_progress': return 'badge-started';
      case 'completed': return 'badge-completed';
      case 'cancelled': return 'badge-cancelled';
      default: return 'badge-suspended';
    }
  };

  // Find eligible online approved drivers of matching vehicle type
  const getEligibleDrivers = (vehicleType: string) => {
    const target = (vehicleType || '').toLowerCase().trim();
    return partners.filter(p => {
      const isAppr = Boolean(p.approved || (p as any).isApproved || String(p.status || '').toUpperCase() === 'APPROVED');
      if (!isAppr) return false;
      const pvt = (p.vehicleType || '').toLowerCase().trim();
      if (pvt === target) return true;
      if (target.includes('car xl') && (pvt.includes('car xl') || pvt.includes('xl') || pvt.includes('innova') || pvt.includes('ertiga'))) return true;
      if (pvt.includes('car xl') || pvt.includes('innova') || pvt.includes('ertiga')) {
        return target.includes('car xl') || target.includes('xl');
      }
      if (target.includes('mini truck') && (pvt.includes('mini truck') || pvt.includes('pickup') || pvt.includes('ace') || pvt.includes('dost'))) return true;
      if (target.includes('heavy truck') && (pvt.includes('heavy truck') || pvt.includes('ton'))) return true;
      if (target.includes('truck') && pvt.includes('truck')) return true;
      if (target.includes('car') && pvt.includes('car')) return true;
      if (target.includes('auto') && pvt.includes('auto')) return true;
      if (target.includes('bike') && (pvt.includes('bike') || pvt.includes('scoot'))) return true;
      return false;
    });
  };

  // Calculate fare breakdown
  const computeFareDetails = (ride: any) => {
    const total = parseFloat((ride.price || '0').replace(/[^0-9.]/g, '')) || 0;
    const isRound = ride.isRoundTrip || ride.tripType === 'ROUND_TRIP' || ride.tripType === 'round_trip';
    const isShared = ride.tripType === 'SHARE_AUTO' || ride.tripType === 'SHARE_CAR' || ride.vehicle?.includes('Share');
    
    if (isRound) {
      const waiting = ride.waitingCharge !== undefined ? ride.waitingCharge : (ride.waitingDurationMinutes && ride.waitingDurationMinutes > 15 ? (ride.waitingDurationMinutes - 15) * 2.5 : 0);
      const outward = ride.outwardFare || Math.round((total - waiting) * 0.52);
      const returnFare = ride.returnFare || Math.round((total - waiting) * 0.48);
      const taxes = ride.taxes || Math.round(total * 0.05);
      const commission = ride.platformCommission || Math.round(total * 0.15);
      const driverEarnings = ride.pilotEarnings || Math.round(total * 0.85);

      return {
        isRoundTrip: true,
        isShared: false,
        base: (config.baseFares as any)[ride.vehicle] || (ride.vehicle === 'Car XL' ? 130 : 50),
        outward,
        returnFare,
        waiting,
        taxes,
        commission,
        driverEarnings,
        total
      };
    }

    const isCarXl = ride.vehicle === 'Car XL' || String(ride.vehicle || '').toLowerCase().includes('car xl');
    const base = (config.baseFares as any)[ride.vehicle] || (isCarXl ? 130 : 50);
    const distanceFare = total - base;
    const commission = total * (config.commissionPercent / 100);
    const driverEarnings = total - commission;
    
    return {
      isRoundTrip: false,
      isShared,
      base,
      distanceFare: distanceFare > 0 ? distanceFare : 0,
      commission,
      driverEarnings,
      total
    };
  };

  return (
    <div className="page-container">
      <div>
        <h2>Passenger Ride Management</h2>
        <p style={{ color: 'var(--text-muted)', fontSize: '14px' }}>Dispatch rides, monitor Round Trip legs & waiting durations, and inspect real-time fare audits.</p>
      </div>

      {/* Filter Card */}
      <div className="card" style={{ padding: '16px', display: 'flex', flexDirection: 'column', gap: '14px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '12px' }}>
          {/* Trip Type Tabs */}
          <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap', alignItems: 'center' }}>
            <span style={{ fontSize: '13px', fontWeight: 600, color: 'var(--text-muted)' }}>Service:</span>
            {[
              { id: 'all', label: 'All Services' },
              { id: 'one_way', label: 'One-Way' },
              { id: 'round_trip', label: 'Round Trip ⇄' },
              { id: 'shared', label: 'Share Auto / Car' }
            ].map(tab => (
              <button
                key={tab.id}
                className={`btn btn-sm ${tripTypeFilter === tab.id ? 'btn-primary' : 'btn-secondary'}`}
                onClick={() => setTripTypeFilter(tab.id)}
                style={{ fontWeight: tripTypeFilter === tab.id ? 700 : 500 }}
              >
                {tab.label}
              </button>
            ))}
          </div>

          <div className="input-icon-wrapper" style={{ width: '280px' }}>
            <Search size={16} />
            <input 
              type="text" 
              placeholder="Search booking ID, customer, driver..." 
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
            />
          </div>
        </div>

        {/* Status Filter Tabs */}
        <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap', alignItems: 'center', borderTop: '1px solid var(--border)', paddingTop: '10px' }}>
          <span style={{ fontSize: '12px', fontWeight: 600, color: 'var(--text-muted)' }}>Status:</span>
          {['all', 'requested', 'accepted', 'started', 'completed', 'cancelled'].map(status => (
            <button
              key={status}
              className={`btn btn-sm ${statusFilter === status ? 'btn-primary' : 'btn-secondary'}`}
              onClick={() => setStatusFilter(status)}
              style={{ textTransform: 'capitalize', fontSize: '12px' }}
            >
              {status}
            </button>
          ))}
        </div>
      </div>

      {/* Rides Table */}
      <div className="table-wrapper">
        <table>
          <thead>
            <tr>
              <th>Ride ID & Type</th>
              <th>Date & Time</th>
              <th>Customer</th>
              <th>Assigned Pilot</th>
              <th>Locations & Leg Tracking</th>
              <th>Vehicle Option</th>
              <th>Fare Amount</th>
              <th>Booking Status</th>
              <th style={{ textAlign: 'right' }}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {filteredRides.length > 0 ? (
              filteredRides.map(b => {
                const isRound = b.isRoundTrip || b.tripType === 'ROUND_TRIP' || b.tripType === 'round_trip';
                const isShared = b.tripType === 'SHARE_AUTO' || b.tripType === 'SHARE_CAR' || b.vehicle?.includes('Share');

                return (
                  <tr key={b.bookingId}>
                    <td>
                      <div style={{ fontWeight: 600 }}>{b.bookingId}</div>
                      <div style={{ display: 'flex', gap: '4px', marginTop: '4px', flexWrap: 'wrap' }}>
                        {isRound && (
                          <span style={{ backgroundColor: '#7c3aed', color: '#fff', fontSize: '10px', padding: '2px 6px', borderRadius: '4px', fontWeight: 700, display: 'inline-flex', alignItems: 'center', gap: '3px' }}>
                            <Repeat size={10} /> ROUND TRIP
                          </span>
                        )}
                        {isShared && (
                          <span style={{ backgroundColor: '#0f766e', color: '#fff', fontSize: '10px', padding: '2px 6px', borderRadius: '4px', fontWeight: 700, display: 'inline-flex', alignItems: 'center', gap: '3px' }}>
                            <Users size={10} /> SHARED ({b.sharedSeats || 1} SEATS)
                          </span>
                        )}
                        {!isRound && !isShared && (
                          <span style={{ backgroundColor: 'var(--bg-input)', color: 'var(--text-muted)', fontSize: '10px', padding: '2px 6px', borderRadius: '4px', fontWeight: 600 }}>
                            ONE-WAY
                          </span>
                        )}
                      </div>
                    </td>
                    <td>
                      <div style={{ fontWeight: 600, fontSize: '13px', display: 'flex', alignItems: 'center', gap: '5px' }}>
                        <Calendar size={13} style={{ color: 'var(--primary)', flexShrink: 0 }} />
                        <span>{b.createdAt ? new Date(b.createdAt).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' }) : 'Recent'}</span>
                      </div>
                      <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginLeft: '18px', marginTop: '2px' }}>
                        {b.createdAt ? new Date(b.createdAt).toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit', hour12: true }) : ''}
                      </div>
                    </td>
                    <td>
                      <div style={{ fontWeight: 500 }}>{b.customerName}</div>
                      <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>UID: {b.customerId}</div>
                    </td>
                    <td>
                      {b.driverName ? (
                        <div>
                          <div style={{ fontWeight: 600 }}>{b.driverName}</div>
                          <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                            {b.driverPhone || (b.driverId ? (b.driverId.length > 15 ? b.driverId.slice(-10) : b.driverId) : '')}
                          </div>
                          {b.vehiclePlate && (
                            <div style={{ fontSize: '10px', backgroundColor: '#f1f5f9', color: '#0f172a', padding: '1px 5px', borderRadius: '3px', display: 'inline-block', marginTop: '2px', fontWeight: 600 }}>
                              {b.vehiclePlate}
                            </div>
                          )}
                        </div>
                      ) : (
                        <span style={{ fontSize: '12px', color: 'var(--text-muted)', fontStyle: 'italic' }}>
                          {b.status === 'searching' || b.status === 'requested' ? 'Finding Pilot...' : 'Unassigned'}
                        </span>
                      )}
                    </td>
                    <td style={{ fontSize: '12px', maxWidth: '380px' }}>
                      <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
                        <div><strong>From:</strong> {b.pickup}</div>
                        <div style={{ color: 'var(--text-muted)' }}><strong>To:</strong> {b.drop}</div>
                        {isRound && (
                          <div style={{ marginTop: '2px', display: 'flex', alignItems: 'center', gap: '6px', flexWrap: 'wrap' }}>
                            <span style={{ color: 'var(--primary)', fontWeight: 600, fontSize: '11px' }}>
                              ⇄ Return: {b.returnDrop || b.pickup}
                            </span>
                            {b.pilotWaitOption === 'return_later' && (
                              <span style={{ backgroundColor: '#e0e7ff', color: '#3730a3', fontSize: '10px', padding: '1px 6px', borderRadius: '4px', fontWeight: 700, display: 'inline-flex', alignItems: 'center', gap: '3px' }}>
                                <Calendar size={10} /> Return: {b.returnDate} {b.returnTime}
                              </span>
                            )}
                            {b.currentLeg === 'waiting' && (
                              <span style={{ backgroundColor: '#fef3c7', color: '#92400e', fontSize: '10px', padding: '1px 6px', borderRadius: '4px', fontWeight: 700, display: 'inline-flex', alignItems: 'center', gap: '3px' }}>
                                <Clock size={10} /> Waiting ({b.waitingDurationMinutes || 15}m)
                              </span>
                            )}
                            {b.currentLeg === 'return' && (
                              <span style={{ backgroundColor: '#dbeafe', color: '#1e40af', fontSize: '10px', padding: '1px 6px', borderRadius: '4px', fontWeight: 700 }}>
                                🚗 Leg 2: Return Journey
                              </span>
                            )}
                            {b.currentLeg === 'outward' && (
                              <span style={{ backgroundColor: '#d1fae5', color: '#065f46', fontSize: '10px', padding: '1px 6px', borderRadius: '4px', fontWeight: 700 }}>
                                🟢 Leg 1: Outward Journey
                              </span>
                            )}
                          </div>
                        )}
                      </div>
                    </td>
                    <td>
                      <span style={{ fontWeight: 600 }}>{b.vehicle}</span>
                      {b.passengerCount && (
                        <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>{b.passengerCount} passenger{b.passengerCount > 1 ? 's' : ''}</div>
                      )}
                      {b.sharedSeats && (
                        <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>{b.sharedSeats} seat(s) reserved</div>
                      )}
                      {b.specialInstructions && (
                        <div style={{ fontSize: '10px', color: '#6366f1', fontStyle: 'italic', maxWidth: '150px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={b.specialInstructions}>
                          Note: {b.specialInstructions}
                        </div>
                      )}
                    </td>
                    <td style={{ fontWeight: 600 }}>{b.price}</td>
                    <td>
                      <span className={`badge ${getStatusBadgeClass(b.status)}`}>
                        {b.status}
                      </span>
                    </td>
                    <td style={{ textAlign: 'right' }}>
                      <div style={{ display: 'flex', gap: '8px', justifyContent: 'flex-end' }}>
                        <button 
                          className="btn btn-secondary btn-sm"
                          onClick={() => {
                            setSelectedRide(b);
                            setShowAssignPanel(false);
                          }}
                        >
                          <Eye size={14} />
                          <span>Inspect</span>
                        </button>
                        
                        {b.status === 'requested' && (
                          <button 
                            className="btn btn-yellow btn-sm"
                            onClick={() => {
                              setSelectedRide(b);
                              setShowAssignPanel(true);
                            }}
                          >
                            <Compass size={14} />
                            <span>Dispatch</span>
                          </button>
                        )}

                        {b.status !== 'completed' && b.status !== 'cancelled' && (
                          <button 
                            className="btn btn-danger btn-sm"
                            onClick={() => cancelBooking(b.bookingId, false)}
                          >
                            <Ban size={14} />
                            <span>Cancel</span>
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                );
              })
            ) : (
              <tr>
                <td colSpan={8} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: '24px' }}>
                  No ride bookings found matching the filters.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {/* Ride Detail & Dispatch Panel */}
      {selectedRide && (() => {
        const fare = computeFareDetails(selectedRide);
        const drivers = getEligibleDrivers(selectedRide.vehicle);
        const isRound = selectedRide.isRoundTrip || selectedRide.tripType === 'ROUND_TRIP' || selectedRide.tripType === 'round_trip';
        const isShared = selectedRide.tripType === 'SHARE_AUTO' || selectedRide.tripType === 'SHARE_CAR' || selectedRide.vehicle?.includes('Share');

        return (
          <div className="modal-overlay">
            <div className="modal-content" style={{ maxWidth: '840px', maxHeight: '90vh', overflowY: 'auto' }}>
              <div className="modal-header">
                <div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <h3 style={{ fontSize: '18px' }}>Ride Record: {selectedRide.bookingId}</h3>
                    {isRound && (
                      <span style={{ backgroundColor: '#7c3aed', color: '#fff', fontSize: '11px', padding: '2px 8px', borderRadius: '4px', fontWeight: 700 }}>
                        ROUND TRIP (2 LEGS)
                      </span>
                    )}
                    {isShared && (
                      <span style={{ backgroundColor: '#0f766e', color: '#fff', fontSize: '11px', padding: '2px 8px', borderRadius: '4px', fontWeight: 700 }}>
                        SHARED RIDE
                      </span>
                    )}
                  </div>
                  <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Created At: {new Date(selectedRide.createdAt).toLocaleString('en-IN')}</span>
                </div>
                <button 
                  className="btn btn-secondary btn-icon" 
                  onClick={() => setSelectedRide(null)}
                  style={{ width: '32px', height: '32px', minWidth: '32px' }}
                >
                  <X size={14} />
                </button>
              </div>

              {/* Multi-Leg Round Trip Timeline Component */}
              {isRound && (
                <div style={{ margin: '16px 24px 0 24px', backgroundColor: '#1e1b4b', border: '1px solid #4338ca', borderRadius: '12px', padding: '16px', color: '#e0e7ff' }}>
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '12px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                      <Repeat size={16} color="#a5b4fc" />
                      <span style={{ fontWeight: 700, fontSize: '14px', letterSpacing: '0.3px', color: '#ffffff' }}>ROUND TRIP JOURNEY TIMELINE</span>
                    </div>
                    <span style={{ fontSize: '12px', backgroundColor: '#312e81', color: '#c7d2fe', padding: '3px 8px', borderRadius: '6px', fontWeight: 600 }}>
                      Current: {selectedRide.currentLeg ? selectedRide.currentLeg.toUpperCase() : 'OUTWARD'}
                    </span>
                  </div>

                  <div style={{ display: 'grid', gridTemplateColumns: '1fr auto 1fr auto 1fr', gap: '10px', alignItems: 'center' }}>
                    {/* Leg 1 Outward */}
                    <div style={{ backgroundColor: '#312e81', borderRadius: '8px', padding: '12px', border: selectedRide.currentLeg === 'outward' ? '2px solid #10b981' : '1px solid #4338ca' }}>
                      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '6px' }}>
                        <span style={{ fontSize: '11px', fontWeight: 700, color: '#34d399' }}>LEG 1: OUTWARD</span>
                        <span style={{ fontSize: '10px', color: '#a5b4fc' }}>{selectedRide.outwardDistance || '14.2 km'}</span>
                      </div>
                      <div style={{ fontSize: '12px', color: '#f8fafc', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                        🟢 {selectedRide.pickup}
                      </div>
                      <div style={{ fontSize: '12px', color: '#f8fafc', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', marginTop: '4px' }}>
                        🔴 {selectedRide.drop}
                      </div>
                      <div style={{ marginTop: '8px', fontSize: '11px', color: '#cbd5e1' }}>
                        Status: <strong style={{ color: selectedRide.outwardTripStatus === 'completed' ? '#34d399' : '#fbbf24' }}>{selectedRide.outwardTripStatus || 'In Progress'}</strong>
                      </div>
                    </div>

                    <ArrowRight size={18} color="#818cf8" />

                    {/* Halt / Waiting */}
                    <div style={{ backgroundColor: '#312e81', borderRadius: '8px', padding: '12px', border: selectedRide.currentLeg === 'waiting' ? '2px solid #fbbf24' : '1px solid #4338ca' }}>
                      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '6px' }}>
                        <span style={{ fontSize: '11px', fontWeight: 700, color: '#fbbf24' }}>HALT & WAITING</span>
                        <span style={{ fontSize: '10px', color: '#a5b4fc' }}>{selectedRide.waitingDurationMinutes || 15} mins</span>
                      </div>
                      <div style={{ fontSize: '12px', color: '#f8fafc' }}>
                        Option: <strong>{selectedRide.pilotWaitOption === 'pilot_wait' ? 'Pilot Waiting on Site' : 'Return Later Booking'}</strong>
                      </div>
                      <div style={{ fontSize: '11px', color: '#cbd5e1', marginTop: '4px' }}>
                        Allowance: 15 mins free, then ₹2.5/min
                      </div>
                      <div style={{ marginTop: '8px', fontSize: '11px', color: '#cbd5e1' }}>
                        Wait Fee: <strong style={{ color: '#fbbf24' }}>₹{fare.waiting ? fare.waiting.toFixed(2) : '0.00'}</strong>
                      </div>
                    </div>

                    <ArrowRight size={18} color="#818cf8" />

                    {/* Leg 2 Return */}
                    <div style={{ backgroundColor: '#312e81', borderRadius: '8px', padding: '12px', border: selectedRide.currentLeg === 'return' ? '2px solid #60a5fa' : '1px solid #4338ca' }}>
                      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '6px' }}>
                        <span style={{ fontSize: '11px', fontWeight: 700, color: '#60a5fa' }}>LEG 2: RETURN</span>
                        <span style={{ fontSize: '10px', color: '#a5b4fc' }}>{selectedRide.returnDistance || '14.2 km'} (10% OFF)</span>
                      </div>
                      <div style={{ fontSize: '12px', color: '#f8fafc', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                        🟢 {selectedRide.returnPickup || selectedRide.drop}
                      </div>
                      <div style={{ fontSize: '12px', color: '#f8fafc', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', marginTop: '4px' }}>
                        🔴 {selectedRide.returnDrop || selectedRide.pickup}
                      </div>
                      <div style={{ marginTop: '8px', fontSize: '11px', color: '#cbd5e1' }}>
                        Status: <strong style={{ color: selectedRide.returnTripStatus === 'completed' ? '#34d399' : '#94a3b8' }}>{selectedRide.returnTripStatus || 'Pending'}</strong>
                      </div>
                    </div>
                  </div>
                </div>
              )}

              <div className="modal-body" style={{ display: 'grid', gridTemplateColumns: '1.2fr 1fr', gap: '20px', padding: '20px 24px' }}>
                {/* Left side details */}
                <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
                  <div>
                    <span style={{ fontSize: '11px', color: 'var(--text-muted)', fontWeight: 600 }}>ROUTING & DESTINATIONS</span>
                    <div style={{ fontSize: '13px', display: 'flex', flexDirection: 'column', gap: '6px', marginTop: '4px' }}>
                      <div>🟢 <strong>Outward Pickup:</strong> {selectedRide.pickup}</div>
                      <div>🔴 <strong>Outward Drop-off (Halt Location):</strong> {selectedRide.drop}</div>
                      {isRound && (
                        <div>🔄 <strong>Final Return Destination:</strong> {selectedRide.returnDrop || selectedRide.pickup}</div>
                      )}
                    </div>
                  </div>

                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px', fontSize: '13px' }}>
                    <div>
                      <span style={{ color: 'var(--text-muted)' }}>Customer Name</span>
                      <div style={{ fontWeight: 600 }}>{selectedRide.customerName}</div>
                    </div>
                    <div>
                      <span style={{ color: 'var(--text-muted)' }}>
                        {selectedRide.serviceType === 'parcel' ? 'Pickup OTP Status' : 'Ride Start OTP Status'}
                      </span>
                      <div style={{ fontWeight: 700, color: (selectedRide.otpVerified || selectedRide.status === 'started' || selectedRide.status === 'completed') ? '#10b981' : '#f59e0b', display: 'flex', alignItems: 'center', gap: '6px' }}>
                        <span>
                          {(selectedRide.otpVerified || selectedRide.status === 'started' || selectedRide.status === 'completed') ? '✓ Verified' : '⏳ Pending Verification'}
                        </span>
                        {(selectedRide.otpAttempts && selectedRide.otpAttempts > 0 && !selectedRide.otpVerified) && (
                          <span style={{ fontSize: '11px', color: '#ef4444', fontWeight: 600 }}>({selectedRide.otpAttempts}/5 attempts)</span>
                        )}
                      </div>
                    </div>
                    {(selectedRide.serviceType === 'parcel' || selectedRide.deliveryOtpVerified !== undefined) && (
                      <div>
                        <span style={{ color: 'var(--text-muted)' }}>Parcel Delivery OTP Status</span>
                        <div style={{ fontWeight: 700, color: selectedRide.deliveryOtpVerified ? '#10b981' : '#f59e0b', display: 'flex', alignItems: 'center', gap: '6px' }}>
                          <span>
                            {selectedRide.deliveryOtpVerified ? '✓ Verified & Delivered' : '⏳ Pending Delivery'}
                          </span>
                          {(selectedRide.deliveryOtpAttempts && selectedRide.deliveryOtpAttempts > 0 && !selectedRide.deliveryOtpVerified) && (
                            <span style={{ fontSize: '11px', color: '#ef4444', fontWeight: 600 }}>({selectedRide.deliveryOtpAttempts}/5 attempts)</span>
                          )}
                        </div>
                      </div>
                    )}
                    {selectedRide.startTime && (
                      <div>
                        <span style={{ color: 'var(--text-muted)' }}>
                          {selectedRide.serviceType === 'parcel' ? 'Delivery Started At' : 'Ride Started At'}
                        </span>
                        <div style={{ fontWeight: 600 }}>{new Date(selectedRide.startTime).toLocaleTimeString('en-IN')}</div>
                      </div>
                    )}
                    {(selectedRide.endTime || selectedRide.paidAt) && (
                      <div>
                        <span style={{ color: 'var(--text-muted)' }}>
                          {selectedRide.serviceType === 'parcel' ? 'Delivered At' : 'Completed At'}
                        </span>
                        <div style={{ fontWeight: 600 }}>{new Date(selectedRide.endTime || selectedRide.paidAt).toLocaleTimeString('en-IN')}</div>
                      </div>
                    )}
                    <div>
                      <span style={{ color: 'var(--text-muted)' }}>Payment Method</span>
                      <div style={{ fontWeight: 600 }}>{selectedRide.paymentOption}</div>
                    </div>
                    <div>
                      <span style={{ color: 'var(--text-muted)' }}>Vehicle & Trip Option</span>
                      <div style={{ fontWeight: 600 }}>StayDriv {selectedRide.vehicle}</div>
                    </div>
                    <div>
                      <span style={{ color: 'var(--text-muted)' }}>Passenger Count</span>
                      <div style={{ fontWeight: 600, color: 'var(--primary)' }}>{selectedRide.passengerCount || 1} Person{(selectedRide.passengerCount || 1) > 1 ? 's' : ''}</div>
                    </div>
                    {isShared && (
                      <div>
                        <span style={{ color: 'var(--text-muted)' }}>Seats Booked</span>
                        <div style={{ fontWeight: 600, color: '#0d9488' }}>{selectedRide.sharedSeats || 1} Seat(s) Reserved</div>
                      </div>
                    )}
                    {isRound && (selectedRide.returnDateTime || selectedRide.returnDate) && (
                      <div>
                        <span style={{ color: 'var(--text-muted)' }}>Scheduled Return</span>
                        <div style={{ fontWeight: 600, color: '#4338ca' }}>
                          {selectedRide.returnDate ? `${selectedRide.returnDate} at ${selectedRide.returnTime}` : selectedRide.returnDateTime}
                        </div>
                      </div>
                    )}
                    {selectedRide.specialInstructions && (
                      <div style={{ gridColumn: 'span 2' }}>
                        <span style={{ color: 'var(--text-muted)' }}>Special Instructions / Luggage Notes</span>
                        <div style={{ fontWeight: 500, color: '#4338ca', backgroundColor: '#eef2ff', padding: '6px 10px', borderRadius: '6px', marginTop: '2px', fontSize: '12px' }}>
                          {selectedRide.specialInstructions}
                        </div>
                      </div>
                    )}
                  </div>

                  <hr style={{ border: 'none', borderTop: '1px solid var(--border)' }} />

                  {/* Driver Assign Section */}
                  {selectedRide.driverId ? (
                    <div>
                      <span style={{ fontSize: '11px', color: 'var(--text-muted)', fontWeight: 600 }}>ASSIGNED PILOT</span>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginTop: '6px', fontSize: '13px' }}>
                        <div style={{ width: '8px', height: '8px', borderRadius: '50%', backgroundColor: 'var(--success)' }} />
                        <div>
                          <div style={{ fontWeight: 600 }}>{selectedRide.driverName}</div>
                          <div style={{ color: 'var(--text-muted)', fontSize: '11px' }}>{selectedRide.vehicleModelColor} ({selectedRide.vehiclePlate})</div>
                        </div>
                      </div>
                    </div>
                  ) : (
                    <div style={{ backgroundColor: 'var(--warning-bg)', border: '1px solid var(--warning)', borderRadius: '8px', padding: '10px 14px', color: 'var(--warning)', display: 'flex', gap: '8px', alignItems: 'center', fontSize: '12px' }}>
                      <AlertCircle size={16} style={{ flexShrink: 0 }} />
                      <span>This ride does not have an assigned pilot. Manually dispatch below.</span>
                    </div>
                  )}

                  {/* Manual dispatch list */}
                  {showAssignPanel && (
                    <div style={{ border: '1px solid var(--border)', borderRadius: '12px', padding: '12px', display: 'flex', flexDirection: 'column', gap: '10px' }}>
                      <span style={{ fontSize: '12px', fontWeight: 700 }}>Choose Available approved {selectedRide.vehicle} Drivers</span>
                      <div style={{ maxHeight: '160px', overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: '6px' }}>
                        {drivers.length > 0 ? (
                          drivers.map(drv => (
                            <div 
                              key={drv.uid} 
                              style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '8px 10px', border: '1px solid var(--border)', borderRadius: '8px', fontSize: '12px' }}
                            >
                              <div>
                                <span style={{ fontWeight: 600 }}>{drv.name}</span>
                                <span style={{ color: 'var(--text-muted)', marginLeft: '6px' }}>({drv.vehiclePlate})</span>
                              </div>
                              <button 
                                className="btn btn-primary btn-sm"
                                onClick={() => {
                                  assignDriver(selectedRide.bookingId, drv.uid, false);
                                  setSelectedRide({
                                    ...selectedRide,
                                    driverId: drv.uid,
                                    driverName: drv.name,
                                    vehiclePlate: drv.vehiclePlate,
                                    vehicleModelColor: drv.vehicleModelColor,
                                    status: 'accepted'
                                  });
                                  setShowAssignPanel(false);
                                }}
                              >
                                Match
                              </button>
                            </div>
                          ))
                        ) : (
                          <div style={{ textAlign: 'center', color: 'var(--text-muted)', fontSize: '11px', padding: '10px' }}>
                            No approved drivers currently online for StayDriv {selectedRide.vehicle}.
                          </div>
                        )}
                      </div>
                    </div>
                  )}
                </div>

                {/* Right side - Fare Breakdown */}
                <div style={{ backgroundColor: 'var(--bg-input)', padding: '16px', borderRadius: '16px', display: 'flex', flexDirection: 'column', gap: '12px' }}>
                  <h4 style={{ fontSize: '13px', borderBottom: '1px solid var(--border)', paddingBottom: '6px' }}>
                    {isRound ? 'ROUND TRIP FARE AUDIT' : 'FARE AUDIT & BREAKDOWN'}
                  </h4>
                  
                  {isRound ? (
                    <>
                      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '13px' }}>
                        <span style={{ color: 'var(--text-muted)' }}>Leg 1 Outward Journey:</span>
                        <span style={{ fontWeight: 500 }}>₹{fare.outward?.toFixed(2)}</span>
                      </div>

                      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '13px' }}>
                        <span style={{ color: 'var(--text-muted)' }}>Leg 2 Return (10% Discount):</span>
                        <span style={{ fontWeight: 500 }}>₹{fare.returnFare?.toFixed(2)}</span>
                      </div>

                      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '13px' }}>
                        <span style={{ color: 'var(--text-muted)' }}>Halt / Waiting Charges:</span>
                        <span style={{ fontWeight: 500, color: fare.waiting ? 'var(--warning)' : 'inherit' }}>
                          ₹{fare.waiting ? fare.waiting.toFixed(2) : '0.00'}
                        </span>
                      </div>

                      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '13px' }}>
                        <span style={{ color: 'var(--text-muted)' }}>GST & Toll Taxes (5%):</span>
                        <span style={{ fontWeight: 500 }}>₹{fare.taxes?.toFixed(2)}</span>
                      </div>

                      <hr style={{ border: 'none', borderTop: '1px dashed var(--border)' }} />

                      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '13px' }}>
                        <span style={{ color: 'var(--text-muted)', fontWeight: 600 }}>Total Customer Charge:</span>
                        <span style={{ fontWeight: 700, fontSize: '15px' }}>₹{fare.total.toFixed(2)}</span>
                      </div>

                      <hr style={{ border: 'none', borderTop: '1px solid var(--border)' }} />

                      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '13px', color: 'var(--success)' }}>
                        <span>StayDriv Commission (15%):</span>
                        <span style={{ fontWeight: 700 }}>₹{fare.commission.toFixed(2)}</span>
                      </div>

                      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '13px', color: 'var(--primary)' }}>
                        <span>Pilot Net Earnings (85%):</span>
                        <span style={{ fontWeight: 700 }}>₹{fare.driverEarnings.toFixed(2)}</span>
                      </div>
                    </>
                  ) : (
                    <>
                      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '13px' }}>
                        <span style={{ color: 'var(--text-muted)' }}>Base Vehicle Charge:</span>
                        <span style={{ fontWeight: 500 }}>₹{fare.base.toFixed(2)}</span>
                      </div>

                      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '13px' }}>
                        <span style={{ color: 'var(--text-muted)' }}>Distance Travel Charge:</span>
                        <span style={{ fontWeight: 500 }}>₹{fare.distanceFare ? fare.distanceFare.toFixed(2) : '0.00'}</span>
                      </div>

                      {isShared && (
                        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '13px', color: '#0d9488' }}>
                          <span>Shared Seats Split ({selectedRide.sharedSeats || 1} Seat):</span>
                          <span style={{ fontWeight: 600 }}>Per Seat: ₹{(fare.total / (selectedRide.sharedSeats || 1)).toFixed(2)}</span>
                        </div>
                      )}

                      <hr style={{ border: 'none', borderTop: '1px dashed var(--border)' }} />

                      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '13px' }}>
                        <span style={{ color: 'var(--text-muted)' }}>Gross Customer Fare:</span>
                        <span style={{ fontWeight: 600 }}>₹{fare.total.toFixed(2)}</span>
                      </div>

                      <hr style={{ border: 'none', borderTop: '1px solid var(--border)' }} />

                      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '13px', color: 'var(--success)' }}>
                        <span>Platform Commission ({config.commissionPercent}%):</span>
                        <span style={{ fontWeight: 700 }}>₹{fare.commission.toFixed(2)}</span>
                      </div>

                      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '13px', color: 'var(--primary)' }}>
                        <span>Driver Net Earnings (85%):</span>
                        <span style={{ fontWeight: 700 }}>₹{fare.driverEarnings.toFixed(2)}</span>
                      </div>
                    </>
                  )}
                </div>
              </div>

              <div className="modal-footer" style={{ padding: '16px 24px' }}>
                {!selectedRide.driverId && !showAssignPanel && (
                  <button className="btn btn-yellow" onClick={() => setShowAssignPanel(true)}>
                    Assign Driver Manually
                  </button>
                )}
                {selectedRide.status !== 'completed' && selectedRide.status !== 'cancelled' && (
                  <button 
                    className="btn btn-danger"
                    onClick={() => {
                      cancelBooking(selectedRide.bookingId, false);
                      setSelectedRide({ ...selectedRide, status: 'cancelled' });
                    }}
                  >
                    Cancel Booking
                  </button>
                )}
                <button className="btn btn-secondary" onClick={() => setSelectedRide(null)}>Close</button>
              </div>
            </div>
          </div>
        );
      })()}
    </div>
  );
};
export default Rides;
