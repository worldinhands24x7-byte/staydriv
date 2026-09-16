import React, { useState } from 'react';
import { useDatabase } from '../context/DatabaseContext';
import { Search, Eye, AlertCircle, Ban, Compass, CheckCircle, X } from 'lucide-react';

export const Rides: React.FC = () => {
  const { bookings, partners, assignDriver, cancelBooking, config } = useDatabase();
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [selectedRide, setSelectedRide] = useState<any | null>(null);
  const [showAssignPanel, setShowAssignPanel] = useState(false);

  // Filtered list
  const filteredRides = bookings.filter(b => {
    const matchesSearch = 
      b.bookingId.toLowerCase().includes(searchTerm.toLowerCase()) ||
      b.customerName.toLowerCase().includes(searchTerm.toLowerCase()) ||
      (b.driverName && b.driverName.toLowerCase().includes(searchTerm.toLowerCase()));

    if (!matchesSearch) return false;
    if (statusFilter === 'all') return true;
    return b.status === statusFilter;
  });

  const getStatusBadgeClass = (status: string) => {
    switch (status) {
      case 'requested': return 'badge-requested';
      case 'accepted': return 'badge-accepted';
      case 'arriving': return 'badge-accepted';
      case 'started': return 'badge-started';
      case 'completed': return 'badge-completed';
      case 'cancelled': return 'badge-cancelled';
      default: return 'badge-suspended';
    }
  };

  // Find eligible online approved drivers of matching vehicle type
  const getEligibleDrivers = (vehicleType: 'Bike' | 'Auto' | 'Car') => {
    return partners.filter(p => 
      p.status === 'approved' && 
      p.vehicleType === vehicleType
    );
  };

  // Calculate fare breakdown
  const computeFareDetails = (priceStr: string, vehicleType: string) => {
    const total = parseFloat(priceStr.replace(/[^0-9.]/g, '')) || 0;
    const base = config.baseFares[vehicleType as keyof typeof config.baseFares] || 50;
    const distanceFare = total - base;
    const commission = total * (config.commissionPercent / 100);
    const driverEarnings = total - commission;
    
    return {
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
        <p style={{ color: 'var(--text-muted)', fontSize: '14px' }}>Dispatch rides, audit status transitions, and inspect fare parameters.</p>
      </div>

      {/* Filter Card */}
      <div className="card" style={{ padding: '16px', display: 'flex', gap: '12px', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'space-between' }}>
        <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
          {['all', 'requested', 'accepted', 'started', 'completed', 'cancelled'].map(status => (
            <button
              key={status}
              className={`btn btn-sm ${statusFilter === status ? 'btn-primary' : 'btn-secondary'}`}
              onClick={() => setStatusFilter(status)}
              style={{ textTransform: 'capitalize' }}
            >
              {status}
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

      {/* Rides Table */}
      <div className="table-wrapper">
        <table>
          <thead>
            <tr>
              <th>Ride ID</th>
              <th>Customer</th>
              <th>Locations (Pickup &rarr; Drop)</th>
              <th>Vehicle Option</th>
              <th>Fare Amount</th>
              <th>Booking Status</th>
              <th style={{ textAlign: 'right' }}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {filteredRides.length > 0 ? (
              filteredRides.map(b => (
                <tr key={b.bookingId}>
                  <td style={{ fontWeight: 600 }}>{b.bookingId}</td>
                  <td>
                    <div style={{ fontWeight: 500 }}>{b.customerName}</div>
                    <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>UID: {b.customerId}</div>
                  </td>
                  <td style={{ fontSize: '12px', maxWidth: '350px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    <div><strong>From:</strong> {b.pickup}</div>
                    <div style={{ color: 'var(--text-muted)' }}><strong>To:</strong> {b.drop}</div>
                  </td>
                  <td>
                    <span style={{ fontWeight: 600 }}>{b.vehicle}</span>
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
              ))
            ) : (
              <tr>
                <td colSpan={7} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: '24px' }}>
                  No ride bookings found matching the filters.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {/* Ride Detail & Dispatch Panel */}
      {selectedRide && (() => {
        const fare = computeFareDetails(selectedRide.price, selectedRide.vehicle);
        const drivers = getEligibleDrivers(selectedRide.vehicle);
        return (
          <div className="modal-overlay">
            <div className="modal-content" style={{ maxWidth: '750px' }}>
              <div className="modal-header">
                <div>
                  <h3 style={{ fontSize: '18px' }}>Ride Record: {selectedRide.bookingId}</h3>
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

              <div className="modal-body" style={{ display: 'grid', gridTemplateColumns: '1.2fr 1fr', gap: '20px' }}>
                {/* Left side details */}
                <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
                  <div>
                    <span style={{ fontSize: '11px', color: 'var(--text-muted)', fontWeight: 600 }}>LOCATIONS</span>
                    <div style={{ fontSize: '13px', display: 'flex', flexDirection: 'column', gap: '6px', marginTop: '4px' }}>
                      <div>🟢 <strong>Pickup:</strong> {selectedRide.pickup}</div>
                      <div>🔴 <strong>Drop-off:</strong> {selectedRide.drop}</div>
                    </div>
                  </div>

                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px', fontSize: '13px' }}>
                    <div>
                      <span style={{ color: 'var(--text-muted)' }}>Customer Name</span>
                      <div style={{ fontWeight: 600 }}>{selectedRide.customerName}</div>
                    </div>
                    <div>
                      <span style={{ color: 'var(--text-muted)' }}>One-Time OTP</span>
                      <div style={{ fontWeight: 700, color: 'var(--safety-yellow)' }}>{selectedRide.otp}</div>
                    </div>
                    <div>
                      <span style={{ color: 'var(--text-muted)' }}>Payment Method</span>
                      <div style={{ fontWeight: 600 }}>{selectedRide.paymentOption}</div>
                    </div>
                    <div>
                      <span style={{ color: 'var(--text-muted)' }}>Vehicle Type</span>
                      <div style={{ fontWeight: 600 }}>StayDriv {selectedRide.vehicle}</div>
                    </div>
                  </div>

                  <hr style={{ border: 'none', borderTop: '1px solid var(--border)' }} />

                  {/* Driver Assign Section */}
                  {selectedRide.driverId ? (
                    <div>
                      <span style={{ fontSize: '11px', color: 'var(--text-muted)', fontWeight: 600 }}>ASSIGNED PARTNER</span>
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
                      <span>This ride does not have an assigned driver. Manually dispatch below.</span>
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
                  <h4 style={{ fontSize: '13px', borderBottom: '1px solid var(--border)', paddingBottom: '6px' }}>FARE AUDIT & BREAKDOWN</h4>
                  
                  <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '13px' }}>
                    <span style={{ color: 'var(--text-muted)' }}>Base Vehicle Charge:</span>
                    <span style={{ fontWeight: 500 }}>₹{fare.base.toFixed(2)}</span>
                  </div>

                  <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '13px' }}>
                    <span style={{ color: 'var(--text-muted)' }}>Distance Travel Charge:</span>
                    <span style={{ fontWeight: 500 }}>₹{fare.distanceFare.toFixed(2)}</span>
                  </div>

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
                    <span>Driver Net Earnings (80%):</span>
                    <span style={{ fontWeight: 700 }}>₹{fare.driverEarnings.toFixed(2)}</span>
                  </div>
                </div>
              </div>

              <div className="modal-footer">
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
