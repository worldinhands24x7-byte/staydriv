let admin = null;
try {
  admin = require('firebase-admin');
} catch (e) {
  console.warn('[PUSH] firebase-admin package not loaded:', e.message);
}

const fs = require('fs');
const path = require('path');
const DeviceToken = require('../models/DeviceToken');
const NotificationCampaign = require('../models/NotificationCampaign');
const InAppNotification = require('../models/InAppNotification');

class PushNotificationService {
  constructor() {
    this.firebaseInitialized = false;
    this.firebaseProjectId = null;
    this.initFirebase();
  }

  initFirebase() {
    try {
      if (!admin) {
        console.log('[PUSH] Firebase Admin SDK running in In-App / Socket mode (admin package not loaded)');
        return;
      }

      if (admin.apps && Array.isArray(admin.apps) && admin.apps.length > 0) {
        this.firebaseInitialized = true;
        this.firebaseProjectId = admin.apps[0]?.options?.projectId || 'staydriv-74e8f';
        return;
      }

      let serviceAccount = null;

      // 1. Check environment variable for direct JSON content
      if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
        try {
          serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
        } catch (e) {
          console.error('[PUSH] Failed to parse FIREBASE_SERVICE_ACCOUNT_JSON:', e.message);
        }
      }

      // 2. Check environment variable for file path
      if (!serviceAccount && process.env.FIREBASE_SERVICE_ACCOUNT_PATH) {
        const filePath = path.resolve(process.env.FIREBASE_SERVICE_ACCOUNT_PATH);
        if (fs.existsSync(filePath)) {
          serviceAccount = JSON.parse(fs.readFileSync(filePath, 'utf8'));
        }
      }

      // 3. Check default locations in project
      if (!serviceAccount) {
        const potentialPaths = [
          path.join(__dirname, '..', 'serviceAccountKey.json'),
          path.join(__dirname, '..', 'staydriv-firebase-adminsdk.json'),
          path.join(__dirname, '..', 'firebase-service-account.json'),
          path.join('/opt/staydriv/serviceAccountKey.json'),
          path.join('/opt/staydriv/staydriv-firebase-adminsdk.json')
        ];

        for (const p of potentialPaths) {
          if (fs.existsSync(p)) {
            try {
              serviceAccount = JSON.parse(fs.readFileSync(p, 'utf8'));
              break;
            } catch (_) {}
          }
        }
      }

      if (serviceAccount && serviceAccount.project_id && serviceAccount.private_key) {
        admin.initializeApp({
          credential: admin.credential.cert(serviceAccount)
        });
        this.firebaseInitialized = true;
        this.firebaseProjectId = serviceAccount.project_id;
        console.log(`[PUSH] Firebase Admin SDK initialized successfully for project: ${serviceAccount.project_id}`);
      } else {
        console.log('[PUSH] Firebase Admin SDK in In-App Inbox mode (No service account private key found)');
      }
    } catch (err) {
      console.warn('[PUSH] Firebase Admin init notice:', err.message);
    }
  }

  /**
   * Register or update a device FCM push token
   */
  async registerDeviceToken({ token, uid, phone, role = 'customer', platform = 'android', appType = 'staydriv_combined' }, User) {
    if (!token || typeof token !== 'string') {
      throw new Error('Valid push token is required');
    }

    const cleanToken = token.trim();
    
    // Validate real token format - ignore obvious mock or test tokens
    if (cleanToken.startsWith('fcm_test_') || cleanToken.length < 30) {
      throw new Error('Invalid FCM token format: Real device registration token required');
    }

    const cleanRole = ['customer', 'partner', 'restaurant', 'admin'].includes(role?.toLowerCase())
      ? role.toLowerCase()
      : 'customer';

    const topics = ['all'];
    if (cleanRole === 'customer') topics.push('customers');
    if (cleanRole === 'partner') topics.push('partners');
    if (cleanRole === 'restaurant') topics.push('restaurants');

    const updateDoc = {
      token: cleanToken,
      uid: uid || null,
      phone: phone || null,
      role: cleanRole,
      platform: platform || 'android',
      appType: appType || 'staydriv_combined',
      topics,
      isActive: true,
      lastSeenAt: new Date()
    };

    const device = await DeviceToken.findOneAndUpdate(
      { token: cleanToken },
      { $set: updateDoc },
      { upsert: true, new: true }
    );

    // Sync to User record if model available
    if (User && (uid || phone)) {
      try {
        const query = uid ? { uid } : { phone };
        await User.updateOne(query, { $set: { fcmToken: cleanToken, updatedAt: new Date() } });
      } catch (err) {
        console.warn('[PUSH] Could not sync fcmToken to User:', err.message);
      }
    }

    // Subscribe to Firebase topics if Firebase Admin initialized
    if (this.firebaseInitialized && admin) {
      try {
        for (const topic of topics) {
          await admin.messaging().subscribeToTopic([cleanToken], topic);
        }
      } catch (err) {
        console.warn(`[PUSH] Topic subscription notice for ${cleanToken.substring(0, 10)}...:`, err.message);
      }
    }

    return device;
  }

  /**
   * Mark token inactive (on logout or app uninstall)
   */
  async unregisterDeviceToken(token) {
    if (!token) return null;
    return await DeviceToken.findOneAndUpdate(
      { token: token.trim() },
      { $set: { isActive: false, lastSeenAt: new Date() } }
    );
  }

  /**
   * Broadcast a notification campaign to the targeted audience
   */
  async broadcastCampaign({
    title,
    body,
    targetGroup = 'all',
    type = 'push',
    destination = { type: 'none' },
    adminEmail = 'admin@staydriv.com',
    adminName = 'Super Admin',
    ipAddress = '127.0.0.1',
    metadata = {}
  }, io) {
    if (!title || !title.trim()) throw new Error('Notification title is required');
    if (!body || !body.trim()) throw new Error('Notification message body is required');

    const cleanTitle = title.trim();
    const cleanBody = body.trim();
    const cleanTarget = ['all', 'customers', 'partners', 'restaurants', 'selected'].includes(targetGroup)
      ? targetGroup
      : 'all';
    const cleanType = ['push', 'promo', 'alert', 'emergency'].includes(type) ? type : 'push';

    const campaignId = `CAMP-${Date.now()}-${Math.random().toString(36).substring(2, 7).toUpperCase()}`;
    const notificationId = `NOTIF-${Date.now()}-${Math.random().toString(36).substring(2, 7).toUpperCase()}`;

    // 1. Determine eligible device tokens from database (excluding fake test tokens)
    const tokenQuery = { 
      isActive: true,
      token: { $not: /^fcm_test_/ }
    };
    if (cleanTarget === 'customers') {
      tokenQuery.role = 'customer';
    } else if (cleanTarget === 'partners') {
      tokenQuery.role = 'partner';
    } else if (cleanTarget === 'restaurants') {
      tokenQuery.role = 'restaurant';
    }

    const eligibleDevices = await DeviceToken.find(tokenQuery).lean();
    const totalEligible = eligibleDevices.length;
    const tokens = eligibleDevices.map(d => d.token).filter(Boolean);

    // 2. Persist In-App Notification Record for Customer / Partner Inboxes
    const inAppNotif = new InAppNotification({
      notificationId,
      campaignId,
      title: cleanTitle,
      body: cleanBody,
      type: cleanType,
      targetGroup: cleanTarget,
      destination: destination || { type: 'none' },
      adminEmail,
      metadata,
      createdAt: new Date()
    });
    await inAppNotif.save();

    let fcmAcceptedCount = 0;
    let fcmFailureCount = 0;
    let invalidTokensCount = 0;

    // 3. Dispatch FCM Push Notifications if Firebase Admin is initialized
    if (this.firebaseInitialized && admin && tokens.length > 0) {
      const batchSize = 500;
      for (let i = 0; i < tokens.length; i += batchSize) {
        const batch = tokens.slice(i, i + batchSize);
        try {
          const multicastPayload = {
            tokens: batch,
            notification: {
              title: cleanTitle,
              body: cleanBody
            },
            data: {
              notificationId,
              campaignId,
              type: cleanType,
              targetGroup: cleanTarget,
              title: cleanTitle,
              body: cleanBody,
              click_action: 'FLUTTER_NOTIFICATION_CLICK',
              timestamp: new Date().toISOString()
            },
            android: {
              priority: cleanType === 'emergency' ? 'high' : 'normal',
              notification: {
                channelId: 'staydriv_general_notifications',
                icon: 'ic_launcher',
                color: '#1E60FF',
                sound: 'default'
              }
            },
            apns: {
              payload: {
                aps: {
                  sound: 'default',
                  badge: 1
                }
              }
            }
          };

          const response = await admin.messaging().sendEachForMulticast(multicastPayload);
          fcmAcceptedCount += response.successCount;
          fcmFailureCount += response.failureCount;

          // Check individual response errors to remove invalid tokens safely
          if (response.failureCount > 0 && Array.isArray(response.responses)) {
            for (let idx = 0; idx < response.responses.length; idx++) {
              const resp = response.responses[idx];
              if (!resp.success && resp.error) {
                const errCode = resp.error.code;
                if (
                  errCode === 'messaging/invalid-registration-token' ||
                  errCode === 'messaging/registration-token-not-registered'
                ) {
                  const badToken = batch[idx];
                  await DeviceToken.updateOne({ token: badToken }, { $set: { isActive: false } });
                  invalidTokensCount++;
                }
              }
            }
          }
        } catch (batchErr) {
          console.error('[PUSH] FCM Multicast dispatch error:', batchErr.message);
          fcmFailureCount += batch.length;
        }
      }
    }

    // 4. Dispatch Real-Time Socket.IO notification to all active apps
    if (io) {
      const socketPayload = {
        notificationId,
        campaignId,
        title: cleanTitle,
        body: cleanBody,
        type: cleanType,
        targetGroup: cleanTarget,
        destination: inAppNotif.destination,
        timestamp: inAppNotif.createdAt.toISOString()
      };

      io.emit('new_in_app_notification', socketPayload);
      if (cleanTarget === 'all') {
        io.emit('push_notification_broadcast', socketPayload);
      } else if (cleanTarget === 'customers') {
        io.emit('push_notification_customers', socketPayload);
      } else if (cleanTarget === 'partners') {
        io.emit('push_notification_partners', socketPayload);
      }
    }

    // 5. Determine Accurate Status
    let status = 'in_app_delivered';
    if (this.firebaseInitialized) {
      if (fcmFailureCount > 0 && fcmAcceptedCount > 0) {
        status = 'partial';
      } else if (fcmAcceptedCount > 0) {
        status = 'fcm_accepted';
      } else if (fcmFailureCount > 0 && tokens.length > 0) {
        status = 'failed';
      } else {
        status = 'in_app_delivered';
      }
    }

    // 6. Record Campaign into Sent Campaign History Logs
    const campaign = new NotificationCampaign({
      campaignId,
      title: cleanTitle,
      body: cleanBody,
      targetGroup: cleanTarget,
      type: cleanType,
      adminEmail,
      adminName,
      ipAddress,
      status,
      totalEligible,
      successCount: this.firebaseInitialized ? fcmAcceptedCount : totalEligible,
      failureCount: fcmFailureCount,
      sentAt: new Date(),
      deliveryStats: {
        inAppDelivered: totalEligible,
        fcmAccepted: fcmAcceptedCount,
        fcmFailed: fcmFailureCount,
        invalidTokens: invalidTokensCount,
        opened: 0
      },
      metadata: {
        ...metadata,
        notificationId,
        fcmConfigured: this.firebaseInitialized,
        projectId: this.firebaseProjectId,
        dispatchMode: this.firebaseInitialized ? 'fcm_and_in_app_inbox' : 'in_app_inbox_only'
      }
    });

    await campaign.save();

    return {
      success: true,
      campaignId,
      notificationId,
      campaign,
      totalEligible,
      inAppDelivered: totalEligible,
      fcmAccepted: fcmAcceptedCount,
      fcmFailed: fcmFailureCount,
      invalidTokens: invalidTokensCount,
      fcmConfigured: this.firebaseInitialized,
      status
    };
  }

  /**
   * Fetch customer inbox notifications with read/unread tracking
   */
  async getCustomerInbox({ role = 'customer', phone, uid, limit = 50 }) {
    const cleanRole = role === 'partner' ? 'partners' : 'customers';
    const targetGroups = ['all', cleanRole];

    const notifications = await InAppNotification.find({
      targetGroup: { $in: targetGroups }
    })
      .sort({ createdAt: -1 })
      .limit(limit)
      .lean();

    const mapped = notifications.map(n => {
      const isRead = Array.isArray(n.readBy) && n.readBy.some(r => 
        (phone && r.phone === phone) || 
        (uid && r.uid === uid)
      );

      return {
        id: n.notificationId,
        campaignId: n.campaignId,
        title: n.title,
        body: n.body,
        type: n.type,
        targetGroup: n.targetGroup,
        destination: n.destination,
        createdAt: n.createdAt,
        isRead
      };
    });

    const unreadCount = mapped.filter(n => !n.isRead).length;
    const latestNotification = mapped.length > 0 ? mapped[0] : null;

    return {
      success: true,
      unreadCount,
      latestNotification,
      notifications: mapped
    };
  }

  /**
   * Mark notification(s) as read for a customer or partner
   */
  async markNotificationRead({ notificationId, phone, uid, markAll = false, role = 'customer' }) {
    if (!phone && !uid) {
      throw new Error('Phone or UID is required to mark notifications as read');
    }

    const reader = {
      phone: phone || null,
      uid: uid || null,
      readAt: new Date()
    };

    if (markAll) {
      const cleanRole = role === 'partner' ? 'partners' : 'customers';
      await InAppNotification.updateMany(
        { targetGroup: { $in: ['all', cleanRole] } },
        { $push: { readBy: reader } }
      );
    } else if (notificationId) {
      await InAppNotification.updateOne(
        { notificationId },
        { $push: { readBy: reader } }
      );
    }

    return await this.getCustomerInbox({ role, phone, uid });
  }

  /**
   * Fetch sent campaign history logs
   */
  async getCampaignHistory(limit = 100) {
    return await NotificationCampaign.find()
      .sort({ sentAt: -1 })
      .limit(limit)
      .lean();
  }

  /**
   * Fetch audience & token stats (excluding invalid test strings)
   */
  async getAudienceStats() {
    const validQuery = { 
      isActive: true,
      token: { $not: /^fcm_test_/ }
    };

    const [total, customers, partners, restaurants, android, ios] = await Promise.all([
      DeviceToken.countDocuments(validQuery),
      DeviceToken.countDocuments({ ...validQuery, role: 'customer' }),
      DeviceToken.countDocuments({ ...validQuery, role: 'partner' }),
      DeviceToken.countDocuments({ ...validQuery, role: 'restaurant' }),
      DeviceToken.countDocuments({ ...validQuery, platform: 'android' }),
      DeviceToken.countDocuments({ ...validQuery, platform: 'ios' })
    ]);

    return {
      totalEligible: total,
      customers,
      partners,
      restaurants,
      fcmConfigured: this.firebaseInitialized,
      projectId: this.firebaseProjectId,
      platforms: {
        android,
        ios
      }
    };
  }
}

module.exports = new PushNotificationService();
