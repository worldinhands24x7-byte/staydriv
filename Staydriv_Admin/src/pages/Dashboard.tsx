import React, { useState } from 'react';
import { useDatabase } from '../context/DatabaseContext';
import { 
  Users, Compass, Car, Truck, IndianRupee, Clock, AlertTriangle, Activity 
} from 'lucide-react';
import { 
  AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
  BarChart, Bar, Legend, Cell, PieChart, Pie
} from 'recharts';

export const Dashboard: React.FC = () => {
  const { customers, partners, bookings, deliveries, payments } = useDatabase();
  const [filterRange, setFilterRange] = useState<'today' | 'week' | 'month'>('week');

  // ---------------- COMPUTING METRICS DYNAMICALLY ----------------
  const totalCustomers = customers.length;
  const totalPartners = partners.length;
  const pendingApprovals = partners.filter(p => p.status === 'pending').length;
  
  const activeRides = bookings.filter(b => b.status !== 'completed' && b.status !== 'cancelled').length;
  const activeDeliveries = deliveries.filter(d => d.status !== 'completed' && d.status !== 'cancelled').length;

  const completedRidesToday = bookings.filter(b => b.status === 'completed').length; // Mock simplified
  const completedDeliveriesToday = deliveries.filter(d => d.status === 'completed').length;

  // Active drivers online count: partners that have status approved (simulated as online in demo)
  const onlineDriversCount = partners.filter(p => p.status === 'approved').length; // In demo, approved means online

  // Calculate revenue
  const parsePrice = (priceStr: string): number => {
    return parseFloat(priceStr.replace(/[^0-9.]/g, '')) || 0;
  };

  const totalBookingRevenue = bookings
    .filter(b => b.status === 'completed')
    .reduce((sum, b) => sum + parsePrice(b.price), 0);

  const totalDeliveryRevenue = deliveries
    .filter(d => d.status === 'completed')
    .reduce((sum, d) => sum + parsePrice(d.price), 0);

  const totalRevenue = totalBookingRevenue + totalDeliveryRevenue;
  
  // Daily / Weekly / Monthly distributions
  const dailyRevenue = totalRevenue * 0.15; // Simulated distributions
  const weeklyRevenue = totalRevenue * 0.65;
  const monthlyRevenue = totalRevenue;

  // Cancellation calculations
  const totalRides = bookings.length;
  const cancelledRides = bookings.filter(b => b.status === 'cancelled').length;
  const cancellationRate = totalRides > 0 ? ((cancelledRides / totalRides) * 100).toFixed(1) : '0';

  // ---------------- CHART DATA CALCULATIONS ----------------
  
  // 1. Revenue Trends Data
  const revenueChartData = [
    { name: 'Mon', Revenue: weeklyRevenue * 0.12, Trips: 14 },
    { name: 'Tue', Revenue: weeklyRevenue * 0.15, Trips: 18 },
    { name: 'Wed', Revenue: weeklyRevenue * 0.11, Trips: 12 },
    { name: 'Thu', Revenue: weeklyRevenue * 0.14, Trips: 15 },
    { name: 'Fri', Revenue: weeklyRevenue * 0.18, Trips: 22 },
    { name: 'Sat', Revenue: weeklyRevenue * 0.20, Trips: 25 },
    { name: 'Sun', Revenue: weeklyRevenue * 0.10, Trips: 11 },
  ];

  // 2. Category Distribution
  const categoryCount = {
    Bike: bookings.filter(b => b.vehicle === 'Bike').length + deliveries.filter(d => d.vehicle === 'Bike').length,
    Auto: bookings.filter(b => b.vehicle === 'Auto').length + deliveries.filter(d => d.vehicle === 'Auto').length,
    Car: bookings.filter(b => b.vehicle === 'Car').length,
    Truck: deliveries.filter(d => d.vehicle === 'Mini Truck' || d.vehicle === 'Truck').length,
  };

  const pieData = [
    { name: 'Bike Taxi', value: categoryCount.Bike || 5, color: '#6366f1' },
    { name: 'Auto Auto', value: categoryCount.Auto || 3, color: '#fbbf24' },
    { name: 'Cab Rides', value: categoryCount.Car || 6, color: '#3b82f6' },
    { name: 'Cargo Trucks', value: categoryCount.Truck || 2, color: '#10b981' },
  ];

  return (
    <div className="page-container">
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div>
          <h2>Real-Time Overview</h2>
          <p style={{ color: 'var(--text-muted)', fontSize: '14px' }}>StayDriv unified mobility dashboard.</p>
        </div>
        <div style={{ display: 'flex', gap: '8px' }}>
          <button 
            className={`btn btn-sm ${filterRange === 'today' ? 'btn-primary' : 'btn-secondary'}`}
            onClick={() => setFilterRange('today')}
          >
            Today
          </button>
          <button 
            className={`btn btn-sm ${filterRange === 'week' ? 'btn-primary' : 'btn-secondary'}`}
            onClick={() => setFilterRange('week')}
          >
            Weekly
          </button>
          <button 
            className={`btn btn-sm ${filterRange === 'month' ? 'btn-primary' : 'btn-secondary'}`}
            onClick={() => setFilterRange('month')}
          >
            Monthly
          </button>
        </div>
      </div>

      {/* KPI Cards Grid */}
      <div className="kpi-grid">
        <div className="kpi-card">
          <div className="kpi-info">
            <span className="kpi-label">Total Customers</span>
            <span className="kpi-value">{totalCustomers}</span>
            <span className="kpi-trend trend-up">🟢 Active accounts</span>
          </div>
          <div className="kpi-icon-wrapper" style={{ color: 'var(--primary)' }}>
            <Users size={20} />
          </div>
        </div>

        <div className="kpi-card">
          <div className="kpi-info">
            <span className="kpi-label">Partners Registered</span>
            <span className="kpi-value">{totalPartners}</span>
            <span className="kpi-trend trend-up" style={{ color: pendingApprovals > 0 ? 'var(--warning)' : 'var(--success)' }}>
              {pendingApprovals > 0 ? `${pendingApprovals} Pending Approval` : 'All Verified'}
            </span>
          </div>
          <div className="kpi-icon-wrapper" style={{ color: 'var(--success)' }}>
            <Compass size={20} />
          </div>
        </div>

        <div className="kpi-card">
          <div className="kpi-info">
            <span className="kpi-label">Active Bookings</span>
            <span className="kpi-value">{activeRides + activeDeliveries}</span>
            <span className="kpi-trend text-muted" style={{ display: 'flex', gap: '8px' }}>
              <span>🚗 {activeRides} rides</span>
              <span>📦 {activeDeliveries} parcels</span>
            </span>
          </div>
          <div className="kpi-icon-wrapper" style={{ color: 'var(--info)' }}>
            <Car size={20} />
          </div>
        </div>

        <div className="kpi-card">
          <div className="kpi-info">
            <span className="kpi-label">Platform Revenue</span>
            <span className="kpi-value">
              ₹{(filterRange === 'today' ? dailyRevenue : filterRange === 'week' ? weeklyRevenue : monthlyRevenue).toLocaleString('en-IN', { maximumFractionDigits: 0 })}
            </span>
            <span className="kpi-trend trend-up">20% commission cut</span>
          </div>
          <div className="kpi-icon-wrapper" style={{ color: 'var(--safety-yellow)' }}>
            <IndianRupee size={20} />
          </div>
        </div>

        <div className="kpi-card">
          <div className="kpi-info">
            <span className="kpi-label">Completed Today</span>
            <span className="kpi-value">{completedRidesToday + completedDeliveriesToday}</span>
            <span className="kpi-trend text-muted" style={{ display: 'flex', gap: '8px' }}>
              <span>{completedRidesToday} rides</span>
              <span>{completedDeliveriesToday} deliveries</span>
            </span>
          </div>
          <div className="kpi-icon-wrapper" style={{ color: 'var(--success)' }}>
            <Activity size={20} />
          </div>
        </div>

        <div className="kpi-card">
          <div className="kpi-info">
            <span className="kpi-label">Cancellation Rate</span>
            <span className="kpi-value">{cancellationRate}%</span>
            <span className="kpi-trend trend-down" style={{ color: parseFloat(cancellationRate) > 10 ? 'var(--error)' : 'var(--success)' }}>
              {parseFloat(cancellationRate) > 10 ? '⚠️ High cancellation' : 'Stable'}
            </span>
          </div>
          <div className="kpi-icon-wrapper" style={{ color: 'var(--error)' }}>
            <Clock size={20} />
          </div>
        </div>
      </div>

      {/* Analytics Charts */}
      <div className="charts-grid">
        <div className="card" style={{ height: '360px' }}>
          <div className="card-title">
            <span>Weekly Operations Trend</span>
            <span style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: 500 }}>
              Revenue & Trip Counts
            </span>
          </div>
          <div style={{ flex: 1, width: '100%', height: '100%' }}>
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={revenueChartData} margin={{ top: 10, right: 10, left: -20, bottom: 0 }}>
                <defs>
                  <linearGradient id="colorRevenue" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="var(--primary)" stopOpacity={0.3}/>
                    <stop offset="95%" stopColor="var(--primary)" stopOpacity={0}/>
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" />
                <XAxis dataKey="name" stroke="var(--text-muted)" fontSize={12} />
                <YAxis stroke="var(--text-muted)" fontSize={12} />
                <Tooltip 
                  contentStyle={{ 
                    backgroundColor: 'var(--bg-card)', 
                    borderColor: 'var(--border)', 
                    color: 'var(--text-main)',
                    borderRadius: '8px'
                  }} 
                />
                <Area type="monotone" dataKey="Revenue" stroke="var(--primary)" strokeWidth={2} fillOpacity={1} fill="url(#colorRevenue)" />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </div>

        <div className="card" style={{ height: '360px', alignItems: 'center', justifyContent: 'center' }}>
          <div className="card-title" style={{ width: '100%', textAlign: 'left' }}>Category Split</div>
          <div style={{ flex: 1, width: '100%', height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', position: 'relative' }}>
            <ResponsiveContainer width="100%" height="90%">
              <PieChart>
                <Pie
                  data={pieData}
                  cx="50%"
                  cy="50%"
                  innerRadius={60}
                  outerRadius={80}
                  paddingAngle={5}
                  dataKey="value"
                >
                  {pieData.map((entry, index) => (
                    <Cell key={`cell-${index}`} fill={entry.color} />
                  ))}
                </Pie>
                <Tooltip 
                  contentStyle={{ 
                    backgroundColor: 'var(--bg-card)', 
                    borderColor: 'var(--border)', 
                    color: 'var(--text-main)',
                    borderRadius: '8px'
                  }}
                />
              </PieChart>
            </ResponsiveContainer>
            
            {/* Center label */}
            <div style={{ position: 'absolute', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
              <span style={{ fontSize: '20px', fontWeight: 800 }}>{bookings.length + deliveries.length}</span>
              <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Total Bookings</span>
            </div>
          </div>
          
          {/* Custom legend */}
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: '12px', justifyContent: 'center', width: '100%' }}>
            {pieData.map((item, idx) => (
              <div key={idx} style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '12px' }}>
                <div style={{ width: '10px', height: '10px', borderRadius: '50%', backgroundColor: item.color }} />
                <span style={{ color: 'var(--text-muted)' }}>{item.name} ({item.value})</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Bottom section showing quick alerts */}
      <div className="card">
        <div className="card-title" style={{ fontSize: '15px' }}>🚨 System Health Alerts</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
          {pendingApprovals > 0 && (
            <div style={{ display: 'flex', gap: '10px', backgroundColor: 'var(--warning-bg)', border: '1px solid var(--warning)', padding: '12px 16px', borderRadius: '8px', color: 'var(--warning)', alignItems: 'center', fontSize: '13px' }}>
              <AlertTriangle size={18} />
              <span>We have <strong>{pendingApprovals} partner registration request(s)</strong> awaiting profile document verification and credentials vetting.</span>
            </div>
          )}
          {activeRides > 0 && (
            <div style={{ display: 'flex', gap: '10px', backgroundColor: 'rgba(59,130,246,0.08)', border: '1px solid var(--primary)', padding: '12px 16px', borderRadius: '8px', color: 'var(--primary)', alignItems: 'center', fontSize: '13px' }}>
              <Activity size={18} />
              <span>StayDriv Fleet operates smoothly. <strong>{activeRides} active ride(s)</strong> are currently monitored on the live map.</span>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
export default Dashboard;
