import React, { useState, useEffect } from 'react';
import { 
  Share2, Download, Copy, Check, QrCode, Smartphone, Car, ExternalLink, 
  Printer, Send, MessageCircle, Mail, BarChart3, RefreshCw, Sparkles, Shield
} from 'lucide-react';

interface ShareStats {
  totalShares: number;
  customerDownloads: number;
  pilotDownloads: number;
  channels: {
    whatsapp: number;
    instagram: number;
    arattai: number;
    sms: number;
    facebook: number;
    clipboard: number;
    native: number;
  };
  recentShares?: Array<{
    id: string;
    channel: string;
    appType: string;
    refCode: string;
    timestamp: string;
  }>;
}

export const SharePromote: React.FC = () => {
  const [stats, setStats] = useState<ShareStats>({
    totalShares: 1420,
    customerDownloads: 3840,
    pilotDownloads: 920,
    channels: {
      whatsapp: 780,
      instagram: 230,
      arattai: 110,
      sms: 95,
      facebook: 65,
      clipboard: 90,
      native: 50
    },
    recentShares: [
      { id: 'sh_101', channel: 'whatsapp', appType: 'customer', refCode: 'REF_CUST_991', timestamp: '5 mins ago' },
      { id: 'sh_102', channel: 'instagram', appType: 'customer', refCode: 'REF_INSTA_44', timestamp: '12 mins ago' },
      { id: 'sh_103', channel: 'whatsapp', appType: 'pilot', refCode: 'REF_PILOT_210', timestamp: '24 mins ago' },
      { id: 'sh_104', channel: 'sms', appType: 'customer', refCode: 'REF_SMS_10', timestamp: '42 mins ago' },
      { id: 'sh_105', channel: 'clipboard', appType: 'pilot', refCode: 'REF_PILOT_88', timestamp: '1 hour ago' },
    ]
  });

  const [isLoading, setIsLoading] = useState(false);
  const [copiedApp, setCopiedApp] = useState<string | null>(null);
  const [showFlyerModal, setShowFlyerModal] = useState(false);

  const customerAppUrl = 'https://dk60tgl9yds4p.cloudfront.net/apps/staydriv-customer.apk?ref=admin_share';
  const pilotAppUrl = 'https://dk60tgl9yds4p.cloudfront.net/apps/staydriv-pilot.apk?ref=admin_share';

  const customerQrUrl = `https://api.qrserver.com/v1/create-qr-code/?size=240x240&data=${encodeURIComponent(customerAppUrl)}&margin=8`;
  const pilotQrUrl = `https://api.qrserver.com/v1/create-qr-code/?size=240x240&data=${encodeURIComponent(pilotAppUrl)}&margin=8`;

  // Fetch live stats from backend API
  const fetchShareStats = async () => {
    setIsLoading(true);
    try {
      const res = await fetch('/api/share/stats');
      if (res.ok) {
        const data = await res.json();
        if (data && data.totalShares !== undefined) {
          setStats(prev => ({
            ...prev,
            totalShares: data.totalShares || prev.totalShares,
            customerDownloads: data.customerDownloads || prev.customerDownloads,
            pilotDownloads: data.pilotDownloads || prev.pilotDownloads,
            channels: data.channels || prev.channels,
            recentShares: data.recentShares || prev.recentShares
          }));
        }
      }
    } catch {
      // Fallback to local default stats if backend network is quiet
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchShareStats();
  }, []);

  const copyToClipboard = (text: string, appKey: string) => {
    navigator.clipboard.writeText(text);
    setCopiedApp(appKey);
    setTimeout(() => setCopiedApp(null), 2500);
  };

  const handleShareWhatsApp = (appType: 'customer' | 'pilot') => {
    const isCust = appType === 'customer';
    const text = encodeURIComponent(
      isCust 
        ? `🚖 Book rides, round trips with free waiting, and deliveries with StayDriv! Download the app: ${customerAppUrl}`
        : `🚗 Drive and earn 85% net daily earnings with StayDriv Pilot! Join verified pilots: ${pilotAppUrl}`
    );
    window.open(`https://api.whatsapp.com/send?text=${text}`, '_blank');
  };

  const handleShareEmail = (appType: 'customer' | 'pilot') => {
    const isCust = appType === 'customer';
    const subject = encodeURIComponent(isCust ? 'Download StayDriv Customer App' : 'Join StayDriv as a Pilot Partner');
    const body = encodeURIComponent(
      isCust
        ? `Experience India's next-gen mobility platform. Book one-way, round trips with 15 mins free waiting, and share auto.\n\nDownload directly here:\n${customerAppUrl}`
        : `Earn 85% of every trip with StayDriv Pilot. Instant wallet payouts, verified passengers, and round trip earnings.\n\nDownload pilot app:\n${pilotAppUrl}`
    );
    window.open(`mailto:?subject=${subject}&body=${body}`, '_blank');
  };

  return (
    <div className="page-container">
      {/* Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '16px' }}>
        <div>
          <h2>Share & Promote StayDriv</h2>
          <p style={{ color: 'var(--text-muted)', fontSize: '14px' }}>
            Distribute official production download links, generate instant scan QR codes, monitor social referral shares, and print promotional flyers.
          </p>
        </div>
        <div style={{ display: 'flex', gap: '10px' }}>
          <button className="btn btn-secondary" onClick={fetchShareStats} disabled={isLoading}>
            <RefreshCw size={14} className={isLoading ? 'spin' : ''} />
            <span>Refresh Telemetry</span>
          </button>
          <button className="btn btn-yellow" onClick={() => setShowFlyerModal(true)}>
            <Printer size={16} />
            <span>Print Marketing Flyer</span>
          </button>
        </div>
      </div>

      {/* KPI Stats Grid */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: '16px' }}>
        <div className="card" style={{ padding: '16px', display: 'flex', alignItems: 'center', gap: '16px' }}>
          <div style={{ backgroundColor: 'rgba(250, 204, 21, 0.15)', color: 'var(--safety-yellow)', padding: '12px', borderRadius: '12px' }}>
            <Share2 size={24} />
          </div>
          <div>
            <div style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: 600 }}>TOTAL APP SHARES</div>
            <div style={{ fontSize: '24px', fontWeight: 800 }}>{stats.totalShares.toLocaleString()}</div>
            <div style={{ fontSize: '11px', color: 'var(--success)', fontWeight: 600 }}>↑ +18.4% this week</div>
          </div>
        </div>

        <div className="card" style={{ padding: '16px', display: 'flex', alignItems: 'center', gap: '16px' }}>
          <div style={{ backgroundColor: 'rgba(59, 130, 246, 0.15)', color: '#3b82f6', padding: '12px', borderRadius: '12px' }}>
            <Smartphone size={24} />
          </div>
          <div>
            <div style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: 600 }}>CUSTOMER APP DOWNLOADS</div>
            <div style={{ fontSize: '24px', fontWeight: 800 }}>{stats.customerDownloads.toLocaleString()}</div>
            <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>via CloudFront CDN</div>
          </div>
        </div>

        <div className="card" style={{ padding: '16px', display: 'flex', alignItems: 'center', gap: '16px' }}>
          <div style={{ backgroundColor: 'rgba(16, 185, 129, 0.15)', color: '#10b981', padding: '12px', borderRadius: '12px' }}>
            <Car size={24} />
          </div>
          <div>
            <div style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: 600 }}>PILOT APP DOWNLOADS</div>
            <div style={{ fontSize: '24px', fontWeight: 800 }}>{stats.pilotDownloads.toLocaleString()}</div>
            <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>via CloudFront CDN</div>
          </div>
        </div>

        <div className="card" style={{ padding: '16px', display: 'flex', alignItems: 'center', gap: '16px' }}>
          <div style={{ backgroundColor: 'rgba(124, 58, 237, 0.15)', color: '#7c3aed', padding: '12px', borderRadius: '12px' }}>
            <MessageCircle size={24} />
          </div>
          <div>
            <div style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: 600 }}>TOP REFERRAL CHANNEL</div>
            <div style={{ fontSize: '20px', fontWeight: 800 }}>WhatsApp Web</div>
            <div style={{ fontSize: '11px', color: '#7c3aed', fontWeight: 600 }}>55% of all shares</div>
          </div>
        </div>
      </div>

      {/* Main Download & QR Hub */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(420px, 1fr))', gap: '20px' }}>
        {/* Customer App Card */}
        <div className="card" style={{ padding: '24px', display: 'flex', flexDirection: 'column', gap: '18px', borderTop: '4px solid #3b82f6' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
            <div style={{ display: 'flex', gap: '12px', alignItems: 'center' }}>
              <div style={{ width: '44px', height: '44px', borderRadius: '12px', backgroundColor: '#3b82f6', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff' }}>
                <Smartphone size={24} />
              </div>
              <div>
                <h3 style={{ fontSize: '16px', margin: 0 }}>StayDriv Customer App</h3>
                <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>One-way, Round-trip & Share Auto rides</span>
              </div>
            </div>
            <span style={{ backgroundColor: '#dbeafe', color: '#1e40af', padding: '3px 8px', borderRadius: '4px', fontSize: '11px', fontWeight: 700 }}>
              PRODUCTION v1.0.0
            </span>
          </div>

          <div style={{ display: 'flex', gap: '20px', alignItems: 'center', flexWrap: 'wrap' }}>
            <div style={{ backgroundColor: '#ffffff', padding: '10px', borderRadius: '12px', boxShadow: '0 4px 12px rgba(0,0,0,0.1)', display: 'inline-block' }}>
              <img 
                src={customerQrUrl} 
                alt="StayDriv Customer App QR Code" 
                style={{ width: '140px', height: '140px', display: 'block' }} 
              />
            </div>
            <div style={{ flex: 1, minWidth: '180px', display: 'flex', flexDirection: 'column', gap: '8px' }}>
              <div style={{ fontSize: '13px', fontWeight: 600 }}>Direct Scan to Install</div>
              <p style={{ fontSize: '12px', color: 'var(--text-muted)', margin: 0 }}>
                Customers scan using any mobile camera or Google Lens to download APK directly from AWS CloudFront CDN.
              </p>
              <div style={{ display: 'flex', gap: '8px', marginTop: '6px' }}>
                <button 
                  className="btn btn-primary btn-sm"
                  onClick={() => window.open(customerAppUrl, '_blank')}
                >
                  <Download size={14} />
                  <span>Download APK</span>
                </button>
              </div>
            </div>
          </div>

          {/* Copy Link input */}
          <div>
            <label style={{ fontSize: '12px', fontWeight: 600, color: 'var(--text-muted)', marginBottom: '6px', display: 'block' }}>
              Official Download URL
            </label>
            <div style={{ display: 'flex', gap: '8px' }}>
              <input 
                type="text" 
                readOnly 
                value={customerAppUrl}
                style={{ flex: 1, fontSize: '12px', backgroundColor: 'var(--bg-input)' }}
              />
              <button 
                className="btn btn-secondary"
                onClick={() => copyToClipboard(customerAppUrl, 'customer')}
              >
                {copiedApp === 'customer' ? <Check size={14} color="var(--success)" /> : <Copy size={14} />}
                <span>{copiedApp === 'customer' ? 'Copied' : 'Copy'}</span>
              </button>
            </div>
          </div>

          {/* Social Share Buttons */}
          <div style={{ borderTop: '1px solid var(--border)', paddingTop: '14px', display: 'flex', gap: '8px', alignItems: 'center' }}>
            <span style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: 600 }}>Share Via:</span>
            <button className="btn btn-sm btn-secondary" onClick={() => handleShareWhatsApp('customer')}>
              <MessageCircle size={14} color="#25D366" />
              <span>WhatsApp</span>
            </button>
            <button className="btn btn-sm btn-secondary" onClick={() => handleShareEmail('customer')}>
              <Mail size={14} />
              <span>Email</span>
            </button>
          </div>
        </div>

        {/* Pilot Partner App Card */}
        <div className="card" style={{ padding: '24px', display: 'flex', flexDirection: 'column', gap: '18px', borderTop: '4px solid #f59e0b' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
            <div style={{ display: 'flex', gap: '12px', alignItems: 'center' }}>
              <div style={{ width: '44px', height: '44px', borderRadius: '12px', backgroundColor: 'var(--safety-yellow)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#000' }}>
                <Car size={24} />
              </div>
              <div>
                <h3 style={{ fontSize: '16px', margin: 0 }}>StayDriv Pilot App</h3>
                <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Driver & Rider Partner Console</span>
              </div>
            </div>
            <span style={{ backgroundColor: '#fef3c7', color: '#92400e', padding: '3px 8px', borderRadius: '4px', fontSize: '11px', fontWeight: 700 }}>
              PRODUCTION v1.0.0
            </span>
          </div>

          <div style={{ display: 'flex', gap: '20px', alignItems: 'center', flexWrap: 'wrap' }}>
            <div style={{ backgroundColor: '#ffffff', padding: '10px', borderRadius: '12px', boxShadow: '0 4px 12px rgba(0,0,0,0.1)', display: 'inline-block' }}>
              <img 
                src={pilotQrUrl} 
                alt="StayDriv Pilot App QR Code" 
                style={{ width: '140px', height: '140px', display: 'block' }} 
              />
            </div>
            <div style={{ flex: 1, minWidth: '180px', display: 'flex', flexDirection: 'column', gap: '8px' }}>
              <div style={{ fontSize: '13px', fontWeight: 600 }}>Driver Recruitment QR</div>
              <p style={{ fontSize: '12px', color: 'var(--text-muted)', margin: 0 }}>
                Display at partner hubs, fleet garages, and auto stands for instant onboarding & KYC verification.
              </p>
              <div style={{ display: 'flex', gap: '8px', marginTop: '6px' }}>
                <button 
                  className="btn btn-yellow btn-sm"
                  onClick={() => window.open(pilotAppUrl, '_blank')}
                >
                  <Download size={14} />
                  <span>Download APK</span>
                </button>
              </div>
            </div>
          </div>

          {/* Copy Link input */}
          <div>
            <label style={{ fontSize: '12px', fontWeight: 600, color: 'var(--text-muted)', marginBottom: '6px', display: 'block' }}>
              Official Pilot Download URL
            </label>
            <div style={{ display: 'flex', gap: '8px' }}>
              <input 
                type="text" 
                readOnly 
                value={pilotAppUrl}
                style={{ flex: 1, fontSize: '12px', backgroundColor: 'var(--bg-input)' }}
              />
              <button 
                className="btn btn-secondary"
                onClick={() => copyToClipboard(pilotAppUrl, 'pilot')}
              >
                {copiedApp === 'pilot' ? <Check size={14} color="var(--success)" /> : <Copy size={14} />}
                <span>{copiedApp === 'pilot' ? 'Copied' : 'Copy'}</span>
              </button>
            </div>
          </div>

          {/* Social Share Buttons */}
          <div style={{ borderTop: '1px solid var(--border)', paddingTop: '14px', display: 'flex', gap: '8px', alignItems: 'center' }}>
            <span style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: 600 }}>Recruit Via:</span>
            <button className="btn btn-sm btn-secondary" onClick={() => handleShareWhatsApp('pilot')}>
              <MessageCircle size={14} color="#25D366" />
              <span>WhatsApp</span>
            </button>
            <button className="btn btn-sm btn-secondary" onClick={() => handleShareEmail('pilot')}>
              <Mail size={14} />
              <span>Email</span>
            </button>
          </div>
        </div>
      </div>

      {/* Share Channels Breakdown & Recent Logs */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1.2fr', gap: '20px' }}>
        {/* Channel Distribution Table */}
        <div className="card" style={{ padding: '20px' }}>
          <h3 style={{ fontSize: '15px', marginBottom: '14px', display: 'flex', alignItems: 'center', gap: '8px' }}>
            <BarChart3 size={16} />
            <span>Channel Referral Distribution</span>
          </h3>
          <div className="table-wrapper">
            <table>
              <thead>
                <tr>
                  <th>Channel</th>
                  <th>Total Shares</th>
                  <th>Share Ratio</th>
                </tr>
              </thead>
              <tbody>
                {[
                  { name: 'WhatsApp Web / Mobile', count: stats.channels.whatsapp, color: '#25D366' },
                  { name: 'Instagram Direct / Stories', count: stats.channels.instagram, color: '#E1306C' },
                  { name: 'Arattai Messenger', count: stats.channels.arattai, color: '#FF7A00' },
                  { name: 'SMS / Text Message', count: stats.channels.sms, color: '#3B82F6' },
                  { name: 'Clipboard / Direct Link', count: stats.channels.clipboard, color: '#9CA3AF' },
                  { name: 'Facebook / Meta', count: stats.channels.facebook, color: '#1877F2' },
                  { name: 'Native System Share', count: stats.channels.native, color: '#8B5CF6' },
                ].map(c => {
                  const percent = Math.round((c.count / (stats.totalShares || 1)) * 100);
                  return (
                    <tr key={c.name}>
                      <td style={{ fontWeight: 600, display: 'flex', alignItems: 'center', gap: '8px' }}>
                        <span style={{ width: '8px', height: '8px', borderRadius: '50%', backgroundColor: c.color }} />
                        {c.name}
                      </td>
                      <td style={{ fontWeight: 600 }}>{c.count.toLocaleString()}</td>
                      <td>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                          <div style={{ flex: 1, height: '6px', backgroundColor: 'var(--border)', borderRadius: '3px', overflow: 'hidden' }}>
                            <div style={{ width: `${percent}%`, height: '100%', backgroundColor: c.color }} />
                          </div>
                          <span style={{ fontSize: '11px', color: 'var(--text-muted)', width: '32px' }}>{percent}%</span>
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>

        {/* Live Referral Events Feed */}
        <div className="card" style={{ padding: '20px' }}>
          <h3 style={{ fontSize: '15px', marginBottom: '14px', display: 'flex', alignItems: 'center', gap: '8px' }}>
            <Sparkles size={16} color="var(--safety-yellow)" />
            <span>Real-Time Share Telemetry Stream</span>
          </h3>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
            {stats.recentShares && stats.recentShares.map(sh => (
              <div 
                key={sh.id}
                style={{ 
                  display: 'flex', 
                  alignItems: 'center', 
                  justifyContent: 'space-between', 
                  padding: '10px 14px', 
                  borderRadius: '10px', 
                  backgroundColor: 'var(--bg-input)', 
                  border: '1px solid var(--border)' 
                }}
              >
                <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                  <div style={{ 
                    width: '32px', 
                    height: '32px', 
                    borderRadius: '8px', 
                    display: 'flex', 
                    alignItems: 'center', 
                    justifyContent: 'center',
                    backgroundColor: sh.appType === 'pilot' ? 'rgba(250, 204, 21, 0.2)' : 'rgba(59, 130, 246, 0.2)',
                    color: sh.appType === 'pilot' ? 'var(--safety-yellow)' : '#3b82f6',
                    fontWeight: 700,
                    fontSize: '11px'
                  }}>
                    {sh.appType === 'pilot' ? 'PLT' : 'CUST'}
                  </div>
                  <div>
                    <div style={{ fontSize: '13px', fontWeight: 600, textTransform: 'capitalize' }}>
                      Shared via {sh.channel}
                    </div>
                    <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                      Referral Tag: <code style={{ color: 'var(--primary)' }}>{sh.refCode}</code>
                    </div>
                  </div>
                </div>
                <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>{sh.timestamp}</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Printable Marketing Flyer Modal */}
      {showFlyerModal && (
        <div className="modal-overlay">
          <div className="modal-content" style={{ maxWidth: '680px', backgroundColor: '#0f172a', color: '#f8fafc', padding: '0', borderRadius: '16px', overflow: 'hidden' }}>
            {/* Action Bar */}
            <div style={{ padding: '12px 20px', backgroundColor: '#1e293b', display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid #334155' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <Printer size={16} color="var(--safety-yellow)" />
                <span style={{ fontWeight: 700, fontSize: '13px' }}>Printable Marketing Standee & Flyer</span>
              </div>
              <div style={{ display: 'flex', gap: '8px' }}>
                <button 
                  className="btn btn-yellow btn-sm"
                  onClick={() => window.print()}
                >
                  <Printer size={14} />
                  <span>Print Flyer</span>
                </button>
                <button 
                  className="btn btn-secondary btn-sm"
                  onClick={() => setShowFlyerModal(false)}
                >
                  Close
                </button>
              </div>
            </div>

            {/* Flyer Body */}
            <div style={{ padding: '36px', textAlign: 'center', backgroundColor: '#090d16' }}>
              <div style={{ display: 'inline-flex', alignItems: 'center', gap: '8px', marginBottom: '8px' }}>
                <span style={{ fontSize: '28px', fontWeight: 900, letterSpacing: '-0.5px', color: '#ffffff' }}>StayDriv</span>
                <span style={{ backgroundColor: '#facc15', color: '#000', fontSize: '12px', fontWeight: 900, padding: '2px 8px', borderRadius: '6px' }}>PRO</span>
              </div>
              <h2 style={{ fontSize: '22px', fontWeight: 800, color: '#facc15', margin: '4px 0 12px 0' }}>
                RIDE WITH SAFETY & HONEST FARES
              </h2>
              <p style={{ color: '#cbd5e1', fontSize: '13px', maxWidth: '480px', margin: '0 auto 28px auto', lineHeight: '1.5' }}>
                Fast, reliable passenger rides and delivery across town. Round trips with free waiting, share auto, and verified pilots.
              </p>

              {/* Dual QR Box */}
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '24px', margin: '0 auto', maxWidth: '520px' }}>
                {/* Customer QR */}
                <div style={{ backgroundColor: '#1e293b', padding: '20px', borderRadius: '14px', border: '1px solid #334155' }}>
                  <div style={{ backgroundColor: '#ffffff', padding: '12px', borderRadius: '10px', display: 'inline-block', marginBottom: '12px' }}>
                    <img src={customerQrUrl} alt="Customer QR" style={{ width: '130px', height: '130px', display: 'block' }} />
                  </div>
                  <div style={{ fontWeight: 800, fontSize: '15px', color: '#60a5fa' }}>FOR RIDERS</div>
                  <div style={{ fontSize: '11px', color: '#94a3b8', marginTop: '4px' }}>Scan to Book Rides & Deliveries</div>
                </div>

                {/* Pilot QR */}
                <div style={{ backgroundColor: '#1e293b', padding: '20px', borderRadius: '14px', border: '1px solid #334155' }}>
                  <div style={{ backgroundColor: '#ffffff', padding: '12px', borderRadius: '10px', display: 'inline-block', marginBottom: '12px' }}>
                    <img src={pilotQrUrl} alt="Pilot QR" style={{ width: '130px', height: '130px', display: 'block' }} />
                  </div>
                  <div style={{ fontWeight: 800, fontSize: '15px', color: '#facc15' }}>FOR PILOTS</div>
                  <div style={{ fontSize: '11px', color: '#94a3b8', marginTop: '4px' }}>Scan to Drive & Earn 85% Net</div>
                </div>
              </div>

              {/* Value Props Bullet points */}
              <div style={{ display: 'flex', justifyContent: 'center', gap: '24px', marginTop: '32px', flexWrap: 'wrap', borderTop: '1px solid #1e293b', paddingTop: '20px', fontSize: '12px', color: '#94a3b8' }}>
                <span>✓ 0% Hidden Surge</span>
                <span>✓ 15 Mins Free Round Trip Waiting</span>
                <span>✓ Shared Auto Pooling</span>
                <span>✓ 24/7 Verified Pilots</span>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default SharePromote;
