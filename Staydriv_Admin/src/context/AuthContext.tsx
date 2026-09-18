import React, { createContext, useContext, useState, useEffect } from 'react';
import { AdminUser, mockAdminUsers } from '../data/mockData';

interface AuthContextType {
  user: AdminUser | null;
  activeRole: 'super_admin' | 'admin' | 'support' | 'finance' | null;
  loading: boolean;
  login: (email: string, pass: string) => Promise<boolean>;
  logout: () => void;
  setActiveRole: (role: 'super_admin' | 'admin' | 'support' | 'finance') => void;
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

  const login = async (email: string, pass: string): Promise<boolean> => {
    // Simulated credential check (or link to Firebase Authentication in live mode)
    // For demonstration, standard matching emails in mockAdminUsers are authenticated:
    // super@staydriv.com -> admin_1 (Super Admin)
    // ops@staydriv.com -> admin_2 (Admin)
    // support@staydriv.com -> admin_3 (Support)
    // finance@staydriv.com -> admin_4 (Finance)
    // Password is 'bhavi@123' for all accounts
    
    return new Promise((resolve) => {
      setTimeout(() => {
        const found = mockAdminUsers.find(u => u.email.toLowerCase() === email.toLowerCase());
        if (found && (pass === 'admin@123' || pass === 'bhavi@123' || pass === 'staydriv123' || pass === 'admin' || pass === 'staydriv@123' || pass === '123456')) {
          setUser(found);
          setActiveRoleState(found.role);
          localStorage.setItem('staydriv_admin_user', JSON.stringify(found));
          localStorage.setItem('staydriv_admin_role', found.role);
          
          // Write log to audit logs
          const loginLog = {
            logId: 'LOG_' + Date.now(),
            adminId: found.uid,
            adminEmail: found.email,
            action: 'LOGIN_SUCCESS',
            details: `Admin user ${found.name} logged in successfully. Role: ${found.role}`,
            ipAddress: '127.0.0.1',
            timestamp: new Date().toISOString()
          };
          const logs = JSON.parse(localStorage.getItem('staydriv_audit_logs') || '[]');
          logs.unshift(loginLog);
          localStorage.setItem('staydriv_audit_logs', JSON.stringify(logs));
          
          resolve(true);
        } else {
          resolve(false);
        }
      }, 600);
    });
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
    <AuthContext.Provider value={{ user, activeRole, loading, login, logout, setActiveRole }}>
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) throw new Error('useAuth must be used within an AuthProvider');
  return context;
};
