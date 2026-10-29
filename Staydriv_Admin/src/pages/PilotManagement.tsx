import React, { useState } from 'react';
import { useDatabase } from '../context/DatabaseContext';
import { 
  Users, Search, ShieldCheck, ShieldAlert, Bike, Car, Truck, 
  CheckCircle2, Clock, Phone, AlertCircle, Lock, Unlock, RefreshCw, X, ShieldX,
  Power, PowerOff
} from 'lucide-react';

export const PilotManagement: React.FC = () => {
  const { 
    partners, 
    updatePilotBookingAccess, 
    togglePilotDuty, 
    updatePilotServicePreferences,
    blockCustomer, 
    refreshAllData, 
    lastUpdatedTime 
  } = useDatabase();
  const [searchTerm, setSearchTerm] = useState(() => {
    const auto = sessionStorage.getItem('admin_auto_filter');
    if (auto) {
      sessionStorage.removeItem('admin_auto_filter');
      return auto;
    }
    return '';
  });

  React.useEffect(() => {
    const handleSearchNav = (e: any) => {
      if (e.detail?.filter && (e.detail?.tab === 'pilot-management' || !e.detail?.tab)) {
        setSearchTerm(e.detail.filter);
      }
    };
    window.addEventListener('admin:search-navigate', handleSearchNav);
    return () => window.removeEventListener('admin:search-navigate', handleSearchNav);
  }, []);
  const [vehicleFilter, setVehicleFilter] = useState('all');
  const [statusFilter, setStatusFilter] = useState('all');
  const [bookingAccessFilter, setBookingAccessFilter] = useState('all');
  const [dutyFilter, setDutyFilter] = useState('all');

  // Disable Modal state
  const [disableModalPilot, setDisableModalPilot] = useState<any | null>(null);
  const [disableReason, setDisableReason] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [feedbackToast, setFeedbackToast] = useState<{ message: string; type: 'success' | 'error' } | null>(null);

  const showToast = (message: string, type: 'success' | 'error' = 'success') => {
    setFeedbackToast({ message, type });
    setTimeout(() => setFeedbackToast(null), 4000);
  };

  const filteredPilots = (partners || []).filter(p => {
    const matchesSearch = 
      (p.name || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (p.phone || '').includes(searchTerm) ||
      (p.uid || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (p.applicationId || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (p.vehiclePlate || '').toLowerCase().includes(searchTerm.toLowerCase());

    const matchesVehicle = vehicleFilter === 'all' || 
      (vehicleFilter === 'bike' && (p.vehicleType || '').toLowerCase().includes('bike')) ||
      (vehicleFilter === 'auto' && (p.vehicleType || '').toLowerCase().includes('auto')) ||
      (vehicleFilter === 'car' && (p.vehicleType || '').toLowerCase().includes('car')) ||
      (vehicleFilter === 'mini_truck' && ((p.vehicleType || '').toLowerCase().includes('mini truck') || (p.vehicleType || '').toLowerCase().includes('pickup') || (p.vehicleType || '').toLowerCase().includes('ace') || (p.vehicleType || '').toLowerCase().includes('dost'))) ||
      (vehicleFilter === 'heavy_truck' && ((p.vehicleType || '').toLowerCase().includes('heavy truck') || (p.vehicleType || '').toLowerCase().includes('ton'))) ||
      (vehicleFilter === 'truck' && (p.vehicleType || '').toLowerCase().includes('truck')) ||
      (p.vehicleType || '').toLowerCase() === vehicleFilter.toLowerCase();
    
    let matchesStatus = true;
    const s = String(p.status || '').toUpperCase();
    const isAppr = Boolean(p.approved || (p as any).isApproved || s === 'APPROVED');
    const isPend = !isAppr && (s === 'PENDING' || s === 'PENDING_VERIFICATION' || s === 'SUBMITTED' || s === 'UNDER_REVIEW' || s === 'DRAFT' || !p.status);
    const isActReq = s === 'ACTION_REQUIRED' || s === 'RESUBMISSION_REQUIRED' || s === 'REJECTED';

    if (statusFilter === 'pending') matchesStatus = isPend;
    else if (statusFilter === 'action_required') matchesStatus = isActReq;
    else if (statusFilter === 'approved') matchesStatus = isAppr;
    else if (statusFilter === 'online') matchesStatus = !!p.online;
    else if (statusFilter === 'offline') matchesStatus = !p.online;
    else if (statusFilter === 'blocked') matchesStatus = !!p.isBlocked || s === 'SUSPENDED';

    // Booking access filter
    const isAccessEnabled = Boolean(
      (p as any).adminBookingEnabled === true || 
      (p as any).bookingAccessStatus === 'ENABLED' || 
      p.bookingAccess?.enabled === true || 
      p.bookingAccess?.status === 'enabled'
    );
    let matchesAccess = true;
    if (bookingAccessFilter === 'enabled') matchesAccess = isAccessEnabled;
    else if (bookingAccessFilter === 'disabled') matchesAccess = !isAccessEnabled;

    // Duty status filter
    const rawDuty = String((p as any).dutyStatus || (p as any).pilotDutyStatus || '').toUpperCase();
    const isDutyOn = rawDuty === 'ON' || rawDuty === 'DUTY ON' || (isAccessEnabled && !!p.online);
    let matchesDuty = true;
    if (dutyFilter === 'on') matchesDuty = isDutyOn;
    else if (dutyFilter === 'off') matchesDuty = !isDutyOn;

    return matchesSearch && matchesVehicle && matchesStatus && matchesAccess && matchesDuty;
  });

  const handleToggleDuty = async (pilot: any, targetDuty: 'DUTY_ON' | 'DUTY_OFF') => {
    try {
      setIsSubmitting(true);
      const pilotKey = pilot.uid || pilot.phone || (pilot as any)._id;
      const res = await togglePilotDuty(
        pilotKey,
        targetDuty,
        targetDuty === 'DUTY_ON' ? 'Duty activated by Administrator' : 'Duty switched OFF by Administrator'
      );
      if (res && res.success) {
        showToast(`Pilot ${pilot.name || pilotKey} duty switched to ${targetDuty === 'DUTY_ON' ? 'DUTY ON' : 'DUTY OFF'}.`);
        await refreshAllData();
      } else {
        showToast(res?.message || 'Failed to update pilot duty status.', 'error');
      }
    } catch (e: any) {
      showToast(e.message || 'Error updating pilot duty status.', 'error');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleEnableAccess = async (pilot: any) => {
    try {
      setIsSubmitting(true);
      const pilotKey = pilot.uid || pilot.phone || (pilot as any)._id;
      if (pilot.isBlocked) {
        await blockCustomer(pilotKey, false, 'Unblocked and enabled by Administrator');
      }
      const res = await updatePilotBookingAccess(pilotKey, 'ENABLE', 'Booking access enabled by Administrator');
      if (res && res.success) {
        showToast(`Booking access enabled for pilot ${pilot.name || pilotKey}. Pilot may now receive bookings.`);
        await refreshAllData();
      } else {
        showToast(res?.message || 'Failed to enable booking access.', 'error');
      }
    } catch (e: any) {
      showToast(e.message || 'Error enabling booking access.', 'error');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleToggleServicePreference = async (pilot: any, type: 'ride' | 'food') => {
    try {
      setIsSubmitting(true);
      const pilotKey = pilot.uid || pilot.phone || (pilot as any)._id;
      const currentVal = type === 'ride' 
        ? ((pilot as any).rideServiceEnabled !== false)
        : ((pilot as any).foodServiceEnabled !== false);
      const targetVal = !currentVal;
      
      const payload = type === 'ride' 
        ? { rideServiceEnabled: targetVal }
        : { foodServiceEnabled: targetVal };

      const res = await updatePilotServicePreferences(pilotKey, payload);
      if (res && res.success) {
        showToast(`Pilot ${pilot.name || pilotKey} ${type === 'ride' ? 'Ride Booking' : 'Food Delivery'} set to ${targetVal ? 'ENABLED' : 'DISABLED'}.`);
        await refreshAllData();
      } else {
        showToast(res?.message || 'Failed to update service preference.', 'error');
      }
    } catch (e: any) {
      showToast(e.message || 'Error updating service preference.', 'error');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleOpenDisableModal = (pilot: any) => {
    setDisableModalPilot(pilot);
    setDisableReason('');
  };

  const handleConfirmDisable = async () => {
    if (!disableModalPilot) return;
    if (!disableReason.trim()) {
      alert('Please provide a reason for disabling booking access.');
      return;
    }
    try {
      setIsSubmitting(true);
      const pilotKey = disableModalPilot.uid || disableModalPilot.phone || (disableModalPilot as any)._id;
      const res = await updatePilotBookingAccess(pilotKey, 'DISABLE', disableReason.trim());
      if (res && res.success) {
        showToast(`Booking access disabled for pilot ${disableModalPilot.name || pilotKey}. Duty switched OFF.`);
        setDisableModalPilot(null);
        setDisableReason('');
        await refreshAllData();
      } else {
        showToast(res?.message || 'Failed to disable booking access.', 'error');
      }
    } catch (e: any) {
      showToast(e.message || 'Error disabling booking access.', 'error');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleToggleBlock = async (pilot: any) => {
    const isCurrentlyBlocked = !!pilot.isBlocked;
    const confirmMsg = isCurrentlyBlocked 
      ? `Are you sure you want to unblock pilot ${pilot.name}?` 
      : `Are you sure you want to block pilot ${pilot.name}?`;

    if (!window.confirm(confirmMsg)) return;

    const reason = isCurrentlyBlocked 
      ? 'Unblocked by Admin' 
      : (window.prompt('Enter reason for blocking pilot:', 'Operational suspension') || 'Suspended by Admin');

    await blockCustomer(pilot.uid, !isCurrentlyBlocked, reason);
    await refreshAllData();
    showToast(`Pilot ${pilot.name} ${isCurrentlyBlocked ? 'unblocked' : 'blocked'} successfully.`);
  };

  const getVehicleIcon = (type: string) => {
    const t = (type || '').toLowerCase();
    if (t.includes('heavy')) return <Truck size={16} style={{ color: '#ea580c' }} />;
    if (t.includes('mini') || t.includes('truck')) return <Truck size={16} style={{ color: '#0284c7' }} />;
    if (t.includes('car')) return <Car size={16} style={{ color: '#2563eb' }} />;
    return <Bike size={16} style={{ color: '#16a34a' }} />;
  };

  const formatTimestamp = (d?: string | Date) => {
    if (!d) return 'N/A';
    try {
      const date = new Date(d);
      if (isNaN(date.getTime())) return 'N/A';
      return date.toLocaleDateString('en-IN', {
        day: '2-digit',
        month: 'short',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
      });
    } catch {
      return 'N/A';
    }
  };

  return (
    <div className="page-container">
      {/* Feedback Toast */}
      {feedbackToast && (
        <div style={{
          position: 'fixed',
          top: '20px',
          right: '24px',
          zIndex: 9999,
          background: feedbackToast.type === 'success' ? '#065f46' : '#991b1b',
          color: '#ffffff',
          padding: '12px 20px',
          borderRadius: '8px',
          boxShadow: '0 8px 24px rgba(0,0,0,0.25)',
          display: 'flex',
          alignItems: 'center',
          gap: '10px',
          fontWeight: 600,
          fontSize: '13px',
          border: `1px solid ${feedbackToast.type === 'success' ? '#10b981' : '#f87171'}`
        }}>
          {feedbackToast.type === 'success' ? <CheckCircle2 size={16} /> : <AlertCircle size={16} />}
          <span>{feedbackToast.message}</span>
        </div>
      )}

      {/* Top Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '16px' }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <h2>Pilot Fleet Operations & Directory</h2>
            <span style={{ 
              display: 'inline-flex', 
              alignItems: 'center', 
              gap: '6px', 
              padding: '4px 10px', 
              borderRadius: '20px', 
              fontSize: '11px', 
              fontWeight: 700, 
              background: 'rgba(59, 130, 246, 0.15)', 
              color: 'var(--primary)' 
            }}>
              <CheckCircle2 size={12} />
              REAL-TIME FLEET TELEMETRY
            </span>
          </div>
          <p style={{ color: 'var(--text-muted)', fontSize: '13px', marginTop: '4px' }}>
            Comprehensive directory of all onboarded pilots, real-time booking access controls, live duty status, vehicle assignments, and disciplinary governance.
          </p>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
          <button 
            className="btn btn-secondary btn-sm"
            onClick={() => refreshAllData()}
            style={{ display: 'flex', alignItems: 'center', gap: '6px' }}
          >
            <RefreshCw size={13} />
            Refresh
          </button>
          <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
            Updated: {lastUpdatedTime}
          </div>
        </div>
      </div>

      {/* Filter Toolbar */}
      <div className="card" style={{ padding: '16px' }}>
        <div style={{ display: 'flex', gap: '12px', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'space-between' }}>
          <div style={{ display: 'flex', gap: '12px', flex: '1', minWidth: '320px', flexWrap: 'wrap' }}>
            <div style={{ position: 'relative', flex: 1, minWidth: '220px' }}>
              <Search size={16} style={{ position: 'absolute', left: '12px', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
              <input 
                type="text"
                placeholder="Search pilot name, ID, phone, plate..."
                value={searchTerm}
                onChange={e => setSearchTerm(e.target.value)}
                className="input"
                style={{ paddingLeft: '36px', width: '100%' }}
              />
            </div>

            <select 
              value={vehicleFilter} 
              onChange={e => setVehicleFilter(e.target.value)}
              className="input"
              style={{ width: '140px' }}
            >
              <option value="all">All Vehicles</option>
              <option value="bike">Bike / Scooty</option>
              <option value="auto">Auto Rickshaw</option>
              <option value="car">Cab / Car</option>
              <option value="mini_truck">Mini Truck</option>
              <option value="heavy_truck">Heavy Truck</option>
              <option value="truck">All Trucks</option>
            </select>

            <select 
              value={bookingAccessFilter} 
              onChange={e => setBookingAccessFilter(e.target.value)}
              className="input"
              style={{ width: '160px' }}
            >
              <option value="all">Access: All</option>
              <option value="enabled">Access: ENABLED</option>
              <option value="disabled">Access: DISABLED</option>
            </select>

            <select 
              value={dutyFilter} 
              onChange={e => setDutyFilter(e.target.value)}
              className="input"
              style={{ width: '140px' }}
            >
              <option value="all">Duty: All</option>
              <option value="on">Duty: ON</option>
              <option value="off">Duty: OFF</option>
            </select>

            <select 
              value={statusFilter} 
              onChange={e => setStatusFilter(e.target.value)}
              className="input"
              style={{ width: '150px' }}
            >
              <option value="all">All Verification</option>
              <option value="approved">✓ Verified</option>
              <option value="pending">⏳ Pending KYC</option>
              <option value="action_required">⚠️ Action Required</option>
              <option value="blocked">Blocked / Suspended</option>
            </select>
          </div>

          <span style={{ fontSize: '13px', color: 'var(--text-muted)' }}>
            Showing <strong>{filteredPilots.length}</strong> of <strong>{partners?.length || 0}</strong> registered pilots
          </span>
        </div>
      </div>

      {/* Pilots Directory Table */}
      <div className="card" style={{ padding: '0', overflow: 'hidden' }}>
        <div className="table-responsive">
          <table className="data-table" style={{ fontSize: '12px' }}>
            <thead>
              <tr>
                <th>Pilot Profile</th>
                <th>Vehicle & Registration</th>
                <th>Current Status</th>
                <th>Availability</th>
                <th>Service Preferences</th>
                <th>Wallet Balance</th>
                <th>Total Earnings</th>
                <th>KYC Verification</th>
                <th>Disciplinary Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {filteredPilots.length === 0 ? (
                <tr>
                  <td colSpan={10} style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>
                    No pilots match the selected criteria.
                  </td>
                </tr>
              ) : (
                filteredPilots.map((p, idx) => {
                  const isAccessEnabled = Boolean(
                    (p as any).adminBookingEnabled === true || 
                    (p as any).bookingAccessStatus === 'ENABLED' || 
                    p.bookingAccess?.enabled === true || 
                    p.bookingAccess?.status === 'enabled'
                  );
                  const rawAccessReason = p.bookingAccess?.disabledReason || (p as any).bookingAccessReason || '';
                  const accessReason = (isAccessEnabled || /eligible for 100% earnings/i.test(rawAccessReason))
                    ? ''
                    : rawAccessReason;
                  
                  const rawDuty = String((p as any).dutyStatus || (p as any).pilotDutyStatus || '').toUpperCase();
                  const isDutyOn = rawDuty === 'ON' || rawDuty === 'DUTY ON' || (isAccessEnabled && !!p.online);

                  const dailyPlanObj = (p as any).dailyPlan || {};
                  const dailyPlanStatus = (p as any).dailyPlanStatus || (
                    dailyPlanObj.planStatus === 'paid' && dailyPlanObj.expiresAt && new Date(dailyPlanObj.expiresAt) > new Date()
                      ? 'PAID'
                      : (dailyPlanObj.planStatus === 'paid' || dailyPlanObj.planStatus === 'expired' ? 'EXPIRED' : 'UNPAID')
                  );

                  return (
                    <tr key={p.uid || idx}>
                      {/* 1. Pilot Profile */}
                      <td>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                          <div style={{ 
                            width: '36px', 
                            height: '36px', 
                            borderRadius: '50%', 
                            background: 'var(--bg-input)', 
                            display: 'flex', 
                            alignItems: 'center', 
                            justifyContent: 'center',
                            color: 'var(--primary)',
                            fontWeight: 700,
                            fontSize: '14px',
                            overflow: 'hidden'
                          }}>
                            {p.photo ? <img src={p.photo} alt={p.name} style={{ width: '100%', height: '100%', objectFit: 'cover' }} /> : (p.name ? p.name[0].toUpperCase() : 'P')}
                          </div>
                          <div>
                            <div style={{ fontWeight: 600, color: 'var(--text-main)' }}>{p.name || 'Pilot Partner'}</div>
                            <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>📞 {p.phone}</div>
                            {p.applicationId ? (
                              <div style={{ fontSize: '10px', color: '#38bdf8', fontFamily: 'monospace', fontWeight: 600 }}>
                                App: {p.applicationId}
                              </div>
                            ) : (
                              <div style={{ fontSize: '10px', color: '#38bdf8', fontFamily: 'monospace', fontWeight: 600 }}>
                                App: SD-PLT-{(p.phone || '').slice(-4)}-{(p.uid || '').slice(-4).toUpperCase()}
                              </div>
                            )}
                            <div style={{ fontSize: '10px', color: 'var(--text-muted)', fontFamily: 'monospace' }}>ID: {p.uid}</div>
                          </div>
                        </div>
                      </td>

                      {/* 2. Vehicle & Registration */}
                      <td>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                          {getVehicleIcon(p.vehicleType)}
                          <div>
                            <div style={{ fontWeight: 600 }}>{p.vehicleType || 'Bike'}</div>
                            <div style={{ fontSize: '11px', color: 'var(--text-muted)', fontFamily: 'monospace' }}>
                              {p.vehiclePlate || p.vehicleNumber || 'Unassigned Plate'}
                            </div>
                            <div style={{ fontSize: '10px', color: 'var(--text-muted)' }}>
                              {p.vehicleModelColor || 'Black Bike'}
                            </div>
                          </div>
                        </div>
                      </td>

                      {/* 3. Current Status (Online/Offline) */}
                      <td>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                          <span style={{
                            width: '8px',
                            height: '8px',
                            borderRadius: '50%',
                            background: p.online ? '#10b981' : '#64748b',
                            display: 'inline-block'
                          }} />
                          <span style={{
                            fontSize: '11px',
                            fontWeight: 700,
                            color: p.online ? '#10b981' : '#94a3b8'
                          }}>
                            {p.online ? 'ONLINE' : 'OFFLINE'}
                          </span>
                        </div>
                      </td>

                      {/* 4. Availability Column with Admin Booking Access Toggle (Exact location highlighted in Screenshot 2) */}
                      <td>
                        <div style={{ display: 'flex', flexDirection: 'column', gap: '6px', minWidth: '185px' }}>
                          {/* Toggle Switch row: OFF = Disabled, ON = Enabled */}
                          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                            <label 
                              style={{ 
                                position: 'relative', 
                                display: 'inline-block', 
                                width: '48px', 
                                height: '24px', 
                                margin: 0, 
                                cursor: isSubmitting ? 'not-allowed' : 'pointer' 
                              }}
                              title={isAccessEnabled ? "Booking Access: ENABLED (Click to Disable)" : "Booking Access: DISABLED (Click to Enable)"}
                            >
                              <input
                                type="checkbox"
                                checked={isAccessEnabled}
                                disabled={isSubmitting}
                                onChange={() => {
                                  if (isAccessEnabled) {
                                    handleOpenDisableModal(p);
                                  } else {
                                    handleEnableAccess(p);
                                  }
                                }}
                                style={{ opacity: 0, width: 0, height: 0, margin: 0 }}
                              />
                              <span style={{
                                position: 'absolute',
                                cursor: isSubmitting ? 'not-allowed' : 'pointer',
                                top: 0,
                                left: 0,
                                right: 0,
                                bottom: 0,
                                backgroundColor: isAccessEnabled ? '#10b981' : '#1e293b',
                                transition: 'all 0.25s cubic-bezier(0.4, 0, 0.2, 1)',
                                borderRadius: '24px',
                                boxShadow: isAccessEnabled ? '0 0 10px rgba(16, 185, 129, 0.45)' : 'inset 0 2px 4px rgba(0,0,0,0.5)',
                                border: `1.5px solid ${isAccessEnabled ? '#059669' : '#475569'}`
                              }}>
                                <span style={{
                                  position: 'absolute',
                                  content: '""',
                                  height: '18px',
                                  width: '18px',
                                  left: isAccessEnabled ? '25px' : '3px',
                                  bottom: '1.5px',
                                  backgroundColor: '#ffffff',
                                  transition: 'all 0.25s cubic-bezier(0.4, 0, 0.2, 1)',
                                  borderRadius: '50%',
                                  boxShadow: '0 2px 5px rgba(0, 0, 0, 0.35)'
                                }} />
                              </span>
                            </label>

                            {/* Booking Access Status Label */}
                            <span style={{
                              fontSize: '11px',
                              fontWeight: 800,
                              letterSpacing: '0.4px',
                              color: isAccessEnabled ? '#10b981' : '#ef4444'
                            }}>
                              {isAccessEnabled ? 'ENABLED' : 'DISABLED'}
                            </span>
                          </div>

                          {/* Pilot Operational Availability & Duty Action */}
                          <div style={{ display: 'flex', alignItems: 'center', gap: '6px', flexWrap: 'wrap' }}>
                            <span style={{
                              fontSize: '10px',
                              fontWeight: 700,
                              padding: '2px 7px',
                              borderRadius: '4px',
                              background: (isDutyOn && isAccessEnabled) ? 'rgba(16, 185, 129, 0.15)' : 'rgba(100, 116, 139, 0.15)',
                              color: (isDutyOn && isAccessEnabled) ? '#34d399' : '#94a3b8',
                              border: `1px solid ${(isDutyOn && isAccessEnabled) ? 'rgba(16, 185, 129, 0.3)' : 'rgba(100, 116, 139, 0.3)'}`
                            }}>
                              {(isDutyOn && isAccessEnabled) ? 'AVAILABLE' : 'UNAVAILABLE'}
                            </span>

                            {isAccessEnabled && (
                              <button
                                type="button"
                                disabled={isSubmitting}
                                onClick={() => handleToggleDuty(p, isDutyOn ? 'DUTY_OFF' : 'DUTY_ON')}
                                style={{
                                  background: 'transparent',
                                  border: `1px solid ${isDutyOn ? '#f87171' : '#34d399'}`,
                                  color: isDutyOn ? '#f87171' : '#34d399',
                                  fontSize: '9px',
                                  fontWeight: 700,
                                  borderRadius: '4px',
                                  padding: '1px 5px',
                                  cursor: 'pointer'
                                }}
                                title={isDutyOn ? "Switch pilot duty to OFF" : "Switch pilot duty to ON"}
                              >
                                {isDutyOn ? 'Duty OFF' : 'Duty ON'}
                              </button>
                            )}

                            {/* Separate Daily ₹20 Plan Status Badge */}
                            <span style={{
                              fontSize: '9px',
                              fontWeight: 700,
                              padding: '1.5px 6px',
                              borderRadius: '4px',
                              background: dailyPlanStatus === 'PAID'
                                ? 'rgba(16, 185, 129, 0.12)'
                                : (dailyPlanStatus === 'EXPIRED' ? 'rgba(245, 158, 11, 0.12)' : 'rgba(148, 163, 184, 0.12)'),
                              color: dailyPlanStatus === 'PAID'
                                ? '#10b981'
                                : (dailyPlanStatus === 'EXPIRED' ? '#f59e0b' : '#94a3b8'),
                              border: `1px solid ${dailyPlanStatus === 'PAID' ? 'rgba(16, 185, 129, 0.3)' : (dailyPlanStatus === 'EXPIRED' ? 'rgba(245, 158, 11, 0.3)' : 'rgba(148, 163, 184, 0.25)')}`
                            }}>
                              ₹20 Plan: {dailyPlanStatus}
                            </span>
                          </div>

                          {!isAccessEnabled && accessReason && (
                            <div style={{ fontSize: '9.5px', color: '#f87171', maxWidth: '200px', lineHeight: 1.2 }} title={accessReason}>
                              Reason: {accessReason}
                            </div>
                          )}
                        </div>
                      </td>

                      {/* 5. Service Preferences */}
                      <td>
                        <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
                          <button
                            type="button"
                            disabled={isSubmitting}
                            onClick={() => handleToggleServicePreference(p, 'ride')}
                            style={{
                              display: 'inline-flex',
                              alignItems: 'center',
                              justifyContent: 'space-between',
                              gap: '6px',
                              padding: '3px 8px',
                              borderRadius: '5px',
                              fontSize: '11px',
                              fontWeight: 700,
                              cursor: 'pointer',
                              background: (p as any).rideServiceEnabled !== false ? '#eff6ff' : '#f8fafc',
                              color: (p as any).rideServiceEnabled !== false ? '#1d4ed8' : '#94a3b8',
                              border: `1px solid ${(p as any).rideServiceEnabled !== false ? '#93c5fd' : '#cbd5e1'}`
                            }}
                            title="Click to Toggle Ride Booking"
                          >
                            <span>🚕 Rides</span>
                            <span style={{
                              fontSize: '9px',
                              padding: '1px 5px',
                              borderRadius: '3px',
                              background: (p as any).rideServiceEnabled !== false ? '#2563eb' : '#64748b',
                              color: 'white'
                            }}>
                              {(p as any).rideServiceEnabled !== false ? 'ON' : 'OFF'}
                            </span>
                          </button>
                          <button
                            type="button"
                            disabled={isSubmitting}
                            onClick={() => handleToggleServicePreference(p, 'food')}
                            style={{
                              display: 'inline-flex',
                              alignItems: 'center',
                              justifyContent: 'space-between',
                              gap: '6px',
                              padding: '3px 8px',
                              borderRadius: '5px',
                              fontSize: '11px',
                              fontWeight: 700,
                              cursor: 'pointer',
                              background: (p as any).foodServiceEnabled !== false ? '#ecfdf5' : '#f8fafc',
                              color: (p as any).foodServiceEnabled !== false ? '#047857' : '#94a3b8',
                              border: `1px solid ${(p as any).foodServiceEnabled !== false ? '#6ee7b7' : '#cbd5e1'}`
                            }}
                            title="Click to Toggle Food Delivery"
                          >
                            <span>🍔 Food</span>
                            <span style={{
                              fontSize: '9px',
                              padding: '1px 5px',
                              borderRadius: '3px',
                              background: (p as any).foodServiceEnabled !== false ? '#059669' : '#64748b',
                              color: 'white'
                            }}>
                              {(p as any).foodServiceEnabled !== false ? 'ON' : 'OFF'}
                            </span>
                          </button>
                        </div>
                      </td>

                      {/* 6. Wallet Balance (Matching Screenshot 2 cyan bold text) */}
                      <td>
                        <div style={{ fontSize: '13px', fontWeight: 800, color: '#38bdf8', fontFamily: 'monospace' }}>
                          ₹{(p.walletBalance || 0).toFixed(2)}
                        </div>
                      </td>

                      {/* 7. Total Earnings (Matching Screenshot 2) */}
                      <td>
                        <div style={{ fontSize: '12px', fontWeight: 700, color: 'var(--text-main)', fontFamily: 'monospace' }}>
                          ₹{((p as any).totalLifetimeEarnings || 0).toFixed(2)}
                        </div>
                      </td>

                      {/* 8. KYC Verification (Matching Screenshot 2) */}
                      <td>
                        {p.approved || (p as any).isApproved ? (
                          <span style={{ fontSize: '11px', fontWeight: 800, color: '#10b981', letterSpacing: '0.4px' }}>
                            VERIFIED
                          </span>
                        ) : (
                          <span style={{ fontSize: '11px', fontWeight: 800, color: '#f59e0b', letterSpacing: '0.4px' }}>
                            PENDING KYC
                          </span>
                        )}
                      </td>

                      {/* 9. Disciplinary Status (Matching Screenshot 2) */}
                      <td>
                        {p.isBlocked ? (
                          <span style={{ fontSize: '11px', fontWeight: 800, color: '#ef4444', letterSpacing: '0.4px' }}>
                            BLOCKED
                          </span>
                        ) : (
                          <span style={{ fontSize: '11px', fontWeight: 800, color: '#10b981', letterSpacing: '0.4px' }}>
                            IN GOOD STANDING
                          </span>
                        )}
                      </td>

                      {/* 10. Actions (Block/Unblock Button matching Screenshot 2) */}
                      <td>
                        <button 
                          className="btn btn-sm"
                          onClick={() => handleToggleBlock(p)}
                          style={{
                            fontSize: '11px',
                            fontWeight: 700,
                            padding: '4px 10px',
                            borderRadius: '5px',
                            background: p.isBlocked ? '#10b981' : '#ef4444',
                            color: '#ffffff',
                            border: 'none',
                            cursor: 'pointer'
                          }}
                        >
                          {p.isBlocked ? 'Unblock' : 'Block'}
                        </button>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Disable Booking Access Modal */}
      {disableModalPilot && (
        <div style={{
          position: 'fixed',
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          backgroundColor: 'rgba(0, 0, 0, 0.7)',
          backdropFilter: 'blur(3px)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 99999,
          padding: '16px'
        }}>
          <div style={{
            background: 'var(--bg-card, #1e293b)',
            color: 'var(--text-main, #f8fafc)',
            borderRadius: '16px',
            maxWidth: '460px',
            width: '100%',
            padding: '24px',
            boxShadow: '0 20px 40px rgba(0,0,0,0.5)',
            border: '1px solid var(--border-color, rgba(255,255,255,0.1))'
          }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <div style={{
                  width: '32px',
                  height: '32px',
                  borderRadius: '50%',
                  background: 'rgba(239, 68, 68, 0.15)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  color: '#ef4444'
                }}>
                  <Lock size={18} />
                </div>
                <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 700 }}>Disable Booking Access</h3>
              </div>
              <button 
                onClick={() => setDisableModalPilot(null)}
                style={{ background: 'transparent', border: 'none', color: 'var(--text-muted)', cursor: 'pointer' }}
              >
                <X size={20} />
              </button>
            </div>

            <p style={{ fontSize: '13px', color: 'var(--text-muted)', marginBottom: '16px', lineHeight: 1.5 }}>
              Disabling booking access for <strong>{disableModalPilot.name}</strong> ({disableModalPilot.uid}) will immediately switch their duty OFF and prevent all new ride and food delivery dispatch assignments.
            </p>

            <div style={{ marginBottom: '20px' }}>
              <label style={{ display: 'block', fontSize: '12px', fontWeight: 600, marginBottom: '6px' }}>
                Mandatory Reason for Disabling <span style={{ color: '#ef4444' }}>*</span>
              </label>
              <textarea
                rows={3}
                placeholder="e.g. Document renewal required, terms violation, operational review..."
                value={disableReason}
                onChange={e => setDisableReason(e.target.value)}
                className="input"
                style={{ width: '100%', resize: 'none', fontSize: '13px' }}
                autoFocus
              />
            </div>

            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px' }}>
              <button
                className="btn btn-secondary"
                disabled={isSubmitting}
                onClick={() => setDisableModalPilot(null)}
                style={{ fontSize: '13px' }}
              >
                Cancel
              </button>
              <button
                className="btn"
                disabled={isSubmitting || !disableReason.trim()}
                onClick={handleConfirmDisable}
                style={{
                  background: '#dc2626',
                  color: '#fff',
                  fontWeight: 700,
                  fontSize: '13px',
                  padding: '8px 16px',
                  opacity: (!disableReason.trim() || isSubmitting) ? 0.6 : 1
                }}
              >
                {isSubmitting ? 'Disabling...' : 'Confirm Disable Access'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default PilotManagement;
