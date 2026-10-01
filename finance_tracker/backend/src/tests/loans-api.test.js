const request = require('supertest');
const { eq } = require('drizzle-orm');
const {
  app,
  createTestUser,
  getAuthTokens,
  cleanupUser,
  getFirstSourceId,
  db,
} = require('./setup');
const { transactions } = require('../db/schema');

describe('Loans API', () => {
  const testEmail = `test-loans-${Date.now()}@test.com`;
  let testUser, tokens, sourceId;
  const today = new Date().toISOString().slice(0, 10);
  const currentMonth = today.slice(0, 7);
  const daysAgo = (n) =>
    new Date(Date.now() - n * 86400000).toISOString().slice(0, 10);

  const auth = (req) => req.set('Authorization', `Bearer ${tokens.accessToken}`);

  // Shared across the ordered cases below.
  let loanAId, loanATxId, loanAFirstPaymentTxId, overdueLoanId;

  beforeAll(async () => {
    testUser = await createTestUser(testEmail);
    tokens = await getAuthTokens(testUser);
    sourceId = await getFirstSourceId();
  });

  afterAll(async () => {
    if (testUser) await cleanupUser(testUser.id);
  });

  // ─── Create ───────────────────────────────────────────────────

  describe('POST /api/loans', () => {
    it('creates a lent loan and records the money movement', async () => {
      const res = await auth(request(app).post('/api/loans')).send({
        counterparty: 'Ali Raza',
        direction: 'lent',
        principal: 50000,
        issueDate: today,
      });

      expect(res.status).toBe(201);
      const loan = res.body.data.loan;
      expect(loan.paid).toBe(0);
      expect(loan.outstanding).toBe(50000);
      expect(loan.state).toBe('open');
      expect(loan.transactionId).toBeTruthy();

      loanAId = loan.id;
      loanATxId = loan.transactionId;

      const [tx] = await db.select().from(transactions).where(eq(transactions.id, loanATxId));
      expect(tx.kind).toBe('loan_disbursement');
      expect(tx.loanId).toBe(loanAId);
      expect(tx.type).toBe('expense'); // lending money out is a cash outflow
      expect(parseFloat(tx.amount)).toBe(50000);
      expect(tx.merchant).toBe('Ali Raza');
    });

    it('can create a loan without recording a transaction', async () => {
      const res = await auth(request(app).post('/api/loans')).send({
        counterparty: 'Bilal Ahmed',
        direction: 'borrowed',
        principal: 25000,
        issueDate: today,
        recordTransaction: false,
      });

      expect(res.status).toBe(201);
      expect(res.body.data.loan.transactionId).toBeNull();
    });

    it('rejects a due date before the issue date', async () => {
      const res = await auth(request(app).post('/api/loans')).send({
        counterparty: 'Bad Dates',
        direction: 'lent',
        principal: 1000,
        issueDate: '2026-05-10',
        dueDate: '2026-05-01',
      });

      expect(res.status).toBe(400);
      expect(res.body.error.code).toBe('VALIDATION_ERROR');
    });

    it('requires a counterparty and a positive amount', async () => {
      const res = await auth(request(app).post('/api/loans'))
        .send({ counterparty: '', direction: 'lent', principal: 0, issueDate: today });

      expect(res.status).toBe(400);
    });
  });

  // ─── Read ─────────────────────────────────────────────────────

  describe('GET /api/loans', () => {
    it('lists active loans with derived money fields', async () => {
      const res = await auth(request(app).get('/api/loans'));

      expect(res.status).toBe(200);
      const loan = res.body.data.loans.find((l) => l.id === loanAId);
      expect(loan).toBeDefined();
      expect(loan.outstanding).toBe(50000);
      expect(loan.state).toBe('open');
      expect(loan.overdue).toBe(false);
      expect(res.body.data.pagination.total).toBeGreaterThan(0);
    });

    it('filters by direction', async () => {
      const res = await auth(request(app).get('/api/loans?direction=borrowed'));

      expect(res.status).toBe(200);
      expect(res.body.data.loans.some((l) => l.id === loanAId)).toBe(false);
      expect(res.body.data.loans.every((l) => l.direction === 'borrowed')).toBe(true);
    });

    it('returns a single loan with its payment timeline', async () => {
      const res = await auth(request(app).get(`/api/loans/${loanAId}`));

      expect(res.status).toBe(200);
      expect(res.body.data.loan.id).toBe(loanAId);
      expect(res.body.data.payments).toEqual([]);
    });

    it('404s for an unknown loan', async () => {
      const res = await auth(request(app).get('/api/loans/999999'));
      expect(res.status).toBe(404);
    });
  });

  // ─── Repayments ───────────────────────────────────────────────

  describe('POST /api/loans/:id/payments', () => {
    it('records a partial repayment and reduces the balance', async () => {
      const res = await auth(request(app).post(`/api/loans/${loanAId}/payments`))
        .send({ amount: 20000, paymentDate: today });

      expect(res.status).toBe(201);
      expect(res.body.data.loan.paid).toBe(20000);
      expect(res.body.data.loan.outstanding).toBe(30000);
      expect(res.body.data.loan.state).toBe('open');
      expect(res.body.data.settled).toBe(false);

      loanAFirstPaymentTxId = res.body.data.payment.transactionId;
      const [tx] = await db
        .select()
        .from(transactions)
        .where(eq(transactions.id, loanAFirstPaymentTxId));
      expect(tx.kind).toBe('loan_repayment');
      expect(tx.type).toBe('income'); // being repaid is money back in
    });

    it('accepts an overpayment instead of rejecting it, settling with a surplus', async () => {
      // 30,000 outstanding; paying 40,000 leaves a 10,000 surplus.
      const res = await auth(request(app).post(`/api/loans/${loanAId}/payments`))
        .send({ amount: 40000, paymentDate: today });

      expect(res.status).toBe(201); // explicitly NOT a 400
      const loan = res.body.data.loan;
      expect(loan.outstanding).toBe(0);
      expect(loan.surplus).toBe(10000);
      expect(loan.state).toBe('settled');
      expect(res.body.data.settled).toBe(true);
      expect(res.body.data.surplusAdded).toBe(10000);
    });

    it('rejects a second payment with the same idempotency key', async () => {
      const created = await auth(request(app).post('/api/loans')).send({
        counterparty: 'Idem Person',
        direction: 'lent',
        principal: 5000,
        issueDate: today,
        recordTransaction: false,
      });
      const loanId = created.body.data.loan.id;
      const body = { amount: 1000, paymentDate: today, idempotencyKey: `idem-${Date.now()}` };

      const first = await auth(request(app).post(`/api/loans/${loanId}/payments`)).send(body);
      expect(first.status).toBe(201);

      const second = await auth(request(app).post(`/api/loans/${loanId}/payments`)).send(body);
      expect(second.status).toBe(409);
      expect(second.body.error.code).toBe('CONFLICT');
    });

    it('rejects a non-positive repayment', async () => {
      const res = await auth(request(app).post(`/api/loans/${loanAId}/payments`))
        .send({ amount: 0, paymentDate: today });

      expect(res.status).toBe(400);
    });
  });

  // ─── Summary ──────────────────────────────────────────────────

  describe('GET /api/loans/summary', () => {
    it('summarises per person, splitting what they owe from what I owe', async () => {
      const res = await auth(request(app).get('/api/loans/summary'));

      expect(res.status).toBe(200);
      const ali = res.body.data.people.find((p) => p.person === 'Ali Raza');
      expect(ali).toBeDefined();
      expect(ali.repaid).toBe(60000);
      expect(ali.theyOwe).toBe(0); // fully repaid, so nothing outstanding
      expect(ali.iOwe).toBe(0);
      expect(ali.state).toBe('settled');

      const bilal = res.body.data.people.find((p) => p.person === 'Bilal Ahmed');
      expect(bilal.iOwe).toBe(25000); // borrowed, still owed by me
      expect(bilal.theyOwe).toBe(0);
      expect(bilal.state).toBe('open');
    });

    it('groups the same person typed with different casing into one row', async () => {
      // A fresh name, so this does not disturb the Ali Raza row asserted above.
      for (const spelling of ['Sana Malik', '  sana   malik ']) {
        await auth(request(app).post('/api/loans')).send({
          counterparty: spelling,
          direction: 'lent',
          principal: 1000,
          issueDate: today,
          recordTransaction: false,
        });
      }

      const res = await auth(request(app).get('/api/loans/summary'));
      // Compared on normalised text so this asserts "one person", not a spelling.
      const normalise = (s) => s.trim().toLowerCase().replace(/\s+/g, ' ');
      const matches = res.body.data.people.filter(
        (p) => normalise(p.person) === 'sana malik'
      );

      // One row, with both spellings' loans counted into it.
      expect(matches).toHaveLength(1);
      expect(matches[0].theyOwe).toBe(2000);
      expect(matches[0].loanCount).toBe(2);
    });

    it('counts active loans past their due date', async () => {
      // Nothing is overdue to start with: Ali Raza is settled and Bilal Ahmed has
      // no due date, so neither can be overdue however old they are.
      const before = await auth(request(app).get('/api/loans/summary'));
      expect(before.body.data.overdueCount).toBe(0);

      const created = await auth(request(app).post('/api/loans')).send({
        counterparty: 'Overdue Person',
        direction: 'lent',
        principal: 5000,
        issueDate: daysAgo(30),
        dueDate: daysAgo(5),
        recordTransaction: false,
      });
      overdueLoanId = created.body.data.loan.id;

      const res = await auth(request(app).get('/api/loans/summary'));
      expect(res.body.data.overdueCount).toBe(1);
      // The dashboard names who is late, so the person comes back too.
      expect(res.body.data.overduePeople).toEqual(['Overdue Person']);
    });

    it('stops counting a loan as overdue once it is repaid', async () => {
      await auth(request(app).post(`/api/loans/${overdueLoanId}/payments`)).send({
        amount: 5000,
        paymentDate: today,
        recordTransaction: false,
      });

      const res = await auth(request(app).get('/api/loans/summary'));
      expect(res.body.data.overdueCount).toBe(0);
      expect(res.body.data.overduePeople).toEqual([]);
    });

    it('does not count a removed loan as overdue', async () => {
      // A hidden loan is gone from the user's view, so flagging it would be noise.
      const created = await auth(request(app).post('/api/loans')).send({
        counterparty: 'Removed Person',
        direction: 'lent',
        principal: 7000,
        issueDate: daysAgo(20),
        dueDate: daysAgo(2),
        recordTransaction: false,
      });

      const before = await auth(request(app).get('/api/loans/summary'));
      expect(before.body.data.overdueCount).toBe(1);
      expect(before.body.data.overduePeople).toContain('Removed Person');

      await auth(request(app).delete(`/api/loans/${created.body.data.loan.id}`));

      const after = await auth(request(app).get('/api/loans/summary'));
      expect(after.body.data.overdueCount).toBe(0);
      expect(after.body.data.overduePeople).toEqual([]);
    });

    it('names an overdue person once, however their name was typed', async () => {
      // Two overdue loans, one person, two spellings — the dashboard should read
      // "Hamza Iqbal", not two entries.
      for (const [name, due] of [
        ['Hamza Iqbal', daysAgo(9)],
        ['  hamza   iqbal ', daysAgo(3)],
      ]) {
        await auth(request(app).post('/api/loans')).send({
          counterparty: name,
          direction: 'lent',
          principal: 1000,
          issueDate: daysAgo(40),
          dueDate: due,
          recordTransaction: false,
        });
      }

      const res = await auth(request(app).get('/api/loans/summary'));
      const normalise = (s) => s.trim().toLowerCase().replace(/\s+/g, ' ');
      const named = res.body.data.overduePeople.filter(
        (p) => normalise(p) === 'hamza iqbal'
      );

      expect(named).toHaveLength(1);
      // Both loans are still counted, even though the person is named once.
      expect(res.body.data.overdueCount).toBe(2);
    });
  });

  // ─── Report isolation ─────────────────────────────────────────

  describe('dashboard isolation', () => {
    it('keeps loan money movements out of reported income and expense', async () => {
      // This user has loan transactions for 50,000 out, 20,000 in and 40,000 in.
      // None of it is income or expense, so every reported total must stay zero.
      const res = await auth(
        request(app).get(`/api/dashboard/summary?month=${currentMonth}`)
      );

      expect(res.status).toBe(200);
      expect(res.body.data.totalIncome).toBe(0);
      expect(res.body.data.totalExpense).toBe(0);
      expect(res.body.data.transactionCount).toBe(0);
    });
  });

  // ─── Delete ───────────────────────────────────────────────────

  describe('DELETE /api/loans/:id', () => {
    it('hides the loan, deletes only its own transactions, and keeps the repaid history', async () => {
      // An unrelated transaction that the delete must not touch.
      const manual = await auth(request(app).post('/api/transactions')).send({
        sourceId,
        amount: 777,
        type: 'expense',
        merchant: 'Unrelated Shop',
        transactionDate: today,
      });
      expect(manual.status).toBe(201);

      const del = await auth(request(app).delete(`/api/loans/${loanAId}`));
      expect(del.status).toBe(200);
      // one disbursement + two repayments
      expect(del.body.data.deletedTransactionCount).toBe(3);

      // Gone from the active list, and no longer readable as an active loan.
      const list = await auth(request(app).get('/api/loans'));
      expect(list.body.data.loans.find((l) => l.id === loanAId)).toBeUndefined();
      const detail = await auth(request(app).get(`/api/loans/${loanAId}`));
      expect(detail.status).toBe(404);

      // Its transactions are gone...
      const loanTxs = await db
        .select()
        .from(transactions)
        .where(eq(transactions.loanId, loanAId));
      expect(loanTxs).toHaveLength(0);

      // ...but the unrelated transaction survived untouched.
      const unrelated = await db
        .select()
        .from(transactions)
        .where(eq(transactions.id, manual.body.data.transaction.id));
      expect(unrelated).toHaveLength(1);

      // And the person is still in the summary, with their repaid history intact —
      // but nothing owed, and no active loan left.
      const summary = await auth(request(app).get('/api/loans/summary'));
      const ali = summary.body.data.people.find((p) => p.person === 'Ali Raza');
      expect(ali).toBeDefined();
      expect(ali.repaid).toBe(60000);
      expect(ali.theyOwe).toBe(0);
      expect(ali.iOwe).toBe(0);
      expect(ali.loanCount).toBe(0);
    });

    it('stops counting a removed loan as owed, while keeping what was repaid', async () => {
      // The reported bug: a loan with a real balance left on it, part-repaid, then
      // removed. It must leave the owed figures (which the dashboard reports) while
      // its repayment stays on record.
      const created = await auth(request(app).post('/api/loans')).send({
        counterparty: 'Balance Person',
        direction: 'lent',
        principal: 9000,
        issueDate: today,
        recordTransaction: false,
      });
      const loanId = created.body.data.loan.id;

      await auth(request(app).post(`/api/loans/${loanId}/payments`)).send({
        amount: 2000,
        paymentDate: today,
        recordTransaction: false,
      });

      const before = await auth(request(app).get('/api/loans/summary'));
      const b = before.body.data.people.find((p) => p.person === 'Balance Person');
      expect(b.theyOwe).toBe(7000);
      expect(b.repaid).toBe(2000);
      expect(b.loanCount).toBe(1);
      expect(b.state).toBe('open');

      await auth(request(app).delete(`/api/loans/${loanId}`));

      const after = await auth(request(app).get('/api/loans/summary'));
      const a = after.body.data.people.find((p) => p.person === 'Balance Person');
      expect(a.theyOwe).toBe(0);
      expect(a.iOwe).toBe(0);
      expect(a.state).toBe('settled');
      expect(a.loanCount).toBe(0);
      // The repayment is still on record.
      expect(a.repaid).toBe(2000);
    });

    it('404s when removing an already-removed loan', async () => {
      const res = await auth(request(app).delete(`/api/loans/${loanAId}`));
      expect(res.status).toBe(404);
    });
  });

  // ─── Removing a repayment ─────────────────────────────────────

  describe('DELETE /api/loans/:id/payments/:paymentId', () => {
    it('reopens a settled loan when a repayment is removed', async () => {
      const created = await auth(request(app).post('/api/loans')).send({
        counterparty: 'Reopen Person',
        direction: 'lent',
        principal: 10000,
        issueDate: today,
        recordTransaction: false,
      });
      const loanId = created.body.data.loan.id;

      const payment = await auth(request(app).post(`/api/loans/${loanId}/payments`))
        .send({ amount: 10000, paymentDate: today });
      expect(payment.body.data.loan.state).toBe('settled');

      const paymentId = payment.body.data.payment.id;
      const paymentTxId = payment.body.data.payment.transactionId;

      const removed = await auth(
        request(app).delete(`/api/loans/${loanId}/payments/${paymentId}`)
      );
      expect(removed.status).toBe(200);
      expect(removed.body.data.loan.paid).toBe(0);
      expect(removed.body.data.loan.outstanding).toBe(10000);
      expect(removed.body.data.loan.state).toBe('open');

      // The transaction the repayment created is removed too.
      const orphan = await db
        .select()
        .from(transactions)
        .where(eq(transactions.id, paymentTxId));
      expect(orphan).toHaveLength(0);
    });
  });

  // ─── Edit ─────────────────────────────────────────────────────

  describe('PUT /api/loans/:id', () => {
    it('keeps the linked transaction in step when the principal changes', async () => {
      const created = await auth(request(app).post('/api/loans')).send({
        counterparty: 'Edit Person',
        direction: 'lent',
        principal: 8000,
        issueDate: today,
      });
      const loanId = created.body.data.loan.id;
      const txId = created.body.data.loan.transactionId;

      const res = await auth(request(app).put(`/api/loans/${loanId}`))
        .send({ principal: 12000 });
      expect(res.status).toBe(200);
      expect(res.body.data.loan.principal).toBe(12000);

      const [tx] = await db.select().from(transactions).where(eq(transactions.id, txId));
      expect(parseFloat(tx.amount)).toBe(12000);
    });

    it('rejects an edit that would put the due date before the issue date', async () => {
      const created = await auth(request(app).post('/api/loans')).send({
        counterparty: 'Date Check',
        direction: 'lent',
        principal: 500,
        issueDate: '2026-05-10',
        recordTransaction: false,
      });

      const res = await auth(request(app).put(`/api/loans/${created.body.data.loan.id}`))
        .send({ dueDate: '2026-05-01' });

      expect(res.status).toBe(400);
    });
  });

  // ─── Person names ─────────────────────────────────────────────

  describe('person names', () => {
    it('stores a name exactly as the user typed it', async () => {
      // No house style is imposed; how the name is written is the user's choice.
      const res = await auth(request(app).post('/api/loans')).send({
        counterparty: 'sana malik',
        direction: 'lent',
        principal: 3000,
        issueDate: today,
        recordTransaction: false,
      });

      expect(res.status).toBe(201);
      expect(res.body.data.loan.counterparty).toBe('sana malik');
    });

    it('labels the recorded transaction with the name as typed', async () => {
      const res = await auth(request(app).post('/api/loans')).send({
        counterparty: 'hamza  iqbal',
        direction: 'lent',
        principal: 4000,
        issueDate: today,
      });

      const [tx] = await db
        .select()
        .from(transactions)
        .where(eq(transactions.id, res.body.data.loan.transactionId));
      expect(tx.merchant).toBe('hamza  iqbal');
    });

    it('still groups the same person typed several ways into one summary row', async () => {
      // Grouping is unaffected by removing the formatting: it stays case-insensitive
      // and whitespace-insensitive, so careless spellings do not split a person in two.
      for (const spelling of ['Sana Malik', '  SANA   MALIK ']) {
        await auth(request(app).post('/api/loans')).send({
          counterparty: spelling,
          direction: 'lent',
          principal: 1000,
          issueDate: today,
          recordTransaction: false,
        });
      }

      const res = await auth(request(app).get('/api/loans/summary'));
      const normalise = (s) => s.trim().toLowerCase().replace(/\s+/g, ' ');
      const matches = res.body.data.people.filter(
        (p) => normalise(p.person) === 'sana malik'
      );

      expect(matches).toHaveLength(1);
      expect(matches[0].loanCount).toBeGreaterThanOrEqual(3); // 3000 + 1000 + 1000
    });

    it('rejects a name that is only whitespace', async () => {
      const res = await auth(request(app).post('/api/loans')).send({
        counterparty: '   ',
        direction: 'lent',
        principal: 100,
        issueDate: today,
      });

      expect(res.status).toBe(400);
    });

    it('renames a loan and keeps its transactions in step', async () => {
      const created = await auth(request(app).post('/api/loans')).send({
        counterparty: 'Old Name',
        direction: 'lent',
        principal: 9000,
        issueDate: today,
      });
      const loanId = created.body.data.loan.id;

      await auth(request(app).post(`/api/loans/${loanId}/payments`))
        .send({ amount: 1000, paymentDate: today, recordTransaction: true });

      const res = await auth(request(app).put(`/api/loans/${loanId}`))
        .send({ counterparty: 'New Name' });
      expect(res.status).toBe(200);
      expect(res.body.data.loan.counterparty).toBe('New Name');

      // Both the disbursement and the repayment are relabelled.
      const rows = await db
        .select()
        .from(transactions)
        .where(eq(transactions.loanId, loanId));
      expect(rows).toHaveLength(2);
      expect(rows.every((row) => row.merchant === 'New Name')).toBe(true);
    });
  });
});
