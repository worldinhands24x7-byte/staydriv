import React from 'react';
import { 
  LayoutDashboard, Users, UserCheck, Map, Car, Truck, 
  WalletCards, TrendingUp, BookOpen, Building2, PhoneCall, KeyRound,
  AlertTriangle, Tag, Bell, FileText, ShieldCheck, Settings, LogOut, Share2, UtensilsCrossed, Sparkles, Image as ImageIcon, CreditCard 
} from 'lucide-react';
import { useAuth } from '../context/AuthContext';
import { useDatabase } from '../context/DatabaseContext';

interface SidebarProps {
  currentTab: string;
  setCurrentTab: (tab: string) => void;
}

interface MenuItem {
  id: string;
  label: string;
  icon: any;
  roles: string[];
  section?: string;
  badge?: string;
}

export const Sidebar: React.FC<SidebarProps> = ({ currentTab, setCurrentTab }) => {
  const { logout, activeRole, user } = useAuth();
  const { partners } = useDatabase();
  const pendingApprovalsCount = (partners || []).filter(p => {
    if (p.approved || (p as any).isApproved) return false;
    const s = String(p.status || '').toUpperCase();
    return s === 'PENDING' || s === 'PENDING_VERIFICATION' || s === 'SUBMITTED' || s === 'UNDER_REVIEW' || s === 'ACTION_REQUIRED' || s === 'RESUBMISSION_REQUIRED' || s === 'DRAFT' || !p.status;
  }).length;

  const menuSections: { title: string; items: MenuItem[] }[] = [
    {
      title: 'FLEET & OPERATIONS',
      items: [
        { id: 'dashboard', label: '1. Real-Time Dashboard', icon: LayoutDashboard, roles: ['super_admin', 'admin', 'support', 'finance'] },
        { id: 'tracking', label: '2. Live Operations / Tracking', icon: Map, roles: ['super_admin', 'admin', 'support'] },
        { id: 'pilot-management', label: '3. Pilot Management', icon: Users, roles: ['super_admin', 'admin'] },
        { id: 'daily-pilot-plan', label: '3b. Daily ₹20 Pilot Plan Payments', icon: CreditCard, roles: ['super_admin', 'admin', 'finance', 'support'] },
        { id: 'partners', label: '4. Pilot Verification', icon: UserCheck, roles: ['super_admin', 'admin'] },
        { id: 'customers', label: '5. Customer Management', icon: Users, roles: ['super_admin', 'admin', 'support'] },
        { id: 'rides', label: '6. Ride Bookings', icon: Car, roles: ['super_admin', 'admin', 'support'] },
        { id: 'deliveries', label: '7. Delivery Bookings', icon: Truck, roles: ['super_admin', 'admin', 'support'] },
        { id: 'food-orders', label: '8. Food Orders & Restaurants', icon: UtensilsCrossed, roles: ['super_admin', 'admin', 'support', 'finance'] },
        { id: 'food-membership', label: '8b. Food Membership', icon: Sparkles, roles: ['super_admin', 'admin', 'finance', 'support'] },
      ]
    },
    {
      title: 'FINANCE & TREASURY',
      items: [
        { id: 'withdrawals', label: '8. Pilot Wallet & Withdrawals', icon: WalletCards, roles: ['super_admin', 'finance'] },
        { id: 'founder-commission', label: '9. Founder Commission', icon: TrendingUp, roles: ['super_admin', 'finance'] },
        { id: 'ledger', label: '10. Financial Ledger', icon: BookOpen, roles: ['super_admin', 'finance'] },
        { id: 'gateway-settlements', label: '11. Gateway Settlements', icon: Building2, roles: ['super_admin', 'finance'] },
      ]
    },
    {
      title: 'SUPPORT & TELEMETRY',
      items: [
        { id: 'calls', label: '12. Call Logs', icon: PhoneCall, roles: ['super_admin', 'admin', 'support'] },
        { id: 'otp-logs', label: '13. OTP Diagnostics', icon: KeyRound, roles: ['super_admin', 'admin', 'support'] },
        { id: 'disputes', label: '14. Refunds & Disputes', icon: AlertTriangle, roles: ['super_admin', 'admin', 'support', 'finance'] },
      ]
    },
    {
      title: 'GROWTH & GOVERNANCE',
      items: [
        { id: 'customer-banners', label: '15. Customer App Banners', icon: ImageIcon, roles: ['super_admin', 'admin'] },
        { id: 'promos', label: '15b. Promos & Coupons', icon: Tag, roles: ['super_admin', 'admin'] },
        { id: 'notifications', label: '16. Notifications & Alerts', icon: Bell, roles: ['super_admin', 'admin'] },
        { id: 'reports', label: '17. Reports & Exports', icon: FileText, roles: ['super_admin', 'admin', 'finance'] },
        { id: 'share-promote', label: '18. Share & Promote StayDriv', icon: Share2, roles: ['super_admin', 'admin', 'finance', 'support'] },
        { id: 'admin-users', label: '19. Admin Users & Roles', icon: ShieldCheck, roles: ['super_admin', 'admin', 'finance', 'support'] },
        { id: 'settings', label: '20. Settings & Config', icon: Settings, roles: ['super_admin'] },
      ]
    }
  ];

  return (
    <aside className="sidebar" style={{ width: '275px' }}>
      <div className="sidebar-header" style={{ padding: '16px 20px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
          <div className="sidebar-logo">StayDriv</div>
          <span style={{ 
            fontSize: '10px', 
            fontWeight: 800, 
            background: 'var(--safety-yellow)', 
            color: '#000', 
            padding: '2px 6px', 
            borderRadius: '4px',
            letterSpacing: '0.5px' 
          }}>
            PRO
          </span>
        </div>
      </div>

      <div className="sidebar-menu" style={{ padding: '12px 10px' }}>
        {menuSections.map((section, sIdx) => {
          const visibleItems = section.items.filter(item => activeRole && item.roles.includes(activeRole));
          if (visibleItems.length === 0) return null;

          return (
            <div key={sIdx} style={{ marginBottom: '14px' }}>
              <div style={{ 
                fontSize: '10px', 
                fontWeight: 700, 
                color: '#64748b', 
                letterSpacing: '0.8px', 
                padding: '6px 12px',
                textTransform: 'uppercase'
              }}>
                {section.title}
              </div>

              {visibleItems.map(item => {
                const Icon = item.icon;
                const isActive = currentTab === item.id;
                return (
                  <a 
                    key={item.id}
                    href={`#${item.id}`}
                    className={`sidebar-item-link ${isActive ? 'active' : ''}`}
                    onClick={(e) => {
                      e.preventDefault();
                      setCurrentTab(item.id);
                    }}
                    style={{
                      padding: '8px 12px',
                      fontSize: '12.5px',
                      borderRadius: '6px',
                      marginBottom: '2px',
                      display: 'flex',
                      alignItems: 'center',
                      gap: '10px'
                    }}
                  >
                    <Icon size={16} style={{ flexShrink: 0 }} />
                    <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                      {item.label}
                    </span>
                    {item.id === 'partners' && pendingApprovalsCount > 0 && (
                      <span style={{ 
                        marginLeft: 'auto', 
                        background: '#f59e0b', 
                        color: '#000', 
                        fontSize: '10px', 
                        fontWeight: 800, 
                        padding: '1px 6px', 
                        borderRadius: '10px' 
                      }}>
                        {pendingApprovalsCount}
                      </span>
                    )}
                  </a>
                );
              })}
            </div>
          );
        })}
      </div>

      <div className="sidebar-footer" style={{ padding: '14px 16px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
          <div style={{ 
            width: '28px', 
            height: '28px', 
            borderRadius: '50%', 
            background: 'var(--safety-yellow)', 
            color: '#000',
            fontWeight: 800,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            fontSize: '12px'
          }}>
            {user?.name ? user.name[0].toUpperCase() : 'A'}
          </div>
          <div style={{ overflow: 'hidden' }}>
            <div style={{ color: '#fff', fontWeight: 600, fontSize: '12px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
              {user?.name || 'Administrator'}
            </div>
            <div style={{ color: '#64748b', fontSize: '10px', textTransform: 'uppercase' }}>
              {activeRole}
            </div>
          </div>
        </div>

        <button 
          className="btn btn-secondary btn-sm" 
          onClick={logout}
          style={{ width: '100%', marginTop: '8px', display: 'flex', gap: '6px', justifyContent: 'center', fontSize: '11px', padding: '6px' }}
        >
          <LogOut size={13} />
          <span>Sign Out</span>
        </button>
      </div>
    </aside>
  );
};

export default Sidebar;
