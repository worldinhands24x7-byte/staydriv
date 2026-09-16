import React, { useState } from 'react';
import { useDatabase } from '../context/DatabaseContext';
import { Bell, Send, AlertOctagon, Info, Tag, Megaphone, Trash2 } from 'lucide-react';

export const Notifications: React.FC = () => {
  const { auditLogs, broadcastNotification } = useDatabase();
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [target, setTarget] = useState<'all' | 'customers' | 'partners'>('all');
  const [type, setType] = useState<'push' | 'promo' | 'alert' | 'emergency'>('push');
  const [isBroadcasting, setIsBroadcasting] = useState(false);

  // Filter audit logs for notification broadcasts
  const broadcastHistory = auditLogs.filter(log => log.action === 'BROADCAST_NOTIFICATION');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!title || !body) {
      alert("Please fill in notification title and message body!");
      return;
    }
    
    setIsBroadcasting(true);
    await broadcastNotification({
      title: title.trim(),
      body: body.trim(),
      type,
      targetGroup: target
    });
    setIsBroadcasting(false);

    // Reset Form
    setTitle('');
    setBody('');
  };

  const getAlertIcon = (alertType: string) => {
    switch (alertType) {
      case 'emergency': return <AlertOctagon size={16} style={{ color: 'var(--error)' }} />;
      case 'promo': return <Tag size={16} style={{ color: 'var(--success)' }} />;
      case 'alert': return <Info size={16} style={{ color: 'var(--warning)' }} />;
      default: return <Megaphone size={16} style={{ color: 'var(--primary)' }} />;
    }
  };

  return (
    <div className="page-container">
      <div>
        <h2>Push Notification Center</h2>
        <p style={{ color: 'var(--text-muted)', fontSize: '14px' }}>Draft and broadcast service alerts, marketing promos, and emergency announcements to the fleet.</p>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1.2fr', gap: '24px' }}>
        
        {/* Left Side - Push Broadcast Creator Form */}
        <div className="card">
          <div className="card-title">Compose Global Broadcast</div>
          <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
            <div className="form-group">
              <label>Notification Title</label>
              <input 
                type="text" 
                placeholder="Enter compelling heading..." 
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                required
              />
            </div>

            <div className="form-group">
              <label>Message Content Body</label>
              <textarea 
                rows={4}
                placeholder="Enter detailed notification body text..." 
                value={body}
                onChange={(e) => setBody(e.target.value)}
                required
              />
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
              <div className="form-group">
                <label>Target Audience Group</label>
                <select value={target} onChange={(e) => setTarget(e.target.value as any)}>
                  <option value="all">Everyone (All App Users)</option>
                  <option value="customers">Customers Only</option>
                  <option value="partners">Drivers / Partners Only</option>
                </select>
              </div>

              <div className="form-group">
                <label>Campaign Type Alert Category</label>
                <select value={type} onChange={(e) => setType(e.target.value as any)}>
                  <option value="push">Push Notification</option>
                  <option value="promo">Marketing / Promo</option>
                  <option value="alert">Service Status Alert</option>
                  <option value="emergency">🚨 Emergency Broadcast</option>
                </select>
              </div>
            </div>

            <button 
              className={`btn ${type === 'emergency' ? 'btn-danger' : 'btn-primary'}`} 
              type="submit" 
              style={{ marginTop: '8px' }}
              disabled={isBroadcasting}
            >
              <Send size={16} />
              <span>{isBroadcasting ? 'Sending broadcast...' : 'Dispatch Broadcast'}</span>
            </button>
          </form>
        </div>

        {/* Right Side - Sent Broadcast History log */}
        <div className="card">
          <div className="card-title">Sent Campaign History Logs</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '12px', maxHeight: '420px', overflowY: 'auto' }}>
            {broadcastHistory.length > 0 ? (
              broadcastHistory.map(history => {
                // Parse details string which contains title, body, target
                const actionDetails = history.details;
                return (
                  <div 
                    key={history.logId}
                    style={{ 
                      padding: '16px', 
                      border: '1px solid var(--border)', 
                      borderRadius: '12px',
                      backgroundColor: 'var(--bg-input)',
                      display: 'flex',
                      gap: '12px',
                      alignItems: 'flex-start'
                    }}
                  >
                    <div style={{ marginTop: '3px' }}>
                      {getAlertIcon(actionDetails.includes('emergency') ? 'emergency' : actionDetails.includes('promo') ? 'promo' : actionDetails.includes('alert') ? 'alert' : 'push')}
                    </div>
                    <div style={{ flex: 1 }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <span style={{ fontWeight: 600, fontSize: '13px' }}>{history.adminEmail}</span>
                        <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>{new Date(history.timestamp).toLocaleString('en-IN')}</span>
                      </div>
                      <p style={{ fontSize: '13px', color: 'var(--text-main)', marginTop: '6px', fontWeight: 500 }}>
                        {actionDetails}
                      </p>
                      <div style={{ display: 'flex', gap: '6px', marginTop: '6px' }}>
                        <span style={{ fontSize: '10px', backgroundColor: 'var(--bg-card)', padding: '2px 6px', borderRadius: '4px', border: '1px solid var(--border)' }}>
                          IP: {history.ipAddress}
                        </span>
                      </div>
                    </div>
                  </div>
                );
              })
            ) : (
              <div style={{ textAlign: 'center', color: 'var(--text-muted)', padding: '40px' }}>
                No records of notification campaigns sent during this session.
              </div>
            )}
          </div>
        </div>

      </div>
    </div>
  );
};
export default Notifications;
