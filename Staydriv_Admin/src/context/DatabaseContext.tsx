import React, { createContext, useContext, useState, useEffect } from 'react';
import { 
  Customer, Partner, Booking, Delivery, Payment, SupportTicket, PromoCode, AuditLog,
  mockCustomers, mockPartners, mockBookings, mockDeliveries, mockPayments, mockSupportTickets, mockPromoCodes, mockAuditLogs, mockConfig 
} from '../data/mockData';
import { useAuth } from './AuthContext';

// Safe dynamic imports for Firebase
import { initializeApp, getApps, getApp } from 'firebase/app';
import { 
  getFirestore, doc, collection, onSnapshot, updateDoc, setDoc, 
  deleteDoc, addDoc, serverTimestamp, query, orderBy, limit,
  enableMultiTabIndexedDbPersistence
} from 'firebase/firestore';

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
  
  blockCustomer: (uid: string, blocked: boolean) => Promise<void>;
  verifyPartner: (uid: string, status: Partner['status']) => Promise<void>;
  assignDriver: (bookingId: string, driverId: string, isDelivery?: boolean) => Promise<void>;
  cancelBooking: (bookingId: string, isDelivery?: boolean) => Promise<void>;
  processWithdrawal: (txnId: string, approve: boolean) => Promise<void>;
  updateCommissionRate: (percent: number) => Promise<void>;
  updateBaseFare: (category: string, amount: number) => Promise<void>;
  updatePerKmRate: (category: string, amount: number) => Promise<void>;
  createPromoCode: (promo: Omit<PromoCode, 'usageCount'>) => Promise<void>;
  togglePromoCode: (code: string) => Promise<void>;
  broadcastNotification: (notification: { title: string; body: string; type: 'push' | 'promo' | 'alert' | 'emergency'; targetGroup: 'all' | 'customers' | 'partners' }) => Promise<void>;
  replyToSupportTicket: (ticketId: string, message: string) => Promise<void>;
  saveFirebaseConfig: (cfg: any) => void;
  clearFirebaseConfig: () => void;
  getFirebaseConfig: () => any;
}

const DatabaseContext = createContext<DatabaseContextType | undefined>(undefined);

export const DatabaseProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { user } = useAuth();
  const [isLive, setIsLive] = useState(false);
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

  useEffect(() => {
    const handleOnline = () => {
      setIsOnline(true);
      console.log("Admin Panel network connection restored.");
    };
    const handleOffline = () => {
      setIsOnline(false);
      console.log("Admin Panel network disconnected. Operating in offline cache mode.");
    };

    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);

    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, []);

  // Initialize data provider
  useEffect(() => {
    const savedConfig = localStorage.getItem('staydriv_fb_config');
    let dbInstance: any = null;

    if (savedConfig) {
      try {
        const parsed = JSON.parse(savedConfig);
        if (parsed.projectId && parsed.apiKey) {
          const app = getApps().length === 0 ? initializeApp(parsed) : getApp();
          dbInstance = getFirestore(app);
          setIsLive(true);
          console.log("Database initialized in LIVE Firestore mode:", parsed.projectId);
          enableMultiTabIndexedDbPersistence(dbInstance).catch((err) => {
            console.warn("Firestore offline persistence config status:", err.message);
          });
        }
      } catch (e) {
        console.error("Failed to connect to Firebase Firestore, falling back to local simulation:", e);
      }
    }

    if (dbInstance) {
      // 1. LIVE FIRESTORE listeners
      const unsubCustomers = onSnapshot(collection(dbInstance, 'users'), (snapshot) => {
        const list: Customer[] = [];
        snapshot.forEach(d => list.push({ uid: d.id, ...d.data() } as any));
        setCustomers(list.length > 0 ? list : mockCustomers); // fallback if empty
      });

      const unsubPartners = onSnapshot(collection(dbInstance, 'partners'), (snapshot) => {
        const list: Partner[] = [];
        snapshot.forEach(d => list.push({ uid: d.id, ...d.data() } as any));
        setPartners(list.length > 0 ? list : mockPartners);
      });

      const unsubBookings = onSnapshot(collection(dbInstance, 'bookings'), (snapshot) => {
        const list: Booking[] = [];
        snapshot.forEach(d => list.push({ bookingId: d.id, ...d.data() } as any));
        setBookings(list.length > 0 ? list : mockBookings);
      });

      const unsubDeliveries = onSnapshot(collection(dbInstance, 'deliveries'), (snapshot) => {
        const list: Delivery[] = [];
        snapshot.forEach(d => list.push({ bookingId: d.id, ...d.data() } as any));
        setDeliveries(list.length > 0 ? list : mockDeliveries);
      });

      const unsubPayments = onSnapshot(collection(dbInstance, 'payments'), (snapshot) => {
        const list: Payment[] = [];
        snapshot.forEach(d => list.push({ transactionId: d.id, ...d.data() } as any));
        setPayments(list.length > 0 ? list : mockPayments);
      });

      const unsubTickets = onSnapshot(collection(dbInstance, 'support_tickets'), (snapshot) => {
        const list: SupportTicket[] = [];
        snapshot.forEach(d => list.push({ ticketId: d.id, ...d.data() } as any));
        setSupportTickets(list.length > 0 ? list : mockSupportTickets);
      });

      const unsubPromos = onSnapshot(collection(dbInstance, 'promo_codes'), (snapshot) => {
        const list: PromoCode[] = [];
        snapshot.forEach(d => list.push({ code: d.id, ...d.data() } as any));
        setPromoCodes(list.length > 0 ? list : mockPromoCodes);
      });

      const unsubAudit = onSnapshot(collection(dbInstance, 'audit_logs'), (snapshot) => {
        const list: AuditLog[] = [];
        snapshot.forEach(d => list.push({ logId: d.id, ...d.data() } as any));
        setAuditLogs(list);
      });

      return () => {
        unsubCustomers();
        unsubPartners();
        unsubBookings();
        unsubDeliveries();
        unsubPayments();
        unsubTickets();
        unsubPromos();
        unsubAudit();
      };
    } else {
      // 2. SIMULATION/LOCAL STORAGE Mode
      setIsLive(false);
      
      const loadLocalData = () => {
        const getOrSet = (key: string, initial: any) => {
          const stored = localStorage.getItem(key);
          if (stored) {
            try { return JSON.parse(stored); } catch (e) {}
          }
          localStorage.setItem(key, JSON.stringify(initial));
          return initial;
        };

        setCustomers(getOrSet('staydriv_customers', mockCustomers));
        setPartners(getOrSet('staydriv_partners', mockPartners));
        setBookings(getOrSet('staydriv_bookings', mockBookings));
        setDeliveries(getOrSet('staydriv_deliveries', mockDeliveries));
        setPayments(getOrSet('staydriv_payments', mockPayments));
        setSupportTickets(getOrSet('staydriv_tickets', mockSupportTickets));
        setPromoCodes(getOrSet('staydriv_promos', mockPromoCodes));
        setAuditLogs(getOrSet('staydriv_audit_logs', mockAuditLogs));
        setConfig(getOrSet('staydriv_config', mockConfig));
      };

      loadLocalData();
    }
  }, [isLive]);

  // Logger helper
  const addAuditLog = async (action: string, details: string) => {
    const log: AuditLog = {
      logId: 'LOG_' + Date.now(),
      adminId: user?.uid || 'anonymous',
      adminEmail: user?.email || 'anonymous',
      action,
      details,
      ipAddress: '127.0.0.1',
      timestamp: new Date().toISOString()
    };

    if (isLive) {
      try {
        const savedConfig = JSON.parse(localStorage.getItem('staydriv_fb_config') || '{}');
        const app = getApp();
        const dbInstance = getFirestore(app);
        await setDoc(doc(dbInstance, 'audit_logs', log.logId), log);
      } catch (e) {
        console.error(e);
      }
    } else {
      const logs = [log, ...auditLogs];
      setAuditLogs(logs);
      localStorage.setItem('staydriv_audit_logs', JSON.stringify(logs));
    }
  };

  // ---------------- ADMIN ACTIONS IMPLEMENTATIONS ----------------

  const blockCustomer = async (uid: string, blocked: boolean) => {
    if (isLive) {
      const app = getApp();
      const dbInstance = getFirestore(app);
      await updateDoc(doc(dbInstance, 'users', uid), { status: blocked ? 'blocked' : 'active' });
    } else {
      const list = customers.map(c => c.uid === uid ? { ...c, status: (blocked ? 'blocked' : 'active') as any } : c);
      setCustomers(list);
      localStorage.setItem('staydriv_customers', JSON.stringify(list));
    }
    await addAuditLog('BLOCK_CUSTOMER', `${blocked ? 'Blocked' : 'Unblocked'} customer account: ${uid}`);
  };

  const verifyPartner = async (uid: string, status: Partner['status']) => {
    if (isLive) {
      const app = getApp();
      const dbInstance = getFirestore(app);
      await updateDoc(doc(dbInstance, 'partners', uid), { status });
    } else {
      const list = partners.map(p => p.uid === uid ? { ...p, status } : p);
      setPartners(list);
      localStorage.setItem('staydriv_partners', JSON.stringify(list));
    }
    await addAuditLog('VERIFY_PARTNER', `Updated partner ${uid} status to: ${status}`);
  };

  const assignDriver = async (bookingId: string, driverId: string, isDelivery = false) => {
    const driver = partners.find(p => p.uid === driverId);
    if (!driver) return;

    if (isLive) {
      const app = getApp();
      const dbInstance = getFirestore(app);
      const collectionName = isDelivery ? 'deliveries' : 'bookings';
      await updateDoc(doc(dbInstance, collectionName, bookingId), {
        driverId: driver.uid,
        driverName: driver.name,
        vehiclePlate: driver.vehiclePlate,
        vehicleModelColor: driver.vehicleModelColor,
        status: 'accepted'
      });
    } else {
      if (isDelivery) {
        const list = deliveries.map(d => d.bookingId === bookingId ? {
          ...d,
          driverId: driver.uid,
          driverName: driver.name,
          vehiclePlate: driver.vehiclePlate,
          vehicleModelColor: driver.vehicleModelColor,
          status: 'accepted' as any
        } : d);
        setDeliveries(list);
        localStorage.setItem('staydriv_deliveries', JSON.stringify(list));
      } else {
        const list = bookings.map(b => b.bookingId === bookingId ? {
          ...b,
          driverId: driver.uid,
          driverName: driver.name,
          vehiclePlate: driver.vehiclePlate,
          vehicleModelColor: driver.vehicleModelColor,
          status: 'accepted' as any
        } : b);
        setBookings(list);
        localStorage.setItem('staydriv_bookings', JSON.stringify(list));
      }
    }
    await addAuditLog('ASSIGN_DRIVER', `Manually assigned driver ${driver.name} (${driverId}) to booking ${bookingId}`);
  };

  const cancelBooking = async (bookingId: string, isDelivery = false) => {
    if (isLive) {
      const app = getApp();
      const dbInstance = getFirestore(app);
      const collectionName = isDelivery ? 'deliveries' : 'bookings';
      await updateDoc(doc(dbInstance, collectionName, bookingId), { status: 'cancelled' });
    } else {
      if (isDelivery) {
        const list = deliveries.map(d => d.bookingId === bookingId ? { ...d, status: 'cancelled' as any } : d);
        setDeliveries(list);
        localStorage.setItem('staydriv_deliveries', JSON.stringify(list));
      } else {
        const list = bookings.map(b => b.bookingId === bookingId ? { ...b, status: 'cancelled' as any } : b);
        setBookings(list);
        localStorage.setItem('staydriv_bookings', JSON.stringify(list));
      }
    }
    await addAuditLog('CANCEL_BOOKING', `Cancelled booking ${bookingId}`);
  };

  const processWithdrawal = async (txnId: string, approve: boolean) => {
    // Withdrawal requests are records in payments with type: 'withdrawal'
    if (isLive) {
      const app = getApp();
      const dbInstance = getFirestore(app);
      await updateDoc(doc(dbInstance, 'payments', txnId), { status: approve ? 'completed' : 'failed' });
    } else {
      const list = payments.map(p => p.transactionId === txnId ? { ...p, status: (approve ? 'completed' : 'failed') as any } : p);
      setPayments(list);
      localStorage.setItem('staydriv_payments', JSON.stringify(list));
      
      // If approved, adjust driver's wallet balance
      if (approve) {
        const paymentItem = payments.find(p => p.transactionId === txnId);
        if (paymentItem) {
          const updatedPartners = partners.map(p => p.uid === paymentItem.userId ? { ...p, walletBalance: p.walletBalance - paymentItem.amount } : p);
          setPartners(updatedPartners);
          localStorage.setItem('staydriv_partners', JSON.stringify(updatedPartners));
        }
      }
    }
    await addAuditLog('WITHDRAWAL_PROCESS', `${approve ? 'Approved' : 'Rejected'} withdrawal transaction: ${txnId}`);
  };

  const updateCommissionRate = async (percent: number) => {
    if (isLive) {
      const app = getApp();
      const dbInstance = getFirestore(app);
      await setDoc(doc(dbInstance, 'configurations', 'settings'), { commissionPercent: percent }, { merge: true });
    } else {
      const newConfig = { ...config, commissionPercent: percent };
      setConfig(newConfig);
      localStorage.setItem('staydriv_config', JSON.stringify(newConfig));
    }
    await addAuditLog('UPDATE_COMMISSION', `Adjusted platform commission percentage to ${percent}%`);
  };

  const updateBaseFare = async (category: string, amount: number) => {
    if (isLive) {
      const app = getApp();
      const dbInstance = getFirestore(app);
      await setDoc(doc(dbInstance, 'configurations', 'settings'), { baseFares: { [category]: amount } }, { merge: true });
    } else {
      const baseFares = { ...config.baseFares, [category]: amount };
      const newConfig = { ...config, baseFares };
      setConfig(newConfig);
      localStorage.setItem('staydriv_config', JSON.stringify(newConfig));
    }
    await addAuditLog('UPDATE_BASE_FARE', `Adjusted base fare for ${category} to ₹${amount}`);
  };

  const updatePerKmRate = async (category: string, amount: number) => {
    if (isLive) {
      const app = getApp();
      const dbInstance = getFirestore(app);
      await setDoc(doc(dbInstance, 'configurations', 'settings'), { perKmRates: { [category]: amount } }, { merge: true });
    } else {
      const perKmRates = { ...config.perKmRates, [category]: amount };
      const newConfig = { ...config, perKmRates };
      setConfig(newConfig);
      localStorage.setItem('staydriv_config', JSON.stringify(newConfig));
    }
    await addAuditLog('UPDATE_PER_KM_RATE', `Adjusted per-km rate for ${category} to ₹${amount}`);
  };

  const createPromoCode = async (promo: Omit<PromoCode, 'usageCount'>) => {
    const newPromo: PromoCode = { ...promo, usageCount: 0 };
    if (isLive) {
      const app = getApp();
      const dbInstance = getFirestore(app);
      await setDoc(doc(dbInstance, 'promo_codes', promo.code.toUpperCase()), newPromo);
    } else {
      const list = [newPromo, ...promoCodes];
      setPromoCodes(list);
      localStorage.setItem('staydriv_promos', JSON.stringify(list));
    }
    await addAuditLog('CREATE_PROMO', `Created promo code: ${promo.code} (${promo.discountPercentage}% off)`);
  };

  const togglePromoCode = async (code: string) => {
    if (isLive) {
      const app = getApp();
      const dbInstance = getFirestore(app);
      const current = promoCodes.find(p => p.code === code);
      if (current) {
        await updateDoc(doc(dbInstance, 'promo_codes', code), { status: current.status === 'active' ? 'inactive' : 'active' });
      }
    } else {
      const list = promoCodes.map(p => p.code === code ? { ...p, status: (p.status === 'active' ? 'inactive' : 'active') as any } : p);
      setPromoCodes(list);
      localStorage.setItem('staydriv_promos', JSON.stringify(list));
    }
    await addAuditLog('TOGGLE_PROMO', `Toggled promo code status: ${code}`);
  };

  const broadcastNotification = async (notification: { title: string; body: string; type: 'push' | 'promo' | 'alert' | 'emergency'; targetGroup: 'all' | 'customers' | 'partners' }) => {
    const newNotif = {
      notificationId: 'NTF_' + Date.now(),
      ...notification,
      sentAt: new Date().toISOString(),
      sentBy: user?.name || 'Admin'
    };

    if (isLive) {
      const app = getApp();
      const dbInstance = getFirestore(app);
      await setDoc(doc(dbInstance, 'notifications', newNotif.notificationId), newNotif);
    } else {
      // In simulation mode, add transaction elements or push alerts
      alert(`[PUSH BROADCAST SENT] \nTo: ${notification.targetGroup.toUpperCase()} \nTitle: ${notification.title} \nBody: ${notification.body}`);
    }
    await addAuditLog('BROADCAST_NOTIFICATION', `Sent ${notification.type} push campaign: "${notification.title}" to ${notification.targetGroup}`);
  };

  const replyToSupportTicket = async (ticketId: string, message: string) => {
    if (!user) return;
    const newMessage = {
      senderId: user.uid,
      senderName: user.name,
      message,
      timestamp: new Date().toISOString()
    };

    if (isLive) {
      const app = getApp();
      const dbInstance = getFirestore(app);
      const currentTicket = supportTickets.find(t => t.ticketId === ticketId);
      if (currentTicket) {
        await updateDoc(doc(dbInstance, 'support_tickets', ticketId), {
          status: 'resolved',
          chatHistory: [...currentTicket.chatHistory, newMessage]
        });
      }
    } else {
      const list = supportTickets.map(t => {
        if (t.ticketId === ticketId) {
          return {
            ...t,
            status: 'resolved' as any,
            chatHistory: [...t.chatHistory, newMessage]
          };
        }
        return t;
      });
      setSupportTickets(list);
      localStorage.setItem('staydriv_tickets', JSON.stringify(list));
    }
    await addAuditLog('TICKET_RESOLVE', `Responded and resolved ticket: ${ticketId}`);
  };

  // Firebase configurations management from UI Settings panel
  const saveFirebaseConfig = (cfg: any) => {
    localStorage.setItem('staydriv_fb_config', JSON.stringify(cfg));
    // Reload page to re-trigger database listeners
    window.location.reload();
  };

  const clearFirebaseConfig = () => {
    localStorage.removeItem('staydriv_fb_config');
    window.location.reload();
  };

  const getFirebaseConfig = () => {
    const stored = localStorage.getItem('staydriv_fb_config');
    return stored ? JSON.parse(stored) : { apiKey: '', authDomain: '', projectId: '', storageBucket: '', messagingSenderId: '', appId: '' };
  };

  return (
    <DatabaseContext.Provider value={{
      isLive, isOnline, customers, partners, bookings, deliveries, payments, supportTickets, promoCodes, auditLogs, config,
      blockCustomer, verifyPartner, assignDriver, cancelBooking, processWithdrawal,
      updateCommissionRate, updateBaseFare, updatePerKmRate, createPromoCode, togglePromoCode, broadcastNotification, replyToSupportTicket,
      saveFirebaseConfig, clearFirebaseConfig, getFirebaseConfig
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
