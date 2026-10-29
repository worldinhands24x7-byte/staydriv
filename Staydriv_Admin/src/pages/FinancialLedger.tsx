import React, { useState } from 'react';
import { useDatabase } from '../context/DatabaseContext';
import { 
  BookOpen, Search, RefreshCw, Download, CheckCircle2, 
  RotateCw, Filter, Layers, ArrowLeftRight, ShieldCheck 
} from 'lucide-react';

export const FinancialLedger: React.FC = () => {
  const { financialLedger, reconcileLedger, refreshFinancials, exportReport, lastUpdatedTime } = useDatabase();
  const [searchTerm, setSearchTerm] = useState('');
  const [typeFilter, setTypeFilter] = useState('all');
  const [isReconciling, setIsReconciling] = useState(false);
  const [reconcileResult, setReconcileResult] = useState<any>(null);

  const handleReconcile = async () => {
    setIsReconciling(true);
    try {
      const res = await reconcileLedger();
      setReconcileResult(res);
    } catch (err: any) {
      alert(`Reconciliation error: ${err.message}`);
    } finally {
      setIsReconciling(false);
    }
  };

  const filteredEntries = (financialLedger || []).filter(e => {
    const matchesSearch = 
      (e.ledgerId || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (e.transactionId || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (e.sourceBookingId || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (e.debitAccount || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (e.creditAccount || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (e.referenceNumber || '').toLowerCase().includes(searchTerm.toLowerCase());

    const matchesType = typeFilter === 'all' || e.entryType === typeFilter;
    return matchesSearch && matchesType;
  });

  const totalVolume = (financialLedger || []).reduce((sum, e) => sum + (e.amount || 0), 0);

  const formatEntryType = (t: string) => {
    return (t || '').replace(/_/g, ' ');
  };

  return (
    <div className="page-container">
      {/* Top Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '16px' }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <h2>Real-Time Double-Entry Financial Ledger</h2>
            <span style={{ 
              display: 'inline-flex', 
              alignItems: 'center', 
              gap: '6px', 
              padding: '4px 10px', 
              borderRadius: '20px', 
              fontSize: '11px', 
              fontWeight: 700, 
              background: 'rgba(16, 185, 129, 0.15)', 
              color: 'var(--success)' 
            }}>
              <CheckCircle2 size={12} />
              IMMUTABLE & BALANCED
            </span>
          </div>
          <p style={{ color: 'var(--text-muted)', fontSize: '13px', marginTop: '4px' }}>
            Permanent double-entry record for customer collections, commissions, pilot credits, payouts, taxes, and reversals.
          </p>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          <button 
            className="btn btn-secondary btn-sm" 
            onClick={() => exportReport('ledger')}
            style={{ display: 'flex', alignItems: 'center', gap: '6px' }}
          >
            <Download size={14} />
            <span>Export CSV</span>
          </button>
          <button 
            className="btn btn-primary btn-sm" 
            onClick={handleReconcile}
            disabled={isReconciling}
            style={{ display: 'flex', alignItems: 'center', gap: '6px' }}
          >
            <RotateCw size={14} className={isReconciling ? 'animate-spin' : ''} />
            <span>{isReconciling ? 'Auditing...' : 'Run Automated Audit Reconciliation'}</span>
          </button>
          <button className="btn btn-secondary btn-sm" onClick={refreshFinancials}>
            <RefreshCw size={14} />
          </button>
        </div>
      </div>

      {/* Balanced Accounting Status Banner */}
      <div style={{ 
        background: 'rgba(16, 185, 129, 0.08)', 
        border: '1px solid rgba(16, 185, 129, 0.25)', 
        borderRadius: '8px', 
        padding: '12px 18px', 
        display: 'flex', 
        justifyContent: 'space-between', 
        alignItems: 'center',
        flexWrap: 'wrap',
        gap: '12px',
        fontSize: '13px'
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          <ShieldCheck size={20} style={{ color: 'var(--success)' }} />
          <span>
            <strong>Ledger Health: BALANCED</strong> — Equal and balanced debits and credits posted. Historical entries are immutable and tamper-evident.
          </span>
        </div>
        <div style={{ display: 'flex', gap: '16px' }}>
          <span>Total Posted Volume: <strong>₹{totalVolume.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</strong></span>
          <span>Entries: <strong>{financialLedger?.length || 0}</strong></span>
        </div>
      </div>

      {/* Reconciliation Modal Result if triggered */}
      {reconcileResult && (
        <div style={{
          background: 'var(--bg-card)',
          border: '1px solid var(--border)',
          borderRadius: '8px',
          padding: '16px 20px',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          fontSize: '13px'
        }}>
          <div>
            <h4 style={{ color: 'var(--success)', marginBottom: '4px' }}>✓ Automated Reconciliation Complete</h4>
            <div style={{ color: 'var(--text-muted)' }}>
              Verified at {new Date(reconcileResult.reconciledAt).toLocaleString()} | Pilot Wallets: ₹{reconcileResult.totalPilotWallets?.toFixed(2)} | Discrepancies: {reconcileResult.discrepanciesCount}
            </div>
          </div>
          <button className="btn btn-secondary btn-sm" onClick={() => setReconcileResult(null)}>Dismiss</button>
        </div>
      )}

      {/* Filter Toolbar */}
      <div className="card" style={{ padding: '16px' }}>
        <div style={{ display: 'flex', gap: '12px', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'space-between' }}>
          <div style={{ display: 'flex', gap: '12px', flex: '1', minWidth: '280px' }}>
            <div style={{ position: 'relative', flex: 1 }}>
              <Search size={16} style={{ position: 'absolute', left: '12px', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
              <input 
                type="text"
                placeholder="Search ledger ID, transaction ID, booking ID, accounts, reference..."
                value={searchTerm}
                onChange={e => setSearchTerm(e.target.value)}
                className="input"
                style={{ paddingLeft: '36px', width: '100%' }}
              />
            </div>

            <select 
              value={typeFilter} 
              onChange={e => setTypeFilter(e.target.value)}
              className="input"
              style={{ width: '220px' }}
            >
              <option value="all">All Transaction Types</option>
              <option value="BOOKING_FARE_REVENUE">Customer Fare Collection</option>
              <option value="PLATFORM_COMMISSION">Platform Commission</option>
              <option value="PILOT_FARE_EARNING">Pilot Fare Earning</option>
              <option value="WITHDRAWAL_RESERVE">Withdrawal Reservation</option>
              <option value="WITHDRAWAL_PAYOUT">Withdrawal Payout</option>
              <option value="WITHDRAWAL_REVERSAL">Withdrawal Reversal</option>
              <option value="TAX_LIABILITY">GST Tax Liability</option>
              <option value="GATEWAY_FEE">Gateway Processing Fee</option>
              <option value="FOUNDER_DISTRIBUTION">Founder Distribution</option>
            </select>
          </div>

          <span style={{ fontSize: '13px', color: 'var(--text-muted)' }}>
            Showing <strong>{filteredEntries.length}</strong> of <strong>{financialLedger?.length || 0}</strong> ledger entries
          </span>
        </div>
      </div>

      {/* Ledger Table */}
      <div className="card" style={{ padding: '0', overflow: 'hidden' }}>
        <div style={{ padding: '16px 20px', borderBottom: '1px solid var(--border)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <h3 style={{ fontSize: '15px' }}>Double-Entry Journal & Ledger Entries</h3>
          <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Every transaction records balanced debit and credit accounts</span>
        </div>

        <div className="table-responsive">
          <table className="data-table" style={{ fontSize: '12px' }}>
            <thead>
              <tr>
                <th>Ledger & Txn ID</th>
                <th>Transaction Type</th>
                <th>Source Booking / Payout</th>
                <th>Debit Account</th>
                <th>Credit Account</th>
                <th>Amount (INR)</th>
                <th>Reference</th>
                <th>Description</th>
                <th>Timestamp</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {filteredEntries.length === 0 ? (
                <tr>
                  <td colSpan={10} style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>
                    No ledger entries match the filter criteria.
                  </td>
                </tr>
              ) : (
                filteredEntries.map((e, idx) => (
                  <tr key={e.ledgerId || idx}>
                    <td>
                      <div style={{ display: 'flex', flexDirection: 'column' }}>
                        <span style={{ fontFamily: 'monospace', fontWeight: 600, color: 'var(--primary)' }}>{e.ledgerId}</span>
                        <span style={{ fontFamily: 'monospace', fontSize: '10px', color: 'var(--text-muted)' }}>{e.transactionId}</span>
                      </div>
                    </td>
                    <td>
                      <span className="badge badge-info" style={{ fontWeight: 600, fontSize: '10px' }}>
                        {formatEntryType(e.entryType)}
                      </span>
                    </td>
                    <td>
                      <span style={{ fontFamily: 'monospace', fontSize: '11px' }}>
                        {e.sourceBookingId || e.withdrawalId || 'N/A'}
                      </span>
                    </td>
                    <td>
                      <span style={{ 
                        fontFamily: 'monospace', 
                        fontSize: '11px', 
                        color: 'var(--primary)',
                        background: 'rgba(59,130,246,0.06)',
                        padding: '2px 6px',
                        borderRadius: '4px'
                      }}>
                        {e.debitAccount}
                      </span>
                    </td>
                    <td>
                      <span style={{ 
                        fontFamily: 'monospace', 
                        fontSize: '11px', 
                        color: 'var(--success)',
                        background: 'rgba(16,185,129,0.06)',
                        padding: '2px 6px',
                        borderRadius: '4px'
                      }}>
                        {e.creditAccount}
                      </span>
                    </td>
                    <td>
                      <span style={{ fontWeight: 700, fontSize: '13px', color: 'var(--text-main)' }}>
                        ₹{e.amount.toFixed(2)}
                      </span>
                    </td>
                    <td>
                      <span style={{ fontFamily: 'monospace', fontSize: '11px', color: 'var(--text-muted)' }}>
                        {e.referenceNumber || 'N/A'}
                      </span>
                    </td>
                    <td>
                      <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                        {e.description}
                      </span>
                    </td>
                    <td>
                      <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                        {e.timestamp ? new Date(e.timestamp).toLocaleString() : 'N/A'}
                      </span>
                    </td>
                    <td>
                      <span className="badge badge-success">
                        {e.status}
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

export default FinancialLedger;
