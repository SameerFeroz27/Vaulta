const { db } = require('../config/db');
const { refreshTokens } = require('../db/schema');
const { lt, isNotNull, or } = require('drizzle-orm');

/**
 * Delete expired and revoked refresh tokens to prevent unbounded table growth.
 * Runs periodically from index.js via setInterval.
 */
async function cleanupExpiredTokens() {
  try {
    const now = new Date();
    const deleted = await db
      .delete(refreshTokens)
      .where(
        or(
          lt(refreshTokens.expiresAt, now),
          isNotNull(refreshTokens.revokedAt)
        )
      )
      .returning({ id: refreshTokens.id });

    if (deleted.length > 0) {
      console.log(`[Token Cleanup] Removed ${deleted.length} expired/revoked refresh tokens`);
    }
  } catch (err) {
    console.error('[Token Cleanup] Error:', err.message);
  }
}

module.exports = { cleanupExpiredTokens };
