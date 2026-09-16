import React, { useState } from 'react';
import { useDatabase } from '../context/DatabaseContext';
import { Search, ShieldCheck, ShieldAlert, Award, Star, Eye, Check, X, FileText, Ban } from 'lucide-react';

export const Partners: React.FC = () => {
  const { partners, verifyPartner } = useDatabase();
  const [searchTerm, setSearchTerm] = useState('');
  const [activeTab, setActiveTab] = useState<'all' | 'pending' | 'approved' | 'suspended'>('all');
  const [selectedPartner, setSelectedPartner] = useState<any | null>(null);

  // Filters
  const filteredPartners = partners.filter(p => {
    // Search filter
    const matchesSearch = 
      p.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
      p.email.toLowerCase().includes(searchTerm.toLowerCase()) ||
      p.phone.includes(searchTerm) ||
      p.vehiclePlate.toLowerCase().includes(searchTerm.toLowerCase());

    if (!matchesSearch) return false;

    // Tab filter
    if (activeTab === 'all') return true;
    return p.status === activeTab;
  });

  const getStatusBadgeClass = (status: string) => {
    switch (status) {
      case 'approved': return 'badge-active';
      case 'pending': return 'badge-pending';
      case 'suspended': return 'badge-suspended';
      case 'rejected': return 'badge-rejected';
      default: return 'badge-suspended';
    }
  };

  return (
    <div className="page-container">
      <div>
        <h2>Pilot Management</h2>
        <p style={{ color: 'var(--text-muted)', fontSize: '14px' }}>Verify documents, approve registrations, and audit pilot standings.</p>
      </div>

      {/* Tabs and Search */}
      <div className="card" style={{ padding: '16px', display: 'flex', flexDirection: 'column', gap: '16px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '12px' }}>
          <div style={{ display: 'flex', gap: '8px' }}>
            {(['all', 'pending', 'approved', 'suspended'] as const).map(tab => (
              <button 
                key={tab}
                className={`btn btn-sm ${activeTab === tab ? 'btn-primary' : 'btn-secondary'}`}
                onClick={() => setActiveTab(tab)}
                style={{ textTransform: 'capitalize' }}
              >
                {tab === 'pending' ? 'Pending Approval' : tab}
              </button>
            ))}
          </div>
          <div className="input-icon-wrapper" style={{ width: '300px' }}>
            <Search size={16} />
            <input 
              type="text" 
              placeholder="Search name, plate, vehicle..." 
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
            />
          </div>
        </div>
      </div>

      {/* Partners List Table */}
      <div className="table-wrapper">
        <table>
          <thead>
            <tr>
              <th>Pilot Name</th>
              <th>Vehicle Category</th>
              <th>License Plate</th>
              <th>Rating / Trips</th>
              <th>Total Earnings</th>
              <th>Status</th>
              <th style={{ textAlign: 'right' }}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {filteredPartners.length > 0 ? (
              filteredPartners.map(p => (
                <tr key={p.uid}>
                  <td>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                      <img 
                        src={p.documents.profilePhoto} 
                        alt={p.name} 
                        style={{ width: '36px', height: '36px', borderRadius: '50%', objectFit: 'cover', border: '1px solid var(--border)' }}
                      />
                      <div>
                        <div style={{ fontWeight: 600 }}>{p.name}</div>
                        <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>+91 {p.phone}</div>
                      </div>
                    </div>
                  </td>
                  <td>
                    <div style={{ fontWeight: 500 }}>{p.vehicleType}</div>
                    <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>{p.vehicleModelColor}</div>
                  </td>
                  <td style={{ fontFamily: 'monospace', fontWeight: 600 }}>{p.vehiclePlate}</td>
                  <td>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '4px', fontWeight: 600 }}>
                      <Star size={14} fill="#fbbf24" stroke="#fbbf24" />
                      <span>{p.rating > 0 ? p.rating.toFixed(1) : 'New'}</span>
                    </div>
                    <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>{p.totalTrips} trips • {p.totalDeliveries} delivery</div>
                  </td>
                  <td style={{ fontWeight: 600 }}>₹{p.earnings.toLocaleString('en-IN')}</td>
                  <td>
                    <span className={`badge ${getStatusBadgeClass(p.status)}`}>
                      {p.status}
                    </span>
                  </td>
                  <td style={{ textAlign: 'right' }}>
                    <div style={{ display: 'flex', gap: '8px', justifyContent: 'flex-end' }}>
                      <button 
                        className="btn btn-secondary btn-sm"
                        onClick={() => setSelectedPartner(p)}
                      >
                        <Eye size={14} />
                        <span>Inspect Profile</span>
                      </button>
                      
                      {p.status === 'pending' && (
                        <>
                          <button 
                            className="btn btn-success btn-sm btn-icon"
                            onClick={() => verifyPartner(p.uid, 'approved')}
                            title="Quick Approve"
                          >
                            <Check size={14} />
                          </button>
                          <button 
                            className="btn btn-danger btn-sm btn-icon"
                            onClick={() => verifyPartner(p.uid, 'rejected')}
                            title="Quick Reject"
                          >
                            <X size={14} />
                          </button>
                        </>
                      )}
                      
                      {p.status === 'approved' && (
                        <button 
                          className="btn btn-danger btn-sm"
                          onClick={() => verifyPartner(p.uid, 'suspended')}
                          title="Suspend Partner"
                        >
                          <Ban size={14} />
                          <span>Suspend</span>
                        </button>
                      )}

                      {p.status === 'suspended' && (
                        <button 
                          className="btn btn-success btn-sm"
                          onClick={() => verifyPartner(p.uid, 'approved')}
                          title="Reactivate Partner"
                        >
                          <ShieldCheck size={14} />
                          <span>Activate</span>
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              ))
            ) : (
              <tr>
                <td colSpan={7} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: '24px' }}>
                  No pilot records matched.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {/* Partner Credentials Audit Modal */}
      {selectedPartner && (
        <div className="modal-overlay">
          <div className="modal-content" style={{ maxWidth: '850px' }}>
            <div className="modal-header">
              <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                <img 
                  src={selectedPartner.documents.profilePhoto} 
                  alt={selectedPartner.name} 
                  style={{ width: '48px', height: '48px', borderRadius: '50%', objectFit: 'cover' }}
                />
                <div>
                  <h3 style={{ fontSize: '18px' }}>Pilot Credentials Review: {selectedPartner.name}</h3>
                  <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>UID: {selectedPartner.uid} • +91 {selectedPartner.phone}</span>
                </div>
              </div>
              <button 
                className="btn btn-secondary btn-icon" 
                onClick={() => setSelectedPartner(null)}
                style={{ width: '32px', height: '32px', minWidth: '32px' }}
              >
                <X size={14} />
              </button>
            </div>
            
            <div className="modal-body" style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '20px' }}>
              {/* Left Column - Partner Info */}
              <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
                <h4 style={{ fontSize: '14px', borderBottom: '1px solid var(--border)', paddingBottom: '6px' }}>Profile Details</h4>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px', fontSize: '13px' }}>
                  <div>
                    <span style={{ color: 'var(--text-muted)' }}>Email Address</span>
                    <div style={{ fontWeight: 600 }}>{selectedPartner.email}</div>
                  </div>
                  <div>
                    <span style={{ color: 'var(--text-muted)' }}>Vehicle Registered</span>
                    <div style={{ fontWeight: 600 }}>{selectedPartner.vehicleType} ({selectedPartner.vehicleModelColor})</div>
                  </div>
                  <div>
                    <span style={{ color: 'var(--text-muted)' }}>License Plate</span>
                    <div style={{ fontWeight: 700, color: 'var(--primary)', fontFamily: 'monospace' }}>{selectedPartner.vehiclePlate}</div>
                  </div>
                  <div>
                    <span style={{ color: 'var(--text-muted)' }}>Current Status</span>
                    <div>
                      <span className={`badge ${getStatusBadgeClass(selectedPartner.status)}`}>
                        {selectedPartner.status}
                      </span>
                    </div>
                  </div>
                  <div>
                    <span style={{ color: 'var(--text-muted)' }}>Rating Score</span>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '4px', fontWeight: 600 }}>
                      <Star size={14} fill="#fbbf24" stroke="#fbbf24" />
                      <span>{selectedPartner.rating > 0 ? selectedPartner.rating.toFixed(1) : 'N/A'}</span>
                    </div>
                  </div>
                  <div>
                    <span style={{ color: 'var(--text-muted)' }}>Wallet Balance</span>
                    <div style={{ fontWeight: 700 }}>₹{selectedPartner.walletBalance.toFixed(2)}</div>
                  </div>
                </div>

                <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', backgroundColor: 'var(--bg-input)', padding: '12px', borderRadius: '8px', fontSize: '12px' }}>
                  <div style={{ fontWeight: 600 }}>Historical Performance summary:</div>
                  <div>Trips Executed: <strong>{selectedPartner.totalTrips} Completed rides</strong></div>
                  <div>Parcels Delivered: <strong>{selectedPartner.totalDeliveries} Completed cargo bookings</strong></div>
                  <div>Aggregated Platform Earnings: <strong>₹{selectedPartner.earnings.toLocaleString()}</strong></div>
                </div>
              </div>

              {/* Right Column - Scanned Registration Documents */}
              <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
                <h4 style={{ fontSize: '14px', borderBottom: '1px solid var(--border)', paddingBottom: '6px' }}>Uploaded Verification Files</h4>
                <div className="document-grid" style={{ gridTemplateColumns: '1fr 1fr', maxHeight: '300px', overflowY: 'auto' }}>
                  <div className="document-card">
                    <div className="document-title">Aadhaar Card Front</div>
                    <div className="document-preview">
                      <div className="document-placeholder">
                        <FileText size={24} />
                        <span>{selectedPartner.documents.aadhaarFront}</span>
                      </div>
                    </div>
                  </div>

                  <div className="document-card">
                    <div className="document-title">Aadhaar Card Back</div>
                    <div className="document-preview">
                      <div className="document-placeholder">
                        <FileText size={24} />
                        <span>{selectedPartner.documents.aadhaarBack}</span>
                      </div>
                    </div>
                  </div>

                  <div className="document-card">
                    <div className="document-title">Driving License Front</div>
                    <div className="document-preview">
                      <div className="document-placeholder">
                        <FileText size={24} />
                        <span>{selectedPartner.documents.drivingLicenseFront}</span>
                      </div>
                    </div>
                  </div>

                  <div className="document-card">
                    <div className="document-title">Driving License Back</div>
                    <div className="document-preview">
                      <div className="document-placeholder">
                        <FileText size={24} />
                        <span>{selectedPartner.documents.drivingLicenseBack}</span>
                      </div>
                    </div>
                  </div>

                  <div className="document-card">
                    <div className="document-title">Vehicle RC Front</div>
                    <div className="document-preview">
                      <div className="document-placeholder">
                        <FileText size={24} />
                        <span>{selectedPartner.documents.rcFront}</span>
                      </div>
                    </div>
                  </div>

                  <div className="document-card">
                    <div className="document-title">Vehicle RC Back</div>
                    <div className="document-preview">
                      <div className="document-placeholder">
                        <FileText size={24} />
                        <span>{selectedPartner.documents.rcBack}</span>
                      </div>
                    </div>
                  </div>

                  {selectedPartner.documents.fitness && (
                    <div className="document-card">
                      <div className="document-title">Fitness Certificate</div>
                      <div className="document-preview">
                        <div className="document-placeholder">
                          <FileText size={24} />
                          <span>{selectedPartner.documents.fitness}</span>
                        </div>
                      </div>
                    </div>
                  )}

                  {selectedPartner.documents.permit && (
                    <div className="document-card">
                      <div className="document-title">Vehicle Permit</div>
                      <div className="document-preview">
                        <div className="document-placeholder">
                          <FileText size={24} />
                          <span>{selectedPartner.documents.permit}</span>
                        </div>
                      </div>
                    </div>
                  )}
                </div>
              </div>
            </div>

            <div className="modal-footer">
              {selectedPartner.status === 'pending' ? (
                <>
                  <button 
                    className="btn btn-danger"
                    onClick={() => {
                      verifyPartner(selectedPartner.uid, 'rejected');
                      setSelectedPartner(null);
                    }}
                  >
                    Reject Application
                  </button>
                  <button 
                    className="btn btn-success"
                    onClick={() => {
                      verifyPartner(selectedPartner.uid, 'approved');
                      setSelectedPartner(null);
                    }}
                  >
                    Approve & Onboard Pilot
                  </button>
                </>
              ) : selectedPartner.status === 'approved' ? (
                <button 
                  className="btn btn-danger"
                  onClick={() => {
                    verifyPartner(selectedPartner.uid, 'suspended');
                    setSelectedPartner(null);
                  }}
                >
                  Suspend Pilot Duty
                </button>
              ) : (
                <button 
                  className="btn btn-success"
                  onClick={() => {
                    verifyPartner(selectedPartner.uid, 'approved');
                    setSelectedPartner(null);
                  }}
                >
                  Reactivate Pilot
                </button>
              )}
              <button className="btn btn-secondary" onClick={() => setSelectedPartner(null)}>Close Review</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
export default Partners;
