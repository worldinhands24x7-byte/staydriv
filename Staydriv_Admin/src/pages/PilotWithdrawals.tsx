import React, { useState } from 'react';
import { useDatabase } from '../context/DatabaseContext';
import { useAuth } from '../context/AuthContext';
import { 
  CreditCard, Search, Download, RefreshCw, CheckCircle2, XCircle, 
  Clock, AlertTriangle, ArrowRight, ShieldCheck, Eye, RotateCw, ExternalLink 
} from 'lucide-react';

export const PilotWithdrawals: React.FC = () => {
  const { withdrawals, processWithdrawalAction, refreshFinancials, exportReport, lastUpdatedTime } = useDatabase();
  const { activeRole } = useAuth();

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
      if (e.detail?.filter && (e.detail?.tab === 'withdrawals' || !e.detail?.tab)) {
        setSearchTerm(e.detail.filter);
      }
    };
    window.addEventListener('admin:search-navigate', handleSearchNav);
    return () => window.removeEventListener('admin:search-navigate', handleSearchNav);
  }, []);
  const [statusFilter, setStatusFilter] = useState('all');
  const [selectedWithdrawal, setSelectedWithdrawal] = useState<any>(null);
  const [modalMode, setModalMode] = useState<'details' | 'approve' | 'reject' | 'initiate' | 'complete' | 'retry' | null>(null);

  // Form states for modal actions
  const [actionRemarks, setActionRemarks] = useState('');
  const [rejectionReason, setRejectionReason] = useState('');
  const [settlementUtr, setSettlementUtr] = useState('');
  const [isProcessingAction, setIsProcessingAction] = useState(false);
  const [actionError, setActionError] = useState('');

  const isPrivileged = activeRole === 'super_admin' || activeRole === 'finance' || activeRole === 'admin' || !activeRole;

  // Filter list
  const filteredWithdrawals = (withdrawals || []).filter(w => {
    const matchesSearch = 
      (w.withdrawalId || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (w.transactionId || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (w.pilotName || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (w.pilotPhone || '').includes(searchTerm) ||
      (w.pilotId || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (w.utr || '').toLowerCase().includes(searchTerm.toLowerCase());

    const status = (w.status || '').toLowerCase();
    const matchesStatus = statusFilter === 'all' || 
      (statusFilter === 'pending' ? (status === 'pending' || status === 'pending_approval' || status === 'under_review') : false) ||
      (statusFilter === 'completed' ? (status === 'completed' || status === 'paid') : false) ||
      status === statusFilter.toLowerCase();
    return matchesSearch && matchesStatus;
  });

  const handleOpenAction = (item: any, mode: 'details' | 'approve' | 'reject' | 'initiate' | 'complete' | 'retry') => {
    setSelectedWithdrawal(item);
    setModalMode(mode);
    setActionRemarks('');
    setRejectionReason('');
    setSettlementUtr('');
    setActionError('');
  };

  const handleExecuteAction = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedWithdrawal || !modalMode) return;

    if (modalMode === 'reject' && (!rejectionReason || !rejectionReason.trim())) {
      setActionError('Mandatory rejection reason must be entered.');
      return;
    }
    if (modalMode === 'complete' && (!settlementUtr || !settlementUtr.trim())) {
      setActionError('Valid settlement UTR / Bank Reference Number is mandatory to mark completed.');
      return;
    }

    setIsProcessingAction(true);
    setActionError('');

    try {
      let actionName = '';
      let params: any = {};

      if (modalMode === 'approve') {
        actionName = 'approve';
        params = { remarks: actionRemarks };
      } else if (modalMode === 'reject') {
        actionName = 'reject';
        params = { reason: rejectionReason, remarks: actionRemarks };
      } else if (modalMode === 'initiate') {
        actionName = 'initiate_payout';
        params = { remarks: actionRemarks, gatewayRef: `POUT_${Date.now()}` };
      } else if (modalMode === 'complete') {
        actionName = 'mark_completed';
        params = { utr: settlementUtr, remarks: actionRemarks };
      } else if (modalMode === 'retry') {
        actionName = 'retry';
        params = { remarks: actionRemarks };
      }

      await processWithdrawalAction(selectedWithdrawal.withdrawalId, actionName, params);
      setModalMode(null);
      setSelectedWithdrawal(null);
    } catch (err: any) {
      setActionError(err.message || 'Operation failed.');
    } finally {
      setIsProcessingAction(false);
    }
  };

  const getStatusBadge = (status: string) => {
    const s = (status || '').toLowerCase();
    switch (s) {
      case 'paid':
      case 'completed':
        return <span className="badge badge-success"><CheckCircle2 size={12} style={{ marginRight: 4 }} /> Paid</span>;
      case 'approved':
        return <span className="badge badge-primary"><ShieldCheck size={12} style={{ marginRight: 4 }} /> Approved</span>;
      case 'processing':
        return <span className="badge badge-info"><Clock size={12} style={{ marginRight: 4 }} /> Processing</span>;
      case 'rejected':
        return <span className="badge badge-error"><XCircle size={12} style={{ marginRight: 4 }} /> Rejected</span>;
      case 'failed':
        return <span className="badge badge-error"><AlertTriangle size={12} style={{ marginRight: 4 }} /> Failed</span>;
      case 'cancelled':
        return <span className="badge badge-secondary" style={{ opacity: 0.7 }}><XCircle size={12} style={{ marginRight: 4 }} /> Cancelled</span>;
      case 'reversed':
        return <span className="badge badge-warning"><RotateCw size={12} style={{ marginRight: 4 }} /> Reversed</span>;
      case 'pending_approval':
      case 'pending':
      default:
        return <span className="badge badge-warning"><Clock size={12} style={{ marginRight: 4 }} /> Pending Approval</span>;
    }
  };

  return (
    <div className="page-container">
      {/* Top Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '16px' }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <h2>Pilot Withdrawal & Payout Management</h2>
            <span style={{ 
              display: 'inline-flex', 
              alignItems: 'center', 
              gap: '6px', 
              padding: '4px 10px', 
              borderRadius: '20px', 
              fontSize: '11px', 
              fontWeight: 700, 
              background: 'rgba(59, 130, 246, 0.15)', 
              color: 'var(--primary)' 
            }}>
              <ShieldCheck size={12} />
              IMMUTABLE AUDIT TRAIL
            </span>
          </div>
          <p style={{ color: 'var(--text-muted)', fontSize: '13px', marginTop: '4px' }}>
            Multi-stage verified payouts with balance reservation, double-entry escrow, UTR reconciliation, and duplicate locking.
          </p>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          <button 
            className="btn btn-secondary btn-sm" 
            onClick={() => exportReport('withdrawals')}
            style={{ display: 'flex', alignItems: 'center', gap: '6px' }}
          >
            <Download size={14} />
            <span>Export CSV</span>
          </button>
          <button 
            className="btn btn-secondary btn-sm" 
            onClick={refreshFinancials}
            style={{ display: 'flex', alignItems: 'center', gap: '6px' }}
          >
            <RefreshCw size={14} />
            <span>Refresh</span>
          </button>
        </div>
      </div>

      {/* Filter Toolbar */}
      <div className="card" style={{ padding: '16px' }}>
        <div style={{ display: 'flex', gap: '12px', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'space-between' }}>
          <div style={{ display: 'flex', gap: '12px', flex: '1', minWidth: '280px' }}>
            <div style={{ position: 'relative', flex: 1 }}>
              <Search size={16} style={{ position: 'absolute', left: '12px', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
              <input 
                type="text"
                placeholder="Search transaction ID, withdrawal ID, pilot name, phone, UTR..."
                value={searchTerm}
                onChange={e => setSearchTerm(e.target.value)}
                className="input"
                style={{ paddingLeft: '36px', width: '100%' }}
              />
            </div>

            <select 
              value={statusFilter} 
              onChange={e => setStatusFilter(e.target.value)}
              className="input"
              style={{ width: '160px' }}
            >
              <option value="all">All Statuses</option>
              <option value="pending">Pending</option>
              <option value="approved">Approved</option>
              <option value="processing">Processing</option>
              <option value="completed">Completed</option>
              <option value="rejected">Rejected</option>
              <option value="failed">Failed</option>
              <option value="reversed">Reversed</option>
            </select>
          </div>

          <span style={{ fontSize: '13px', color: 'var(--text-muted)' }}>
            Showing <strong>{filteredWithdrawals.length}</strong> withdrawal records
          </span>
        </div>
      </div>

      {/* 20-Column Master Withdrawals Table */}
      <div className="card" style={{ padding: '0', overflow: 'hidden' }}>
        <div style={{ padding: '16px 20px', borderBottom: '1px solid var(--border)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <h3 style={{ fontSize: '15px' }}>Pilot Advance & Salary Withdrawal Requests</h3>
          <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Approval alone != Completed payment. Confirmed settlement required.</span>
        </div>

        <div className="table-responsive">
          <table className="data-table" style={{ fontSize: '12px' }}>
            <thead>
              <tr>
                <th>Txn & Request ID</th>
                <th>Pilot Details</th>
                <th>Requested</th>
                <th>Fee</th>
                <th>Net Payable</th>
                <th>Destination (Masked)</th>
                <th>Gateway Ref / UTR</th>
                <th>Status</th>
                <th>Approval</th>
                <th>Approved By</th>
                <th>Dates (Req / Settled)</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {filteredWithdrawals.length === 0 ? (
                <tr>
                  <td colSpan={12} style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>
                    No withdrawal transactions found.
                  </td>
                </tr>
              ) : (
                filteredWithdrawals.map((w, idx) => (
                  <tr key={w.withdrawalId || idx}>
                    <td>
                      <div style={{ display: 'flex', flexDirection: 'column' }}>
                        <span style={{ fontWeight: 700, color: 'var(--primary)', fontFamily: 'monospace' }}>{w.transactionId}</span>
                        <span style={{ fontSize: '10px', color: 'var(--text-muted)', fontFamily: 'monospace' }}>{w.withdrawalId}</span>
                      </div>
                    </td>
                    <td>
                      <div style={{ display: 'flex', flexDirection: 'column' }}>
                        <span style={{ fontWeight: 600, color: 'var(--text-main)' }}>{w.pilotName}</span>
                        <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>📞 {(w.pilotPhone || '').replace('pilot_', '')}</span>
                        <span style={{ fontSize: '10px', color: 'var(--text-muted)' }}>ID: {w.pilotId}</span>
                      </div>
                    </td>
                    <td>
                      <span style={{ fontWeight: 700, color: 'var(--text-main)' }}>₹{(w.requestedAmount || 0).toFixed(2)}</span>
                    </td>
                    <td>
                      <span style={{ color: 'var(--text-muted)' }}>₹{(w.withdrawalFee || 0).toFixed(2)}</span>
                    </td>
                    <td>
                      <span style={{ fontWeight: 700, color: 'var(--success)', fontSize: '13px' }}>₹{(w.netPayableAmount || 0).toFixed(2)}</span>
                    </td>
                    <td>
                      <span style={{ fontFamily: 'monospace', fontSize: '11px', background: 'rgba(255,255,255,0.04)', padding: '2px 4px', borderRadius: '4px' }}>
                        {w.maskedDestination}
                      </span>
                    </td>
                    <td>
                      <div style={{ display: 'flex', flexDirection: 'column' }}>
                        <span style={{ fontFamily: 'monospace', fontSize: '11px', color: 'var(--text-main)' }}>
                          {w.utr && w.utr !== 'Pending settlement' ? `UTR: ${w.utr}` : (w.paymentGatewayRef || 'N/A')}
                        </span>
                      </div>
                    </td>
                    <td>
                      {getStatusBadge(w.status)}
                    </td>
                    <td>
                      <span style={{ 
                        fontSize: '11px', 
                        fontWeight: 600, 
                        color: w.approvalStatus === 'approved' ? 'var(--success)' : (w.approvalStatus === 'rejected' ? 'var(--error)' : 'var(--warning)') 
                      }}>
                        {w.approvalStatus ? w.approvalStatus.toUpperCase() : 'PENDING'}
                      </span>
                    </td>
                    <td>
                      <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>{w.approvedOrRejectedBy}</span>
                    </td>
                    <td>
                      <div style={{ display: 'flex', flexDirection: 'column', fontSize: '10px', color: 'var(--text-muted)' }}>
                        <span>Req: {w.requestDate ? new Date(w.requestDate).toLocaleDateString() : 'N/A'}</span>
                        {w.actualSettlementDate && (
                          <span style={{ color: 'var(--success)' }}>Set: {new Date(w.actualSettlementDate).toLocaleDateString()}</span>
                        )}
                      </div>
                    </td>
                    <td>
                      <div style={{ display: 'flex', gap: '6px' }}>
                        <button 
                          className="btn btn-secondary btn-sm" 
                          onClick={() => handleOpenAction(w, 'details')}
                          title="View Full Details & Audit Trail"
                          style={{ padding: '4px 8px' }}
                        >
                          <Eye size={12} />
                        </button>

                        {isPrivileged && (w.status === 'pending' || w.status === 'pending_approval' || w.status === 'under_review') && (
                          <>
                            <button 
                              className="btn btn-primary btn-sm" 
                              onClick={() => handleOpenAction(w, 'approve')}
                              title="Approve Request"
                              style={{ padding: '4px 8px', backgroundColor: 'var(--success)', borderColor: 'var(--success)' }}
                            >
                              Approve
                            </button>
                            <button 
                              className="btn btn-secondary btn-sm" 
                              onClick={() => handleOpenAction(w, 'reject')}
                              title="Reject with Reason"
                              style={{ padding: '4px 8px', color: 'var(--error)' }}
                            >
                              Reject
                            </button>
                          </>
                        )}

                        {isPrivileged && w.status === 'approved' && (
                          <>
                            <button 
                              className="btn btn-primary btn-sm" 
                              onClick={() => handleOpenAction(w, 'initiate')}
                              title="Initiate Gateway Payout"
                              style={{ padding: '4px 8px' }}
                            >
                              Payout
                            </button>
                            <button 
                              className="btn btn-secondary btn-sm" 
                              onClick={() => handleOpenAction(w, 'reject')}
                              title="Reject Request"
                              style={{ padding: '4px 8px', color: 'var(--error)' }}
                            >
                              Reject
                            </button>
                          </>
                        )}

                        {isPrivileged && w.status === 'processing' && (
                          <button 
                            className="btn btn-primary btn-sm" 
                            onClick={() => handleOpenAction(w, 'complete')}
                            title="Confirm Settlement & Record UTR"
                            style={{ padding: '4px 8px', backgroundColor: 'var(--success)', borderColor: 'var(--success)' }}
                          >
                            Mark Settled
                          </button>
                        )}

                        {isPrivileged && w.status === 'failed' && (
                          <button 
                            className="btn btn-secondary btn-sm" 
                            onClick={() => handleOpenAction(w, 'retry')}
                            title="Retry Payout Safely"
                            style={{ padding: '4px 8px', color: 'var(--warning)' }}
                          >
                            <RotateCw size={12} /> Retry
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Action Modal */}
      {modalMode && selectedWithdrawal && (
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
          <div className="card" style={{ maxWidth: '580px', width: '100%', maxHeight: '90vh', overflowY: 'auto' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid var(--border)', paddingBottom: '12px' }}>
              <h3>
                {modalMode === 'details' && 'Withdrawal Details & Audit Trail'}
                {modalMode === 'approve' && 'Approve Withdrawal Request'}
                {modalMode === 'reject' && 'Reject Withdrawal Request'}
                {modalMode === 'initiate' && 'Initiate Provider Payout'}
                {modalMode === 'complete' && 'Confirm Bank Settlement (UTR Verification)'}
                {modalMode === 'retry' && 'Retry Failed Payout'}
              </h3>
              <button className="btn btn-secondary btn-sm" onClick={() => setModalMode(null)}>✕</button>
            </div>

            {actionError && (
              <div style={{ background: 'rgba(239, 68, 68, 0.1)', color: 'var(--error)', padding: '10px 14px', borderRadius: '6px', fontSize: '13px', marginTop: '14px' }}>
                ⚠️ {actionError}
              </div>
            )}

            {/* Quick Context Summary */}
            <div style={{ marginTop: '16px', background: 'var(--bg-input)', padding: '12px', borderRadius: '8px', fontSize: '13px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '6px' }}>
                <span style={{ color: 'var(--text-muted)' }}>Withdrawal ID:</span>
                <span style={{ fontWeight: 600, fontFamily: 'monospace' }}>{selectedWithdrawal.withdrawalId}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '6px' }}>
                <span style={{ color: 'var(--text-muted)' }}>Pilot Partner:</span>
                <span style={{ fontWeight: 600 }}>{selectedWithdrawal.pilotName} ({selectedWithdrawal.pilotPhone})</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '6px' }}>
                <span style={{ color: 'var(--text-muted)' }}>Requested Net Amount:</span>
                <span style={{ fontWeight: 700, color: 'var(--success)', fontSize: '15px' }}>₹{selectedWithdrawal.netPayableAmount.toFixed(2)}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: 'var(--text-muted)' }}>Destination Account:</span>
                <span style={{ fontFamily: 'monospace' }}>{selectedWithdrawal.maskedDestination}</span>
              </div>
            </div>

            {/* Detailed Audit Trail View */}
            {modalMode === 'details' && (
              <div style={{ marginTop: '20px' }}>
                <h4 style={{ fontSize: '13px', marginBottom: '10px', color: 'var(--text-muted)' }}>AUDIT TRAIL & LEDGER REFERENCES</h4>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                  <div style={{ fontSize: '12px', display: 'flex', justifyContent: 'space-between' }}>
                    <span style={{ color: 'var(--text-muted)' }}>Transaction Reference:</span>
                    <span style={{ fontFamily: 'monospace' }}>{selectedWithdrawal.transactionId}</span>
                  </div>
                  <div style={{ fontSize: '12px', display: 'flex', justifyContent: 'space-between' }}>
                    <span style={{ color: 'var(--text-muted)' }}>Gateway Provider Ref:</span>
                    <span style={{ fontFamily: 'monospace' }}>{selectedWithdrawal.paymentGatewayRef || 'None'}</span>
                  </div>
                  <div style={{ fontSize: '12px', display: 'flex', justifyContent: 'space-between' }}>
                    <span style={{ color: 'var(--text-muted)' }}>UTR / Bank Settlement:</span>
                    <span style={{ fontFamily: 'monospace', color: 'var(--primary)' }}>{selectedWithdrawal.utr || 'Pending'}</span>
                  </div>
                  {selectedWithdrawal.rejectionReason && (
                    <div style={{ fontSize: '12px', color: 'var(--error)' }}>
                      <strong>Rejection Reason:</strong> {selectedWithdrawal.rejectionReason}
                    </div>
                  )}
                  {selectedWithdrawal.failureReason && (
                    <div style={{ fontSize: '12px', color: 'var(--error)' }}>
                      <strong>Failure Reason:</strong> {selectedWithdrawal.failureReason}
                    </div>
                  )}
                </div>

                <h4 style={{ fontSize: '13px', margin: '16px 0 10px', color: 'var(--text-muted)' }}>STATUS EVENT LOGS</h4>
                <div style={{ maxHeight: '150px', overflowY: 'auto', background: 'var(--bg-main)', padding: '10px', borderRadius: '6px', fontSize: '11px' }}>
                  {selectedWithdrawal.auditTrail?.length > 0 ? (
                    selectedWithdrawal.auditTrail.map((log: any, i: number) => (
                      <div key={i} style={{ padding: '4px 0', borderBottom: '1px solid rgba(255,255,255,0.04)' }}>
                        <span style={{ color: 'var(--primary)', fontWeight: 600 }}>{log.action}</span> by {log.performedBy} on {new Date(log.timestamp).toLocaleString()}
                        {log.notes && <div style={{ color: 'var(--text-muted)' }}>{log.notes}</div>}
                      </div>
                    ))
                  ) : (
                    <div style={{ color: 'var(--text-muted)' }}>No audit history recorded.</div>
                  )}
                </div>
              </div>
            )}

            {/* Form for Actions */}
            {modalMode !== 'details' && (
              <form onSubmit={handleExecuteAction} style={{ marginTop: '16px' }}>
                {modalMode === 'reject' && (
                  <div className="form-group" style={{ marginBottom: '14px' }}>
                    <label className="label" style={{ color: 'var(--error)', fontWeight: 600 }}>
                      Mandatory Rejection Reason *
                    </label>
                    <textarea 
                      className="input"
                      rows={3}
                      placeholder="Enter detailed reason for rejecting this payout request (e.g., Bank details mismatch, suspicious activity, pilot requested cancellation)..."
                      value={rejectionReason}
                      onChange={e => setRejectionReason(e.target.value)}
                      required
                    />
                  </div>
                )}

                {modalMode === 'complete' && (
                  <div className="form-group" style={{ marginBottom: '14px' }}>
                    <label className="label" style={{ fontWeight: 600, color: 'var(--success)' }}>
                      Bank UTR / Transaction Reference Number *
                    </label>
                    <input 
                      type="text"
                      className="input"
                      placeholder="e.g. 426819283719 or CMS918237192"
                      value={settlementUtr}
                      onChange={e => setSettlementUtr(e.target.value)}
                      required
                    />
                    <small style={{ color: 'var(--text-muted)', fontSize: '11px', marginTop: '4px', display: 'block' }}>
                      Withdrawals are permanently marked Completed ONLY after confirmed bank settlement.
                    </small>
                  </div>
                )}

                <div className="form-group" style={{ marginBottom: '16px' }}>
                  <label className="label">Admin Remarks (Optional)</label>
                  <input 
                    type="text"
                    className="input"
                    placeholder="Internal audit notes..."
                    value={actionRemarks}
                    onChange={e => setActionRemarks(e.target.value)}
                  />
                </div>

                <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px' }}>
                  <button type="button" className="btn btn-secondary" onClick={() => setModalMode(null)}>
                    Cancel
                  </button>
                  <button 
                    type="submit" 
                    className="btn btn-primary"
                    disabled={isProcessingAction}
                    style={{
                      backgroundColor: modalMode === 'reject' ? 'var(--error)' : 'var(--primary)',
                      borderColor: modalMode === 'reject' ? 'var(--error)' : 'var(--primary)'
                    }}
                  >
                    {isProcessingAction ? 'Processing...' : (
                      modalMode === 'approve' ? 'Confirm Approval' :
                      modalMode === 'reject' ? 'Confirm Rejection' :
                      modalMode === 'initiate' ? 'Dispatch Payout' :
                      modalMode === 'complete' ? 'Confirm Settlement' : 'Retry Payout'
                    )}
                  </button>
                </div>
              </form>
            )}
          </div>
        </div>
      )}
    </div>
  );
};

export default PilotWithdrawals;
