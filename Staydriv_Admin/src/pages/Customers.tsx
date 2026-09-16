import React, { useState } from 'react';
import { useDatabase } from '../context/DatabaseContext';
import { Search, UserCheck, ShieldAlert, ArrowLeftRight, Download, Eye, X } from 'lucide-react';

export const Customers: React.FC = () => {
  const { customers, bookings, deliveries, blockCustomer } = useDatabase();
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedCustomer, setSelectedCustomer] = useState<any | null>(null);

  // Filtered List
  const filteredCustomers = customers.filter(c => 
    c.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    c.email.toLowerCase().includes(searchTerm.toLowerCase()) ||
    c.phone.includes(searchTerm)
  );

  // Handle Export to CSV
  const handleExportCSV = () => {
    const headers = ['UID', 'Name', 'Email', 'Phone', 'Wallet Balance', 'Status', 'Registration Date'];
    const rows = filteredCustomers.map(c => [
      c.uid,
      c.name,
      c.email,
      c.phone,
      `₹${c.walletBalance}`,
      c.status,
      c.createdAt
    ]);

    const csvContent = [headers.join(','), ...rows.map(r => r.join(','))].join('\n');
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.setAttribute('href', url);
    link.setAttribute('download', `StayDriv_Customers_${new Date().toISOString().split('T')[0]}.csv`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  // Get customer specific stats
  const getCustomerHistory = (uid: string) => {
    const rides = bookings.filter(b => b.customerId === uid);
    const parcels = deliveries.filter(d => d.customerId === uid);
    return { rides, parcels };
  };

  return (
    <div className="page-container">
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div>
          <h2>Customer Directory</h2>
          <p style={{ color: 'var(--text-muted)', fontSize: '14px' }}>Search and manage StayDriv client accounts.</p>
        </div>
        <button className="btn btn-secondary" onClick={handleExportCSV}>
          <Download size={16} />
          <span>Export Directory</span>
        </button>
      </div>

      {/* Search and Filters */}
      <div className="card" style={{ padding: '16px' }}>
        <div className="input-icon-wrapper" style={{ maxWidth: '400px' }}>
          <Search size={16} />
          <input 
            type="text" 
            placeholder="Search by name, email or phone number..." 
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
          />
        </div>
      </div>

      {/* Customers Table */}
      <div className="table-wrapper">
        <table>
          <thead>
            <tr>
              <th>Client Name</th>
              <th>Contact Details</th>
              <th>Wallet Balance</th>
              <th>Status</th>
              <th>Registered At</th>
              <th style={{ textAlign: 'right' }}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {filteredCustomers.length > 0 ? (
              filteredCustomers.map(c => (
                <tr key={c.uid}>
                  <td>
                    <div style={{ fontWeight: 600 }}>{c.name}</div>
                    <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>UID: {c.uid}</div>
                  </td>
                  <td>
                    <div>{c.email}</div>
                    <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>+91 {c.phone}</div>
                  </td>
                  <td style={{ fontWeight: 600 }}>₹{c.walletBalance.toFixed(2)}</td>
                  <td>
                    <span className={`badge badge-${c.status}`}>
                      {c.status}
                    </span>
                  </td>
                  <td>{new Date(c.createdAt).toLocaleDateString('en-IN')}</td>
                  <td style={{ textAlign: 'right' }}>
                    <div style={{ display: 'flex', gap: '8px', justifyContent: 'flex-end' }}>
                      <button 
                        className="btn btn-secondary btn-sm"
                        onClick={() => setSelectedCustomer(c)}
                        title="View Profile Details"
                      >
                        <Eye size={14} />
                        <span>Inspect</span>
                      </button>
                      <button 
                        className={`btn btn-sm ${c.status === 'blocked' ? 'btn-success' : 'btn-danger'}`}
                        onClick={() => blockCustomer(c.uid, c.status !== 'blocked')}
                      >
                        {c.status === 'blocked' ? <UserCheck size={14} /> : <ShieldAlert size={14} />}
                        <span>{c.status === 'blocked' ? 'Unblock' : 'Block'}</span>
                      </button>
                    </div>
                  </td>
                </tr>
              ))
            ) : (
              <tr>
                <td colSpan={6} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: '24px' }}>
                  No customer records matched your query.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {/* Customer Profile Details Modal */}
      {selectedCustomer && (() => {
        const history = getCustomerHistory(selectedCustomer.uid);
        return (
          <div className="modal-overlay">
            <div className="modal-content" style={{ maxWidth: '800px' }}>
              <div className="modal-header">
                <div>
                  <h3 style={{ fontSize: '18px' }}>Customer Profile: {selectedCustomer.name}</h3>
                  <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>UID: {selectedCustomer.uid}</span>
                </div>
                <button 
                  className="btn btn-secondary btn-icon" 
                  onClick={() => setSelectedCustomer(null)}
                  style={{ width: '32px', height: '32px', minWidth: '32px' }}
                >
                  <X size={14} />
                </button>
              </div>
              <div className="modal-body">
                {/* Top Info Grid */}
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px', backgroundColor: 'var(--bg-input)', padding: '16px', borderRadius: '12px' }}>
                  <div>
                    <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Email Address</span>
                    <div style={{ fontWeight: 600 }}>{selectedCustomer.email}</div>
                  </div>
                  <div>
                    <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Phone Number</span>
                    <div style={{ fontWeight: 600 }}>+91 {selectedCustomer.phone}</div>
                  </div>
                  <div>
                    <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Wallet Balance</span>
                    <div style={{ fontWeight: 700, color: 'var(--primary)' }}>₹{selectedCustomer.walletBalance.toFixed(2)}</div>
                  </div>
                  <div>
                    <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Account Status</span>
                    <div>
                      <span className={`badge badge-${selectedCustomer.status}`}>
                        {selectedCustomer.status}
                      </span>
                    </div>
                  </div>
                </div>

                {/* History Section */}
                <div>
                  <h4 style={{ fontSize: '14px', marginBottom: '10px' }}>Trip & Parcel Booking History</h4>
                  
                  {/* Rides History list */}
                  <h5 style={{ fontSize: '12px', color: 'var(--text-muted)', marginBottom: '8px' }}>🚕 Passenger Rides ({history.rides.length})</h5>
                  {history.rides.length > 0 ? (
                    <div className="table-wrapper" style={{ maxHeight: '180px', overflowY: 'auto', marginBottom: '16px' }}>
                      <table>
                        <thead>
                          <tr>
                            <th>Ride ID</th>
                            <th>Pickup / Drop</th>
                            <th>Fare</th>
                            <th>Status</th>
                            <th>Date</th>
                          </tr>
                        </thead>
                        <tbody>
                          {history.rides.map(b => (
                            <tr key={b.bookingId}>
                              <td style={{ fontWeight: 600 }}>{b.bookingId}</td>
                              <td style={{ fontSize: '12px', maxWidth: '300px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                                <div><strong>From:</strong> {b.pickup}</div>
                                <div><strong>To:</strong> {b.drop}</div>
                              </td>
                              <td>{b.price}</td>
                              <td><span className={`badge badge-${b.status}`}>{b.status}</span></td>
                              <td style={{ fontSize: '12px' }}>{new Date(b.createdAt).toLocaleDateString('en-IN')}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  ) : (
                    <p style={{ fontSize: '12px', color: 'var(--text-muted)', marginBottom: '16px' }}>No ride records found.</p>
                  )}

                  {/* Deliveries History list */}
                  <h5 style={{ fontSize: '12px', color: 'var(--text-muted)', marginBottom: '8px' }}>📦 Parcel Deliveries ({history.parcels.length})</h5>
                  {history.parcels.length > 0 ? (
                    <div className="table-wrapper" style={{ maxHeight: '180px', overflowY: 'auto' }}>
                      <table>
                        <thead>
                          <tr>
                            <th>Delivery ID</th>
                            <th>Cargo Details</th>
                            <th>Fare</th>
                            <th>Status</th>
                            <th>Date</th>
                          </tr>
                        </thead>
                        <tbody>
                          {history.parcels.map(d => (
                            <tr key={d.bookingId}>
                              <td style={{ fontWeight: 600 }}>{d.bookingId}</td>
                              <td style={{ fontSize: '12px' }}>
                                <div><strong>Type:</strong> {d.goodsType} ({d.weight})</div>
                                <div style={{ color: 'var(--text-muted)', maxWidth: '300px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>To: {d.drop}</div>
                              </td>
                              <td>{d.price}</td>
                              <td><span className={`badge badge-${d.status}`}>{d.status}</span></td>
                              <td style={{ fontSize: '12px' }}>{new Date(d.createdAt).toLocaleDateString('en-IN')}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  ) : (
                    <p style={{ fontSize: '12px', color: 'var(--text-muted)' }}>No delivery records found.</p>
                  )}
                </div>
              </div>
              <div className="modal-footer">
                <button 
                  className={`btn ${selectedCustomer.status === 'blocked' ? 'btn-success' : 'btn-danger'}`}
                  onClick={() => {
                    blockCustomer(selectedCustomer.uid, selectedCustomer.status !== 'blocked');
                    setSelectedCustomer({ ...selectedCustomer, status: selectedCustomer.status === 'blocked' ? 'active' : 'blocked' });
                  }}
                >
                  {selectedCustomer.status === 'blocked' ? 'Reactivate Account' : 'Suspend Account'}
                </button>
                <button className="btn btn-secondary" onClick={() => setSelectedCustomer(null)}>Close Profile</button>
              </div>
            </div>
          </div>
        );
      })()}
    </div>
  );
};
export default Customers;
