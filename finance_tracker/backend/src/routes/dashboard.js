const express = require('express');
const { db } = require('../config/db');
const { transactions, categories, budgets } = require('../db/schema');
const { eq, and, sql } = require('drizzle-orm');
const authenticate = require('../middleware/auth');
const { sendSuccess, sendError } = require('../utils/response');
const { getMonthRange } = require('../utils/dates');

const router = express.Router();

// All dashboard routes require authentication
router.use(authenticate);

// ─── Helpers ─────────────────────────────────────────────────────

/**
 * Rows left out of every reported total.
 *
 * - `archived` is deleted by the user.
 * - `needs_review` means the AI could not settle the direction with confidence, so
 *   counting it would let an unconfirmed guess skew income and expense. It reappears
 *   the moment the user confirms or flips it.
 * - Loan rows (`kind` set) are money movement, not income or expense: lending converts
 *   cash into a receivable and borrowing creates a liability. They are real
 *   transactions and stay in the ledger, but they must not inflate these figures.
 */
const EXCLUDED_FROM_TOTALS = sql`t.status NOT IN ('archived', 'needs_review') AND t.kind IS NULL`;

function getCurrentMonth() {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
}

/**
 * Generate an array of the last N months in YYYY-MM format (oldest first).
 */
function getRecentMonths(count) {
  const months = [];
  const now = new Date();
  for (let i = count - 1; i >= 0; i--) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
    months.push(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`);
  }
  return months;
}

// ─── GET /api/dashboard/summary ──────────────────────────────────
/**
 * Returns income, expense, balance, transaction count, and top 5 merchants.
 * Query: ?month=YYYY-MM (defaults to current month)
 */
router.get('/summary', async (req, res, next) => {
  try {
    const month = req.query.month || getCurrentMonth();
    if (!/^\d{4}-\d{2}$/.test(month)) {
      return sendError(res, 'Month must be in YYYY-MM format', 'VALIDATION_ERROR', 400);
    }

    const { start, end } = getMonthRange(month);
    const userId = req.user.id;

    // Aggregate income/expense/count
    const [summary] = (await db.execute(sql`
      SELECT
        COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount * COALESCE((u.exchange_rates->>t.currency)::numeric, 1) ELSE 0 END), 0)::numeric AS total_income,
        COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount * COALESCE((u.exchange_rates->>t.currency)::numeric, 1) ELSE 0 END), 0)::numeric AS total_expense,
        COUNT(*)::int AS transaction_count
      FROM transactions t
      JOIN users u ON u.id = t.user_id
      WHERE t.user_id = ${userId}
        AND t.transaction_date >= ${start}
        AND t.transaction_date < ${end}
        AND ${EXCLUDED_FROM_TOTALS}
    `)).rows;

    // Top 5 merchants by expense
    const topMerchants = (await db.execute(sql`
      SELECT t.merchant, SUM(t.amount * COALESCE((u.exchange_rates->>t.currency)::numeric, 1))::numeric AS total_spent
      FROM transactions t
      JOIN users u ON u.id = t.user_id
      WHERE t.user_id = ${userId}
        AND t.type = 'expense'
        AND t.transaction_date >= ${start}
        AND t.transaction_date < ${end}
        AND ${EXCLUDED_FROM_TOTALS}
        AND t.merchant IS NOT NULL
      GROUP BY t.merchant
      ORDER BY total_spent DESC
      LIMIT 5
    `)).rows.map((r) => ({
      merchant: r.merchant,
      totalSpent: parseFloat(r.total_spent),
    }));

    const totalIncome = parseFloat(summary.total_income);
    const totalExpense = parseFloat(summary.total_expense);

    return sendSuccess(res, {
      month,
      totalIncome,
      totalExpense,
      balance: totalIncome - totalExpense,
      transactionCount: summary.transaction_count,
      topMerchants,
    });
  } catch (err) {
    next(err);
  }
});

// ─── GET /api/dashboard/expense-by-category ──────────────────────
/**
 * Returns expense totals grouped by category (with color & icon for pie chart).
 * Query: ?month=YYYY-MM (defaults to current month)
 */
router.get('/expense-by-category', async (req, res, next) => {
  try {
    const month = req.query.month || getCurrentMonth();
    if (!/^\d{4}-\d{2}$/.test(month)) {
      return sendError(res, 'Month must be in YYYY-MM format', 'VALIDATION_ERROR', 400);
    }

    const { start, end } = getMonthRange(month);
    const userId = req.user.id;

    const rows = (await db.execute(sql`
      SELECT
        c.id AS category_id,
        c.name AS category_name,
        c.icon,
        c.color,
        SUM(t.amount * COALESCE((u.exchange_rates->>t.currency)::numeric, 1))::numeric AS total
      FROM transactions t
      INNER JOIN categories c ON t.category_id = c.id
      JOIN users u ON u.id = t.user_id
      WHERE t.user_id = ${userId}
        AND t.type = 'expense'
        AND t.transaction_date >= ${start}
        AND t.transaction_date < ${end}
        AND ${EXCLUDED_FROM_TOTALS}
      GROUP BY c.id, c.name, c.icon, c.color
      ORDER BY total DESC
    `)).rows.map((r) => ({
      categoryId: r.category_id,
      categoryName: r.category_name,
      icon: r.icon,
      color: r.color,
      total: parseFloat(r.total),
    }));

    const grandTotal = rows.reduce((sum, r) => sum + r.total, 0);

    const result = rows.map((r) => ({
      ...r,
      percentage: grandTotal > 0 ? (r.total / grandTotal) * 100 : 0,
    }));

    return sendSuccess(res, {
      month,
      totalExpense: grandTotal,
      categories: result,
    });
  } catch (err) {
    next(err);
  }
});

// ─── GET /api/dashboard/expense-by-source ────────────────────────
/**
 * Returns expense totals grouped by payment source (Card/Cash/Online) for pie chart.
 * Query: ?month=YYYY-MM (defaults to current month)
 */
router.get('/expense-by-source', async (req, res, next) => {
  try {
    const month = req.query.month || getCurrentMonth();
    if (!/^\d{4}-\d{2}$/.test(month)) {
      return sendError(res, 'Month must be in YYYY-MM format', 'VALIDATION_ERROR', 400);
    }

    const { start, end } = getMonthRange(month);
    const userId = req.user.id;

    const rows = (await db.execute(sql`
      SELECT
        s.id AS source_id,
        s.name AS source_name,
        COALESCE(SUM(t.amount * COALESCE((u.exchange_rates->>t.currency)::numeric, 1)), 0)::numeric AS total
      FROM sources s
      LEFT JOIN transactions t ON t.source_id = s.id
        AND t.user_id = ${userId}
        AND t.type = 'expense'
        AND t.transaction_date >= ${start}
        AND t.transaction_date < ${end}
        AND ${EXCLUDED_FROM_TOTALS}
      LEFT JOIN users u ON u.id = ${userId}
      GROUP BY s.id, s.name
      ORDER BY total DESC
    `)).rows.map((r) => ({
      sourceId: r.source_id,
      sourceName: r.source_name,
      total: parseFloat(r.total),
    }));

    const grandTotal = rows.reduce((sum, r) => sum + r.total, 0);

    const result = rows.map((r) => ({
      ...r,
      percentage: grandTotal > 0 ? (r.total / grandTotal) * 100 : 0,
    }));

    return sendSuccess(res, {
      month,
      totalExpense: grandTotal,
      sources: result,
    });
  } catch (err) {
    next(err);
  }
});

// ─── GET /api/dashboard/expense-trend ────────────────────────────
/**
 * Returns monthly expense & income totals for the last N months (for bar chart).
 * Query: ?months=6 (default 6, max 24)
 */
router.get('/expense-trend', async (req, res, next) => {
  try {
    const numMonths = Math.min(Math.max(parseInt(req.query.months, 10) || 6, 1), 24);
    const userId = req.user.id;

    const monthList = getRecentMonths(numMonths);
    const startDate = `${monthList[0]}-01`;

    const rows = (await db.execute(sql`
      SELECT
        TO_CHAR(t.transaction_date, 'YYYY-MM') AS month,
        COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount * COALESCE((u.exchange_rates->>t.currency)::numeric, 1) ELSE 0 END), 0)::numeric AS total_expense,
        COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount * COALESCE((u.exchange_rates->>t.currency)::numeric, 1) ELSE 0 END), 0)::numeric AS total_income
      FROM transactions t
      JOIN users u ON u.id = t.user_id
      WHERE t.user_id = ${userId}
        AND t.transaction_date >= ${startDate}
        AND ${EXCLUDED_FROM_TOTALS}
      GROUP BY TO_CHAR(t.transaction_date, 'YYYY-MM')
      ORDER BY month ASC
    `)).rows;

    // Build a map from the DB results, then fill in 0 for months with no data
    const dbMap = {};
    for (const r of rows) {
      dbMap[r.month] = {
        totalExpense: parseFloat(r.total_expense),
        totalIncome: parseFloat(r.total_income),
      };
    }

    const result = monthList.map((m) => ({
      month: m,
      totalExpense: dbMap[m]?.totalExpense || 0,
      totalIncome: dbMap[m]?.totalIncome || 0,
    }));

    return sendSuccess(res, {
      months: numMonths,
      data: result,
    });
  } catch (err) {
    next(err);
  }
});

// ─── GET /api/dashboard/budget-status ────────────────────────────
/**
 * Returns budget vs. actual spent per category + overall for the given month.
 * Query: ?month=YYYY-MM (defaults to current month)
 */
router.get('/budget-status', async (req, res, next) => {
  try {
    const month = req.query.month || getCurrentMonth();
    if (!/^\d{4}-\d{2}$/.test(month)) {
      return sendError(res, 'Month must be in YYYY-MM format', 'VALIDATION_ERROR', 400);
    }

    const { start, end } = getMonthRange(month);
    const userId = req.user.id;

    // 1. Fetch all budgets for this user + month
    const budgetRows = await db
      .select({
        id: budgets.id,
        categoryId: budgets.categoryId,
        amount: budgets.amount,
      })
      .from(budgets)
      .where(and(eq(budgets.userId, userId), eq(budgets.month, month)));

    // 2. Fetch actual spending per category for the month
    const spendingRows = (await db.execute(sql`
      SELECT
        t.category_id,
        SUM(t.amount * COALESCE((u.exchange_rates->>t.currency)::numeric, 1))::numeric AS spent
      FROM transactions t
      JOIN users u ON u.id = t.user_id
      WHERE t.user_id = ${userId}
        AND t.type = 'expense'
        AND t.transaction_date >= ${start}
        AND t.transaction_date < ${end}
        AND ${EXCLUDED_FROM_TOTALS}
      GROUP BY t.category_id
    `)).rows;

    // 3. Overall spending for the month
    const [overallRow] = (await db.execute(sql`
      SELECT COALESCE(SUM(t.amount * COALESCE((u.exchange_rates->>t.currency)::numeric, 1)), 0)::numeric AS spent
      FROM transactions t
      JOIN users u ON u.id = t.user_id
      WHERE t.user_id = ${userId}
        AND t.type = 'expense'
        AND t.transaction_date >= ${start}
        AND t.transaction_date < ${end}
        AND ${EXCLUDED_FROM_TOTALS}
    `)).rows;

    const overallSpent = parseFloat(overallRow.spent);

    // Build spending map (categoryId → spent)
    const spendingMap = {};
    for (const r of spendingRows) {
      const key = r.category_id === null ? 'null' : r.category_id;
      spendingMap[key] = parseFloat(r.spent);
    }

    // 4. Build per-category budget status
    const categoryBudgets = [];
    let overallBudget = null;

    for (const b of budgetRows) {
      const spent = b.categoryId === null
        ? overallSpent
        : (spendingMap[b.categoryId] || 0);
      const budgetAmount = parseFloat(b.amount);
      const remaining = budgetAmount - spent;
      const percentage = budgetAmount > 0 ? (spent / budgetAmount) * 100 : 0;

      const entry = {
        budgetId: b.id,
        budgetAmount,
        spent,
        remaining,
        percentage,
        overBudget: spent > budgetAmount,
      };

      if (b.categoryId === null) {
        overallBudget = entry;
      } else {
        // Fetch category details
        const [cat] = await db
          .select({
            name: categories.name,
            icon: categories.icon,
            color: categories.color,
          })
          .from(categories)
          .where(eq(categories.id, b.categoryId))
          .limit(1);

        categoryBudgets.push({
          ...entry,
          categoryId: b.categoryId,
          categoryName: cat?.name || 'Unknown',
          icon: cat?.icon || '📁',
          color: cat?.color || '#BDC3C7',
        });
      }
    }

    return sendSuccess(res, {
      month,
      overall: overallBudget
        ? { ...overallBudget, spent: overallSpent }
        : { budgetAmount: null, spent: overallSpent, remaining: null, percentage: null, overBudget: false },
      categories: categoryBudgets,
    });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
