import React, { useEffect } from 'react';
import { Sun, Moon, Database, ShieldAlert } from 'lucide-react';
import { useAuth } from '../context/AuthContext';
import { useDatabase } from '../context/DatabaseContext';

export const Topbar: React.FC = () => {
  const { user, activeRole, setActiveRole } = useAuth();
  const { isLive } = useDatabase();
  const [theme, setTheme] = React.useState<'light' | 'dark'>(() => {
    return (localStorage.getItem('theme') as any) || 'dark';
  });

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('theme', theme);
  }, [theme]);

  const toggleTheme = () => {
    setTheme(prev => prev === 'light' ? 'dark' : 'light');
  };

  const handleRoleChange = (e: React.ChangeEvent<HTMLSelectElement>) => {
    setActiveRole(e.target.value as any);
  };

  // Human readable role names
  const roleNames = {
    super_admin: 'Super Admin',
    admin: 'Operations Admin',
    support: 'Support Executive',
    finance: 'Finance Manager',
  };

  return (
    <header className="topbar">
      <div className="sync-status">
        <div className={`indicator ${isLive ? 'indicator-live' : 'indicator-demo'}`} />
        <span style={{ fontSize: '13px', fontWeight: 600 }}>
          {isLive ? 'Live Firestore Database Active' : 'Simulation Mode (Sandbox)'}
        </span>
      </div>

      <div className="topbar-actions">
        {/* Role Simulator - Visible to Super Admins only, or for testing/demo */}
        {user?.role === 'super_admin' && (
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <span style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: 500 }}>
              Test Role View:
            </span>
            <select 
              value={activeRole || 'super_admin'} 
              onChange={handleRoleChange}
              style={{ padding: '4px 8px', fontSize: '12px', borderRadius: '6px' }}
            >
              <option value="super_admin">Super Admin (All)</option>
              <option value="admin">Operations Admin</option>
              <option value="support">Support Executive</option>
              <option value="finance">Finance Manager</option>
            </select>
          </div>
        )}

        <div className={`role-badge badge-${activeRole}`}>
          {activeRole ? roleNames[activeRole] : ''}
        </div>

        {/* Theme Toggle Button */}
        <button 
          className="btn btn-secondary btn-icon" 
          onClick={toggleTheme} 
          title="Toggle Light/Dark Theme"
          style={{ width: '36px', height: '36px', display: 'flex', alignItems: 'center', justifyContent: 'center' }}
        >
          {theme === 'light' ? <Sun size={18} /> : <Moon size={18} />}
        </button>

        <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
          <div style={{ 
            width: '32px', 
            height: '32px', 
            borderRadius: '50%', 
            backgroundColor: 'var(--primary)', 
            color: '#fff', 
            display: 'flex', 
            alignItems: 'center', 
            justifyContent: 'center',
            fontSize: '14px',
            fontWeight: 700
          }}>
            {user?.name.charAt(0)}
          </div>
        </div>
      </div>
    </header>
  );
};
export default Topbar;
