import React, { useState, useEffect } from 'react';
import { useDatabase } from '../context/DatabaseContext';
import { 
  AlertTriangle, CheckCircle2, Clock, Search, RefreshCw, 
  MessageSquare, UserX, ShieldAlert, ArrowRight 
} from 'lucide-react';

export const RefundsDisputes: React.FC = () => {
  const [complaints, setComplaints] = useState<any[]>([]);
  const [refunds, setRefunds] = useState<any[]>([]);
  const [activeTab, setActiveTab] = useState<'complaints' | 'refunds'>('complaints');
  const [isLoading, setIsLoading] = useState(false);
  const [resolutionModal, setResolutionModal] = useState<any>(null);
  const [resolutionNotes, setResolutionNotes] = useState('');

  const backendUrl = (window as any).REACT_APP_BACKEND_URL || 
    (window.location.port === '5173' ? 'http://localhost:3000' : window.location.origin);

  const token = localStorage.getItem('staydriv_admin_token') || 'staydriv_admin_secret_2026';
  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${token}`,
    'x-admin-key': 'staydriv_admin_secret_2026'
  };

  const fetchData = async () => {
    setIsLoading(true);
    try {
      const [compRes, refRes] = await Promise.all([
        fetch(`${backendUrl}/api/admin/complaints`, { headers }).then(r => r.json()),
        fetch(`${backendUrl}/api/admin/stats`, { headers }).then(r => r.json())
      ]);

      if (compRes.success && Array.isArray(compRes.complaints)) {
        setComplaints(compRes.complaints);
      }
      // Fetch refunds directly
      const refundsResponse = await fetch(`${backendUrl}/api/admin/refunds`, { headers })
        .then(r => r.json())
        .catch(() => ({ success: false, refunds: [] }));

      if (refundsResponse.success && Array.isArray(refundsResponse.refunds)) {
        setRefunds(refundsResponse.refunds);
      }
    } catch (err) {
      console.warn('Error fetching disputes:', err);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
  }, []);

  const handleResolveComplaint = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!resolutionModal) return;

    try {
      const res = await fetch(`${backendUrl}/api/admin/complaint/resolve`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          complaintId: resolutionModal.complaintId,
          resolutionNotes
        })
      });
      const data = await res.json();
      if (data.success) {
        setResolutionModal(null);
        setResolutionNotes('');
        await fetchData();
      }
    } catch (err) {
      alert('Failed to resolve complaint.');
    }
  };

  return (
    <div className="page-container">
      {/* Top Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '16px' }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <h2>Customer & Pilot Disputes and Refunds</h2>
            <span style={{ 
              display: 'inline-flex', 
              alignItems: 'center', 
              gap: '6px', 
              padding: '4px 10px', 
              borderRadius: '20px', 
              fontSize: '11px', 
              fontWeight: 700, 
              background: 'rgba(239, 68, 68, 0.15)', 
              color: 'var(--error)' 
            }}>
              <AlertTriangle size={12} />
              DISPUTE RESOLUTION ACTIVE
            </span>
          </div>
          <p style={{ color: 'var(--text-muted)', fontSize: '13px', marginTop: '4px' }}>
            Investigate customer grievances, pilot misconduct, ride disputes, and processed refunds.
          </p>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          <div style={{ display: 'flex', background: 'var(--bg-input)', padding: '2px', borderRadius: '6px' }}>
            <button 
              className={`btn btn-sm ${activeTab === 'complaints' ? 'btn-primary' : 'btn-secondary'}`}
              onClick={() => setActiveTab('complaints')}
              style={{ border: 'none' }}
            >
              Complaints & Misbehaviour ({complaints.length})
            </button>
            <button 
              className={`btn btn-sm ${activeTab === 'refunds' ? 'btn-primary' : 'btn-secondary'}`}
              onClick={() => setActiveTab('refunds')}
              style={{ border: 'none' }}
            >
              Customer Refunds ({refunds.length})
            </button>
          </div>

          <button className="btn btn-secondary btn-sm" onClick={fetchData} disabled={isLoading}>
            <RefreshCw size={14} className={isLoading ? 'animate-spin' : ''} />
          </button>
        </div>
      </div>

      {/* Complaints Table */}
      {activeTab === 'complaints' && (
        <div className="card" style={{ padding: '0', overflow: 'hidden' }}>
          <div className="table-responsive">
            <table className="data-table" style={{ fontSize: '12px' }}>
              <thead>
                <tr>
                  <th>Complaint ID</th>
                  <th>Category</th>
                  <th>Reported By</th>
                  <th>Subject & Details</th>
                  <th>Target User</th>
                  <th>Booking ID</th>
                  <th>Status</th>
                  <th>Date Filed</th>
                  <th>Action</th>
                </tr>
              </thead>
              <tbody>
                {complaints.length === 0 ? (
                  <tr>
                    <td colSpan={9} style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>
                      No reported complaints found.
                    </td>
                  </tr>
                ) : (
                  complaints.map((c, idx) => (
                    <tr key={c.complaintId || idx}>
                      <td>
                        <span style={{ fontFamily: 'monospace', fontWeight: 600, color: 'var(--primary)' }}>
                          {c.complaintId}
                        </span>
                      </td>
                      <td>
                        <span className="badge badge-warning" style={{ fontSize: '10px' }}>
                          {(c.type || 'general').replace(/_/g, ' ')}
                        </span>
                      </td>
                      <td>
                        <div style={{ fontWeight: 600 }}>{c.reportedByName}</div>
                        <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>{c.reportedByRole} (📞 {c.reportedByPhone})</div>
                      </td>
                      <td>
                        <div style={{ fontWeight: 600 }}>{c.subject}</div>
                        <div style={{ fontSize: '11px', color: 'var(--text-muted)', maxWidth: '280px', whiteSpace: 'normal' }}>
                          {c.description}
                        </div>
                        {c.resolutionNotes && (
                          <div style={{ fontSize: '10px', color: 'var(--success)', marginTop: '4px' }}>
                            <strong>Resolution:</strong> {c.resolutionNotes}
                          </div>
                        )}
                      </td>
                      <td>
                        <div>{c.targetName || 'N/A'}</div>
                        <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>{c.targetPhone}</div>
                      </td>
                      <td>
                        <span style={{ fontFamily: 'monospace', fontSize: '11px' }}>{c.bookingId || 'N/A'}</span>
                      </td>
                      <td>
                        <span className={`badge ${c.status === 'resolved' ? 'badge-success' : 'badge-error'}`}>
                          {c.status}
                        </span>
                      </td>
                      <td>
                        <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                          {c.createdAt ? new Date(c.createdAt).toLocaleDateString() : 'N/A'}
                        </span>
                      </td>
                      <td>
                        {c.status !== 'resolved' ? (
                          <button 
                            className="btn btn-primary btn-sm"
                            onClick={() => {
                              setResolutionModal(c);
                              setResolutionNotes('');
                            }}
                            style={{ fontSize: '11px', padding: '4px 8px' }}
                          >
                            Resolve
                          </button>
                        ) : (
                          <span style={{ color: 'var(--success)', fontSize: '11px' }}>Resolved</span>
                        )}
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Refunds Table */}
      {activeTab === 'refunds' && (
        <div className="card" style={{ padding: '0', overflow: 'hidden' }}>
          <div className="table-responsive">
            <table className="data-table" style={{ fontSize: '12px' }}>
              <thead>
                <tr>
                  <th>Refund ID</th>
                  <th>Customer Name & Phone</th>
                  <th>Booking ID</th>
                  <th>Amount</th>
                  <th>Payment Method</th>
                  <th>Reason</th>
                  <th>Status</th>
                  <th>Processed At</th>
                </tr>
              </thead>
              <tbody>
                {refunds.length === 0 ? (
                  <tr>
                    <td colSpan={8} style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>
                      No refund records found.
                    </td>
                  </tr>
                ) : (
                  refunds.map((r, idx) => (
                    <tr key={r.refundId || idx}>
                      <td>
                        <span style={{ fontFamily: 'monospace', fontWeight: 600, color: 'var(--primary)' }}>
                          {r.refundId}
                        </span>
                      </td>
                      <td>
                        <div style={{ fontWeight: 600 }}>{r.userName}</div>
                        <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>📞 {r.userPhone}</div>
                      </td>
                      <td>
                        <span style={{ fontFamily: 'monospace', fontSize: '11px' }}>{r.bookingId}</span>
                      </td>
                      <td>
                        <span style={{ fontWeight: 700, color: 'var(--text-main)', fontSize: '13px' }}>
                          {r.amount}
                        </span>
                      </td>
                      <td>
                        <span style={{ fontSize: '11px' }}>{r.paymentMethod}</span>
                      </td>
                      <td>
                        <span style={{ fontSize: '11px' }}>{r.reason}</span>
                      </td>
                      <td>
                        <span className={`badge ${r.status === 'processed' ? 'badge-success' : 'badge-warning'}`}>
                          {r.status}
                        </span>
                      </td>
                      <td>
                        <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                          {r.createdAt ? new Date(r.createdAt).toLocaleDateString() : 'N/A'}
                        </span>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Resolution Modal */}
      {resolutionModal && (
        <div style={{
          position: 'fixed',
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          backgroundColor: 'rgba(0,0,0,0.75)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 1000,
          padding: '20px'
        }}>
          <div className="card" style={{ maxWidth: '500px', width: '100%' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid var(--border)', paddingBottom: '12px' }}>
              <h3>Resolve Complaint {resolutionModal.complaintId}</h3>
              <button className="btn btn-secondary btn-sm" onClick={() => setResolutionModal(null)}>✕</button>
            </div>

            <div style={{ marginTop: '14px', fontSize: '13px', background: 'var(--bg-input)', padding: '10px', borderRadius: '6px' }}>
              <strong>Subject:</strong> {resolutionModal.subject}
              <div style={{ color: 'var(--text-muted)', marginTop: '4px' }}>{resolutionModal.description}</div>
            </div>

            <form onSubmit={handleResolveComplaint} style={{ marginTop: '16px' }}>
              <div className="form-group" style={{ marginBottom: '16px' }}>
                <label className="label">Resolution Action Notes *</label>
                <textarea 
                  rows={3}
                  className="input"
                  placeholder="State the resolution action taken (e.g., Pilot issued formal warning, customer refunded, ride fare adjusted)..."
                  value={resolutionNotes}
                  onChange={e => setResolutionNotes(e.target.value)}
                  required
                />
              </div>

              <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px' }}>
                <button type="button" className="btn btn-secondary" onClick={() => setResolutionModal(null)}>
                  Cancel
                </button>
                <button type="submit" className="btn btn-primary">
                  Mark Complaint Resolved
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};

export default RefundsDisputes;
