const { db } = require('../config/db');
const { transactions } = require('../db/schema');
const { eq, and, sql } = require('drizzle-orm');

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
  findDuplicateByAmountAndDate,
};
