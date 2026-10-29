import React, { useState } from 'react';
import { useDatabase } from '../context/DatabaseContext';
import { 
  Wallet, Search, RefreshCw, Download, ArrowUpRight, Clock, 
  CheckCircle2, XCircle, AlertCircle, ShieldAlert, Bike, Car, Truck 
} from 'lucide-react';

export const PilotWallets: React.FC = () => {
  const { pilotWallets, refreshFinancials, exportReport, lastUpdatedTime } = useDatabase();
  const [searchTerm, setSearchTerm] = useState('');
  const [vehicleFilter, setVehicleFilter] = useState('all');
  const [isRefreshing, setIsRefreshing] = useState(false);

  const handleRefresh = async () => {
    setIsRefreshing(true);
    try {
      await refreshFinancials();
    } finally {
      setIsRefreshing(false);
    }
  };

  // Filtering
  const filteredPilots = (pilotWallets || []).filter(p => {
    const matchesSearch = 
      (p.name || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (p.phone || '').includes(searchTerm) ||
      (p.pilotId || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
      (p.vehiclePlate || '').toLowerCase().includes(searchTerm.toLowerCase());

    const matchesVehicle = vehicleFilter === 'all' || 
      (vehicleFilter === 'bike' && (p.vehicleType || '').toLowerCase().includes('bike')) ||
      (vehicleFilter === 'auto' && (p.vehicleType || '').toLowerCase().includes('auto')) ||
      (vehicleFilter === 'car' && (p.vehicleType || '').toLowerCase().includes('car')) ||
      (vehicleFilter === 'mini_truck' && ((p.vehicleType || '').toLowerCase().includes('mini truck') || (p.vehicleType || '').toLowerCase().includes('pickup') || (p.vehicleType || '').toLowerCase().includes('ace') || (p.vehicleType || '').toLowerCase().includes('dost'))) ||
      (vehicleFilter === 'heavy_truck' && ((p.vehicleType || '').toLowerCase().includes('heavy truck') || (p.vehicleType || '').toLowerCase().includes('ton'))) ||
      (vehicleFilter === 'truck' && (p.vehicleType || '').toLowerCase().includes('truck')) ||
      (p.vehicleType || '').toLowerCase() === vehicleFilter.toLowerCase();
    return matchesSearch && matchesVehicle;
  });

  // Aggregates across all pilots
  const totalFleetBalance = (pilotWallets || []).reduce((sum, p) => sum + (p.availableBalance || 0), 0);
  const totalFleetWithdrawable = (pilotWallets || []).reduce((sum, p) => sum + (p.withdrawableBalance || 0), 0);
  const totalFleetPendingWithdrawals = (pilotWallets || []).reduce((sum, p) => sum + (p.totalPendingWithdrawal || 0), 0);
  const totalFleetEarnings = (pilotWallets || []).reduce((sum, p) => sum + (p.totalEarnings || 0), 0);
  const totalCommissionDeducted = (pilotWallets || []).reduce((sum, p) => sum + (p.commissionDeducted || 0), 0);

  const getVehicleIcon = (type: string) => {
    const t = (type || '').toLowerCase();
    if (t.includes('heavy')) return <Truck size={14} style={{ color: '#ea580c' }} />;
    if (t.includes('mini') || t.includes('truck')) return <Truck size={14} style={{ color: '#0284c7' }} />;
    if (t.includes('car')) return <Car size={14} style={{ color: '#2563eb' }} />;
    return <Bike size={14} style={{ color: '#16a34a' }} />;
  };

  return (
    <div className="page-container">
      {/* Top Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '16px' }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <h2>Pilot Wallet & Earnings Management</h2>
            <span style={{ 
              display: 'inline-flex', 
              alignItems: 'center', 
              gap: '6px', 
              padding: '4px 10px', 
              borderRadius: '20px', 
              fontSize: '11px', 
              fontWeight: 700, 
              background: 'rgba(16, 185, 129, 0.15)', 
              color: 'var(--success)' 
            }}>
              <CheckCircle2 size={12} />
              REAL-TIME LEDGER ACTIVE
            </span>
          </div>
          <p style={{ color: 'var(--text-muted)', fontSize: '13px', marginTop: '4px' }}>
            Genuine double-entry balance accounts, ride & goods earnings, commission deductions, and withdrawal limits.
          </p>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          <button 
            className="btn btn-secondary btn-sm" 
            onClick={() => exportReport('wallets')}
            style={{ display: 'flex', alignItems: 'center', gap: '6px' }}
          >
            <Download size={14} />
            <span>Export CSV</span>
          </button>
          <button 
            className="btn btn-secondary btn-sm" 
            onClick={handleRefresh}
            disabled={isRefreshing}
            style={{ display: 'flex', alignItems: 'center', gap: '6px' }}
          >
            <RefreshCw size={14} className={isRefreshing ? 'animate-spin' : ''} />
            <span>{isRefreshing ? 'Syncing...' : 'Sync Ledgers'}</span>
          </button>
          <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Updated: {lastUpdatedTime}</span>
        </div>
      </div>

      {/* Fleet Wallet KPI Summary */}
      <div className="kpi-grid" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(210px, 1fr))' }}>
        <div className="kpi-card" style={{ borderLeft: '3px solid var(--primary)' }}>
          <div className="kpi-info">
            <span className="kpi-label">Total Fleet Wallet Liabilities</span>
            <span className="kpi-value" style={{ color: 'var(--primary)' }}>₹{totalFleetBalance.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
            <span className="kpi-trend text-muted">{pilotWallets?.length || 0} registered pilots</span>
          </div>
          <div className="kpi-icon-wrapper" style={{ color: 'var(--primary)', backgroundColor: 'rgba(59,130,246,0.1)' }}>
            <Wallet size={20} />
          </div>
        </div>

        <div className="kpi-card" style={{ borderLeft: '3px solid var(--success)' }}>
          <div className="kpi-info">
            <span className="kpi-label">Free Withdrawable Balances</span>
            <span className="kpi-value" style={{ color: 'var(--success)' }}>₹{totalFleetWithdrawable.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
            <span className="kpi-trend trend-up">Available for payout requests</span>
          </div>
          <div className="kpi-icon-wrapper" style={{ color: 'var(--success)', backgroundColor: 'var(--success-bg)' }}>
            <ArrowUpRight size={20} />
          </div>
        </div>

        <div className="kpi-card" style={{ borderLeft: '3px solid var(--warning)' }}>
          <div className="kpi-info">
            <span className="kpi-label">Reserved Pending Payouts</span>
            <span className="kpi-value" style={{ color: 'var(--warning)' }}>₹{totalFleetPendingWithdrawals.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
            <span className="kpi-trend text-muted">Reserved in payout escrow</span>
          </div>
          <div className="kpi-icon-wrapper" style={{ color: 'var(--warning)', backgroundColor: 'var(--warning-bg)' }}>
            <Clock size={20} />
          </div>
        </div>

        <div className="kpi-card" style={{ borderLeft: '3px solid #a855f7' }}>
          <div className="kpi-info">
            <span className="kpi-label">Total Platform Commissions</span>
            <span className="kpi-value" style={{ color: '#a855f7' }}>₹{totalCommissionDeducted.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
            <span className="kpi-trend text-muted">Retained platform share</span>
          </div>
          <div className="kpi-icon-wrapper" style={{ color: '#a855f7', backgroundColor: 'rgba(168,85,247,0.1)' }}>
            <CheckCircle2 size={20} />
          </div>
        </div>
      </div>

      {/* Filter Toolbar */}
      <div className="card" style={{ padding: '16px' }}>
        <div style={{ display: 'flex', gap: '12px', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'space-between' }}>
          <div style={{ display: 'flex', gap: '12px', flex: '1', minWidth: '280px' }}>
            <div style={{ position: 'relative', flex: 1 }}>
              <Search size={16} style={{ position: 'absolute', left: '12px', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
              <input 
                type="text"
                placeholder="Search pilot ID, name, mobile, vehicle plate..."
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
              style={{ width: '160px' }}
            >
              <option value="all">All Vehicles</option>
              <option value="bike">Bike Taxi</option>
              <option value="auto">Auto Rickshaw</option>
              <option value="car">Cab / Taxi</option>
              <option value="mini_truck">Mini Truck</option>
              <option value="heavy_truck">Heavy Truck</option>
              <option value="truck">All Trucks</option>
            </select>
          </div>

          <span style={{ fontSize: '13px', color: 'var(--text-muted)' }}>
            Showing <strong>{filteredPilots.length}</strong> of <strong>{pilotWallets?.length || 0}</strong> pilot accounts
          </span>
        </div>
      </div>

      {/* Detailed Pilot Wallets Table */}
      <div className="card" style={{ padding: '0', overflow: 'hidden' }}>
        <div style={{ padding: '16px 20px', borderBottom: '1px solid var(--border)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <h3 style={{ fontSize: '15px' }}>Pilot Partner Wallet Ledger Accounts</h3>
          <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Strict immutable balances synced with database ledger</span>
        </div>

        <div className="table-responsive">
          <table className="data-table">
            <thead>
              <tr>
                <th>Pilot Details</th>
                <th>Vehicle</th>
                <th>Rides Earnings</th>
                <th>Goods Earnings</th>
                <th>Commissions Deducted</th>
                <th>Current Available</th>
                <th>Withdrawable</th>
                <th>Total Withdrawn</th>
                <th>Pending Payout</th>
                <th>Linked Bank / UPI</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {filteredPilots.length === 0 ? (
                <tr>
                  <td colSpan={11} style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>
                    No pilot partner records match your criteria.
                  </td>
                </tr>
              ) : (
                filteredPilots.map((p, idx) => (
                  <tr key={p.pilotId || idx}>
                    <td>
                      <div style={{ display: 'flex', flexDirection: 'column' }}>
                        <span style={{ fontWeight: 600, color: 'var(--text-main)' }}>{p.name || 'Pilot Partner'}</span>
                        <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>ID: {p.pilotId}</span>
                        <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>📞 {p.phone || 'N/A'}</span>
                      </div>
                    </td>
                    <td>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                        {getVehicleIcon(p.vehicleType)}
                        <div style={{ display: 'flex', flexDirection: 'column' }}>
                          <span style={{ fontSize: '12px', fontWeight: 600 }}>{p.vehicleType || 'Bike'}</span>
                          <span style={{ fontSize: '10px', color: 'var(--text-muted)' }}>{p.vehiclePlate || 'TS--'}</span>
                        </div>
                      </div>
                    </td>
                    <td>
                      <span style={{ fontWeight: 600, color: 'var(--text-main)' }}>₹{(p.ridesEarnings || 0).toFixed(2)}</span>
                    </td>
                    <td>
                      <span style={{ fontWeight: 600, color: 'var(--text-main)' }}>₹{(p.deliveryEarnings || 0).toFixed(2)}</span>
                    </td>
                    <td>
                      <span style={{ color: '#ef4444', fontWeight: 600 }}>-₹{(p.commissionDeducted || 0).toFixed(2)}</span>
                    </td>
                    <td>
                      <span style={{ 
                        fontWeight: 700, 
                        color: (p.availableBalance || 0) > 0 ? 'var(--primary)' : 'var(--text-muted)',
                        fontSize: '13px'
                      }}>
                        ₹{(p.availableBalance || 0).toFixed(2)}
                      </span>
                    </td>
                    <td>
                      <span style={{ 
                        fontWeight: 700, 
                        color: (p.withdrawableBalance || 0) > 0 ? 'var(--success)' : 'var(--text-muted)',
                        fontSize: '13px'
                      }}>
                        ₹{(p.withdrawableBalance || 0).toFixed(2)}
                      </span>
                    </td>
                    <td>
                      <span style={{ color: 'var(--text-muted)', fontSize: '12px' }}>₹{(p.totalWithdrawn || 0).toFixed(2)}</span>
                    </td>
                    <td>
                      {(p.totalPendingWithdrawal || 0) > 0 ? (
                        <span style={{ 
                          display: 'inline-flex', 
                          alignItems: 'center', 
                          gap: '4px',
                          color: 'var(--warning)', 
                          fontWeight: 600,
                          fontSize: '12px' 
                        }}>
                          <Clock size={12} />
                          ₹{p.totalPendingWithdrawal.toFixed(2)}
                        </span>
                      ) : (
                        <span style={{ color: 'var(--text-muted)', fontSize: '12px' }}>₹0.00</span>
                      )}
                    </td>
                    <td>
                      <span style={{ 
                        fontSize: '11px', 
                        fontFamily: 'monospace', 
                        padding: '2px 6px', 
                        borderRadius: '4px', 
                        background: 'rgba(255,255,255,0.04)',
                        border: '1px solid var(--border)'
                      }}>
                        {p.maskedDestination || '••••'}
                      </span>
                    </td>
                    <td>
                      {p.isBlocked ? (
                        <span className="badge badge-error">BLOCKED</span>
                      ) : p.isApproved ? (
                        <span className="badge badge-success">ACTIVE</span>
                      ) : (
                        <span className="badge badge-warning">PENDING KYC</span>
                      )}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};

export default PilotWallets;
