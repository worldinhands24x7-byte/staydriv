const mongoose = require('mongoose');
const { Readable } = require('stream');

let gridFSBucket = null;

/**
 * Initialize MongoDB GridFS Bucket
 * Can be called with a specific db instance or defaults to mongoose.connection.db
 */
function initGridFS(db) {
  try {
    const targetDb = db || (mongoose.connection && mongoose.connection.db);
    if (!targetDb) {
      console.warn('[STORAGE] MongoDB connection database not yet ready for GridFS');
      return null;
    }
    gridFSBucket = new mongoose.mongo.GridFSBucket(targetDb, {
      bucketName: 'uploads'
    });
    console.log('[STORAGE] MongoDB GridFS Bucket initialized successfully (bucket: uploads)');
    return gridFSBucket;
  } catch (err) {
    console.error('[STORAGE] Error initializing GridFS:', err.message);
    return null;
  }
}

// Auto-initialize when mongoose connects
if (mongoose.connection) {
  mongoose.connection.on('open', () => {
    initGridFS();
  });
}

/**
 * Upload a file Buffer into MongoDB GridFS
 * @param {Object} options
 * @param {Buffer} options.buffer - Raw binary buffer
 * @param {string} options.filename - Desired filename
 * @param {string} options.mimetype - MIME type of the file
 * @param {Object} [options.metadata] - Additional metadata (uid, documentType, etc.)
 * @returns {Promise<Object>} Uploaded file details
 */
async function uploadFromBuffer({ buffer, filename, mimetype, metadata = {} }) {
  if (!gridFSBucket) {
    initGridFS();
  }
  if (!gridFSBucket) {
    throw new Error('MongoDB GridFS storage is currently unavailable');
  }

  return new Promise((resolve, reject) => {
    const safeFilename = filename.replace(/[^a-zA-Z0-9._-]/g, '_');
    const uploadStream = gridFSBucket.openUploadStream(safeFilename, {
      contentType: mimetype || 'application/octet-stream',
      metadata: {
        ...metadata,
        uploadedAt: new Date()
      }
    });

    const fileId = uploadStream.id;

    const readable = new Readable();
    readable._read = () => {};
    readable.push(buffer);
    readable.push(null);

    uploadStream.on('error', (err) => {
      console.error('[STORAGE] GridFS stream upload error:', err.message);
      reject(err);
    });

    uploadStream.on('finish', () => {
      console.log(`[STORAGE] Uploaded to GridFS: id=${fileId}, name=${safeFilename}, size=${buffer.length} bytes`);
      resolve({
        fileId: fileId.toString(),
        filename: safeFilename,
        contentType: mimetype || 'application/octet-stream',
        length: buffer.length,
        uploadDate: new Date()
      });
    });

    readable.pipe(uploadStream);
  });
}

/**
 * Stream a file from GridFS to an HTTP response
 * @param {string} fileId - MongoDB ObjectId string
 * @param {Object} res - Express response object
 */
async function downloadStream(fileId, res) {
  if (!gridFSBucket) {
    initGridFS();
  }
  if (!gridFSBucket) {
    return res.status(503).json({ success: false, message: 'Storage unavailable' });
  }

  let objId;
  try {
    objId = new mongoose.mongo.ObjectId(fileId);
  } catch (e) {
    return res.status(400).json({ success: false, message: 'Invalid file ID format' });
  }

  try {
    const files = await gridFSBucket.find({ _id: objId }).toArray();
    if (!files || files.length === 0) {
      return res.status(404).json({ success: false, message: 'File not found' });
    }

    const file = files[0];
    const safeContentType = file.contentType || (file.metadata && file.metadata.contentType) || (file.filename.endsWith('.pdf') ? 'application/pdf' : file.filename.endsWith('.png') ? 'image/png' : 'image/jpeg');
    res.setHeader('Content-Type', safeContentType);
    res.setHeader('Content-Length', file.length);
    res.setHeader('Content-Disposition', `inline; filename="${encodeURIComponent(file.filename)}"`);
    res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');

    const download = gridFSBucket.openDownloadStream(objId);
    download.on('error', (err) => {
      console.error('[STORAGE] GridFS download stream error:', err.message);
      if (!res.headersSent) {
        res.status(500).json({ success: false, message: 'Error streaming file' });
      }
    });

    download.pipe(res);
  } catch (err) {
    console.error('[STORAGE] GridFS find error:', err.message);
    if (!res.headersSent) {
      res.status(500).json({ success: false, message: 'Storage query error' });
    }
  }
}

/**
 * Delete a file from GridFS by ID
 * @param {string} fileId
 */
async function deleteFile(fileId) {
  if (!gridFSBucket) {
    initGridFS();
  }
  if (!gridFSBucket || !fileId) return false;

  try {
    const objId = new mongoose.mongo.ObjectId(fileId);
    await gridFSBucket.delete(objId);
    console.log(`[STORAGE] Deleted file from GridFS: ${fileId}`);
    return true;
  } catch (err) {
    console.warn(`[STORAGE] Could not delete file ${fileId}:`, err.message);
    return false;
  }
}

module.exports = {
  initGridFS,
  uploadFromBuffer,
  downloadStream,
  deleteFile
};
