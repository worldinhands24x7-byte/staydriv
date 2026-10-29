const express = require('express');
const router = express.Router();
const crypto = require('crypto');
const path = require('path');
const fs = require('fs');
const mongoose = require('mongoose');
const Promotion = require('../models/Promotion');
const storageService = require('../services/storageService');

// Helper to get Socket.io instance safely
function getIo(req) {
  return req.app.get('io');
}

// Ensure public/uploads directory exists
const uploadsDir = path.join(__dirname, '..', 'public', 'uploads');
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}

// -------------------------------------------------------------
// PUBLIC / CUSTOMER PROMOTION ENDPOINTS
// -------------------------------------------------------------

/**
 * GET /api/promotions/active
 * Query params:
 *   - screen: 'home' | 'food' (optional, defaults to returning for both/all)
 */
router.get('/active', async (req, res) => {
  try {
    const { screen } = req.query;
    const now = new Date();

    const query = {
      isDeleted: false,
      isActive: true,
      startAt: { $lte: now },
      $or: [
        { endAt: null },
        { endAt: { $gte: now } }
      ]
    };

    if (screen && ['home', 'food'].includes(screen.toLowerCase())) {
      query.targetScreen = { $in: [screen.toLowerCase(), 'both'] };
    }

    const promotions = await Promotion.find(query)
      .sort({ displayOrder: 1, createdAt: -1 })
      .lean();

    res.json({
      success: true,
      count: promotions.length,
      screen: screen || 'all',
      promotions: promotions.map(p => ({
        promotionId: p.promotionId,
        title: p.title,
        description: p.description || '',
        mediaType: p.mediaType || 'image',
        mediaUrl: p.mediaUrl,
        thumbnailUrl: p.thumbnailUrl || '',
        targetScreen: p.targetScreen,
        destinationType: p.destinationType || 'none',
        destinationId: p.destinationId || '',
        destinationUrl: p.destinationUrl || '',
        offerText: p.offerText || '',
        buttonLabel: p.buttonLabel || '',
        displayOrder: p.displayOrder || 0,
        startAt: p.startAt,
        endAt: p.endAt
      }))
    });
  } catch (err) {
    console.error('[PROMOTIONS API] Error fetching active promotions:', err);
    res.status(500).json({ success: false, message: 'Failed to fetch active promotions: ' + err.message });
  }
});

/**
 * POST /api/promotions/:id/impression
 * Records a banner view/impression
 */
router.post('/:id/impression', async (req, res) => {
  try {
    const { id } = req.params;
    await Promotion.updateOne(
      { $or: [{ promotionId: id }, { _id: mongoose.isValidObjectId(id) ? id : null }] },
      { $inc: { impressionsCount: 1 } }
    );
    res.json({ success: true, message: 'Impression recorded' });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/promotions/:id/click
 * Records a banner click
 */
router.post('/:id/click', async (req, res) => {
  try {
    const { id } = req.params;
    await Promotion.updateOne(
      { $or: [{ promotionId: id }, { _id: mongoose.isValidObjectId(id) ? id : null }] },
      { $inc: { clicksCount: 1 } }
    );
    res.json({ success: true, message: 'Click recorded' });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// -------------------------------------------------------------
// ADMIN MANAGEMENT ENDPOINTS
// -------------------------------------------------------------

/**
 * GET /api/promotions/admin/all
 * Query params:
 *   - screen: 'home' | 'food' | 'both' | 'all'
 *   - status: 'active' | 'inactive' | 'all'
 *   - includeDeleted: 'true' | 'false'
 */
router.get('/admin/all', async (req, res) => {
  try {
    const { screen, status, includeDeleted } = req.query;
    const query = {};

    if (includeDeleted !== 'true') {
      query.isDeleted = false;
    }

    if (screen && screen !== 'all') {
      query.targetScreen = screen;
    }

    if (status === 'active') {
      query.isActive = true;
    } else if (status === 'inactive') {
      query.isActive = false;
    }

    const promotions = await Promotion.find(query)
      .sort({ displayOrder: 1, createdAt: -1 })
      .lean();

    // Summary stats
    const allNonDeleted = await Promotion.find({ isDeleted: false }).lean();
    const stats = {
      total: allNonDeleted.length,
      activeCount: allNonDeleted.filter(p => p.isActive).length,
      inactiveCount: allNonDeleted.filter(p => !p.isActive).length,
      homeCount: allNonDeleted.filter(p => p.targetScreen === 'home' || p.targetScreen === 'both').length,
      foodCount: allNonDeleted.filter(p => p.targetScreen === 'food' || p.targetScreen === 'both').length,
      bothCount: allNonDeleted.filter(p => p.targetScreen === 'both').length,
      totalImpressions: allNonDeleted.reduce((sum, p) => sum + (p.impressionsCount || 0), 0),
      totalClicks: allNonDeleted.reduce((sum, p) => sum + (p.clicksCount || 0), 0)
    };

    res.json({
      success: true,
      count: promotions.length,
      stats,
      promotions
    });
  } catch (err) {
    console.error('[PROMOTIONS API] Error listing admin promotions:', err);
    res.status(500).json({ success: false, message: 'Failed to list promotions: ' + err.message });
  }
});

/**
 * POST /api/promotions/admin/upload
 * Handles media upload for banners (JPG, JPEG, PNG, WEBP, GIF, MP4)
 */
router.post('/admin/upload', async (req, res) => {
  try {
    const { mediaData, fileName, mimeType } = req.body;
    if (!mediaData || !fileName) {
      return res.status(400).json({ success: false, message: 'mediaData (base64) and fileName are required' });
    }

    const ext = path.extname(fileName).toLowerCase();
    const allowedExtensions = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.mp4'];
    if (!allowedExtensions.includes(ext)) {
      return res.status(400).json({
        success: false,
        message: 'Unsupported format. Allowed formats: JPG, JPEG, PNG, WebP, GIF, MP4'
      });
    }

    let detectedMime = mimeType;
    if (!detectedMime) {
      if (ext === '.gif') detectedMime = 'image/gif';
      else if (ext === '.mp4') detectedMime = 'video/mp4';
      else if (ext === '.png') detectedMime = 'image/png';
      else if (ext === '.webp') detectedMime = 'image/webp';
      else detectedMime = 'image/jpeg';
    }

    let detectedMediaType = 'image';
    if (ext === '.gif' || detectedMime.includes('gif')) detectedMediaType = 'gif';
    else if (ext === '.mp4' || detectedMime.includes('video') || detectedMime.includes('mp4')) detectedMediaType = 'video';

    // Strip data URL scheme if present
    let rawBase64 = mediaData;
    if (mediaData.includes(';base64,')) {
      rawBase64 = mediaData.split(';base64,')[1];
    }

    const buffer = Buffer.from(rawBase64, 'base64');

    // Size limits: 25MB for GIF/Video, 10MB for static images
    const maxSize = (detectedMediaType === 'video' || detectedMediaType === 'gif')
      ? 25 * 1024 * 1024
      : 10 * 1024 * 1024;

    if (buffer.length > maxSize) {
      const limitMb = detectedMediaType === 'video' || detectedMediaType === 'gif' ? 25 : 10;
      return res.status(400).json({
        success: false,
        message: `File size (${(buffer.length / (1024 * 1024)).toFixed(1)}MB) exceeds limit of ${limitMb}MB`
      });
    }

    const randomHex = crypto.randomBytes(4).toString('hex');
    const safeBaseName = path.basename(fileName, ext).replace(/[^a-zA-Z0-9_-]/g, '_').substring(0, 30);
    const uniqueFileName = `promo_${Date.now()}_${randomHex}_${safeBaseName}${ext}`;

    // 1. Save locally to public/uploads
    const filePath = path.join(uploadsDir, uniqueFileName);
    fs.writeFileSync(filePath, buffer);

    // 2. Also persist to GridFS if available
    let gridFsFileId = null;
    try {
      if (storageService && typeof storageService.uploadFromBuffer === 'function') {
        const gridRes = await storageService.uploadFromBuffer({
          buffer,
          filename: uniqueFileName,
          mimetype: detectedMime,
          metadata: { documentType: 'promotion_media', originalName: fileName }
        });
        gridFsFileId = gridRes ? gridRes.fileId : null;
      }
    } catch (gridErr) {
      console.warn('[PROMOTIONS UPLOAD] GridFS backup notice:', gridErr.message);
    }

    const relativeUrl = `/uploads/${uniqueFileName}`;
    const fullUrl = `https://dk60tgl9yds4p.cloudfront.net${relativeUrl}`;

    res.json({
      success: true,
      message: 'Media uploaded successfully',
      url: fullUrl,
      relativeUrl,
      fileName: uniqueFileName,
      mediaType: detectedMediaType,
      mimeType: detectedMime,
      sizeBytes: buffer.length,
      gridFsFileId
    });
  } catch (err) {
    console.error('[PROMOTIONS API] Upload error:', err);
    res.status(500).json({ success: false, message: 'Upload failed: ' + err.message });
  }
});

/**
 * POST /api/promotions/admin/create
 * Creates and publishes a new promotion
 */
router.post('/admin/create', async (req, res) => {
  try {
    const {
      title,
      description,
      mediaType,
      mediaUrl,
      thumbnailUrl,
      targetScreen,
      destinationType,
      destinationId,
      destinationUrl,
      offerText,
      buttonLabel,
      startAt,
      endAt,
      displayOrder,
      isActive,
      createdBy
    } = req.body;

    if (!title || !title.trim()) {
      return res.status(400).json({ success: false, message: 'Promotion title is required' });
    }
    if (!mediaUrl || !mediaUrl.trim()) {
      return res.status(400).json({ success: false, message: 'Media URL or file is required' });
    }

    // Auto-detect mediaType if missing
    let finalMediaType = mediaType;
    if (!finalMediaType || !['image', 'gif', 'video'].includes(finalMediaType)) {
      const lower = mediaUrl.toLowerCase();
      if (lower.endsWith('.gif')) finalMediaType = 'gif';
      else if (lower.endsWith('.mp4')) finalMediaType = 'video';
      else finalMediaType = 'image';
    }

    const promotionId = `promo_${Date.now()}_${crypto.randomBytes(3).toString('hex')}`;

    const newPromotion = new Promotion({
      promotionId,
      title: title.trim(),
      description: (description || '').trim(),
      mediaType: finalMediaType,
      mediaUrl: mediaUrl.trim(),
      thumbnailUrl: (thumbnailUrl || '').trim(),
      targetScreen: ['home', 'food', 'both'].includes(targetScreen) ? targetScreen : 'both',
      destinationType: ['none', 'food_screen', 'restaurant', 'membership', 'ride_screen', 'parcel_screen', 'external_url', 'food', 'ride', 'parcel'].includes(destinationType) ? destinationType : 'none',
      destinationId: (destinationId || '').trim(),
      destinationUrl: (destinationUrl || '').trim(),
      offerText: (offerText || '').trim(),
      buttonLabel: (buttonLabel || '').trim(),
      startAt: startAt ? new Date(startAt) : new Date(),
      endAt: endAt ? new Date(endAt) : null,
      displayOrder: typeof displayOrder === 'number' ? displayOrder : (parseInt(displayOrder, 10) || 0),
      isActive: isActive !== undefined ? Boolean(isActive) : true,
      createdBy: createdBy || 'admin'
    });

    await newPromotion.save();

    // Broadcast update via Socket.IO
    const io = getIo(req);
    if (io) {
      io.emit('promotions_updated', {
        action: 'create',
        promotionId,
        targetScreen: newPromotion.targetScreen,
        timestamp: Date.now()
      });
    }

    res.status(201).json({
      success: true,
      message: 'Promotion created successfully',
      promotion: newPromotion
    });
  } catch (err) {
    console.error('[PROMOTIONS API] Create error:', err);
    res.status(500).json({ success: false, message: 'Failed to create promotion: ' + err.message });
  }
});

/**
 * PUT /api/promotions/admin/:id
 * Updates an existing promotion
 */
router.put('/admin/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const {
      title,
      description,
      mediaType,
      mediaUrl,
      thumbnailUrl,
      targetScreen,
      destinationType,
      destinationId,
      destinationUrl,
      offerText,
      buttonLabel,
      startAt,
      endAt,
      displayOrder,
      isActive
    } = req.body;

    const promotion = await Promotion.findOne({
      $or: [{ promotionId: id }, { _id: mongoose.isValidObjectId(id) ? id : null }],
      isDeleted: false
    });

    if (!promotion) {
      return res.status(404).json({ success: false, message: 'Promotion not found' });
    }

    if (title !== undefined) promotion.title = title.trim();
    if (description !== undefined) promotion.description = (description || '').trim();
    if (mediaType !== undefined && ['image', 'gif', 'video'].includes(mediaType)) {
      promotion.mediaType = mediaType;
    }
    if (mediaUrl !== undefined) promotion.mediaUrl = mediaUrl.trim();
    if (thumbnailUrl !== undefined) promotion.thumbnailUrl = (thumbnailUrl || '').trim();
    if (targetScreen !== undefined && ['home', 'food', 'both'].includes(targetScreen)) {
      promotion.targetScreen = targetScreen;
    }
    if (destinationType !== undefined && ['none', 'food_screen', 'restaurant', 'membership', 'ride_screen', 'parcel_screen', 'external_url', 'food', 'ride', 'parcel'].includes(destinationType)) {
      promotion.destinationType = destinationType;
    }
    if (destinationId !== undefined) promotion.destinationId = (destinationId || '').trim();
    if (destinationUrl !== undefined) promotion.destinationUrl = (destinationUrl || '').trim();
    if (offerText !== undefined) promotion.offerText = (offerText || '').trim();
    if (buttonLabel !== undefined) promotion.buttonLabel = (buttonLabel || '').trim();
    if (startAt !== undefined) promotion.startAt = startAt ? new Date(startAt) : new Date();
    if (endAt !== undefined) promotion.endAt = endAt ? new Date(endAt) : null;
    if (displayOrder !== undefined) {
      promotion.displayOrder = typeof displayOrder === 'number' ? displayOrder : (parseInt(displayOrder, 10) || 0);
    }
    if (isActive !== undefined) promotion.isActive = Boolean(isActive);

    await promotion.save();

    const io = getIo(req);
    if (io) {
      io.emit('promotions_updated', {
        action: 'update',
        promotionId: promotion.promotionId,
        targetScreen: promotion.targetScreen,
        timestamp: Date.now()
      });
    }

    res.json({
      success: true,
      message: 'Promotion updated successfully',
      promotion
    });
  } catch (err) {
    console.error('[PROMOTIONS API] Update error:', err);
    res.status(500).json({ success: false, message: 'Failed to update promotion: ' + err.message });
  }
});

/**
 * PATCH /api/promotions/admin/:id/status
 * Toggles or sets active status
 */
router.patch('/admin/:id/status', async (req, res) => {
  try {
    const { id } = req.params;
    const { isActive } = req.body;

    const promotion = await Promotion.findOne({
      $or: [{ promotionId: id }, { _id: mongoose.isValidObjectId(id) ? id : null }],
      isDeleted: false
    });

    if (!promotion) {
      return res.status(404).json({ success: false, message: 'Promotion not found' });
    }

    promotion.isActive = isActive !== undefined ? Boolean(isActive) : !promotion.isActive;
    await promotion.save();

    const io = getIo(req);
    if (io) {
      io.emit('promotions_updated', {
        action: 'status_change',
        promotionId: promotion.promotionId,
        isActive: promotion.isActive,
        timestamp: Date.now()
      });
    }

    res.json({
      success: true,
      message: `Promotion ${promotion.isActive ? 'activated' : 'deactivated'} successfully`,
      isActive: promotion.isActive,
      promotion
    });
  } catch (err) {
    console.error('[PROMOTIONS API] Status toggle error:', err);
    res.status(500).json({ success: false, message: 'Failed to update status: ' + err.message });
  }
});

/**
 * PATCH /api/promotions/admin/reorder
 * Bulk reorder promotions
 * Body: { items: [ { id: 'promo_123', displayOrder: 0 }, ... ] }
 */
router.patch('/admin/reorder', async (req, res) => {
  try {
    const { items } = req.body;
    if (!Array.isArray(items)) {
      return res.status(400).json({ success: false, message: 'items array is required' });
    }

    const updates = items.map(item => {
      const order = typeof item.displayOrder === 'number' ? item.displayOrder : (parseInt(item.displayOrder, 10) || 0);
      return Promotion.updateOne(
        { $or: [{ promotionId: item.id }, { _id: mongoose.isValidObjectId(item.id) ? item.id : null }] },
        { $set: { displayOrder: order } }
      );
    });

    await Promise.all(updates);

    const io = getIo(req);
    if (io) {
      io.emit('promotions_updated', {
        action: 'reorder',
        timestamp: Date.now()
      });
    }

    res.json({
      success: true,
      message: 'Promotions reordered successfully'
    });
  } catch (err) {
    console.error('[PROMOTIONS API] Reorder error:', err);
    res.status(500).json({ success: false, message: 'Failed to reorder promotions: ' + err.message });
  }
});

/**
 * DELETE /api/promotions/admin/:id
 * Soft deletes a promotion
 */
router.delete('/admin/:id', async (req, res) => {
  try {
    const { id } = req.params;

    const promotion = await Promotion.findOne({
      $or: [{ promotionId: id }, { _id: mongoose.isValidObjectId(id) ? id : null }]
    });

    if (!promotion) {
      return res.status(404).json({ success: false, message: 'Promotion not found' });
    }

    promotion.isDeleted = true;
    promotion.deletedAt = new Date();
    promotion.isActive = false;
    await promotion.save();

    const io = getIo(req);
    if (io) {
      io.emit('promotions_updated', {
        action: 'delete',
        promotionId: promotion.promotionId,
        timestamp: Date.now()
      });
    }

    res.json({
      success: true,
      message: 'Promotion deleted successfully (soft delete for audit history)',
      promotionId: promotion.promotionId
    });
  } catch (err) {
    console.error('[PROMOTIONS API] Delete error:', err);
    res.status(500).json({ success: false, message: 'Failed to delete promotion: ' + err.message });
  }
});

module.exports = router;
