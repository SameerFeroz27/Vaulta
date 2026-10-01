const express = require('express');
const crypto = require('crypto');
const { db } = require('../config/db');
const { users, refreshTokens, passwordResetTokens } = require('../db/schema');
const { eq, and, isNull, gt } = require('drizzle-orm');
const { hashPassword, comparePassword } = require('../utils/password');
const { generateTokens, verifyRefreshToken, hashToken } = require('../utils/jwt');
const { registerSchema, loginSchema, refreshSchema, forgotPasswordSchema, resetPasswordSchema, changePasswordSchema } = require('../validators/auth.schema');
const validate = require('../middleware/validate');
const authenticate = require('../middleware/auth');
const { authLimiter, passwordResetLimiter } = require('../middleware/rate-limit');
const { sendSuccess, sendError } = require('../utils/response');
const { sendOtpEmail } = require('../utils/email');

const router = express.Router();

/**
 * Hash a refresh token and store it for the user with a 7-day expiry.
 * @param {number} userId
 * @param {string} refreshToken
 * @param {object} req - current request (for IP address and user agent)
 */
async function issueAndStoreRefreshToken(userId, refreshToken, req) {
  const tokenHash = hashToken(refreshToken);
  const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000); // 7 days
  await db.insert(refreshTokens).values({
    userId,
    tokenHash,
    expiresAt,
    ipAddress: req.ip,
    userAgent: req.headers['user-agent'],
  });
}

/**
 * POST /api/auth/register
 * Register a new user
 */
router.post('/register', authLimiter, validate(registerSchema), async (req, res, next) => {
  try {
    const { email, password, name, currency, timezone } = req.body;

    // Check if user already exists
    const existing = await db.select().from(users).where(eq(users.email, email)).limit(1);
    if (existing.length > 0) {
      return sendError(res, 'Email is already registered', 'CONFLICT', 409);
    }

    const passwordHash = await hashPassword(password);

    const [newUser] = await db
      .insert(users)
      .values({
        email,
        passwordHash,
        name,
        currency: currency || 'PKR',
        timezone: timezone || 'Asia/Karachi',
      })
      .returning({
        id: users.id,
        email: users.email,
        name: users.name,
        currency: users.currency,
        timezone: users.timezone,
        createdAt: users.createdAt,
      });

    // Generate tokens
    const tokens = generateTokens(newUser);
    await issueAndStoreRefreshToken(newUser.id, tokens.refreshToken, req);

    return sendSuccess(
      res,
      {
        user: newUser,
        tokens,
      },
      201
    );
  } catch (err) {
    next(err);
  }
});

/**
 * POST /api/auth/login
 * User login
 */
router.post('/login', authLimiter, validate(loginSchema), async (req, res, next) => {
  try {
    const { email, password } = req.body;

    const [user] = await db.select().from(users).where(eq(users.email, email)).limit(1);
    if (!user || user.status !== 'active') {
      return sendError(res, 'Invalid email or password', 'INVALID_CREDENTIALS', 401);
    }

    const isMatch = await comparePassword(password, user.passwordHash);
    if (!isMatch) {
      return sendError(res, 'Invalid email or password', 'INVALID_CREDENTIALS', 401);
    }

    // Generate tokens
    const tokens = generateTokens(user);
    await issueAndStoreRefreshToken(user.id, tokens.refreshToken, req);

    const userProfile = {
      id: user.id,
      email: user.email,
      name: user.name,
      currency: user.currency,
      timezone: user.timezone,
    };

    return sendSuccess(res, {
      user: userProfile,
      tokens,
    });
  } catch (err) {
    next(err);
  }
});

/**
 * POST /api/auth/refresh
 * Refresh access token & rotate refresh token
 */
router.post('/refresh', authLimiter, validate(refreshSchema), async (req, res, next) => {
  try {
    const { refreshToken } = req.body;

    let decoded;
    try {
      decoded = verifyRefreshToken(refreshToken);
    } catch (err) {
      return sendError(res, 'Invalid or expired refresh token', 'UNAUTHORIZED', 401);
    }

    const incomingHash = hashToken(refreshToken);

    // Look up token in DB
    const [storedToken] = await db
      .select()
      .from(refreshTokens)
      .where(
        and(
          eq(refreshTokens.tokenHash, incomingHash),
          isNull(refreshTokens.revokedAt),
          gt(refreshTokens.expiresAt, new Date())
        )
      )
      .limit(1);

    if (!storedToken) {
      // Possible reuse attack: revoke all tokens for this user
      await db
        .update(refreshTokens)
        .set({ revokedAt: new Date() })
        .where(eq(refreshTokens.userId, decoded.userId));
      return sendError(res, 'Refresh token invalid or already revoked', 'UNAUTHORIZED', 401);
    }

    // Revoke old refresh token (Rotation)
    await db
      .update(refreshTokens)
      .set({ revokedAt: new Date() })
      .where(eq(refreshTokens.id, storedToken.id));

    const [user] = await db.select().from(users).where(eq(users.id, decoded.userId)).limit(1);
    if (!user || user.status !== 'active') {
      return sendError(res, 'User not found or inactive', 'UNAUTHORIZED', 401);
    }

    // Generate new tokens
    const newTokens = generateTokens(user);
    await issueAndStoreRefreshToken(user.id, newTokens.refreshToken, req);

    return sendSuccess(res, {
      tokens: newTokens,
    });
  } catch (err) {
    next(err);
  }
});

/**
 * POST /api/auth/logout
 * Revoke the provided refresh token
 */
router.post('/logout', authLimiter, async (req, res, next) => {
  try {
    const { refreshToken } = req.body;
    if (refreshToken) {
      const incomingHash = hashToken(refreshToken);
      await db
        .update(refreshTokens)
        .set({ revokedAt: new Date() })
        .where(eq(refreshTokens.tokenHash, incomingHash));
    }

    return sendSuccess(res, { message: 'Logged out successfully' });
  } catch (err) {
    next(err);
  }
});

/**
 * GET /api/auth/me
 * Get current authenticated user profile
 */
router.get('/me', authenticate, async (req, res) => {
  return sendSuccess(res, { user: req.user });
});

/**
 * PUT /api/auth/me
 * Update user profile (currency, timezone, name)
 */
router.put('/me', authenticate, async (req, res, next) => {
  try {
    const { currency, timezone, name, exchangeRates } = req.body;

    const updates = {};
    if (currency !== undefined) {
      if (typeof currency !== 'string' || currency.length !== 3) {
        return sendError(res, 'Currency must be a 3-letter code', 'VALIDATION_ERROR', 400);
      }
      updates.currency = currency.toUpperCase();
      // Rates are relative to the base currency — reset when it changes
      updates.exchangeRates = null;
    }
    if (timezone !== undefined) {
      updates.timezone = timezone;
    }
    if (name !== undefined) {
      if (typeof name !== 'string' || name.trim().length === 0) {
        return sendError(res, 'Name cannot be empty', 'VALIDATION_ERROR', 400);
      }
      updates.name = name.trim();
    }
    if (exchangeRates !== undefined) {
      if (exchangeRates === null) {
        updates.exchangeRates = null;
      } else if (typeof exchangeRates === 'object') {
        // Validate: { "USD": 280, "EUR": 300, ... }
        const cleaned = {};
        for (const [code, rate] of Object.entries(exchangeRates)) {
          if (typeof code === 'string' && code.length === 3 && typeof rate === 'number' && rate > 0) {
            cleaned[code.toUpperCase()] = rate;
          }
        }
        updates.exchangeRates = cleaned;
      }
    }

    if (Object.keys(updates).length === 0) {
      return sendError(res, 'No valid fields to update', 'VALIDATION_ERROR', 400);
    }

    const [updatedUser] = await db
      .update(users)
      .set({ ...updates, updatedAt: new Date() })
      .where(eq(users.id, req.user.id))
      .returning({
        id: users.id,
        email: users.email,
        name: users.name,
        currency: users.currency,
        timezone: users.timezone,
        exchangeRates: users.exchangeRates,
        status: users.status,
      });

    return sendSuccess(res, { user: updatedUser });
  } catch (err) {
    next(err);
  }
});

/**
 * POST /api/auth/forgot-password
 * Generate a 6-digit OTP, store its hash, and email the code to the user.
 */
router.post('/forgot-password', passwordResetLimiter, validate(forgotPasswordSchema), async (req, res, next) => {
  try {
    const { email } = req.body;

    const [user] = await db.select().from(users).where(eq(users.email, email)).limit(1);
    if (!user) {
      return sendError(res, 'No account found with that email', 'NOT_FOUND', 404);
    }

    // Generate a 6-digit OTP and store its hash (same table, same expiry)
    const otp = crypto.randomInt(100000, 1000000).toString();
    const tokenHash = hashToken(otp);
    const expiresAt = new Date(Date.now() + 60 * 60 * 1000); // 1 hour

    await db.insert(passwordResetTokens).values({
      userId: user.id,
      tokenHash,
      expiresAt,
      ipAddress: req.ip,
    });

    // Email the OTP to the user
    await sendOtpEmail(user.email, otp);

    return sendSuccess(res, {
      message: 'A 6-digit reset code has been sent to your email',
    });
  } catch (err) {
    next(err);
  }
});

/**
 * POST /api/auth/reset-password
 * Reset password using a valid reset token.
 */
router.post('/reset-password', passwordResetLimiter, validate(resetPasswordSchema), async (req, res, next) => {
  try {
    const { token, password } = req.body;

    const incomingHash = hashToken(token);

    // Look up a valid, unused, non-expired reset token
    const [resetRecord] = await db
      .select()
      .from(passwordResetTokens)
      .where(
        and(
          eq(passwordResetTokens.tokenHash, incomingHash),
          isNull(passwordResetTokens.usedAt),
          gt(passwordResetTokens.expiresAt, new Date())
        )
      )
      .limit(1);

    if (!resetRecord) {
      return sendError(res, 'Invalid or expired reset token', 'INVALID_TOKEN', 400);
    }

    // Prevent reusing the current password
    const [user] = await db
      .select({ passwordHash: users.passwordHash })
      .from(users)
      .where(eq(users.id, resetRecord.userId))
      .limit(1);

    if (user && await comparePassword(password, user.passwordHash)) {
      return sendError(
        res,
        'New password must be different from your current password',
        'SAME_PASSWORD',
        400
      );
    }

    // Hash the new password and update the user
    const passwordHash = await hashPassword(password);
    await db
      .update(users)
      .set({ passwordHash, updatedAt: new Date() })
      .where(eq(users.id, resetRecord.userId));

    // Mark the reset token as used
    await db
      .update(passwordResetTokens)
      .set({ usedAt: new Date() })
      .where(eq(passwordResetTokens.id, resetRecord.id));

    // Revoke all existing refresh tokens so old sessions are invalidated
    await db
      .update(refreshTokens)
      .set({ revokedAt: new Date() })
      .where(eq(refreshTokens.userId, resetRecord.userId));

    return sendSuccess(res, { message: 'Password reset successfully' });
  } catch (err) {
    next(err);
  }
});

/**
 * PUT /api/auth/me/password
 * Change password for the authenticated user.
 */
router.put('/me/password', authenticate, validate(changePasswordSchema), async (req, res, next) => {
  try {
    const { currentPassword, newPassword } = req.body;

    // Fetch the user's current password hash
    const [user] = await db
      .select({ id: users.id, passwordHash: users.passwordHash })
      .from(users)
      .where(eq(users.id, req.user.id))
      .limit(1);

    if (!user) {
      return sendError(res, 'User not found', 'NOT_FOUND', 404);
    }

    const isMatch = await comparePassword(currentPassword, user.passwordHash);
    if (!isMatch) {
      return sendError(res, 'Current password is incorrect', 'INVALID_CREDENTIALS', 401);
    }

    // Prevent reusing the current password
    if (await comparePassword(newPassword, user.passwordHash)) {
      return sendError(
        res,
        'New password must be different from your current password',
        'SAME_PASSWORD',
        400
      );
    }

    const passwordHash = await hashPassword(newPassword);
    await db
      .update(users)
      .set({ passwordHash, updatedAt: new Date() })
      .where(eq(users.id, req.user.id));

    return sendSuccess(res, { message: 'Password changed successfully' });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
