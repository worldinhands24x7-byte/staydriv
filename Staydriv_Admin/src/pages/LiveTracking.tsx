import React, { useState, useEffect, useRef, useMemo } from 'react';
import { io, Socket } from 'socket.io-client';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { 
  Search, RefreshCw, Layers, Compass, Phone, Car, Navigation, 
  MapPin, CheckCircle2, AlertCircle, Clock, ShieldCheck, User,
  Radio, X, Eye, Maximize2, Zap, ArrowUpRight, Copy, Check,
  ExternalLink, UserCheck, Key, Shield, AlertTriangle
} from 'lucide-react';
import { useDatabase } from '../context/DatabaseContext';

export const LiveTracking: React.FC = () => {
  const { customers, partners, liveOperations, stats, isLive, refreshAllData, lastUpdatedTime } = useDatabase();

  const mapContainerRef = useRef<HTMLDivElement | null>(null);
  const mapInstanceRef = useRef<L.Map | null>(null);
  const pilotMarkersRef = useRef<Map<string, L.Marker>>(new Map());
  const customerMarkersRef = useRef<Map<string, L.Marker>>(new Map());
  const polylinesRef = useRef<Map<string, L.Polyline>>(new Map());
  const socketRef = useRef<Socket | null>(null);

  const [selectedEntity, setSelectedEntity] = useState<{ type: 'pilot' | 'customer'; data: any } | null>(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [filterType, setFilterType] = useState<'all' | 'online_pilots' | 'active_customers' | 'on_ride' | 'arriving' | 'offline'>('all');
  const [vehicleFilter, setVehicleFilter] = useState<string>('all');
  const [mapTileType, setMapTileType] = useState<'streets' | 'satellite' | 'dark'>('streets');
  const [isConnected, setIsConnected] = useState(false);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [copiedText, setCopiedText] = useState<string | null>(null);

  // Backend URL helper
  const getBackendUrl = () => {
    return (window as any).REACT_APP_BACKEND_URL || 
      ((window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1')
        ? `${window.location.protocol}//${window.location.hostname}:3000`
        : window.location.origin);
  };

  // Helper: Format relative timestamp
  const formatLastSeen = (timestampStr?: string) => {
    if (!timestampStr) return 'Location unavailable';
    const ts = new Date(timestampStr).getTime();
    if (isNaN(ts) || ts <= 0) return 'Location unavailable';
    const elapsedSec = Math.floor((Date.now() - ts) / 1000);
    if (elapsedSec < 10) return 'Just now (Real-time)';
    if (elapsedSec < 60) return `${elapsedSec}s ago`;
    const elapsedMin = Math.floor(elapsedSec / 60);
    if (elapsedMin < 60) return `${elapsedMin}m ago`;
    const elapsedHr = Math.floor(elapsedMin / 60);
    return `${elapsedHr}h ago`;
  };

  // Helper: Google Maps Driving Avatar Marker HTML for Pilots
  const createPilotAvatarHtml = (pilot: any, isSelected: boolean) => {
    const heading = Math.round(pilot.heading || 0);
    const speed = Math.round(pilot.speed || 0);
    const status = pilot.rideStatus || (pilot.online ? 'online' : 'offline');

    let statusColor = '#10b981'; // Available: Green
    let haloColor = 'rgba(16, 185, 129, 0.28)';

    if (status === 'on_ride') {
      statusColor = '#2563eb'; // On Ride: Blue
      haloColor = 'rgba(37, 99, 235, 0.32)';
    } else if (status === 'arriving') {
      statusColor = '#f59e0b'; // Arriving: Orange
      haloColor = 'rgba(245, 158, 11, 0.35)';
    } else if (status === 'offline' || !pilot.online) {
      statusColor = '#ef4444'; // Offline: Red
      haloColor = 'rgba(239, 68, 68, 0.15)';
    }

    let vehicleGlyph = '';
    const vType = (pilot.vehicleType || 'Bike').toLowerCase();
    if (vType.includes('bike') || vType.includes('moto')) {
      vehicleGlyph = `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="${statusColor}" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"><circle cx="5.5" cy="17.5" r="3.5"/><circle cx="18.5" cy="17.5" r="3.5"/><path d="M15 6a1 1 0 1 0 0-2 1 1 0 0 0 0 2zm-3 11.5L9 9l4.5-3 2 4.5h4"/></svg>`;
    } else if (vType.includes('auto') || vType.includes('rick')) {
      vehicleGlyph = `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="${statusColor}" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"><path d="M19 17h2c.6 0 1-.4 1-1v-3c0-.9-.7-1.7-1.5-1.9C18.7 10.6 16 10 16 10s-1.3-1.4-2.2-2.3c-.5-.4-1.1-.7-1.8-.7H5c-.6 0-1.1.4-1.4.9l-1.4 2.9A3.7 3.7 0 0 0 2 12v4c0 .6.4 1 1 1h2"/><circle cx="7" cy="17" r="2"/><path d="M9 17h6"/><circle cx="17" cy="17" r="2"/></svg>`;
    } else if (vType.includes('heavy')) {
      vehicleGlyph = `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#ea580c" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"><path d="M14 18V6a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2v11a1 1 0 0 0 1 1h2"/><path d="M15 18h2a1 1 0 0 0 1-1v-4.5a2 2 0 0 0-.58-1.42L15 8.5"/><circle cx="7.5" cy="18.5" r="2.5"/><circle cx="17.5" cy="18.5" r="2.5"/></svg>`;
    } else if (vType.includes('truck') || vType.includes('goods') || vType.includes('pickup')) {
      vehicleGlyph = `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#0284c7" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"><path d="M14 18V6a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2v11a1 1 0 0 0 1 1h2"/><path d="M15 18h2a1 1 0 0 0 1-1v-4.5a2 2 0 0 0-.58-1.42L15 8.5"/><circle cx="7.5" cy="18.5" r="2.5"/><circle cx="17.5" cy="18.5" r="2.5"/></svg>`;
    } else {
      vehicleGlyph = `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="${statusColor}" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"><path d="M19 17h2c.6 0 1-.4 1-1v-3c0-.9-.7-1.7-1.5-1.9C18.7 10.6 16 10 16 10s-1.3-1.4-2.2-2.3c-.5-.4-1.1-.7-1.8-.7H5c-.6 0-1.1.4-1.4.9l-1.4 2.9A3.7 3.7 0 0 0 2 12v4c0 .6.4 1 1 1h2"/><circle cx="7" cy="17" r="2"/><path d="M9 17h6"/><circle cx="17" cy="17" r="2"/></svg>`;
    }

    const shortName = pilot.name ? pilot.name.split(' ')[0] : 'Pilot';
    const tagBorder = isSelected ? 'border: 2px solid #3b82f6; box-shadow: 0 0 10px rgba(59,130,246,0.8);' : 'border: 1px solid rgba(255,255,255,0.25);';

    return `
      <div class="gm-driver-avatar" style="${isSelected ? 'transform: scale(1.18); z-index: 1000;' : ''}">
        <div class="gm-driver-tag" style="${tagBorder}">
          <span style="color: ${statusColor}; margin-right: 4px;">●</span>${shortName} • ${pilot.vehiclePlate || pilot.vehicleNumber || pilot.vehicleType}
        </div>
        <div class="gm-puck-halo ${pilot.online ? 'transmitting' : ''}" style="background: ${haloColor};"></div>
        <div class="gm-puck-disc" style="border-color: ${statusColor};">
          <div class="gm-heading-arrow" style="transform: rotate(${heading}deg);">
            ${vehicleGlyph}
          </div>
        </div>
        ${speed > 0 ? `<div class="gm-speed-tag">${speed} km/h</div>` : ''}
      </div>
    `;
  };

  // Helper: Customer Marker HTML
  const createCustomerMarkerHtml = (customer: any, isSelected: boolean) => {
    const shortName = customer.name ? customer.name.split(' ')[0] : 'Customer';
    const hasActiveBooking = customer.bookingStatus && customer.bookingStatus !== 'none';
    const statusColor = hasActiveBooking ? '#3b82f6' : '#8b5cf6';
    const tagBorder = isSelected ? 'border: 2px solid #ec4899; box-shadow: 0 0 10px rgba(236,72,153,0.8);' : 'border: 1px solid rgba(255,255,255,0.25);';

    return `
      <div class="gm-customer-avatar" style="${isSelected ? 'transform: scale(1.18); z-index: 1000;' : ''}">
        <div class="gm-driver-tag" style="${tagBorder} background: #1e1b4b;">
          <span style="color: ${statusColor}; margin-right: 4px;">👤</span>${shortName} ${hasActiveBooking ? `• Ride Active` : ''}
        </div>
        <div class="gm-puck-halo transmitting" style="background: rgba(59, 130, 246, 0.25);"></div>
        <div class="gm-puck-disc" style="border-color: ${statusColor}; background: #ffffff;">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="${statusColor}" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round">
            <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/>
            <circle cx="12" cy="7" r="4"/>
          </svg>
        </div>
      </div>
    `;
  };

  // 1. Initialize Leaflet Map
  useEffect(() => {
    if (!mapContainerRef.current || mapInstanceRef.current) return;

    const map = L.map(mapContainerRef.current, {
      center: [17.4483, 78.3746], // Hyderabad Central
      zoom: 12,
      zoomControl: false,
      attributionControl: false
    });

    const streetLayer = L.tileLayer('https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}', {
      maxZoom: 20,
      subdomains: ['mt0', 'mt1', 'mt2', 'mt3']
    });

    streetLayer.addTo(map);
    mapInstanceRef.current = map;
    L.control.zoom({ position: 'topright' }).addTo(map);

    return () => {
      map.remove();
      mapInstanceRef.current = null;
    };
  }, []);

  // Switch Tile Layer
  useEffect(() => {
    if (!mapInstanceRef.current) return;
    const map = mapInstanceRef.current;

    map.eachLayer(layer => {
      if (layer instanceof L.TileLayer) {
        map.removeLayer(layer);
      }
    });

    let newUrl = 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}';
    if (mapTileType === 'satellite') {
      newUrl = 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}';
    } else if (mapTileType === 'dark') {
      newUrl = 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
    }

    L.tileLayer(newUrl, { maxZoom: 20 }).addTo(map);
  }, [mapTileType]);

  // Connect to Socket.IO for live connection status
  useEffect(() => {
    const backendUrl = getBackendUrl();
    const token = localStorage.getItem('staydriv_admin_token') || 'staydriv_admin_secret_2026';

    const socket = io(backendUrl, {
      transports: ['websocket', 'polling'],
      reconnectionAttempts: 15,
      reconnectionDelay: 1000
    });
    socketRef.current = socket;

    socket.on('connect', () => {
      setIsConnected(true);
      socket.emit('admin_join_tracking', {
        adminKey: 'staydriv_admin_secret_2026',
        token,
        role: 'super_admin'
      });
    });

    socket.on('admin_tracking_joined', () => {
      setIsConnected(true);
    });

    socket.on('reconnect', () => {
      setIsConnected(true);
      socket.emit('admin_join_tracking', {
        adminKey: 'staydriv_admin_secret_2026',
        token,
        role: 'super_admin'
      });
      refreshAllData();
    });

    socket.on('disconnect', () => {
      setIsConnected(false);
    });

    return () => {
      socket.disconnect();
    };
  }, []);

  // 2. Synchronize Leaflet Markers (Pilots & Customers) & Route Polylines
  useEffect(() => {
    if (!mapInstanceRef.current) return;
    const map = mapInstanceRef.current;
    const pilotMarkers = pilotMarkersRef.current;
    const customerMarkers = customerMarkersRef.current;
    const polylines = polylinesRef.current;

    // Filter valid pilots with real GPS coordinates
    const validPilots = partners.filter(p => {
      const lat = p.lat !== undefined && p.lat !== null ? Number(p.lat) : Number((p as any).latitude);
      const lng = p.lng !== undefined && p.lng !== null ? Number(p.lng) : Number((p as any).longitude);
      return !isNaN(lat) && !isNaN(lng) && lat !== 0 && lng !== 0;
    });
    const activePilotUids = new Set(validPilots.map(p => p.uid));

    // Remove obsolete pilot markers
    pilotMarkers.forEach((marker, uid) => {
      if (!activePilotUids.has(uid)) {
        map.removeLayer(marker);
        pilotMarkers.delete(uid);
      }
    });

    // Update or add pilot markers
    validPilots.forEach(pilot => {
      const lat = pilot.lat !== undefined && pilot.lat !== null ? Number(pilot.lat) : Number((pilot as any).latitude);
      const lng = pilot.lng !== undefined && pilot.lng !== null ? Number(pilot.lng) : Number((pilot as any).longitude);
      const isSelected = selectedEntity?.type === 'pilot' && selectedEntity.data.uid === pilot.uid;
      const htmlContent = createPilotAvatarHtml(pilot, isSelected);

      const icon = L.divIcon({
        className: 'gm-avatar-container smooth-move',
        html: htmlContent,
        iconSize: [54, 54],
        iconAnchor: [27, 27]
      });

      if (pilotMarkers.has(pilot.uid)) {
        const existingMarker = pilotMarkers.get(pilot.uid)!;
        existingMarker.setLatLng([lat, lng]);
        existingMarker.setIcon(icon);
        existingMarker.setZIndexOffset(isSelected ? 1000 : (pilot.online ? 500 : 100));
      } else {
        const newMarker = L.marker([lat, lng], { icon, zIndexOffset: isSelected ? 1000 : 500 });
        newMarker.on('click', () => {
          setSelectedEntity({ type: 'pilot', data: pilot });
          map.panTo([lat, lng], { animate: true, duration: 0.6 });
        });
        newMarker.addTo(map);
        pilotMarkers.set(pilot.uid, newMarker);
      }
    });

    // Filter active customers with real coordinates
    const validCustomers = customers.filter(c => {
      const lat = c.lat !== undefined && c.lat !== null ? Number(c.lat) : Number((c as any).latitude);
      const lng = c.lng !== undefined && c.lng !== null ? Number(c.lng) : Number((c as any).longitude);
      return !isNaN(lat) && !isNaN(lng) && lat !== 0 && lng !== 0;
    });
    const activeCustUids = new Set(validCustomers.map(c => c.uid));

    // Remove obsolete customer markers
    customerMarkers.forEach((marker, uid) => {
      if (!activeCustUids.has(uid)) {
        map.removeLayer(marker);
        customerMarkers.delete(uid);
      }
    });

    // Update or add customer markers
    validCustomers.forEach(customer => {
      const lat = customer.lat !== undefined && customer.lat !== null ? Number(customer.lat) : Number((customer as any).latitude);
      const lng = customer.lng !== undefined && customer.lng !== null ? Number(customer.lng) : Number((customer as any).longitude);
      const isSelected = selectedEntity?.type === 'customer' && selectedEntity.data.uid === customer.uid;
      const htmlContent = createCustomerMarkerHtml(customer, isSelected);

      const icon = L.divIcon({
        className: 'gm-avatar-container smooth-move',
        html: htmlContent,
        iconSize: [54, 54],
        iconAnchor: [27, 27]
      });

      if (customerMarkers.has(customer.uid)) {
        const existingMarker = customerMarkers.get(customer.uid)!;
        existingMarker.setLatLng([lat, lng]);
        existingMarker.setIcon(icon);
        existingMarker.setZIndexOffset(isSelected ? 1000 : 400);
      } else {
        const newMarker = L.marker([lat, lng], { icon, zIndexOffset: isSelected ? 1000 : 400 });
        newMarker.on('click', () => {
          setSelectedEntity({ type: 'customer', data: customer });
          map.panTo([lat, lng], { animate: true, duration: 0.6 });
        });
        newMarker.addTo(map);
        customerMarkers.set(customer.uid, newMarker);
      }
    });

    // Draw active ride route polylines between customer and assigned pilot
    const activeRelationships = liveOperations?.relationships || [];
    const activeRelIds = new Set(activeRelationships.map(r => r.bookingId));

    // Remove obsolete polylines
    polylines.forEach((poly, id) => {
      if (!activeRelIds.has(id)) {
        map.removeLayer(poly);
        polylines.delete(id);
      }
    });

    // Draw lines
    activeRelationships.forEach(rel => {
      if (rel.customer?.lat && rel.customer?.lng && rel.pilot?.lat && rel.pilot?.lng) {
        const latLngs: L.LatLngExpression[] = [
          [rel.pilot.lat, rel.pilot.lng],
          [rel.customer.lat, rel.customer.lng]
        ];

        if (polylines.has(rel.bookingId)) {
          polylines.get(rel.bookingId)!.setLatLngs(latLngs);
        } else {
          const poly = L.polyline(latLngs, {
            color: '#3b82f6',
            weight: 3.5,
            dashArray: '6, 8',
            opacity: 0.85
          }).addTo(map);
          polylines.set(rel.bookingId, poly);
        }
      }
    });
  }, [partners, customers, liveOperations, selectedEntity]);

  // Center on Hyderabad
  const handleRecenter = () => {
    if (mapInstanceRef.current) {
      mapInstanceRef.current.setView([17.4483, 78.3746], 12, { animate: true });
    }
  };

  // Auto-fit all active markers
  const handleFitBounds = () => {
    if (!mapInstanceRef.current) return;
    const allCoords: L.LatLngExpression[] = [];

    partners.forEach(p => {
      if (p.lat && p.lng && !isNaN(p.lat) && !isNaN(p.lng) && p.lat !== 0) {
        allCoords.push([p.lat, p.lng]);
      }
    });
    customers.forEach(c => {
      if (c.lat && c.lng && !isNaN(c.lat) && !isNaN(c.lng) && c.lat !== 0) {
        allCoords.push([c.lat, c.lng]);
      }
    });

    if (allCoords.length > 0) {
      const bounds = L.latLngBounds(allCoords);
      mapInstanceRef.current.fitBounds(bounds, { padding: [50, 50], maxZoom: 15, animate: true });
    }
  };

  const handleManualRefresh = async () => {
    setIsRefreshing(true);
    await refreshAllData();
    setIsRefreshing(false);
  };

  const copyToClipboard = (text: string, label: string) => {
    navigator.clipboard.writeText(text);
    setCopiedText(label);
    setTimeout(() => setCopiedText(null), 2000);
  };

  // Filtered lists for sidebar
  const filteredPilots = useMemo(() => {
    return partners.filter(p => {
      const term = searchTerm.toLowerCase().trim();
      const matchesSearch = !term ||
        p.name.toLowerCase().includes(term) ||
        p.phone.includes(term) ||
        (p.vehiclePlate && p.vehiclePlate.toLowerCase().includes(term)) ||
        (p.vehicleNumber && p.vehicleNumber.toLowerCase().includes(term));

      if (!matchesSearch) return false;

      if (filterType === 'online_pilots' && !p.online) return false;
      if (filterType === 'on_ride' && p.rideStatus !== 'on_ride') return false;
      if (filterType === 'arriving' && p.rideStatus !== 'arriving') return false;
      if (filterType === 'offline' && p.online) return false;

      if (vehicleFilter !== 'all') {
        const pvt = (p.vehicleType || '').toLowerCase();
        const vf = vehicleFilter.toLowerCase();
        let matches = pvt === vf;
        if (vf === 'bike' && (pvt.includes('bike') || pvt.includes('scoot'))) matches = true;
        else if (vf === 'auto' && pvt.includes('auto')) matches = true;
        else if (vf === 'car' && pvt.includes('car')) matches = true;
        else if (vf === 'mini_truck' && (pvt.includes('mini truck') || pvt.includes('pickup') || pvt.includes('ace') || pvt.includes('dost'))) matches = true;
        else if (vf === 'heavy_truck' && (pvt.includes('heavy truck') || pvt.includes('ton'))) matches = true;
        else if (vf === 'truck' && pvt.includes('truck')) matches = true;
        if (!matches) return false;
      }

      return true;
    });
  }, [partners, searchTerm, filterType, vehicleFilter]);

  const filteredCustomers = useMemo(() => {
    return customers.filter(c => {
      const term = searchTerm.toLowerCase().trim();
      const matchesSearch = !term ||
        c.name.toLowerCase().includes(term) ||
        c.phone.includes(term) ||
        (c.activeBookingId && c.activeBookingId.toLowerCase().includes(term));

      if (!matchesSearch) return false;
      if (filterType === 'active_customers' && (!c.bookingStatus || c.bookingStatus === 'none')) return false;

      return true;
    });
  }, [customers, searchTerm, filterType]);

  // Find linked relationship for selected entity
  const selectedRelationship = useMemo(() => {
    if (!selectedEntity || !liveOperations?.relationships) return null;
    const rels = liveOperations.relationships;
    if (selectedEntity.type === 'pilot') {
      return rels.find(r => r.pilot?.id === selectedEntity.data.uid) || null;
    } else {
      return rels.find(r => r.customer?.id === selectedEntity.data.uid || r.bookingId === selectedEntity.data.activeBookingId) || null;
    }
  }, [selectedEntity, liveOperations]);

  return (
    <div className="page-container" style={{ paddingBottom: '16px' }}>
      {/* 1. Header & Live Metrics Bar */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: '16px', marginBottom: '16px' }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
            <h2 style={{ margin: 0, fontSize: '24px', fontWeight: 800 }}>Live Operations & Location Map</h2>
            <div 
              style={{ 
                display: 'flex', 
                alignItems: 'center', 
                gap: '8px', 
                padding: '4px 12px', 
                borderRadius: '20px', 
                backgroundColor: (isConnected || isLive) ? 'rgba(16, 185, 129, 0.12)' : 'rgba(239, 68, 68, 0.12)',
                border: `1px solid ${(isConnected || isLive) ? 'rgba(16, 185, 129, 0.35)' : 'rgba(239, 68, 68, 0.35)'}`
              }}
            >
              <div 
                className={(isConnected || isLive) ? 'live-pulse-dot' : ''}
                style={{ 
                  width: '8px', 
                  height: '8px', 
                  borderRadius: '50%', 
                  backgroundColor: (isConnected || isLive) ? '#10b981' : '#ef4444' 
                }} 
              />
              <span style={{ fontSize: '12px', fontWeight: 700, color: (isConnected || isLive) ? '#10b981' : '#ef4444' }}>
                {(isConnected || isLive) ? 'Real-Time WebSocket Stream Live' : 'Connecting to Stream...'}
              </span>
            </div>
          </div>
          <p style={{ color: 'var(--text-muted)', fontSize: '13.5px', marginTop: '4px' }}>
            Authoritative, real-time GPS telemetry of all active StayDriv customers & pilot fleet. Last updated: {lastUpdatedTime}
          </p>
        </div>

        {/* Live Counters Strip */}
        <div style={{ display: 'flex', gap: '10px', flexWrap: 'wrap' }}>
          <div className="card" style={{ padding: '8px 16px', display: 'flex', alignItems: 'center', gap: '10px', minWidth: '130px' }}>
            <div style={{ width: '36px', height: '36px', borderRadius: '10px', backgroundColor: 'rgba(16, 185, 129, 0.12)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <Radio size={18} color="#10b981" />
            </div>
            <div>
              <div style={{ fontSize: '11px', color: 'var(--text-muted)', fontWeight: 600 }}>ONLINE PILOTS</div>
              <div style={{ fontSize: '18px', fontWeight: 800, color: '#10b981' }}>
                {partners.filter(p => p.online).length || stats.onlinePilots}
              </div>
            </div>
          </div>

          <div className="card" style={{ padding: '8px 16px', display: 'flex', alignItems: 'center', gap: '10px', minWidth: '130px' }}>
            <div style={{ width: '36px', height: '36px', borderRadius: '10px', backgroundColor: 'rgba(37, 99, 235, 0.12)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <Navigation size={18} color="#2563eb" />
            </div>
            <div>
              <div style={{ fontSize: '11px', color: 'var(--text-muted)', fontWeight: 600 }}>ACTIVE RIDES</div>
              <div style={{ fontSize: '18px', fontWeight: 800, color: '#2563eb' }}>
                {partners.filter(p => p.rideStatus === 'on_ride' || p.rideStatus === 'arriving' || p.currentBookingId).length || stats.activeRides}
              </div>
            </div>
          </div>

          <div className="card" style={{ padding: '8px 16px', display: 'flex', alignItems: 'center', gap: '10px', minWidth: '130px' }}>
            <div style={{ width: '36px', height: '36px', borderRadius: '10px', backgroundColor: 'rgba(139, 92, 246, 0.12)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <User size={18} color="#8b5cf6" />
            </div>
            <div>
              <div style={{ fontSize: '11px', color: 'var(--text-muted)', fontWeight: 600 }}>ACTIVE CLIENTS</div>
              <div style={{ fontSize: '18px', fontWeight: 800, color: '#8b5cf6' }}>
                {customers.filter(c => (c.bookingStatus && c.bookingStatus !== 'none') || (!c.isLocationStale && c.hasLocation)).length || stats.activeCustomers}
              </div>
            </div>
          </div>

          <button 
            className="btn btn-secondary"
            onClick={handleManualRefresh}
            disabled={isRefreshing}
            style={{ height: '52px', padding: '0 16px' }}
          >
            <RefreshCw size={16} className={isRefreshing ? 'spin-anim' : ''} />
            <span>Sync</span>
          </button>
        </div>
      </div>

      {/* 2. Map & Operations Dual-Pane Container */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 380px', gap: '16px', height: 'calc(100vh - 240px)', minHeight: '600px' }}>
        {/* Left Map Column */}
        <div style={{ position: 'relative', borderRadius: '16px', overflow: 'hidden', border: '1px solid var(--border)', boxShadow: '0 8px 30px rgba(0,0,0,0.12)' }}>
          {/* Leaflet Map Div */}
          <div ref={mapContainerRef} style={{ width: '100%', height: '100%', zIndex: 1 }} />

          {/* Floating Map Controls at Top Left */}
          <div style={{ position: 'absolute', top: '16px', left: '16px', zIndex: 500, display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
            {/* Tile Layer Selector */}
            <div className="card" style={{ padding: '4px', display: 'flex', gap: '4px', backgroundColor: 'rgba(15, 23, 42, 0.85)', backdropFilter: 'blur(10px)', border: '1px solid rgba(255,255,255,0.15)' }}>
              <button 
                className={`btn btn-sm ${mapTileType === 'streets' ? 'btn-primary' : 'btn-secondary'}`}
                onClick={() => setMapTileType('streets')}
                style={{ padding: '6px 12px', fontSize: '12px' }}
              >
                Streets
              </button>
              <button 
                className={`btn btn-sm ${mapTileType === 'satellite' ? 'btn-primary' : 'btn-secondary'}`}
                onClick={() => setMapTileType('satellite')}
                style={{ padding: '6px 12px', fontSize: '12px' }}
              >
                Satellite
              </button>
              <button 
                className={`btn btn-sm ${mapTileType === 'dark' ? 'btn-primary' : 'btn-secondary'}`}
                onClick={() => setMapTileType('dark')}
                style={{ padding: '6px 12px', fontSize: '12px' }}
              >
                Dark
              </button>
            </div>

            {/* Recenter & Fit Bounds */}
            <button 
              className="btn btn-secondary btn-sm"
              onClick={handleRecenter}
              style={{ backgroundColor: 'rgba(15, 23, 42, 0.85)', backdropFilter: 'blur(10px)', border: '1px solid rgba(255,255,255,0.15)', color: '#fff' }}
              title="Recenter to Central Hyderabad"
            >
              <Compass size={14} />
              <span>Hyderabad</span>
            </button>
            <button 
              className="btn btn-secondary btn-sm"
              onClick={handleFitBounds}
              style={{ backgroundColor: 'rgba(15, 23, 42, 0.85)', backdropFilter: 'blur(10px)', border: '1px solid rgba(255,255,255,0.15)', color: '#fff' }}
              title="Fit map to encompass all live riders"
            >
              <Maximize2 size={14} />
              <span>Fit All</span>
            </button>
          </div>

          {/* Floating Legend at Bottom Left */}
          <div 
            style={{ 
              position: 'absolute', 
              bottom: '16px', 
              left: '16px', 
              zIndex: 500, 
              padding: '10px 16px', 
              borderRadius: '12px', 
              backgroundColor: 'rgba(15, 23, 42, 0.85)', 
              backdropFilter: 'blur(10px)',
              border: '1px solid rgba(255,255,255,0.15)',
              display: 'flex', 
              gap: '14px', 
              fontSize: '12px',
              fontWeight: 600,
              color: '#fff'
            }}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
              <span style={{ width: '10px', height: '10px', borderRadius: '50%', backgroundColor: '#10b981', display: 'inline-block' }}></span>
              <span>Available Pilot</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
              <span style={{ width: '10px', height: '10px', borderRadius: '50%', backgroundColor: '#2563eb', display: 'inline-block' }}></span>
              <span>On Ride</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
              <span style={{ width: '10px', height: '10px', borderRadius: '50%', backgroundColor: '#f59e0b', display: 'inline-block' }}></span>
              <span>Arriving</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
              <span style={{ width: '10px', height: '10px', borderRadius: '50%', backgroundColor: '#8b5cf6', display: 'inline-block' }}></span>
              <span>Customer</span>
            </div>
          </div>
        </div>

        {/* Right Operations Sidebar */}
        <div className="card" style={{ display: 'flex', flexDirection: 'column', overflow: 'hidden', padding: 0 }}>
          {/* Sidebar Tabs & Filter Pills */}
          <div style={{ padding: '16px', borderBottom: '1px solid var(--border)', display: 'flex', flexDirection: 'column', gap: '12px' }}>
            <div className="input-icon-wrapper" style={{ width: '100%' }}>
              <Search size={16} />
              <input 
                type="text" 
                placeholder="Search pilot, customer, mobile, vehicle plate..." 
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
              />
            </div>

            {/* Filter Pills */}
            <div style={{ display: 'flex', gap: '6px', overflowX: 'auto', paddingBottom: '4px' }}>
              {[
                { id: 'all', label: 'All Fleet' },
                { id: 'online_pilots', label: 'Online' },
                { id: 'active_customers', label: 'Customers' },
                { id: 'on_ride', label: 'On Ride' },
                { id: 'arriving', label: 'Arriving' },
                { id: 'offline', label: 'Offline' }
              ].map(f => (
                <button
                  key={f.id}
                  className={`btn btn-sm ${filterType === f.id ? 'btn-primary' : 'btn-secondary'}`}
                  onClick={() => setFilterType(f.id as any)}
                  style={{ padding: '4px 10px', fontSize: '11px', whiteSpace: 'nowrap' }}
                >
                  {f.label}
                </button>
              ))}
            </div>

            {/* Vehicle Category Filter Pills */}
            <div style={{ display: 'flex', gap: '6px', overflowX: 'auto', paddingBottom: '2px' }}>
              {[
                { id: 'all', label: 'All Vehicles' },
                { id: 'bike', label: 'Bike' },
                { id: 'auto', label: 'Auto' },
                { id: 'car', label: 'Cab' },
                { id: 'mini_truck', label: 'Mini Truck' },
                { id: 'heavy_truck', label: 'Heavy Truck' },
              ].map(v => (
                <button
                  key={v.id}
                  className={`btn btn-sm ${vehicleFilter === v.id ? 'btn-primary' : 'btn-secondary'}`}
                  onClick={() => setVehicleFilter(v.id)}
                  style={{ padding: '2px 8px', fontSize: '10px', whiteSpace: 'nowrap', borderRadius: '12px' }}
                >
                  {v.label}
                </button>
              ))}
            </div>
          </div>

          {/* List of Pilots / Customers */}
          <div style={{ flex: 1, overflowY: 'auto', padding: '12px' }}>
            {/* Show Selected Details Drawer if an item is selected */}
            {selectedEntity ? (
              <div style={{ display: 'flex', flexDirection: 'column', gap: '14px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid var(--border)', paddingBottom: '10px' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <span style={{ fontSize: '14px', fontWeight: 800 }}>
                      {selectedEntity.type === 'pilot' ? '🚁 Pilot Partner Details' : '👤 Customer Client Details'}
                    </span>
                  </div>
                  <button 
                    className="btn btn-secondary btn-icon"
                    onClick={() => setSelectedEntity(null)}
                    style={{ width: '28px', height: '28px', minWidth: '28px' }}
                  >
                    <X size={14} />
                  </button>
                </div>

                {/* PILOT DETAILS PANEL */}
                {selectedEntity.type === 'pilot' && (() => {
                  const pilot = selectedEntity.data;
                  return (
                    <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '12px', padding: '12px', borderRadius: '12px', backgroundColor: 'var(--bg-input)' }}>
                        <div style={{ width: '48px', height: '48px', borderRadius: '50%', backgroundColor: '#10b981', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontWeight: 800, fontSize: '18px' }}>
                          {pilot.name?.charAt(0) || 'P'}
                        </div>
                        <div style={{ flex: 1 }}>
                          <div style={{ fontWeight: 800, fontSize: '16px' }}>{pilot.name}</div>
                          <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>UID: {pilot.uid}</div>
                          <div style={{ display: 'flex', alignItems: 'center', gap: '6px', marginTop: '4px' }}>
                            <span className={`badge ${pilot.online ? 'badge-active' : 'badge-suspended'}`}>
                              {pilot.online ? 'Online' : 'Offline'}
                            </span>
                            <span className="badge badge-pending">
                              {pilot.rideStatus || 'Available'}
                            </span>
                          </div>
                          <div style={{ display: 'flex', alignItems: 'center', gap: '6px', marginTop: '6px' }}>
                            <span style={{
                              padding: '2px 6px',
                              borderRadius: '4px',
                              fontSize: '10px',
                              fontWeight: 700,
                              backgroundColor: pilot.rideServiceEnabled !== false ? '#eff6ff' : '#f1f5f9',
                              color: pilot.rideServiceEnabled !== false ? '#2563eb' : '#94a3b8',
                              border: `1px solid ${pilot.rideServiceEnabled !== false ? '#bfdbfe' : '#e2e8f0'}`
                            }}>
                              🚕 Rides: {pilot.rideServiceEnabled !== false ? 'ON' : 'PAUSED'}
                            </span>
                            <span style={{
                              padding: '2px 6px',
                              borderRadius: '4px',
                              fontSize: '10px',
                              fontWeight: 700,
                              backgroundColor: pilot.foodServiceEnabled !== false ? '#ecfdf5' : '#f1f5f9',
                              color: pilot.foodServiceEnabled !== false ? '#059669' : '#94a3b8',
                              border: `1px solid ${pilot.foodServiceEnabled !== false ? '#a7f3d0' : '#e2e8f0'}`
                            }}>
                              🍔 Food: {pilot.foodServiceEnabled !== false ? 'ON' : 'PAUSED'}
                            </span>
                          </div>
                        </div>
                      </div>

                      {/* Primary Contact & Vehicle Grid */}
                      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '10px' }}>
                        <div style={{ padding: '10px', borderRadius: '10px', backgroundColor: 'var(--bg-input)' }}>
                          <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Driver Mobile</span>
                          <div style={{ fontWeight: 700, fontSize: '13px', display: 'flex', alignItems: 'center', gap: '6px' }}>
                            <Phone size={12} />
                            <span>+91 {pilot.phone}</span>
                            <button onClick={() => copyToClipboard(pilot.phone, 'phone')} style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--primary)' }}>
                              {copiedText === 'phone' ? <Check size={12} /> : <Copy size={12} />}
                            </button>
                          </div>
                        </div>

                        <div style={{ padding: '10px', borderRadius: '10px', backgroundColor: 'var(--bg-input)' }}>
                          <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Vehicle Plate</span>
                          <div style={{ fontWeight: 700, fontSize: '13px' }}>{pilot.vehiclePlate || pilot.vehicleNumber}</div>
                        </div>

                        <div style={{ padding: '10px', borderRadius: '10px', backgroundColor: 'var(--bg-input)' }}>
                          <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Vehicle Owner</span>
                          <div style={{ fontWeight: 700, fontSize: '13px' }}>{pilot.ownerName || pilot.name}</div>
                        </div>

                        <div style={{ padding: '10px', borderRadius: '10px', backgroundColor: 'var(--bg-input)' }}>
                          <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Owner Mobile</span>
                          <div style={{ fontWeight: 700, fontSize: '13px' }}>+91 {pilot.ownerPhone || pilot.phone}</div>
                        </div>

                        <div style={{ padding: '10px', borderRadius: '10px', backgroundColor: 'var(--bg-input)' }}>
                          <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Vehicle Type & Model</span>
                          <div style={{ fontWeight: 700, fontSize: '13px' }}>{pilot.vehicleType} • {pilot.vehicleModel || 'Standard'}</div>
                        </div>

                        <div style={{ padding: '10px', borderRadius: '10px', backgroundColor: 'var(--bg-input)' }}>
                          <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Speed / Heading</span>
                          <div style={{ fontWeight: 700, fontSize: '13px' }}>{pilot.speed || 0} km/h • {pilot.heading || 0}°</div>
                        </div>
                      </div>

                      {/* GPS & Location Status */}
                      <div style={{ padding: '12px', borderRadius: '10px', backgroundColor: pilot.isLocationStale ? 'rgba(239,68,68,0.08)' : 'rgba(16,185,129,0.08)', border: `1px solid ${pilot.isLocationStale ? 'rgba(239,68,68,0.25)' : 'rgba(16,185,129,0.25)'}` }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                          <span style={{ fontSize: '12px', fontWeight: 700, color: pilot.isLocationStale ? '#ef4444' : '#10b981' }}>
                            {pilot.hasLocation ? (pilot.isLocationStale ? '⚠️ Stale Location (>2m)' : '🟢 Active Real-Time GPS') : '❌ Location Unavailable'}
                          </span>
                          <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                            {formatLastSeen(pilot.lastLocationUpdate)}
                          </span>
                        </div>
                        {pilot.lat && pilot.lng ? (
                          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '6px' }}>
                            <span style={{ fontSize: '12px', fontFamily: 'monospace' }}>
                              {Number(pilot.lat).toFixed(5)}, {Number(pilot.lng).toFixed(5)}
                            </span>
                            <a 
                              href={pilot.googleMapsUrl || `https://www.google.com/maps?q=${pilot.lat},${pilot.lng}`} 
                              target="_blank" 
                              rel="noopener noreferrer"
                              className="btn btn-sm btn-secondary"
                              style={{ padding: '3px 8px', fontSize: '11px' }}
                            >
                              <ExternalLink size={12} />
                              <span>Google Maps</span>
                            </a>
                          </div>
                        ) : null}
                      </div>

                      {/* Customer <-> Pilot Relationship Pipeline */}
                      {selectedRelationship ? (
                        <div style={{ padding: '12px', borderRadius: '12px', backgroundColor: 'var(--bg-input)', border: '1px solid var(--primary)' }}>
                          <div style={{ fontSize: '12px', fontWeight: 800, color: 'var(--primary)', marginBottom: '8px' }}>
                            🔗 Active Relationship Pipeline
                          </div>
                          <div style={{ fontSize: '12px', display: 'flex', flexDirection: 'column', gap: '6px' }}>
                            <div><strong>Booking ID:</strong> {selectedRelationship.bookingId}</div>
                            <div><strong>Passenger:</strong> {selectedRelationship.customer?.name} (+91 {selectedRelationship.customer?.phone})</div>
                            <div><strong>Pickup:</strong> {selectedRelationship.pickup}</div>
                            <div><strong>Destination:</strong> {selectedRelationship.drop}</div>
                            <div><strong>Ride Status:</strong> <span className="badge badge-active">{selectedRelationship.status}</span></div>
                          </div>
                        </div>
                      ) : (
                        <div style={{ fontSize: '12px', color: 'var(--text-muted)', fontStyle: 'italic', textAlign: 'center', padding: '8px' }}>
                          Pilot is currently not assigned to any active ride booking.
                        </div>
                      )}
                    </div>
                  );
                })()}

                {/* CUSTOMER DETAILS PANEL */}
                {selectedEntity.type === 'customer' && (() => {
                  const cust = selectedEntity.data;
                  return (
                    <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '12px', padding: '12px', borderRadius: '12px', backgroundColor: 'var(--bg-input)' }}>
                        <div style={{ width: '48px', height: '48px', borderRadius: '50%', backgroundColor: '#8b5cf6', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontWeight: 800, fontSize: '18px' }}>
                          {cust.name?.charAt(0) || 'C'}
                        </div>
                        <div style={{ flex: 1 }}>
                          <div style={{ fontWeight: 800, fontSize: '16px' }}>{cust.name}</div>
                          <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>UID: {cust.uid || cust.customerId}</div>
                          <div style={{ display: 'flex', alignItems: 'center', gap: '6px', marginTop: '4px' }}>
                            <span className={`badge ${cust.bookingStatus && cust.bookingStatus !== 'none' ? 'badge-active' : 'badge-pending'}`}>
                              {cust.bookingStatus && cust.bookingStatus !== 'none' ? `Ride: ${cust.bookingStatus}` : 'Idle (No Ride)'}
                            </span>
                          </div>
                        </div>
                      </div>

                      {/* Primary Contact Details */}
                      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '10px' }}>
                        <div style={{ padding: '10px', borderRadius: '10px', backgroundColor: 'var(--bg-input)' }}>
                          <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Customer Mobile</span>
                          <div style={{ fontWeight: 700, fontSize: '13px', display: 'flex', alignItems: 'center', gap: '6px' }}>
                            <Phone size={12} />
                            <span>+91 {cust.phone}</span>
                            <button onClick={() => copyToClipboard(cust.phone, 'cust_phone')} style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--primary)' }}>
                              {copiedText === 'cust_phone' ? <Check size={12} /> : <Copy size={12} />}
                            </button>
                          </div>
                        </div>

                        <div style={{ padding: '10px', borderRadius: '10px', backgroundColor: 'var(--bg-input)' }}>
                          <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Wallet Balance</span>
                          <div style={{ fontWeight: 700, fontSize: '13px' }}>₹{(cust.walletBalance || 0).toFixed(2)}</div>
                        </div>
                      </div>

                      {/* Route Details */}
                      {cust.currentPickup || cust.currentDestination ? (
                        <div style={{ padding: '10px', borderRadius: '10px', backgroundColor: 'var(--bg-input)', display: 'flex', flexDirection: 'column', gap: '6px' }}>
                          <div>
                            <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Pickup Location</span>
                            <div style={{ fontSize: '12px', fontWeight: 600 }}>{cust.currentPickup || 'N/A'}</div>
                          </div>
                          <div>
                            <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Destination</span>
                            <div style={{ fontSize: '12px', fontWeight: 600 }}>{cust.currentDestination || 'N/A'}</div>
                          </div>
                        </div>
                      ) : null}

                      {/* GPS & Location Status */}
                      <div style={{ padding: '12px', borderRadius: '10px', backgroundColor: cust.isLocationStale ? 'rgba(239,68,68,0.08)' : 'rgba(59,130,246,0.08)', border: `1px solid ${cust.isLocationStale ? 'rgba(239,68,68,0.25)' : 'rgba(59,130,246,0.25)'}` }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                          <span style={{ fontSize: '12px', fontWeight: 700, color: cust.isLocationStale ? '#ef4444' : '#3b82f6' }}>
                            {cust.hasLocation ? (cust.isLocationStale ? '⚠️ Stale Location' : '🟢 Live Customer Coordinates') : '❌ Location Unavailable'}
                          </span>
                          <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                            {formatLastSeen(cust.lastLocationUpdate)}
                          </span>
                        </div>
                        {cust.lat && cust.lng ? (
                          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '6px' }}>
                            <span style={{ fontSize: '12px', fontFamily: 'monospace' }}>
                              {Number(cust.lat).toFixed(5)}, {Number(cust.lng).toFixed(5)}
                            </span>
                            <a 
                              href={cust.googleMapsUrl || `https://www.google.com/maps?q=${cust.lat},${cust.lng}`} 
                              target="_blank" 
                              rel="noopener noreferrer"
                              className="btn btn-sm btn-secondary"
                              style={{ padding: '3px 8px', fontSize: '11px' }}
                            >
                              <ExternalLink size={12} />
                              <span>Google Maps</span>
                            </a>
                          </div>
                        ) : null}
                      </div>

                      {/* Assigned Pilot & Relationship */}
                      {cust.assignedPilotName ? (
                        <div style={{ padding: '12px', borderRadius: '12px', backgroundColor: 'var(--bg-input)', border: '1px solid var(--primary)' }}>
                          <div style={{ fontSize: '12px', fontWeight: 800, color: 'var(--primary)', marginBottom: '8px' }}>
                            🔗 Assigned Pilot Connection
                          </div>
                          <div style={{ fontSize: '12px', display: 'flex', flexDirection: 'column', gap: '6px' }}>
                            <div><strong>Pilot Name:</strong> {cust.assignedPilotName}</div>
                            <div><strong>Driver Mobile:</strong> +91 {cust.assignedPilotPhone}</div>
                            <div><strong>Vehicle Plate:</strong> {cust.vehiclePlate} ({cust.vehicleType})</div>
                            <div><strong>Vehicle Owner:</strong> {cust.vehicleOwnerName} (+91 {cust.vehicleOwnerPhone})</div>
                            <div><strong>Booking ID:</strong> {cust.activeBookingId}</div>
                          </div>
                        </div>
                      ) : (
                        <div style={{ fontSize: '12px', color: 'var(--text-muted)', fontStyle: 'italic', textAlign: 'center', padding: '8px' }}>
                          Customer has no active ride booking or pilot assigned.
                        </div>
                      )}
                    </div>
                  );
                })()}
              </div>
            ) : (
              /* Normal List Mode */
              <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                <div style={{ fontSize: '12px', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase', marginBottom: '4px' }}>
                  Pilots ({filteredPilots.length}) & Customers ({filteredCustomers.length})
                </div>

                {/* Pilots items */}
                {filteredPilots.map(p => (
                  <div
                    key={p.uid}
                    onClick={() => {
                      setSelectedEntity({ type: 'pilot', data: p });
                      if (p.lat && p.lng && mapInstanceRef.current) {
                        mapInstanceRef.current.panTo([p.lat, p.lng], { animate: true, duration: 0.6 });
                      }
                    }}
                    style={{
                      padding: '10px 12px',
                      borderRadius: '10px',
                      backgroundColor: 'var(--bg-input)',
                      border: '1px solid var(--border)',
                      cursor: 'pointer',
                      display: 'flex',
                      justifyContent: 'space-between',
                      alignItems: 'center',
                      transition: 'border 0.2s'
                    }}
                  >
                    <div>
                      <div style={{ fontWeight: 700, fontSize: '13px' }}>{p.name}</div>
                      <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                        {p.vehicleType} • {p.vehiclePlate || p.vehicleNumber}
                      </div>
                    </div>
                    <div style={{ textAlign: 'right' }}>
                      <span className={`badge ${p.online ? 'badge-active' : 'badge-suspended'}`} style={{ fontSize: '10px', padding: '2px 8px' }}>
                        {p.online ? 'Online' : 'Offline'}
                      </span>
                      <div style={{ fontSize: '10px', color: 'var(--text-muted)', marginTop: '2px' }}>
                        {(p.speed ?? 0) > 0 ? `${p.speed} km/h` : (p.rideStatus || 'Idle')}
                      </div>
                    </div>
                  </div>
                ))}

                {/* Customers items */}
                {filteredCustomers.map(c => (
                  <div
                    key={c.uid}
                    onClick={() => {
                      setSelectedEntity({ type: 'customer', data: c });
                      if (c.lat && c.lng && mapInstanceRef.current) {
                        mapInstanceRef.current.panTo([c.lat, c.lng], { animate: true, duration: 0.6 });
                      }
                    }}
                    style={{
                      padding: '10px 12px',
                      borderRadius: '10px',
                      backgroundColor: 'rgba(139, 92, 246, 0.06)',
                      border: '1px solid rgba(139, 92, 246, 0.2)',
                      cursor: 'pointer',
                      display: 'flex',
                      justifyContent: 'space-between',
                      alignItems: 'center'
                    }}
                  >
                    <div>
                      <div style={{ fontWeight: 700, fontSize: '13px' }}>👤 {c.name}</div>
                      <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                        +91 {c.phone}
                      </div>
                    </div>
                    <div style={{ textAlign: 'right' }}>
                      <span className={`badge ${c.bookingStatus && c.bookingStatus !== 'none' ? 'badge-active' : 'badge-pending'}`} style={{ fontSize: '10px', padding: '2px 8px' }}>
                        {c.bookingStatus && c.bookingStatus !== 'none' ? c.bookingStatus : 'Customer'}
                      </span>
                    </div>
                  </div>
                ))}

                {filteredPilots.length === 0 && filteredCustomers.length === 0 && (
                  <div style={{ textAlign: 'center', color: 'var(--text-muted)', padding: '24px', fontSize: '13px' }}>
                    No pilot or customer records match the query.
                  </div>
                )}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

export default LiveTracking;
