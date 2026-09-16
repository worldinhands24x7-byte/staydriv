import React, { useState } from 'react';
import { useDatabase } from '../context/DatabaseContext';
import { useAuth } from '../context/AuthContext';
import { DollarSign, Percent, Wallet, FileSpreadsheet, Check, X, ShieldAlert } from 'lucide-react';

export const Finance: React.FC = () => {
  const { payments, partners, config, processWithdrawal, updateCommissionRate } = useDatabase();
  const { activeRole } = useAuth();
  
  const [newCommissionPercent, setNewCommissionPercent] = useState<number>(config.commissionPercent);
  const [isUpdatingCommission, setIsUpdatingCommission] = useState(false);

  // 1. Calculate General Financial Figures
  const totalRevenue = payments
    .filter(p => p.status === 'completed' && (p.type === 'ride_fare' || p.type === 'delivery_fare'))
    .reduce((sum, p) => sum + p.amount, 0);

  const totalCommissions = payments
    .filter(p => p.status === 'completed' && p.type === 'commission')
    .reduce((sum, p) => sum + p.amount, 0);

  const completedWithdrawals = payments
    .filter(p => p.status === 'completed' && p.type === 'withdrawal')
    .reduce((sum, p) => sum + p.amount, 0);

  // 2. Separate pending withdrawal requests
  const withdrawalRequests = payments.filter(p => p.type === 'withdrawal' && p.status === 'pending');
  const transactionHistory = payments.filter(p => p.type !== 'withdrawal' || p.status === 'completed');

  // Handle Commission Rate Submit
  const handleUpdateCommission = async (e: React.FormEvent) => {
    e.preventDefault();
    if (newCommissionPercent < 1 || newCommissionPercent > 50) {
      alert("Platform commission rate should be between 1% and 50%.");
      return;
    }
    setIsUpdatingCommission(true);
    await updateCommissionRate(newCommissionPercent);
    setIsUpdatingCommission(false);
    alert("Platform commission percentage updated successfully!");
  };

  const getPartnerName = (uid: string) => {
    const found = partners.find(p => p.uid === uid);
    return found ? found.name : 'Unknown Driver';
  };

  const isAuthorized = activeRole === 'super_admin' || activeRole === 'finance';

  if (!isAuthorized) {
    return (
      <div className="page-container">
        <div className="card" style={{ padding: '40px', textAlign: 'center', alignItems: 'center', gap: '16px' }}>
          <ShieldAlert size={48} style={{ color: 'var(--error)' }} />
          <h3>Access Denied</h3>
          <p style={{ color: 'var(--text-muted)' }}>Only the Super Admin or Finance Manager can access Payments & Financial Ledgers.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="page-container">
      <div>
        <h2>Payments & Platform Finance</h2>
        <p style={{ color: 'var(--text-muted)', fontSize: '14px' }}>Review cash flows, manage partner payouts, and configure billing commission rules.</p>
      </div>

      {/* Financial KPI Summary */}
      <div className="kpi-grid" style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(250px, 1fr))' }}>
        <div className="kpi-card">
          <div className="kpi-info">
            <span className="kpi-label">Gross Cargo & Fare Revenue</span>
            <span className="kpi-value">₹{totalRevenue.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
            <span className="kpi-trend text-muted">Aggregated completed bookings</span>
          </div>
          <div className="kpi-icon-wrapper" style={{ color: 'var(--primary)', backgroundColor: 'rgba(59,130,246,0.1)' }}>
            <DollarSign size={20} />
          </div>
        </div>

        <div className="kpi-card">
          <div className="kpi-info">
            <span className="kpi-label">Gross Platform Commission</span>
            <span className="kpi-value">₹{totalCommissions.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
            <span className="kpi-trend trend-up">{(totalRevenue > 0 ? (totalCommissions / totalRevenue) * 100 : 0).toFixed(0)}% average share</span>
          </div>
          <div className="kpi-icon-wrapper" style={{ color: 'var(--success)', backgroundColor: 'var(--success-bg)' }}>
            <Percent size={20} />
          </div>
        </div>

        <div className="kpi-card">
          <div className="kpi-info">
            <span className="kpi-label">Driver Payouts Executed</span>
            <span className="kpi-value">₹{completedWithdrawals.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
            <span className="kpi-trend text-muted">Transferred to partner banks</span>
          </div>
          <div className="kpi-icon-wrapper" style={{ color: 'var(--warning)', backgroundColor: 'var(--warning-bg)' }}>
            <Wallet size={20} />
          </div>
        </div>
      </div>

      {/* Two columns for controls */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1.5fr', gap: '24px' }}>
        
        {/* Left Side: Commission Adjustments & Withdrawal Queue */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
          
          {/* Commission Config Form */}
          <div className="card">
            <div className="card-title">Adjust Commission Percentage</div>
            <form onSubmit={handleUpdateCommission} style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
              <div className="form-group">
                <label>Platform Commission Percentage (%)</label>
                <div style={{ display: 'flex', gap: '12px', alignItems: 'center' }}>
                  <input 
                    type="range" 
                    min="1" 
                    max="50" 
                    value={newCommissionPercent} 
                    onChange={(e) => setNewCommissionPercent(parseInt(e.target.value))}
                    style={{ flex: 1, padding: 0 }}
                  />
                  <span style={{ fontSize: '18px', fontWeight: 800, minWidth: '45px', textAlign: 'right' }}>
                    {newCommissionPercent}%
                  </span>
                </div>
              </div>
              <button className="btn btn-primary" type="submit" disabled={isUpdatingCommission}>
                {isUpdatingCommission ? 'Saving settings...' : 'Update Commission Rule'}
              </button>
            </form>
          </div>

          {/* Withdrawal Requests Queue */}
          <div className="card" style={{ flex: 1 }}>
            <div className="card-title">Pending Withdrawal Requests ({withdrawalRequests.length})</div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '12px', maxHeight: '300px', overflowY: 'auto' }}>
              {withdrawalRequests.length > 0 ? (
                withdrawalRequests.map(req => (
                  <div 
                    key={req.transactionId}
                    style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '12px', border: '1px solid var(--border)', borderRadius: '12px' }}
                  >
                    <div>
                      <div style={{ fontWeight: 600, fontSize: '13px' }}>{getPartnerName(req.userId)}</div>
                      <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>UID: {req.userId} • via {req.paymentMethod}</div>
                    </div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                      <span style={{ fontWeight: 700, color: 'var(--primary)' }}>₹{req.amount.toFixed(0)}</span>
                      <div style={{ display: 'flex', gap: '4px' }}>
                        <button 
                          className="btn btn-success btn-sm btn-icon"
                          onClick={() => processWithdrawal(req.transactionId, true)}
                          title="Approve Bank Payout"
                        >
                          <Check size={14} />
                        </button>
                        <button 
                          className="btn btn-danger btn-sm btn-icon"
                          onClick={() => processWithdrawal(req.transactionId, false)}
                          title="Reject Payout Request"
                        >
                          <X size={14} />
                        </button>
                      </div>
                    </div>
                  </div>
                ))
              ) : (
                <div style={{ textAlign: 'center', color: 'var(--text-muted)', fontSize: '12px', padding: '24px' }}>
                  No pending partner bank withdrawal requests.
                </div>
              )}
            </div>
          </div>
        </div>

        {/* Right Side: Completed Transactions Log */}
        <div className="card">
          <div className="card-title">Completed Financial Transaction Log</div>
          <div className="table-wrapper" style={{ maxHeight: '420px', overflowY: 'auto' }}>
            <table>
              <thead>
                <tr>
                  <th>Transaction ID</th>
                  <th>Amount</th>
                  <th>Method</th>
                  <th>Type</th>
                  <th>User Role</th>
                  <th>Billing Date</th>
                </tr>
              </thead>
              <tbody>
                {transactionHistory.length > 0 ? (
                  transactionHistory.map(txn => (
                    <tr key={txn.transactionId}>
                      <td style={{ fontWeight: 600, fontFamily: 'monospace' }}>{txn.transactionId}</td>
                      <td style={{ fontWeight: 600 }}>₹{txn.amount.toFixed(2)}</td>
                      <td style={{ textTransform: 'uppercase', fontSize: '12px' }}>{txn.paymentMethod}</td>
                      <td>
                        <span className={`badge ${txn.type === 'commission' ? 'badge-completed' : txn.type === 'withdrawal' ? 'badge-suspended' : 'badge-requested'}`}>
                          {txn.type.replace('_', ' ')}
                        </span>
                      </td>
                      <td style={{ textTransform: 'capitalize', fontSize: '12px' }}>{txn.userRole}</td>
                      <td style={{ fontSize: '12px' }}>{new Date(txn.createdAt).toLocaleDateString('en-IN')}</td>
                    </tr>
                  ))
                ) : (
                  <tr>
                    <td colSpan={6} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: '24px' }}>
                      No transactions recorded.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  );
};
export default Finance;
