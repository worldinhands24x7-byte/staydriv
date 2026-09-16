import React, { useState } from 'react';
import { AuthProvider, useAuth } from './context/AuthContext';
import { DatabaseProvider, useDatabase } from './context/DatabaseContext';
import Sidebar from './components/Sidebar';
import Topbar from './components/Topbar';
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';
import Customers from './pages/Customers';
import Partners from './pages/Partners';
import LiveTracking from './pages/LiveTracking';
import Rides from './pages/Rides';
import Deliveries from './pages/Deliveries';
import Finance from './pages/Finance';
import Promos from './pages/Promos';
import Notifications from './pages/Notifications';
import Support from './pages/Support';
import Reports from './pages/Reports';
import Settings from './pages/Settings';
import './index.css';

const AppContent: React.FC = () => {
  const { user, activeRole, loading } = useAuth();
  const { isOnline } = useDatabase();
  const [currentTab, setCurrentTab] = useState('dashboard');

  if (loading) {
    return (
      <div style={{ 
        height: '100vh', 
        display: 'flex', 
        alignItems: 'center', 
        justifyContent: 'center',
        background: 'var(--bg-main)',
        color: 'var(--text-main)'
      }}>
        <h2>StayDriv Security Validation...</h2>
      </div>
    );
  }

  if (!user) {
    return <Login />;
  }

  // Double check role-based access for the current page
  // If the user's role is not authorized for the current tab, revert to dashboard
  const isAuthorized = (tab: string): boolean => {
    if (!activeRole) return false;
    
    // Role permissions mapping
    const permissions: Record<string, string[]> = {
      dashboard: ['super_admin', 'admin', 'support', 'finance'],
      customers: ['super_admin', 'admin', 'support'],
      partners: ['super_admin', 'admin'],
      tracking: ['super_admin', 'admin', 'support'],
      rides: ['super_admin', 'admin', 'support'],
      deliveries: ['super_admin', 'admin', 'support'],
      finance: ['super_admin', 'finance'],
      promos: ['super_admin', 'admin'],
      notifications: ['super_admin', 'admin'],
      support: ['super_admin', 'admin', 'support'],
      reports: ['super_admin', 'admin', 'finance'],
      settings: ['super_admin']
    };

    return permissions[tab]?.includes(activeRole) || false;
  };

  const renderTab = () => {
    // Safety check
    const tabToRender = isAuthorized(currentTab) ? currentTab : 'dashboard';
    
    switch (tabToRender) {
      case 'dashboard': return <Dashboard />;
      case 'customers': return <Customers />;
      case 'partners': return <Partners />;
      case 'tracking': return <LiveTracking />;
      case 'rides': return <Rides />;
      case 'deliveries': return <Deliveries />;
      case 'finance': return <Finance />;
      case 'promos': return <Promos />;
      case 'notifications': return <Notifications />;
      case 'support': return <Support />;
      case 'reports': return <Reports />;
      case 'settings': return <Settings />;
      default: return <Dashboard />;
    }
  };

  return (
    <div className="app-container">
      <Sidebar currentTab={currentTab} setCurrentTab={setCurrentTab} />
      <div className="main-content">
        <Topbar />
        {!isOnline && (
          <div style={{
            backgroundColor: 'var(--error-bg, #fee2e2)',
            color: 'var(--error, #ef4444)',
            borderBottom: '1px solid rgba(239, 68, 68, 0.2)',
            padding: '10px 24px',
            fontSize: '13px',
            fontWeight: '600',
            display: 'flex',
            alignItems: 'center',
            gap: '8px',
            zIndex: 9
          }}>
            <span style={{ fontSize: '16px' }}>⚠️</span>
            <span>StayDriv System Offline: Operating in local cache mode. Data will auto-sync when network returns.</span>
          </div>
        )}
        {renderTab()}
      </div>
    </div>
  );
};

export const App: React.FC = () => {
  return (
    <AuthProvider>
      <DatabaseProvider>
        <AppContent />
      </DatabaseProvider>
    </AuthProvider>
  );
};

export default App;
