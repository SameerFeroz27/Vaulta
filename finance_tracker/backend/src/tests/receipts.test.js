const request = require('supertest');
const crypto = require('crypto');
const {
  app,
  createTestUser,
  getAuthTokens,
  cleanupUser,
  getFirstSourceId,
  db,
} = require('./setup');
const { receipts, transactions } = require('../db/schema');

const hashOf = (text) => crypto.createHash('sha256').update(text.trim()).digest('hex');

describe('Receipts API — bank message dedup', () => {
  const testEmail = `test-receipts-${Date.now()}@test.com`;
  let testUser, tokens, sourceId;
  const today = new Date().toISOString().slice(0, 10);

  const submit = (message) =>
    request(app)
      .post('/api/receipts/bank-message')
      .set('Authorization', `Bearer ${tokens.accessToken}`)
      .send({ message });

  beforeAll(async () => {
    testUser = await createTestUser(testEmail);
    tokens = await getAuthTokens(testUser);
    sourceId = await getFirstSourceId();
  });

  afterAll(async () => {
    if (testUser) await cleanupUser(testUser.id);
  });

  it('queues a bank message, then reports a resubmission as a duplicate', async () => {
    const message = 'PKR 1,500 spent at KFC on 15/01/2024';

    const first = await submit(message);
    expect(first.status).toBe(202);
    expect(first.body.data.status).toBe('queued');

    const second = await submit(message);
    expect(second.status).toBe(200);
    expect(second.body.data.status).toBe('duplicate');
  });

  it('rejects a required message that is missing', async () => {
    const res = await submit('');
    expect(res.status).toBe(400);
  });

  it('treats a direction-uncertain receipt as already processed', async () => {
    // needs_review with a linked transaction means "parsed fine, direction unresolved".
    // Re-submitting must not create a second transaction for the same movement.
    const message = 'PKR 2,000 transferred to AHMED on 16/01/2024';

    const [tx] = await db
      .insert(transactions)
      .values({
        userId: testUser.id,
        sourceId,
        amount: '2000.00',
        currency: 'PKR',
        type: 'expense',
        status: 'needs_review',
        occurredAt: new Date(),
        transactionDate: today,
      })
      .returning({ id: transactions.id });

    await db.insert(receipts).values({
      userId: testUser.id,
      inputType: 'bank_message',
      fileHash: hashOf(message),
      rawText: message,
      status: 'needs_review',
      transactionId: tx.id,
    });

    const res = await submit(message);
    expect(res.status).toBe(200);
    expect(res.body.data.status).toBe('duplicate');
    expect(res.body.data.existingTransactionId).toBe(tx.id);
  });

  it('allows retrying a receipt whose parsing failed', async () => {
    // needs_review with no transaction means parsing failed and nothing was recorded,
    // so re-uploading is a legitimate retry rather than a duplicate.
    const message = 'PKR 3,000 at an unreadable merchant 17/01/2024';

    await db.insert(receipts).values({
      userId: testUser.id,
      inputType: 'bank_message',
      fileHash: hashOf(message),
      rawText: message,
      status: 'needs_review',
      transactionId: null,
    });

    const res = await submit(message);
    expect(res.status).toBe(202);
    expect(res.body.data.status).toBe('queued');
  });
});
