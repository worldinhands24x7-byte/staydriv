import React, { useState, useEffect, useRef, useCallback } from 'react';
import { 
  Search, X, Loader2, User, Bike, Car, Utensils, Store, 
  CreditCard, AlertCircle, ArrowRight, Calendar, Phone, 
  ExternalLink, ChevronRight, ShieldCheck, Clock, CheckCircle2,
  Package, DollarSign, LifeBuoy
} from 'lucide-react';
import { useDatabase } from '../context/DatabaseContext';

export interface SearchResultItem {
  id: string;
  recordId: string;
  title: string;
  subtitle: string;
  module: 'pilots' | 'customers' | 'rides' | 'food_orders' | 'restaurants' | 'daily_plans' | 'payments' | 'withdrawals' | 'complaints';
  moduleLabel: string;
  matchContext: string;
  status: string;
  statusType?: 'success' | 'warning' | 'error' | 'info';
  date?: string | null;
  targetTab: string;
  filterParam: string;
  rawDetails?: Record<string, any>;
}

export interface GroupedSearchResults {
  pilots: SearchResultItem[];
  customers: SearchResultItem[];
  rides: SearchResultItem[];
  food_orders: SearchResultItem[];
  restaurants: SearchResultItem[];
  daily_plans: SearchResultItem[];
  payments: SearchResultItem[];
  withdrawals: SearchResultItem[];
  complaints: SearchResultItem[];
}

export const GlobalSearch: React.FC = () => {
  const { customers, partners, bookings, deliveries, withdrawals } = useDatabase();
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<SearchResultItem[]>([]);
  const [groupedResults, setGroupedResults] = useState<GroupedSearchResults>({
    pilots: [],
    customers: [],
    rides: [],
    food_orders: [],
    restaurants: [],
    daily_plans: [],
    payments: [],
    withdrawals: [],
    complaints: []
  });
  const [selectedModuleFilter, setSelectedModuleFilter] = useState<string>('all');
  const [selectedIndex, setSelectedIndex] = useState<number>(-1);
  const [isLoading, setIsLoading] = useState(false);
  const [isOpen, setIsOpen] = useState(false);
  const [showAllModal, setShowAllModal] = useState(false);

  const containerRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const abortControllerRef = useRef<AbortController | null>(null);

  // Helper to resolve backend base URL
  const getBackendUrl = () => {
    return (window as any).REACT_APP_BACKEND_URL || 
      ((window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1')
        ? `${window.location.protocol}//${window.location.hostname}:3000`
        : window.location.origin);
  };

  // Helper for admin authorization headers
  const getAuthHeaders = () => {
    const token = localStorage.getItem('staydriv_admin_token') || 'staydriv_admin_secret_2026';
    return {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
      'x-admin-key': 'staydriv_admin_secret_2026'
    };
  };

  // Global Keyboard Shortcut: Ctrl + K (or Cmd + K) to focus search
  useEffect(() => {
    const handleGlobalKeyDown = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        inputRef.current?.focus();
        setIsOpen(true);
      }
    };
    window.addEventListener('keydown', handleGlobalKeyDown);
    return () => window.removeEventListener('keydown', handleGlobalKeyDown);
  }, []);

  // Click outside listener to dismiss dropdown
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setIsOpen(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  // Live Debounced Backend Search Query (300ms)
  useEffect(() => {
    const trimmed = query.trim();
    if (!trimmed) {
      setResults([]);
      setGroupedResults({
        pilots: [],
        customers: [],
        rides: [],
        food_orders: [],
        restaurants: [],
        daily_plans: [],
        payments: [],
        withdrawals: [],
        complaints: []
      });
      setIsLoading(false);
      setSelectedIndex(-1);
      return;
    }

    setIsLoading(true);

    if (abortControllerRef.current) {
      abortControllerRef.current.abort();
    }
    const controller = new AbortController();
    abortControllerRef.current = controller;

    const timer = setTimeout(async () => {
      try {
        const backendUrl = getBackendUrl();
        const headers = getAuthHeaders();
        const res = await fetch(
          `${backendUrl}/api/admin/global-search?q=${encodeURIComponent(trimmed)}&limit=15`,
          {
            headers,
            signal: controller.signal
          }
        );

        if (res.ok) {
          const data = await res.json();
          if (data && data.success) {
            setResults(data.results || []);
            setGroupedResults(data.groupedResults || {
              pilots: [],
              customers: [],
              rides: [],
              food_orders: [],
              restaurants: [],
              daily_plans: [],
              payments: [],
              withdrawals: [],
              complaints: []
            });
            setIsLoading(false);
            return;
          }
        }
        throw new Error('Fallback to local database context');
      } catch (err: any) {
        if (err.name === 'AbortError') return;

        // Fallback search against live local DatabaseContext caches
        const qLower = trimmed.toLowerCase();
        const localMatches: SearchResultItem[] = [];
        const localGrouped: GroupedSearchResults = {
          pilots: [],
          customers: [],
          rides: [],
          food_orders: [],
          restaurants: [],
          daily_plans: [],
          payments: [],
          withdrawals: [],
          complaints: []
        };

        // Fallback Pilots
        (partners || []).forEach(p => {
          if (
            (p.name && p.name.toLowerCase().includes(qLower)) ||
            (p.phone && p.phone.includes(trimmed)) ||
            (p.uid && p.uid.toLowerCase().includes(qLower)) ||
            (p.vehiclePlate && p.vehiclePlate.toLowerCase().includes(qLower))
          ) {
            const item: SearchResultItem = {
              id: `pilot_${p.uid}`,
              recordId: p.uid || p.applicationId || 'PILOT',
              title: p.name || 'Pilot Partner',
              subtitle: `${p.vehicleType || 'Vehicle'} • ${p.vehiclePlate || 'Plate'} • 📞 ${p.phone || 'N/A'}`,
              module: 'pilots',
              moduleLabel: 'Pilot / Driver',
              matchContext: `Phone: ${p.phone || 'N/A'}`,
              status: p.status || 'APPROVED',
              statusType: 'success',
              targetTab: 'pilot-management',
              filterParam: p.phone || p.name || p.uid
            };
            localMatches.push(item);
            localGrouped.pilots.push(item);
          }
        });

        // Fallback Customers
        (customers || []).forEach(c => {
          if (
            (c.name && c.name.toLowerCase().includes(qLower)) ||
            (c.phone && c.phone.includes(trimmed)) ||
            (c.uid && c.uid.toLowerCase().includes(qLower))
          ) {
            const item: SearchResultItem = {
              id: `cust_${c.uid}`,
              recordId: c.uid,
              title: c.name || 'Customer',
              subtitle: `Customer • 📞 ${c.phone || 'N/A'}${c.email ? ` • ${c.email}` : ''}`,
              module: 'customers',
              moduleLabel: 'Customer',
              matchContext: `Phone: ${c.phone || 'N/A'}`,
              status: c.status || 'ACTIVE',
              statusType: 'success',
              targetTab: 'customers',
              filterParam: c.phone || c.name || c.uid
            };
            localMatches.push(item);
            localGrouped.customers.push(item);
          }
        });

        // Fallback Bookings / Rides
        (bookings || []).forEach(b => {
          if (
            (b.bookingId && b.bookingId.toLowerCase().includes(qLower)) ||
            (b.customerName && b.customerName.toLowerCase().includes(qLower)) ||
            (b.driverName && b.driverName.toLowerCase().includes(qLower))
          ) {
            const item: SearchResultItem = {
              id: `bk_${b.bookingId}`,
              recordId: b.bookingId,
              title: `${b.bookingId} (${b.vehicle || 'Ride'})`,
              subtitle: `Customer: ${b.customerName || 'N/A'} • Pilot: ${b.driverName || 'Unassigned'} • ₹${(b as any).fare || b.price || 0}`,
              module: 'rides',
              moduleLabel: 'Ride Booking',
              matchContext: `Booking ID: ${b.bookingId}`,
              status: (b.status || 'PENDING').toUpperCase(),
              statusType: 'info',
              targetTab: 'rides',
              filterParam: b.bookingId
            };
            localMatches.push(item);
            localGrouped.rides.push(item);
          }
        });

        setResults(localMatches);
        setGroupedResults(localGrouped);
        setIsLoading(false);
      }
    }, 300);

    return () => clearTimeout(timer);
  }, [query, partners, customers, bookings]);

  // Filter results by selected module tab
  const displayedResults = selectedModuleFilter === 'all'
    ? results
    : results.filter(r => r.module === selectedModuleFilter);

  // Keyboard navigation inside search dropdown (Up, Down, Enter, Escape)
  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Escape') {
      setIsOpen(false);
      setShowAllModal(false);
      inputRef.current?.blur();
      return;
    }

    if (e.key === 'ArrowDown') {
      e.preventDefault();
      if (!isOpen) setIsOpen(true);
      setSelectedIndex(prev => (prev < displayedResults.length - 1 ? prev + 1 : 0));
      return;
    }

    if (e.key === 'ArrowUp') {
      e.preventDefault();
      if (!isOpen) setIsOpen(true);
      setSelectedIndex(prev => (prev > 0 ? prev - 1 : displayedResults.length - 1));
      return;
    }

    if (e.key === 'Enter') {
      e.preventDefault();
      if (selectedIndex >= 0 && selectedIndex < displayedResults.length) {
        handleSelectResult(displayedResults[selectedIndex]);
      } else if (displayedResults.length > 0) {
        // If Enter is pressed without specific selection, view all modal
        setShowAllModal(true);
      }
    }
  };

  // Execute navigation to selected result
  const handleSelectResult = (item: SearchResultItem) => {
    // 1. Store the search term in sessionStorage so destination page can filter immediately
    if (item.filterParam) {
      sessionStorage.setItem('admin_auto_filter', item.filterParam);
    }

    // 2. Dispatch custom event for real-time listener if page is already open
    window.dispatchEvent(
      new CustomEvent('admin:search-navigate', {
        detail: {
          tab: item.targetTab,
          filter: item.filterParam,
          item
        }
      })
    );

    // 3. Switch tab via URL hash change
    window.location.hash = `#${item.targetTab}`;

    // 4. Close dropdown and modal
    setIsOpen(false);
    setShowAllModal(false);
  };

  // Clear query
  const handleClear = () => {
    setQuery('');
    setResults([]);
    setSelectedIndex(-1);
    inputRef.current?.focus();
  };

  // Helper for module icon
  const getModuleIcon = (module: string) => {
    switch (module) {
      case 'pilots': return <Bike size={14} className="text-emerald-500" />;
      case 'customers': return <User size={14} className="text-blue-500" />;
      case 'rides': return <Car size={14} className="text-indigo-500" />;
      case 'food_orders': return <Utensils size={14} className="text-orange-500" />;
      case 'restaurants': return <Store size={14} className="text-amber-500" />;
      case 'daily_plans': return <CreditCard size={14} className="text-emerald-500" />;
      case 'payments': return <DollarSign size={14} className="text-green-500" />;
      case 'withdrawals': return <ArrowRight size={14} className="text-purple-500" />;
      case 'complaints': return <AlertCircle size={14} className="text-rose-500" />;
      default: return <Search size={14} className="text-gray-400" />;
    }
  };

  // Helper for status badge styling
  const getStatusBadgeStyle = (statusType?: string) => {
    switch (statusType) {
      case 'success':
        return {
          backgroundColor: 'rgba(16, 185, 129, 0.14)',
          color: '#10b981',
          border: '1px solid rgba(16, 185, 129, 0.3)'
        };
      case 'error':
        return {
          backgroundColor: 'rgba(239, 68, 68, 0.14)',
          color: '#ef4444',
          border: '1px solid rgba(239, 68, 68, 0.3)'
        };
      case 'warning':
        return {
          backgroundColor: 'rgba(245, 158, 11, 0.14)',
          color: '#f59e0b',
          border: '1px solid rgba(245, 158, 11, 0.3)'
        };
      case 'info':
      default:
        return {
          backgroundColor: 'rgba(59, 130, 246, 0.14)',
          color: '#3b82f6',
          border: '1px solid rgba(59, 130, 246, 0.3)'
        };
    }
  };

  const moduleCategories = [
    { id: 'all', label: 'All', count: results.length },
    { id: 'pilots', label: 'Pilots', count: groupedResults.pilots.length },
    { id: 'rides', label: 'Rides', count: groupedResults.rides.length },
    { id: 'food_orders', label: 'Food', count: groupedResults.food_orders.length },
    { id: 'customers', label: 'Customers', count: groupedResults.customers.length },
    { id: 'restaurants', label: 'Restaurants', count: groupedResults.restaurants.length },
    { id: 'daily_plans', label: 'Plans', count: groupedResults.daily_plans.length },
    { id: 'payments', label: 'Payments', count: groupedResults.payments.length },
    { id: 'withdrawals', label: 'Withdrawals', count: groupedResults.withdrawals.length },
    { id: 'complaints', label: 'Complaints', count: groupedResults.complaints.length },
  ].filter(cat => cat.id === 'all' || cat.count > 0);

  return (
    <div 
      ref={containerRef} 
      className="global-search-container"
      style={{
        position: 'relative',
        flex: '1 1 380px',
        maxWidth: '540px',
        minWidth: '220px',
        margin: '0 12px'
      }}
    >
      {/* Search Input Bar */}
      <div 
        className="global-search-input-wrapper"
        style={{
          display: 'flex',
          alignItems: 'center',
          backgroundColor: 'var(--bg-input)',
          borderRadius: '10px',
          border: isOpen ? '1px solid var(--primary)' : '1px solid var(--border)',
          padding: '6px 12px',
          transition: 'all 0.2s ease',
          boxShadow: isOpen ? '0 0 0 3px rgba(59, 130, 246, 0.15)' : 'none',
          gap: '8px'
        }}
      >
        {isLoading ? (
          <Loader2 
            size={16} 
            style={{ 
              color: 'var(--primary)', 
              animation: 'spin 1s linear infinite', 
              flexShrink: 0 
            }} 
          />
        ) : (
          <Search 
            size={16} 
            style={{ 
              color: 'var(--text-muted)', 
              flexShrink: 0 
            }} 
          />
        )}

        <input
          ref={inputRef}
          type="text"
          value={query}
          onChange={(e) => {
            setQuery(e.target.value);
            if (!isOpen) setIsOpen(true);
          }}
          onFocus={() => setIsOpen(true)}
          onKeyDown={handleKeyDown}
          placeholder="Search anything by keyword, name, ID, phone, booking, payment..."
          style={{
            background: 'transparent',
            border: 'none',
            outline: 'none',
            color: 'var(--text-main)',
            fontSize: '13px',
            width: '100%',
            fontWeight: 500
          }}
          aria-label="Global Admin Search"
        />

        {query && (
          <button
            type="button"
            onClick={handleClear}
            style={{
              background: 'transparent',
              border: 'none',
              cursor: 'pointer',
              color: 'var(--text-muted)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              padding: '2px',
              borderRadius: '50%'
            }}
            title="Clear search"
          >
            <X size={14} />
          </button>
        )}

        {/* Keyboard shortcut pill */}
        <kbd
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            fontSize: '10px',
            fontWeight: 700,
            padding: '2px 6px',
            borderRadius: '5px',
            backgroundColor: 'var(--bg-card)',
            color: 'var(--text-muted)',
            border: '1px solid var(--border)',
            boxShadow: '0 1px 2px rgba(0,0,0,0.06)',
            letterSpacing: '0.02em',
            userSelect: 'none',
            flexShrink: 0
          }}
          title="Press Ctrl + K to focus search"
        >
          Ctrl K
        </kbd>
      </div>

      {/* Matching Results Live Dropdown */}
      {isOpen && query.trim().length > 0 && (
        <div
          className="global-search-dropdown"
          style={{
            position: 'absolute',
            top: 'calc(100% + 8px)',
            left: 0,
            right: 0,
            backgroundColor: 'var(--bg-card)',
            border: '1px solid var(--border)',
            borderRadius: '12px',
            boxShadow: '0 12px 30px rgba(0, 0, 0, 0.25)',
            zIndex: 1000,
            maxHeight: '480px',
            overflowY: 'auto',
            animation: 'fadeIn 0.15s ease'
          }}
        >
          {/* Module Filter Tabs */}
          {moduleCategories.length > 2 && (
            <div
              style={{
                display: 'flex',
                gap: '6px',
                padding: '8px 12px',
                borderBottom: '1px solid var(--border)',
                overflowX: 'auto',
                backgroundColor: 'var(--bg-input)'
              }}
            >
              {moduleCategories.map(cat => (
                <button
                  key={cat.id}
                  onClick={() => setSelectedModuleFilter(cat.id)}
                  style={{
                    padding: '3px 10px',
                    borderRadius: '16px',
                    fontSize: '11px',
                    fontWeight: 600,
                    border: 'none',
                    cursor: 'pointer',
                    whiteSpace: 'nowrap',
                    backgroundColor: selectedModuleFilter === cat.id ? 'var(--primary)' : 'var(--bg-card)',
                    color: selectedModuleFilter === cat.id ? '#ffffff' : 'var(--text-muted)',
                    boxShadow: selectedModuleFilter === cat.id ? '0 1px 3px rgba(59, 130, 246, 0.3)' : 'none',
                    transition: 'all 0.15s ease'
                  }}
                >
                  {cat.label} ({cat.count})
                </button>
              ))}
            </div>
          )}

          {/* Results List */}
          {displayedResults.length > 0 ? (
            <div style={{ padding: '6px 0' }}>
              {displayedResults.map((item, idx) => {
                const isSelected = idx === selectedIndex;
                return (
                  <div
                    key={item.id}
                    onClick={() => handleSelectResult(item)}
                    onMouseEnter={() => setSelectedIndex(idx)}
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'space-between',
                      padding: '10px 14px',
                      cursor: 'pointer',
                      borderBottom: '1px solid var(--border-inverse)',
                      backgroundColor: isSelected ? 'rgba(59, 130, 246, 0.08)' : 'transparent',
                      transition: 'background-color 0.15s ease',
                      gap: '12px'
                    }}
                  >
                    {/* Left Icon & Information */}
                    <div style={{ display: 'flex', alignItems: 'flex-start', gap: '10px', minWidth: 0, flex: 1 }}>
                      <div
                        style={{
                          width: '28px',
                          height: '28px',
                          borderRadius: '8px',
                          backgroundColor: 'var(--bg-input)',
                          display: 'flex',
                          alignItems: 'center',
                          justifyContent: 'center',
                          flexShrink: 0,
                          marginTop: '2px'
                        }}
                      >
                        {getModuleIcon(item.module)}
                      </div>

                      <div style={{ minWidth: 0, flex: 1 }}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '8px', flexWrap: 'wrap' }}>
                          <span style={{ fontWeight: 700, fontSize: '13px', color: 'var(--text-main)' }}>
                            {item.title}
                          </span>
                          <span
                            style={{
                              fontSize: '10px',
                              fontWeight: 700,
                              padding: '1px 6px',
                              borderRadius: '4px',
                              backgroundColor: 'rgba(99, 102, 241, 0.12)',
                              color: '#6366f1',
                              letterSpacing: '0.02em'
                            }}
                          >
                            {item.moduleLabel}
                          </span>
                        </div>

                        <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '2px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                          {item.subtitle}
                        </div>

                        {/* Match Context snippet */}
                        <div style={{ fontSize: '10px', color: 'var(--primary)', marginTop: '2px', fontWeight: 600 }}>
                          🎯 {item.matchContext}
                        </div>
                      </div>
                    </div>

                    {/* Right Status & Date */}
                    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: '4px', flexShrink: 0 }}>
                      {item.status && (
                        <span
                          style={{
                            fontSize: '10px',
                            fontWeight: 700,
                            padding: '2px 8px',
                            borderRadius: '12px',
                            textTransform: 'uppercase',
                            letterSpacing: '0.03em',
                            ...getStatusBadgeStyle(item.statusType)
                          }}
                        >
                          {item.status}
                        </span>
                      )}

                      {item.date && (
                        <span style={{ fontSize: '10px', color: 'var(--text-muted)' }}>
                          {new Date(item.date).toLocaleDateString('en-IN', {
                            day: 'numeric',
                            month: 'short'
                          })}
                        </span>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          ) : (
            /* Empty State */
            <div
              style={{
                padding: '32px 20px',
                textAlign: 'center',
                color: 'var(--text-muted)'
              }}
            >
              <AlertCircle size={28} style={{ margin: '0 auto 8px', color: 'var(--text-muted)', opacity: 0.7 }} />
              <div style={{ fontSize: '13px', fontWeight: 600, color: 'var(--text-main)' }}>
                No matching records found. Try another keyword.
              </div>
              <div style={{ fontSize: '11px', marginTop: '4px' }}>
                Search by Pilot Name, Phone, Plate, Customer ID, Booking ID, Transaction ID, or Restaurant.
              </div>
            </div>
          )}

          {/* Bottom Bar: Result Count & Actions */}
          {displayedResults.length > 0 && (
            <div
              style={{
                padding: '8px 14px',
                backgroundColor: 'var(--bg-input)',
                borderTop: '1px solid var(--border)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
                fontSize: '11px',
                color: 'var(--text-muted)'
              }}
            >
              <span>
                Found <strong>{displayedResults.length}</strong> matching records
              </span>

              <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                <span style={{ fontSize: '10px', color: 'var(--text-muted)' }}>
                  ↑↓ navigate • ↵ select • esc close
                </span>
                {results.length > 5 && (
                  <button
                    onClick={() => setShowAllModal(true)}
                    style={{
                      padding: '3px 8px',
                      borderRadius: '6px',
                      fontSize: '11px',
                      fontWeight: 700,
                      backgroundColor: 'var(--primary)',
                      color: '#ffffff',
                      border: 'none',
                      cursor: 'pointer',
                      display: 'inline-flex',
                      alignItems: 'center',
                      gap: '4px'
                    }}
                  >
                    View All ({results.length})
                    <ChevronRight size={12} />
                  </button>
                )}
              </div>
            </div>
          )}
        </div>
      )}

      {/* Expanded "View All Results" Modal */}
      {showAllModal && (
        <div
          style={{
            position: 'fixed',
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            backgroundColor: 'rgba(0, 0, 0, 0.7)',
            backdropFilter: 'blur(4px)',
            zIndex: 9999,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            padding: '20px'
          }}
          onClick={() => setShowAllModal(false)}
        >
          <div
            style={{
              backgroundColor: 'var(--bg-card)',
              border: '1px solid var(--border)',
              borderRadius: '16px',
              width: '100%',
              maxWidth: '850px',
              maxHeight: '85vh',
              display: 'flex',
              flexDirection: 'column',
              boxShadow: '0 20px 40px rgba(0, 0, 0, 0.4)',
              overflow: 'hidden'
            }}
            onClick={(e) => e.stopPropagation()}
          >
            {/* Modal Header */}
            <div
              style={{
                padding: '16px 24px',
                borderBottom: '1px solid var(--border)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
                backgroundColor: 'var(--bg-input)'
              }}
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                <Search size={20} style={{ color: 'var(--primary)' }} />
                <div>
                  <h3 style={{ fontSize: '16px', fontWeight: 700, margin: 0 }}>
                    Global Search Results for "{query}"
                  </h3>
                  <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
                    Total {results.length} records found across all modules
                  </div>
                </div>
              </div>

              <button
                onClick={() => setShowAllModal(false)}
                style={{
                  background: 'transparent',
                  border: 'none',
                  cursor: 'pointer',
                  color: 'var(--text-muted)',
                  padding: '4px'
                }}
              >
                <X size={20} />
              </button>
            </div>

            {/* Modal Category Filter Tabs */}
            <div
              style={{
                display: 'flex',
                gap: '8px',
                padding: '12px 24px',
                borderBottom: '1px solid var(--border)',
                overflowX: 'auto'
              }}
            >
              {moduleCategories.map(cat => (
                <button
                  key={cat.id}
                  onClick={() => setSelectedModuleFilter(cat.id)}
                  style={{
                    padding: '6px 14px',
                    borderRadius: '20px',
                    fontSize: '12px',
                    fontWeight: 700,
                    border: 'none',
                    cursor: 'pointer',
                    backgroundColor: selectedModuleFilter === cat.id ? 'var(--primary)' : 'var(--bg-input)',
                    color: selectedModuleFilter === cat.id ? '#ffffff' : 'var(--text-muted)',
                    transition: 'all 0.15s ease'
                  }}
                >
                  {cat.label} ({cat.count})
                </button>
              ))}
            </div>

            {/* Modal Results Grid / List */}
            <div
              style={{
                padding: '16px 24px',
                overflowY: 'auto',
                flex: 1,
                display: 'grid',
                gridTemplateColumns: 'repeat(auto-fill, minmax(360px, 1fr))',
                gap: '12px'
              }}
            >
              {displayedResults.map(item => (
                <div
                  key={item.id}
                  onClick={() => handleSelectResult(item)}
                  style={{
                    backgroundColor: 'var(--bg-input)',
                    border: '1px solid var(--border)',
                    borderRadius: '12px',
                    padding: '14px',
                    cursor: 'pointer',
                    display: 'flex',
                    flexDirection: 'column',
                    justifyContent: 'space-between',
                    gap: '10px',
                    transition: 'all 0.2s ease',
                    boxShadow: '0 2px 4px rgba(0,0,0,0.05)'
                  }}
                  onMouseEnter={(e) => {
                    e.currentTarget.style.borderColor = 'var(--primary)';
                    e.currentTarget.style.transform = 'translateY(-2px)';
                  }}
                  onMouseLeave={(e) => {
                    e.currentTarget.style.borderColor = 'var(--border)';
                    e.currentTarget.style.transform = 'none';
                  }}
                >
                  <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: '8px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                      <div
                        style={{
                          width: '28px',
                          height: '28px',
                          borderRadius: '6px',
                          backgroundColor: 'var(--bg-card)',
                          display: 'flex',
                          alignItems: 'center',
                          justifyContent: 'center'
                        }}
                      >
                        {getModuleIcon(item.module)}
                      </div>
                      <div>
                        <span style={{ fontSize: '11px', fontWeight: 700, color: 'var(--primary)' }}>
                          {item.moduleLabel}
                        </span>
                        <div style={{ fontWeight: 700, fontSize: '13px', color: 'var(--text-main)' }}>
                          {item.title}
                        </div>
                      </div>
                    </div>

                    {item.status && (
                      <span
                        style={{
                          fontSize: '10px',
                          fontWeight: 700,
                          padding: '2px 8px',
                          borderRadius: '12px',
                          textTransform: 'uppercase',
                          ...getStatusBadgeStyle(item.statusType)
                        }}
                      >
                        {item.status}
                      </span>
                    )}
                  </div>

                  <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
                    {item.subtitle}
                  </div>

                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', paddingTop: '8px', borderTop: '1px solid var(--border)', fontSize: '11px' }}>
                    <span style={{ color: 'var(--primary)', fontWeight: 600 }}>
                      🎯 {item.matchContext}
                    </span>
                    <span style={{ color: 'var(--primary)', display: 'inline-flex', alignItems: 'center', gap: '4px', fontWeight: 700 }}>
                      Open Module
                      <ExternalLink size={12} />
                    </span>
                  </div>
                </div>
              ))}
            </div>

            {/* Modal Footer */}
            <div
              style={{
                padding: '12px 24px',
                borderTop: '1px solid var(--border)',
                display: 'flex',
                justifyContent: 'flex-end',
                backgroundColor: 'var(--bg-input)'
              }}
            >
              <button
                onClick={() => setShowAllModal(false)}
                className="btn btn-secondary"
                style={{ padding: '6px 16px', fontSize: '12px' }}
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default GlobalSearch;
