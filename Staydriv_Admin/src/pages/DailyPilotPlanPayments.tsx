import React, { useState, useEffect, useCallback } from 'react';
import { 
  CreditCard, Search, RefreshCw, Download, CheckCircle2, 
  XCircle, AlertCircle, Clock, Bike, Car, Truck, PlayCircle, StopCircle, 
  ShieldCheck, ShieldAlert, Sparkles, History
} from 'lucide-react';
import { useAuth } from '../context/AuthContext';

interface AuditHistoryItem {
  action: string;
  changedBy: string;
  reason?: string;
  timestamp: string;
}

interface DailyPlanRecord {
  _id: string;
  pilotId: string;
  pilotName: string;
  pilotPhone: string;
  vehicleType: string;
  paidAt: string;
  amount: number;
  currency: string;
  transactionId: string;
  paymentStatus: 'paid' | 'expired' | 'pending' | 'failed';
  expiresAt: string;
  dutyStatus?: 'DUTY ON' | 'DUTY OFF';
  bookingAccessStatus: 'enabled' | 'disabled';
  adminStartStopStatus: 'START' | 'STOP' | 'DUTY_ON' | 'DUTY_OFF' | 'NONE';
  adminReason?: string;
  adminUpdatedBy?: string;
  adminUpdatedAt?: string;
  auditHistory?: AuditHistoryItem[];
}

interface SummaryData {
  dailyPaymentTotals: number;
  pilotsPaidToday: number;
  activePaidPilots: number;
  expiredUnpaidPilots: number;
  dutyOnCount?: number;
  dutyOffCount?: number;
  totalRegisteredPilots: number;
}

export const DailyPilotPlanPayments: React.FC = () => {
  const { user } = useAuth();
  const [payments, setPayments] = useState<DailyPlanRecord[]>([]);
  const [summary, setSummary] = useState<SummaryData>({
    dailyPaymentTotals: 0,
    pilotsPaidToday: 0,
    activePaidPilots: 0,
    expiredUnpaidPilots: 0,
    dutyOnCount: 0,
    dutyOffCount: 0,
    totalRegisteredPilots: 0
  });

  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [searchTerm, setSearchTerm] = useState(() => {
    const auto = sessionStorage.getItem('admin_auto_filter');
    if (auto) {
      sessionStorage.removeItem('admin_auto_filter');
      return auto;
    }
    return '';
  });

  useEffect(() => {
    const handleSearchNav = (e: any) => {
      if (e.detail?.filter && (e.detail?.tab === 'daily-pilot-plan' || !e.detail?.tab)) {
        setSearchTerm(e.detail.filter);
      }
    };
    window.addEventListener('admin:search-navigate', handleSearchNav);
    return () => window.removeEventListener('admin:search-navigate', handleSearchNav);
  }, []);
  const [activeFilterTab, setActiveFilterTab] = useState<'all' | 'paid_today' | 'valid_paid' | 'expired' | 'pending_failed' | 'duty_on' | 'duty_off'>('all');
  const [vehicleFilter, setVehicleFilter] = useState('all');
  const [dateFilter, setDateFilter] = useState('');

  // Duty Action Dialog States
  const [selectedPilotForAction, setSelectedPilotForAction] = useState<DailyPlanRecord | null>(null);
  const [actionType, setActionType] = useState<'DUTY_ON' | 'DUTY_OFF' | null>(null);
  const [actionReason, setActionReason] = useState('');
  const [isSubmittingAction, setIsSubmittingAction] = useState(false);
  const [actionError, setActionError] = useState('');
  const [actionSuccess, setActionSuccess] = useState('');

  // History Modal States
  const [selectedPilotForHistory, setSelectedPilotForHistory] = useState<DailyPlanRecord | null>(null);

  const getBackendUrl = () => {
    return window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1'
      ? 'http://localhost:5000'
      : (window.location.origin.includes('cloudfront')
          ? 'https://dk60tgl9yds4p.cloudfront.net'
          : window.location.origin);
  };

  const getAuthHeaders = () => {
    const token = localStorage.getItem('staydriv_admin_token') || 'staydriv_admin_secret_2026';
    return {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
      'x-admin-key': 'staydriv_admin_secret_2026'
    };
  };

  const fetchPayments = useCallback(async (quiet = false) => {
    if (!quiet) setIsLoading(true);
    try {
      const backendUrl = getBackendUrl();
      const params = new URLSearchParams();
      if (searchTerm) params.append('search', searchTerm);
      if (activeFilterTab !== 'all') params.append('view', activeFilterTab);
      if (vehicleFilter !== 'all') params.append('vehicleType', vehicleFilter);
      if (dateFilter) params.append('date', dateFilter);

      const res = await fetch(`${backendUrl}/api/admin/pilot-daily-plans?${params.toString()}`, {
        headers: getAuthHeaders()
      });
      const data = await res.json();
      if (data.success) {
        setPayments(data.payments || []);
        if (data.summary) setSummary(data.summary);
      }
    } catch (err: any) {
      console.error('Error fetching pilot daily plan payments:', err);
    } finally {
      setIsLoading(false);
      setIsRefreshing(false);
    }
  }, [searchTerm, activeFilterTab, vehicleFilter, dateFilter]);

  useEffect(() => {
    fetchPayments();
  }, [fetchPayments]);

  const handleRefresh = async () => {
    setIsRefreshing(true);
    await fetchPayments(true);
  };

  const handleExportCsv = () => {
    const backendUrl = getBackendUrl();
    window.open(`${backendUrl}/api/admin/pilot-daily-plans/export`, '_blank');
  };

  const openDutyActionModal = (pilot: DailyPlanRecord, type: 'DUTY_ON' | 'DUTY_OFF') => {
    setSelectedPilotForAction(pilot);
    setActionType(type);
    setActionReason(type === 'DUTY_ON' ? 'Fee verified & duty authorized by Admin' : '');
    setActionError('');
    setActionSuccess('');
  };

  const closeDutyActionModal = () => {
    setSelectedPilotForAction(null);
    setActionType(null);
    setActionReason('');
    setActionError('');
    setActionSuccess('');
  };

  const handleExecuteDutyAction = async () => {
    if (!selectedPilotForAction || !actionType) return;
    if (actionType === 'DUTY_OFF' && (!actionReason || !actionReason.trim())) {
      setActionError('A mandatory reason is required to set pilot duty to OFF.');
      return;
    }

    setIsSubmittingAction(true);
    setActionError('');

    try {
      const backendUrl = getBackendUrl();
      const targetId = selectedPilotForAction.pilotId || selectedPilotForAction.pilotPhone || (selectedPilotForAction as any)._id;
      const res = await fetch(`${backendUrl}/api/admin/drivers/${encodeURIComponent(targetId)}/duty`, {
        method: 'POST',
        headers: getAuthHeaders(),
        body: JSON.stringify({
          action: actionType,
          reason: actionReason.trim(),
          adminId: user?.uid || 'admin',
          adminName: user?.name || 'StayDriv Admin'
        })
      });

      const data = await res.json();
      if (data.success) {
        setActionSuccess(data.message || `Duty status updated to ${actionType === 'DUTY_ON' ? 'DUTY ON' : 'DUTY OFF'} successfully.`);
        setTimeout(() => {
          closeDutyActionModal();
          fetchPayments(true);
        }, 1200);
      } else {
        setActionError(data.message || 'Failed to update pilot duty status.');
      }
    } catch (err: any) {
      setActionError(err.message || 'Network error executing duty status change.');
    } finally {
      setIsSubmittingAction(false);
    }
  };

  const getVehicleIcon = (type: string) => {
    const t = (type || '').toLowerCase();
    if (t.includes('heavy')) return <Truck size={14} style={{ color: '#ea580c' }} />;
    if (t.includes('mini') || t.includes('truck')) return <Truck size={14} style={{ color: '#0284c7' }} />;
    if (t.includes('car')) return <Car size={14} style={{ color: '#2563eb' }} />;
    return <Bike size={14} style={{ color: '#16a34a' }} />;
  };

  const formatDateTime = (dateStr: string) => {
    if (!dateStr) return '—';
    try {
      const d = new Date(dateStr);
      return d.toLocaleString('en-IN', {
        day: '2-digit',
        month: 'short',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
        hour12: true
      });
    } catch {
      return dateStr;
    }
  };

  const getExpiryStatus = (expiresAtStr: string, status: string) => {
    if (!expiresAtStr) return null;
    const exp = new Date(expiresAtStr);
    const now = new Date();
    const isExpired = now >= exp || status === 'expired';

    if (isExpired) {
      return (
        <span style={{ fontSize: '11px', color: '#ef4444', fontWeight: 600 }}>
          Expired
        </span>
      );
    }

    const diffHours = Math.round((exp.getTime() - now.getTime()) / (1000 * 60 * 60));
    return (
      <span style={{ fontSize: '11px', color: '#10b981', fontWeight: 600 }}>
        Valid ({diffHours}h left)
      </span>
    );
  };

  return (
    <div className="page-container">
      {/* 1. Header Section: Exact Title ₹20 DAILY PILOT PAYMENTS */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '16px', marginBottom: '20px' }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <h2 style={{ margin: 0, fontSize: '24px', fontWeight: 800, letterSpacing: '-0.5px' }}>₹20 DAILY PILOT PAYMENTS</h2>
            <span style={{ 
              display: 'inline-flex', 
              alignItems: 'center', 
              gap: '6px', 
              padding: '4px 10px', 
              borderRadius: '20px', 
              fontSize: '11px', 
              fontWeight: 700, 
              background: 'rgba(16, 185, 129, 0.15)', 
              color: '#10b981' 
            }}>
              <CheckCircle2 size={12} />
              100% EARNINGS • ZERO STAYDRIV COMMISSION
            </span>
          </div>
          <p style={{ color: 'var(--text-muted)', fontSize: '13px', marginTop: '6px', marginBottom: 0 }}>
            Pilots who pay the daily fee of ₹20 receive 100% of ride-booking and food-delivery earnings without StayDriv commission deductions. Admin Console has exclusive authority over DUTY ON / DUTY OFF.
          </p>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          <button 
            className="btn btn-secondary btn-sm" 
            onClick={handleExportCsv}
            style={{ display: 'flex', alignItems: 'center', gap: '6px' }}
          >
            <Download size={14} />
            <span>Export CSV</span>
          </button>
          <button 
            className="btn btn-secondary btn-sm" 
            onClick={handleRefresh}
            disabled={isRefreshing}
            style={{ display: 'flex', alignItems: 'center', gap: '6px' }}
          >
            <RefreshCw size={14} className={isRefreshing ? 'animate-spin' : ''} />
            <span>{isRefreshing ? 'Syncing...' : 'Refresh'}</span>
          </button>
        </div>
      </div>

      {/* 2. Key KPI Metric Cards */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(210px, 1fr))', gap: '16px', marginBottom: '20px' }}>
        {/* Card 1: Daily Payment Totals */}
        <div className="card" style={{ padding: '18px', borderLeft: '4px solid #10b981' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', color: 'var(--text-muted)', fontSize: '12px', fontWeight: 600 }}>
            <span>TODAY'S DAILY PLAN REVENUE</span>
            <CreditCard size={18} color="#10b981" />
          </div>
          <div style={{ fontSize: '26px', fontWeight: 800, marginTop: '8px', color: 'var(--text)' }}>
            ₹{summary.dailyPaymentTotals.toLocaleString('en-IN')}
          </div>
          <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '4px' }}>
            Separate ₹20 daily fee accounting ledger
          </div>
        </div>

        {/* Card 2: Number of Pilots Paid Today */}
        <div className="card" style={{ padding: '18px', borderLeft: '4px solid #0284c7' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', color: 'var(--text-muted)', fontSize: '12px', fontWeight: 600 }}>
            <span>PILOTS PAID TODAY</span>
            <Sparkles size={18} color="#0284c7" />
          </div>
          <div style={{ fontSize: '26px', fontWeight: 800, marginTop: '8px', color: '#0284c7' }}>
            {summary.pilotsPaidToday}
          </div>
          <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '4px' }}>
            Paid ₹20 fee during today's window
          </div>
        </div>

        {/* Card 3: Active Paid Pilots */}
        <div className="card" style={{ padding: '18px', borderLeft: '4px solid #10b981' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', color: 'var(--text-muted)', fontSize: '12px', fontWeight: 600 }}>
            <span>ACTIVE PAID PILOTS</span>
            <ShieldCheck size={18} color="#10b981" />
          </div>
          <div style={{ fontSize: '26px', fontWeight: 800, marginTop: '8px', color: '#10b981' }}>
            {summary.activePaidPilots}
          </div>
          <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '4px' }}>
            Within valid 24-hr payment period
          </div>
        </div>

        {/* Card 4: DUTY ON Pilots */}
        <div className="card" style={{ padding: '18px', borderLeft: '4px solid #059669' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', color: 'var(--text-muted)', fontSize: '12px', fontWeight: 600 }}>
            <span>PILOTS ON DUTY ON</span>
            <PlayCircle size={18} color="#059669" />
          </div>
          <div style={{ fontSize: '26px', fontWeight: 800, marginTop: '8px', color: '#059669' }}>
            {summary.dutyOnCount ?? 0}
          </div>
          <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '4px' }}>
            Admin authorized for dispatch
          </div>
        </div>

        {/* Card 5: DUTY OFF Pilots */}
        <div className="card" style={{ padding: '18px', borderLeft: '4px solid #ef4444' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', color: 'var(--text-muted)', fontSize: '12px', fontWeight: 600 }}>
            <span>PILOTS ON DUTY OFF</span>
            <StopCircle size={18} color="#ef4444" />
          </div>
          <div style={{ fontSize: '26px', fontWeight: 800, marginTop: '8px', color: '#ef4444' }}>
            {summary.dutyOffCount ?? summary.expiredUnpaidPilots}
          </div>
          <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '4px' }}>
            Blocked from receiving bookings
          </div>
        </div>
      </div>

      {/* 3. Dedicated 6 Filter Views (Tabs) */}
      <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap', marginBottom: '16px' }}>
        {[
          { id: 'all', label: 'All Payments' },
          { id: 'paid_today', label: '1. Paid ₹20 Today' },
          { id: 'valid_paid', label: '2. Valid Paid Daily Plan' },
          { id: 'expired', label: '3. Plan Expired' },
          { id: 'pending_failed', label: '4. Pending / Failed' },
          { id: 'duty_on', label: '5. DUTY ON Pilots' },
          { id: 'duty_off', label: '6. DUTY OFF Pilots' },
        ].map((tab) => {
          const isActive = activeFilterTab === tab.id;
          return (
            <button
              key={tab.id}
              onClick={() => setActiveFilterTab(tab.id as any)}
              style={{
                padding: '8px 14px',
                borderRadius: '8px',
                fontSize: '12.5px',
                fontWeight: 700,
                border: isActive ? '1px solid #10b981' : '1px solid var(--border-color)',
                background: isActive ? '#10b981' : 'var(--bg-card)',
                color: isActive ? '#ffffff' : 'var(--text)',
                cursor: 'pointer',
                transition: 'all 0.15s ease'
              }}
            >
              {tab.label}
            </button>
          );
        })}
      </div>

      {/* 4. Search and Secondary Filters Toolbar */}
      <div className="card" style={{ padding: '14px 16px', marginBottom: '20px' }}>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: '12px', alignItems: 'center' }}>
          {/* Search Box: ID, Name, Phone */}
          <div style={{ position: 'relative', flex: '1 1 260px', minWidth: '220px' }}>
            <Search size={15} style={{ position: 'absolute', left: '12px', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
            <input
              type="text"
              className="form-control"
              placeholder="Search by pilot ID, name, mobile number, or txn..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              style={{ paddingLeft: '36px', height: '38px', fontSize: '13px' }}
            />
          </div>

          {/* Vehicle Type Filter */}
          <div style={{ minWidth: '150px' }}>
            <select
              className="form-control"
              value={vehicleFilter}
              onChange={(e) => setVehicleFilter(e.target.value)}
              style={{ height: '38px', fontSize: '13px' }}
            >
              <option value="all">All Vehicles</option>
              <option value="bike">Bike / Scooty</option>
              <option value="auto">Auto</option>
              <option value="car">Car</option>
              <option value="car xl">Car XL</option>
            </select>
          </div>

          {/* Date Picker Filter */}
          <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
            <input
              type="date"
              className="form-control"
              value={dateFilter}
              onChange={(e) => setDateFilter(e.target.value)}
              style={{ height: '38px', fontSize: '13px' }}
            />
            {dateFilter && (
              <button 
                className="btn btn-secondary btn-sm"
                onClick={() => setDateFilter('')}
                style={{ height: '38px' }}
              >
                Clear
              </button>
            )}
          </div>
        </div>
      </div>

      {/* 5. Verified ₹20 Daily Payment Register Table */}
      <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
        <div style={{ padding: '16px 20px', borderBottom: '1px solid var(--border-color)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <h3 style={{ margin: 0, fontSize: '16px', fontWeight: 700 }}>₹20 Daily Pilot Payment Register</h3>
            <span style={{ fontSize: '12px', background: 'var(--bg-subtle)', padding: '2px 8px', borderRadius: '12px', color: 'var(--text-muted)' }}>
              {payments.length} verified records
            </span>
          </div>
        </div>

        {isLoading ? (
          <div style={{ padding: '60px', textAlign: 'center', color: 'var(--text-muted)' }}>
            <RefreshCw size={28} className="animate-spin" style={{ margin: '0 auto 12px' }} />
            <p>Loading ₹20 daily pilot payment records...</p>
          </div>
        ) : payments.length === 0 ? (
          <div style={{ padding: '60px', textAlign: 'center', color: 'var(--text-muted)' }}>
            <CreditCard size={36} style={{ margin: '0 auto 12px', opacity: 0.5 }} />
            <p style={{ fontSize: '15px', fontWeight: 600 }}>No payment records found matching this view</p>
            <p style={{ fontSize: '13px' }}>Genuine ₹20 daily payments will appear here as pilots subscribe.</p>
          </div>
        ) : (
          <div style={{ overflowX: 'auto' }}>
            <table className="table" style={{ width: '100%', borderCollapse: 'collapse', textAlign: 'left', fontSize: '13px' }}>
              <thead>
                <tr style={{ background: 'var(--bg-subtle)', borderBottom: '1px solid var(--border-color)', color: 'var(--text-muted)', fontSize: '11px', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                  <th style={{ padding: '12px 14px' }}>Pilot ID</th>
                  <th style={{ padding: '12px 14px' }}>Pilot Name</th>
                  <th style={{ padding: '12px 14px' }}>Mobile Number</th>
                  <th style={{ padding: '12px 14px' }}>Vehicle Type</th>
                  <th style={{ padding: '12px 14px' }}>Payment Amount</th>
                  <th style={{ padding: '12px 14px' }}>Payment Date & Time</th>
                  <th style={{ padding: '12px 14px' }}>Transaction ID</th>
                  <th style={{ padding: '12px 14px' }}>Payment Status</th>
                  <th style={{ padding: '12px 14px' }}>Plan Expiry</th>
                  <th style={{ padding: '12px 14px', textAlign: 'center' }}>Current Duty Status</th>
                  <th style={{ padding: '12px 14px', textAlign: 'center' }}>Admin Action History</th>
                  <th style={{ padding: '12px 14px', textAlign: 'center' }}>Admin Duty Control</th>
                </tr>
              </thead>
              <tbody>
                {payments.map((record) => {
                  const isPaid = record.paymentStatus === 'paid';
                  const isExpired = record.paymentStatus === 'expired';
                  const isDutyOn = record.dutyStatus === 'DUTY ON' || (record.bookingAccessStatus === 'enabled' && isPaid);

                  return (
                    <tr key={record._id} style={{ borderBottom: '1px solid var(--border-color)' }}>
                      {/* 1. Pilot ID */}
                      <td style={{ padding: '12px 14px', fontWeight: 700, fontFamily: 'monospace', color: 'var(--primary)' }}>
                        {record.pilotId}
                      </td>

                      {/* 2. Pilot Name */}
                      <td style={{ padding: '12px 14px', fontWeight: 600 }}>
                        {record.pilotName || 'Pilot Partner'}
                      </td>

                      {/* 3. Mobile Number */}
                      <td style={{ padding: '12px 14px', fontFamily: 'monospace' }}>
                        +91 {record.pilotPhone}
                      </td>

                      {/* 4. Vehicle Type */}
                      <td style={{ padding: '12px 14px' }}>
                        <div style={{ display: 'inline-flex', alignItems: 'center', gap: '6px' }}>
                          {getVehicleIcon(record.vehicleType)}
                          <span style={{ fontWeight: 600 }}>{record.vehicleType || 'Bike'}</span>
                        </div>
                      </td>

                      {/* 5. Payment Amount */}
                      <td style={{ padding: '12px 14px', fontWeight: 800, color: 'var(--success)' }}>
                        ₹{record.amount || 20}
                      </td>

                      {/* 6. Payment Date & Time */}
                      <td style={{ padding: '12px 14px', color: 'var(--text-muted)' }}>
                        {formatDateTime(record.paidAt)}
                      </td>

                      {/* 7. Transaction ID */}
                      <td style={{ padding: '12px 14px', fontFamily: 'monospace', fontSize: '11px', color: 'var(--text-muted)' }}>
                        {record.transactionId}
                      </td>

                      {/* 8. Payment Status Badge */}
                      <td style={{ padding: '12px 14px' }}>
                        <span style={{ 
                          display: 'inline-flex', 
                          alignItems: 'center', 
                          gap: '4px', 
                          padding: '3px 8px', 
                          borderRadius: '12px', 
                          fontSize: '11px', 
                          fontWeight: 700,
                          background: isPaid ? 'rgba(16, 185, 129, 0.15)' : isExpired ? 'rgba(245, 158, 11, 0.15)' : 'rgba(239, 68, 68, 0.15)',
                          color: isPaid ? '#10b981' : isExpired ? '#f59e0b' : '#ef4444'
                        }}>
                          {isPaid ? <CheckCircle2 size={11} /> : isExpired ? <Clock size={11} /> : <XCircle size={11} />}
                          {record.paymentStatus.toUpperCase()}
                        </span>
                      </td>

                      {/* 9. Plan Expiry */}
                      <td style={{ padding: '12px 14px' }}>
                        <div>{formatDateTime(record.expiresAt)}</div>
                        <div>{getExpiryStatus(record.expiresAt, record.paymentStatus)}</div>
                      </td>

                      {/* 10. Current Duty Status */}
                      <td style={{ padding: '12px 14px', textAlign: 'center' }}>
                        <span style={{ 
                          display: 'inline-flex', 
                          alignItems: 'center', 
                          gap: '5px', 
                          padding: '4px 10px', 
                          borderRadius: '12px', 
                          fontSize: '11px', 
                          fontWeight: 800,
                          background: isDutyOn ? 'rgba(16, 185, 129, 0.2)' : 'rgba(239, 68, 68, 0.15)',
                          color: isDutyOn ? '#059669' : '#dc2626'
                        }}>
                          {isDutyOn ? <CheckCircle2 size={12} /> : <XCircle size={12} />}
                          {isDutyOn ? 'DUTY ON' : 'DUTY OFF'}
                        </span>
                        {record.adminReason && !isDutyOn && (
                          <div style={{ fontSize: '10px', color: '#dc2626', marginTop: '3px', maxWidth: '140px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={record.adminReason}>
                            {record.adminReason}
                          </div>
                        )}
                      </td>

                      {/* 11. Admin Action History */}
                      <td style={{ padding: '12px 14px', textAlign: 'center' }}>
                        <button
                          className="btn btn-secondary btn-sm"
                          onClick={() => setSelectedPilotForHistory(record)}
                          style={{
                            display: 'inline-flex',
                            alignItems: 'center',
                            gap: '4px',
                            fontSize: '11px',
                            padding: '4px 8px'
                          }}
                        >
                          <History size={12} />
                          <span>History ({record.auditHistory?.length || 0})</span>
                        </button>
                      </td>

                      {/* 12. Admin-Only Duty Action Control */}
                      <td style={{ padding: '12px 14px', textAlign: 'center' }}>
                        {isDutyOn ? (
                          <button
                            className="btn btn-sm"
                            onClick={() => openDutyActionModal(record, 'DUTY_OFF')}
                            style={{ 
                              display: 'inline-flex', 
                              alignItems: 'center', 
                              gap: '6px', 
                              background: '#ef4444', 
                              color: 'white', 
                              border: 'none', 
                              padding: '6px 12px', 
                              borderRadius: '6px', 
                              fontWeight: 700, 
                              fontSize: '11px',
                              cursor: 'pointer'
                            }}
                          >
                            <StopCircle size={14} />
                            <span>DUTY OFF</span>
                          </button>
                        ) : (
                          <button
                            className="btn btn-sm"
                            onClick={() => openDutyActionModal(record, 'DUTY_ON')}
                            title={isPaid ? 'Authorize pilot to receive bookings (Plan is active)' : 'Authorize pilot to receive bookings (Admin will grant 24h plan)'}
                            style={{ 
                              display: 'inline-flex', 
                              alignItems: 'center', 
                              gap: '6px', 
                              background: '#10b981', 
                              color: 'white', 
                              border: 'none', 
                              padding: '6px 12px', 
                              borderRadius: '6px', 
                              fontWeight: 700, 
                              fontSize: '11px', 
                              cursor: 'pointer',
                              boxShadow: '0 2px 4px rgba(16, 185, 129, 0.2)'
                            }}
                          >
                            <PlayCircle size={14} />
                            <span>DUTY ON</span>
                          </button>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* 6. Admin Action History Modal */}
      {selectedPilotForHistory && (
        <div style={{
          position: 'fixed',
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          background: 'rgba(0, 0, 0, 0.7)',
          display: 'flex',
          justifyContent: 'center',
          alignItems: 'center',
          zIndex: 10000,
          padding: '20px'
        }}>
          <div style={{
            background: 'var(--bg-card, #ffffff)',
            borderRadius: '16px',
            maxWidth: '540px',
            width: '100%',
            padding: '24px',
            boxShadow: '0 20px 25px -5px rgba(0, 0, 0, 0.3)',
            color: 'var(--text)'
          }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <History size={20} color="#0284c7" />
                <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>Admin Action History</h3>
              </div>
              <button
                className="btn btn-secondary btn-sm"
                onClick={() => setSelectedPilotForHistory(null)}
              >
                Close
              </button>
            </div>

            <div style={{ fontSize: '13px', marginBottom: '14px', color: 'var(--text-muted)' }}>
              Pilot: <strong>{selectedPilotForHistory.pilotName}</strong> ({selectedPilotForHistory.pilotPhone}) • ID: <span style={{ fontFamily: 'monospace' }}>{selectedPilotForHistory.pilotId}</span>
            </div>

            <div style={{ maxHeight: '320px', overflowY: 'auto' }}>
              {(!selectedPilotForHistory.auditHistory || selectedPilotForHistory.auditHistory.length === 0) ? (
                <p style={{ textAlign: 'center', color: 'var(--text-muted)', fontSize: '13px', padding: '20px' }}>
                  No historical actions recorded yet for this pilot.
                </p>
              ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
                  {selectedPilotForHistory.auditHistory.map((item, idx) => (
                    <div key={idx} style={{
                      padding: '10px 12px',
                      borderRadius: '8px',
                      background: 'var(--bg-subtle, #f8fafc)',
                      border: '1px solid var(--border-color, #e2e8f0)',
                      fontSize: '12px'
                    }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '4px' }}>
                        <span style={{
                          fontWeight: 700,
                          color: item.action.includes('ON') || item.action.includes('START') || item.action.includes('PAYMENT') ? '#10b981' : '#ef4444'
                        }}>
                          {item.action}
                        </span>
                        <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                          {formatDateTime(item.timestamp)}
                        </span>
                      </div>
                      <div style={{ color: 'var(--text)', marginBottom: '2px' }}>
                        <strong>Changed by:</strong> {item.changedBy}
                      </div>
                      {item.reason && (
                        <div style={{ color: 'var(--text-muted)' }}>
                          <strong>Reason:</strong> {item.reason}
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* 7. Dedicated Confirmation Modal for DUTY ON / DUTY OFF */}
      {selectedPilotForAction && actionType && (
        <div style={{
          position: 'fixed',
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          background: 'rgba(0, 0, 0, 0.7)',
          display: 'flex',
          justifyContent: 'center',
          alignItems: 'center',
          zIndex: 10000,
          padding: '20px'
        }}>
          <div style={{
            background: 'var(--bg-card, #ffffff)',
            borderRadius: '16px',
            maxWidth: '480px',
            width: '100%',
            padding: '24px',
            boxShadow: '0 20px 25px -5px rgba(0, 0, 0, 0.3)',
            color: 'var(--text)'
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '16px' }}>
              <div style={{
                width: '44px',
                height: '44px',
                borderRadius: '50%',
                background: actionType === 'DUTY_ON' ? 'rgba(16, 185, 129, 0.15)' : 'rgba(239, 68, 68, 0.15)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                color: actionType === 'DUTY_ON' ? '#10b981' : '#ef4444'
              }}>
                {actionType === 'DUTY_ON' ? <PlayCircle size={26} /> : <StopCircle size={26} />}
              </div>
              <div>
                <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>
                  {actionType === 'DUTY_ON' ? 'Turn DUTY ON' : 'Turn DUTY OFF'}
                </h3>
                <p style={{ margin: '2px 0 0', fontSize: '12px', color: 'var(--text-muted)' }}>
                  Admin Console Exclusive Authority
                </p>
              </div>
            </div>

            {/* Pilot Details Summary Box */}
            <div style={{
              background: 'var(--bg-subtle, #f8fafc)',
              borderRadius: '10px',
              padding: '12px 14px',
              marginBottom: '16px',
              fontSize: '13px',
              border: '1px solid var(--border-color, #e2e8f0)'
            }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '6px' }}>
                <span style={{ color: 'var(--text-muted)' }}>Pilot Name:</span>
                <strong>{selectedPilotForAction.pilotName}</strong>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '6px' }}>
                <span style={{ color: 'var(--text-muted)' }}>Pilot ID:</span>
                <span style={{ fontFamily: 'monospace' }}>{selectedPilotForAction.pilotId}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '6px' }}>
                <span style={{ color: 'var(--text-muted)' }}>Vehicle Type:</span>
                <span>{selectedPilotForAction.vehicleType}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: 'var(--text-muted)' }}>Daily Plan Expiry:</span>
                <span>{formatDateTime(selectedPilotForAction.expiresAt)}</span>
              </div>
            </div>

            {/* Verification Notice */}
            {actionType === 'DUTY_ON' ? (
              <div style={{
                background: 'rgba(16, 185, 129, 0.1)',
                border: '1px solid rgba(16, 185, 129, 0.3)',
                borderRadius: '8px',
                padding: '10px 12px',
                fontSize: '12px',
                color: '#065f46',
                marginBottom: '16px'
              }}>
                Authorizing DUTY ON enables the pilot to immediately receive eligible ride and food delivery offers. The pilot will receive 100% of booking earnings without StayDriv commission deductions.
              </div>
            ) : (
              <div style={{
                background: 'rgba(239, 68, 68, 0.1)',
                border: '1px solid rgba(239, 68, 68, 0.3)',
                borderRadius: '8px',
                padding: '10px 12px',
                fontSize: '12px',
                color: '#991b1b',
                marginBottom: '16px'
              }}>
                Setting DUTY OFF immediately prevents new booking offers from being assigned. Any ride or food delivery already in progress will NOT be automatically cancelled. A mandatory reason is required.
              </div>
            )}

            {/* Reason Input (Mandatory for DUTY OFF, Optional for DUTY ON) */}
            <div style={{ marginBottom: '16px' }}>
              <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px', color: 'var(--text)' }}>
                {actionType === 'DUTY_OFF' ? 'Mandatory Reason for Turning Duty OFF *' : 'Admin Note / Reason (Optional)'}
              </label>
              <textarea
                className="form-control"
                rows={3}
                placeholder={actionType === 'DUTY_OFF' ? 'e.g. Operational pause, document re-audit required, customer complaint review...' : 'e.g. Verified and authorized for booking duty'}
                value={actionReason}
                onChange={(e) => setActionReason(e.target.value)}
                style={{ width: '100%', fontSize: '13px' }}
              />
            </div>

            {/* Error or Success Alert */}
            {actionError && (
              <div style={{
                background: '#fee2e2',
                color: '#b91c1c',
                padding: '8px 12px',
                borderRadius: '6px',
                fontSize: '12px',
                marginBottom: '14px',
                display: 'flex',
                alignItems: 'center',
                gap: '6px'
              }}>
                <AlertCircle size={14} />
                <span>{actionError}</span>
              </div>
            )}

            {actionSuccess && (
              <div style={{
                background: '#dcfce7',
                color: '#15803d',
                padding: '8px 12px',
                borderRadius: '6px',
                fontSize: '12px',
                marginBottom: '14px',
                display: 'flex',
                alignItems: 'center',
                gap: '6px'
              }}>
                <CheckCircle2 size={14} />
                <span>{actionSuccess}</span>
              </div>
            )}

            {/* Buttons */}
            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px' }}>
              <button
                type="button"
                className="btn btn-secondary"
                onClick={closeDutyActionModal}
                disabled={isSubmittingAction}
              >
                Cancel
              </button>
              <button
                type="button"
                className="btn"
                onClick={handleExecuteDutyAction}
                disabled={isSubmittingAction}
                style={{
                  background: actionType === 'DUTY_ON' ? '#10b981' : '#ef4444',
                  color: 'white',
                  border: 'none',
                  fontWeight: 700
                }}
              >
                {isSubmittingAction ? 'Processing...' : (actionType === 'DUTY_ON' ? 'Confirm DUTY ON' : 'Confirm DUTY OFF')}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default DailyPilotPlanPayments;
