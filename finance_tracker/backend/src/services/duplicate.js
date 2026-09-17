const { db } = require('../config/db');
const { receipts, transactions } = require('../db/schema');
const { eq, and, isNull, sql } = require('drizzle-orm');

/**
 * Check if a receipt with the same file hash already exists for this user.
 * @param {number} userId
 * @param {string} fileHash - SHA-256 hash of the file
 * @returns {Promise<object|null>} The existing receipt or null
 */
async function findDuplicateReceipt(userId, fileHash) {
  if (!fileHash) return null;

  const [existing] = await db
    .select({
      id: receipts.id,
      status: receipts.status,
      transactionId: receipts.transactionId,
      createdAt: receipts.createdAt,
    })
    .from(receipts)
    .where(
      and(
        eq(receipts.userId, userId),
        eq(receipts.fileHash, fileHash),
        sql`${receipts.status} IN ('success', 'processing', 'queued')`
      )
    )
    .limit(1);

  return existing || null;
}

/**
 * Check if a transaction with the same idempotency key already exists for this user.
 * @param {number} userId
 * @param {string} idempotencyKey
 * @returns {Promise<object|null>} The existing transaction or null
 */
async function findDuplicateTransactionByKey(userId, idempotencyKey) {
  if (!idempotencyKey) return null;

  const [existing] = await db
    .select({
      id: transactions.id,
      amount: transactions.amount,
      merchant: transactions.merchant,
      transactionDate: transactions.transactionDate,
    })
    .from(transactions)
    .where(
      and(
        eq(transactions.userId, userId),
        eq(transactions.idempotencyKey, idempotencyKey)
      )
    )
    .limit(1);

  return existing || null;
}

/**
 * Check for a potential duplicate transaction based on amount + date + user.
 * If the same user has a transaction with the same amount on the same date,
 * it's likely a duplicate.
 * @param {number} userId
 * @param {number} amount
 * @param {string} transactionDate - YYYY-MM-DD
 * @returns {Promise<object|null>} The existing transaction or null
 */
async function findDuplicateByAmountAndDate(userId, amount, transactionDate) {
  if (!amount || !transactionDate) return null;

  const [existing] = await db
    .select({
      id: transactions.id,
      amount: transactions.amount,
      merchant: transactions.merchant,
      transactionDate: transactions.transactionDate,
    })
    .from(transactions)
    .where(
      and(
        eq(transactions.userId, userId),
        eq(transactions.amount, amount.toFixed(2)),
        eq(transactions.transactionDate, transactionDate),
        sql`${transactions.status} != 'archived'`
      )
    )
    .limit(1);

  return existing || null;
}

module.exports = {
  findDuplicateReceipt,
  findDuplicateTransactionByKey,
  findDuplicateByAmountAndDate,
};
