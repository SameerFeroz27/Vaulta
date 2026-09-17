const { db, pool } = require('../config/db');
const { users, refreshTokens, sources, categories } = require('../db/schema');
const { eq } = require('drizzle-orm');
const { hashPassword } = require('../utils/password');
const { generateTokens, hashToken } = require('../utils/jwt');

/**
 * Create a test user directly in the database (bypasses API / rate limits).
 */
async function createTestUser(email, password = 'Test1234!') {
  const passwordHash = await hashPassword(password);
  const [user] = await db
    .insert(users)
    .values({
      email,
      passwordHash,
      name: 'Test User',
      currency: 'PKR',
      timezone: 'Asia/Karachi',
    })
    .returning({
      id: users.id,
      email: users.email,
      name: users.name,
      currency: users.currency,
      timezone: users.timezone,
      status: users.status,
    });
  return user;
}

/**
 * Generate JWT tokens for a user and store the refresh token hash in the DB.
 */
async function getAuthTokens(user) {
  const tokens = generateTokens(user);
  const tokenHash = hashToken(tokens.refreshToken);
  const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
  await db.insert(refreshTokens).values({
    userId: user.id,
    tokenHash,
    expiresAt,
  });
  return tokens;
}

/**
 * Delete a test user — cascades to refresh_tokens, transactions, receipts, budgets, custom categories.
 */
async function cleanupUser(userId) {
  await db.delete(users).where(eq(users.id, userId));
}

/**
 * Get the first source ID from the seeded sources table.
 */
async function getFirstSourceId() {
  const [source] = await db.select({ id: sources.id }).from(sources).limit(1);
  return source.id;
}

/**
 * Get the first global category ID from the seeded categories table.
 */
async function getFirstCategoryId() {
  const [category] = await db.select({ id: categories.id }).from(categories).limit(1);
  return category.id;
}

module.exports = {
  app: require('../app'),
  db,
  pool,
  createTestUser,
  getAuthTokens,
  cleanupUser,
  getFirstSourceId,
  getFirstCategoryId,
};
