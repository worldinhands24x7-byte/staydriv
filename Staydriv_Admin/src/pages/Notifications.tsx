import React, { useState, useEffect } from 'react';
import { useDatabase } from '../context/DatabaseContext';
import { Send, AlertOctagon, Info, Tag, Megaphone, CheckCircle2, XCircle, Users, RefreshCw } from 'lucide-react';

interface CampaignRecord {
  campaignId: string;
  title: string;
  body: string;
  targetGroup: 'all' | 'customers' | 'partners' | 'restaurants' | 'selected';
  type: 'push' | 'promo' | 'alert' | 'emergency';
  adminEmail: string;
  adminName?: string;
  ipAddress?: string;
  status: 'sent' | 'partial' | 'failed' | 'sending' | 'fcm_accepted' | 'in_app_delivered';
  totalEligible: number;
  successCount: number;
  failureCount: number;
  sentAt: string;
  deliveryStats?: {
    delivered?: number;
    inAppDelivered?: number;
    fcmAccepted?: number;
    fcmFailed?: number;
    invalidTokens?: number;
    opened?: number;
  };
  metadata?: {
    fcmConfigured?: boolean;
    dispatchMode?: string;
    projectId?: string;
  };
}

export const Notifications: React.FC = () => {
  const { auditLogs, broadcastNotification, fetchCampaigns, fetchAudienceStats } = useDatabase();
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [target, setTarget] = useState<'all' | 'customers' | 'partners' | 'restaurants' | 'selected'>('all');
  const [type, setType] = useState<'push' | 'promo' | 'alert' | 'emergency'>('push');
  const [isBroadcasting, setIsBroadcasting] = useState(false);
  const [showConfirmModal, setShowConfirmModal] = useState(false);
  const [lastBroadcastResult, setLastBroadcastResult] = useState<{
    success: boolean;
    message?: string;
    totalEligible?: number;
    successCount?: number;
  } | null>(null);

  const [campaigns, setCampaigns] = useState<CampaignRecord[]>([]);
  const [audienceStats, setAudienceStats] = useState<{
    totalEligible: number;
    customers: number;
    partners: number;
    restaurants: number;
    fcmConfigured?: boolean;
    projectId?: string;
  } | null>(null);
  const [isLoadingHistory, setIsLoadingHistory] = useState(false);
  const [showFcmModal, setShowFcmModal] = useState(false);
  const [fcmJsonInput, setFcmJsonInput] = useState('');
  const [isSavingFcm, setIsSavingFcm] = useState(false);
  const [fcmSaveResult, setFcmSaveResult] = useState<{ success: boolean; msg: string } | null>(null);

  // Load real campaign logs from backend on mount
  const loadCampaigns = async () => {
    setIsLoadingHistory(true);
    try {
      const data = await fetchCampaigns();
      if (Array.isArray(data) && data.length > 0) {
        setCampaigns(data);
      }
      const stats = await fetchAudienceStats();
      if (stats) {
        setAudienceStats(stats);
      }
    } catch (_) {
    } finally {
      setIsLoadingHistory(false);
    }
  };

  useEffect(() => {
    loadCampaigns();
  }, []);

  const handleOpenConfirm = (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim() || !body.trim()) {
      alert("Please fill in notification heading and message body!");
      return;
    }
    setShowConfirmModal(true);
  };

  const handleConfirmDispatch = async () => {
    if (isBroadcasting) return; // Prevent duplicate clicks
    setIsBroadcasting(true);
    setLastBroadcastResult(null);

    try {
      const result = await broadcastNotification({
        title: title.trim(),
        body: body.trim(),
        type,
        targetGroup: target
      });

      if (result && result.success) {
        let msg = '';
        if (result.fcmConfigured && result.fcmAccepted > 0) {
          msg = `Broadcast dispatched to ${result.totalEligible} device(s) (FCM Accepted: ${result.fcmAccepted}, In-App: ${result.inAppDelivered})!`;
        } else if (result.status === 'in_app_delivered') {
          msg = `Broadcast delivered to Customer In-App Inbox (${result.inAppDelivered} eligible device(s))!`;
        } else {
          msg = `Broadcast successfully dispatched (${result.totalEligible ?? 0} recipients)!`;
        }

        setLastBroadcastResult({
          success: true,
          message: msg,
          totalEligible: result.totalEligible,
          successCount: result.successCount
        });
        // Reset form
        setTitle('');
        setBody('');
        setShowConfirmModal(false);
        // Refresh campaign history immediately from backend
        await loadCampaigns();
      } else {
        setLastBroadcastResult({
          success: false,
          message: result?.message || 'Failed to dispatch broadcast. Please check backend connection.'
        });
        setShowConfirmModal(false);
      }
    } catch (err: any) {
      setLastBroadcastResult({
        success: false,
        message: err.message || 'Network error while dispatching broadcast.'
      });
      setShowConfirmModal(false);
    } finally {
      setIsBroadcasting(false);
    }
  };

  const handleSaveFcmKey = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!fcmJsonInput.trim()) return;
    setIsSavingFcm(true);
    setFcmSaveResult(null);

    try {
      const backendUrl = localStorage.getItem('staydriv_backend_url') || '';
      const res = await fetch(`${backendUrl}/api/notifications/configure-fcm`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ serviceAccountJson: fcmJsonInput.trim() })
      });
      const data = await res.json();
      if (data.success) {
        setFcmSaveResult({ success: true, msg: `Service Account successfully configured for project: ${data.projectId}!` });
        await loadCampaigns();
        setTimeout(() => {
          setShowFcmModal(false);
          setFcmJsonInput('');
          setFcmSaveResult(null);
        }, 1500);
      } else {
        setFcmSaveResult({ success: false, msg: data.message || 'Failed to configure service account' });
      }
    } catch (err: any) {
      setFcmSaveResult({ success: false, msg: err.message || 'Network error' });
    } finally {
      setIsSavingFcm(false);
    }
  };

  const getAlertIcon = (alertType: string) => {
    switch (alertType) {
      case 'emergency': return <AlertOctagon size={16} style={{ color: 'var(--error)' }} />;
      case 'promo': return <Tag size={16} style={{ color: 'var(--success)' }} />;
      case 'alert': return <Info size={16} style={{ color: 'var(--warning)' }} />;
      default: return <Megaphone size={16} style={{ color: 'var(--primary)' }} />;
    }
  };

  const getTargetLabel = (t: string) => {
    switch (t) {
      case 'customers': return 'Customers Only';
      case 'partners': return 'Pilots / Drivers Only';
      case 'restaurants': return 'Restaurant Partners';
      case 'selected': return 'Selected Users';
      default: return 'Everyone (All App Users)';
    }
  };

  const getTypeLabel = (cType: string) => {
    switch (cType) {
      case 'promo': return 'Marketing / Promo';
      case 'alert': return 'Service Status Alert';
      case 'emergency': return '🚨 Emergency Broadcast';
      default: return 'Push Notification';
    }
  };

  const getEstimatedAudienceCount = () => {
    if (!audienceStats) return null;
    switch (target) {
      case 'customers': return audienceStats.customers;
      case 'partners': return audienceStats.partners;
      case 'restaurants': return audienceStats.restaurants;
      default: return audienceStats.totalEligible;
    }
  };

  // Fallback merge: if no backend campaigns yet, display audit logs
  const displayRecords: CampaignRecord[] = campaigns.length > 0
    ? campaigns
    : auditLogs
        .filter(log => log.action === 'BROADCAST_NOTIFICATION')
        .map(log => ({
          campaignId: log.logId,
          title: log.details.split(': ')[1] || 'StayDriv Announcement',
          body: log.details,
          targetGroup: 'all' as const,
          type: 'push' as const,
          adminEmail: log.adminEmail,
          status: 'in_app_delivered' as const,
          totalEligible: 1,
          successCount: 1,
          failureCount: 0,
          sentAt: log.timestamp,
          ipAddress: log.ipAddress,
          deliveryStats: {
            inAppDelivered: 1
          }
        }));

  return (
    <div className="page-container">
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
        <div>
          <h2>Push Notification Center</h2>
          <p style={{ color: 'var(--text-muted)', fontSize: '14px' }}>Draft and broadcast service alerts, marketing promos, and emergency announcements to the fleet.</p>
        </div>
        <div style={{ display: 'flex', gap: '8px' }}>
          <button 
            className="btn btn-secondary btn-sm" 
            onClick={() => setShowFcmModal(true)}
            style={{ display: 'flex', alignItems: 'center', gap: '6px', borderColor: audienceStats?.fcmConfigured ? 'var(--success)' : 'var(--warning)' }}
          >
            <span>{audienceStats?.fcmConfigured ? '✅ FCM Active' : '⚙️ Configure FCM Key'}</span>
          </button>
          <button 
            className="btn btn-secondary btn-sm" 
            onClick={loadCampaigns} 
            disabled={isLoadingHistory}
            style={{ display: 'flex', alignItems: 'center', gap: '6px' }}
          >
            <RefreshCw size={14} className={isLoadingHistory ? 'spin' : ''} />
            <span>Refresh</span>
          </button>
        </div>
      </div>

      {/* FCM Status Banner */}
      <div style={{
        marginTop: '12px',
        padding: '10px 16px',
        borderRadius: '10px',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        flexWrap: 'wrap',
        gap: '8px',
        backgroundColor: audienceStats?.fcmConfigured ? 'rgba(16, 185, 129, 0.08)' : 'rgba(245, 158, 11, 0.08)',
        border: `1px solid ${audienceStats?.fcmConfigured ? 'rgba(16, 185, 129, 0.3)' : 'rgba(245, 158, 11, 0.3)'}`
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px', fontSize: '13px' }}>
          <span style={{ fontSize: '16px' }}>{audienceStats?.fcmConfigured ? '🟢' : '🟡'}</span>
          <div>
            <strong style={{ color: audienceStats?.fcmConfigured ? 'var(--success)' : 'var(--warning)' }}>
              {audienceStats?.fcmConfigured 
                ? `FCM Cloud Messaging Active (Project: ${audienceStats.projectId || 'staydriv-74e8f'})`
                : 'FCM Gateway: In-App Inbox & Realtime Socket Active'}
            </strong>
            <p style={{ margin: 0, fontSize: '12px', color: 'var(--text-muted)' }}>
              {audienceStats?.fcmConfigured 
                ? 'System tray push notifications and in-app inbox are operating with Google FCM credentials.'
                : 'All broadcasts reach customer in-app notification bars and bells. Upload serviceAccountKey.json to enable lockscreen push.'}
            </p>
          </div>
        </div>
        {!audienceStats?.fcmConfigured && (
          <button 
            className="btn btn-primary btn-sm" 
            onClick={() => setShowFcmModal(true)}
            style={{ fontSize: '12px', padding: '4px 12px' }}
          >
            Configure Service Account
          </button>
        )}
      </div>

      {lastBroadcastResult && (
        <div style={{
          marginTop: '16px',
          padding: '14px 18px',
          borderRadius: '12px',
          backgroundColor: lastBroadcastResult.success ? 'var(--success-bg, rgba(16, 185, 129, 0.1))' : 'var(--error-bg, rgba(239, 68, 68, 0.1))',
          border: `1px solid ${lastBroadcastResult.success ? 'var(--success, #10B981)' : 'var(--error, #EF4444)'}`,
          display: 'flex',
          alignItems: 'center',
          gap: '12px',
          fontSize: '14px',
          fontWeight: 600,
          color: lastBroadcastResult.success ? 'var(--success, #10B981)' : 'var(--error, #EF4444)'
        }}>
          {lastBroadcastResult.success ? <CheckCircle2 size={18} /> : <XCircle size={18} />}
          <span>{lastBroadcastResult.message}</span>
        </div>
      )}

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1.2fr', gap: '24px', marginTop: '20px' }}>
        
        {/* Left Side - Push Broadcast Creator Form */}
        <div className="card">
          <div className="card-title">Compose Global Broadcast</div>
          <form onSubmit={handleOpenConfirm} style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
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
                  <option value="restaurants">Restaurant Partners Only</option>
                  <option value="selected">Selected Users</option>
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

            {/* Audience estimate helper */}
            <div style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              padding: '10px 14px',
              borderRadius: '8px',
              backgroundColor: 'var(--bg-input, #0f172a)',
              border: '1px solid var(--border, #334155)',
              fontSize: '12px',
              color: 'var(--text-muted, #94a3b8)'
            }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                <Users size={14} style={{ color: 'var(--primary, #3b82f6)' }} />
                <span>Target: <strong>{getTargetLabel(target)}</strong></span>
              </div>
              {getEstimatedAudienceCount() !== null && (
                <span>Eligible Devices: <strong style={{ color: 'var(--text-main, #f8fafc)' }}>{getEstimatedAudienceCount()}</strong></span>
              )}
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
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '14px' }}>
            <div className="card-title" style={{ margin: 0 }}>Sent Campaign History Logs</div>
            <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
              {displayRecords.length} {displayRecords.length === 1 ? 'campaign' : 'campaigns'} recorded
            </span>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '12px', maxHeight: '460px', overflowY: 'auto' }}>
            {displayRecords.length > 0 ? (
              displayRecords.map((history, idx) => {
                const isEmergency = history.type === 'emergency';
                const isPromo = history.type === 'promo';
                const isAlert = history.type === 'alert';

                return (
                  <div 
                    key={history.campaignId || idx}
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
                      {getAlertIcon(history.type)}
                    </div>
                    <div style={{ flex: 1 }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '4px' }}>
                        <span style={{ fontWeight: 600, fontSize: '13px' }}>{history.adminEmail}</span>
                        <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                          {new Date(history.sentAt).toLocaleString('en-IN')}
                        </span>
                      </div>

                      <div style={{ marginTop: '6px' }}>
                        <strong style={{ fontSize: '13px', color: 'var(--text-main)' }}>{history.title}</strong>
                        <p style={{ fontSize: '12.5px', color: 'var(--text-muted)', marginTop: '2px', lineHeight: 1.4 }}>
                          {history.body}
                        </p>
                      </div>

                      <div style={{ display: 'flex', gap: '6px', marginTop: '10px', flexWrap: 'wrap', alignItems: 'center' }}>
                        <span style={{ 
                          fontSize: '10.5px', 
                          backgroundColor: 'var(--bg-card)', 
                          padding: '2px 8px', 
                          borderRadius: '6px', 
                          border: '1px solid var(--border)',
                          fontWeight: 600,
                          color: isEmergency ? 'var(--error)' : isPromo ? 'var(--success)' : isAlert ? 'var(--warning)' : 'var(--primary)'
                        }}>
                          {getTypeLabel(history.type)}
                        </span>

                        <span style={{ 
                          fontSize: '10.5px', 
                          backgroundColor: 'var(--bg-card)', 
                          padding: '2px 8px', 
                          borderRadius: '6px', 
                          border: '1px solid var(--border)',
                          color: 'var(--text-muted)'
                        }}>
                          Audience: {getTargetLabel(history.targetGroup)}
                        </span>

                        <span style={{ 
                          fontSize: '10.5px', 
                          backgroundColor: 'var(--bg-card)', 
                          padding: '2px 8px', 
                          borderRadius: '6px', 
                          border: '1px solid var(--border)',
                          color: 'var(--text-muted)'
                        }}>
                          Recipients: <strong style={{ color: 'var(--text-main)' }}>{history.totalEligible ?? 0}</strong>
                          {history.deliveryStats?.fcmAccepted !== undefined && history.deliveryStats.fcmAccepted > 0 && (
                            <span style={{ marginLeft: '4px', color: 'var(--success)' }}>FCM: {history.deliveryStats.fcmAccepted}</span>
                          )}
                          {history.deliveryStats?.inAppDelivered !== undefined && (
                            <span style={{ marginLeft: '4px', color: '#60a5fa' }}>In-App: {history.deliveryStats.inAppDelivered}</span>
                          )}
                        </span>

                        {history.status && (
                          <span style={{ 
                            fontSize: '10.5px', 
                            padding: '2px 8px', 
                            borderRadius: '6px',
                            fontWeight: 700,
                            backgroundColor: history.status === 'fcm_accepted' 
                              ? 'rgba(16, 185, 129, 0.15)' 
                              : history.status === 'in_app_delivered' || history.status === 'sent'
                              ? 'rgba(37, 99, 235, 0.15)'
                              : history.status === 'partial' 
                              ? 'rgba(245, 158, 11, 0.15)' 
                              : 'rgba(239, 68, 68, 0.15)',
                            color: history.status === 'fcm_accepted' 
                              ? 'var(--success, #10B981)' 
                              : history.status === 'in_app_delivered' || history.status === 'sent'
                              ? '#60a5fa'
                              : history.status === 'partial' 
                              ? 'var(--warning, #F59E0B)' 
                              : 'var(--error, #EF4444)'
                          }}>
                            {history.status === 'fcm_accepted' 
                              ? 'FCM ACCEPTED' 
                              : history.status === 'in_app_delivered' || history.status === 'sent'
                              ? 'IN-APP DELIVERED'
                              : history.status.toUpperCase()}
                          </span>
                        )}

                        {history.ipAddress && (
                          <span style={{ fontSize: '10px', color: 'var(--text-muted)', marginLeft: 'auto' }}>
                            IP: {history.ipAddress}
                          </span>
                        )}
                      </div>
                    </div>
                  </div>
                );
              })
            ) : (
              <div style={{ textAlign: 'center', color: 'var(--text-muted)', padding: '40px' }}>
                No records of notification campaigns sent yet.
              </div>
            )}
          </div>
        </div>

      </div>

      {/* Confirmation Dialog Modal */}
      {showConfirmModal && (
        <div style={{
          position: 'fixed',
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          backgroundColor: 'rgba(0, 0, 0, 0.65)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 9999,
          backdropFilter: 'blur(3px)'
        }}>
          <div style={{
            backgroundColor: 'var(--bg-card, #1e293b)',
            borderRadius: '16px',
            border: '1px solid var(--border, #334155)',
            padding: '24px',
            width: '90%',
            maxWidth: '480px',
            boxShadow: '0 20px 25px -5px rgba(0, 0, 0, 0.5)'
          }}>
            <h3 style={{ margin: '0 0 8px 0', fontSize: '18px', fontWeight: 700, color: 'var(--text-main, #f8fafc)' }}>
              Confirm Push Broadcast
            </h3>
            <p style={{ fontSize: '13px', color: 'var(--text-muted, #94a3b8)', marginBottom: '16px' }}>
              Are you sure you want to dispatch this global push notification to all eligible devices in the selected audience?
            </p>

            <div style={{
              backgroundColor: 'var(--bg-input, #0f172a)',
              padding: '14px',
              borderRadius: '10px',
              border: '1px solid var(--border, #334155)',
              display: 'flex',
              flexDirection: 'column',
              gap: '8px',
              marginBottom: '20px'
            }}>
              <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
                Target: <strong style={{ color: 'var(--text-main)' }}>{getTargetLabel(target)}</strong>
              </div>
              <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
                Category: <strong style={{ color: 'var(--text-main)' }}>{getTypeLabel(type)}</strong>
              </div>
              <div style={{ height: '1px', backgroundColor: 'var(--border, #334155)', margin: '4px 0' }} />
              <div>
                <div style={{ fontSize: '11px', color: 'var(--text-muted)', textTransform: 'uppercase', fontWeight: 700 }}>Heading</div>
                <div style={{ fontSize: '13.5px', fontWeight: 600, color: 'var(--text-main)' }}>{title}</div>
              </div>
              <div>
                <div style={{ fontSize: '11px', color: 'var(--text-muted)', textTransform: 'uppercase', fontWeight: 700 }}>Message</div>
                <div style={{ fontSize: '12.5px', color: 'var(--text-muted)', lineHeight: 1.4 }}>{body}</div>
              </div>
            </div>

            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '12px' }}>
              <button 
                type="button" 
                className="btn btn-secondary" 
                onClick={() => setShowConfirmModal(false)}
                disabled={isBroadcasting}
              >
                Cancel
              </button>
              <button 
                type="button" 
                className={`btn ${type === 'emergency' ? 'btn-danger' : 'btn-primary'}`}
                onClick={handleConfirmDispatch}
                disabled={isBroadcasting}
                style={{ display: 'flex', alignItems: 'center', gap: '8px' }}
              >
                <Send size={15} />
                <span>{isBroadcasting ? 'Dispatching...' : 'Confirm & Dispatch'}</span>
              </button>
            </div>
          </div>
        </div>
      )}

      {/* FCM Configuration Modal */}
      {showFcmModal && (
        <div style={{
          position: 'fixed',
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          backgroundColor: 'rgba(0, 0, 0, 0.7)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 9999,
          backdropFilter: 'blur(3px)'
        }}>
          <div style={{
            backgroundColor: 'var(--bg-card, #1e293b)',
            borderRadius: '16px',
            border: '1px solid var(--border, #334155)',
            padding: '24px',
            width: '90%',
            maxWidth: '560px',
            boxShadow: '0 20px 25px -5px rgba(0, 0, 0, 0.5)'
          }}>
            <h3 style={{ margin: '0 0 8px 0', fontSize: '18px', fontWeight: 700, color: 'var(--text-main, #f8fafc)' }}>
              Configure Firebase Service Account
            </h3>
            <p style={{ fontSize: '13px', color: 'var(--text-muted, #94a3b8)', marginBottom: '16px', lineHeight: 1.4 }}>
              To enable direct system-tray push notifications on Android 13+ and iOS via Firebase Cloud Messaging HTTP v1, paste the content of your Firebase service account private key JSON file (e.g. for project <code>staydriv-74e8f</code>).
            </p>

            <form onSubmit={handleSaveFcmKey} style={{ display: 'flex', flexDirection: 'column', gap: '14px' }}>
              <div className="form-group">
                <label style={{ fontSize: '12px', fontWeight: 600 }}>Service Account JSON Content</label>
                <textarea 
                  rows={8}
                  style={{ fontFamily: 'monospace', fontSize: '11.5px' }}
                  placeholder='{\n  "type": "service_account",\n  "project_id": "staydriv-74e8f",\n  "private_key_id": "...",\n  "private_key": "-----BEGIN PRIVATE KEY-----\\n...",\n  "client_email": "firebase-adminsdk-...@staydriv-74e8f.iam.gserviceaccount.com"\n}'
                  value={fcmJsonInput}
                  onChange={(e) => setFcmJsonInput(e.target.value)}
                  required
                />
              </div>

              {fcmSaveResult && (
                <div style={{
                  padding: '10px 14px',
                  borderRadius: '8px',
                  fontSize: '12.5px',
                  fontWeight: 600,
                  backgroundColor: fcmSaveResult.success ? 'rgba(16, 185, 129, 0.15)' : 'rgba(239, 68, 68, 0.15)',
                  border: `1px solid ${fcmSaveResult.success ? 'var(--success)' : 'var(--error)'}`,
                  color: fcmSaveResult.success ? '#34d399' : '#f87171'
                }}>
                  {fcmSaveResult.msg}
                </div>
              )}

              <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px', marginTop: '6px' }}>
                <button 
                  type="button" 
                  className="btn btn-secondary" 
                  onClick={() => {
                    setShowFcmModal(false);
                    setFcmJsonInput('');
                    setFcmSaveResult(null);
                  }}
                  disabled={isSavingFcm}
                >
                  Cancel
                </button>
                <button 
                  type="submit" 
                  className="btn btn-primary"
                  disabled={isSavingFcm || !fcmJsonInput.trim()}
                >
                  {isSavingFcm ? 'Validating & Saving...' : 'Save Service Account'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

    </div>
  );
};

export default Notifications;
