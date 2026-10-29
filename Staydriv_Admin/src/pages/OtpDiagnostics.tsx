import React, { useState, useEffect } from 'react';
import { Search, ShieldAlert, RefreshCw, CheckCircle2, XCircle, AlertCircle, Clock, KeyRound, Copy, Check } from 'lucide-react';

interface OtpLogRecord {
  _id: string;
  requestId: string;
  transactionId?: string;
  mobileMasked: string;
  userType: string;
  status: string;
  gateway: string;
  provider?: string;
  providerMessageId?: string;
  jobId?: string;
  campaignId?: string;
  templateId: string;
  senderId: string;
  submissionStatus: string;
  deliveryStatus: string;
  providerErrorCode?: string;
  failureReason?: string;
  bind?: string | null;
  pkg?: string | null;
  verificationStatus: string;
  statusCode: number;
  submittedAt?: string;
  gatewayAcceptedAt?: string;
  deliveryConfirmedAt?: string;
  rejectedAt?: string;
  verifiedAt?: string;
  createdAt: string;
  updatedAt: string;
}

export const OtpDiagnostics: React.FC = () => {
  const [logs, setLogs] = useState<OtpLogRecord[]>([]);
  const [loading, setLoading] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [lastRefreshed, setLastRefreshed] = useState<Date>(new Date());
  const [selectedRecord, setSelectedRecord] = useState<OtpLogRecord | null>(null);
  const [copiedSupportText, setCopiedSupportText] = useState(false);
  const [testMobile, setTestMobile] = useState('9490440281');
  const [testingRunning, setTestingRunning] = useState(false);
  const [testResult, setTestResult] = useState<any>(null);

  const runDiagnosticTest = async () => {
    setTestingRunning(true);
    setTestResult(null);
    try {
      const res = await fetch('/api/admin/otp/test-ttbs', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-admin-key': 'staydriv_admin_secret_2026'
        },
        body: JSON.stringify({ mobile: testMobile })
      });
      const data = await res.json();
      setTestResult(data);
      await fetchLogs();
    } catch (err: any) {
      setTestResult({ success: false, message: err.message });
    } finally {
      setTestingRunning(false);
    }
  };

  const supportRequestText = `Subject: URGENT – Activate Transactional SMS Package/Carrier Route for SADGURURL – Error 15019

Body:
Enterprise Account: SADGURURL
Account ID: d7cd1a10-6f30-44ba-9a64-ce3a9cd9b12a
DLT PE ID: 1601419178359745779
DLT Template ID: 1677100000000393380
Sender/Header: SADGRL

Our API requests are successfully authenticated and TTBS returns HTTP 202 ACCEPTED with a message ID.

However, internal TTBS processing returns:
15019 – INVALID_API_KEY

The account/package query shows:
active: []
browse: []
provider: null
bind: null

Please activate/bind the transactional SMS package and carrier/provider route for this enterprise account and confirm that outbound SMS delivery is enabled.

For SMPP Gateway binds (Username: 44HKs9do35O2kqu), please whitelist our outbound application server Elastic IP:
Public IP: 18.61.40.190

We require real-time transactional OTP SMS delivery to Indian mobile numbers.`;

  const copyToClipboard = () => {
    navigator.clipboard.writeText(supportRequestText);
    setCopiedSupportText(true);
    setTimeout(() => setCopiedSupportText(false), 3000);
  };

  const fetchLogs = async () => {
    setLoading(true);
    try {
      let res;
      try {
        res = await fetch('/api/admin/otp-logs');
      } catch (e) {
        res = await fetch('https://dk60tgl9yds4p.cloudfront.net/api/admin/otp-logs');
      }
      if (res && res.ok) {
        const data = await res.json();
        if (data.success && Array.isArray(data.logs)) {
          setLogs(data.logs);
        }
      }
    } catch (err) {
      console.warn('Failed to fetch admin OTP diagnostic logs:', err);
    } finally {
      setLoading(false);
      setLastRefreshed(new Date());
    }
  };

  useEffect(() => {
    fetchLogs();
    const interval = setInterval(fetchLogs, 15000);
    return () => clearInterval(interval);
  }, []);

  const filteredLogs = logs.filter(l => {
    const matchesSearch =
      (l.transactionId && l.transactionId.toLowerCase().includes(searchTerm.toLowerCase())) ||
      (l.mobileMasked && l.mobileMasked.includes(searchTerm)) ||
      (l.jobId && l.jobId.toLowerCase().includes(searchTerm.toLowerCase())) ||
      (l.providerMessageId && l.providerMessageId.toLowerCase().includes(searchTerm.toLowerCase())) ||
      (l.requestId && l.requestId.toLowerCase().includes(searchTerm.toLowerCase()));

    if (!matchesSearch) return false;
    if (statusFilter === 'all') return true;
    return l.deliveryStatus === statusFilter || l.status === statusFilter || l.submissionStatus === statusFilter;
  });

  const getDeliveryBadge = (status: string) => {
    switch (status) {
      case 'SMS_DELIVERED':
      case 'DELIVERED':
        return <span className="badge badge-completed" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}><CheckCircle2 size={12} /> DELIVERED</span>;
      case 'PENDING_CARRIER':
        return <span className="badge badge-accepted" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}><Clock size={12} /> PENDING CARRIER</span>;
      case 'SMS_REJECTED':
      case 'REJECTED':
        return <span className="badge badge-cancelled" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}><XCircle size={12} /> SMS REJECTED</span>;
      case 'SMS_FAILED':
      case 'FAILED':
        return <span className="badge badge-cancelled" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}><AlertCircle size={12} /> SMS FAILED</span>;
      case 'VERIFIED':
        return <span className="badge badge-completed" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}><CheckCircle2 size={12} /> VERIFIED</span>;
      default:
        return <span className="badge badge-suspended">{status}</span>;
    }
  };

  return (
    <div className="page-container">
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: '16px' }}>
        <div>
          <h2 style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <KeyRound size={24} style={{ color: 'var(--primary)' }} />
            TTBS / Smartflo OTP Diagnostic Logs
          </h2>
          <p style={{ color: 'var(--text-muted)', fontSize: '0.9rem', marginTop: '4px' }}>
            Full end-to-end trace from StayDriv App &rarr; Backend &rarr; TTBS Gateway &rarr; Telecom Carrier.
          </p>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
          <span style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>
            Updated: {lastRefreshed.toLocaleTimeString()}
          </span>
          <button 
            className="btn btn-secondary btn-sm" 
            onClick={fetchLogs} 
            disabled={loading}
            style={{ display: 'flex', alignItems: 'center', gap: '6px' }}
          >
            <RefreshCw size={14} className={loading ? 'spin' : ''} />
            Refresh
          </button>
        </div>
      </div>

      {/* Critical Diagnostic Banner (Requirement 7) */}
      <div style={{
        marginTop: '16px',
        padding: '16px 20px',
        borderRadius: '10px',
        background: '#fff1f2',
        border: '1.5px solid #f43f5e',
        color: '#881337'
      }}>
        <div style={{ display: 'flex', alignItems: 'flex-start', gap: '12px' }}>
          <ShieldAlert size={24} style={{ color: '#e11d48', flexShrink: 0, marginTop: '2px' }} />
          <div style={{ flex: 1 }}>
            <h4 style={{ margin: '0 0 6px 0', color: '#9f1239', fontSize: '1.05rem', fontWeight: 700 }}>
              CRITICAL: TTBS SMS ROUTE NOT PROVISIONED (Error 15019 / INVALID_API_KEY)
            </h4>
            <div style={{ fontSize: '0.85rem', lineHeight: '1.6', color: '#4c0519' }}>
              <strong>TTBS Gateway accepts the API request with HTTP 202 ACCEPTED</strong>, but the enterprise account does not currently have an active SMS package, provider, or bind route configured on TTBS CPaaS. Outbound carrier dispatch is currently blocked by TTBS routing.
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: '10px', marginTop: '12px', fontSize: '0.82rem', background: '#ffe4e6', padding: '12px', borderRadius: '8px' }}>
              <div><strong>Enterprise Account:</strong> SADGURURL</div>
              <div><strong>Account ID:</strong> d7cd1a10-6f30-44ba-9a64-ce3a9cd9b12a</div>
              <div><strong>DLT PE ID:</strong> 1601419178359745779</div>
              <div><strong>DLT Template ID:</strong> 1677100000000393380</div>
              <div><strong>Sender / Header:</strong> SADGRL</div>
              <div><strong>App Outbound NAT IP:</strong> 18.61.40.190</div>
              <div><strong>SMS_PACKAGE_STATUS:</strong> <span style={{ color: '#b91c1c', fontWeight: 600 }}>NOT PROVISIONED (0 active)</span></div>
              <div><strong>PROVIDER_STATUS:</strong> <span style={{ color: '#b91c1c', fontWeight: 600 }}>NOT PROVISIONED (null)</span></div>
              <div><strong>BIND_STATUS:</strong> <span style={{ color: '#b91c1c', fontWeight: 600 }}>NOT PROVISIONED (null)</span></div>
              <div><strong>ROUTE_STATUS:</strong> <span style={{ color: '#b91c1c', fontWeight: 600 }}>TTBS SMS ROUTE NOT PROVISIONED</span></div>
            </div>

            {/* Copyable Support Request Box (Requirement 23) */}
            <div style={{ marginTop: '14px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '6px' }}>
                <span style={{ fontSize: '0.82rem', fontWeight: 600 }}>Action Required: Copy and send this request to your TTBS / Smartflo Account Manager:</span>
                <button 
                  onClick={copyToClipboard}
                  className="btn btn-secondary btn-sm"
                  style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', fontSize: '0.78rem', background: '#fff' }}
                >
                  {copiedSupportText ? <Check size={14} color="#10b981" /> : <Copy size={14} />}
                  {copiedSupportText ? 'Copied to Clipboard!' : 'Copy Support Request'}
                </button>
              </div>
              <textarea 
                readOnly
                value={supportRequestText}
                rows={7}
                style={{
                  width: '100%',
                  fontSize: '0.78rem',
                  fontFamily: 'monospace',
                  padding: '8px 12px',
                  borderRadius: '6px',
                  border: '1px solid #fda4af',
                  backgroundColor: '#ffffff',
                  color: '#1e293b'
                }}
              />
            </div>
          </div>
        </div>
      </div>

      {/* Admin Controlled Diagnostic Test Tool (Requirement 16) */}
      <div className="card" style={{ marginTop: '16px', padding: '16px', background: '#f8fafc', border: '1px solid #cbd5e1' }}>
        <h4 style={{ margin: '0 0 10px 0', display: 'flex', alignItems: 'center', gap: '8px', fontSize: '0.95rem' }}>
          <KeyRound size={18} color="var(--primary)" />
          Run Controlled TTBS Diagnostic Test (POST /api/admin/otp/test-ttbs)
        </h4>
        <div style={{ display: 'flex', gap: '12px', alignItems: 'center', flexWrap: 'wrap' }}>
          <div style={{ width: '220px' }}>
            <input 
              type="text" 
              className="form-control" 
              placeholder="Test Mobile (e.g. 9490440281)" 
              value={testMobile}
              onChange={e => setTestMobile(e.target.value)}
              style={{ width: '100%', fontSize: '0.85rem' }}
            />
          </div>
          <button 
            className="btn btn-primary btn-sm" 
            onClick={runDiagnosticTest} 
            disabled={testingRunning}
            style={{ display: 'flex', alignItems: 'center', gap: '6px' }}
          >
            <RefreshCw size={14} className={testingRunning ? 'spin' : ''} />
            {testingRunning ? 'Executing Live Test...' : 'Send Controlled Test SMS'}
          </button>
        </div>

        {testResult && (
          <div style={{ marginTop: '12px', padding: '12px', borderRadius: '8px', background: testResult.carrierStatus === 'SMS_DELIVERED' ? '#f0fdf4' : '#fff1f2', border: `1px solid ${testResult.carrierStatus === 'SMS_DELIVERED' ? '#86efac' : '#fca5a5'}`, fontSize: '0.82rem', fontFamily: 'monospace' }}>
            <div style={{ fontWeight: 700, marginBottom: '6px', color: testResult.carrierStatus === 'SMS_DELIVERED' ? '#166534' : '#991b1b' }}>
              Test Result: {testResult.carrierStatus} ({testResult.httpStatus || 202} ACCEPTED)
            </div>
            <div>Transaction ID: {testResult.transactionId}</div>
            <div>TTBS Request ID: {testResult.ttbsRequestId}</div>
            <div>TTBS Message ID: {testResult.messageId}</div>
            <div>Gateway Status: {testResult.gatewayStatus}</div>
            <div>Carrier Status: {testResult.carrierStatus}</div>
            <div>TTBS Error: {testResult.errorCode || '15019'} - {testResult.errorMessage || 'Account lacks active SMS package/route'}</div>
            <div>Latency: {testResult.latencyMs}ms</div>
          </div>
        )}
      </div>

      {/* Filters */}
      <div className="card" style={{ marginTop: '16px', padding: '16px' }}>
        <div style={{ display: 'flex', gap: '16px', flexWrap: 'wrap' }}>
          <div style={{ flex: 1, minWidth: '240px', position: 'relative' }}>
            <Search size={16} style={{ position: 'absolute', left: '12px', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
            <input 
              type="text" 
              className="form-control" 
              placeholder="Search by Transaction ID, Mobile, Message ID..." 
              value={searchTerm}
              onChange={e => setSearchTerm(e.target.value)}
              style={{ paddingLeft: '36px', width: '100%' }}
            />
          </div>
          <div style={{ width: '220px' }}>
            <select 
              className="form-control" 
              value={statusFilter} 
              onChange={e => setStatusFilter(e.target.value)}
              style={{ width: '100%' }}
            >
              <option value="all">All Delivery States</option>
              <option value="SMS_DELIVERED">SMS Delivered</option>
              <option value="PENDING_CARRIER">Pending Carrier</option>
              <option value="SMS_REJECTED">SMS Rejected (15019)</option>
              <option value="SMS_FAILED">SMS Failed</option>
              <option value="VERIFIED">Verified</option>
            </select>
          </div>
        </div>
      </div>

      {/* Diagnostic Logs Table (Requirement 14) */}
      <div className="card" style={{ marginTop: '16px', overflow: 'hidden' }}>
        <div style={{ overflowX: 'auto' }}>
          <table className="table" style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.85rem' }}>
            <thead>
              <tr style={{ borderBottom: '1px solid var(--border-color)', textAlign: 'left', background: 'var(--table-header-bg, rgba(0,0,0,0.02))' }}>
                <th style={{ padding: '12px 14px' }}>Transaction ID</th>
                <th style={{ padding: '12px 14px' }}>Mobile</th>
                <th style={{ padding: '12px 14px' }}>Created</th>
                <th style={{ padding: '12px 14px' }}>Gateway Status</th>
                <th style={{ padding: '12px 14px' }}>TTBS Message ID</th>
                <th style={{ padding: '12px 14px' }}>Delivery Status</th>
                <th style={{ padding: '12px 14px' }}>TTBS Error Code</th>
                <th style={{ padding: '12px 14px' }}>Error Message</th>
                <th style={{ padding: '12px 14px' }}>Provider</th>
                <th style={{ padding: '12px 14px' }}>Bind</th>
                <th style={{ padding: '12px 14px' }}>Package</th>
                <th style={{ padding: '12px 14px' }}>Last Updated</th>
                <th style={{ padding: '12px 14px' }}>Action</th>
              </tr>
            </thead>
            <tbody>
              {filteredLogs.length === 0 ? (
                <tr>
                  <td colSpan={13} style={{ padding: '32px', textAlign: 'center', color: 'var(--text-muted)' }}>
                    {loading ? 'Loading diagnostic records...' : 'No OTP diagnostic records match your criteria.'}
                  </td>
                </tr>
              ) : (
                filteredLogs.map(item => (
                  <tr key={item._id || item.requestId} style={{ borderBottom: '1px solid var(--border-color)' }}>
                    <td style={{ padding: '12px 14px', fontWeight: 600, fontFamily: 'monospace' }}>
                      {item.transactionId || 'OTP-001'}
                    </td>
                    <td style={{ padding: '12px 14px', fontFamily: 'monospace' }}>
                      {item.mobileMasked}
                    </td>
                    <td style={{ padding: '12px 14px', color: 'var(--text-muted)', fontSize: '0.78rem' }}>
                      {new Date(item.createdAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })}
                    </td>
                    <td style={{ padding: '12px 14px' }}>
                      <span style={{ 
                        color: item.submissionStatus === 'GATEWAY_ACCEPTED' || item.submissionStatus === 'ACCEPTED' ? '#10b981' : '#ef4444',
                        fontWeight: 600
                      }}>
                        {item.submissionStatus}
                      </span>
                    </td>
                    <td style={{ padding: '12px 14px', fontFamily: 'monospace', fontSize: '0.78rem' }}>
                      {item.jobId || item.providerMessageId ? (item.jobId || item.providerMessageId)!.slice(0, 14) + '...' : '—'}
                    </td>
                    <td style={{ padding: '12px 14px' }}>
                      {getDeliveryBadge(item.deliveryStatus || item.status)}
                    </td>
                    <td style={{ padding: '12px 14px', fontFamily: 'monospace', color: item.providerErrorCode ? '#e11d48' : 'inherit' }}>
                      {item.providerErrorCode || '—'}
                    </td>
                    <td style={{ padding: '12px 14px', fontSize: '0.78rem', color: item.failureReason ? '#e11d48' : 'var(--text-muted)', maxWidth: '180px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={item.failureReason || ''}>
                      {item.failureReason || 'None'}
                    </td>
                    <td style={{ padding: '12px 14px', fontSize: '0.78rem' }}>
                      {item.provider || 'ttbs'}
                    </td>
                    <td style={{ padding: '12px 14px', fontSize: '0.78rem', color: 'var(--text-muted)' }}>
                      {item.bind ?? 'null'}
                    </td>
                    <td style={{ padding: '12px 14px', fontSize: '0.78rem', color: 'var(--text-muted)' }}>
                      {item.pkg ?? 'not assigned'}
                    </td>
                    <td style={{ padding: '12px 14px', color: 'var(--text-muted)', fontSize: '0.78rem' }}>
                      {new Date(item.updatedAt || item.createdAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })}
                    </td>
                    <td style={{ padding: '12px 14px' }}>
                      <button 
                        className="btn btn-secondary btn-sm"
                        onClick={() => setSelectedRecord(item)}
                        style={{ padding: '4px 8px', fontSize: '0.78rem' }}
                      >
                        Inspect
                      </button>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Inspect Modal */}
      {selectedRecord && (
        <div style={{
          position: 'fixed',
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          backgroundColor: 'rgba(0,0,0,0.5)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 1000,
          padding: '16px'
        }}>
          <div className="card" style={{ maxWidth: '580px', width: '100%', padding: '24px', borderRadius: '12px' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
              <h3 style={{ margin: 0, display: 'flex', alignItems: 'center', gap: '8px' }}>
                <KeyRound size={20} color="var(--primary)" />
                OTP Transaction Diagnostic Record
              </h3>
              <button 
                onClick={() => setSelectedRecord(null)}
                style={{ background: 'none', border: 'none', cursor: 'pointer', fontSize: '1.2rem' }}
              >
                &times;
              </button>
            </div>

            <div style={{ 
              background: '#0f172a', 
              color: '#f8fafc', 
              padding: '16px', 
              borderRadius: '8px', 
              fontFamily: 'monospace',
              fontSize: '0.85rem',
              lineHeight: '1.7',
              whiteSpace: 'pre-wrap'
            }}>
{`OTP Transaction
------------------------------
Transaction ID:      ${selectedRecord.transactionId || 'OTP-001'}
User Type:           ${selectedRecord.userType || 'Customer'}
Mobile:              ${selectedRecord.mobileMasked}
Gateway:             TTBS Smartflo
Template ID:         ${selectedRecord.templateId || '1677100000000393380'}
Sender / Header:     ${selectedRecord.senderId || 'SADGRL'}
Submitted:           YES
Gateway Status:      ${selectedRecord.submissionStatus}
Gateway Request ID:  ${selectedRecord.requestId}
Message ID:          ${selectedRecord.jobId || selectedRecord.providerMessageId || 'N/A'}
Delivery Status:     ${selectedRecord.deliveryStatus || selectedRecord.status}
TTBS Error Code:     ${selectedRecord.providerErrorCode || 'None'}
Failure Reason:      ${selectedRecord.failureReason || 'None'}
Provider:            ${selectedRecord.provider || 'ttbs'}
Bind:                ${selectedRecord.bind ?? 'null'}
Package:             ${selectedRecord.pkg ?? 'not assigned'}
Verification:        ${selectedRecord.verificationStatus || 'PENDING'}`}
            </div>

            <div style={{ marginTop: '16px', display: 'flex', justifyContent: 'flex-end' }}>
              <button className="btn btn-primary btn-sm" onClick={() => setSelectedRecord(null)}>
                Close
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default OtpDiagnostics;
