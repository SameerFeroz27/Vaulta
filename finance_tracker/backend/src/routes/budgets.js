const express = require('express');
const { db } = require('../config/db');
const { budgets, categories } = require('../db/schema');
const { eq, and, or, desc, sql } = require('drizzle-orm');
const authenticate = require('../middleware/auth');
const validate = require('../middleware/validate');
const { createBudgetSchema, updateBudgetSchema, listBudgetsSchema } = require('../validators/budget.schema');
const { sendSuccess, sendError } = require('../utils/response');
const { getMonthRange } = require('../utils/dates');

const router = express.Router();

// All budget routes require authentication
router.use(authenticate);

// ─── Helpers ─────────────────────────────────────────────────────

/**
 * Fetch spending per category for a given user + month.
 * Returns a map: { categoryId: spent } where 'null' key = uncategorized, 'overall' key = total.
 */
async function getMonthlySpending(userId, month) {
  const { start, end } = getMonthRange(month);

  const rows = (await db.execute(sql`
    SELECT
      category_id,
      SUM(amount)::numeric AS spent
    FROM transactions
    WHERE user_id = ${userId}
      AND type = 'expense'
      AND transaction_date >= ${start}
      AND transaction_date < ${end}
      AND status != 'archived'
    GROUP BY category_id
  `)).rows;

  const spendingMap = {};
  let overall = 0;
  for (const r of rows) {
    const key = r.category_id === null ? 'null' : r.category_id;
    const spent = parseFloat(r.spent);
    spendingMap[key] = spent;
    overall += spent;
  }
  spendingMap['overall'] = overall;

  return spendingMap;
}

/**
 * Attach computed fields (spent, remaining, percentage, overBudget) to a budget.
 */
function attachComputedFields(budget, spendingMap) {
  const spent = budget.categoryId === null
    ? spendingMap['overall'] || 0
    : spendingMap[budget.categoryId] || 0;

  const remaining = budget.amount - spent;
  const percentage = budget.amount > 0 ? (spent / budget.amount) * 100 : 0;

  return {
    ...budget,
    spent,
    remaining,
    percentage,
    overBudget: spent > budget.amount,
  };
}

// ─── POST /api/budgets ───────────────────────────────────────────
/**
 * Create a monthly budget (overall if no categoryId, or category-specific).
 */
router.post('/', validate(createBudgetSchema), async (req, res, next) => {
  try {
    const { amount, month, categoryId } = req.body;
    const finalCategoryId = categoryId || null;

    // If categoryId provided, verify it belongs to the user or is global
    if (finalCategoryId) {
      const [cat] = await db
        .select({ id: categories.id })
        .from(categories)
        .where(
          and(
            eq(categories.id, finalCategoryId),
            or(
              eq(categories.userId, req.user.id),
              sql`${categories.userId} IS NULL`
            )
          )
        )
        .limit(1);
      if (!cat) {
        return sendError(res, 'Category not found', 'NOT_FOUND', 404);
      }
    }

    // Check for existing budget (same user + categoryId + month)
    const [existing] = await db
      .select({ id: budgets.id })
      .from(budgets)
      .where(
        and(
          eq(budgets.userId, req.user.id),
          eq(budgets.month, month),
          finalCategoryId
            ? eq(budgets.categoryId, finalCategoryId)
            : sql`${budgets.categoryId} IS NULL`
        )
      )
      .limit(1);

    if (existing) {
      return sendError(
        res,
        finalCategoryId
          ? 'A budget for this category and month already exists'
          : 'An overall budget for this month already exists',
        'CONFLICT',
        409
      );
    }

    const [newBudget] = await db
      .insert(budgets)
      .values({
        userId: req.user.id,
        categoryId: finalCategoryId,
        amount: amount.toFixed(2),
        month,
      })
      .returning({
        id: budgets.id,
        amount: budgets.amount,
        categoryId: budgets.categoryId,
        month: budgets.month,
        period: budgets.period,
        createdAt: budgets.createdAt,
      });

    // Compute spent for the new budget
    const spendingMap = await getMonthlySpending(req.user.id, month);
    const budgetWithComputed = attachComputedFields(
      { ...newBudget, amount: parseFloat(newBudget.amount) },
      spendingMap
    );

    return sendSuccess(res, { budget: budgetWithComputed }, 201);
  } catch (err) {
    // Handle unique constraint violation (safety net)
    if (err.code === '23505') {
      return sendError(res, 'A budget for this category and month already exists', 'CONFLICT', 409);
    }
    next(err);
  }
});

// ─── GET /api/budgets ────────────────────────────────────────────
/**
 * List budgets for the authenticated user with computed spent & remaining.
 * Query: ?month=YYYY-MM (optional filter), ?page, ?limit
 */
router.get('/', async (req, res, next) => {
  try {
    const parsed = listBudgetsSchema.parse(req.query);
    const { month, page, limit } = parsed;
    const offset = (page - 1) * limit;

    // Build where conditions
    const conditions = [eq(budgets.userId, req.user.id)];
    if (month) {
      conditions.push(eq(budgets.month, month));
    }

    // Fetch budgets
    const budgetRows = await db
      .select({
        id: budgets.id,
        amount: budgets.amount,
        categoryId: budgets.categoryId,
        month: budgets.month,
        period: budgets.period,
        createdAt: budgets.createdAt,
        updatedAt: budgets.updatedAt,
      })
      .from(budgets)
      .where(and(...conditions))
      .orderBy(desc(budgets.month))
      .limit(limit)
      .offset(offset);

    // Total count
    const [{ count: total }] = await db
      .select({ count: sql`count(*)::int` })
      .from(budgets)
      .where(and(...conditions));

    if (budgetRows.length === 0) {
      return sendSuccess(res, {
        budgets: [],
        pagination: { page, limit, total, totalPages: 0 },
      });
    }

    // Fetch category details for category-specific budgets
    const categoryIds = budgetRows
      .filter((b) => b.categoryId !== null)
      .map((b) => b.categoryId);

    const categoryDetails = {};
    if (categoryIds.length > 0) {
      const cats = await db
        .select({
          id: categories.id,
          name: categories.name,
          icon: categories.icon,
          color: categories.color,
        })
        .from(categories)
        .where(sql`${categories.id} = ANY(${categoryIds})`);

      for (const c of cats) {
        categoryDetails[c.id] = c;
      }
    }

    // Fetch spending for each unique month in the results
    const uniqueMonths = [...new Set(budgetRows.map((b) => b.month))];
    const spendingByMonth = {};
    for (const m of uniqueMonths) {
      spendingByMonth[m] = await getMonthlySpending(req.user.id, m);
    }

    // Merge everything together
    const result = budgetRows.map((b) => {
      const budget = {
        ...b,
        amount: parseFloat(b.amount),
      };

      // Attach category details
      if (b.categoryId !== null && categoryDetails[b.categoryId]) {
        budget.categoryName = categoryDetails[b.categoryId].name;
        budget.categoryIcon = categoryDetails[b.categoryId].icon;
        budget.categoryColor = categoryDetails[b.categoryId].color;
      }

      return attachComputedFields(budget, spendingByMonth[b.month]);
    });

    return sendSuccess(res, {
      budgets: result,
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
    });
  } catch (err) {
    next(err);
  }
});

// ─── PUT /api/budgets/:id ────────────────────────────────────────
/**
 * Update a budget.
 */
router.put('/:id', validate(updateBudgetSchema), async (req, res, next) => {
  try {
    const budgetId = parseInt(req.params.id, 10);
    if (Number.isNaN(budgetId)) {
      return sendError(res, 'Invalid budget ID', 'VALIDATION_ERROR', 400);
    }

    // Verify ownership
    const [existing] = await db
      .select({
        id: budgets.id,
        month: budgets.month,
        categoryId: budgets.categoryId,
      })
      .from(budgets)
      .where(and(eq(budgets.id, budgetId), eq(budgets.userId, req.user.id)))
      .limit(1);

    if (!existing) {
      return sendError(res, 'Budget not found', 'NOT_FOUND', 404);
    }

    // Build update data
    const updateData = { updatedAt: new Date() };
    if (req.body.amount !== undefined) updateData.amount = req.body.amount.toFixed(2);
    if (req.body.month !== undefined) updateData.month = req.body.month;
    if (req.body.categoryId !== undefined) updateData.categoryId = req.body.categoryId || null;

    const [updated] = await db
      .update(budgets)
      .set(updateData)
      .where(eq(budgets.id, budgetId))
      .returning({
        id: budgets.id,
        amount: budgets.amount,
        categoryId: budgets.categoryId,
        month: budgets.month,
        period: budgets.period,
        updatedAt: budgets.updatedAt,
      });

    // Compute spent for the updated budget
    const spendingMap = await getMonthlySpending(req.user.id, updated.month);
    const budgetWithComputed = attachComputedFields(
      { ...updated, amount: parseFloat(updated.amount) },
      spendingMap
    );

    return sendSuccess(res, { budget: budgetWithComputed });
  } catch (err) {
    if (err.code === '23505') {
      return sendError(res, 'A budget for this category and month already exists', 'CONFLICT', 409);
    }
    next(err);
  }
});

// ─── DELETE /api/budgets/:id ────────────────────────────────────
/**
 * Delete a budget.
 */
router.delete('/:id', async (req, res, next) => {
  try {
    const budgetId = parseInt(req.params.id, 10);
    if (Number.isNaN(budgetId)) {
      return sendError(res, 'Invalid budget ID', 'VALIDATION_ERROR', 400);
    }

    const [existing] = await db
      .select({ id: budgets.id })
      .from(budgets)
      .where(and(eq(budgets.id, budgetId), eq(budgets.userId, req.user.id)))
      .limit(1);

    if (!existing) {
      return sendError(res, 'Budget not found', 'NOT_FOUND', 404);
    }

    await db.delete(budgets).where(eq(budgets.id, budgetId));

    return sendSuccess(res, { message: 'Budget deleted successfully' });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
