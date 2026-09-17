const { sendError } = require('../utils/response');

function errorHandler(err, req, res, next) {
  console.error('[Error]', err);

  if (err.name === 'ZodError') {
    const details = err.errors.map((e) => ({
      field: e.path.join('.'),
      message: e.message,
    }));
    return sendError(res, 'Validation error', 'VALIDATION_ERROR', 400, details);
  }

  if (err.type === 'entity.parse.failed') {
    return sendError(res, 'Invalid JSON payload', 'INVALID_JSON', 400);
  }

  // Multer errors (file size limit, unexpected field, etc.)
  if (err.code === 'LIMIT_FILE_SIZE') {
    return sendError(res, 'File size exceeds the allowed limit', 'FILE_TOO_LARGE', 413);
  }
  if (err.code === 'LIMIT_UNEXPECTED_FILE') {
    return sendError(res, `Unexpected field name: ${err.field}. Use "receipt" for the image file`, 'UNEXPECTED_FIELD', 400);
  }

  const statusCode = err.statusCode || 500;
  const message = err.message || 'Internal Server Error';
  const code = err.code || 'INTERNAL_ERROR';

  return sendError(res, message, code, statusCode, err.details || []);
}

module.exports = errorHandler;
