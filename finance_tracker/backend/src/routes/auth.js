const express = require('express');
const { db } = require('../config/db');
const { users, refreshTokens } = require('../db/schema');
const { eq, and, isNull, gt } = require('drizzle-orm');
const { hashPassword, comparePassword } = require('../utils/password');
const { generateTokens, verifyRefreshToken, hashToken } = require('../utils/jwt');
const { registerSchema, loginSchema, refreshSchema } = require('../validators/auth.schema');
const validate = require('../middleware/validate');
const authenticate = require('../middleware/auth');
const { authLimiter } = require('../middleware/rate-limit');
const { sendSuccess, sendError } = require('../utils/response');

const router = express.Router();

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
    const tokenHash = hashToken(tokens.refreshToken);

    // Save refresh token
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000); // 7 days
    await db.insert(refreshTokens).values({
      userId: newUser.id,
      tokenHash,
      expiresAt,
      ipAddress: req.ip,
      userAgent: req.headers['user-agent'],
    });

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
    const tokenHash = hashToken(tokens.refreshToken);

    // Store refresh token
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
    await db.insert(refreshTokens).values({
      userId: user.id,
      tokenHash,
      expiresAt,
      ipAddress: req.ip,
      userAgent: req.headers['user-agent'],
    });

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
    const newTokenHash = hashToken(newTokens.refreshToken);

    const newExpiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
    await db.insert(refreshTokens).values({
      userId: user.id,
      tokenHash: newTokenHash,
      expiresAt: newExpiresAt,
      ipAddress: req.ip,
      userAgent: req.headers['user-agent'],
    });

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
    const { currency, timezone, name } = req.body;

    const updates = {};
    if (currency !== undefined) {
      if (typeof currency !== 'string' || currency.length !== 3) {
        return sendError(res, 'Currency must be a 3-letter code', 'VALIDATION_ERROR', 400);
      }
      updates.currency = currency.toUpperCase();
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
        status: users.status,
      });

    return sendSuccess(res, { user: updatedUser });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
