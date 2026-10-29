import React, { useState, useMemo } from 'react';
import { useDatabase } from '../context/DatabaseContext';
import { 
  Search, UserCheck, ShieldAlert, Download, Eye, X, MapPin, 
  ExternalLink, Phone, Navigation, Clock, User, Check, Copy, AlertTriangle
} from 'lucide-react';

export const Customers: React.FC = () => {
  const { customers, blockCustomer, refreshAllData, lastUpdatedTime } = useDatabase();

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
      if (e.detail?.filter && (e.detail?.tab === 'customers' || !e.detail?.tab)) {
        setSearchTerm(e.detail.filter);
      }
    };
    window.addEventListener('admin:search-navigate', handleSearchNav);
    return () => window.removeEventListener('admin:search-navigate', handleSearchNav);
  }, []);
  const [statusFilter, setStatusFilter] = useState<'all' | 'in_ride' | 'searching' | 'idle' | 'blocked'>('all');
  const [locationFilter, setLocationFilter] = useState<'all' | 'has_location' | 'no_location'>('all');
  const [selectedCustomer, setSelectedCustomer] = useState<any | null>(null);
  const [copiedText, setCopiedText] = useState<string | null>(null);

  // Filtered List based on search and filters
  const filteredCustomers = useMemo(() => {
    return customers.filter(c => {
      const term = searchTerm.toLowerCase().trim();
      const matchesSearch = !term ||
        (c.name && c.name.toLowerCase().includes(term)) ||
        (c.phone && c.phone.includes(term)) ||
        (c.uid && c.uid.toLowerCase().includes(term)) ||
        (c.email && c.email.toLowerCase().includes(term)) ||
        (c.activeBookingId && c.activeBookingId.toLowerCase().includes(term)) ||
        (c.assignedPilotName && c.assignedPilotName.toLowerCase().includes(term));

      if (!matchesSearch) return false;

      // Status filter
      if (statusFilter === 'in_ride') {
        const inRideStatuses = ['accepted', 'arrived', 'started', 'heading_to_pickup', 'on_trip'];
        if (!c.bookingStatus || !inRideStatuses.includes(c.bookingStatus)) return false;
      } else if (statusFilter === 'searching') {
        if (c.bookingStatus !== 'searching') return false;
      } else if (statusFilter === 'idle') {
        if (c.bookingStatus && c.bookingStatus !== 'none') return false;
      } else if (statusFilter === 'blocked') {
        if (c.status !== 'blocked') return false;
      }

      // Location availability filter
      if (locationFilter === 'has_location') {
        if (!c.hasLocation && (!c.lat || !c.lng)) return false;
      } else if (locationFilter === 'no_location') {
        if (c.hasLocation || (c.lat && c.lng)) return false;
      }

      return true;
    });
  }, [customers, searchTerm, statusFilter, locationFilter]);

  // Handle Export to CSV
  const handleExportCSV = () => {
    const headers = ['Customer ID', 'Name', 'Phone', 'Email', 'Booking Status', 'Assigned Pilot', 'Pilot Phone', 'Vehicle', 'Latitude', 'Longitude', 'Status', 'Wallet Balance', 'Registration Date'];
    const rows = filteredCustomers.map(c => [
      c.uid,
      c.name,
      c.phone,
      c.email,
      c.bookingStatus || 'none',
      c.assignedPilotName || 'N/A',
      c.assignedPilotPhone || 'N/A',
      c.vehiclePlate || 'N/A',
      c.lat || '',
      c.lng || '',
      c.status,
      c.walletBalance || 0,
      c.createdAt
    ]);

    const csvContent = [headers.join(','), ...rows.map(r => r.join(','))].join('\n');
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.setAttribute('href', url);
    link.setAttribute('download', `StayDriv_Customers_${new Date().toISOString().split('T')[0]}.csv`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  const copyToClipboard = (text: string, label: string) => {
    navigator.clipboard.writeText(text);
    setCopiedText(label);
    setTimeout(() => setCopiedText(null), 2000);
  };

  const formatLastSeen = (timestampStr?: string) => {
    if (!timestampStr) return 'Unavailable';
    const ts = new Date(timestampStr).getTime();
    if (isNaN(ts) || ts <= 0) return 'Unavailable';
    const elapsedSec = Math.floor((Date.now() - ts) / 1000);
    if (elapsedSec < 30) return 'Just now';
    if (elapsedSec < 60) return `${elapsedSec}s ago`;
    const elapsedMin = Math.floor(elapsedSec / 60);
    if (elapsedMin < 60) return `${elapsedMin}m ago`;
    const elapsedHr = Math.floor(elapsedMin / 60);
    return `${elapsedHr}h ago`;
  };

  return (
    <div className="page-container">
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '16px' }}>
        <div>
          <h2>Customer Directory & Live Operations</h2>
          <p style={{ color: 'var(--text-muted)', fontSize: '14px' }}>
            Real-time verified client accounts, live ride status, and GPS coordinates. Last synced: {lastUpdatedTime}
          </p>
        </div>
        <div style={{ display: 'flex', gap: '10px' }}>
          <button className="btn btn-secondary" onClick={refreshAllData}>
            <span>Refresh</span>
          </button>
          <button className="btn btn-secondary" onClick={handleExportCSV}>
            <Download size={16} />
            <span>Export CSV</span>
          </button>
        </div>
      </div>

      {/* Search and Filters */}
      <div className="card" style={{ padding: '16px', display: 'flex', flexDirection: 'column', gap: '14px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '12px' }}>
          <div className="input-icon-wrapper" style={{ width: '380px' }}>
            <Search size={16} />
            <input 
              type="text" 
              placeholder="Search by name, mobile, customer ID, booking ID..." 
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
            />
          </div>

          {/* Status Filter Tabs */}
          <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
            {[
              { id: 'all', label: 'All Customers' },
              { id: 'in_ride', label: 'In Active Ride' },
              { id: 'searching', label: 'Searching' },
              { id: 'idle', label: 'Idle' },
              { id: 'blocked', label: 'Blocked' }
            ].map(f => (
              <button
                key={f.id}
                className={`btn btn-sm ${statusFilter === f.id ? 'btn-primary' : 'btn-secondary'}`}
                onClick={() => setStatusFilter(f.id as any)}
                style={{ fontSize: '12px' }}
              >
                {f.label}
              </button>
            ))}
          </div>

          {/* Location Availability Filter */}
          <div style={{ display: 'flex', gap: '6px' }}>
            <button
              className={`btn btn-sm ${locationFilter === 'all' ? 'btn-primary' : 'btn-secondary'}`}
              onClick={() => setLocationFilter('all')}
              style={{ fontSize: '11px' }}
            >
              All Locations
            </button>
            <button
              className={`btn btn-sm ${locationFilter === 'has_location' ? 'btn-primary' : 'btn-secondary'}`}
              onClick={() => setLocationFilter('has_location')}
              style={{ fontSize: '11px' }}
            >
              📍 Has Location
            </button>
            <button
              className={`btn btn-sm ${locationFilter === 'no_location' ? 'btn-primary' : 'btn-secondary'}`}
              onClick={() => setLocationFilter('no_location')}
              style={{ fontSize: '11px' }}
            >
              No Location
            </button>
          </div>
        </div>
      </div>

      {/* Customers Table Matching Section 7 */}
      <div className="table-wrapper">
        <table>
          <thead>
            <tr>
              <th>Client Name</th>
              <th>Mobile</th>
              <th>Customer ID</th>
              <th>Booking Status</th>
              <th>Assigned Pilot</th>
              <th>Current Location</th>
              <th>Last Updated</th>
              <th style={{ textAlign: 'right' }}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {filteredCustomers.length > 0 ? (
              filteredCustomers.map(c => {
                const hasLocation = Boolean(c.lat && c.lng && c.lat !== 0 && c.lng !== 0);
                const isSearching = c.bookingStatus === 'searching';
                const isInRide = ['accepted', 'arrived', 'started', 'heading_to_pickup', 'on_trip'].includes(c.bookingStatus || '');

                return (
                  <tr key={c.uid}>
                    {/* Name */}
                    <td>
                      <div style={{ fontWeight: 700, fontSize: '14px' }}>{c.name}</div>
                      <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>{c.email || 'No email provided'}</div>
                    </td>

                    {/* Mobile */}
                    <td>
                      <div style={{ fontWeight: 600, fontSize: '13px', display: 'flex', alignItems: 'center', gap: '6px' }}>
                        <Phone size={12} color="var(--primary)" />
                        <span>+91 {c.phone}</span>
                        <button 
                          onClick={() => copyToClipboard(c.phone, c.uid)} 
                          style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-muted)' }}
                          title="Copy phone"
                        >
                          {copiedText === c.uid ? <Check size={12} color="#10b981" /> : <Copy size={12} />}
                        </button>
                      </div>
                    </td>

                    {/* Customer ID */}
                    <td>
                      <span style={{ fontSize: '12px', fontFamily: 'monospace', color: 'var(--text-muted)' }}>
                        {c.uid}
                      </span>
                    </td>

                    {/* Booking Status */}
                    <td>
                      <span className={`badge ${isInRide ? 'badge-active' : (isSearching ? 'badge-pending' : 'badge-suspended')}`}>
                        {isInRide ? `Active: ${c.bookingStatus}` : (isSearching ? 'Searching Pilot' : 'Idle')}
                      </span>
                      {c.activeBookingId && (
                        <div style={{ fontSize: '10px', color: 'var(--text-muted)', marginTop: '2px', fontFamily: 'monospace' }}>
                          {c.activeBookingId}
                        </div>
                      )}
                    </td>

                    {/* Assigned Pilot */}
                    <td>
                      {c.assignedPilotName ? (
                        <div>
                          <div style={{ fontWeight: 600, fontSize: '13px' }}>{c.assignedPilotName}</div>
                          <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                            +91 {c.assignedPilotPhone} {c.vehiclePlate ? `• ${c.vehiclePlate}` : ''}
                          </div>
                        </div>
                      ) : (
                        <span style={{ fontSize: '12px', color: 'var(--text-muted)', fontStyle: 'italic' }}>
                          None
                        </span>
                      )}
                    </td>

                    {/* Current Location */}
                    <td>
                      {hasLocation ? (
                        <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                          <span style={{ fontSize: '12px', fontFamily: 'monospace' }}>
                            {Number(c.lat).toFixed(4)}, {Number(c.lng).toFixed(4)}
                          </span>
                          <a 
                            href={c.googleMapsUrl || `https://www.google.com/maps?q=${c.lat},${c.lng}`}
                            target="_blank" 
                            rel="noopener noreferrer"
                            className="btn btn-sm btn-secondary"
                            style={{ padding: '2px 6px', fontSize: '10px' }}
                            title="Open Google Maps in new tab"
                          >
                            <ExternalLink size={10} />
                            <span>Map</span>
                          </a>
                        </div>
                      ) : (
                        <span style={{ fontSize: '12px', color: '#94a3b8', fontStyle: 'italic' }}>
                          Location unavailable
                        </span>
                      )}
                    </td>

                    {/* Last Updated */}
                    <td>
                      <div style={{ fontSize: '12px', color: 'var(--text-muted)', display: 'flex', alignItems: 'center', gap: '4px' }}>
                        <Clock size={11} />
                        <span>{formatLastSeen(c.lastLocationUpdate)}</span>
                      </div>
                    </td>

                    {/* Actions */}
                    <td style={{ textAlign: 'right' }}>
                      <div style={{ display: 'flex', gap: '8px', justifyContent: 'flex-end' }}>
                        <button 
                          className="btn btn-secondary btn-sm"
                          onClick={() => setSelectedCustomer(c)}
                          title="Inspect details and relationship"
                        >
                          <Eye size={14} />
                          <span>Inspect</span>
                        </button>
                        {c.googleMapsUrl || (c.lat && c.lng) ? (
                          <a 
                            href={c.googleMapsUrl || `https://maps.google.com/?q=${c.lat},${c.lng}`}
                            target="_blank"
                            rel="noreferrer"
                            className="btn btn-secondary btn-sm"
                            title="View customer on Google Maps"
                            style={{ textDecoration: 'none', display: 'inline-flex', alignItems: 'center', gap: '4px' }}
                          >
                            <Navigation size={14} />
                            <span>Map</span>
                          </a>
                        ) : null}
                        <button 
                          className={`btn btn-sm ${c.status === 'blocked' ? 'btn-success' : 'btn-danger'}`}
                          onClick={() => blockCustomer(c.uid, c.status !== 'blocked')}
                        >
                          {c.status === 'blocked' ? <UserCheck size={14} /> : <ShieldAlert size={14} />}
                          <span>{c.status === 'blocked' ? 'Unblock' : 'Block'}</span>
                        </button>
                      </div>
                    </td>
                  </tr>
                );
              })
            ) : (
              <tr>
                <td colSpan={8} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: '32px' }}>
                  No customer records matched your query or filters.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {/* Customer Profile & Complete Relationship Details Modal */}
      {selectedCustomer && (
        <div className="modal-overlay">
          <div className="modal-content" style={{ maxWidth: '850px' }}>
            <div className="modal-header">
              <div>
                <h3 style={{ fontSize: '18px', fontWeight: 800 }}>Customer Details: {selectedCustomer.name}</h3>
                <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>UID: {selectedCustomer.uid}</span>
              </div>
              <button 
                className="btn btn-secondary btn-icon" 
                onClick={() => setSelectedCustomer(null)}
                style={{ width: '32px', height: '32px', minWidth: '32px' }}
              >
                <X size={14} />
              </button>
            </div>
            <div className="modal-body" style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
              {/* Top Summary Grid */}
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: '12px', backgroundColor: 'var(--bg-input)', padding: '16px', borderRadius: '12px' }}>
                <div>
                  <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Mobile Number</span>
                  <div style={{ fontWeight: 700 }}>+91 {selectedCustomer.phone}</div>
                </div>
                <div>
                  <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Email Address</span>
                  <div style={{ fontWeight: 600 }}>{selectedCustomer.email || 'N/A'}</div>
                </div>
                <div>
                  <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Wallet Balance</span>
                  <div style={{ fontWeight: 800, color: 'var(--primary)' }}>₹{(selectedCustomer.walletBalance || 0).toFixed(2)}</div>
                </div>
                <div>
                  <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Account Standing</span>
                  <div>
                    <span className={`badge badge-${selectedCustomer.status}`}>
                      {selectedCustomer.status}
                    </span>
                  </div>
                </div>
              </div>

              {/* Live Location Details */}
              <div style={{ padding: '16px', borderRadius: '12px', backgroundColor: 'var(--bg-input)', border: '1px solid var(--border)' }}>
                <h4 style={{ margin: '0 0 10px 0', fontSize: '14px', fontWeight: 800, display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <MapPin size={16} color="var(--primary)" />
                  <span>Live Location Coordinates</span>
                </h4>
                {selectedCustomer.lat && selectedCustomer.lng ? (
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '12px' }}>
                    <div>
                      <div><strong>Latitude:</strong> {selectedCustomer.lat}</div>
                      <div><strong>Longitude:</strong> {selectedCustomer.lng}</div>
                      <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginTop: '4px' }}>
                        Last Updated: {formatLastSeen(selectedCustomer.lastLocationUpdate)}
                      </div>
                    </div>
                    <a 
                      href={selectedCustomer.googleMapsUrl || `https://www.google.com/maps?q=${selectedCustomer.lat},${selectedCustomer.lng}`} 
                      target="_blank" 
                      rel="noopener noreferrer"
                      className="btn btn-primary"
                    >
                      <ExternalLink size={14} />
                      <span>Open on Google Maps</span>
                    </a>
                  </div>
                ) : (
                  <div style={{ color: 'var(--text-muted)', fontStyle: 'italic', fontSize: '13px' }}>
                    Location is currently unavailable (Device GPS offline or permissions not granted).
                  </div>
                )}
              </div>

              {/* Complete Relationship Pipeline */}
              <div style={{ padding: '16px', borderRadius: '12px', backgroundColor: 'rgba(59, 130, 246, 0.05)', border: '1px solid rgba(59, 130, 246, 0.3)' }}>
                <h4 style={{ margin: '0 0 12px 0', fontSize: '14px', fontWeight: 800, color: 'var(--primary)', display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <span>🔗 Customer ↔ Booking ↔ Pilot ↔ Vehicle ↔ Owner Relationship</span>
                </h4>

                {selectedCustomer.bookingStatus && selectedCustomer.bookingStatus !== 'none' ? (
                  <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: '14px', fontSize: '13px' }}>
                    <div>
                      <div style={{ color: 'var(--text-muted)', fontSize: '11px' }}>BOOKING IDENTIFIER</div>
                      <div style={{ fontWeight: 700 }}>{selectedCustomer.activeBookingId || 'N/A'}</div>
                    </div>
                    <div>
                      <div style={{ color: 'var(--text-muted)', fontSize: '11px' }}>CURRENT RIDE STATUS</div>
                      <div><span className="badge badge-active">{selectedCustomer.bookingStatus}</span></div>
                    </div>
                    <div>
                      <div style={{ color: 'var(--text-muted)', fontSize: '11px' }}>PICKUP LOCATION</div>
                      <div style={{ fontWeight: 600 }}>{selectedCustomer.currentPickup || 'N/A'}</div>
                    </div>
                    <div>
                      <div style={{ color: 'var(--text-muted)', fontSize: '11px' }}>DESTINATION</div>
                      <div style={{ fontWeight: 600 }}>{selectedCustomer.currentDestination || 'N/A'}</div>
                    </div>
                    <div>
                      <div style={{ color: 'var(--text-muted)', fontSize: '11px' }}>ASSIGNED PILOT</div>
                      <div style={{ fontWeight: 700 }}>{selectedCustomer.assignedPilotName || 'Awaiting acceptance'}</div>
                      <div style={{ fontSize: '12px' }}>{selectedCustomer.assignedPilotPhone ? `+91 ${selectedCustomer.assignedPilotPhone}` : ''}</div>
                    </div>
                    <div>
                      <div style={{ color: 'var(--text-muted)', fontSize: '11px' }}>VEHICLE ASSIGNED</div>
                      <div style={{ fontWeight: 700 }}>{selectedCustomer.vehiclePlate || 'N/A'} ({selectedCustomer.vehicleType || 'Bike'})</div>
                      <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Model: {selectedCustomer.vehicleModel || 'Standard'}</div>
                    </div>
                    <div>
                      <div style={{ color: 'var(--text-muted)', fontSize: '11px' }}>VEHICLE OWNER</div>
                      <div style={{ fontWeight: 700 }}>{selectedCustomer.vehicleOwnerName || 'N/A'}</div>
                    </div>
                    <div>
                      <div style={{ color: 'var(--text-muted)', fontSize: '11px' }}>OWNER MOBILE NUMBER</div>
                      <div style={{ fontWeight: 700 }}>{selectedCustomer.vehicleOwnerPhone ? `+91 ${selectedCustomer.vehicleOwnerPhone}` : 'N/A'}</div>
                    </div>
                  </div>
                ) : (
                  <div style={{ color: 'var(--text-muted)', fontStyle: 'italic', fontSize: '13px' }}>
                    This customer currently has no active booking. Complete relationship links will display automatically when a booking is created and accepted.
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default Customers;
