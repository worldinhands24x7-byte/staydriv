const express = require('express');
const router = express.Router();
const pushNotificationService = require('../services/pushNotificationService');

module.exports = function(io, User) {

  // 1. Register or refresh device push token
  router.post('/register-token', async (req, res) => {
    try {
      const { token, uid, phone, role, platform, appType } = req.body;
      if (!token) {
        return res.status(400).json({ success: false, message: 'Device push token is required' });
      }

      const device = await pushNotificationService.registerDeviceToken({
        token,
        uid,
        phone,
        role,
        platform,
        appType
      }, User);

      return res.status(200).json({
        success: true,
        message: 'Push notification token registered successfully',
        device: {
          token: device.token,
          role: device.role,
          platform: device.platform,
          topics: device.topics,
          isActive: device.isActive
        }
      });
    } catch (err) {
      console.error('[API /register-token] Error:', err);
      return res.status(400).json({ success: false, message: err.message });
    }
  });

  // 2. Unregister device push token (logout / app removal)
  router.post('/unregister-token', async (req, res) => {
    try {
      const { token } = req.body;
      if (!token) {
        return res.status(400).json({ success: false, message: 'Token is required' });
      }

      await pushNotificationService.unregisterDeviceToken(token);
      return res.status(200).json({ success: true, message: 'Token unregistered' });
    } catch (err) {
      console.error('[API /unregister-token] Error:', err);
      return res.status(500).json({ success: false, message: err.message });
    }
  });

  // 3. Dispatch broadcast campaign from Admin Console
  router.post('/broadcast', async (req, res) => {
    try {
      const { title, body, targetGroup, type, destination, adminEmail, adminName } = req.body;

      if (!title || !title.trim()) {
        return res.status(400).json({ success: false, message: 'Notification title is required' });
      }
      if (!body || !body.trim()) {
        return res.status(400).json({ success: false, message: 'Message content body is required' });
      }

      const clientIp = req.headers['x-forwarded-for'] || req.socket.remoteAddress || '127.0.0.1';

      const result = await pushNotificationService.broadcastCampaign({
        title,
        body,
        targetGroup: targetGroup || 'all',
        type: type || 'push',
        destination: destination || { type: 'none' },
        adminEmail: adminEmail || req.user?.email || 'admin@staydriv.com',
        adminName: adminName || req.user?.name || 'Super Admin',
        ipAddress: typeof clientIp === 'string' ? clientIp.split(',')[0].trim() : '127.0.0.1',
        metadata: {
          userAgent: req.headers['user-agent']
        }
      }, io);

      return res.status(200).json(result);
    } catch (err) {
      console.error('[API /broadcast] Error:', err);
      return res.status(500).json({ success: false, message: err.message });
    }
  });

  // 4. Customer / Partner In-App Notification Inbox
  router.get('/inbox', async (req, res) => {
    try {
      const role = req.query.role || 'customer';
      const phone = req.query.phone || null;
      const uid = req.query.uid || null;
      const limit = parseInt(req.query.limit) || 50;

      const inboxData = await pushNotificationService.getCustomerInbox({
        role,
        phone,
        uid,
        limit
      });

      return res.status(200).json(inboxData);
    } catch (err) {
      console.error('[API /inbox] Error:', err);
      return res.status(500).json({ success: false, message: err.message });
    }
  });

  // 5. Mark notification(s) as read
  router.post('/mark-read', async (req, res) => {
    try {
      const { notificationId, phone, uid, markAll, role } = req.body;

      if (!phone && !uid) {
        return res.status(400).json({ success: false, message: 'Phone or UID required' });
      }

      const result = await pushNotificationService.markNotificationRead({
        notificationId,
        phone,
        uid,
        markAll: Boolean(markAll),
        role: role || 'customer'
      });

      return res.status(200).json(result);
    } catch (err) {
      console.error('[API /mark-read] Error:', err);
      return res.status(500).json({ success: false, message: err.message });
    }
  });

  // 6. Get sent campaign history logs
  router.get('/campaigns', async (req, res) => {
    try {
      const limit = parseInt(req.query.limit) || 100;
      const campaigns = await pushNotificationService.getCampaignHistory(limit);
      return res.status(200).json({ success: true, campaigns });
    } catch (err) {
      console.error('[API /campaigns] Error:', err);
      return res.status(500).json({ success: false, message: err.message });
    }
  });

  // 7. Get audience stats for composer
  router.get('/stats', async (req, res) => {
    try {
      const stats = await pushNotificationService.getAudienceStats();
      return res.status(200).json({ success: true, stats });
    } catch (err) {
      console.error('[API /stats] Error:', err);
      return res.status(500).json({ success: false, message: err.message });
    }
  });

  // 8. Configure Firebase Service Account for FCM HTTP v1 push
  router.post('/configure-fcm', async (req, res) => {
    try {
      let { serviceAccountJson } = req.body;
      if (!serviceAccountJson) {
        return res.status(400).json({ success: false, message: 'serviceAccountJson is required' });
      }

      let parsed = null;
      if (typeof serviceAccountJson === 'string') {
        try {
          parsed = JSON.parse(serviceAccountJson);
        } catch (e) {
          return res.status(400).json({ success: false, message: 'Invalid JSON format: ' + e.message });
        }
      } else {
        parsed = serviceAccountJson;
      }

      if (!parsed.project_id || !parsed.private_key) {
        return res.status(400).json({
          success: false,
          message: 'Service account JSON must contain project_id and private_key'
        });
      }

      const fs = require('fs');
      const path = require('path');
      const savePaths = [
        path.join(__dirname, '..', 'serviceAccountKey.json'),
        path.join('/opt/staydriv/serviceAccountKey.json')
      ];

      for (const sp of savePaths) {
        try {
          fs.writeFileSync(sp, JSON.stringify(parsed, null, 2), 'utf8');
        } catch (_) {}
      }

      // Re-initialize Firebase Admin
      pushNotificationService.initFirebase();

      return res.status(200).json({
        success: true,
        message: `Firebase Service Account configured successfully for project: ${parsed.project_id}`,
        projectId: parsed.project_id,
        fcmConfigured: pushNotificationService.firebaseInitialized
      });
    } catch (err) {
      console.error('[API /configure-fcm] Error:', err);
      return res.status(500).json({ success: false, message: err.message });
    }
  });

  return router;
};
