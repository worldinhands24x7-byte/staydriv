import React, { useState, useMemo } from 'react';
import { useDatabase } from '../context/DatabaseContext';
import { 
  Search, ShieldCheck, ShieldAlert, Award, Star, Eye, Check, X, FileText, Ban,
  Phone, Navigation, ExternalLink, Clock, Car, Radio, CheckCircle2, Copy, Download,
  ZoomIn, AlertTriangle, History, ArrowRight, RefreshCw, MessageSquare
} from 'lucide-react';
import { Partner } from '../data/mockData';

export const Partners: React.FC = () => {
  const { 
    partners, 
    verifyPartner, 
    verifyDocument, 
    rejectDocument, 
    requestCorrection, 
    refreshAllData, 
    lastUpdatedTime 
  } = useDatabase();

  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState<'all' | 'pending' | 'action_required' | 'approved' | 'online' | 'offline' | 'suspended'>('all');
  const [locationFilter, setLocationFilter] = useState<'all' | 'has_location' | 'no_location'>('all');
  const [selectedPartner, setSelectedPartner] = useState<Partner | null>(null);
  const [previewDoc, setPreviewDoc] = useState<{ label: string; url: string } | null>(null);
  const [copiedText, setCopiedText] = useState<string | null>(null);
  const [actionLoading, setActionLoading] = useState(false);

  // Helper to format Registration Time (e.g. "Today, 11:34 PM")
  const formatRegistrationTime = (timestampStr?: string) => {
    if (!timestampStr) return { display: 'Recently', isToday: false };
    const date = new Date(timestampStr);
    if (isNaN(date.getTime())) return { display: 'Recently', isToday: false };

    const now = new Date();
    const isToday = (
      date.getDate() === now.getDate() &&
      date.getMonth() === now.getMonth() &&
      date.getFullYear() === now.getFullYear()
    );

    let hours = date.getHours();
    const minutes = date.getMinutes();
    const ampm = hours >= 12 ? 'PM' : 'AM';
    hours = hours % 12;
    hours = hours ? hours : 12;
    const minutesStr = minutes < 10 ? '0' + minutes : String(minutes);
    const timeStr = `${hours}:${minutesStr} ${ampm}`;

    const yesterday = new Date();
    yesterday.setDate(now.getDate() - 1);
    const isYesterday = (
      date.getDate() === yesterday.getDate() &&
      date.getMonth() === yesterday.getMonth() &&
      date.getFullYear() === yesterday.getFullYear()
    );

    let datePrefix = '';
    if (isToday) {
      datePrefix = 'Today';
    } else if (isYesterday) {
      datePrefix = 'Yesterday';
    } else {
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      datePrefix = `${date.getDate()} ${months[date.getMonth()]}`;
    }

    return {
      display: `${datePrefix}, ${timeStr}`,
      isToday
    };
  };

  // Canonical Status Helper Functions
  const isPilotPending = (p: any): boolean => {
    if (p.approved || p.isApproved) return false;
    const s = String(p.status || '').toUpperCase();
    return s === 'PENDING' || s === 'PENDING_VERIFICATION' || s === 'SUBMITTED' || s === 'UNDER_REVIEW' || s === 'DRAFT' || !p.status;
  };

  const isPilotApproved = (p: any): boolean => {
    if (p.approved || p.isApproved) return true;
    return String(p.status || '').toUpperCase() === 'APPROVED';
  };

  const isPilotActionRequired = (p: any): boolean => {
    const s = String(p.status || '').toUpperCase();
    return s === 'ACTION_REQUIRED' || s === 'RESUBMISSION_REQUIRED' || s === 'REJECTED';
  };

  const isPilotSuspended = (p: any): boolean => {
    if (p.isBlocked) return true;
    return String(p.status || '').toUpperCase() === 'SUSPENDED';
  };

  const counts = useMemo(() => {
    const list = partners || [];
    return {
      all: list.length,
      pending: list.filter(p => isPilotPending(p)).length,
      action_required: list.filter(p => isPilotActionRequired(p)).length,
      approved: list.filter(p => isPilotApproved(p)).length,
      online: list.filter(p => p.online).length,
      offline: list.filter(p => !p.online).length,
      suspended: list.filter(p => isPilotSuspended(p)).length,
    };
  }, [partners]);

  // Filters with newest registrations prioritized at top
  const filteredPartners = useMemo(() => {
    const list = (partners || []).filter(p => {
      const term = searchTerm.toLowerCase().trim();
      const matchesSearch = !term ||
        (p.name && p.name.toLowerCase().includes(term)) ||
        (p.driverName && p.driverName.toLowerCase().includes(term)) ||
        (p.phone && p.phone.includes(term)) ||
        (p.applicationId && p.applicationId.toLowerCase().includes(term)) ||
        (p.ownerName && p.ownerName.toLowerCase().includes(term)) ||
        (p.ownerPhone && p.ownerPhone.includes(term)) ||
        (p.vehiclePlate && p.vehiclePlate.toLowerCase().includes(term)) ||
        (p.vehicleNumber && p.vehicleNumber.toLowerCase().includes(term)) ||
        (p.vehicleType && p.vehicleType.toLowerCase().includes(term)) ||
        (p.vehicleModel && p.vehicleModel.toLowerCase().includes(term)) ||
        (p.uid && p.uid.toLowerCase().includes(term));

      if (!matchesSearch) return false;

      // Status filters using canonical helpers
      if (statusFilter === 'pending') {
        if (!isPilotPending(p)) return false;
      } else if (statusFilter === 'action_required') {
        if (!isPilotActionRequired(p)) return false;
      } else if (statusFilter === 'approved') {
        if (!isPilotApproved(p)) return false;
      } else if (statusFilter === 'online') {
        if (!p.online) return false;
      } else if (statusFilter === 'offline') {
        if (p.online) return false;
      } else if (statusFilter === 'suspended') {
        if (!isPilotSuspended(p)) return false;
      }

      // Location filter
      if (locationFilter === 'has_location') {
        if (!p.hasLocation && (!p.lat || !p.lng)) return false;
      } else if (locationFilter === 'no_location') {
        if (p.hasLocation || (p.lat && p.lng)) return false;
      }

      return true;
    });

    // Sort by registration/submission timestamp descending so newest submissions appear first
    return list.sort((a, b) => {
      const timeA = new Date(a.submittedAt || a.updatedAt || a.createdAt || 0).getTime();
      const timeB = new Date(b.submittedAt || b.updatedAt || b.createdAt || 0).getTime();
      return timeB - timeA;
    });
  }, [partners, searchTerm, statusFilter, locationFilter]);

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

  const getDocStatusBadge = (doc: any, docUrl: string | null) => {
    if (!docUrl) {
      return (
        <span style={{ fontSize: '10px', padding: '2px 6px', borderRadius: '4px', background: 'rgba(148, 163, 184, 0.1)', color: '#94a3b8', fontWeight: 600 }}>
          NOT SUBMITTED
        </span>
      );
    }
    const status = doc?.status || 'PENDING';
    if (status === 'VERIFIED') {
      return (
        <span style={{ fontSize: '10px', padding: '2px 6px', borderRadius: '4px', background: 'rgba(22, 163, 74, 0.15)', color: '#22c55e', border: '1px solid rgba(34, 197, 94, 0.3)', fontWeight: 700 }}>
          ✓ VERIFIED
        </span>
      );
    }
    if (status === 'REJECTED') {
      return (
        <span style={{ fontSize: '10px', padding: '2px 6px', borderRadius: '4px', background: 'rgba(220, 38, 38, 0.15)', color: '#ef4444', border: '1px solid rgba(239, 68, 68, 0.3)', fontWeight: 700 }}>
          ❌ REJECTED
        </span>
      );
    }
    return (
      <span style={{ fontSize: '10px', padding: '2px 6px', borderRadius: '4px', background: 'rgba(245, 158, 11, 0.15)', color: '#f59e0b', border: '1px solid rgba(245, 158, 11, 0.3)', fontWeight: 700 }}>
        ⏳ PENDING REVIEW
      </span>
    );
  };

  const getPartnerStatusBadge = (status?: string, isBlocked?: boolean) => {
    if (isBlocked || status === 'suspended') {
      return <span className="badge badge-suspended" style={{ fontSize: '11px', fontWeight: 700 }}>🚫 Suspended</span>;
    }
    const s = String(status || '').toUpperCase();
    if (s === 'APPROVED') {
      return <span className="badge badge-active" style={{ fontSize: '11px', fontWeight: 700 }}>✓ Approved</span>;
    }
    if (s === 'REJECTED') {
      return <span className="badge" style={{ backgroundColor: 'rgba(239, 68, 68, 0.2)', color: '#ef4444', border: '1px solid #ef4444', fontSize: '11px', fontWeight: 700 }}>✖ Rejected</span>;
    }
    if (s === 'ACTION_REQUIRED' || s === 'RESUBMISSION_REQUIRED') {
      return <span className="badge" style={{ backgroundColor: 'rgba(239, 68, 68, 0.2)', color: '#ef4444', border: '1px solid #ef4444', fontSize: '11px', fontWeight: 700 }}>⚠️ Resubmission Required</span>;
    }
    if (s === 'UNDER_REVIEW') {
      return <span className="badge" style={{ backgroundColor: 'rgba(59, 130, 246, 0.2)', color: '#60a5fa', border: '1px solid #60a5fa', fontSize: '11px', fontWeight: 700 }}>🔍 Under Review</span>;
    }
    if (s === 'SUBMITTED' || s === 'PENDING_VERIFICATION' || s === 'PENDING' || s === 'DRAFT') {
      return <span className="badge badge-pending" style={{ fontSize: '11px', fontWeight: 700 }}>⏳ Pending Verification</span>;
    }
    return <span className="badge badge-pending" style={{ fontSize: '11px', fontWeight: 700 }}>⏳ {status || 'Pending Verification'}</span>;
  };

  // Keep selected partner synchronized when partners list updates in real-time
  React.useEffect(() => {
    if (selectedPartner) {
      const updated = partners.find(p => p.uid === selectedPartner.uid);
      if (updated) {
        setSelectedPartner(updated);
      }
    }
  }, [partners]);

  return (
    <div className="page-container">
      {/* Page Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '16px' }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <h2>Pilot Applications & KYC Document Verification</h2>
            <span style={{ 
              display: 'inline-flex', 
              alignItems: 'center', 
              gap: '6px', 
              padding: '4px 10px', 
              borderRadius: '20px', 
              fontSize: '11px', 
              fontWeight: 700, 
              background: counts.pending > 0 ? 'rgba(245, 158, 11, 0.15)' : 'rgba(34, 197, 94, 0.15)', 
              color: counts.pending > 0 ? '#f59e0b' : '#22c55e' 
            }}>
              <CheckCircle2 size={12} />
              {counts.pending > 0 ? `${counts.pending} AWAITING APPROVAL` : 'ALL APPLICATIONS REVIEWED'}
            </span>
          </div>
          <p style={{ color: 'var(--text-muted)', fontSize: '14px', marginTop: '4px' }}>
            Verify driving licenses, RC, Aadhaar, PAN cards and activate verified pilots. Real-time updates via live WebSockets. Last synced: {lastUpdatedTime}
          </p>
        </div>

        <button className="btn btn-secondary" onClick={refreshAllData} style={{ display: 'inline-flex', alignItems: 'center', gap: '6px' }}>
          <RefreshCw size={14} />
          <span>Refresh Fleet Data</span>
        </button>
      </div>

      {/* Tabs and Search Bar */}
      <div className="card" style={{ padding: '16px', display: 'flex', flexDirection: 'column', gap: '14px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '12px' }}>
          <div className="input-icon-wrapper" style={{ width: '380px' }}>
            <Search size={16} />
            <input 
              type="text" 
              placeholder="Search pilot name, Application ID, mobile, vehicle plate..." 
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
            />
          </div>

          {/* Status Filter Tabs */}
          <div style={{ display: 'flex', gap: '6px', flexWrap: 'wrap' }}>
            {[
              { id: 'all', label: `All Pilots (${counts.all})` },
              { id: 'pending', label: `⏳ Pending Approvals (${counts.pending})`, alert: counts.pending > 0 },
              { id: 'action_required', label: `⚠️ Action Required (${counts.action_required})`, alert: counts.action_required > 0 },
              { id: 'approved', label: `✓ Approved (${counts.approved})` },
              { id: 'online', label: `🟢 Online (${counts.online})` },
              { id: 'offline', label: `Offline (${counts.offline})` },
              { id: 'suspended', label: `🚫 Suspended (${counts.suspended})` },
            ].map(tab => (
              <button 
                key={tab.id}
                className={`btn btn-sm ${statusFilter === tab.id ? 'btn-primary' : 'btn-secondary'}`}
                onClick={() => setStatusFilter(tab.id as any)}
                style={{ 
                  fontSize: '12px', 
                  fontWeight: statusFilter === tab.id ? 700 : 500,
                  position: 'relative'
                }}
              >
                {tab.label}
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
              📍 Has GPS
            </button>
            <button
              className={`btn btn-sm ${locationFilter === 'no_location' ? 'btn-primary' : 'btn-secondary'}`}
              onClick={() => setLocationFilter('no_location')}
              style={{ fontSize: '11px' }}
            >
              No GPS
            </button>
          </div>
        </div>
      </div>

      {/* Pilots Table */}
      <div className="table-wrapper" style={{ overflowX: 'auto', position: 'relative' }}>
        <table>
          <thead>
            <tr>
              <th style={{ minWidth: '220px' }}>Pilot & Application ID</th>
              <th style={{ minWidth: '180px' }}>Vehicle & Owner</th>
              <th style={{ minWidth: '160px' }}>Submitted Time</th>
              <th style={{ minWidth: '160px' }}>Verification Status</th>
              <th style={{ minWidth: '150px' }}>Live GPS Telemetry</th>
              <th style={{ 
                position: 'sticky', 
                right: 0, 
                backgroundColor: 'var(--bg-card, #0f172a)', 
                boxShadow: '-8px 0 16px -2px rgba(0, 0, 0, 0.4)',
                zIndex: 11,
                textAlign: 'right',
                minWidth: '240px'
              }}>
                Actions
              </th>
            </tr>
          </thead>
          <tbody>
            {filteredPartners.length > 0 ? (
              filteredPartners.map(p => {
                const hasLocation = Boolean(p.lat && p.lng && p.lat !== 0 && p.lng !== 0);
                const isOnline = Boolean(p.online);
                const rideStatus = p.rideStatus || (isOnline ? 'Available' : 'Offline');
                const regTime = formatRegistrationTime(p.submittedAt || p.createdAt);
                const isPending = isPilotPending(p);
                const isActionRequired = isPilotActionRequired(p);
                const isApproved = isPilotApproved(p);

                // Document verified stats
                const docs = p.documents || {};
                const docKeys = Object.keys(docs);
                const verifiedDocsCount = docKeys.filter(k => docs[k]?.status === 'VERIFIED').length;
                const rejectedDocsCount = docKeys.filter(k => docs[k]?.status === 'REJECTED').length;

                return (
                  <tr key={p.uid} style={isPending ? { backgroundColor: 'rgba(245, 158, 11, 0.03)' } : (isActionRequired ? { backgroundColor: 'rgba(239, 68, 68, 0.03)' } : {})}>
                    {/* Pilot, Application ID & Mobile */}
                    <td>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                        <div style={{
                          width: '34px',
                          height: '34px',
                          borderRadius: '50%',
                          background: 'var(--bg-input)',
                          display: 'flex',
                          alignItems: 'center',
                          justifyContent: 'center',
                          fontWeight: 800,
                          fontSize: '13px',
                          color: 'var(--primary)',
                          overflow: 'hidden'
                        }}>
                          {p.photo ? <img src={p.photo} alt={p.name} style={{ width: '100%', height: '100%', objectFit: 'cover' }} /> : (p.name ? p.name[0].toUpperCase() : 'P')}
                        </div>
                        <div>
                          <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                            <span style={{ fontWeight: 700, fontSize: '13px', color: '#f8fafc' }}>
                              {p.name || p.driverName || 'StayDriv Pilot'}
                            </span>
                            {isPending && (
                              <span className="badge badge-pending" style={{ fontSize: '9px', padding: '1px 5px', fontWeight: 800 }}>
                                PENDING REVIEW
                              </span>
                            )}
                          </div>
                          
                          {/* Application ID with copy */}
                          <div style={{ display: 'flex', alignItems: 'center', gap: '4px', marginTop: '2px' }}>
                            <span style={{ fontSize: '11px', fontFamily: 'monospace', color: '#38bdf8', fontWeight: 600 }}>
                              App ID: {p.applicationId || 'SD-PLT-PENDING'}
                            </span>
                            <button 
                              onClick={() => copyToClipboard(p.applicationId || '', p.uid + '_appId')}
                              style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-muted)', padding: '1px' }}
                              title="Copy Application ID"
                            >
                              {copiedText === p.uid + '_appId' ? <Check size={11} color="#10b981" /> : <Copy size={11} />}
                            </button>
                          </div>

                          {/* Mobile */}
                          <div style={{ fontWeight: 600, fontSize: '12px', display: 'flex', alignItems: 'center', gap: '4px', marginTop: '1px' }}>
                            <Phone size={11} color="var(--primary)" />
                            <span>+91 {p.phone || p.driverPhone}</span>
                            <button 
                              onClick={() => copyToClipboard(p.phone || p.driverPhone || '', p.uid + '_phone')}
                              style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-muted)', padding: '1px' }}
                              title="Copy Phone"
                            >
                              {copiedText === p.uid + '_phone' ? <Check size={11} color="#10b981" /> : <Copy size={11} />}
                            </button>
                          </div>
                        </div>
                      </div>
                    </td>

                    {/* Vehicle & Owner */}
                    <td>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '6px', marginBottom: '4px' }}>
                        <span className="badge badge-secondary" style={{ fontWeight: 700, fontSize: '11px', display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
                          <Car size={12} />
                          {p.vehicleType || 'Bike'}
                        </span>
                        <span style={{ fontWeight: 800, fontSize: '12px', fontFamily: 'monospace', color: 'var(--primary)', letterSpacing: '0.5px' }}>
                          {p.vehiclePlate || p.vehicleNumber || 'Unassigned'}
                        </span>
                      </div>
                      <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                        Owner: <strong style={{ color: '#cbd5e1' }}>{p.ownerName || p.name}</strong>
                      </div>
                    </td>

                    {/* Registration / Submission Time */}
                    <td>
                      <div>
                        <div style={{ 
                          display: 'inline-flex', 
                          alignItems: 'center', 
                          gap: '6px', 
                          padding: '3px 8px', 
                          borderRadius: '6px', 
                          backgroundColor: regTime.isToday ? 'rgba(245, 158, 11, 0.15)' : 'rgba(148, 163, 184, 0.1)',
                          border: `1px solid ${regTime.isToday ? 'rgba(245, 158, 11, 0.4)' : 'rgba(148, 163, 184, 0.2)'}`,
                          fontWeight: 700,
                          fontSize: '12px',
                          color: regTime.isToday ? '#fbbf24' : '#e2e8f0'
                        }}>
                          <Clock size={12} color={regTime.isToday ? '#fbbf24' : 'var(--primary)'} />
                          <span>{regTime.display}</span>
                        </div>
                        <div style={{ fontSize: '10px', color: 'var(--text-muted)', marginTop: '2px' }}>
                          {isPending ? '⏳ Awaiting verification' : (p.status === 'approved' ? '✓ Active Fleet' : 'Action Required')}
                        </div>
                      </div>
                    </td>

                    {/* Verification Status & Docs Breakdown */}
                    <td>
                      <div style={{ display: 'flex', flexDirection: 'column', gap: '4px', alignItems: 'flex-start' }}>
                        {getPartnerStatusBadge(p.status, (p as any).isBlocked)}
                        
                        <div style={{ fontSize: '11px', color: 'var(--text-muted)', display: 'flex', alignItems: 'center', gap: '4px' }}>
                          <FileText size={11} />
                          <span>
                            {docKeys.length > 0 ? (
                              rejectedDocsCount > 0 ? (
                                <span style={{ color: '#ef4444' }}>{rejectedDocsCount} Doc(s) Rejected</span>
                              ) : verifiedDocsCount === docKeys.length ? (
                                <span style={{ color: '#22c55e' }}>All {docKeys.length} Docs Verified</span>
                              ) : (
                                <span>{verifiedDocsCount}/{docKeys.length} Docs Verified</span>
                              )
                            ) : (
                              <span>No documents yet</span>
                            )}
                          </span>
                        </div>
                      </div>
                    </td>

                    {/* Live GPS & Telemetry */}
                    <td>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '6px', marginBottom: '4px' }}>
                        <span className={`badge ${isOnline ? 'badge-active' : 'badge-suspended'}`} style={{ fontSize: '10px' }}>
                          {isOnline ? 'Online' : 'Offline'}
                        </span>
                        <span className="badge badge-secondary" style={{ fontSize: '10px' }}>
                          {rideStatus}
                        </span>
                      </div>
                      {hasLocation ? (
                        <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                          <span style={{ fontSize: '11px', fontFamily: 'monospace', color: '#94a3b8' }}>
                            {Number(p.lat).toFixed(4)}, {Number(p.lng).toFixed(4)}
                          </span>
                          <a 
                            href={p.googleMapsUrl || `https://www.google.com/maps?q=${p.lat},${p.lng}`}
                            target="_blank" 
                            rel="noopener noreferrer"
                            className="btn btn-sm btn-secondary"
                            style={{ padding: '2px 5px', fontSize: '10px' }}
                            title="Open Google Maps in new tab"
                          >
                            <ExternalLink size={9} />
                            <span>Map</span>
                          </a>
                        </div>
                      ) : (
                        <span style={{ fontSize: '11px', color: '#64748b', fontStyle: 'italic' }}>
                          GPS Idle
                        </span>
                      )}
                    </td>

                    {/* Actions Column (Sticky Right) */}
                    <td style={{ 
                      position: 'sticky', 
                      right: 0, 
                      backgroundColor: 'var(--bg-card, #0f172a)', 
                      boxShadow: '-8px 0 16px -2px rgba(0, 0, 0, 0.4)',
                      zIndex: 10,
                      textAlign: 'right'
                    }}>
                      <div style={{ display: 'flex', gap: '6px', justifyContent: 'flex-end', alignItems: 'center', flexWrap: 'nowrap' }}>
                        <button 
                          className="btn btn-primary btn-sm"
                          onClick={() => setSelectedPartner(p)}
                          title="Inspect Pilot Profile, Documents and Verification Controls"
                          style={{ padding: '5px 10px', fontSize: '12px', whiteSpace: 'nowrap', fontWeight: 700 }}
                        >
                          <Eye size={13} style={{ marginRight: '4px' }} />
                          <span>Inspect KYC</span>
                        </button>

                        {isPending ? (
                          <>
                            <button 
                              className="btn btn-sm btn-success"
                              onClick={async () => {
                                if (window.confirm(`Approve pilot application for ${p.name || p.phone}?`)) {
                                  await verifyPartner(p.uid, 'approved');
                                }
                              }}
                              title="Approve Pilot Application"
                              style={{ padding: '5px 8px', fontSize: '11px', whiteSpace: 'nowrap', backgroundColor: '#16a34a', color: 'white', fontWeight: 700 }}
                            >
                              <Check size={13} />
                              <span>Approve</span>
                            </button>
                            <button 
                              className="btn btn-sm btn-danger"
                              onClick={async () => {
                                const reason = window.prompt(`Enter rejection reason for ${p.name || p.phone}:`, 'Documents unreadable or incomplete');
                                if (reason) {
                                  await verifyPartner(p.uid, 'rejected', reason);
                                }
                              }}
                              title="Reject Pilot Application"
                              style={{ padding: '5px 8px', fontSize: '11px', whiteSpace: 'nowrap', backgroundColor: '#dc2626', color: 'white' }}
                            >
                              <X size={13} />
                              <span>Reject</span>
                            </button>
                          </>
                        ) : isApproved ? (
                          <button 
                            className="btn btn-sm btn-danger"
                            onClick={async () => {
                              const reason = window.prompt(`Enter suspension reason for ${p.name || p.phone}:`, 'Operational disciplinary suspension');
                              if (reason) {
                                await verifyPartner(p.uid, 'suspended', reason);
                              }
                            }}
                            title="Suspend Pilot Account"
                            style={{ padding: '5px 8px', fontSize: '11px', whiteSpace: 'nowrap' }}
                          >
                            <Ban size={13} />
                            <span>Suspend</span>
                          </button>
                        ) : (
                          <button 
                            className="btn btn-sm btn-success"
                            onClick={async () => {
                              if (window.confirm(`Re-activate pilot account for ${p.name || p.phone}?`)) {
                                await verifyPartner(p.uid, 'approved');
                              }
                            }}
                            title="Re-activate Pilot Account"
                            style={{ padding: '5px 8px', fontSize: '11px', whiteSpace: 'nowrap' }}
                          >
                            <CheckCircle2 size={13} />
                            <span>Re-Approve</span>
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                );
              })
            ) : (
              <tr>
                <td colSpan={6} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: '40px' }}>
                  <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '8px' }}>
                    <ShieldCheck size={36} color="var(--primary)" style={{ opacity: 0.7 }} />
                    <div style={{ fontSize: '15px', fontWeight: 700, color: '#f8fafc' }}>
                      {statusFilter === 'pending' ? 'No pending pilot applications awaiting approval' : 'No pilot records match your search or filter'}
                    </div>
                    <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
                      New pilot registrations will appear here automatically via real-time WebSocket events.
                    </div>
                  </div>
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {/* Comprehensive Pilot KYC & Document Verification Inspection Modal */}
      {selectedPartner && (
        <div className="modal-overlay">
          <div className="modal-content" style={{ maxWidth: '960px', maxHeight: '92vh', overflowY: 'auto' }}>
            <div className="modal-header" style={{ position: 'sticky', top: 0, backgroundColor: 'var(--bg-card)', zIndex: 20, borderBottom: '1px solid var(--border)', paddingBottom: '12px' }}>
              <div>
                <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                  <h3 style={{ fontSize: '18px', fontWeight: 800, margin: 0 }}>
                    Pilot Application: {selectedPartner.name}
                  </h3>
                  {getPartnerStatusBadge(selectedPartner.status, (selectedPartner as any).isBlocked)}
                </div>
                <div style={{ display: 'flex', gap: '14px', alignItems: 'center', fontSize: '12px', color: 'var(--text-muted)', marginTop: '4px' }}>
                  <span style={{ fontFamily: 'monospace', color: '#38bdf8', fontWeight: 700 }}>
                    Application ID: {selectedPartner.applicationId || 'SD-PLT-PENDING'}
                  </span>
                  <span>UID: {selectedPartner.uid}</span>
                  <span>Mobile: +91 {selectedPartner.phone}</span>
                </div>
              </div>
              <button 
                className="btn btn-secondary btn-icon" 
                onClick={() => setSelectedPartner(null)}
                style={{ width: '32px', height: '32px', minWidth: '32px' }}
              >
                <X size={14} />
              </button>
            </div>

            <div className="modal-body" style={{ display: 'flex', flexDirection: 'column', gap: '18px', paddingTop: '16px' }}>
              {/* Correction / Rejection Alerts if applicable */}
              {selectedPartner.rejectionReason && (
                <div style={{ 
                  backgroundColor: 'rgba(239, 68, 68, 0.12)', 
                  border: '1px solid rgba(239, 68, 68, 0.4)', 
                  padding: '12px 16px', 
                  borderRadius: '10px',
                  display: 'flex',
                  alignItems: 'center',
                  gap: '10px'
                }}>
                  <AlertTriangle size={18} color="#ef4444" style={{ flexShrink: 0 }} />
                  <div>
                    <div style={{ fontWeight: 700, color: '#ef4444', fontSize: '13px' }}>
                      Rejection / Correction Notice
                    </div>
                    <div style={{ fontSize: '12px', color: '#fca5a5', marginTop: '2px' }}>
                      {selectedPartner.rejectionReason}
                    </div>
                  </div>
                </div>
              )}

              {/* Overview Details Grid */}
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))', gap: '12px', backgroundColor: 'var(--bg-input)', padding: '14px', borderRadius: '10px', border: '1px solid var(--border)' }}>
                <div>
                  <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Pilot Name</span>
                  <div style={{ fontWeight: 700, fontSize: '13px' }}>{selectedPartner.name}</div>
                </div>
                <div>
                  <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Registered Phone</span>
                  <div style={{ fontWeight: 700, fontSize: '13px' }}>+91 {selectedPartner.phone}</div>
                </div>
                <div>
                  <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Vehicle Type</span>
                  <div style={{ fontWeight: 800, color: 'var(--primary)', fontSize: '13px' }}>{selectedPartner.vehicleType || 'Bike'}</div>
                </div>
                <div>
                  <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Registration Plate</span>
                  <div style={{ fontWeight: 800, fontFamily: 'monospace', color: '#f8fafc', fontSize: '13px' }}>
                    {selectedPartner.vehiclePlate || selectedPartner.vehicleNumber || 'Unassigned'}
                  </div>
                </div>
                <div>
                  <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Make & Model</span>
                  <div style={{ fontWeight: 700, fontSize: '13px', color: '#e2e8f0' }}>
                    {selectedPartner.vehicleMake ? `${selectedPartner.vehicleMake} ${selectedPartner.vehicleModel || ''}` : (selectedPartner.vehicleModel || 'Standard')}
                  </div>
                </div>
                <div>
                  <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Vehicle Colour</span>
                  <div style={{ fontWeight: 700, fontSize: '13px', color: '#38bdf8' }}>
                    {selectedPartner.vehicleColor || 'Standard'}
                  </div>
                </div>
                <div>
                  <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Registration Date</span>
                  <div style={{ fontWeight: 700, fontSize: '13px', color: '#f8fafc' }}>
                    {selectedPartner.vehicleRegistrationDate || 'Not Provided'}
                  </div>
                </div>
                <div>
                  <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Insurance Expiry</span>
                  <div style={{ fontWeight: 700, fontSize: '13px', color: '#fbbf24' }}>
                    {selectedPartner.insuranceExpiryDate || 'Not Provided'}
                  </div>
                </div>
                {selectedPartner.address && (
                  <div style={{ gridColumn: '1 / -1' }}>
                    <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Residential Address</span>
                    <div style={{ fontWeight: 600, fontSize: '12px', color: '#cbd5e1', marginTop: '2px' }}>
                      {selectedPartner.address}
                    </div>
                  </div>
                )}
                <div>
                  <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Vehicle Owner</span>
                  <div style={{ fontWeight: 600, fontSize: '13px' }}>{selectedPartner.ownerName || selectedPartner.name}</div>
                </div>
                {(selectedPartner as any).driverPhone && (selectedPartner as any).driverPhone !== selectedPartner.phone && (
                  <div>
                    <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Assigned Driver Mobile</span>
                    <div style={{ fontWeight: 700, fontSize: '13px', color: '#ea580c' }}>📞 +91 {(selectedPartner as any).driverPhone}</div>
                  </div>
                )}
                <div>
                  <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Submitted Time</span>
                  <div style={{ fontWeight: 700, color: '#fbbf24', fontSize: '12px' }}>
                    {formatRegistrationTime(selectedPartner.submittedAt || (selectedPartner as any).createdAt).display}
                  </div>
                </div>
                <div>
                  <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Approval Status</span>
                  <div style={{ fontWeight: 800, fontSize: '12px' }}>
                    {selectedPartner.status?.toUpperCase() || 'PENDING'}
                  </div>
                </div>
              </div>

              {/* Individual Document Verification Suite */}
              <div style={{ padding: '16px', borderRadius: '12px', backgroundColor: 'var(--bg-input)', border: '1px solid var(--border)' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '14px' }}>
                  <h4 style={{ margin: 0, fontSize: '15px', fontWeight: 800, display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <FileText size={18} color="var(--primary)" />
                    <span>Pilot Documents & Verification Controls</span>
                  </h4>
                  <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
                    Verify each uploaded KYC document individually
                  </span>
                </div>

                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))', gap: '14px' }}>
                  {[
                    { key: 'aadhaarFront', label: 'Aadhaar Card - Front', url: selectedPartner.aadhaarFront || selectedPartner.documents?.aadhaarFront?.url || selectedPartner.documents?.aadhaarFront },
                    { key: 'aadhaarBack', label: 'Aadhaar Card - Back', url: selectedPartner.aadhaarBack || selectedPartner.documents?.aadhaarBack?.url || selectedPartner.documents?.aadhaarBack },
                    { key: 'panFront', label: 'PAN Card - Front', url: selectedPartner.panFront || selectedPartner.documents?.panFront?.url || selectedPartner.documents?.panFront },
                    { key: 'panBack', label: 'PAN Card - Back', url: selectedPartner.panBack || selectedPartner.documents?.panBack?.url || selectedPartner.documents?.panBack },
                    { key: 'rcFront', label: 'Vehicle RC - Front', url: selectedPartner.rcFront || selectedPartner.documents?.rcFront?.url || selectedPartner.documents?.rcFront },
                    { key: 'rcBack', label: 'Vehicle RC - Back', url: selectedPartner.rcBack || selectedPartner.documents?.rcBack?.url || selectedPartner.documents?.rcBack },
                    { key: 'insurance', label: 'Vehicle Insurance Copy', url: selectedPartner.insuranceDocument || (selectedPartner as any).insuranceDocumentUrl || selectedPartner.documents?.insurance?.url || selectedPartner.documents?.insurance },
                    { key: 'licenseFront', label: 'Driving License - Front', url: selectedPartner.licenseFront || selectedPartner.documents?.licenseFront?.url || selectedPartner.documents?.licenseFront },
                    { key: 'licenseBack', label: 'Driving License - Back', url: selectedPartner.licenseBack || selectedPartner.documents?.licenseBack?.url || selectedPartner.documents?.licenseBack },
                    { key: 'driverLicenseFront', label: 'New Assigned Driver License - Front', url: (selectedPartner as any).driverLicenseFront || selectedPartner.documents?.driverLicenseFront?.url },
                    { key: 'driverLicenseBack', label: 'New Assigned Driver License - Back', url: (selectedPartner as any).driverLicenseBack || selectedPartner.documents?.driverLicenseBack?.url },
                    { key: 'photo', label: 'Pilot Profile Photo', url: selectedPartner.photo || selectedPartner.documents?.photo?.url || selectedPartner.documents?.photo },
                    { key: 'fitness', label: 'Fitness Certificate', url: selectedPartner.fitness || selectedPartner.documents?.fitness?.url || selectedPartner.documents?.fitness },
                    { key: 'permit', label: 'Vehicle Commercial Permit', url: selectedPartner.permit || selectedPartner.documents?.permit?.url || selectedPartner.documents?.permit },
                  ].map((docItem, idx) => {
                    const rawUrl = typeof docItem.url === 'string' ? docItem.url : docItem.url?.url;
                    const docObj = (selectedPartner.documents && typeof selectedPartner.documents === 'object') ? selectedPartner.documents[docItem.key] : null;
                    const docUrl = rawUrl ? (rawUrl.startsWith('http') ? rawUrl : `${window.location.origin}${rawUrl}`) : null;
                    const docStatus = docObj?.status || (docUrl ? 'PENDING' : 'NOT_SUBMITTED');

                    return (
                      <div key={idx} style={{ 
                        borderRadius: '10px', 
                        border: '1px solid var(--border)', 
                        padding: '12px', 
                        backgroundColor: 'var(--bg-card)',
                        display: 'flex',
                        flexDirection: 'column',
                        justifyContent: 'space-between',
                        gap: '10px'
                      }}>
                        <div>
                          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '6px' }}>
                            <div style={{ fontSize: '12px', fontWeight: 700, color: 'var(--text-main)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                              {docItem.label}
                            </div>
                          </div>

                          <div style={{ marginBottom: '8px' }}>
                            {getDocStatusBadge(docObj, docUrl)}
                          </div>

                          {/* Image Thumbnail / Empty Placeholder */}
                          {docUrl ? (
                            <div 
                              style={{ 
                                position: 'relative', 
                                width: '100%', 
                                height: '110px', 
                                borderRadius: '6px', 
                                overflow: 'hidden', 
                                backgroundColor: '#0f172a',
                                cursor: 'pointer',
                                border: '1px solid rgba(255, 255, 255, 0.05)'
                              }}
                              onClick={() => setPreviewDoc({ label: docItem.label, url: docUrl })}
                              title="Click to zoom / preview in full screen"
                            >
                              <img 
                                src={docUrl} 
                                alt={docItem.label} 
                                style={{ width: '100%', height: '100%', objectFit: 'cover' }} 
                                onError={(e) => { 
                                  (e.target as any).src = 'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><text x="10" y="50" fill="%23aaa">Image Error</text></svg>'; 
                                }}
                              />
                              <div style={{ 
                                position: 'absolute', 
                                inset: 0, 
                                backgroundColor: 'rgba(0,0,0,0.3)', 
                                display: 'flex', 
                                alignItems: 'center', 
                                justifyContent: 'center',
                                opacity: 0,
                                transition: 'opacity 0.2s',
                              }}
                              onMouseEnter={(e) => { (e.currentTarget as any).style.opacity = '1'; }}
                              onMouseLeave={(e) => { (e.currentTarget as any).style.opacity = '0'; }}
                              >
                                <span style={{ background: 'rgba(0,0,0,0.7)', color: 'white', padding: '4px 8px', borderRadius: '4px', fontSize: '11px', display: 'flex', alignItems: 'center', gap: '4px' }}>
                                  <ZoomIn size={12} /> Preview
                                </span>
                              </div>
                            </div>
                          ) : (
                            <div style={{ 
                              height: '110px', 
                              display: 'flex', 
                              alignItems: 'center', 
                              justifyContent: 'center', 
                              backgroundColor: 'rgba(148, 163, 184, 0.06)', 
                              borderRadius: '6px',
                              fontSize: '11px',
                              color: 'var(--text-muted)',
                              fontStyle: 'italic',
                              textAlign: 'center',
                              padding: '8px'
                            }}>
                              Not submitted
                            </div>
                          )}

                          {/* Rejection reason notice if rejected */}
                          {docObj?.rejectionReason && (
                            <div style={{ fontSize: '10px', color: '#ef4444', backgroundColor: 'rgba(239, 68, 68, 0.1)', padding: '4px 6px', borderRadius: '4px', marginTop: '6px' }}>
                              Reason: {docObj.rejectionReason}
                            </div>
                          )}
                        </div>

                        {/* Document Action Buttons */}
                        {docUrl ? (
                          <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
                            <div style={{ display: 'flex', gap: '6px' }}>
                              <button 
                                className="btn btn-sm btn-secondary" 
                                style={{ flex: 1, fontSize: '10px', padding: '3px 4px', textAlign: 'center' }}
                                onClick={() => setPreviewDoc({ label: docItem.label, url: docUrl })}
                              >
                                <ZoomIn size={11} style={{ marginRight: '3px' }} />
                                <span>Preview</span>
                              </button>
                              <a 
                                href={docUrl} 
                                download={`${selectedPartner.name || 'pilot'}_${docItem.key}.jpg`}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="btn btn-sm btn-secondary" 
                                style={{ fontSize: '10px', padding: '3px 6px', textAlign: 'center' }}
                                title="Download Document"
                              >
                                <Download size={11} />
                              </a>
                            </div>

                            <div style={{ display: 'flex', gap: '6px' }}>
                              <button 
                                className="btn btn-sm btn-success" 
                                style={{ 
                                  flex: 1, 
                                  fontSize: '10px', 
                                  padding: '4px 6px',
                                  backgroundColor: docStatus === 'VERIFIED' ? '#15803d' : '#16a34a',
                                  color: 'white',
                                  fontWeight: 700 
                                }}
                                disabled={actionLoading}
                                onClick={async () => {
                                  setActionLoading(true);
                                  await verifyDocument(selectedPartner.uid, docItem.key);
                                  setActionLoading(false);
                                }}
                              >
                                <Check size={11} style={{ marginRight: '3px' }} />
                                <span>{docStatus === 'VERIFIED' ? 'Verified' : 'Verify'}</span>
                              </button>
                              <button 
                                className="btn btn-sm btn-danger" 
                                style={{ 
                                  flex: 1, 
                                  fontSize: '10px', 
                                  padding: '4px 6px',
                                  backgroundColor: docStatus === 'REJECTED' ? '#b91c1c' : '#dc2626',
                                  color: 'white' 
                                }}
                                disabled={actionLoading}
                                onClick={async () => {
                                  const reason = window.prompt(`Enter reason for rejecting ${docItem.label}:`, 'Document is blurry or unreadable');
                                  if (reason) {
                                    setActionLoading(true);
                                    await rejectDocument(selectedPartner.uid, docItem.key, reason);
                                    setActionLoading(false);
                                  }
                                }}
                              >
                                <X size={11} style={{ marginRight: '3px' }} />
                                <span>Reject</span>
                              </button>
                            </div>
                          </div>
                        ) : null}
                      </div>
                    );
                  })}
                </div>

                {/* Overall Application Decision Actions */}
                <div style={{ 
                  display: 'flex', 
                  justifyContent: 'space-between', 
                  alignItems: 'center', 
                  flexWrap: 'wrap', 
                  gap: '12px', 
                  marginTop: '20px', 
                  paddingTop: '16px', 
                  borderTop: '1px solid var(--border)' 
                }}>
                  <div style={{ display: 'flex', gap: '8px' }}>
                    <button 
                      className="btn btn-secondary"
                      disabled={actionLoading}
                      onClick={async () => {
                        const notes = window.prompt(`Enter correction instructions for pilot ${selectedPartner.name}:`, 'Please upload clear photos of your Driving License and PAN card.');
                        if (notes) {
                          setActionLoading(true);
                          await requestCorrection(selectedPartner.uid, notes);
                          setActionLoading(false);
                        }
                      }}
                      style={{ fontSize: '13px' }}
                    >
                      <MessageSquare size={15} style={{ marginRight: '6px' }} />
                      <span>Request Correction / Re-upload</span>
                    </button>
                  </div>

                  <div style={{ display: 'flex', gap: '10px' }}>
                    {selectedPartner.status !== 'approved' ? (
                      <>
                        <button 
                          className="btn btn-danger"
                          disabled={actionLoading}
                          onClick={async () => {
                            const reason = window.prompt('Enter reason for rejecting application:', 'Document verification failed') || 'Rejected by Admin';
                            setActionLoading(true);
                            await verifyPartner(selectedPartner.uid, 'rejected', reason);
                            setActionLoading(false);
                          }}
                        >
                          <X size={16} />
                          <span>Reject Entire Application</span>
                        </button>
                        <button 
                          className="btn btn-success"
                          disabled={actionLoading}
                          onClick={async () => {
                            if (window.confirm(`Approve all verified documents and activate ${selectedPartner.name} as StayDriv Pilot?`)) {
                              setActionLoading(true);
                              await verifyPartner(selectedPartner.uid, 'approved');
                              setActionLoading(false);
                            }
                          }}
                          style={{ fontWeight: 800, padding: '8px 18px' }}
                        >
                          <Check size={18} />
                          <span>Approve & Activate Pilot</span>
                        </button>
                      </>
                    ) : (
                      <>
                        <button 
                          className="btn btn-danger"
                          disabled={actionLoading}
                          onClick={async () => {
                            const reason = window.prompt('Enter reason for suspension:', 'Administrative review') || 'Suspended by Admin';
                            setActionLoading(true);
                            await verifyPartner(selectedPartner.uid, 'suspended', reason);
                            setActionLoading(false);
                          }}
                        >
                          <Ban size={16} />
                          <span>Suspend Account</span>
                        </button>
                      </>
                    )}
                  </div>
                </div>
              </div>

              {/* Verification Audit Trail & History */}
              {selectedPartner.verificationHistory && selectedPartner.verificationHistory.length > 0 && (
                <div style={{ padding: '16px', borderRadius: '12px', backgroundColor: 'var(--bg-input)', border: '1px solid var(--border)' }}>
                  <h4 style={{ margin: '0 0 10px 0', fontSize: '14px', fontWeight: 800, display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <History size={16} color="var(--primary)" />
                    <span>Application Verification Audit Trail ({selectedPartner.verificationHistory.length} events)</span>
                  </h4>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', maxHeight: '180px', overflowY: 'auto' }}>
                    {selectedPartner.verificationHistory.map((item: any, hIdx: number) => (
                      <div key={hIdx} style={{ 
                        display: 'flex', 
                        justifyContent: 'space-between', 
                        alignItems: 'center', 
                        padding: '8px 12px', 
                        borderRadius: '6px', 
                        backgroundColor: 'var(--bg-card)',
                        fontSize: '12px'
                      }}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                          <span style={{ 
                            fontWeight: 700, 
                            color: item.action?.includes('APPROV') || item.action?.includes('VERIF') ? '#22c55e' : (item.action?.includes('REJECT') ? '#ef4444' : '#f59e0b') 
                          }}>
                            {item.action}
                          </span>
                          {item.docKey && <span style={{ color: 'var(--text-muted)' }}>({item.docKey})</span>}
                          {item.reason && <span style={{ color: '#cbd5e1' }}>— "{item.reason}"</span>}
                          {item.notes && <span style={{ color: '#cbd5e1' }}>— "{item.notes}"</span>}
                        </div>
                        <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                          By {item.adminName || 'Admin'} • {item.timestamp ? new Date(item.timestamp).toLocaleString() : 'Recent'}
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Full-Screen Document Zoom Preview Modal */}
      {previewDoc && (
        <div className="modal-overlay" style={{ zIndex: 1000 }} onClick={() => setPreviewDoc(null)}>
          <div 
            className="modal-content" 
            style={{ maxWidth: '800px', backgroundColor: '#0f172a', padding: '16px' }}
            onClick={(e) => e.stopPropagation()}
          >
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '12px' }}>
              <h4 style={{ margin: 0, fontSize: '16px', fontWeight: 800 }}>{previewDoc.label}</h4>
              <div style={{ display: 'flex', gap: '8px' }}>
                <a 
                  href={previewDoc.url} 
                  target="_blank" 
                  rel="noopener noreferrer" 
                  className="btn btn-sm btn-primary"
                  style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}
                >
                  <ExternalLink size={12} />
                  <span>Open Full Screen</span>
                </a>
                <button 
                  className="btn btn-secondary btn-icon" 
                  onClick={() => setPreviewDoc(null)}
                  style={{ width: '30px', height: '30px' }}
                >
                  <X size={14} />
                </button>
              </div>
            </div>
            <div style={{ width: '100%', maxHeight: '70vh', overflow: 'auto', textAlign: 'center', backgroundColor: '#020617', borderRadius: '8px', padding: '10px' }}>
              {previewDoc.url.toLowerCase().includes('.pdf') ? (
                <div style={{ padding: '24px 16px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '14px' }}>
                  <FileText size={56} color="#38bdf8" />
                  <div style={{ fontSize: '15px', fontWeight: 700, color: '#f8fafc' }}>PDF Document: {previewDoc.label}</div>
                  <iframe 
                    src={previewDoc.url} 
                    title={previewDoc.label} 
                    style={{ width: '100%', height: '52vh', border: '1px solid #334155', borderRadius: '8px' }} 
                  />
                  <a 
                    href={previewDoc.url} 
                    target="_blank" 
                    rel="noopener noreferrer" 
                    download 
                    className="btn btn-primary btn-sm"
                    style={{ display: 'inline-flex', alignItems: 'center', gap: '6px' }}
                  >
                    <Download size={13} />
                    <span>Download PDF Document</span>
                  </a>
                </div>
              ) : (
                <img 
                  src={previewDoc.url} 
                  alt={previewDoc.label} 
                  style={{ maxWidth: '100%', maxHeight: '65vh', objectFit: 'contain' }} 
                />
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default Partners;
