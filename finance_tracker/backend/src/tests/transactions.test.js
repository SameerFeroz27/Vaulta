const request = require('supertest');
const {
  app,
  createTestUser,
  getAuthTokens,
  cleanupUser,
  getFirstSourceId,
  getFirstCategoryId,
  db,
} = require('./setup');
const { transactions } = require('../db/schema');
const { eq } = require('drizzle-orm');

describe('Transactions API', () => {
  const testEmail = `test-tx-${Date.now()}@test.com`;
  let testUser, tokens, sourceId, categoryId;
  let createdTxIds = [];

  beforeAll(async () => {
    testUser = await createTestUser(testEmail);
    tokens = await getAuthTokens(testUser);
    sourceId = await getFirstSourceId();
    categoryId = await getFirstCategoryId();

    // Create a few transactions for read tests
    for (let i = 0; i < 3; i++) {
      const res = await request(app)
        .post('/api/transactions')
        .set('Authorization', `Bearer ${tokens.accessToken}`)
        .send({
          sourceId,
          categoryId,
          amount: 100 * (i + 1),
          type: 'expense',
          merchant: `Test Merchant ${i + 1}`,
          description: `Test description ${i + 1}`,
          transactionDate: new Date().toISOString().slice(0, 10),
        });
      if (res.body.success) {
        createdTxIds.push(res.body.data.transaction.id);
      }
    }
  });

  afterAll(async () => {
    if (testUser) await cleanupUser(testUser.id);
  });

  // ─── POST /api/transactions ─────────────────────────────────

  describe('POST /api/transactions', () => {
    it('should create a manual transaction', async () => {
      const res = await request(app)
        .post('/api/transactions')
        .set('Authorization', `Bearer ${tokens.accessToken}`)
        .send({
          sourceId,
          categoryId,
          amount: 250.50,
          type: 'expense',
          merchant: 'New Store',
          transactionDate: new Date().toISOString().slice(0, 10),
        });

      expect(res.status).toBe(201);
      expect(res.body.success).toBe(true);
      expect(res.body.data.transaction.amount).toBe('250.50');
      expect(res.body.data.transaction.status).toBe('confirmed');
    });

    it('should reject invalid source ID with 404', async () => {
      const res = await request(app)
        .post('/api/transactions')
        .set('Authorization', `Bearer ${tokens.accessToken}`)
        .send({
          sourceId: 99999,
          amount: 100,
          type: 'expense',
          transactionDate: new Date().toISOString().slice(0, 10),
        });

      expect(res.status).toBe(404);
      expect(res.body.success).toBe(false);
    });

    it('should reject unauthenticated request with 401', async () => {
      const res = await request(app)
        .post('/api/transactions')
        .send({
          sourceId,
          amount: 100,
          type: 'expense',
          transactionDate: new Date().toISOString().slice(0, 10),
        });

      expect(res.status).toBe(401);
    });
  });

  // ─── GET /api/transactions ──────────────────────────────────

  describe('GET /api/transactions', () => {
    it('should return paginated list', async () => {
      const res = await request(app)
        .get('/api/transactions')
        .set('Authorization', `Bearer ${tokens.accessToken}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.transactions).toBeDefined();
      expect(res.body.data.pagination).toBeDefined();
      expect(res.body.data.pagination.total).toBeGreaterThanOrEqual(3);
    });

    it('should filter by type=expense', async () => {
      const res = await request(app)
        .get('/api/transactions?type=expense')
        .set('Authorization', `Bearer ${tokens.accessToken}`);

      expect(res.status).toBe(200);
      expect(res.body.data.transactions.length).toBeGreaterThan(0);
      expect(res.body.data.transactions.every((t) => t.type === 'expense')).toBe(true);
    });

    it('should search by merchant name', async () => {
      const res = await request(app)
        .get('/api/transactions?search=Merchant%201')
        .set('Authorization', `Bearer ${tokens.accessToken}`);

      expect(res.status).toBe(200);
      expect(res.body.data.transactions.length).toBeGreaterThan(0);
      expect(res.body.data.transactions[0].merchant).toContain('Merchant 1');
    });

    it('should sort by amount ascending', async () => {
      const res = await request(app)
        .get('/api/transactions?sort=amount&order=asc')
        .set('Authorization', `Bearer ${tokens.accessToken}`);

      expect(res.status).toBe(200);
      const amounts = res.body.data.transactions.map((t) => parseFloat(t.amount));
      for (let i = 1; i < amounts.length; i++) {
        expect(amounts[i]).toBeGreaterThanOrEqual(amounts[i - 1]);
      }
    });
  });

  // ─── GET /api/transactions/:id ──────────────────────────────

  describe('GET /api/transactions/:id', () => {
    it('should return a single transaction', async () => {
      const res = await request(app)
        .get(`/api/transactions/${createdTxIds[0]}`)
        .set('Authorization', `Bearer ${tokens.accessToken}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.transaction.id).toBe(createdTxIds[0]);
    });

    it('should return 404 for non-existent transaction', async () => {
      const res = await request(app)
        .get('/api/transactions/99999')
        .set('Authorization', `Bearer ${tokens.accessToken}`);

      expect(res.status).toBe(404);
    });
  });

  // ─── PUT /api/transactions/:id ──────────────────────────────

  describe('PUT /api/transactions/:id', () => {
    it('should update a transaction', async () => {
      const res = await request(app)
        .put(`/api/transactions/${createdTxIds[0]}`)
        .set('Authorization', `Bearer ${tokens.accessToken}`)
        .send({ merchant: 'Updated Merchant' });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.transaction.merchant).toBe('Updated Merchant');
    });

    // ─── Direction provenance (typeSource / typeConfidence) ────

    const today = new Date().toISOString().slice(0, 10);

    async function createPendingTx(merchant) {
      const res = await request(app)
        .post('/api/transactions')
        .set('Authorization', `Bearer ${tokens.accessToken}`)
        .send({ sourceId, amount: 55, type: 'expense', merchant, transactionDate: today });
      return res.body.data.transaction.id;
    }

    it('marks a manually entered transaction as such', async () => {
      const res = await request(app)
        .post('/api/transactions')
        .set('Authorization', `Bearer ${tokens.accessToken}`)
        .send({ sourceId, amount: 42, type: 'expense', merchant: 'Manual Store', transactionDate: today });

      expect(res.status).toBe(201);
      expect(res.body.data.transaction.typeSource).toBe('manual');
      expect(res.body.data.transaction.typeConfidence).toBeNull();
    });

    it('records a direction change as a user override', async () => {
      const id = await createPendingTx('Flip Store');

      const res = await request(app)
        .put(`/api/transactions/${id}`)
        .set('Authorization', `Bearer ${tokens.accessToken}`)
        .send({ type: 'income' });

      expect(res.status).toBe(200);
      expect(res.body.data.transaction.type).toBe('income');
      expect(res.body.data.transaction.typeSource).toBe('user_override');
      // The old confidence no longer describes the stored type.
      expect(res.body.data.transaction.typeConfidence).toBeNull();
    });

    it('keeps the original provenance when the direction is unchanged', async () => {
      const id = await createPendingTx('Rename Store');

      // Same type, different merchant: an unrelated edit must not look like an override.
      const res = await request(app)
        .put(`/api/transactions/${id}`)
        .set('Authorization', `Bearer ${tokens.accessToken}`)
        .send({ type: 'expense', merchant: 'Renamed Store' });

      expect(res.status).toBe(200);
      expect(res.body.data.transaction.merchant).toBe('Renamed Store');
      expect(res.body.data.transaction.typeSource).toBe('manual');
    });

    it('does not let a client set provenance directly', async () => {
      const id = await createPendingTx('Spoof Store');

      const res = await request(app)
        .put(`/api/transactions/${id}`)
        .set('Authorization', `Bearer ${tokens.accessToken}`)
        .send({ typeSource: 'ai_auto', typeConfidence: 0.99 });

      expect(res.status).toBe(200);
      // Zod strips the unknown keys, so provenance is untouched.
      expect(res.body.data.transaction.typeSource).toBe('manual');
      expect(res.body.data.transaction.typeConfidence).toBeNull();
    });

    it('does not let a client hide a transaction from reports by setting kind', async () => {
      // `kind` is how loan money movement is excluded from income/expense. If a client
      // could set it, any transaction could be made to disappear from its own reports.
      const created = await request(app)
        .post('/api/transactions')
        .set('Authorization', `Bearer ${tokens.accessToken}`)
        .send({
          sourceId,
          amount: 500,
          type: 'expense',
          merchant: 'Not A Loan',
          transactionDate: today,
          kind: 'loan_repayment',
          loanId: 1,
        });

      expect(created.status).toBe(201);

      const [row] = await db
        .select()
        .from(transactions)
        .where(eq(transactions.id, created.body.data.transaction.id));

      expect(row.kind).toBeNull();
      expect(row.loanId).toBeNull();
    });
  });

  // ─── POST /api/transactions/:id/confirm ─────────────────────

  describe('POST /api/transactions/:id/confirm', () => {
    it('should reject confirm on already-confirmed transaction', async () => {
      // Transactions created via POST are 'confirmed' by default
      const res = await request(app)
        .post(`/api/transactions/${createdTxIds[1]}/confirm`)
        .set('Authorization', `Bearer ${tokens.accessToken}`);

      expect(res.status).toBe(400);
      expect(res.body.error.code).toBe('INVALID_STATE_TRANSITION');
    });
  });

  // ─── DELETE /api/transactions/:id ───────────────────────────

  describe('DELETE /api/transactions/:id', () => {
    it('should delete a transaction', async () => {
      const res = await request(app)
        .delete(`/api/transactions/${createdTxIds[2]}`)
        .set('Authorization', `Bearer ${tokens.accessToken}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);

      // Verify it's gone
      const getRes = await request(app)
        .get(`/api/transactions/${createdTxIds[2]}`)
        .set('Authorization', `Bearer ${tokens.accessToken}`);
      expect(getRes.status).toBe(404);
    });
  });
});

// ─── The review queue count the app's banner relies on ────────────
//
// The UI reads pagination.total from GET /transactions?status=needs_review&limit=1,
// so the count must be the full total, not the number of rows returned.

describe('Transactions API — review queue count', () => {
  const testEmail = `test-tx-review-${Date.now()}@test.com`;
  let testUser, tokens, sourceId;
  const today = new Date().toISOString().slice(0, 10);

  beforeAll(async () => {
    testUser = await createTestUser(testEmail);
    tokens = await getAuthTokens(testUser);
    sourceId = await getFirstSourceId();

    await db.insert(transactions).values([
      {
        userId: testUser.id,
        sourceId,
        amount: '111.00',
        currency: 'PKR',
        type: 'expense',
        status: 'needs_review',
        occurredAt: new Date(),
        transactionDate: today,
      },
      {
        userId: testUser.id,
        sourceId,
        amount: '222.00',
        currency: 'PKR',
        type: 'income',
        status: 'needs_review',
        occurredAt: new Date(),
        transactionDate: today,
      },
      {
        userId: testUser.id,
        sourceId,
        amount: '333.00',
        currency: 'PKR',
        type: 'expense',
        status: 'needs_review',
        occurredAt: new Date(),
        transactionDate: today,
      },
      {
        userId: testUser.id,
        sourceId,
        amount: '444.00',
        currency: 'PKR',
        type: 'expense',
        status: 'confirmed',
        occurredAt: new Date(),
        transactionDate: today,
      },
    ]);
  });

  afterAll(async () => {
    if (testUser) await cleanupUser(testUser.id);
  });

  it('reports the full total while returning a single row', async () => {
    const res = await request(app)
      .get('/api/transactions?status=needs_review&page=1&limit=1')
      .set('Authorization', `Bearer ${tokens.accessToken}`);

    expect(res.status).toBe(200);
    expect(res.body.data.transactions).toHaveLength(1);
    expect(res.body.data.pagination.total).toBe(3);
  });

  it('excludes settled transactions from the review count', async () => {
    const res = await request(app)
      .get('/api/transactions?status=confirmed&page=1&limit=1')
      .set('Authorization', `Bearer ${tokens.accessToken}`);

    expect(res.status).toBe(200);
    expect(res.body.data.pagination.total).toBe(1);
  });
});
