import React, { useState } from 'react';
import { useDatabase } from '../context/DatabaseContext';
import { 
  CreditCard, ShieldCheck, RefreshCw, AlertCircle, 
  CheckCircle2, XCircle, Search, ExternalLink, Activity 
} from 'lucide-react';

export const GatewaySettlements: React.FC = () => {
  const { gatewaySettlements, refreshFinancials, lastUpdatedTime } = useDatabase();
  const [searchTerm, setSearchTerm] = useState('');

  const payments = gatewaySettlements?.payments || [];
  const filteredPayments = payments.filter((p: any) => {
    return (
      (p.orderId || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (p.paymentId || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (p.bookingId || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (p.customerPhone || '').includes(searchTerm)
    );
  });

  const isLive = gatewaySettlements?.mode === 'LIVE PRODUCTION MODE';

  return (
    <div className="page-container">
      {/* Top Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '16px' }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <h2>Payment Gateway Settlements & Webhook Audit</h2>
            <span style={{ 
              display: 'inline-flex', 
              alignItems: 'center', 
              gap: '6px', 
              padding: '4px 10px', 
              borderRadius: '20px', 
              fontSize: '11px', 
              fontWeight: 700, 
              background: isLive ? 'rgba(16, 185, 129, 0.15)' : 'rgba(245, 158, 11, 0.15)', 
              color: isLive ? 'var(--success)' : 'var(--warning)' 
            }}>
              <Activity size={12} />
              {gatewaySettlements?.mode || 'LIVE PRODUCTION MODE'}
            </span>
          </div>
          <p style={{ color: 'var(--text-muted)', fontSize: '13px', marginTop: '4px' }}>
            Provider settlement reconciliation, webhook verification, and captured payment audit logs.
          </p>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          <button className="btn btn-secondary btn-sm" onClick={refreshFinancials}>
            <RefreshCw size={14} />
            <span>Sync Gateway</span>
          </button>
        </div>
      </div>

      {/* Gateway Configuration & Health KPI Grid */}
      <div className="kpi-grid" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))' }}>
        <div className="kpi-card" style={{ borderLeft: '3px solid var(--primary)' }}>
          <div className="kpi-info">
            <span className="kpi-label">Active Payment Provider</span>
            <span className="kpi-value" style={{ fontSize: '18px', color: 'var(--primary)' }}>
              {gatewaySettlements?.gatewayProvider || 'Razorpay Enterprise'}
            </span>
            <span className="kpi-trend text-muted">Key: {gatewaySettlements?.keyIdMasked || 'rzp_live_••••'}</span>
          </div>
          <div className="kpi-icon-wrapper" style={{ color: 'var(--primary)', backgroundColor: 'rgba(59,130,246,0.1)' }}>
            <CreditCard size={20} />
          </div>
        </div>

        <div className="kpi-card" style={{ borderLeft: '3px solid var(--success)' }}>
          <div className="kpi-info">
            <span className="kpi-label">Total Online Collections</span>
            <span className="kpi-value" style={{ color: 'var(--success)' }}>
              ₹{(gatewaySettlements?.totalCapturedRupees || 0).toLocaleString('en-IN', { minimumFractionDigits: 2 })}
            </span>
            <span className="kpi-trend trend-up">Captured and verified payments</span>
          </div>
          <div className="kpi-icon-wrapper" style={{ color: 'var(--success)', backgroundColor: 'var(--success-bg)' }}>
            <CheckCircle2 size={20} />
          </div>
        </div>

        <div className="kpi-card" style={{ borderLeft: '3px solid #ef4444' }}>
          <div className="kpi-info">
            <span className="kpi-label">Failed / Disputed Collections</span>
            <span className="kpi-value" style={{ color: '#ef4444' }}>
              ₹{(gatewaySettlements?.totalFailedRupees || 0).toLocaleString('en-IN', { minimumFractionDigits: 2 })}
            </span>
            <span className="kpi-trend text-muted">Customer bank declines / drops</span>
          </div>
          <div className="kpi-icon-wrapper" style={{ color: '#ef4444', backgroundColor: 'rgba(239,68,68,0.1)' }}>
            <XCircle size={20} />
          </div>
        </div>
      </div>

      {/* Filter and Table */}
      <div className="card" style={{ padding: '0', overflow: 'hidden' }}>
        <div style={{ padding: '16px 20px', borderBottom: '1px solid var(--border)', display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '10px' }}>
          <div>
            <h3 style={{ fontSize: '15px' }}>Gateway Payment Transactions & Webhook Ledger</h3>
            <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Real records captured from provider webhooks with HMAC signatures</span>
          </div>

          <div style={{ position: 'relative', width: '280px' }}>
            <input 
              type="text"
              placeholder="Search Order ID, Payment ID, Booking ID..."
              value={searchTerm}
              onChange={e => setSearchTerm(e.target.value)}
              className="input"
              style={{ width: '100%', fontSize: '12px' }}
            />
          </div>
        </div>

        <div className="table-responsive">
          <table className="data-table" style={{ fontSize: '12px' }}>
            <thead>
              <tr>
                <th>Order ID & Payment ID</th>
                <th>Linked Booking</th>
                <th>Customer Contact</th>
                <th>Amount (₹)</th>
                <th>Payment Method</th>
                <th>Gateway Status</th>
                <th>Verified Timestamp</th>
              </tr>
            </thead>
            <tbody>
              {filteredPayments.length === 0 ? (
                <tr>
                  <td colSpan={7} style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>
                    No payment gateway transactions recorded.
                  </td>
                </tr>
              ) : (
                filteredPayments.map((p: any, idx: number) => (
                  <tr key={p.orderId || idx}>
                    <td>
                      <div style={{ display: 'flex', flexDirection: 'column' }}>
                        <span style={{ fontFamily: 'monospace', fontWeight: 600, color: 'var(--primary)' }}>{p.orderId}</span>
                        {p.paymentId && <span style={{ fontFamily: 'monospace', fontSize: '10px', color: 'var(--text-muted)' }}>Pay ID: {p.paymentId}</span>}
                      </div>
                    </td>
                    <td>
                      <span style={{ fontFamily: 'monospace', fontSize: '11px' }}>{p.bookingId || 'Wallet Top-up'}</span>
                    </td>
                    <td>
                      <span style={{ fontSize: '11px' }}>{p.customerPhone || 'N/A'}</span>
                    </td>
                    <td>
                      <span style={{ fontWeight: 700, color: 'var(--text-main)', fontSize: '13px' }}>
                        ₹{((p.amount || 0) / 100).toFixed(2)}
                      </span>
                    </td>
                    <td>
                      <span style={{ fontSize: '11px' }}>{p.method || 'UPI / NetBanking'}</span>
                    </td>
                    <td>
                      <span className={`badge ${p.status === 'captured' || p.status === 'verified' ? 'badge-success' : (p.status === 'failed' ? 'badge-error' : 'badge-warning')}`}>
                        {p.status}
                      </span>
                    </td>
                    <td>
                      <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                        {p.createdAt ? new Date(p.createdAt).toLocaleString() : 'N/A'}
                      </span>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};

export default GatewaySettlements;
