import React, { useState } from 'react';
import { useDatabase } from '../context/DatabaseContext';
import { useAuth } from '../context/AuthContext';
import { 
  Percent, DollarSign, ArrowUpRight, ShieldCheck, Download, 
  RefreshCw, Sliders, History, Calendar, CheckCircle2, AlertCircle, Info 
} from 'lucide-react';

export const FounderCommission: React.FC = () => {
  const { 
    commissionConfig, commissionBookings, founderSummary, 
    updateCommissionConfig, refreshFinancials, exportReport, lastUpdatedTime 
  } = useDatabase();
  const { activeRole } = useAuth();

  const [activeTab, setActiveTab] = useState<'dashboard' | 'bookings' | 'config'>('dashboard');
  const [selectedPeriod, setSelectedPeriod] = useState<'today' | 'week' | 'month' | 'quarter' | 'year' | 'all'>('all');
  const [searchTerm, setSearchTerm] = useState('');

  // Commission Config Form State
  const [defaultRate, setDefaultRate] = useState<number>(commissionConfig?.defaultRate || 20.0);
  const [bikeRate, setBikeRate] = useState<number>(commissionConfig?.ratesByVehicle?.Bike || 20.0);
  const [autoRate, setAutoRate] = useState<number>(commissionConfig?.ratesByVehicle?.Auto || 15.0);
  const [carRate, setCarRate] = useState<number>(commissionConfig?.ratesByVehicle?.Car || 20.0);
  const [truckRate, setTruckRate] = useState<number>(commissionConfig?.ratesByVehicle?.['6 Ton Truck'] || 10.0);
  const [deliveryRate, setDeliveryRate] = useState<number>(commissionConfig?.ratesByService?.delivery || 15.0);
  const [taxGstRate, setTaxGstRate] = useState<number>(commissionConfig?.taxRateGst || 5.0);
  const [gatewayFeeRate, setGatewayFeeRate] = useState<number>(commissionConfig?.gatewayFeeRate || 2.0);
  const [configNotes, setConfigNotes] = useState('');
  const [isSavingConfig, setIsSavingConfig] = useState(false);
  const [configMessage, setConfigMessage] = useState('');

  const isFounderOrFinance = activeRole === 'super_admin' || activeRole === 'finance';

  const handleSaveCommissionConfig = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSavingConfig(true);
    setConfigMessage('');
    try {
      await updateCommissionConfig({
        defaultRate,
        ratesByVehicle: {
          Bike: bikeRate,
          Auto: autoRate,
          Car: carRate,
          'Mini Truck': 12.0,
          '6 Ton Truck': truckRate
        },
        ratesByService: {
          ride: defaultRate,
          delivery: deliveryRate,
          parcel: deliveryRate
        },
        taxRateGst: taxGstRate,
        gatewayFeeRate,
        notes: configNotes || 'Updated platform commission rates'
      });
      setConfigMessage('Commission schedule updated successfully. Changes apply prospectively to new bookings.');
    } catch (err: any) {
      setConfigMessage(`Error: ${err.message}`);
    } finally {
      setIsSavingConfig(false);
    }
  };

  // Filter booking records
  const filteredBookings = (commissionBookings || []).filter(b => {
    return (
      (b.bookingId || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (b.pilotName || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (b.customerName || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (b.vehicle || '').toLowerCase().includes(searchTerm.toLowerCase())
    );
  });

  const totals = founderSummary || {
    totalCustomerCollections: 0,
    grossBookingValue: 0,
    completedBookingValue: 0,
    grossCommissionEarned: 0,
    commissionCollectedSettled: 0,
    commissionPendingSettlement: 0,
    pilotEarningsPayable: 0,
    pilotEarningsAlreadyPaid: 0,
    pilotWalletLiabilities: 0,
    outstandingWithdrawalLiabilities: 0,
    refundsAndChargebacks: 0,
    paymentGatewayFees: 0,
    statutoryTaxGst: 0,
    authorizedOperatingExpenses: 0,
    netOperatingIncome: 0,
    unreconciledPaymentTransactions: 0,
    unsettledGatewayTransactions: 0,
    totalActualCashReceived: 0,
    totalFounderDistributions: 0
  };

  return (
    <div className="page-container">
      {/* Top Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '16px' }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <h2>Founder Revenue & Platform Commission</h2>
            <span style={{ 
              display: 'inline-flex', 
              alignItems: 'center', 
              gap: '6px', 
              padding: '4px 10px', 
              borderRadius: '20px', 
              fontSize: '11px', 
              fontWeight: 700, 
              background: 'rgba(251, 191, 36, 0.15)', 
              color: 'var(--safety-yellow)' 
            }}>
              <ShieldCheck size={12} />
              PROSPECTIVE AUDITED RATES
            </span>
          </div>
          <p style={{ color: 'var(--text-muted)', fontSize: '13px', marginTop: '4px' }}>
            Platform profit tracking, booking-level fee reconciliation, and company treasury cash isolation.
          </p>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          <div style={{ display: 'flex', background: 'var(--bg-input)', padding: '2px', borderRadius: '6px' }}>
            <button 
              className={`btn btn-sm ${activeTab === 'dashboard' ? 'btn-primary' : 'btn-secondary'}`}
              onClick={() => setActiveTab('dashboard')}
              style={{ border: 'none' }}
            >
              Financial Dashboard
            </button>
            <button 
              className={`btn btn-sm ${activeTab === 'bookings' ? 'btn-primary' : 'btn-secondary'}`}
              onClick={() => setActiveTab('bookings')}
              style={{ border: 'none' }}
            >
              Booking Commissions
            </button>
            {isFounderOrFinance && (
              <button 
                className={`btn btn-sm ${activeTab === 'config' ? 'btn-primary' : 'btn-secondary'}`}
                onClick={() => setActiveTab('config')}
                style={{ border: 'none' }}
              >
                Rate Configuration
              </button>
            )}
          </div>

          <button 
            className="btn btn-secondary btn-sm" 
            onClick={() => exportReport('commission')}
            style={{ display: 'flex', alignItems: 'center', gap: '6px' }}
          >
            <Download size={14} />
            <span>Export CSV</span>
          </button>
          <button className="btn btn-secondary btn-sm" onClick={refreshFinancials}>
            <RefreshCw size={14} />
          </button>
        </div>
      </div>

      {/* Cautionary Banner: Cash Isolation Principle */}
      <div style={{ 
        background: 'rgba(245, 158, 11, 0.08)', 
        border: '1px solid rgba(245, 158, 11, 0.25)', 
        borderRadius: '8px', 
        padding: '12px 16px', 
        display: 'flex', 
        alignItems: 'center', 
        gap: '12px',
        fontSize: '13px'
      }}>
        <Info size={20} style={{ color: 'var(--warning)', flexShrink: 0 }} />
        <span>
          <strong>Treasury Accounting Isolation:</strong> Gross platform commission is NOT treated as instantly distributable founder profit. Funds belonging to pilot wallet balances, payment gateway processing fees, and statutory GST liabilities are legally isolated in the balanced ledger.
        </span>
      </div>

      {/* TAB 1: FOUNDER FINANCIAL DASHBOARD (Section 4.C - 18 Totals) */}
      {activeTab === 'dashboard' && (
        <>
          {/* Period Selector */}
          <div className="card" style={{ padding: '12px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '10px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <Calendar size={16} style={{ color: 'var(--text-muted)' }} />
              <span style={{ fontSize: '13px', fontWeight: 600 }}>Reporting Period:</span>
            </div>
            <div style={{ display: 'flex', gap: '6px' }}>
              {(['today', 'week', 'month', 'quarter', 'year', 'all'] as const).map(p => (
                <button
                  key={p}
                  className={`btn btn-sm ${selectedPeriod === p ? 'btn-primary' : 'btn-secondary'}`}
                  onClick={() => setSelectedPeriod(p)}
                  style={{ textTransform: 'capitalize', fontSize: '11px', padding: '4px 10px' }}
                >
                  {p === 'all' ? 'All Time' : p}
                </button>
              ))}
            </div>
          </div>

          {/* 18 Financial KPI Grid */}
          <div className="kpi-grid" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))' }}>
            {/* 1. Total Customer Collections */}
            <div className="kpi-card" style={{ borderLeft: '3px solid var(--primary)' }}>
              <div className="kpi-info">
                <span className="kpi-label">1. Total Customer Collections</span>
                <span className="kpi-value" style={{ color: 'var(--primary)' }}>₹{totals.totalCustomerCollections.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
                <span className="kpi-trend text-muted">Completed customer fares</span>
              </div>
            </div>

            {/* 2. Gross Booking Value */}
            <div className="kpi-card">
              <div className="kpi-info">
                <span className="kpi-label">2. Gross Booking Value (GBV)</span>
                <span className="kpi-value">₹{totals.grossBookingValue.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
                <span className="kpi-trend text-muted">All dispatched demand</span>
              </div>
            </div>

            {/* 3. Completed Booking Value */}
            <div className="kpi-card">
              <div className="kpi-info">
                <span className="kpi-label">3. Completed Booking Value</span>
                <span className="kpi-value">₹{totals.completedBookingValue.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
                <span className="kpi-trend trend-up">Fulfilled passenger & parcel trips</span>
              </div>
            </div>

            {/* 4. Gross Platform Commission Earned */}
            <div className="kpi-card" style={{ borderLeft: '3px solid var(--safety-yellow)' }}>
              <div className="kpi-info">
                <span className="kpi-label">4. Gross Commission Earned</span>
                <span className="kpi-value" style={{ color: 'var(--safety-yellow)' }}>₹{totals.grossCommissionEarned.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
                <span className="kpi-trend text-muted">Total platform commission</span>
              </div>
            </div>

            {/* 5. Commission Collected & Settled */}
            <div className="kpi-card" style={{ borderLeft: '3px solid var(--success)' }}>
              <div className="kpi-info">
                <span className="kpi-label">5. Commission Collected & Settled</span>
                <span className="kpi-value" style={{ color: 'var(--success)' }}>₹{totals.commissionCollectedSettled.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
                <span className="kpi-trend trend-up">Settled to company bank account</span>
              </div>
            </div>

            {/* 6. Commission Pending Settlement */}
            <div className="kpi-card" style={{ borderLeft: '3px solid var(--warning)' }}>
              <div className="kpi-info">
                <span className="kpi-label">6. Commission Pending Settlement</span>
                <span className="kpi-value" style={{ color: 'var(--warning)' }}>₹{totals.commissionPendingSettlement.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
                <span className="kpi-trend text-muted">Cash collected by pilots / PG batch</span>
              </div>
            </div>

            {/* 7. Pilot Earnings Payable */}
            <div className="kpi-card">
              <div className="kpi-info">
                <span className="kpi-label">7. Pilot Earnings Payable</span>
                <span className="kpi-value">₹{totals.pilotEarningsPayable.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
                <span className="kpi-trend text-muted">Earned pilot trip share</span>
              </div>
            </div>

            {/* 8. Pilot Earnings Paid */}
            <div className="kpi-card">
              <div className="kpi-info">
                <span className="kpi-label">8. Pilot Earnings Already Paid</span>
                <span className="kpi-value">₹{totals.pilotEarningsAlreadyPaid.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
                <span className="kpi-trend text-muted">Dispatched bank payouts</span>
              </div>
            </div>

            {/* 9. Pilot Wallet Liabilities */}
            <div className="kpi-card" style={{ borderLeft: '3px solid #ef4444' }}>
              <div className="kpi-info">
                <span className="kpi-label">9. Pilot Wallet Liabilities</span>
                <span className="kpi-value" style={{ color: '#ef4444' }}>₹{totals.pilotWalletLiabilities.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
                <span className="kpi-trend text-muted">Active fleet wallet liability</span>
              </div>
            </div>

            {/* 10. Outstanding Withdrawal Liabilities */}
            <div className="kpi-card">
              <div className="kpi-info">
                <span className="kpi-label">10. Outstanding Withdrawal Liability</span>
                <span className="kpi-value">₹{totals.outstandingWithdrawalLiabilities.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
                <span className="kpi-trend text-muted">Pending / under review payouts</span>
              </div>
            </div>

            {/* 11. Refunds & Chargebacks */}
            <div className="kpi-card">
              <div className="kpi-info">
                <span className="kpi-label">11. Refunds & Chargebacks</span>
                <span className="kpi-value">₹{totals.refundsAndChargebacks.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
                <span className="kpi-trend text-muted">Customer dispute returns</span>
              </div>
            </div>

            {/* 12. Payment Gateway Fees */}
            <div className="kpi-card">
              <div className="kpi-info">
                <span className="kpi-label">12. Payment Gateway Fees</span>
                <span className="kpi-value">₹{totals.paymentGatewayFees.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
                <span className="kpi-trend text-muted">Razorpay processing charges</span>
              </div>
            </div>

            {/* 13. Applicable Taxes (GST) */}
            <div className="kpi-card">
              <div className="kpi-info">
                <span className="kpi-label">13. Statutory Tax Liabilities (GST)</span>
                <span className="kpi-value">₹{totals.statutoryTaxGst.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
                <span className="kpi-trend text-muted">5% GST statutory provision</span>
              </div>
            </div>

            {/* 14. Operating Expenses */}
            <div className="kpi-card">
              <div className="kpi-info">
                <span className="kpi-label">14. Authorized Operating Expenses</span>
                <span className="kpi-value">₹{totals.authorizedOperatingExpenses.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
                <span className="kpi-trend text-muted">Infrastructure & operations</span>
              </div>
            </div>

            {/* 15. Net Operating Income */}
            <div className="kpi-card" style={{ borderLeft: '3px solid #10b981' }}>
              <div className="kpi-info">
                <span className="kpi-label">15. Net Operating Income</span>
                <span className="kpi-value" style={{ color: '#10b981' }}>₹{totals.netOperatingIncome.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
                <span className="kpi-trend trend-up">Net platform surplus</span>
              </div>
            </div>

            {/* 16. Unreconciled Transactions */}
            <div className="kpi-card">
              <div className="kpi-info">
                <span className="kpi-label">16. Unreconciled Payment Txns</span>
                <span className="kpi-value">₹{totals.unreconciledPaymentTransactions.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
                <span className="kpi-trend text-muted">Gateway audit exceptions</span>
              </div>
            </div>

            {/* 17. Unsettled Gateway Txns */}
            <div className="kpi-card">
              <div className="kpi-info">
                <span className="kpi-label">17. Unsettled Gateway Txns</span>
                <span className="kpi-value">₹{totals.unsettledGatewayTransactions.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
                <span className="kpi-trend text-muted">Settlement in transit</span>
              </div>
            </div>

            {/* 18. Actual Cash Received by Company */}
            <div className="kpi-card" style={{ borderLeft: '3px solid var(--primary)', backgroundColor: 'rgba(59,130,246,0.04)' }}>
              <div className="kpi-info">
                <span className="kpi-label">18. Total Verified Cash In Bank</span>
                <span className="kpi-value" style={{ color: 'var(--primary)', fontSize: '22px' }}>₹{totals.totalActualCashReceived.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
                <span className="kpi-trend trend-up">Net company treasury cash</span>
              </div>
            </div>
          </div>
        </>
      )}

      {/* TAB 2: BOOKING-LEVEL COMMISSION EXPLORER (Section 4.B) */}
      {activeTab === 'bookings' && (
        <div className="card" style={{ padding: '0', overflow: 'hidden' }}>
          <div style={{ padding: '16px 20px', borderBottom: '1px solid var(--border)', display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '10px' }}>
            <div>
              <h3 style={{ fontSize: '15px' }}>Booking-Level Commission Ledger</h3>
              <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Traceable platform split for each completed ride or goods delivery</span>
            </div>

            <div style={{ position: 'relative', width: '280px' }}>
              <input 
                type="text"
                placeholder="Search booking ID, customer, pilot..."
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
                  <th>Booking ID</th>
                  <th>Customer & Pilot</th>
                  <th>Type & Vehicle</th>
                  <th>Fare Amount</th>
                  <th>Comm %</th>
                  <th>Platform Cut</th>
                  <th>Pilot Earnings</th>
                  <th>Gateway Fee</th>
                  <th>GST Tax</th>
                  <th>Settlement Status</th>
                  <th>Completed Date</th>
                </tr>
              </thead>
              <tbody>
                {filteredBookings.length === 0 ? (
                  <tr>
                    <td colSpan={11} style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>
                      No completed bookings found.
                    </td>
                  </tr>
                ) : (
                  filteredBookings.map((b, idx) => (
                    <tr key={b.bookingId || idx}>
                      <td>
                        <span style={{ fontFamily: 'monospace', fontWeight: 600, color: 'var(--primary)' }}>{b.bookingId}</span>
                      </td>
                      <td>
                        <div style={{ display: 'flex', flexDirection: 'column' }}>
                          <span style={{ fontWeight: 600 }}>Rider: {b.customerName}</span>
                          <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Pilot: {b.pilotName}</span>
                        </div>
                      </td>
                      <td>
                        <span style={{ fontSize: '11px' }}>{b.vehicle} ({b.bookingType})</span>
                      </td>
                      <td>
                        <span style={{ fontWeight: 700, color: 'var(--text-main)' }}>₹{b.finalEligibleFare.toFixed(2)}</span>
                      </td>
                      <td>
                        <span className="badge badge-warning" style={{ fontWeight: 700 }}>{b.commissionPercentage}%</span>
                      </td>
                      <td>
                        <span style={{ fontWeight: 700, color: 'var(--safety-yellow)' }}>₹{b.platformCommissionAmount.toFixed(2)}</span>
                      </td>
                      <td>
                        <span style={{ fontWeight: 600, color: 'var(--success)' }}>₹{b.pilotEarnings.toFixed(2)}</span>
                      </td>
                      <td>
                        <span style={{ color: 'var(--text-muted)' }}>₹{b.paymentGatewayFee.toFixed(2)}</span>
                      </td>
                      <td>
                        <span style={{ color: 'var(--text-muted)' }}>₹{b.applicableTaxAmount.toFixed(2)}</span>
                      </td>
                      <td>
                        <span className={`badge ${b.settlementStatus === 'SETTLED' ? 'badge-success' : 'badge-warning'}`}>
                          {b.settlementStatus}
                        </span>
                      </td>
                      <td>
                        <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                          {b.completionDate ? new Date(b.completionDate).toLocaleString() : 'N/A'}
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

      {/* TAB 3: COMMISSION CONFIGURATION (Section 4.A) */}
      {activeTab === 'config' && (
        <div className="card" style={{ maxWidth: '780px' }}>
          <div style={{ borderBottom: '1px solid var(--border)', paddingBottom: '14px', marginBottom: '20px' }}>
            <h3>Commission & Tax Rule Engine</h3>
            <p style={{ color: 'var(--text-muted)', fontSize: '13px', marginTop: '4px' }}>
              Database-stored commission schedule. Versioned and applied prospectively. Historical booking commission rates remain permanently preserved.
            </p>
          </div>

          {configMessage && (
            <div style={{ 
              background: configMessage.startsWith('Error') ? 'rgba(239, 68, 68, 0.1)' : 'rgba(16, 185, 129, 0.1)',
              color: configMessage.startsWith('Error') ? 'var(--error)' : 'var(--success)',
              padding: '12px 16px',
              borderRadius: '6px',
              fontSize: '13px',
              marginBottom: '20px'
            }}>
              {configMessage}
            </div>
          )}

          <form onSubmit={handleSaveCommissionConfig}>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: '16px', marginBottom: '20px' }}>
              <div className="form-group">
                <label className="label">Default Commission Rate (%)</label>
                <input 
                  type="number" 
                  step="0.1" 
                  min="1" 
                  max="50" 
                  className="input" 
                  value={defaultRate} 
                  onChange={e => setDefaultRate(parseFloat(e.target.value))} 
                  required 
                />
              </div>

              <div className="form-group">
                <label className="label">Bike Taxi Rate (%)</label>
                <input 
                  type="number" 
                  step="0.1" 
                  min="1" 
                  max="50" 
                  className="input" 
                  value={bikeRate} 
                  onChange={e => setBikeRate(parseFloat(e.target.value))} 
                  required 
                />
              </div>

              <div className="form-group">
                <label className="label">Auto Rickshaw Rate (%)</label>
                <input 
                  type="number" 
                  step="0.1" 
                  min="1" 
                  max="50" 
                  className="input" 
                  value={autoRate} 
                  onChange={e => setAutoRate(parseFloat(e.target.value))} 
                  required 
                />
              </div>

              <div className="form-group">
                <label className="label">Cab / Car Rate (%)</label>
                <input 
                  type="number" 
                  step="0.1" 
                  min="1" 
                  max="50" 
                  className="input" 
                  value={carRate} 
                  onChange={e => setCarRate(parseFloat(e.target.value))} 
                  required 
                />
              </div>

              <div className="form-group">
                <label className="label">Goods / Truck Rate (%)</label>
                <input 
                  type="number" 
                  step="0.1" 
                  min="1" 
                  max="50" 
                  className="input" 
                  value={truckRate} 
                  onChange={e => setTruckRate(parseFloat(e.target.value))} 
                  required 
                />
              </div>

              <div className="form-group">
                <label className="label">Parcel Delivery Rate (%)</label>
                <input 
                  type="number" 
                  step="0.1" 
                  min="1" 
                  max="50" 
                  className="input" 
                  value={deliveryRate} 
                  onChange={e => setDeliveryRate(parseFloat(e.target.value))} 
                  required 
                />
              </div>

              <div className="form-group">
                <label className="label">Statutory GST Rate (%)</label>
                <input 
                  type="number" 
                  step="0.1" 
                  min="0" 
                  max="28" 
                  className="input" 
                  value={taxGstRate} 
                  onChange={e => setTaxGstRate(parseFloat(e.target.value))} 
                  required 
                />
              </div>

              <div className="form-group">
                <label className="label">Payment Gateway Fee (%)</label>
                <input 
                  type="number" 
                  step="0.1" 
                  min="0" 
                  max="10" 
                  className="input" 
                  value={gatewayFeeRate} 
                  onChange={e => setGatewayFeeRate(parseFloat(e.target.value))} 
                  required 
                />
              </div>
            </div>

            <div className="form-group" style={{ marginBottom: '20px' }}>
              <label className="label">Audit Notes / Executive Justification</label>
              <textarea 
                rows={2} 
                className="input" 
                placeholder="State reason for schedule modification..." 
                value={configNotes}
                onChange={e => setConfigNotes(e.target.value)}
              />
            </div>

            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px' }}>
              <button 
                type="submit" 
                className="btn btn-primary"
                disabled={isSavingConfig}
              >
                {isSavingConfig ? 'Saving Version...' : 'Deploy Prospective Rule'}
              </button>
            </div>
          </form>
        </div>
      )}
    </div>
  );
};

export default FounderCommission;
