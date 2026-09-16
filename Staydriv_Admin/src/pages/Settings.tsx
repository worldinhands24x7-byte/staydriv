import React, { useState } from 'react';
import { useDatabase } from '../context/DatabaseContext';
import { Settings as SettingsIcon, Save, Key, ShieldCheck, Database, RefreshCw, Trash2, MapPin } from 'lucide-react';

export const Settings: React.FC = () => {
  const { 
    config, updateCommissionRate, updateBaseFare, updatePerKmRate, 
    saveFirebaseConfig, clearFirebaseConfig, getFirebaseConfig, isLive 
  } = useDatabase();

  const [commPercent, setCommPercent] = useState<number>(config.commissionPercent);
  
  // Base fares
  const [bikeBase, setBikeBase] = useState(config.baseFares.Bike || 40);
  const [autoBase, setAutoBase] = useState(config.baseFares.Auto || 60);
  const [carBase, setCarBase] = useState(config.baseFares.Car || 100);
  const [miniTruckBase, setMiniTruckBase] = useState(config.baseFares['Mini Truck'] || 250);
  const [truckBase, setTruckBase] = useState(config.baseFares.Truck || 600);

  // Per km rates
  const [bikePerKm, setBikePerKm] = useState(config.perKmRates.Bike || 8);
  const [autoPerKm, setAutoPerKm] = useState(config.perKmRates.Auto || 12);
  const [carPerKm, setCarPerKm] = useState(config.perKmRates.Car || 18);
  const [miniTruckPerKm, setMiniTruckPerKm] = useState(config.perKmRates['Mini Truck'] || 35);
  const [truckPerKm, setTruckPerKm] = useState(config.perKmRates.Truck || 75);

  // Cancellation charges
  const [custCancel, setCustCancel] = useState(config.cancellationCharges.customer || 30);
  const [driverCancel, setDriverCancel] = useState(config.cancellationCharges.partner || 50);

  // Referral
  const [referrerReward, setReferrerReward] = useState(config.referralRewards.referrer || 100);
  const [refereeReward, setRefereeReward] = useState(config.referralRewards.referee || 50);

  // Service Areas
  const [areas, setAreas] = useState(config.serviceAreas);

  // Firebase Config panel states
  const [fbConfig, setFbConfig] = useState(getFirebaseConfig());

  const handleSaveAppConfigs = async (e: React.FormEvent) => {
    e.preventDefault();
    
    // Save platform commission
    await updateCommissionRate(commPercent);
    
    // Save base fares
    await updateBaseFare('Bike', bikeBase);
    await updateBaseFare('Auto', autoBase);
    await updateBaseFare('Car', carBase);
    await updateBaseFare('Mini Truck', miniTruckBase);
    await updateBaseFare('Truck', truckBase);

    // Save rates
    await updatePerKmRate('Bike', bikePerKm);
    await updatePerKmRate('Auto', autoPerKm);
    await updatePerKmRate('Car', carPerKm);
    await updatePerKmRate('Mini Truck', miniTruckPerKm);
    await updatePerKmRate('Truck', truckPerKm);

    alert("Platform parameters updated and synchronized successfully!");
  };

  const handleSaveFirebaseConfig = (e: React.FormEvent) => {
    e.preventDefault();
    if (!fbConfig.apiKey || !fbConfig.projectId) {
      alert("ApiKey and ProjectId are required to link Firebase!");
      return;
    }
    saveFirebaseConfig(fbConfig);
  };

  const toggleArea = (idx: number) => {
    const list = areas.map((a, i) => i === idx ? { ...a, active: !a.active } : a);
    setAreas(list);
  };

  return (
    <div className="page-container">
      <div>
        <h2>System Configuration Settings</h2>
        <p style={{ color: 'var(--text-muted)', fontSize: '14px' }}>Tweak fare engines, manage active zones, and establish live database connections.</p>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '24px' }}>
        
        {/* Left Column: Fare configs, cancellation, rewards */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
          
          {/* Main App Config Form */}
          <div className="card">
            <div className="card-title">Platform Parameter Controls</div>
            <form onSubmit={handleSaveAppConfigs} style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
              
              {/* Commission */}
              <div className="form-group">
                <label>Platform Commission Rate ({commPercent}%)</label>
                <input 
                  type="number" 
                  value={commPercent} 
                  onChange={(e) => setCommPercent(parseInt(e.target.value))} 
                />
              </div>

              {/* Base Fares */}
              <div>
                <span style={{ fontSize: '12px', fontWeight: 600, color: 'var(--text-muted)' }}>Base Category Fares (₹)</span>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '10px', marginTop: '6px' }}>
                  <div className="form-group">
                    <label>Bike Base</label>
                    <input type="number" value={bikeBase} onChange={(e) => setBikeBase(parseInt(e.target.value))} />
                  </div>
                  <div className="form-group">
                    <label>Auto Base</label>
                    <input type="number" value={autoBase} onChange={(e) => setAutoBase(parseInt(e.target.value))} />
                  </div>
                  <div className="form-group">
                    <label>Cab Base</label>
                    <input type="number" value={carBase} onChange={(e) => setCarBase(parseInt(e.target.value))} />
                  </div>
                </div>
              </div>

              {/* Per Km Rates */}
              <div>
                <span style={{ fontSize: '12px', fontWeight: 600, color: 'var(--text-muted)' }}>Per Kilometer Rates (₹/km)</span>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '10px', marginTop: '6px' }}>
                  <div className="form-group">
                    <label>Bike Rate</label>
                    <input type="number" value={bikePerKm} onChange={(e) => setBikePerKm(parseInt(e.target.value))} />
                  </div>
                  <div className="form-group">
                    <label>Auto Rate</label>
                    <input type="number" value={autoPerKm} onChange={(e) => setAutoPerKm(parseInt(e.target.value))} />
                  </div>
                  <div className="form-group">
                    <label>Cab Rate</label>
                    <input type="number" value={carPerKm} onChange={(e) => setCarPerKm(parseInt(e.target.value))} />
                  </div>
                </div>
              </div>

              {/* Heavy Goods Rates */}
              <div>
                <span style={{ fontSize: '12px', fontWeight: 600, color: 'var(--text-muted)' }}>Logistics Cargo Charges (Base / Per-Km)</span>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px', marginTop: '6px' }}>
                  <div className="form-group">
                    <label>Mini Truck Base (₹)</label>
                    <input type="number" value={miniTruckBase} onChange={(e) => setMiniTruckBase(parseInt(e.target.value))} />
                  </div>
                  <div className="form-group">
                    <label>Mini Truck Rate (₹/km)</label>
                    <input type="number" value={miniTruckPerKm} onChange={(e) => setMiniTruckPerKm(parseInt(e.target.value))} />
                  </div>
                  <div className="form-group">
                    <label>Heavy Truck Base (₹)</label>
                    <input type="number" value={truckBase} onChange={(e) => setTruckBase(parseInt(e.target.value))} />
                  </div>
                  <div className="form-group">
                    <label>Heavy Truck Rate (₹/km)</label>
                    <input type="number" value={truckPerKm} onChange={(e) => setTruckPerKm(parseInt(e.target.value))} />
                  </div>
                </div>
              </div>

              {/* Cancellation Charges */}
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
                <div className="form-group">
                  <label>Customer Cancellation fee (₹)</label>
                  <input type="number" value={custCancel} onChange={(e) => setCustCancel(parseInt(e.target.value))} />
                </div>
                <div className="form-group">
                  <label>Partner Cancellation fee (₹)</label>
                  <input type="number" value={driverCancel} onChange={(e) => setDriverCancel(parseInt(e.target.value))} />
                </div>
              </div>

              {/* Referral Rewards */}
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
                <div className="form-group">
                  <label>Referrer Reward Bonus (₹)</label>
                  <input type="number" value={referrerReward} onChange={(e) => setReferrerReward(parseInt(e.target.value))} />
                </div>
                <div className="form-group">
                  <label>Referee Onboarding Credit (₹)</label>
                  <input type="number" value={refereeReward} onChange={(e) => setRefereeReward(parseInt(e.target.value))} />
                </div>
              </div>

              <button className="btn btn-primary" type="submit" style={{ display: 'flex', gap: '8px', justifyContent: 'center' }}>
                <Save size={16} />
                <span>Save Platform Parameters</span>
              </button>
            </form>
          </div>
        </div>

        {/* Right Column: Firebase configuration & Service Areas */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
          
          {/* Firebase Connection Card */}
          <div className="card">
            <div className="card-title">
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <Key size={18} style={{ color: isLive ? 'var(--success)' : 'var(--warning)' }} />
                <span>Firebase Connection Details</span>
              </div>
            </div>
            
            <div style={{ fontSize: '13px', color: 'var(--text-muted)' }}>
              Link this panel to the StayDriv Firebase database. Saving credentials connects Firestore in real-time.
            </div>

            {isLive ? (
              <div style={{ display: 'flex', flexDirection: 'column', gap: '16px', backgroundColor: 'var(--success-bg)', border: '1px solid var(--success)', padding: '16px', borderRadius: '12px' }}>
                <div style={{ display: 'flex', gap: '8px', alignItems: 'center', color: 'var(--success)', fontWeight: 600 }}>
                  <ShieldCheck size={18} />
                  <span>CONNECTED TO LIVE FIRESTORE</span>
                </div>
                <div style={{ fontSize: '12px' }}>
                  Project ID: <strong>{fbConfig.projectId}</strong>
                </div>
                <button className="btn btn-danger btn-sm" onClick={clearFirebaseConfig} style={{ alignSelf: 'flex-start' }}>
                  Disconnect Project
                </button>
              </div>
            ) : (
              <form onSubmit={handleSaveFirebaseConfig} style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
                <div className="form-group">
                  <label>apiKey</label>
                  <input 
                    type="password" 
                    placeholder="AIzaSy..." 
                    value={fbConfig.apiKey || ''} 
                    onChange={(e) => setFbConfig({ ...fbConfig, apiKey: e.target.value.trim() })}
                    required
                  />
                </div>

                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                  <div className="form-group">
                    <label>authDomain</label>
                    <input 
                      type="text" 
                      placeholder="staydriv.firebaseapp.com" 
                      value={fbConfig.authDomain || ''}
                      onChange={(e) => setFbConfig({ ...fbConfig, authDomain: e.target.value.trim() })}
                    />
                  </div>
                  <div className="form-group">
                    <label>projectId</label>
                    <input 
                      type="text" 
                      placeholder="staydriv-project-id" 
                      value={fbConfig.projectId || ''}
                      onChange={(e) => setFbConfig({ ...fbConfig, projectId: e.target.value.trim() })}
                      required
                    />
                  </div>
                </div>

                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                  <div className="form-group">
                    <label>storageBucket</label>
                    <input 
                      type="text" 
                      placeholder="staydriv.appspot.com" 
                      value={fbConfig.storageBucket || ''}
                      onChange={(e) => setFbConfig({ ...fbConfig, storageBucket: e.target.value.trim() })}
                    />
                  </div>
                  <div className="form-group">
                    <label>messagingSenderId</label>
                    <input 
                      type="text" 
                      placeholder="1234567890" 
                      value={fbConfig.messagingSenderId || ''}
                      onChange={(e) => setFbConfig({ ...fbConfig, messagingSenderId: e.target.value.trim() })}
                    />
                  </div>
                </div>

                <div className="form-group">
                  <label>appId</label>
                  <input 
                    type="text" 
                    placeholder="1:123456:web:abcd1234" 
                    value={fbConfig.appId || ''}
                    onChange={(e) => setFbConfig({ ...fbConfig, appId: e.target.value.trim() })}
                  />
                </div>

                <button className="btn btn-yellow" type="submit">
                  Connect & Synchronize
                </button>
              </form>
            )}
          </div>

          {/* Service Area Zones */}
          <div className="card">
            <div className="card-title">Manage Service Areas</div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
              {areas.map((area, idx) => (
                <div 
                  key={idx}
                  style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '12px', border: '1px solid var(--border)', borderRadius: '12px' }}
                >
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <MapPin size={16} style={{ color: area.active ? 'var(--success)' : 'var(--text-muted)' }} />
                    <span style={{ fontWeight: 600, fontSize: '13px' }}>{area.name}</span>
                  </div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>{area.active ? 'Serving' : 'Disabled'}</span>
                    <button 
                      className={`btn btn-sm ${area.active ? 'btn-danger' : 'btn-success'}`}
                      onClick={() => toggleArea(idx)}
                      style={{ padding: '2px 8px', fontSize: '10px' }}
                    >
                      {area.active ? 'Disable' : 'Enable'}
                    </button>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>

      </div>
    </div>
  );
};
export default Settings;
