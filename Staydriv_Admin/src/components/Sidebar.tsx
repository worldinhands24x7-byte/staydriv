import React from 'react';
import { 
  LayoutDashboard, Users, UserCheck, Map, Car, Truck, 
  CreditCard, Tag, Bell, MessageSquare, FileText, Settings, LogOut 
} from 'lucide-react';
import { useAuth } from '../context/AuthContext';

interface SidebarProps {
  currentTab: string;
  setCurrentTab: (tab: string) => void;
}

export const Sidebar: React.FC<SidebarProps> = ({ currentTab, setCurrentTab }) => {
  const { logout, activeRole, user } = useAuth();

  const menuItems = [
    { id: 'dashboard', label: 'Dashboard', icon: LayoutDashboard, roles: ['super_admin', 'admin', 'support', 'finance'] },
    { id: 'customers', label: 'Customers', icon: Users, roles: ['super_admin', 'admin', 'support'] },
    { id: 'partners', label: 'Pilot Verification', icon: UserCheck, roles: ['super_admin', 'admin'] },
    { id: 'tracking', label: 'Live Tracking Map', icon: Map, roles: ['super_admin', 'admin', 'support'] },
    { id: 'rides', label: 'Ride Bookings', icon: Car, roles: ['super_admin', 'admin', 'support'] },
    { id: 'deliveries', label: 'Goods Deliveries', icon: Truck, roles: ['super_admin', 'admin', 'support'] },
    { id: 'finance', label: 'Payments & Finance', icon: CreditCard, roles: ['super_admin', 'finance'] },
    { id: 'promos', label: 'Promo Codes', icon: Tag, roles: ['super_admin', 'admin'] },
    { id: 'notifications', label: 'Push Notifications', icon: Bell, roles: ['super_admin', 'admin'] },
    { id: 'support', label: 'Support Tickets', icon: MessageSquare, roles: ['super_admin', 'admin', 'support'] },
    { id: 'reports', label: 'Reports Export', icon: FileText, roles: ['super_admin', 'admin', 'finance'] },
    { id: 'settings', label: 'System Settings', icon: Settings, roles: ['super_admin'] },
  ];

  const filteredItems = menuItems.filter(item => activeRole && item.roles.includes(activeRole));

  return (
    <aside className="sidebar">
      <div className="sidebar-header">
        <div className="sidebar-logo">StayDriv Admin</div>
      </div>
      <ul className="sidebar-menu">
        {filteredItems.map(item => {
          const Icon = item.icon;
          return (
            <li key={item.id}>
              <a 
                href={`#${item.id}`}
                className={`sidebar-item-link ${currentTab === item.id ? 'active' : ''}`}
                onClick={(e) => {
                  e.preventDefault();
                  setCurrentTab(item.id);
                }}
              >
                <Icon size={18} />
                <span>{item.label}</span>
              </a>
            </li>
          );
        })}
      </ul>
      <div className="sidebar-footer">
        <div>Logged in as:</div>
        <div style={{ color: '#fff', fontWeight: 600, overflow: 'hidden', textOverflow: 'ellipsis' }}>{user?.name}</div>
        <button 
          className="btn btn-secondary btn-sm" 
          onClick={logout}
          style={{ width: '100%', marginTop: '8px', display: 'flex', gap: '8px', justifyContent: 'center' }}
        >
          <LogOut size={14} />
          <span>Sign Out</span>
        </button>
      </div>
    </aside>
  );
};
export default Sidebar;
