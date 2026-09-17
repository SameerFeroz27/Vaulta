/**
 * Standard API response helper functions
 */
function sendSuccess(res, data = {}, statusCode = 200) {
  return res.status(statusCode).json({
    success: true,
    data,
  });
}

function sendError(res, message, code = 'INTERNAL_ERROR', statusCode = 500, details = []) {
  return res.status(statusCode).json({
    success: false,
    error: {
      code,
      message,
      details,
    },
  });
}

module.exports = {
  sendSuccess,
  sendError,
};
