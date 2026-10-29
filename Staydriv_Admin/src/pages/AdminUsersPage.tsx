import React, { useState } from 'react';
import { useAuth, UserRole } from '../context/AuthContext';
import { 
  ShieldCheck, CheckCircle2 
} from 'lucide-react';

interface RolePermissionDef {
  role: UserRole;
  title: string;
  badgeColor: string;
  description: string;
  permissions: string[];
}

const ROLE_DEFINITIONS: RolePermissionDef[] = [
  {
    role: 'super_admin',
    title: 'Super Admin / Founder',
    badgeColor: 'var(--safety-yellow)',
    description: 'Full unconstrained platform control, bank approvals, commission schedules, founder payouts, and system configuration.',
    permissions: [
      'Full Database Access',
      'Approve & Execute Pilot Withdrawals',
      'Authorize Founder Distributions',
      'Modify Commission Schedules',
      'View & Audit Financial Ledger',
      'Block / Unblock Any User',
      'Manage System Integration Keys'
    ]
  },
  {
    role: 'finance',
    title: 'Finance Administrator',
    badgeColor: 'var(--primary)',
    description: 'Specialized financial controller for ledger audits, payout approvals, gateway settlements, and tax reconciliation.',
    permissions: [
      'Review & Approve Pilot Withdrawals',
      'View & Export Financial Ledger',
      'View Founder Financial Dashboard',
      'Verify Bank Settlements & UTRs',
      'Process Refund Requests',
      'Audit Gateway Fees & GST Taxes'
    ]
  },
  {
    role: 'admin',
    title: 'Operations Administrator',
    badgeColor: '#10b981',
    description: 'Day-to-day fleet operations, pilot KYC verification, active ride tracking, and dispatch interventions.',
    permissions: [
      'KYC Verify Pilot Documents',
      'Reassign Drivers on Stalled Bookings',
      'Monitor Live GPS Tracking Map',
      'Investigate Driver Conduct & Block',
      'Manage Promos & Notifications',
      'View Operations Analytics'
    ]
  },
  {
    role: 'support',
    title: 'Customer & Pilot Support',
    badgeColor: '#06b6d4',
    description: 'Customer service desk, grievance handling, call mask diagnostics, and trip inspection.',
    permissions: [
      'View Customer & Pilot Profiles',
      'Inspect Call Masking & Direct Dial Logs',
      'Inspect OTP Delivery Diagnostics',
      'Reply to Support Tickets',
      'Read-Only Access to Rides & Deliveries',
      'Log Customer Complaints'
    ]
  }
];

export const AdminUsersPage: React.FC = () => {
  const { user, activeRole, switchRole } = useAuth();
  const [selectedRole, setSelectedRole] = useState<UserRole>(activeRole || 'super_admin');
  const [successMsg, setSuccessMsg] = useState('');

  const handleRoleChange = (role: UserRole) => {
    setSelectedRole(role);
    switchRole(role);
    setSuccessMsg(`Active session privileges successfully updated to ${role.toUpperCase()}`);
    setTimeout(() => setSuccessMsg(''), 3000);
  };

  return (
    <div className="page-container">
      {/* Top Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '16px' }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <h2>Admin Users &amp; Role-Based Access Control (RBAC)</h2>
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
              <ShieldCheck size={12} />
              GRANULAR PRIVILEGES ACTIVE
            </span>
          </div>
          <p style={{ color: 'var(--text-muted)', fontSize: '13px', marginTop: '4px' }}>
            Multi-tier role management isolating financial payout authorization from daily support operations.
          </p>
        </div>
      </div>

      {successMsg && (
        <div style={{ 
          background: 'rgba(16, 185, 129, 0.1)', 
          color: 'var(--success)', 
          padding: '12px 16px', 
          borderRadius: '6px', 
          fontSize: '13px' 
        }}>
          ✓ {successMsg}
        </div>
      )}

      {/* Current Operator Card */}
      <div className="card" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '16px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
          <div style={{ 
            width: '48px', 
            height: '48px', 
            borderRadius: '50%', 
            background: 'var(--primary)', 
            display: 'flex', 
            alignItems: 'center', 
            justifyContent: 'center',
            color: '#fff',
            fontWeight: 700,
            fontSize: '18px'
          }}>
            {user?.name ? user.name[0].toUpperCase() : 'A'}
          </div>
          <div>
            <div style={{ fontWeight: 700, fontSize: '16px' }}>{user?.name || 'Administrator'}</div>
            <div style={{ color: 'var(--text-muted)', fontSize: '12px' }}>{user?.email || 'admin@staydriv.com'} • {user?.phone || '+91 9999999999'}</div>
          </div>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          <span style={{ fontSize: '13px', color: 'var(--text-muted)' }}>Current Role:</span>
          <span className="badge" style={{ 
            background: 'rgba(59,130,246,0.15)', 
            color: 'var(--primary)', 
            fontSize: '12px', 
            fontWeight: 700,
            padding: '4px 12px'
          }}>
            {activeRole ? activeRole.toUpperCase() : 'SUPER_ADMIN'}
          </span>
        </div>
      </div>

      {/* Role Definitions Grid */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: '20px' }}>
        {ROLE_DEFINITIONS.map(def => {
          const isCurrent = activeRole === def.role;
          return (
            <div 
              key={def.role} 
              className="card" 
              style={{ 
                border: isCurrent ? '2px solid var(--primary)' : '1px solid var(--border)',
                display: 'flex',
                flexDirection: 'column',
                justifyContent: 'space-between'
              }}
            >
              <div>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '10px' }}>
                  <h3 style={{ fontSize: '16px' }}>{def.title}</h3>
                  {isCurrent && (
                    <span className="badge badge-success" style={{ fontSize: '10px' }}>ACTIVE</span>
                  )}
                </div>
                <p style={{ color: 'var(--text-muted)', fontSize: '12px', marginBottom: '16px', lineHeight: '1.4' }}>
                  {def.description}
                </p>

                <h4 style={{ fontSize: '12px', textTransform: 'uppercase', color: 'var(--text-muted)', marginBottom: '8px' }}>
                  Granted Privileges:
                </h4>
                <ul style={{ listStyle: 'none', padding: 0, margin: 0, display: 'flex', flexDirection: 'column', gap: '6px' }}>
                  {def.permissions.map((p, idx) => (
                    <li key={idx} style={{ fontSize: '12px', display: 'flex', alignItems: 'center', gap: '6px' }}>
                      <CheckCircle2 size={13} style={{ color: 'var(--success)', flexShrink: 0 }} />
                      <span>{p}</span>
                    </li>
                  ))}
                </ul>
              </div>

              <div style={{ marginTop: '20px', paddingTop: '14px', borderTop: '1px solid var(--border)' }}>
                <button 
                  className={`btn ${isCurrent ? 'btn-secondary' : 'btn-primary'}`}
                  onClick={() => handleRoleChange(def.role)}
                  disabled={isCurrent}
                  style={{ width: '100%', fontSize: '12px' }}
                >
                  {isCurrent ? 'Active Role Session' : `Switch Role to ${def.title}`}
                </button>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};

export default AdminUsersPage;
