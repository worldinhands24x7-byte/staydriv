import React, { useState, useEffect, useRef } from 'react';
import { useDatabase } from '../context/DatabaseContext';
import { MapPin, Navigation, Compass, Search, RefreshCw, Layers, ShieldAlert } from 'lucide-react';

export const LiveTracking: React.FC = () => {
  const { bookings, deliveries, partners } = useDatabase();
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedTripId, setSelectedTripId] = useState<string | null>(null);
  const [trackingLayer, setTrackingLayer] = useState<'all' | 'rides' | 'deliveries' | 'drivers'>('all');
  
  // Hyderabad bounds simulation
  // Kukatpally: 17.4855, 78.3976
  // Gachibowli: 17.4483, 78.3496
  // Charminar: 17.3616, 78.4747
  // Secunderabad: 17.4344, 78.5015
  
  // Real-time animation coordinates
  const [driverPositions, setDriverPositions] = useState<Array<{
    uid: string;
    name: string;
    vehicleType: string;
    plate: string;
    lat: number;
    lng: number;
    status: 'online' | 'busy' | 'offline';
  }>>([]);

  useEffect(() => {
    // Generate active driver coordinates from partners database
    const initialPositions = partners.map((p, idx) => {
      // Use actual coordinates if available, otherwise fall back to mock locations
      let lat = p.lat !== undefined && p.lat !== null && p.lat !== 0 ? p.lat : 17.4483;
      let lng = p.lng !== undefined && p.lng !== null && p.lng !== 0 ? p.lng : 78.3496;
      if (p.lat === undefined || p.lat === null || p.lat === 0) {
        if (idx === 0) { lat = 17.4855; lng = 78.3976; } // Kukatpally
        if (idx === 1) { lat = 17.4483; lng = 78.3496; } // Gachibowli
        if (idx === 2) { lat = 17.3616; lng = 78.4747; } // Charminar
        if (idx === 3) { lat = 17.4344; lng = 78.5015; } // Secunderabad
      }

      return {
        uid: p.uid,
        name: p.name,
        vehicleType: p.vehicleType,
        plate: p.vehiclePlate,
        lat,
        lng,
        status: p.online ? ('online' as const) : p.status === 'suspended' ? ('offline' as const) : ('offline' as const)
      };
    });
    setDriverPositions(initialPositions);

    // Simulate real-time minor drift/movement
    const timer = setInterval(() => {
      setDriverPositions(prev => prev.map(d => {
        if (d.status === 'offline') return d;
        // Minor random coordinate drift
        const driftLat = (Math.random() - 0.5) * 0.001;
        const driftLng = (Math.random() - 0.5) * 0.001;
        return {
          ...d,
          lat: d.lat + driftLat,
          lng: d.lng + driftLng
        };
      }));
    }, 3000);

    return () => clearInterval(timer);
  }, [partners]);

  // Combine Active Rides & Deliveries for lists
  const activeRides = bookings.filter(b => b.status !== 'completed' && b.status !== 'cancelled');
  const activeParcels = deliveries.filter(d => d.status !== 'completed' && d.status !== 'cancelled');
  
  const allActiveTrips = [
    ...activeRides.map(b => ({
      id: b.bookingId,
      type: 'ride',
      customer: b.customerName,
      vehicle: b.vehicle,
      pickup: b.pickup,
      drop: b.drop,
      price: b.price,
      status: b.status,
      driverName: b.driverName || 'Searching...',
      pickupLatLng: b.pickupLatLng,
      dropLatLng: b.dropLatLng,
      otp: b.otp
    })),
    ...activeParcels.map(d => ({
      id: d.bookingId,
      type: 'delivery',
      customer: d.customerName,
      vehicle: d.vehicle,
      pickup: d.pickup,
      drop: d.drop,
      price: d.price,
      status: d.status,
      driverName: d.driverName || 'Searching...',
      pickupLatLng: d.pickupLatLng,
      dropLatLng: d.dropLatLng,
      otp: d.otp
    }))
  ];

  // Filtering list
  const filteredTrips = allActiveTrips.filter(t => {
    const matchesSearch = 
      t.id.toLowerCase().includes(searchTerm.toLowerCase()) ||
      t.customer.toLowerCase().includes(searchTerm.toLowerCase()) ||
      t.driverName.toLowerCase().includes(searchTerm.toLowerCase());
    
    if (!matchesSearch) return false;
    
    if (trackingLayer === 'all') return true;
    if (trackingLayer === 'rides') return t.type === 'ride';
    if (trackingLayer === 'deliveries') return t.type === 'delivery';
    return false;
  });

  const selectedTrip = allActiveTrips.find(t => t.id === selectedTripId);

  // SVG dimensions for vector map grid
  // We'll map coordinates:
  // Lat: 17.34 to 17.52 -> Y: 380 to 20
  // Lng: 78.32 to 78.52 -> X: 20 to 380
  const convertCoords = (lat: number, lng: number) => {
    const minLat = 17.34;
    const maxLat = 17.52;
    const minLng = 78.32;
    const maxLng = 78.52;
    
    const x = ((lng - minLng) / (maxLng - minLng)) * 360 + 20;
    const y = 400 - (((lat - minLat) / (maxLat - minLat)) * 360 + 20);
    return { x, y };
  };

  return (
    <div className="page-container">
      <div>
        <h2>Live Tracking Console</h2>
        <p style={{ color: 'var(--text-muted)', fontSize: '14px' }}>Real-time GPS positioning, route maps, and active dispatch audits.</p>
      </div>

      <div className="map-layout">
        {/* Left Side - Active trips list */}
        <div className="map-sidebar">
          <div className="card" style={{ padding: '16px', gap: '12px' }}>
            <div className="input-icon-wrapper">
              <Search size={14} />
              <input 
                type="text" 
                placeholder="Search Active IDs/Drivers..." 
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                style={{ padding: '8px 12px 8px 32px', fontSize: '13px' }}
              />
            </div>
            
            <div style={{ display: 'flex', gap: '4px' }}>
              {(['all', 'rides', 'deliveries'] as const).map(layer => (
                <button
                  key={layer}
                  className={`btn btn-sm ${trackingLayer === layer ? 'btn-primary' : 'btn-secondary'}`}
                  onClick={() => setTrackingLayer(layer)}
                  style={{ textTransform: 'capitalize', flex: 1, padding: '4px 6px', fontSize: '11px' }}
                >
                  {layer === 'all' ? 'All Active' : layer}
                </button>
              ))}
            </div>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '10px', maxHeight: '420px', overflowY: 'auto' }}>
            {filteredTrips.length > 0 ? (
              filteredTrips.map(trip => (
                <div 
                  key={trip.id} 
                  className={`card ${selectedTripId === trip.id ? 'active' : ''}`}
                  onClick={() => setSelectedTripId(trip.id)}
                  style={{ 
                    padding: '14px', 
                    cursor: 'pointer',
                    borderColor: selectedTripId === trip.id ? 'var(--primary)' : 'var(--border)',
                    borderLeft: selectedTripId === trip.id ? '4px solid var(--primary)' : '1px solid var(--border)',
                    borderRadius: '12px',
                    gap: '8px'
                  }}
                >
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <span style={{ fontWeight: 700, fontSize: '13px' }}>{trip.id}</span>
                    <span className={`badge ${trip.type === 'ride' ? 'badge-requested' : 'badge-completed'}`} style={{ fontSize: '10px' }}>
                      {trip.type}
                    </span>
                  </div>
                  
                  <div style={{ fontSize: '12px' }}>
                    <div><strong>Customer:</strong> {trip.customer}</div>
                    <div><strong>Driver:</strong> {trip.driverName}</div>
                    <div style={{ color: 'var(--text-muted)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', marginTop: '4px' }}>
                      To: {trip.drop}
                    </div>
                  </div>
                  
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: '11px', marginTop: '4px' }}>
                    <span className={`badge badge-${trip.status}`}>{trip.status}</span>
                    <span style={{ fontWeight: 600 }}>OTP: {trip.otp}</span>
                  </div>
                </div>
              ))
            ) : (
              <div className="card" style={{ padding: '20px', textAlign: 'center', color: 'var(--text-muted)' }}>
                No active bookings found.
              </div>
            )}
          </div>
        </div>

        {/* Right Side - Map rendering viewport */}
        <div className="map-viewport">
          {/* Top Layer Info overlay */}
          <div className="map-search-bar" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', pointerEvents: 'none' }}>
            <span style={{ fontSize: '12px', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '6px' }}>
              <Compass size={14} className="trend-up" />
              <span>Vector GPS Engine: Hyderabad Central Bounds</span>
            </span>
            <div style={{ display: 'flex', gap: '16px', fontSize: '11px', fontWeight: 500 }}>
              <span style={{ display: 'flex', alignItems: 'center', gap: '4px' }}><div style={{ width: '8px', height: '8px', borderRadius: '50%', backgroundColor: '#6366f1' }} /> Ride Taxi</span>
              <span style={{ display: 'flex', alignItems: 'center', gap: '4px' }}><div style={{ width: '8px', height: '8px', borderRadius: '50%', backgroundColor: '#fbbf24' }} /> Auto</span>
              <span style={{ display: 'flex', alignItems: 'center', gap: '4px' }}><div style={{ width: '8px', height: '8px', borderRadius: '50%', backgroundColor: '#10b981' }} /> Cargo</span>
              <span style={{ display: 'flex', alignItems: 'center', gap: '4px' }}><div style={{ width: '8px', height: '8px', borderRadius: '50%', backgroundColor: '#ef4444' }} /> Offline</span>
            </div>
          </div>

          {/* Interactive SVG grid map */}
          <svg className="map-svg-grid" viewBox="0 0 400 400">
            {/* Draw grid lines representing streets */}
            <defs>
              <pattern id="grid" width="40" height="40" patternUnits="userSpaceOnUse">
                <path d="M 40 0 L 0 0 0 40" fill="none" stroke="rgba(255, 255, 255, 0.04)" strokeWidth="1" />
              </pattern>
            </defs>
            <rect width="100%" height="100%" fill="#0f172a" />
            <rect width="100%" height="100%" fill="url(#grid)" />

            {/* Draw major simulated express highways */}
            <line x1="20" y1="200" x2="380" y2="200" stroke="rgba(255, 255, 255, 0.08)" strokeWidth="3" />
            <line x1="200" y1="20" x2="200" y2="380" stroke="rgba(255, 255, 255, 0.08)" strokeWidth="3" />
            
            {/* Outer Ring Road (ORR) bounds circle */}
            <circle cx="200" cy="200" r="150" fill="none" stroke="rgba(251, 191, 36, 0.05)" strokeWidth="2" strokeDasharray="5 5" />
            <text x="200" y="45" fill="rgba(255, 255, 255, 0.2)" fontSize="8" textAnchor="middle">HYDERABAD OUTER RING ROAD (ORR)</text>

            {/* Plot active booking routes if a trip is selected */}
            {selectedTrip && (() => {
              const start = convertCoords(selectedTrip.pickupLatLng.lat, selectedTrip.pickupLatLng.lng);
              const end = convertCoords(selectedTrip.dropLatLng.lat, selectedTrip.dropLatLng.lng);
              return (
                <>
                  {/* Route path */}
                  <line 
                    x1={start.x} 
                    y1={start.y} 
                    x2={end.x} 
                    y2={end.y} 
                    stroke="var(--primary)" 
                    strokeWidth="2" 
                    strokeDasharray="4 4"
                  />
                  {/* Pickup Pin */}
                  <circle cx={start.x} cy={start.y} r="5" fill="#10b981" />
                  <circle cx={start.x} cy={start.y} r="10" fill="none" stroke="#10b981" strokeWidth="1" opacity="0.6" />
                  {/* Drop Pin */}
                  <polygon points={`${end.x},${end.y-6} ${end.x-5},${end.y+3} ${end.x+5},${end.y+3}`} fill="#ef4444" />
                </>
              );
            })()}

            {/* Plot driver markers */}
            {driverPositions.map(drv => {
              const pos = convertCoords(drv.lat, drv.lng);
              const isSelected = selectedTrip && selectedTrip.driverName === drv.name;
              
              // Pin color based on status / vehicle type
              let color = '#ef4444'; // offline
              if (drv.status !== 'offline') {
                if (drv.vehicleType === 'Car') color = '#3b82f6';
                else if (drv.vehicleType === 'Bike') color = '#6366f1';
                else if (drv.vehicleType === 'Auto') color = '#fbbf24';
                else color = '#10b981'; // truck
              }

              return (
                <g key={drv.uid} style={{ cursor: 'pointer' }} onClick={() => alert(`Driver: ${drv.name} \nVehicle: ${drv.plate} \nStatus: ${drv.status}`)}>
                  {/* Pulsing beacon if active or selected */}
                  {isSelected && (
                    <circle cx={pos.x} cy={pos.y} r="14" fill="none" stroke="var(--primary)" strokeWidth="1.5">
                      <animate attributeName="r" values="8;18;8" dur="2s" repeatCount="indefinite" />
                      <animate attributeName="opacity" values="0.8;0.1;0.8" dur="2s" repeatCount="indefinite" />
                    </circle>
                  )}
                  {/* Driver Pin marker dot */}
                  <circle cx={pos.x} cy={pos.y} r="6" fill={color} stroke="#0f172a" strokeWidth="1.5" />
                  {/* Driver tooltip details */}
                  <text x={pos.x} y={pos.y - 10} fill="#fff" fontSize="7" fontWeight="bold" textAnchor="middle" style={{ backgroundColor: '#000' }}>
                    {drv.name.split(' ')[0]}
                  </text>
                </g>
              );
            })}
          </svg>
          
          {/* Map centering HUD detail */}
          {selectedTrip && (
            <div style={{ 
              position: 'absolute', 
              bottom: '16px', 
              left: '16px', 
              right: '16px', 
              backgroundColor: 'var(--bg-card)', 
              border: '1px solid var(--border)', 
              borderRadius: '12px',
              padding: '12px',
              boxShadow: 'var(--shadow-lg)',
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
              fontSize: '13px'
            }}>
              <div>
                <strong>Active Track: {selectedTrip.id}</strong>
                <div style={{ color: 'var(--text-muted)', fontSize: '11px', marginTop: '2px' }}>
                  Pickup: {selectedTrip.pickup} &rarr; Drop: {selectedTrip.drop}
                </div>
              </div>
              <div style={{ display: 'flex', gap: '8px' }}>
                <span className={`badge badge-${selectedTrip.status}`}>{selectedTrip.status}</span>
                <button className="btn btn-secondary btn-sm" onClick={() => setSelectedTripId(null)}>Clear Focus</button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
export default LiveTracking;
