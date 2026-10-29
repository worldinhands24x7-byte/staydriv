import React, { useEffect, useState } from 'react';
import { Sun, Moon, Database, ShieldAlert, Navigation, Smartphone, ExternalLink } from 'lucide-react';
import { useAuth } from '../context/AuthContext';
import { useDatabase } from '../context/DatabaseContext';
import GlobalSearch from './GlobalSearch';

export const Topbar: React.FC = () => {
  const { user, activeRole, setActiveRole } = useAuth();
  const { isLive } = useDatabase();
  const [liveRidersCount, setLiveRidersCount] = useState<number>(0);
  const [theme, setTheme] = React.useState<'light' | 'dark'>(() => {
    return (localStorage.getItem('theme') as any) || 'dark';
  });

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('theme', theme);
  }, [theme]);

  // Periodic polling & sync of live riders count
  useEffect(() => {
    const fetchLiveCount = async () => {
      try {
        const backendBase = (window as any).REACT_APP_BACKEND_URL || 
          ((window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1')
            ? `${window.location.protocol}//${window.location.hostname}:3000`
            : window.location.origin);
        const res = await fetch(`${backendBase}/api/admin/live-riders`, {
          headers: { 'x-admin-key': 'staydriv_admin_secret_2026' }
        });
        if (res.ok) {
          const data = await res.json();
          if (data.success && typeof data.liveRidersCount === 'number') {
            setLiveRidersCount(data.liveRidersCount);
          }
        }
      } catch (_) {}
    };

    fetchLiveCount();
    const interval = setInterval(fetchLiveCount, 8000);
    return () => clearInterval(interval);
  }, []);

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
      <div style={{ display: 'flex', alignItems: 'center', gap: '14px', flexWrap: 'wrap' }}>
        <div className="sync-status">
          <div 
            className={`indicator ${isLive ? 'indicator-live' : 'indicator-demo'}`}
            style={!isLive ? { backgroundColor: '#ef4444', boxShadow: 'none' } : undefined}
          />
          <span style={{ fontSize: '13px', fontWeight: 600, color: isLive ? 'inherit' : '#ef4444' }}>
            {isLive ? 'Live Database Active' : 'Database Disconnected'}
          </span>
        </div>

        {/* Live Riders Live Indicator */}
        <div 
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '8px',
            padding: '4px 12px',
            borderRadius: '20px',
            backgroundColor: 'rgba(16, 185, 129, 0.12)',
            border: '1px solid rgba(16, 185, 129, 0.35)',
            boxShadow: '0 1px 3px rgba(16, 185, 129, 0.1)'
          }}
          title="Current number of active pilots transmitting real-time GPS locations"
        >
          <div 
            className="live-pulse-dot"
            style={{
              width: '8px',
              height: '8px',
              borderRadius: '50%',
              backgroundColor: '#10b981',
              boxShadow: '0 0 8px #10b981'
            }} 
          />
          <span style={{ fontSize: '12px', fontWeight: 700, color: '#10b981', display: 'flex', alignItems: 'center', gap: '4px' }}>
            <Navigation size={12} />
            Live Riders: {liveRidersCount}
          </span>
        </div>

        {/* Quick App Interlinks for Admin */}
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginLeft: '6px' }}>
          <a
            href="http://localhost:3000/customer"
            target="_blank"
            rel="noopener noreferrer"
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: '5px',
              padding: '4px 10px',
              borderRadius: '8px',
              fontSize: '11px',
              fontWeight: 700,
              backgroundColor: 'rgba(37, 99, 235, 0.12)',
              color: '#3b82f6',
              border: '1px solid rgba(59, 130, 246, 0.35)',
              textDecoration: 'none',
              cursor: 'pointer',
            }}
            title="Open StayDriv Customer App in new tab"
          >
            <Smartphone size={13} />
            Customer App
          </a>
          <a
            href="http://localhost:3000/pilot"
            target="_blank"
            rel="noopener noreferrer"
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: '5px',
              padding: '4px 10px',
              borderRadius: '8px',
              fontSize: '11px',
              fontWeight: 700,
              backgroundColor: 'rgba(16, 185, 129, 0.12)',
              color: '#10b981',
              border: '1px solid rgba(16, 185, 129, 0.35)',
              textDecoration: 'none',
              cursor: 'pointer',
            }}
            title="Open StayDriv Pilot Partner App in new tab"
          >
            <Navigation size={13} />
            Pilot App
          </a>
          <a
            href="http://localhost:3000/split.html"
            target="_blank"
            rel="noopener noreferrer"
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: '5px',
              padding: '4px 10px',
              borderRadius: '8px',
              fontSize: '11px',
              fontWeight: 700,
              backgroundColor: 'rgba(245, 158, 11, 0.12)',
              color: '#f59e0b',
              border: '1px solid rgba(245, 158, 11, 0.35)',
              textDecoration: 'none',
              cursor: 'pointer',
            }}
            title="Open Dual Split Simulator (Customer + Pilot side by side)"
          >
            <ExternalLink size={13} />
            Dual View
          </a>
        </div>
      </div>

      {/* Global Search Bar */}
      <GlobalSearch />

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
