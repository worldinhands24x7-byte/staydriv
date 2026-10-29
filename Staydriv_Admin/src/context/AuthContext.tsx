import React, { createContext, useContext, useState, useEffect } from 'react';
import { AdminUser, mockAdminUsers } from '../data/mockData';

export type UserRole = 'super_admin' | 'admin' | 'support' | 'finance';

export interface AuthContextType {
  user: AdminUser | null;
  activeRole: UserRole | null;
  loading: boolean;
  login: (email: string, pass: string) => Promise<boolean>;
  logout: () => void;
  setActiveRole: (role: UserRole) => void;
  switchRole: (role: UserRole) => void;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<AdminUser | null>(null);
  const [activeRole, setActiveRoleState] = useState<'super_admin' | 'admin' | 'support' | 'finance' | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // Check if user is stored in session
    const storedUser = localStorage.getItem('staydriv_admin_user');
    const storedRole = localStorage.getItem('staydriv_admin_role');
    if (storedUser) {
      try {
        const parsedUser = JSON.parse(storedUser) as AdminUser;
        setUser(parsedUser);
        setActiveRoleState((storedRole || parsedUser.role) as any);
      } catch (e) {
        localStorage.removeItem('staydriv_admin_user');
        localStorage.removeItem('staydriv_admin_role');
      }
    }
    setLoading(false);
  }, []);

  const getBackendUrl = () => {
    return (window as any).REACT_APP_BACKEND_URL || 
      ((window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1')
        ? `${window.location.protocol}//${window.location.hostname}:3000`
        : window.location.origin);
  };

  const login = async (email: string, pass: string): Promise<boolean> => {
    try {
      const backendUrl = getBackendUrl();
      const response = await fetch(`${backendUrl}/api/admin/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password: pass })
      });

      const data = await response.json();
      if (response.ok && data.success && data.token) {
        const adminUser: AdminUser = {
          uid: data.user.uid || data.user.id || 'admin_user',
          name: data.user.name || 'StayDriv Administrator',
          email: data.user.email || email,
          role: (data.user.role === 'Staff' ? 'admin' : 'super_admin') as any,
          phone: data.user.phone || '9010922111',
          lastLogin: new Date().toISOString()
        };

        setUser(adminUser);
        setActiveRoleState(adminUser.role);
        localStorage.setItem('staydriv_admin_token', data.token);
        localStorage.setItem('staydriv_admin_user', JSON.stringify(adminUser));
        localStorage.setItem('staydriv_admin_role', adminUser.role);
        localStorage.setItem('staydriv_admin_key', 'staydriv_admin_secret_2026');

        return true;
      }
    } catch (err) {
      console.warn('Backend login attempt note:', err);
    }

    // Local fallback for authorized master passwords
    const cleanPass = String(pass).trim();
    if (cleanPass === 'bhavi@123' || cleanPass === 'admin@123' || cleanPass === 'staydriv123' || cleanPass === 'staydriv@123') {
      const isStaff = cleanPass === 'admin@123';
      const role = isStaff ? 'admin' : 'super_admin';
      const adminUser: AdminUser = {
        uid: isStaff ? 'mock_staff_uid' : 'mock_admin_uid',
        name: isStaff ? 'StayDriv Staff' : 'StayDriv Administrator',
        email: email || 'admin@staydriv.com',
        role: role as any,
        phone: '9010922111',
        lastLogin: new Date().toISOString()
      };

      setUser(adminUser);
      setActiveRoleState(role as any);
      localStorage.setItem('staydriv_admin_token', 'staydriv_admin_secret_2026');
      localStorage.setItem('staydriv_admin_user', JSON.stringify(adminUser));
      localStorage.setItem('staydriv_admin_role', role);
      localStorage.setItem('staydriv_admin_key', 'staydriv_admin_secret_2026');

      return true;
    }

    return false;
  };

  const logout = () => {
    if (user) {
      const logoutLog = {
        logId: 'LOG_' + Date.now(),
        adminId: user.uid,
        adminEmail: user.email,
        action: 'LOGOUT',
        details: `Admin user ${user.name} logged out.`,
        ipAddress: '127.0.0.1',
        timestamp: new Date().toISOString()
      };
      const logs = JSON.parse(localStorage.getItem('staydriv_audit_logs') || '[]');
      logs.unshift(logoutLog);
      localStorage.setItem('staydriv_audit_logs', JSON.stringify(logs));
    }
    
    setUser(null);
    setActiveRoleState(null);
    localStorage.removeItem('staydriv_admin_user');
    localStorage.removeItem('staydriv_admin_role');
  };

  const setActiveRole = (role: 'super_admin' | 'admin' | 'support' | 'finance') => {
    setActiveRoleState(role);
    localStorage.setItem('staydriv_admin_role', role);
  };

  return (
    <AuthContext.Provider value={{ user, activeRole, loading, login, logout, setActiveRole, switchRole: setActiveRole }}>
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) throw new Error('useAuth must be used within an AuthProvider');
  return context;
};
