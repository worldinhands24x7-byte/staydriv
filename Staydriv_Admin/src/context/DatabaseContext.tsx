import React, { createContext, useContext, useState, useEffect, useRef, useCallback } from 'react';
import { io, Socket } from 'socket.io-client';
import { 
  Customer, Partner, Booking, Delivery, Payment, SupportTicket, PromoCode, AuditLog,
  mockDeliveries, mockPayments, mockSupportTickets, mockPromoCodes, mockAuditLogs, mockConfig 
} from '../data/mockData';
import { useAuth } from './AuthContext';

export interface DashboardStats {
  totalCustomers: number;
  onlineCustomers: number;
  activeCustomers: number;
  totalPilots: number;
  onlinePilots: number;
  busyPilots: number;
  availablePilots: number;
  activeRides: number;
  completedRides: number;
  cancelledRides: number;
  [key: string]: any;
}

export interface LiveOperationsData {
  pilots: Partner[];
  customers: Customer[];
  activeCustomers: Customer[];
  onlinePilots: Partner[];
  relationships: any[];
  stats: DashboardStats;
  success?: boolean;
}

interface DatabaseContextType {
  isLive: boolean;
  isOnline: boolean;
  customers: Customer[];
  partners: Partner[];
  bookings: Booking[];
  deliveries: Delivery[];
  payments: Payment[];
  supportTickets: SupportTicket[];
  promoCodes: PromoCode[];
  auditLogs: AuditLog[];
  config: typeof mockConfig;
  stats: DashboardStats;
  liveOperations: LiveOperationsData | null;
  lastUpdatedTime: string;
  refreshAllData: () => Promise<void>;
  
  // Real Financial & Operational Data (Section 2 - 6)
  kpis: any;
  pilotWallets: any[];
  withdrawals: any[];
  commissionConfig: any;
  commissionBookings: any[];
  founderSummary: any;
  companyPayouts: any[];
  financialLedger: any[];
  gatewaySettlements: any;
  refreshFinancials: () => Promise<void>;
  processWithdrawalAction: (withdrawalId: string, action: string, params?: any) => Promise<any>;
  updateCommissionConfig: (configData: any) => Promise<any>;
  recordFounderDistribution: (payoutData: any) => Promise<any>;
  reconcileLedger: () => Promise<any>;
  exportReport: (type: string) => Promise<void>;

  blockCustomer: (uid: string, blocked: boolean, reason?: string) => Promise<void>;
  updatePilotBookingAccess: (pilotId: string, action: 'ENABLE' | 'DISABLE', reason?: string) => Promise<any>;
  togglePilotDuty: (pilotId: string, action: 'DUTY_ON' | 'DUTY_OFF', reason?: string) => Promise<any>;
  updatePilotServicePreferences: (pilotId: string, prefs: { rideServiceEnabled?: boolean; foodServiceEnabled?: boolean }) => Promise<any>;
  verifyPartner: (uid: string, status: Partner['status'], reason?: string) => Promise<void>;
  verifyDocument: (uid: string, docKey: string) => Promise<boolean>;
  rejectDocument: (uid: string, docKey: string, reason: string) => Promise<boolean>;
  requestCorrection: (uid: string, notes: string) => Promise<boolean>;
  assignDriver: (bookingId: string, driverId: string, isDelivery?: boolean) => Promise<void>;
  cancelBooking: (bookingId: string, isDelivery?: boolean) => Promise<void>;
  processWithdrawal: (txnId: string, approve: boolean) => Promise<void>;
  updateCommissionRate: (percent: number) => Promise<void>;
  updateBaseFare: (category: string, amount: number) => Promise<void>;
  updatePerKmRate: (category: string, amount: number) => Promise<void>;
  createPromoCode: (promo: Omit<PromoCode, 'usageCount'>) => Promise<void>;
  togglePromoCode: (code: string) => Promise<void>;
  broadcastNotification: (notification: { 
    title: string; 
    body: string; 
    type: 'push' | 'promo' | 'alert' | 'emergency'; 
    targetGroup: 'all' | 'customers' | 'partners' | 'restaurants' | 'selected';
    adminEmail?: string;
    adminName?: string;
  }) => Promise<any>;
  fetchCampaigns: () => Promise<any[]>;
  fetchAudienceStats: () => Promise<any>;
  replyToSupportTicket: (ticketId: string, message: string) => Promise<void>;
  saveFirebaseConfig: (cfg: any) => void;
  clearFirebaseConfig: () => void;
  getFirebaseConfig: () => any;
}

const initialStats: DashboardStats = {
  totalCustomers: 0,
  onlineCustomers: 0,
  activeCustomers: 0,
  totalPilots: 0,
  onlinePilots: 0,
  busyPilots: 0,
  availablePilots: 0,
  activeRides: 0,
  completedRides: 0,
  cancelledRides: 0
};

const DatabaseContext = createContext<DatabaseContextType | undefined>(undefined);

export const DatabaseProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { user } = useAuth();
  const [isLive, setIsLive] = useState(true);
  const [isOnline, setIsOnline] = useState(navigator.onLine);
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [partners, setPartners] = useState<Partner[]>([]);
  const [bookings, setBookings] = useState<Booking[]>([]);
  const [deliveries, setDeliveries] = useState<Delivery[]>([]);
  const [payments, setPayments] = useState<Payment[]>([]);
  const [supportTickets, setSupportTickets] = useState<SupportTicket[]>([]);
  const [promoCodes, setPromoCodes] = useState<PromoCode[]>([]);
  const [auditLogs, setAuditLogs] = useState<AuditLog[]>([]);
  const [config, setConfig] = useState(mockConfig);
  const [stats, setStats] = useState<DashboardStats>(initialStats);
  const [liveOperations, setLiveOperations] = useState<LiveOperationsData | null>(null);
  const [lastUpdatedTime, setLastUpdatedTime] = useState<string>('Just now');

  // Dedicated Financial State
  const [kpis, setKpis] = useState<any>(null);
  const [pilotWallets, setPilotWallets] = useState<any[]>([]);
  const [withdrawals, setWithdrawals] = useState<any[]>([]);
  const [commissionConfig, setCommissionConfig] = useState<any>(null);
  const [commissionBookings, setCommissionBookings] = useState<any[]>([]);
  const [founderSummary, setFounderSummary] = useState<any>(null);
  const [companyPayouts, setCompanyPayouts] = useState<any[]>([]);
  const [financialLedger, setFinancialLedger] = useState<any[]>([]);
  const [gatewaySettlements, setGatewaySettlements] = useState<any>(null);

  const socketRef = useRef<Socket | null>(null);

  const getBackendUrl = () => {
    return (window as any).REACT_APP_BACKEND_URL || 
      ((window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1')
        ? `${window.location.protocol}//${window.location.hostname}:3000`
        : window.location.origin);
  };

  const getAuthHeaders = useCallback(() => {
    const token = localStorage.getItem('staydriv_admin_token') || 'staydriv_admin_secret_2026';
    return {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
      'x-admin-key': 'staydriv_admin_secret_2026'
    };
  }, []);

  // Fetch all live backend data
  const refreshAllData = useCallback(async () => {
    const backendUrl = getBackendUrl();
    const headers = getAuthHeaders();

    try {
      // 1. Fetch Customers
      const custPromise = fetch(`${backendUrl}/api/admin/customers`, { headers })
        .then(res => res.json())
        .then(data => {
          if (data && data.success && Array.isArray(data.customers)) {
            setCustomers(data.customers);
          }
        }).catch(err => console.warn('Fetch customers note:', err.message));

      // 2. Fetch Pilots
      const pilotPromise = fetch(`${backendUrl}/api/admin/drivers`, { headers })
        .then(res => res.json())
        .then(data => {
          if (data && data.success && (Array.isArray(data.pilots) || Array.isArray(data.drivers))) {
            setPartners(data.pilots || data.drivers);
          }
        }).catch(err => console.warn('Fetch pilots note:', err.message));

      // 3. Fetch Bookings
      const bookPromise = fetch(`${backendUrl}/api/admin/bookings`, { headers })
        .then(res => res.json())
        .then(data => {
          if (data && data.success && Array.isArray(data.bookings)) {
            setBookings(data.bookings);
          }
        }).catch(err => console.warn('Fetch bookings note:', err.message));

      // 4. Fetch Stats
      const statsPromise = fetch(`${backendUrl}/api/admin/stats`, { headers })
        .then(res => res.json())
        .then(data => {
          if (data && data.success && data.stats) {
            setStats(prev => ({ ...prev, ...data.stats }));
          }
        }).catch(err => console.warn('Fetch stats note:', err.message));

      // 5. Fetch Live Operations
      const liveOpsPromise = fetch(`${backendUrl}/api/admin/live-operations`, { headers })
        .then(res => res.json())
        .then(data => {
          if (data && data.success) {
            setLiveOperations(data);
            if (data.stats) setStats(prev => ({ ...prev, ...data.stats }));
          }
        }).catch(err => console.warn('Fetch live operations note:', err.message));

      await Promise.allSettled([custPromise, pilotPromise, bookPromise, statsPromise, liveOpsPromise]);
      await refreshFinancials();
      setLastUpdatedTime(new Date().toLocaleTimeString());
    } catch (e) {
      console.error('Error refreshing admin data:', e);
    }
  }, [getAuthHeaders]);

  // Fetch real financial and wallet data
  const refreshFinancials = useCallback(async () => {
    const backendUrl = getBackendUrl();
    const headers = getAuthHeaders();

    try {
      const [kpisRes, walletsRes, wthRes, cfgRes, commBookingsRes, founderRes, payoutsRes, ledgerRes, gwRes] = await Promise.allSettled([
        fetch(`${backendUrl}/api/admin/realtime-kpis`, { headers }).then(r => r.json()),
        fetch(`${backendUrl}/api/admin/pilot-wallets`, { headers }).then(r => r.json()),
        fetch(`${backendUrl}/api/admin/withdrawals`, { headers }).then(r => r.json()),
        fetch(`${backendUrl}/api/admin/commission/config`, { headers }).then(r => r.json()),
        fetch(`${backendUrl}/api/admin/commission/bookings`, { headers }).then(r => r.json()),
        fetch(`${backendUrl}/api/admin/founder/financial-summary`, { headers }).then(r => r.json()),
        fetch(`${backendUrl}/api/admin/company/founder-payouts`, { headers }).then(r => r.json()),
        fetch(`${backendUrl}/api/admin/ledger`, { headers }).then(r => r.json()),
        fetch(`${backendUrl}/api/admin/gateway-settlements`, { headers }).then(r => r.json())
      ]);

      if (kpisRes.status === 'fulfilled' && kpisRes.value?.success) {
        setKpis(kpisRes.value);
        if (kpisRes.value.metrics) {
          setStats(prev => ({ ...prev, ...kpisRes.value.metrics }));
        }
      }
      if (walletsRes.status === 'fulfilled' && walletsRes.value?.success) {
        setPilotWallets(walletsRes.value.wallets || []);
      }
      if (wthRes.status === 'fulfilled' && wthRes.value?.success) {
        setWithdrawals(wthRes.value.items || []);
      }
      if (cfgRes.status === 'fulfilled' && cfgRes.value?.success) {
        setCommissionConfig(cfgRes.value.activeConfig || null);
      }
      if (commBookingsRes.status === 'fulfilled' && commBookingsRes.value?.success) {
        setCommissionBookings(commBookingsRes.value.items || []);
      }
      if (founderRes.status === 'fulfilled' && founderRes.value?.success) {
        setFounderSummary(founderRes.value.totals || null);
      }
      if (payoutsRes.status === 'fulfilled' && payoutsRes.value?.success) {
        setCompanyPayouts(payoutsRes.value.payouts || []);
      }
      if (ledgerRes.status === 'fulfilled' && ledgerRes.value?.success) {
        setFinancialLedger(ledgerRes.value.entries || []);
      }
      if (gwRes.status === 'fulfilled' && gwRes.value?.success) {
        setGatewaySettlements(gwRes.value);
      }
    } catch (err) {
      console.warn('[FINANCE REFRESH NOTE]:', err);
    }
  }, [getAuthHeaders]);

  // Initial load
  useEffect(() => {
    refreshAllData();

    // Load local deliveries, payments, etc.
    const getOrSet = (key: string, initial: any) => {
      const stored = localStorage.getItem(key);
      if (stored) {
        try { return JSON.parse(stored); } catch (e) {}
      }
      localStorage.setItem(key, JSON.stringify(initial));
      return initial;
    };

    setDeliveries(getOrSet('staydriv_deliveries', mockDeliveries));
    setPayments(getOrSet('staydriv_payments', mockPayments));
    setSupportTickets(getOrSet('staydriv_tickets', mockSupportTickets));
    setPromoCodes(getOrSet('staydriv_promos', mockPromoCodes));
    setAuditLogs(getOrSet('staydriv_audit_logs', mockAuditLogs));
  }, [refreshAllData]);

  // Network online/offline listeners
  useEffect(() => {
    const handleOnline = () => setIsOnline(true);
    const handleOffline = () => setIsOnline(false);
    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);
    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, []);

  // Real-time Socket.IO Connection & Listeners
  useEffect(() => {
    const backendUrl = getBackendUrl();
    const token = localStorage.getItem('staydriv_admin_token') || 'staydriv_admin_secret_2026';

    const socket = io(backendUrl, {
      transports: ['websocket', 'polling'],
      reconnectionAttempts: 20,
      reconnectionDelay: 1000
    });
    socketRef.current = socket;

    socket.on('connect', () => {
      setIsLive(true);
      console.log('[ADMIN SOCKET] Connected to StayDriv backend. Joining admin_tracking room...');
      socket.emit('admin_join_tracking', {
        adminKey: 'staydriv_admin_secret_2026',
        token,
        role: 'super_admin'
      });
    });

    socket.on('disconnect', () => {
      console.log('[ADMIN SOCKET] Disconnected from StayDriv backend.');
    });

    // Real-time Live Operations Snapshot
    socket.on('live_operations_snapshot', (data: LiveOperationsData) => {
      if (data && data.success) {
        setLiveOperations(data);
        if (Array.isArray(data.pilots)) setPartners(data.pilots);
        if (Array.isArray(data.customers)) setCustomers(data.customers);
        if (data.stats) setStats(prev => ({ ...prev, ...data.stats }));
        setLastUpdatedTime(new Date().toLocaleTimeString());
      }
    });

    // Real-time Operational KPIs Snapshot
    socket.on('admin_kpis_snapshot', (kpiData: any) => {
      if (kpiData && kpiData.metrics) {
        setKpis(kpiData);
        setStats(prev => ({ ...prev, ...kpiData.metrics }));
        setLastUpdatedTime(new Date().toLocaleTimeString());
      }
    });

    // Real-time Withdrawal & Payout Updates
    socket.on('withdrawal_status_updated', () => {
      refreshFinancials();
    });

    socket.on('withdrawal_created', () => {
      refreshFinancials();
    });

    socket.on('pilot_wallet_updated', () => {
      refreshFinancials();
    });

    // Real-time Pilot Location Update
    socket.on('pilot_location_update', (pilotData: any) => {
      if (!pilotData || !pilotData.uid) return;
      setPartners(prev => {
        const idx = prev.findIndex(p => p.uid === pilotData.uid || p.pilotId === pilotData.uid || p.phone === pilotData.phone);
        if (idx >= 0) {
          const updated = [...prev];
          updated[idx] = { ...updated[idx], ...pilotData };
          return updated;
        } else {
          return [pilotData, ...prev];
        }
      });
      setLastUpdatedTime(new Date().toLocaleTimeString());
    });

    // Real-time Customer Location Update
    socket.on('customer_location_update', (custData: any) => {
      if (!custData || (!custData.uid && !custData.customerId)) return;
      const cid = custData.uid || custData.customerId;
      setCustomers(prev => {
        const idx = prev.findIndex(c => c.uid === cid || c.customerId === cid || c.phone === custData.phone);
        if (idx >= 0) {
          const updated = [...prev];
          updated[idx] = { ...updated[idx], ...custData, hasLocation: true, isLocationStale: false };
          return updated;
        } else {
          return [custData, ...prev];
        }
      });
      setLastUpdatedTime(new Date().toLocaleTimeString());
    });

    // Pilot Online / Offline / Status Change
    socket.on('pilot_online', (pilot: any) => {
      setPartners(prev => prev.map(p => (p.uid === pilot.uid ? { ...p, online: true, onlineStatus: 'Online' } : p)));
    });

    socket.on('pilot_offline', (data: any) => {
      setPartners(prev => prev.map(p => (p.uid === data.uid ? { ...p, online: false, onlineStatus: 'Offline', rideStatus: 'offline' } : p)));
    });

    socket.on('pilot_status_change', (data: any) => {
      if (data?.uid) {
        setPartners(prev => prev.map(p => (p.uid === data.uid ? { ...p, ...data.pilot, online: data.online, status: data.status } : p)));
      }
    });

    // Booking Lifecycle Events
    socket.on('booking_created', (_bookingData: any) => {
      refreshAllData();
    });

    socket.on('booking_accepted', (_bookingData: any) => {
      refreshAllData();
    });

    socket.on('booking_update', (_bookingData: any) => {
      refreshAllData();
    });

    socket.on('admin_booking_update', (_bookingData: any) => {
      refreshAllData();
    });

    socket.on('pilot_arrived', (_data: any) => {
      refreshAllData();
    });

    socket.on('ride_started', (_data: any) => {
      refreshAllData();
    });

    socket.on('ride_completed', (_data: any) => {
      refreshAllData();
    });

    socket.on('booking_cancelled', (_data: any) => {
      refreshAllData();
    });

    socket.on('pilot_registered', () => {
      console.log('[ADMIN SOCKET] Pilot registered event received. Refreshing fleet data...');
      refreshAllData();
    });

    socket.on('pilot_application_submitted', () => {
      console.log('[ADMIN SOCKET] Pilot application submitted event received. Refreshing fleet data...');
      refreshAllData();
    });

    socket.on('admin_pilots_updated', () => {
      console.log('[ADMIN SOCKET] Admin pilots updated event received. Refreshing fleet data...');
      refreshAllData();
    });

    socket.on('pilot_pending_approval', () => {
      console.log('[ADMIN SOCKET] Pilot pending approval event received. Refreshing fleet data...');
      refreshAllData();
    });

    socket.on('pilot_document_verified', () => {
      console.log('[ADMIN SOCKET] Pilot document verified event received. Refreshing...');
      refreshAllData();
    });

    socket.on('pilot_document_rejected', () => {
      console.log('[ADMIN SOCKET] Pilot document rejected event received. Refreshing...');
      refreshAllData();
    });

    socket.on('pilot_approval_updated', () => {
      console.log('[ADMIN SOCKET] Pilot approval updated event received. Refreshing...');
      refreshAllData();
    });

    socket.on('admin_tracking_joined', () => {
      setIsLive(true);
    });

    socket.on('reconnect', () => {
      setIsLive(true);
      socket.emit('admin_join_tracking', {
        adminKey: 'staydriv_admin_secret_2026',
        token,
        role: 'super_admin'
      });
      refreshAllData();
    });

    // Auto-refresh polling every 10 seconds to ensure fresh data
    const refreshInterval = setInterval(() => {
      refreshAllData();
    }, 10000);

    // Live Metrics Update
    socket.on('admin_stats_update', (newStats: DashboardStats) => {
      if (newStats) {
        setStats(prev => ({ ...prev, ...newStats }));
        setLastUpdatedTime(new Date().toLocaleTimeString());
      }
    });

    socket.on('disconnect', () => {
      setIsLive(false);
      console.log('[ADMIN SOCKET] Disconnected from StayDriv backend.');
    });

    return () => {
      clearInterval(refreshInterval);
      socket.disconnect();
    };
  }, [refreshAllData]);

  // Periodic fallback refresh (every 30s)
  useEffect(() => {
    const interval = setInterval(() => {
      refreshAllData();
    }, 30000);
    return () => clearInterval(interval);
  }, [refreshAllData]);

  // Logger helper
  const addAuditLog = async (action: string, details: string) => {
    const log: AuditLog = {
      logId: 'LOG_' + Date.now(),
      adminId: user?.uid || 'admin',
      adminEmail: user?.email || 'admin@staydriv.com',
      action,
      details,
      ipAddress: '127.0.0.1',
      timestamp: new Date().toISOString()
    };
    const logs = [log, ...auditLogs];
    setAuditLogs(logs);
    localStorage.setItem('staydriv_audit_logs', JSON.stringify(logs));
  };

  // Block Customer Action
  const blockCustomer = async (uid: string, blocked: boolean, reason?: string) => {
    const backendUrl = getBackendUrl();
    const headers = getAuthHeaders();

    try {
      await fetch(`${backendUrl}/api/admin/user/block`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          uid,
          role: 'customer',
          isBlocked: blocked,
          reason: reason || (blocked ? 'Blocked by Admin' : 'Unblocked by Admin'),
          adminId: user?.uid || 'admin',
          adminName: user?.name || 'StayDriv Admin'
        })
      });

      setCustomers(prev => prev.map(c => c.uid === uid ? { ...c, status: blocked ? 'blocked' : 'active' } : c));
      await addAuditLog('BLOCK_CUSTOMER', `${blocked ? 'Blocked' : 'Unblocked'} customer account: ${uid}`);
    } catch (e: any) {
      console.error('Error blocking customer:', e.message);
    }
  };

  // Verify / Approve / Reject Partner Action
  const verifyPartner = async (uid: string, status: Partner['status'], reason?: string) => {
    const backendUrl = getBackendUrl();
    const headers = getAuthHeaders();

    try {
      let endpoint = '/api/admin/driver/approve';
      if (status === 'rejected') endpoint = '/api/admin/driver/reject';
      else if (status === 'suspended') endpoint = '/api/admin/driver/suspend';

      await fetch(`${backendUrl}${endpoint}`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          uid,
          adminId: user?.uid || 'admin',
          adminName: user?.name || 'StayDriv Admin',
          reason: reason || `Partner status updated to ${status}`
        })
      });

      setPartners(prev => prev.map(p => p.uid === uid ? { ...p, status } : p));
      await addAuditLog('VERIFY_PARTNER', `Updated partner ${uid} status to: ${status}`);
      await refreshAllData();
    } catch (e: any) {
      console.error('Error verifying partner:', e.message);
    }
  };

  const verifyDocument = async (uid: string, docKey: string): Promise<boolean> => {
    const backendUrl = getBackendUrl();
    const headers = getAuthHeaders();
    try {
      const res = await fetch(`${backendUrl}/api/admin/driver/verify-doc`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          uid,
          docKey,
          adminId: user?.uid || 'admin',
          adminName: user?.name || 'StayDriv Admin'
        })
      });
      const data = await res.json();
      if (data && data.success) {
        await refreshAllData();
        return true;
      }
      return false;
    } catch (e: any) {
      console.error('Error verifying document:', e.message);
      return false;
    }
  };

  const rejectDocument = async (uid: string, docKey: string, reason: string): Promise<boolean> => {
    const backendUrl = getBackendUrl();
    const headers = getAuthHeaders();
    try {
      const res = await fetch(`${backendUrl}/api/admin/driver/reject-doc`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          uid,
          docKey,
          reason,
          adminId: user?.uid || 'admin',
          adminName: user?.name || 'StayDriv Admin'
        })
      });
      const data = await res.json();
      if (data && data.success) {
        await refreshAllData();
        return true;
      }
      return false;
    } catch (e: any) {
      console.error('Error rejecting document:', e.message);
      return false;
    }
  };

  const requestCorrection = async (uid: string, notes: string): Promise<boolean> => {
    const backendUrl = getBackendUrl();
    const headers = getAuthHeaders();
    try {
      const res = await fetch(`${backendUrl}/api/admin/driver/request-correction`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          uid,
          notes,
          adminId: user?.uid || 'admin',
          adminName: user?.name || 'StayDriv Admin'
        })
      });
      const data = await res.json();
      if (data && data.success) {
        await refreshAllData();
        return true;
      }
      return false;
    } catch (e: any) {
      console.error('Error requesting correction:', e.message);
      return false;
    }
  };

  const updatePilotBookingAccess = async (pilotId: string, action: 'ENABLE' | 'DISABLE', reason = ''): Promise<any> => {
    const backendUrl = getBackendUrl();
    const headers = getAuthHeaders();
    try {
      const res = await fetch(`${backendUrl}/api/admin/drivers/${encodeURIComponent(pilotId)}/booking-access`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          action,
          reason,
          adminId: user?.uid || 'admin',
          adminName: user?.name || 'StayDriv Admin'
        })
      });
      const data = await res.json();
      if (data && data.success) {
        await refreshAllData();
      }
      return data;
    } catch (e: any) {
      console.error('Error updating pilot booking access:', e.message);
      return { success: false, message: e.message };
    }
  };

  const togglePilotDuty = async (pilotId: string, action: 'DUTY_ON' | 'DUTY_OFF', reason = ''): Promise<any> => {
    const backendUrl = getBackendUrl();
    const headers = getAuthHeaders();
    try {
      const res = await fetch(`${backendUrl}/api/admin/drivers/${encodeURIComponent(pilotId)}/duty`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          action,
          reason,
          adminId: user?.uid || 'admin',
          adminName: user?.name || 'StayDriv Admin'
        })
      });
      const data = await res.json();
      if (data && data.success) {
        await refreshAllData();
      }
      return data;
    } catch (e: any) {
      console.error('Error toggling pilot duty:', e.message);
      return { success: false, message: e.message };
    }
  };

  const updatePilotServicePreferences = async (pilotId: string, prefs: { rideServiceEnabled?: boolean; foodServiceEnabled?: boolean }): Promise<any> => {
    const backendUrl = getBackendUrl();
    const headers = getAuthHeaders();
    try {
      const res = await fetch(`${backendUrl}/api/admin/drivers/${encodeURIComponent(pilotId)}/service-preferences`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          ...prefs,
          adminId: user?.uid || 'admin',
          adminName: user?.name || 'StayDriv Admin'
        })
      });
      const data = await res.json();
      if (data && data.success) {
        await refreshAllData();
      }
      return data;
    } catch (e: any) {
      console.error('Error updating pilot service preferences:', e.message);
      return { success: false, message: e.message };
    }
  };

  const assignDriver = async (bookingId: string, driverId: string, isDelivery = false) => {
    const driver = partners.find(p => p.uid === driverId);
    if (!driver) return;

    if (isDelivery) {
      setDeliveries(prev => prev.map(d => d.bookingId === bookingId ? {
        ...d,
        driverId: driver.uid,
        driverName: driver.name,
        vehiclePlate: driver.vehiclePlate,
        vehicleModelColor: driver.vehicleModelColor || '',
        status: 'accepted'
      } : d));
    } else {
      setBookings(prev => prev.map(b => b.bookingId === bookingId ? {
        ...b,
        driverId: driver.uid,
        driverName: driver.name,
        vehiclePlate: driver.vehiclePlate,
        vehicleModelColor: driver.vehicleModelColor || '',
        status: 'accepted'
      } : b));
    }
    await addAuditLog('ASSIGN_DRIVER', `Manually assigned driver ${driver.name} to booking ${bookingId}`);
  };

  const cancelBooking = async (bookingId: string, isDelivery = false) => {
    const backendUrl = getBackendUrl();
    const headers = getAuthHeaders();

    try {
      await fetch(`${backendUrl}/api/admin/booking/cancel`, {
        method: 'POST',
        headers,
        body: JSON.stringify({ bookingId, cancelledBy: 'admin', reason: 'Cancelled by Administrator' })
      });
    } catch (_) {}

    if (isDelivery) {
      setDeliveries(prev => prev.map(d => d.bookingId === bookingId ? { ...d, status: 'cancelled' } : d));
    } else {
      setBookings(prev => prev.map(b => b.bookingId === bookingId ? { ...b, status: 'cancelled' } : b));
    }
    await addAuditLog('CANCEL_BOOKING', `Cancelled booking ${bookingId}`);
  };

  const processWithdrawal = async (txnId: string, approve: boolean) => {
    setPayments(prev => prev.map(p => p.transactionId === txnId ? { ...p, status: approve ? 'completed' : 'failed' } : p));
    await addAuditLog('PROCESS_WITHDRAWAL', `${approve ? 'Approved' : 'Rejected'} withdrawal payout: ${txnId}`);
  };

  const updateCommissionRate = async (percent: number) => {
    const updated = { ...config, commissionPercent: percent };
    setConfig(updated);
    localStorage.setItem('staydriv_config', JSON.stringify(updated));
    await addAuditLog('UPDATE_COMMISSION', `Commission rate updated to ${percent}%`);
  };

  const updateBaseFare = async (category: string, amount: number) => {
    const updated = {
      ...config,
      baseFares: { ...config.baseFares, [category]: amount }
    };
    setConfig(updated);
    localStorage.setItem('staydriv_config', JSON.stringify(updated));
    await addAuditLog('UPDATE_BASE_FARE', `Base fare for ${category} updated to ₹${amount}`);
  };

  const updatePerKmRate = async (category: string, amount: number) => {
    const updated = {
      ...config,
      perKmRates: { ...config.perKmRates, [category]: amount }
    };
    setConfig(updated);
    localStorage.setItem('staydriv_config', JSON.stringify(updated));
    await addAuditLog('UPDATE_KM_RATE', `Per KM rate for ${category} updated to ₹${amount}`);
  };

  const createPromoCode = async (promo: Omit<PromoCode, 'usageCount'>) => {
    const newPromo: PromoCode = { ...promo, usageCount: 0 };
    const list = [newPromo, ...promoCodes];
    setPromoCodes(list);
    localStorage.setItem('staydriv_promos', JSON.stringify(list));
    await addAuditLog('CREATE_PROMO', `Created promo code: ${promo.code}`);
  };

  const togglePromoCode = async (code: string) => {
    const list = promoCodes.map(p => {
      if (p.code !== code) return p;
      const isCurrentlyActive = p.status === 'active' || p.active === true;
      return { 
        ...p, 
        status: isCurrentlyActive ? ('inactive' as const) : ('active' as const),
        active: !isCurrentlyActive
      };
    });
    setPromoCodes(list);
    localStorage.setItem('staydriv_promos', JSON.stringify(list));
    await addAuditLog('TOGGLE_PROMO', `Toggled active status for promo: ${code}`);
  };

  const broadcastNotification = async (notification: { 
    title: string; 
    body: string; 
    type: 'push' | 'promo' | 'alert' | 'emergency'; 
    targetGroup: 'all' | 'customers' | 'partners' | 'restaurants' | 'selected';
    adminEmail?: string;
    adminName?: string;
  }) => {
    const backendUrl = getBackendUrl();
    const headers = getAuthHeaders();
    try {
      const res = await fetch(`${backendUrl}/api/notifications/broadcast`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          ...notification,
          adminEmail: user?.email || 'admin@staydriv.com',
          adminName: user?.name || 'Super Admin'
        })
      });
      const data = await res.json();
      await addAuditLog('BROADCAST_NOTIFICATION', `Broadcasted ${notification.type} to ${notification.targetGroup}: ${notification.title}`);
      return data;
    } catch (err: any) {
      await addAuditLog('BROADCAST_NOTIFICATION', `Broadcast attempt (${notification.type} to ${notification.targetGroup}): ${notification.title}`);
      return { success: false, message: err.message || 'Network error' };
    }
  };

  const fetchCampaigns = async () => {
    const backendUrl = getBackendUrl();
    const headers = getAuthHeaders();
    try {
      const res = await fetch(`${backendUrl}/api/notifications/campaigns`, { headers });
      const data = await res.json();
      return data.success ? data.campaigns : [];
    } catch (_) {
      return [];
    }
  };

  const fetchAudienceStats = async () => {
    const backendUrl = getBackendUrl();
    const headers = getAuthHeaders();
    try {
      const res = await fetch(`${backendUrl}/api/notifications/stats`, { headers });
      const data = await res.json();
      return data.success ? data.stats : null;
    } catch (_) {
      return null;
    }
  };

  const replyToSupportTicket = async (ticketId: string, message: string) => {
    setSupportTickets(prev => prev.map(t => {
      if (t.ticketId === ticketId) {
        const chatHistory = t.chatHistory || [];
        return {
          ...t,
          chatHistory: [...chatHistory, {
            senderId: user?.uid || 'admin',
            senderName: user?.name || 'StayDriv Support',
            message,
            timestamp: new Date().toISOString()
          }]
        };
      }
      return t;
    }));
    await addAuditLog('REPLY_SUPPORT', `Replied to ticket: ${ticketId}`);
  };

  const saveFirebaseConfig = (cfg: any) => {
    localStorage.setItem('staydriv_fb_config', JSON.stringify(cfg));
  };

  const clearFirebaseConfig = () => {
    localStorage.removeItem('staydriv_fb_config');
  };

  const processWithdrawalAction = async (withdrawalId: string, action: string, params?: any) => {
    const backendUrl = getBackendUrl();
    const headers = getAuthHeaders();
    const res = await fetch(`${backendUrl}/api/admin/withdrawals/${withdrawalId}/action`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ action, ...params })
    });
    const data = await res.json();
    if (!res.ok || !data.success) {
      throw new Error(data.error || 'Failed to process withdrawal action');
    }
    await refreshFinancials();
    return data;
  };

  const updateCommissionConfig = async (configData: any) => {
    const backendUrl = getBackendUrl();
    const headers = getAuthHeaders();
    const res = await fetch(`${backendUrl}/api/admin/commission/config`, {
      method: 'POST',
      headers,
      body: JSON.stringify(configData)
    });
    const data = await res.json();
    if (!res.ok || !data.success) {
      throw new Error(data.error || 'Failed to update commission configuration');
    }
    await refreshFinancials();
    return data;
  };

  const recordFounderDistribution = async (payoutData: any) => {
    const backendUrl = getBackendUrl();
    const headers = getAuthHeaders();
    const res = await fetch(`${backendUrl}/api/admin/company/founder-payouts`, {
      method: 'POST',
      headers,
      body: JSON.stringify(payoutData)
    });
    const data = await res.json();
    if (!res.ok || !data.success) {
      throw new Error(data.error || 'Failed to record founder distribution');
    }
    await refreshFinancials();
    return data;
  };

  const reconcileLedger = async () => {
    const backendUrl = getBackendUrl();
    const headers = getAuthHeaders();
    const res = await fetch(`${backendUrl}/api/admin/ledger/reconcile`, { headers });
    const data = await res.json();
    await refreshFinancials();
    return data;
  };

  const exportReport = async (type: string) => {
    const backendUrl = getBackendUrl();
    const token = localStorage.getItem('staydriv_admin_token') || 'staydriv_admin_secret_2026';
    const url = `${backendUrl}/api/admin/reports/export?type=${type}&adminKey=${encodeURIComponent(token)}`;
    window.open(url, '_blank');
  };

  const getFirebaseConfig = () => {
    const c = localStorage.getItem('staydriv_fb_config');
    return c ? JSON.parse(c) : null;
  };

  return (
    <DatabaseContext.Provider value={{
      isLive,
      isOnline,
      customers,
      partners,
      bookings,
      deliveries,
      payments,
      supportTickets,
      promoCodes,
      auditLogs,
      config,
      stats,
      liveOperations,
      lastUpdatedTime,
      refreshAllData,
      kpis,
      pilotWallets,
      withdrawals,
      commissionConfig,
      commissionBookings,
      founderSummary,
      companyPayouts,
      financialLedger,
      gatewaySettlements,
      refreshFinancials,
      processWithdrawalAction,
      updateCommissionConfig,
      recordFounderDistribution,
      reconcileLedger,
      exportReport,
      blockCustomer,
      updatePilotBookingAccess,
      togglePilotDuty,
      updatePilotServicePreferences,
      verifyPartner,
      verifyDocument,
      rejectDocument,
      requestCorrection,
      assignDriver,
      cancelBooking,
      processWithdrawal,
      updateCommissionRate,
      updateBaseFare,
      updatePerKmRate,
      createPromoCode,
      togglePromoCode,
      broadcastNotification,
      fetchCampaigns,
      fetchAudienceStats,
      replyToSupportTicket,
      saveFirebaseConfig,
      clearFirebaseConfig,
      getFirebaseConfig
    }}>
      {children}
    </DatabaseContext.Provider>
  );
};

export const useDatabase = () => {
  const context = useContext(DatabaseContext);
  if (!context) throw new Error('useDatabase must be used within a DatabaseProvider');
  return context;
};
