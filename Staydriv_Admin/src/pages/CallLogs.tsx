import React, { useState, useEffect } from 'react';
import { Search, PhoneCall, RefreshCw, Clock, CheckCircle2, XCircle, PhoneForwarded, ShieldCheck } from 'lucide-react';

interface CallRecord {
  callId?: string;
  bookingId: string;
  orderType?: string;
  callerUserId: string;
  receiverUserId: string;
  customerName?: string;
  pilotName?: string;
  restaurantName?: string;
  customerPhoneMasked?: string;
  pilotPhoneMasked?: string;
  restaurantPhoneMasked?: string;
  virtualNumber?: string;
  callerRole?: string;
  targetRole?: string;
  smartfloRefId?: string;
  callStatus: string;
  callStartedAt: string;
  callAnsweredAt?: string;
  callCompletedAt?: string;
  callFailedAt?: string;
  failureReason?: string;
  duration?: number;
  createdAt: string;
}

export const CallLogs: React.FC = () => {
  const [calls, setCalls] = useState<CallRecord[]>([]);
  const [loading, setLoading] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [lastRefreshed, setLastRefreshed] = useState<Date>(new Date());

  const fetchCalls = async () => {
    setLoading(true);
    try {
      // Try local/relative endpoint first, then CloudFront backend
      let res;
      try {
        res = await fetch('/api/admin/calls');
      } catch (e) {
        res = await fetch('https://dk60tgl9yds4p.cloudfront.net/api/admin/calls');
      }
      if (res && res.ok) {
        const data = await res.json();
        if (data.success && Array.isArray(data.calls)) {
          setCalls(data.calls);
        }
      }
    } catch (err) {
      console.warn('Failed to fetch admin call logs:', err);
    } finally {
      setLoading(false);
      setLastRefreshed(new Date());
    }
  };

  useEffect(() => {
    fetchCalls();
    const interval = setInterval(fetchCalls, 15000);
    return () => clearInterval(interval);
  }, []);

  const filteredCalls = calls.filter(c => {
    const term = searchTerm.toLowerCase();
    const matchesSearch =
      (c.bookingId && c.bookingId.toLowerCase().includes(term)) ||
      (c.callerUserId && c.callerUserId.toLowerCase().includes(term)) ||
      (c.receiverUserId && c.receiverUserId.toLowerCase().includes(term)) ||
      (c.customerName && c.customerName.toLowerCase().includes(term)) ||
      (c.pilotName && c.pilotName.toLowerCase().includes(term)) ||
      (c.restaurantName && c.restaurantName.toLowerCase().includes(term)) ||
      (c.customerPhoneMasked && c.customerPhoneMasked.includes(term)) ||
      (c.pilotPhoneMasked && c.pilotPhoneMasked.includes(term)) ||
      (c.restaurantPhoneMasked && c.restaurantPhoneMasked.includes(term)) ||
      (c.orderType && c.orderType.toLowerCase().includes(term)) ||
      (c.smartfloRefId && c.smartfloRefId.toLowerCase().includes(term));

    if (!matchesSearch) return false;
    if (statusFilter === 'all') return true;
    return c.callStatus.toUpperCase() === statusFilter.toUpperCase();
  });

  const getStatusBadge = (status: string) => {
    switch (status.toUpperCase()) {
      case 'ANSWERED':
      case 'COMPLETED':
        return <span className="badge badge-completed" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}><CheckCircle2 size={12} /> {status}</span>;
      case 'DIRECT_FALLBACK':
        return (
          <span className="badge" style={{ background: 'rgba(245, 158, 11, 0.15)', color: '#d97706', border: '1px solid rgba(245, 158, 11, 0.4)', display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
            <PhoneCall size={12} /> Direct Dial Fallback
          </span>
        );
      case 'INITIATED':
      case 'RINGING':
        return <span className="badge badge-accepted" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}><PhoneForwarded size={12} /> {status}</span>;
      case 'FAILED':
      case 'MISSED':
        return <span className="badge badge-cancelled" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}><XCircle size={12} /> {status}</span>;
      default:
        return <span className="badge badge-suspended">{status}</span>;
    }
  };

  const formatTimestamp = (ts?: string) => {
    if (!ts) return '—';
    try {
      const d = new Date(ts);
      return isNaN(d.getTime()) ? ts : d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' }) + ', ' + d.toLocaleDateString();
    } catch {
      return ts;
    }
  };

  return (
    <div className="page-container">
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: '16px' }}>
        <div>
          <h2 style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <PhoneCall size={24} style={{ color: 'var(--primary)' }} />
            Tata Smartflo Call Masking Logs
          </h2>
          <p style={{ color: 'var(--text-muted)', fontSize: '14px' }}>
            Live masked call session audit between Customers and Pilots routed via Smartflo virtual numbers.
          </p>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
          <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
            Updated: {lastRefreshed.toLocaleTimeString()}
          </span>
          <a
            href="https://cloudphone.tatateleservices.com/login"
            target="_blank"
            rel="noopener noreferrer"
            className="btn btn-secondary btn-sm"
            style={{ display: 'flex', alignItems: 'center', gap: '6px', textDecoration: 'none' }}
            title="Login ID: OR202213 | Client ID: TACN3626694023587"
          >
            <PhoneCall size={14} style={{ color: 'var(--primary)' }} />
            Tata Portal ↗
          </a>
          <button 
            className="btn btn-secondary btn-sm" 
            onClick={fetchCalls} 
            disabled={loading}
            style={{ display: 'flex', alignItems: 'center', gap: '6px' }}
          >
            <RefreshCw size={14} className={loading ? 'spin' : ''} />
            Refresh
          </button>
        </div>
      </div>

      {/* Security Privacy Notice with Tata Smartflo Status */}
      <div style={{
        background: 'rgba(16, 185, 129, 0.08)',
        border: '1px solid rgba(16, 185, 129, 0.25)',
        borderRadius: '8px',
        padding: '12px 16px',
        fontSize: '13px',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        flexWrap: 'wrap',
        gap: '10px',
        color: 'var(--text-main)'
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          <ShieldCheck size={18} style={{ color: '#10b981', flexShrink: 0 }} />
          <span>
            <strong>Tata Smartflo Cloud PBX Connected:</strong> Virtual DID <code>+91 8065 916 303</code> | Client ID: <code>TACN3626694023587</code> | Dual-sided number masking active.
          </span>
        </div>
        <a
          href="https://cloudphone.tatateleservices.com/login"
          target="_blank"
          rel="noopener noreferrer"
          style={{ color: '#3b82f6', textDecoration: 'none', fontSize: '12px', fontWeight: 600, display: 'inline-flex', alignItems: 'center', gap: '4px' }}
        >
          Telecom Portal (Recordings) ↗
        </a>
      </div>

      {/* Filter and Search Bar */}
      <div className="card" style={{ padding: '16px', display: 'flex', gap: '12px', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'space-between' }}>
        <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
          {['all', 'INITIATED', 'ANSWERED', 'COMPLETED', 'DIRECT_FALLBACK', 'FAILED'].map(st => (
            <button
              key={st}
              className={`btn btn-sm ${statusFilter === st ? 'btn-primary' : 'btn-secondary'}`}
              onClick={() => setStatusFilter(st)}
              style={{ textTransform: 'capitalize' }}
            >
              {st === 'DIRECT_FALLBACK' ? '⚠️ Fallback' : st}
            </button>
          ))}
        </div>
        <div className="input-icon-wrapper" style={{ width: '320px' }}>
          <Search size={16} />
          <input 
            type="text" 
            placeholder="Search booking ID, customer, pilot, phone..." 
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
          />
        </div>
      </div>

      {/* Call Sessions Table */}
      <div className="table-wrapper">
        <table>
          <thead>
            <tr>
              <th>ID / Type</th>
              <th>Participant Flow</th>
              <th>Customer</th>
              <th>Pilot / Kitchen</th>
              <th>Status</th>
              <th>Duration</th>
              <th>Start Time</th>
              <th>End Time</th>
              <th>Smartflo Ref ID</th>
              <th>Failure Reason</th>
            </tr>
          </thead>
          <tbody>
            {loading && calls.length === 0 ? (
              <tr>
                <td colSpan={10} style={{ textAlign: 'center', padding: '32px', color: 'var(--text-muted)' }}>
                  Loading masked call sessions...
                </td>
              </tr>
            ) : filteredCalls.length === 0 ? (
              <tr>
                <td colSpan={10} style={{ textAlign: 'center', padding: '32px', color: 'var(--text-muted)' }}>
                  No call records match the current filter.
                </td>
              </tr>
            ) : (
              filteredCalls.map((c, i) => (
                <tr key={c.smartfloRefId || i}>
                  <td>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                      <span
                        className="badge"
                        style={{
                          fontSize: '10px',
                          fontWeight: 700,
                          padding: '2px 6px',
                          background: (c.orderType === 'food_order' || c.bookingId?.startsWith('FD_')) ? 'rgba(234, 88, 12, 0.15)' : 'rgba(37, 99, 235, 0.15)',
                          color: (c.orderType === 'food_order' || c.bookingId?.startsWith('FD_')) ? '#ea580c' : '#2563eb',
                          border: `1px solid ${(c.orderType === 'food_order' || c.bookingId?.startsWith('FD_')) ? 'rgba(234, 88, 12, 0.3)' : 'rgba(37, 99, 235, 0.3)'}`
                        }}
                      >
                        {(c.orderType === 'food_order' || c.bookingId?.startsWith('FD_')) ? '🍔 FOOD' : '🚗 RIDE'}
                      </span>
                      <strong>{c.bookingId}</strong>
                    </div>
                  </td>
                  <td>
                    <div style={{ fontSize: '11px', fontWeight: 600, color: 'var(--text-main)', display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
                      {c.callerRole === 'admin' ? '🛡️ Admin Support' :
                       (c.callerRole === 'customer' && c.targetRole === 'pilot') ? '👤 Customer ➔ 🛵 Pilot' :
                       (c.callerRole === 'customer' && c.targetRole === 'restaurant') ? '👤 Customer ➔ 🍽️ Kitchen' :
                       (c.callerRole === 'pilot' && c.targetRole === 'customer') ? '🛵 Pilot ➔ 👤 Customer' :
                       (c.callerRole === 'pilot' && c.targetRole === 'restaurant') ? '🛵 Pilot ➔ 🍽️ Kitchen' :
                       (c.callerRole === 'restaurant' && c.targetRole === 'customer') ? '🍽️ Kitchen ➔ 👤 Customer' :
                       (c.callerRole === 'restaurant' && c.targetRole === 'pilot') ? '🍽️ Kitchen ➔ 🛵 Pilot' :
                       `${c.callerRole || 'User'} ➔ ${c.targetRole || 'Partner'}`}
                    </div>
                  </td>
                  <td>
                    <div style={{ fontWeight: 600, fontSize: '13px' }}>{c.customerName || (c.callerUserId?.startsWith('cust') ? 'Customer' : c.callerUserId)}</div>
                    {c.customerPhoneMasked && <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>{c.customerPhoneMasked}</div>}
                  </td>
                  <td>
                    <div style={{ fontWeight: 600, fontSize: '13px' }}>
                      {c.targetRole === 'restaurant' || c.callerRole === 'restaurant' 
                        ? (c.restaurantName || 'Restaurant Kitchen') 
                        : (c.pilotName || (c.receiverUserId?.startsWith('pilot') ? 'Pilot' : c.receiverUserId))}
                    </div>
                    {(c.targetRole === 'restaurant' || c.callerRole === 'restaurant')
                      ? (c.restaurantPhoneMasked && <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>{c.restaurantPhoneMasked}</div>)
                      : (c.pilotPhoneMasked && <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>{c.pilotPhoneMasked}</div>)}
                  </td>
                  <td>
                    {getStatusBadge(c.callStatus)}
                  </td>
                  <td>
                    <span style={{ fontSize: '12px', display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
                      <Clock size={12} style={{ color: 'var(--text-muted)' }} />
                      {c.duration ? `${c.duration}s` : '—'}
                    </span>
                  </td>
                  <td style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
                    {formatTimestamp(c.callStartedAt || c.createdAt)}
                  </td>
                  <td style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
                    {formatTimestamp(c.callCompletedAt || c.callFailedAt)}
                  </td>
                  <td>
                    <code style={{ fontSize: '11px', background: 'var(--bg-main)', padding: '2px 6px', borderRadius: '4px' }}>
                      {c.smartfloRefId || 'N/A'}
                    </code>
                  </td>
                  <td>
                    {c.failureReason ? (
                      <span style={{ color: 'var(--error, #ef4444)', fontSize: '12px' }}>{c.failureReason}</span>
                    ) : (
                      <span style={{ color: 'var(--text-muted)', fontSize: '12px' }}>—</span>
                    )}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
};

export default CallLogs;
