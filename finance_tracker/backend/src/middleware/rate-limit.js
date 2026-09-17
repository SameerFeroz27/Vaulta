const rateLimit = require('express-rate-limit');
const { sendError } = require('../utils/response');

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 30, // limit each IP to 30 requests per window
  standardHeaders: true,
  legacyHeaders: false,
  handler: (req, res) => {
    return sendError(
      res,
      'Too many authentication requests from this IP, please try again after 15 minutes',
      'RATE_LIMITED',
      429
    );
  },
});

module.exports = {
  authLimiter,
};
