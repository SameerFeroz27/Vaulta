const multer = require('multer');
const path = require('path');
const crypto = require('crypto');
const { sendError } = require('../utils/response');

const UPLOAD_DIR = process.env.UPLOAD_DIR || './uploads';
const MAX_FILE_SIZE_MB = parseInt(process.env.MAX_FILE_SIZE_MB || '10', 10);
const MAX_FILE_SIZE_BYTES = MAX_FILE_SIZE_MB * 1024 * 1024;

const ALLOWED_MIME_TYPES = [
  'image/jpeg',
  'image/jpg',
  'image/png',
  'image/webp',
  'image/gif',
  'image/bmp',
];

// Disk storage with random filenames to avoid collisions
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, UPLOAD_DIR);
  },
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname) || '.jpg';
    const randomName = crypto.randomBytes(16).toString('hex');
    cb(null, `${randomName}${ext}`);
  },
});

// File filter — only allow image MIME types
const fileFilter = (req, file, cb) => {
  let mimetype = file.mimetype;

  // Fallback: infer MIME type from extension when client sends octet-stream
  if (mimetype === 'application/octet-stream') {
    const ext = path.extname(file.originalname).toLowerCase();
    const extToMime = {
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.png': 'image/png',
      '.webp': 'image/webp',
      '.gif': 'image/gif',
      '.bmp': 'image/bmp',
    };
    mimetype = extToMime[ext] || mimetype;
  }

  if (ALLOWED_MIME_TYPES.includes(mimetype)) {
    file.mimetype = mimetype;
    cb(null, true);
  } else {
    cb(new Error(`Unsupported file type: ${file.mimetype}. Allowed: ${ALLOWED_MIME_TYPES.join(', ')}`), false);
  }
};

const upload = multer({
  storage,
  fileFilter,
  limits: {
    fileSize: MAX_FILE_SIZE_BYTES,
  },
});

/**
 * Middleware for single receipt image upload.
 * Field name: "receipt"
 */
const uploadReceipt = (req, res, next) => {
  upload.single('receipt')(req, res, (err) => {
    if (err) {
      if (err.code === 'LIMIT_FILE_SIZE') {
        return sendError(
          res,
          `File size exceeds the ${MAX_FILE_SIZE_MB}MB limit`,
          'FILE_TOO_LARGE',
          413
        );
      }
      return sendError(res, err.message || 'File upload failed', 'UPLOAD_ERROR', 400);
    }
    if (!req.file) {
      return sendError(res, 'No receipt image provided. Use field name "receipt"', 'NO_FILE', 400);
    }
    next();
  });
};

module.exports = { uploadReceipt, UPLOAD_DIR, MAX_FILE_SIZE_MB };
