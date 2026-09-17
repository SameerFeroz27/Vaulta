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

describe('Dashboard API', () => {
  const testEmail = `test-dash-${Date.now()}@test.com`;
  let testUser, tokens, sourceId, categoryId;
  const today = new Date().toISOString().slice(0, 10);
  const currentMonth = today.slice(0, 7);

  beforeAll(async () => {
    testUser = await createTestUser(testEmail);
    tokens = await getAuthTokens(testUser);
    sourceId = await getFirstSourceId();
    categoryId = await getFirstCategoryId();

    // Create transactions with known amounts for dashboard tests
    // 2 expenses: 1000 + 500 = 1500 total expense
    // 1 income: 5000 total income
    // Balance: 5000 - 1500 = 3500
    await db.insert(transactions).values([
      {
        userId: testUser.id,
        sourceId,
        categoryId,
        amount: '1000.00',
        currency: 'PKR',
        type: 'expense',
        status: 'confirmed',
        merchant: 'Expense Merchant 1',
        occurredAt: new Date(),
        transactionDate: today,
      },
      {
        userId: testUser.id,
        sourceId,
        categoryId,
        amount: '500.00',
        currency: 'PKR',
        type: 'expense',
        status: 'confirmed',
        merchant: 'Expense Merchant 2',
        occurredAt: new Date(),
        transactionDate: today,
      },
      {
        userId: testUser.id,
        sourceId,
        amount: '5000.00',
        currency: 'PKR',
        type: 'income',
        status: 'confirmed',
        merchant: 'Salary',
        occurredAt: new Date(),
        transactionDate: today,
      },
    ]);
  });

  afterAll(async () => {
    if (testUser) await cleanupUser(testUser.id);
  });

  // ─── GET /api/dashboard/summary ─────────────────────────────

  describe('GET /api/dashboard/summary', () => {
    it('should return correct income, expense, and balance', async () => {
      const res = await request(app)
        .get(`/api/dashboard/summary?month=${currentMonth}`)
        .set('Authorization', `Bearer ${tokens.accessToken}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.totalExpense).toBe(1500);
      expect(res.body.data.totalIncome).toBe(5000);
      expect(res.body.data.balance).toBe(3500);
      expect(res.body.data.transactionCount).toBe(3);
    });

    it('should include top merchants', async () => {
      const res = await request(app)
        .get(`/api/dashboard/summary?month=${currentMonth}`)
        .set('Authorization', `Bearer ${tokens.accessToken}`);

      expect(res.status).toBe(200);
      expect(res.body.data.topMerchants).toBeDefined();
      expect(res.body.data.topMerchants.length).toBeGreaterThan(0);
      // Top merchant by expense should be "Expense Merchant 1" (1000)
      expect(res.body.data.topMerchants[0].merchant).toBe('Expense Merchant 1');
      expect(res.body.data.topMerchants[0].totalSpent).toBe(1000);
    });
  });

  // ─── GET /api/dashboard/expense-by-category ─────────────────

  describe('GET /api/dashboard/expense-by-category', () => {
    it('should return expense grouped by category', async () => {
      const res = await request(app)
        .get(`/api/dashboard/expense-by-category?month=${currentMonth}`)
        .set('Authorization', `Bearer ${tokens.accessToken}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.categories).toBeDefined();
      expect(res.body.data.totalExpense).toBe(1500);

      // Should have at least one category with expenses
      const catsWithExpenses = res.body.data.categories.filter((c) => c.total > 0);
      expect(catsWithExpenses.length).toBeGreaterThan(0);

      // Percentages should sum to ~100
      const totalPct = res.body.data.categories.reduce((sum, c) => sum + c.percentage, 0);
      expect(totalPct).toBeCloseTo(100, 0);
    });
  });

  // ─── GET /api/dashboard/expense-by-source ───────────────────

  describe('GET /api/dashboard/expense-by-source', () => {
    it('should return expense grouped by source', async () => {
      const res = await request(app)
        .get(`/api/dashboard/expense-by-source?month=${currentMonth}`)
        .set('Authorization', `Bearer ${tokens.accessToken}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.sources).toBeDefined();
      expect(res.body.data.totalExpense).toBe(1500);

      // At least one source should have expenses
      const sourcesWithExpenses = res.body.data.sources.filter((s) => s.total > 0);
      expect(sourcesWithExpenses.length).toBeGreaterThan(0);
    });
  });

  // ─── GET /api/dashboard/expense-trend ───────────────────────

  describe('GET /api/dashboard/expense-trend', () => {
    it('should return monthly trend data for last 6 months', async () => {
      const res = await request(app)
        .get('/api/dashboard/expense-trend?months=6')
        .set('Authorization', `Bearer ${tokens.accessToken}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.data).toHaveLength(6);

      // Current month should have expense data
      const currentMonthData = res.body.data.data.find((d) => d.month === currentMonth);
      expect(currentMonthData).toBeDefined();
      expect(currentMonthData.totalExpense).toBe(1500);
      expect(currentMonthData.totalIncome).toBe(5000);
    });
  });

  // ─── GET /api/dashboard/budget-status ───────────────────────

  describe('GET /api/dashboard/budget-status', () => {
    it('should return budget status with spent amounts even without budgets', async () => {
      const res = await request(app)
        .get(`/api/dashboard/budget-status?month=${currentMonth}`)
        .set('Authorization', `Bearer ${tokens.accessToken}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.overall).toBeDefined();
      expect(res.body.data.overall.spent).toBe(1500);
      expect(res.body.data.overall.budgetAmount).toBeNull();
      expect(res.body.data.categories).toBeDefined();
    });
  });
});
