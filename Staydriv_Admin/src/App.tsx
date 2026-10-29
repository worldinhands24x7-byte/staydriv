import React, { useState } from 'react';
import { AuthProvider, useAuth } from './context/AuthContext';
import { DatabaseProvider, useDatabase } from './context/DatabaseContext';
import Sidebar from './components/Sidebar';
import Topbar from './components/Topbar';
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';
import Customers from './pages/Customers';
import Partners from './pages/Partners';
import PilotManagement from './pages/PilotManagement';
import LiveTracking from './pages/LiveTracking';
import Rides from './pages/Rides';
import Deliveries from './pages/Deliveries';
import FoodOrdersRestaurants from './pages/FoodOrdersRestaurants';
import FoodMembershipManagement from './pages/FoodMembershipManagement';
import DailyPilotPlanPayments from './pages/DailyPilotPlanPayments';
import PilotWithdrawals from './pages/PilotWithdrawals';
import FounderCommission from './pages/FounderCommission';
import FinancialLedger from './pages/FinancialLedger';
import GatewaySettlements from './pages/GatewaySettlements';
import CallLogs from './pages/CallLogs';
import OtpDiagnostics from './pages/OtpDiagnostics';
import RefundsDisputes from './pages/RefundsDisputes';
import Promos from './pages/Promos';
import Notifications from './pages/Notifications';
import ReportsExports from './pages/ReportsExports';
import SharePromote from './pages/SharePromote';
import AdminUsersPage from './pages/AdminUsersPage';
import Settings from './pages/Settings';
import './index.css';

const AppContent: React.FC = () => {
  const { user, activeRole, loading } = useAuth();
  const { isOnline } = useDatabase();
  const [currentTab, setCurrentTab] = useState<string>(() => {
    const hash = window.location.hash.replace('#', '');
    return hash || 'dashboard';
  });

  React.useEffect(() => {
    const handleHash = () => {
      const hash = window.location.hash.replace('#', '');
      if (hash) setCurrentTab(hash);
    };
    window.addEventListener('hashchange', handleHash);
    return () => window.removeEventListener('hashchange', handleHash);
  }, []);

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
  const isAuthorized = (tab: string): boolean => {
    if (!activeRole) return false;
    
    // Role permissions mapping
    const permissions: Record<string, string[]> = {
      'dashboard': ['super_admin', 'admin', 'support', 'finance'],
      'tracking': ['super_admin', 'admin', 'support'],
      'pilot-management': ['super_admin', 'admin'],
      'daily-pilot-plan': ['super_admin', 'admin', 'finance', 'support'],
      'partners': ['super_admin', 'admin'],
      'customers': ['super_admin', 'admin', 'support'],
      'rides': ['super_admin', 'admin', 'support'],
      'deliveries': ['super_admin', 'admin', 'support'],
      'food-orders': ['super_admin', 'admin', 'support', 'finance'],
      'food-membership': ['super_admin', 'admin', 'support', 'finance'],
      'withdrawals': ['super_admin', 'finance'],
      'founder-commission': ['super_admin', 'finance'],
      'ledger': ['super_admin', 'finance'],
      'gateway-settlements': ['super_admin', 'finance'],
      'calls': ['super_admin', 'admin', 'support'],
      'otp-logs': ['super_admin', 'admin', 'support'],
      'disputes': ['super_admin', 'admin', 'support', 'finance'],
      'customer-banners': ['super_admin', 'admin'],
      'promos': ['super_admin', 'admin'],
      'notifications': ['super_admin', 'admin'],
      'reports': ['super_admin', 'admin', 'finance'],
      'share-promote': ['super_admin', 'admin', 'finance', 'support'],
      'admin-users': ['super_admin', 'admin', 'finance', 'support'],
      'settings': ['super_admin']
    };

    return permissions[tab]?.includes(activeRole) || false;
  };

  const renderTab = () => {
    const tabToRender = isAuthorized(currentTab) ? currentTab : 'dashboard';
    
    switch (tabToRender) {
      case 'dashboard': return <Dashboard />;
      case 'tracking': return <LiveTracking />;
      case 'pilot-management': return <PilotManagement />;
      case 'daily-pilot-plan': return <DailyPilotPlanPayments />;
      case 'partners': return <Partners />;
      case 'customers': return <Customers />;
      case 'rides': return <Rides />;
      case 'deliveries': return <Deliveries />;
      case 'food-orders': return <FoodOrdersRestaurants />;
      case 'food-membership': return <FoodMembershipManagement />;
      case 'withdrawals': return <PilotWithdrawals />;
      case 'founder-commission': return <FounderCommission />;
      case 'ledger': return <FinancialLedger />;
      case 'gateway-settlements': return <GatewaySettlements />;
      case 'calls': return <CallLogs />;
      case 'otp-logs': return <OtpDiagnostics />;
      case 'disputes': return <RefundsDisputes />;
      case 'customer-banners': return <Promos initialTab="banners" />;
      case 'promos': return <Promos initialTab="coupons" />;
      case 'notifications': return <Notifications />;
      case 'reports': return <ReportsExports />;
      case 'share-promote': return <SharePromote />;
      case 'admin-users': return <AdminUsersPage />;
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
