import React, { useState, useEffect } from 'react';
import { useDatabase } from '../context/DatabaseContext';
import { 
  FileText, Search, RefreshCw, Download, 
  ShieldCheck, UserCheck, Lock, Activity 
} from 'lucide-react';

export const AuditLogsPage: React.FC = () => {
  const [logs, setLogs] = useState<any[]>([]);
  const [searchTerm, setSearchTerm] = useState('');
  const [actionFilter, setActionFilter] = useState('all');
  const [isLoading, setIsLoading] = useState(false);

  const backendUrl = (window as any).REACT_APP_BACKEND_URL || 
    (window.location.port === '5173' ? 'http://localhost:3000' : window.location.origin);

  const token = localStorage.getItem('staydriv_admin_token') || 'staydriv_admin_secret_2026';
  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${token}`,
    'x-admin-key': 'staydriv_admin_secret_2026'
  };

  const fetchLogs = async () => {
    setIsLoading(true);
    try {
      const res = await fetch(`${backendUrl}/api/admin/audit-logs`, { headers });
      const data = await res.json();
      if (data.success && Array.isArray(data.auditLogs)) {
        setLogs(data.auditLogs);
      }
    } catch (err) {
      console.warn('Error fetching audit logs:', err);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchLogs();
  }, []);

  const filteredLogs = logs.filter(l => {
    const matchesSearch = 
      (l.adminName || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (l.adminId || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (l.action || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (l.targetName || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (l.targetId || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (l.reason || '').toLowerCase().includes(searchTerm.toLowerCase());

    const matchesAction = actionFilter === 'all' || (l.action || '').includes(actionFilter.toUpperCase());
    return matchesSearch && matchesAction;
  });

  return (
    <div className="page-container">
      {/* Top Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '16px' }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <h2>Administrative Audit Trail & Security Logs</h2>
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
              IMMUTABLE TAMPER-PROOF TRAIL
            </span>
          </div>
          <p style={{ color: 'var(--text-muted)', fontSize: '13px', marginTop: '4px' }}>
            Comprehensive log of all admin operations: pilot verifications, blocks, payout approvals, rate changes, and ticket resolutions.
          </p>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          <button className="btn btn-secondary btn-sm" onClick={fetchLogs} disabled={isLoading}>
            <RefreshCw size={14} className={isLoading ? 'animate-spin' : ''} />
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
                placeholder="Search admin, action, target user, target ID, reason..."
                value={searchTerm}
                onChange={e => setSearchTerm(e.target.value)}
                className="input"
                style={{ paddingLeft: '36px', width: '100%' }}
              />
            </div>

            <select 
              value={actionFilter} 
              onChange={e => setActionFilter(e.target.value)}
              className="input"
              style={{ width: '180px' }}
            >
              <option value="all">All Action Types</option>
              <option value="PILOT">Pilot Approvals / Blocks</option>
              <option value="CUSTOMER">Customer Blocks</option>
              <option value="WITHDRAWAL">Withdrawal Actions</option>
              <option value="COMMISSION">Commission Changes</option>
              <option value="COMPLAINT">Complaint Resolutions</option>
            </select>
          </div>

          <span style={{ fontSize: '13px', color: 'var(--text-muted)' }}>
            Showing <strong>{filteredLogs.length}</strong> of <strong>{logs.length}</strong> recorded audit events
          </span>
        </div>
      </div>

      {/* Audit Log Table */}
      <div className="card" style={{ padding: '0', overflow: 'hidden' }}>
        <div className="table-responsive">
          <table className="data-table" style={{ fontSize: '12px' }}>
            <thead>
              <tr>
                <th>Timestamp</th>
                <th>Admin Operator</th>
                <th>Action Performed</th>
                <th>Target User / Subject</th>
                <th>Reason / Justification</th>
                <th>State Transition</th>
              </tr>
            </thead>
            <tbody>
              {filteredLogs.length === 0 ? (
                <tr>
                  <td colSpan={6} style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>
                    No audit records found matching criteria.
                  </td>
                </tr>
              ) : (
                filteredLogs.map((l, idx) => (
                  <tr key={l._id || idx}>
                    <td>
                      <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                        {l.timestamp ? new Date(l.timestamp).toLocaleString() : 'N/A'}
                      </span>
                    </td>
                    <td>
                      <div style={{ fontWeight: 600 }}>{l.adminName || 'Admin'}</div>
                      <div style={{ fontSize: '10px', color: 'var(--text-muted)' }}>ID: {l.adminId}</div>
                    </td>
                    <td>
                      <span className="badge badge-primary" style={{ fontSize: '10px' }}>
                        {l.action}
                      </span>
                    </td>
                    <td>
                      <div style={{ fontWeight: 600 }}>{l.targetName || l.targetId || 'N/A'}</div>
                      <div style={{ fontSize: '10px', color: 'var(--text-muted)' }}>{l.targetType} {l.targetPhone ? `(${l.targetPhone})` : ''}</div>
                    </td>
                    <td>
                      <span style={{ fontSize: '11px', color: 'var(--text-main)' }}>
                        {l.reason || 'None specified'}
                      </span>
                    </td>
                    <td>
                      {l.newState ? (
                        <span style={{ 
                          fontFamily: 'monospace', 
                          fontSize: '10px', 
                          background: 'rgba(255,255,255,0.04)', 
                          padding: '2px 6px', 
                          borderRadius: '4px' 
                        }}>
                          {JSON.stringify(l.newState)}
                        </span>
                      ) : (
                        <span style={{ color: 'var(--text-muted)' }}>N/A</span>
                      )}
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

export default AuditLogsPage;
