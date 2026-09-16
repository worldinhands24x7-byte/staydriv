import React, { useState } from 'react';
import { useDatabase } from '../context/DatabaseContext';
import { Search, Eye, AlertCircle, Ban, Compass, Box, X } from 'lucide-react';

export const Deliveries: React.FC = () => {
  const { deliveries, partners, assignDriver, cancelBooking } = useDatabase();
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [selectedDelivery, setSelectedDelivery] = useState<any | null>(null);
  const [showAssignPanel, setShowAssignPanel] = useState(false);

  // Filtered list
  const filteredDeliveries = deliveries.filter(d => {
    const matchesSearch = 
      d.bookingId.toLowerCase().includes(searchTerm.toLowerCase()) ||
      d.customerName.toLowerCase().includes(searchTerm.toLowerCase()) ||
      d.goodsType.toLowerCase().includes(searchTerm.toLowerCase()) ||
      (d.driverName && d.driverName.toLowerCase().includes(searchTerm.toLowerCase()));

    if (!matchesSearch) return false;
    if (statusFilter === 'all') return true;
    return d.status === statusFilter;
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

  // Find eligible online approved drivers of matching cargo vehicle type
  const getEligibleDrivers = (vehicleType: string) => {
    return partners.filter(p => 
      p.status === 'approved' && 
      p.vehicleType.toLowerCase().trim() === vehicleType.toLowerCase().trim()
    );
  };

  return (
    <div className="page-container">
      <div>
        <h2>Goods & Cargo Transportation</h2>
        <p style={{ color: 'var(--text-muted)', fontSize: '14px' }}>Monitor logistics flows, verify heavy cargo weights, and assign logistics vehicles.</p>
      </div>

      {/* Filter Options */}
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
            placeholder="Search ID, customer, goods type..." 
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
          />
        </div>
      </div>

      {/* Deliveries Table */}
      <div className="table-wrapper">
        <table>
          <thead>
            <tr>
              <th>Delivery ID</th>
              <th>Customer</th>
              <th>Cargo & Weight Details</th>
              <th>Locations (Pickup &rarr; Drop)</th>
              <th>Vehicle Type</th>
              <th>Fare</th>
              <th>Status</th>
              <th style={{ textAlign: 'right' }}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {filteredDeliveries.length > 0 ? (
              filteredDeliveries.map(d => (
                <tr key={d.bookingId}>
                  <td style={{ fontWeight: 600 }}>{d.bookingId}</td>
                  <td>
                    <div style={{ fontWeight: 500 }}>{d.customerName}</div>
                    <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>UID: {d.customerId}</div>
                  </td>
                  <td>
                    <div style={{ fontWeight: 600, display: 'flex', alignItems: 'center', gap: '6px' }}>
                      <Box size={14} style={{ color: 'var(--primary)' }} />
                      <span>{d.goodsType}</span>
                    </div>
                    <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginLeft: '20px' }}>Weight Load: {d.weight}</div>
                  </td>
                  <td style={{ fontSize: '12px', maxWidth: '280px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    <div><strong>From:</strong> {d.pickup}</div>
                    <div style={{ color: 'var(--text-muted)' }}><strong>To:</strong> {d.drop}</div>
                  </td>
                  <td>
                    <span style={{ fontWeight: 600 }}>{d.vehicle}</span>
                  </td>
                  <td style={{ fontWeight: 600 }}>{d.price}</td>
                  <td>
                    <span className={`badge ${getStatusBadgeClass(d.status)}`}>
                      {d.status}
                    </span>
                  </td>
                  <td style={{ textAlign: 'right' }}>
                    <div style={{ display: 'flex', gap: '8px', justifyContent: 'flex-end' }}>
                      <button 
                        className="btn btn-secondary btn-sm"
                        onClick={() => {
                          setSelectedDelivery(d);
                          setShowAssignPanel(false);
                        }}
                      >
                        <Eye size={14} />
                        <span>Inspect</span>
                      </button>
                      
                      {d.status === 'requested' && (
                        <button 
                          className="btn btn-yellow btn-sm"
                          onClick={() => {
                            setSelectedDelivery(d);
                            setShowAssignPanel(true);
                          }}
                        >
                          <Compass size={14} />
                          <span>Assign</span>
                        </button>
                      )}

                      {d.status !== 'completed' && d.status !== 'cancelled' && (
                        <button 
                          className="btn btn-danger btn-sm"
                          onClick={() => cancelBooking(d.bookingId, true)}
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
                <td colSpan={8} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: '24px' }}>
                  No active cargo transport listings found.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {/* Delivery Inspect and Assign Modal */}
      {selectedDelivery && (() => {
        const drivers = getEligibleDrivers(selectedDelivery.vehicle);
        return (
          <div className="modal-overlay">
            <div className="modal-content" style={{ maxWidth: '720px' }}>
              <div className="modal-header">
                <div>
                  <h3 style={{ fontSize: '18px' }}>Logistics Ticket: {selectedDelivery.bookingId}</h3>
                  <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Created At: {new Date(selectedDelivery.createdAt).toLocaleString('en-IN')}</span>
                </div>
                <button 
                  className="btn btn-secondary btn-icon" 
                  onClick={() => setSelectedDelivery(null)}
                  style={{ width: '32px', height: '32px', minWidth: '32px' }}
                >
                  <X size={14} />
                </button>
              </div>

              <div className="modal-body" style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '20px' }}>
                {/* Left Column - Route and Contacts */}
                <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
                  <div>
                    <span style={{ fontSize: '11px', color: 'var(--text-muted)', fontWeight: 600 }}>ROUTING LOCATIONS</span>
                    <div style={{ fontSize: '13px', display: 'flex', flexDirection: 'column', gap: '6px', marginTop: '4px' }}>
                      <div>🟢 <strong>Pickup:</strong> {selectedDelivery.pickup}</div>
                      <div>🔴 <strong>Drop-off:</strong> {selectedDelivery.drop}</div>
                    </div>
                  </div>

                  <div>
                    <span style={{ fontSize: '11px', color: 'var(--text-muted)', fontWeight: 600 }}>CONTACT PARTIES</span>
                    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px', fontSize: '13px', marginTop: '6px' }}>
                      <div>
                        <div style={{ color: 'var(--text-muted)', fontSize: '11px' }}>Sender Contact:</div>
                        <div style={{ fontWeight: 600 }}>{selectedDelivery.pickupContactName || selectedDelivery.customerName}</div>
                        <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>+91 {selectedDelivery.pickupContactPhone || 'N/A'}</div>
                      </div>
                      <div>
                        <div style={{ color: 'var(--text-muted)', fontSize: '11px' }}>Recipient Contact:</div>
                        <div style={{ fontWeight: 600 }}>{selectedDelivery.dropContactName || 'N/A'}</div>
                        <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>+91 {selectedDelivery.dropContactPhone || 'N/A'}</div>
                      </div>
                    </div>
                  </div>
                </div>

                {/* Right Column - Cargo Details and Dispatch */}
                <div style={{ display: 'flex', flexDirection: 'column', gap: '16px', backgroundColor: 'var(--bg-input)', padding: '16px', borderRadius: '16px' }}>
                  <div>
                    <span style={{ fontSize: '11px', color: 'var(--text-muted)', fontWeight: 600 }}>CARGO DISPATCH SPECIFICATIONS</span>
                    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '10px', fontSize: '13px', marginTop: '6px' }}>
                      <div>
                        <span style={{ color: 'var(--text-muted)' }}>Goods Type:</span>
                        <div style={{ fontWeight: 600 }}>{selectedDelivery.goodsType}</div>
                      </div>
                      <div>
                        <span style={{ color: 'var(--text-muted)' }}>Load Weight:</span>
                        <div style={{ fontWeight: 600 }}>{selectedDelivery.weight}</div>
                      </div>
                      <div>
                        <span style={{ color: 'var(--text-muted)' }}>Required Fleet:</span>
                        <div style={{ fontWeight: 600 }}>{selectedDelivery.vehicle}</div>
                      </div>
                      <div>
                        <span style={{ color: 'var(--text-muted)' }}>Fare Price:</span>
                        <div style={{ fontWeight: 700, color: 'var(--primary)' }}>{selectedDelivery.price}</div>
                      </div>
                    </div>
                  </div>

                  <hr style={{ border: 'none', borderTop: '1px solid var(--border)' }} />

                  {/* Driver allocation status */}
                  {selectedDelivery.driverId ? (
                    <div>
                      <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>ASSIGNED FLEET OPERATOR</span>
                      <div style={{ fontWeight: 600, fontSize: '13px', marginTop: '4px' }}>
                        {selectedDelivery.driverName} ({selectedDelivery.vehiclePlate})
                      </div>
                      <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Model: {selectedDelivery.vehicleModelColor}</div>
                    </div>
                  ) : (
                    <div>
                      <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>MANUAL VEHICLE ALLOCATION</span>
                      
                      {showAssignPanel ? (
                        <div style={{ display: 'flex', flexDirection: 'column', gap: '6px', marginTop: '6px', maxHeight: '140px', overflowY: 'auto' }}>
                          {drivers.length > 0 ? (
                            drivers.map(drv => (
                              <div 
                                key={drv.uid} 
                                style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '6px 8px', border: '1px solid var(--border)', borderRadius: '8px', fontSize: '11px', backgroundColor: 'var(--bg-card)' }}
                              >
                                <div>
                                  <div style={{ fontWeight: 600 }}>{drv.name}</div>
                                  <div style={{ color: 'var(--text-muted)', fontSize: '10px' }}>{drv.vehiclePlate}</div>
                                </div>
                                <button 
                                  className="btn btn-primary btn-sm"
                                  onClick={() => {
                                    assignDriver(selectedDelivery.bookingId, drv.uid, true);
                                    setSelectedDelivery({
                                      ...selectedDelivery,
                                      driverId: drv.uid,
                                      driverName: drv.name,
                                      vehiclePlate: drv.vehiclePlate,
                                      vehicleModelColor: drv.vehicleModelColor,
                                      status: 'accepted'
                                    });
                                    setShowAssignPanel(false);
                                  }}
                                  style={{ padding: '2px 8px', fontSize: '10px' }}
                                >
                                  Allocate
                                </button>
                              </div>
                            ))
                          ) : (
                            <div style={{ fontSize: '11px', color: 'var(--text-muted)', textAlign: 'center', padding: '6px' }}>
                              No online approved {selectedDelivery.vehicle} drivers available.
                            </div>
                          )}
                        </div>
                      ) : (
                        <button 
                          className="btn btn-yellow btn-sm" 
                          onClick={() => setShowAssignPanel(true)} 
                          style={{ width: '100%', marginTop: '6px' }}
                        >
                          <Compass size={14} />
                          <span>Allocate Pilot</span>
                        </button>
                      )}
                    </div>
                  )}
                </div>
              </div>

              <div className="modal-footer">
                {selectedDelivery.status !== 'completed' && selectedDelivery.status !== 'cancelled' && (
                  <button 
                    className="btn btn-danger"
                    onClick={() => {
                      cancelBooking(selectedDelivery.bookingId, true);
                      setSelectedDelivery(null);
                    }}
                  >
                    Cancel Order
                  </button>
                )}
                <button className="btn btn-secondary" onClick={() => setSelectedDelivery(null)}>Close</button>
              </div>
            </div>
          </div>
        );
      })()}
    </div>
  );
};
export default Deliveries;
