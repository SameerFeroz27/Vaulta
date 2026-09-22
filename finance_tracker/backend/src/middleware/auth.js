const { verifyAccessToken } = require('../utils/jwt');
const { sendError } = require('../utils/response');
const { db } = require('../config/db');
const { users } = require('../db/schema');
const { eq } = require('drizzle-orm');

async function authenticate(req, res, next) {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return sendError(res, 'Authentication token missing or invalid', 'UNAUTHORIZED', 401);
    }

    const token = authHeader.split(' ')[1];
    let decoded;
    try {
      decoded = verifyAccessToken(token);
    } catch (err) {
      if (err.name === 'TokenExpiredError') {
        return sendError(res, 'Access token expired', 'TOKEN_EXPIRED', 401);
      }
      return sendError(res, 'Invalid access token', 'UNAUTHORIZED', 401);
    }

    // Verify user exists and is active
    const user = await db
      .select({
        id: users.id,
        email: users.email,
        name: users.name,
        currency: users.currency,
        timezone: users.timezone,
        exchangeRates: users.exchangeRates,
        status: users.status,
      })
      .from(users)
      .where(eq(users.id, decoded.userId))
      .limit(1);

    if (user.length === 0 || user[0].status !== 'active') {
      return sendError(res, 'User account is inactive or not found', 'UNAUTHORIZED', 401);
    }

    req.user = user[0];
    next();
  } catch (err) {
    next(err);
  }
}

module.exports = authenticate;
