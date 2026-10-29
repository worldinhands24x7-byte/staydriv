import React, { useState } from 'react';
import { useDatabase } from '../context/DatabaseContext';
import { useAuth } from '../context/AuthContext';
import { 
  Building2, Landmark, CheckCircle2, AlertTriangle, 
  PlusCircle, RefreshCw, ShieldAlert, ArrowDownRight, FileText, Info 
} from 'lucide-react';

export const CompanyFunds: React.FC = () => {
  const { companyPayouts, founderSummary, recordFounderDistribution, refreshFinancials } = useDatabase();
  const { activeRole } = useAuth();

  const [isModalOpen, setIsModalOpen] = useState(false);
  const [amount, setAmount] = useState('');
  const [beneficiaryName, setBeneficiaryName] = useState('');
  const [destinationBank, setDestinationBank] = useState('');
  const [accountNumber, setAccountNumber] = useState('');
  const [ifsc, setIfsc] = useState('');
  const [reference, setReference] = useState('');
  const [reason, setReason] = useState('');
  const [legalDocRef, setLegalDocRef] = useState('');
  const [period, setPeriod] = useState(new Date().toISOString().slice(0, 7));
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState('');

  const isFounder = activeRole === 'super_admin' || activeRole === 'finance';

  const verifiedCash = founderSummary?.totalActualCashReceived || 0;
  const distributionsTotal = founderSummary?.totalFounderDistributions || 0;
  const availableForDistribution = Math.max(0, verifiedCash - distributionsTotal);

  const handleRecordDistribution = async (e: React.FormEvent) => {
    e.preventDefault();
    const numAmt = parseFloat(amount);
    if (isNaN(numAmt) || numAmt <= 0) {
      setErrorMessage('Please enter a valid payout amount.');
      return;
    }
    if (numAmt > availableForDistribution) {
      setErrorMessage(`Amount exceeds verified available company cash (₹${availableForDistribution.toFixed(2)}). Pilot liabilities and gateway fees cannot be distributed.`);
      return;
    }
    if (!reason.trim()) {
      setErrorMessage('Executive / board resolution justification is required.');
      return;
    }

    setIsSubmitting(true);
    setErrorMessage('');
    try {
      await recordFounderDistribution({
        amount: numAmt,
        beneficiaryName,
        destinationBank,
        accountNumber,
        ifsc,
        reference,
        reason,
        legalDocRef,
        period
      });
      setIsModalOpen(false);
      setAmount('');
      setBeneficiaryName('');
      setDestinationBank('');
      setAccountNumber('');
      setIfsc('');
      setReference('');
      setReason('');
      setLegalDocRef('');
    } catch (err: any) {
      setErrorMessage(err.message || 'Failed to record founder distribution.');
    } finally {
      setIsSubmitting(false);
    }
  };

  if (!isFounder) {
    return (
      <div className="page-container">
        <div className="card" style={{ padding: '40px', textAlign: 'center' }}>
          <ShieldAlert size={48} style={{ color: 'var(--error)', margin: '0 auto 16px' }} />
          <h3>Access Restricted</h3>
          <p style={{ color: 'var(--text-muted)' }}>Only the Founder / Super Admin and Finance Administrator can manage Company Funds & Distributions.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="page-container">
      {/* Top Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '16px' }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <h2>Company Funds & Founder Distributions</h2>
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
              <Landmark size={12} />
              CORPORATE TREASURY RECONCILED
            </span>
          </div>
          <p style={{ color: 'var(--text-muted)', fontSize: '13px', marginTop: '4px' }}>
            Audited platform commission bank receipts, verified bank reconciliation, and authorized founder distributions.
          </p>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          <button 
            className="btn btn-primary btn-sm" 
            onClick={() => setIsModalOpen(true)}
            style={{ display: 'flex', alignItems: 'center', gap: '6px' }}
          >
            <PlusCircle size={14} />
            <span>Record Authorized Distribution</span>
          </button>
          <button className="btn btn-secondary btn-sm" onClick={refreshFinancials}>
            <RefreshCw size={14} />
          </button>
        </div>
      </div>

      {/* Legal & Statutory Isolation Notice */}
      <div style={{ 
        background: 'rgba(59, 130, 246, 0.08)', 
        border: '1px solid rgba(59, 130, 246, 0.25)', 
        borderRadius: '8px', 
        padding: '14px 18px', 
        display: 'flex', 
        alignItems: 'center', 
        gap: '14px',
        fontSize: '13px'
      }}>
        <Building2 size={24} style={{ color: 'var(--primary)', flexShrink: 0 }} />
        <span>
          <strong>Corporate Governance Rule:</strong> Platform commission is never transferred directly into personal accounts without corporate authorization. Distributions must be supported by the company's accounting process, verified available cash balances after deducting pilot liabilities and taxes, and executive approval.
        </span>
      </div>

      {/* Treasury Cards */}
      <div className="kpi-grid" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(260px, 1fr))' }}>
        <div className="kpi-card" style={{ borderLeft: '3px solid var(--primary)' }}>
          <div className="kpi-info">
            <span className="kpi-label">Verified Company Cash Balance</span>
            <span className="kpi-value" style={{ color: 'var(--primary)', fontSize: '22px' }}>
              ₹{verifiedCash.toLocaleString('en-IN', { minimumFractionDigits: 2 })}
            </span>
            <span className="kpi-trend text-muted">Net cash receipts settled in bank</span>
          </div>
          <div className="kpi-icon-wrapper" style={{ color: 'var(--primary)', backgroundColor: 'rgba(59,130,246,0.1)' }}>
            <Landmark size={20} />
          </div>
        </div>

        <div className="kpi-card" style={{ borderLeft: '3px solid var(--success)' }}>
          <div className="kpi-info">
            <span className="kpi-label">Distributable Cash Surplus</span>
            <span className="kpi-value" style={{ color: 'var(--success)', fontSize: '22px' }}>
              ₹{availableForDistribution.toLocaleString('en-IN', { minimumFractionDigits: 2 })}
            </span>
            <span className="kpi-trend trend-up">Available for corporate distribution</span>
          </div>
          <div className="kpi-icon-wrapper" style={{ color: 'var(--success)', backgroundColor: 'var(--success-bg)' }}>
            <CheckCircle2 size={20} />
          </div>
        </div>

        <div className="kpi-card" style={{ borderLeft: '3px solid #a855f7' }}>
          <div className="kpi-info">
            <span className="kpi-label">Cumulative Distributions Paid</span>
            <span className="kpi-value" style={{ color: '#a855f7', fontSize: '22px' }}>
              ₹{distributionsTotal.toLocaleString('en-IN', { minimumFractionDigits: 2 })}
            </span>
            <span className="kpi-trend text-muted">{companyPayouts?.length || 0} distributions recorded</span>
          </div>
          <div className="kpi-icon-wrapper" style={{ color: '#a855f7', backgroundColor: 'rgba(168,85,247,0.1)' }}>
            <ArrowDownRight size={20} />
          </div>
        </div>
      </div>

      {/* Founder Distributions History Table */}
      <div className="card" style={{ padding: '0', overflow: 'hidden' }}>
        <div style={{ padding: '16px 20px', borderBottom: '1px solid var(--border)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <h3 style={{ fontSize: '15px' }}>Audited Founder Distributions & Profit Draws</h3>
          <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Documented records with board resolution references</span>
        </div>

        <div className="table-responsive">
          <table className="data-table" style={{ fontSize: '12px' }}>
            <thead>
              <tr>
                <th>Distribution ID</th>
                <th>Beneficiary Name</th>
                <th>Bank Destination (Masked)</th>
                <th>Payment Reference</th>
                <th>Authorized Amount</th>
                <th>Financial Period</th>
                <th>Authorized By</th>
                <th>Reason & Resolution</th>
                <th>Status</th>
                <th>Date Settled</th>
              </tr>
            </thead>
            <tbody>
              {companyPayouts?.length === 0 ? (
                <tr>
                  <td colSpan={10} style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>
                    No founder distributions have been recorded yet. Available company cash remains intact.
                  </td>
                </tr>
              ) : (
                companyPayouts?.map((p: any, idx: number) => (
                  <tr key={p.payoutId || idx}>
                    <td>
                      <span style={{ fontFamily: 'monospace', fontWeight: 600, color: 'var(--primary)' }}>{p.payoutId}</span>
                    </td>
                    <td>
                      <span style={{ fontWeight: 600 }}>{p.beneficiaryName}</span>
                    </td>
                    <td>
                      <span style={{ fontFamily: 'monospace', fontSize: '11px' }}>{p.accountNumberMasked}</span>
                      <div style={{ fontSize: '10px', color: 'var(--text-muted)' }}>{p.destinationBank} ({p.ifsc})</div>
                    </td>
                    <td>
                      <span style={{ fontFamily: 'monospace', fontSize: '11px' }}>{p.paymentReference || 'N/A'}</span>
                    </td>
                    <td>
                      <span style={{ fontWeight: 700, color: 'var(--success)', fontSize: '13px' }}>₹{p.amount.toFixed(2)}</span>
                    </td>
                    <td>
                      <span className="badge badge-info">{p.financialPeriod}</span>
                    </td>
                    <td>
                      <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>{p.authorizedBy}</span>
                    </td>
                    <td>
                      <div style={{ display: 'flex', flexDirection: 'column' }}>
                        <span style={{ fontSize: '11px' }}>{p.authorizationReason}</span>
                        {p.legalDocumentRef && <span style={{ fontSize: '10px', color: 'var(--text-muted)' }}>Ref: {p.legalDocumentRef}</span>}
                      </div>
                    </td>
                    <td>
                      <span className="badge badge-success">{p.status}</span>
                    </td>
                    <td>
                      <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                        {p.settlementDate ? new Date(p.settlementDate).toLocaleDateString() : 'N/A'}
                      </span>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Record Authorized Distribution Modal */}
      {isModalOpen && (
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
              <h3>Record Authorized Founder Distribution</h3>
              <button className="btn btn-secondary btn-sm" onClick={() => setIsModalOpen(false)}>✕</button>
            </div>

            {errorMessage && (
              <div style={{ background: 'rgba(239, 68, 68, 0.1)', color: 'var(--error)', padding: '10px 14px', borderRadius: '6px', fontSize: '13px', marginTop: '14px' }}>
                ⚠️ {errorMessage}
              </div>
            )}

            <div style={{ marginTop: '16px', background: 'var(--bg-input)', padding: '12px', borderRadius: '8px', fontSize: '13px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: 'var(--text-muted)' }}>Available Distributable Cash:</span>
                <span style={{ fontWeight: 700, color: 'var(--success)', fontSize: '14px' }}>₹{availableForDistribution.toFixed(2)}</span>
              </div>
            </div>

            <form onSubmit={handleRecordDistribution} style={{ marginTop: '16px' }}>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '14px', marginBottom: '14px' }}>
                <div className="form-group">
                  <label className="label">Distribution Amount (₹) *</label>
                  <input 
                    type="number"
                    step="0.01"
                    min="1"
                    max={availableForDistribution}
                    className="input"
                    placeholder="Enter amount..."
                    value={amount}
                    onChange={e => setAmount(e.target.value)}
                    required
                  />
                </div>

                <div className="form-group">
                  <label className="label">Financial Period *</label>
                  <input 
                    type="month"
                    className="input"
                    value={period}
                    onChange={e => setPeriod(e.target.value)}
                    required
                  />
                </div>
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '14px', marginBottom: '14px' }}>
                <div className="form-group">
                  <label className="label">Beneficiary Name *</label>
                  <input 
                    type="text"
                    className="input"
                    placeholder="Founder / Shareholder Name"
                    value={beneficiaryName}
                    onChange={e => setBeneficiaryName(e.target.value)}
                    required
                  />
                </div>

                <div className="form-group">
                  <label className="label">Destination Bank *</label>
                  <input 
                    type="text"
                    className="input"
                    placeholder="e.g. HDFC Bank Ltd"
                    value={destinationBank}
                    onChange={e => setDestinationBank(e.target.value)}
                    required
                  />
                </div>
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '14px', marginBottom: '14px' }}>
                <div className="form-group">
                  <label className="label">Bank Account Number *</label>
                  <input 
                    type="text"
                    className="input"
                    placeholder="Account Number (will be masked)"
                    value={accountNumber}
                    onChange={e => setAccountNumber(e.target.value)}
                    required
                  />
                </div>

                <div className="form-group">
                  <label className="label">Bank IFSC *</label>
                  <input 
                    type="text"
                    className="input"
                    placeholder="e.g. HDFC0001234"
                    value={ifsc}
                    onChange={e => setIfsc(e.target.value.toUpperCase())}
                    required
                  />
                </div>
              </div>

              <div className="form-group" style={{ marginBottom: '14px' }}>
                <label className="label">Bank Transaction Reference / UTR *</label>
                <input 
                  type="text"
                  className="input"
                  placeholder="e.g. CMS9182371982"
                  value={reference}
                  onChange={e => setReference(e.target.value)}
                  required
                />
              </div>

              <div className="form-group" style={{ marginBottom: '14px' }}>
                <label className="label">Board Resolution / Legal Document Reference</label>
                <input 
                  type="text"
                  className="input"
                  placeholder="e.g. BR-2026-Q3-01"
                  value={legalDocRef}
                  onChange={e => setLegalDocRef(e.target.value)}
                />
              </div>

              <div className="form-group" style={{ marginBottom: '20px' }}>
                <label className="label">Executive Authorization Justification *</label>
                <textarea 
                  rows={2}
                  className="input"
                  placeholder="State the corporate dividend or founder distribution authorization..."
                  value={reason}
                  onChange={e => setReason(e.target.value)}
                  required
                />
              </div>

              <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px' }}>
                <button type="button" className="btn btn-secondary" onClick={() => setIsModalOpen(false)}>
                  Cancel
                </button>
                <button 
                  type="submit" 
                  className="btn btn-primary"
                  disabled={isSubmitting}
                >
                  {isSubmitting ? 'Recording Ledger...' : 'Post Authorized Distribution'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};

export default CompanyFunds;
