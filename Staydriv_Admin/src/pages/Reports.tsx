import React, { useState } from 'react';
import { useDatabase } from '../context/DatabaseContext';
import { FileText, Download, Calendar, ArrowRight, Printer } from 'lucide-react';

export const Reports: React.FC = () => {
  const { bookings, deliveries, partners, customers, payments } = useDatabase();
  const [reportType, setReportType] = useState<string>('daily');
  const [startDate, setStartDate] = useState<string>('2026-05-01');
  const [endDate, setEndDate] = useState<string>('2026-05-31');

  // Filtered Booking/Delivery lists based on date range
  const filterByDateRange = (items: any[]) => {
    return items.filter(item => {
      const itemDateStr = item.createdAt.split('T')[0];
      return itemDateStr >= startDate && itemDateStr <= endDate;
    });
  };

  const getReportTitle = () => {
    switch (reportType) {
      case 'daily': return 'Daily Operations Report';
      case 'weekly': return 'Weekly Summary Report';
      case 'monthly': return 'Monthly Performance Report';
      case 'revenue': return 'Revenue & Commissions Audit';
      case 'driver': return 'Pilot Standings & Performance';
      case 'delivery': return 'Goods Delivery & Logistics Audit';
      case 'growth': return 'Customer Account Growth Metrics';
      default: return 'Custom Reports';
    }
  };

  // Compile calculations
  const parsedBookings = filterByDateRange(bookings);
  const parsedDeliveries = filterByDateRange(deliveries);
  
  const parsePrice = (priceStr: string): number => {
    return parseFloat(priceStr.replace(/[^0-9.]/g, '')) || 0;
  };

  const rideFares = parsedBookings.filter(b => b.status === 'completed').reduce((s, b) => s + parsePrice(b.price), 0);
  const deliveryFares = parsedDeliveries.filter(d => d.status === 'completed').reduce((s, d) => s + parsePrice(d.price), 0);
  const totalRevenue = rideFares + deliveryFares;
  const platformCommissions = totalRevenue * 0.20;

  // Handle CSV Export
  const handleCSVExport = () => {
    let headers: string[] = [];
    let rows: any[][] = [];
    let fileName = `StayDriv_${reportType}_Report`;

    if (reportType === 'driver') {
      headers = ['Driver UID', 'Name', 'Vehicle Type', 'License Plate', 'Rating', 'Total Trips', 'Total Earnings'];
      rows = partners.map(p => [p.uid, p.name, p.vehicleType, p.vehiclePlate, p.rating, p.totalTrips, `₹${p.earnings}`]);
    } else if (reportType === 'delivery') {
      headers = ['Booking ID', 'Customer', 'Goods Type', 'Weight', 'Pickup', 'Drop', 'Fare', 'Status'];
      rows = parsedDeliveries.map(d => [d.bookingId, d.customerName, d.goodsType, d.weight, d.pickup, d.drop, d.price, d.status]);
    } else if (reportType === 'growth') {
      headers = ['Customer ID', 'Name', 'Email', 'Phone', 'Created At'];
      rows = customers.map(c => [c.uid, c.name, c.email, c.phone, c.createdAt]);
    } else {
      // Operations reports
      headers = ['Booking ID', 'Type', 'Customer', 'Driver', 'Fare', 'Status', 'Date'];
      rows = [
        ...parsedBookings.map(b => [b.bookingId, 'Ride', b.customerName, b.driverName || 'N/A', b.price, b.status, b.createdAt]),
        ...parsedDeliveries.map(d => [d.bookingId, 'Delivery', d.customerName, d.driverName || 'N/A', d.price, d.status, d.createdAt])
      ];
    }

    const csvContent = [headers.join(','), ...rows.map(r => r.join(','))].join('\n');
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.setAttribute('href', url);
    link.setAttribute('download', `${fileName}_${startDate}_to_${endDate}.csv`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  const handlePrintPDF = () => {
    window.print();
  };

  return (
    <div className="page-container">
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div>
          <h2>Platform Reports & Auditing</h2>
          <p style={{ color: 'var(--text-muted)', fontSize: '14px' }}>Query historical metrics, audit pilots earnings, and export spreadsheets.</p>
        </div>
        <div style={{ display: 'flex', gap: '8px' }}>
          <button className="btn btn-secondary" onClick={handlePrintPDF}>
            <Printer size={16} />
            <span>Print PDF</span>
          </button>
          <button className="btn btn-primary" onClick={handleCSVExport}>
            <Download size={16} />
            <span>Export CSV</span>
          </button>
        </div>
      </div>

      {/* Query Filters */}
      <div className="card" style={{ padding: '20px' }}>
        <div style={{ display: 'flex', gap: '16px', flexWrap: 'wrap', alignItems: 'flex-end' }}>
          <div className="form-group" style={{ minWidth: '240px' }}>
            <label>Select Report Template</label>
            <select value={reportType} onChange={(e) => setReportType(e.target.value)}>
              <option value="daily">Daily Operations Summary</option>
              <option value="weekly">Weekly Fleet Report</option>
              <option value="monthly">Monthly Operations Audit</option>
              <option value="revenue">Revenue & Platform Commissions</option>
              <option value="driver">Pilot Performance</option>
              <option value="delivery">Logistics & Goods Deliveries</option>
              <option value="growth">Customer Growth Ledger</option>
            </select>
          </div>

          <div className="form-group">
            <label>Start Date</label>
            <div className="input-icon-wrapper">
              <Calendar size={14} />
              <input type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} style={{ paddingLeft: '32px' }} />
            </div>
          </div>

          <div style={{ paddingBottom: '12px', color: 'var(--text-muted)' }}>
            <ArrowRight size={16} />
          </div>

          <div className="form-group">
            <label>End Date</label>
            <div className="input-icon-wrapper">
              <Calendar size={14} />
              <input type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} style={{ paddingLeft: '32px' }} />
            </div>
          </div>
        </div>
      </div>

      {/* Report Preview Canvas */}
      <div id="printable-report-section" className="card" style={{ padding: '30px' }}>
        <div style={{ borderBottom: '2px solid var(--primary)', paddingBottom: '16px', display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
          <div>
            <h3 style={{ fontSize: '20px', color: 'var(--text-main)' }}>{getReportTitle()}</h3>
            <span style={{ fontSize: '13px', color: 'var(--text-muted)' }}>
              Date Range Bounds: <strong>{new Date(startDate).toLocaleDateString()}</strong> to <strong>{new Date(endDate).toLocaleDateString()}</strong>
            </span>
          </div>
          <div style={{ textAlign: 'right', fontSize: '11px', color: 'var(--text-muted)' }}>
            <div>StayDriv Unified Mobility Platform</div>
            <div>Generated: {new Date().toLocaleString()}</div>
          </div>
        </div>

        {/* Dynamic preview sections */}
        {reportType === 'driver' ? (
          <div style={{ marginTop: '24px' }}>
            <h4 style={{ fontSize: '14px', marginBottom: '12px' }}>Active Pilot Roster Summary</h4>
            <div className="table-wrapper">
              <table>
                <thead>
                  <tr>
                    <th>Pilot UID</th>
                    <th>Name</th>
                    <th>Vehicle</th>
                    <th>License Plate</th>
                    <th>Avg Rating</th>
                    <th>Executed Trips</th>
                    <th>Gross Earnings</th>
                  </tr>
                </thead>
                <tbody>
                  {partners.map(p => (
                    <tr key={p.uid}>
                      <td style={{ fontFamily: 'monospace', fontWeight: 600 }}>{p.uid}</td>
                      <td>{p.name}</td>
                      <td>{p.vehicleType}</td>
                      <td style={{ fontFamily: 'monospace' }}>{p.vehiclePlate}</td>
                      <td>{p.rating > 0 ? p.rating.toFixed(1) : 'New'}</td>
                      <td>{p.totalTrips}</td>
                      <td style={{ fontWeight: 600 }}>₹{p.earnings.toFixed(2)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        ) : reportType === 'delivery' ? (
          <div style={{ marginTop: '24px' }}>
            <h4 style={{ fontSize: '14px', marginBottom: '12px' }}>Cargo Delivery Orders summary</h4>
            <div className="table-wrapper">
              <table>
                <thead>
                  <tr>
                    <th>ID</th>
                    <th>Goods Type</th>
                    <th>Load weight</th>
                    <th>Pickup &rarr; Drop</th>
                    <th>Price</th>
                    <th>Status</th>
                  </tr>
                </thead>
                <tbody>
                  {parsedDeliveries.map(d => (
                    <tr key={d.bookingId}>
                      <td style={{ fontWeight: 600 }}>{d.bookingId}</td>
                      <td>{d.goodsType}</td>
                      <td>{d.weight}</td>
                      <td style={{ fontSize: '12px' }}>{d.pickup} &rarr; {d.drop}</td>
                      <td>{d.price}</td>
                      <td><span className="badge badge-completed">{d.status}</span></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        ) : reportType === 'growth' ? (
          <div style={{ marginTop: '24px' }}>
            <h4 style={{ fontSize: '14px', marginBottom: '12px' }}>Registered Customers Accounts</h4>
            <div className="table-wrapper">
              <table>
                <thead>
                  <tr>
                    <th>UID</th>
                    <th>Client Name</th>
                    <th>Email</th>
                    <th>Phone</th>
                    <th>Wallet Balance</th>
                    <th>Status</th>
                  </tr>
                </thead>
                <tbody>
                  {customers.map(c => (
                    <tr key={c.uid}>
                      <td style={{ fontFamily: 'monospace' }}>{c.uid}</td>
                      <td>{c.name}</td>
                      <td>{c.email}</td>
                      <td>+91 {c.phone}</td>
                      <td style={{ fontWeight: 600 }}>₹{c.walletBalance.toFixed(2)}</td>
                      <td><span className="badge badge-active">{c.status}</span></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        ) : (
          /* Operations / Financial reports */
          <div style={{ marginTop: '24px', display: 'flex', flexDirection: 'column', gap: '20px' }}>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '16px' }}>
              <div style={{ backgroundColor: 'var(--bg-input)', padding: '16px', borderRadius: '12px' }}>
                <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Aggregated Bookings</span>
                <div style={{ fontSize: '24px', fontWeight: 800, marginTop: '4px' }}>
                  {parsedBookings.length + parsedDeliveries.length}
                </div>
                <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '4px' }}>
                  {parsedBookings.length} rides • {parsedDeliveries.length} cargo deliveries
                </div>
              </div>

              <div style={{ backgroundColor: 'var(--bg-input)', padding: '16px', borderRadius: '12px' }}>
                <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Completed Fares Volume</span>
                <div style={{ fontSize: '24px', fontWeight: 800, marginTop: '4px', color: 'var(--primary)' }}>
                  ₹{totalRevenue.toLocaleString('en-IN', { maximumFractionDigits: 0 })}
                </div>
                <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '4px' }}>
                  ₹{rideFares.toLocaleString()} rides • ₹{deliveryFares.toLocaleString()} deliveries
                </div>
              </div>

              <div style={{ backgroundColor: 'var(--bg-input)', padding: '16px', borderRadius: '12px' }}>
                <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Commission Earnings (20%)</span>
                <div style={{ fontSize: '24px', fontWeight: 800, marginTop: '4px', color: 'var(--success)' }}>
                  ₹{platformCommissions.toLocaleString('en-IN', { maximumFractionDigits: 0 })}
                </div>
                <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '4px' }}>
                  Platform net commissions cut
                </div>
              </div>
            </div>

            <div>
              <h4 style={{ fontSize: '14px', marginBottom: '8px' }}>Detailed Operations Queue</h4>
              <div className="table-wrapper">
                <table>
                  <thead>
                    <tr>
                      <th>Booking ID</th>
                      <th>Type</th>
                      <th>Client Name</th>
                      <th>Assigned Driver</th>
                      <th>Fare</th>
                      <th>Status</th>
                    </tr>
                  </thead>
                  <tbody>
                    {parsedBookings.map(b => (
                      <tr key={b.bookingId}>
                        <td style={{ fontWeight: 600 }}>{b.bookingId}</td>
                        <td><span className="badge badge-requested">Ride</span></td>
                        <td>{b.customerName}</td>
                        <td>{b.driverName || 'Unassigned'}</td>
                        <td style={{ fontWeight: 600 }}>{b.price}</td>
                        <td><span className="badge badge-completed">{b.status}</span></td>
                      </tr>
                    ))}
                    {parsedDeliveries.map(d => (
                      <tr key={d.bookingId}>
                        <td style={{ fontWeight: 600 }}>{d.bookingId}</td>
                        <td><span className="badge badge-completed">Delivery</span></td>
                        <td>{d.customerName}</td>
                        <td>{d.driverName || 'Unassigned'}</td>
                        <td style={{ fontWeight: 600 }}>{d.price}</td>
                        <td><span className="badge badge-completed">{d.status}</span></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
export default Reports;
