const request = require('supertest');
const {
  app,
  createTestUser,
  getAuthTokens,
  cleanupUser,
} = require('./setup');

describe('Auth API', () => {
  const testEmail = `test-auth-${Date.now()}@test.com`;
  const testPassword = 'Test1234!';
  let testUser;
  let tokens;

  beforeAll(async () => {
    testUser = await createTestUser(testEmail, testPassword);
    tokens = await getAuthTokens(testUser);
  });

  afterAll(async () => {
    if (testUser) await cleanupUser(testUser.id);
  });

  // ─── POST /api/auth/register ────────────────────────────────

  describe('POST /api/auth/register', () => {
    it('should register a new user successfully', async () => {
      const email = `new-register-${Date.now()}@test.com`;
      const res = await request(app).post('/api/auth/register').send({
        email,
        password: 'NewPass123!',
        name: 'New User',
      });

      expect(res.status).toBe(201);
      expect(res.body.success).toBe(true);
      expect(res.body.data.user.email).toBe(email);
      expect(res.body.data.tokens.accessToken).toBeDefined();
      expect(res.body.data.tokens.refreshToken).toBeDefined();

      // Cleanup
      await cleanupUser(res.body.data.user.id);
    });

    it('should reject duplicate email with 409', async () => {
      const res = await request(app).post('/api/auth/register').send({
        email: testEmail,
        password: testPassword,
        name: 'Duplicate User',
      });

      expect(res.status).toBe(409);
      expect(res.body.success).toBe(false);
    });

    it('should reject invalid email with 400', async () => {
      const res = await request(app).post('/api/auth/register').send({
        email: 'not-an-email',
        password: testPassword,
        name: 'Test',
      });

      expect(res.status).toBe(400);
      expect(res.body.success).toBe(false);
    });

    it('should reject weak password with 400', async () => {
      const res = await request(app).post('/api/auth/register').send({
        email: `weak-${Date.now()}@test.com`,
        password: '123',
        name: 'Test',
      });

      expect(res.status).toBe(400);
      expect(res.body.success).toBe(false);
    });
  });

  // ─── POST /api/auth/login ───────────────────────────────────

  describe('POST /api/auth/login', () => {
    it('should login successfully with correct credentials', async () => {
      const res = await request(app).post('/api/auth/login').send({
        email: testEmail,
        password: testPassword,
      });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.user.email).toBe(testEmail);
      expect(res.body.data.tokens.accessToken).toBeDefined();
      expect(res.body.data.tokens.refreshToken).toBeDefined();
    });

    it('should reject wrong password with 401', async () => {
      const res = await request(app).post('/api/auth/login').send({
        email: testEmail,
        password: 'WrongPassword123',
      });

      expect(res.status).toBe(401);
      expect(res.body.success).toBe(false);
      expect(res.body.error.code).toBe('INVALID_CREDENTIALS');
    });
  });

  // ─── POST /api/auth/refresh ─────────────────────────────────

  describe('POST /api/auth/refresh', () => {
    it('should rotate refresh token and return new tokens', async () => {
      const res = await request(app).post('/api/auth/refresh').send({
        refreshToken: tokens.refreshToken,
      });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.tokens.accessToken).toBeDefined();
      expect(res.body.data.tokens.refreshToken).toBeDefined();
      // New refresh token should be different from the old one
      expect(res.body.data.tokens.refreshToken).not.toBe(tokens.refreshToken);
    });

    it('should reject reused (revoked) token and revoke all user tokens', async () => {
      // Login to get fresh tokens (previous test consumed the shared token)
      const loginRes = await request(app).post('/api/auth/login').send({
        email: testEmail,
        password: testPassword,
      });
      const freshRefreshToken = loginRes.body.data.tokens.refreshToken;

      // First refresh — rotates the token (old one is now revoked)
      const firstRefresh = await request(app).post('/api/auth/refresh').send({
        refreshToken: freshRefreshToken,
      });
      expect(firstRefresh.status).toBe(200);

      // Try to reuse the original (now revoked) token
      const reuseAttempt = await request(app).post('/api/auth/refresh').send({
        refreshToken: freshRefreshToken,
      });

      expect(reuseAttempt.status).toBe(401);
      expect(reuseAttempt.body.success).toBe(false);

      // The new token from the first refresh should also be revoked
      // (because reuse detection revokes ALL tokens for the user)
      const newTokenAttempt = await request(app).post('/api/auth/refresh').send({
        refreshToken: firstRefresh.body.data.tokens.refreshToken,
      });

      expect(newTokenAttempt.status).toBe(401);
    });
  });

  // ─── POST /api/auth/logout ──────────────────────────────────

  describe('POST /api/auth/logout', () => {
    it('should logout successfully by revoking refresh token', async () => {
      // Create a fresh user with tokens for this test
      const email = `logout-${Date.now()}@test.com`;
      const user = await createTestUser(email);
      const userTokens = await getAuthTokens(user);

      const res = await request(app).post('/api/auth/logout').send({
        refreshToken: userTokens.refreshToken,
      });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);

      // Verify the token can no longer be refreshed
      const refreshAttempt = await request(app).post('/api/auth/refresh').send({
        refreshToken: userTokens.refreshToken,
      });

      expect(refreshAttempt.status).toBe(401);

      await cleanupUser(user.id);
    });
  });

  // ─── GET /api/auth/me ───────────────────────────────────────

  describe('GET /api/auth/me', () => {
    it('should return user profile with valid token', async () => {
      // Login to get fresh tokens
      const loginRes = await request(app).post('/api/auth/login').send({
        email: testEmail,
        password: testPassword,
      });

      const res = await request(app)
        .get('/api/auth/me')
        .set('Authorization', `Bearer ${loginRes.body.data.tokens.accessToken}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.user.email).toBe(testEmail);
    });

    it('should reject request without auth header', async () => {
      const res = await request(app).get('/api/auth/me');

      expect(res.status).toBe(401);
      expect(res.body.success).toBe(false);
    });
  });
});
