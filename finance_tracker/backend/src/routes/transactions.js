const express = require('express');
const { db } = require('../config/db');
const { transactions, sources, categories } = require('../db/schema');
const { eq, and, or, ilike, gte, lt, desc, asc, sql } = require('drizzle-orm');
const authenticate = require('../middleware/auth');
const validate = require('../middleware/validate');
const {
  createTransactionSchema,
  updateTransactionSchema,
  listTransactionsSchema,
} = require('../validators/transaction.schema');
const { sendSuccess, sendError } = require('../utils/response');

const router = express.Router();

// All transaction routes require authentication
router.use(authenticate);

/**
 * Helper: compute month range as { start, end } date strings.
 * end is the first day of the next month (exclusive upper bound).
 */
function getMonthRange(month) {
  const [year, mon] = month.split('-').map(Number);
  const start = `${month}-01`;
  const nextMonth = mon === 12
    ? `${year + 1}-01`
    : `${year}-${String(mon + 1).padStart(2, '0')}`;
  const end = `${nextMonth}-01`;
  return { start, end };
}

/**
 * Helper: map sort param to a Drizzle column.
 */
function getSortColumn(sort) {
  switch (sort) {
    case 'amount':
      return transactions.amount;
    case 'created_at':
      return transactions.createdAt;
    case 'date':
    default:
      return transactions.transactionDate;
  }
}

/**
 * GET /api/transactions
 * Paginated, filtered, searchable transaction list
 */
router.get('/', async (req, res, next) => {
  try {
    const parsed = listTransactionsSchema.parse(req.query);
    const { month, source, category, type, status, search, sort, order, page, limit } = parsed;

    // Build WHERE conditions (always scoped to the authenticated user)
    const conditions = [eq(transactions.userId, req.user.id)];

    if (month) {
      const { start, end } = getMonthRange(month);
      conditions.push(gte(transactions.transactionDate, start));
      conditions.push(lt(transactions.transactionDate, end));
    }
    if (source) conditions.push(eq(transactions.sourceId, source));
    if (category) conditions.push(eq(transactions.categoryId, category));
    if (type) conditions.push(eq(transactions.type, type));
    if (status) conditions.push(eq(transactions.status, status));
    if (search) {
      conditions.push(
        or(
          ilike(transactions.merchant, `%${search}%`),
          ilike(transactions.description, `%${search}%`)
        )
      );
    }

    const whereClause = and(...conditions);
    const offset = (page - 1) * limit;
    const sortCol = getSortColumn(sort);
    const orderBy = order === 'asc' ? asc(sortCol) : desc(sortCol);

    // Fetch transactions with joined source & category
    const rows = await db
      .select({
        id: transactions.id,
        amount: transactions.amount,
        currency: transactions.currency,
        type: transactions.type,
        status: transactions.status,
        merchant: transactions.merchant,
        description: transactions.description,
        occurredAt: transactions.occurredAt,
        transactionDate: transactions.transactionDate,
        cardLast4: transactions.cardLast4,
        bankReference: transactions.bankReference,
        receiptId: transactions.receiptId,
        createdAt: transactions.createdAt,
        updatedAt: transactions.updatedAt,
        sourceId: transactions.sourceId,
        sourceName: sources.name,
        categoryId: transactions.categoryId,
        categoryName: categories.name,
        categoryIcon: categories.icon,
        categoryColor: categories.color,
      })
      .from(transactions)
      .leftJoin(sources, eq(transactions.sourceId, sources.id))
      .leftJoin(categories, eq(transactions.categoryId, categories.id))
      .where(whereClause)
      .orderBy(orderBy)
      .limit(limit)
      .offset(offset);

    // Total count for pagination metadata
    const [{ count: total }] = await db
      .select({ count: sql`count(*)::int` })
      .from(transactions)
      .where(whereClause);

    return sendSuccess(res, {
      transactions: rows,
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
        hasNext: page * limit < total,
        hasPrev: page > 1,
      },
    });
  } catch (err) {
    next(err);
  }
});

/**
 * POST /api/transactions
 * Manual transaction entry (default status: confirmed)
 */
router.post('/', validate(createTransactionSchema), async (req, res, next) => {
  try {
    const {
      sourceId,
      categoryId,
      amount,
      currency,
      type,
      merchant,
      description,
      occurredAt,
      transactionDate,
      cardLast4,
      bankReference,
      idempotencyKey,
    } = req.body;

    // Verify the source exists
    const [source] = await db.select({ id: sources.id }).from(sources).where(eq(sources.id, sourceId)).limit(1);
    if (!source) {
      return sendError(res, 'Source not found', 'NOT_FOUND', 404);
    }

    // If categoryId provided, verify it belongs to the user or is global
    if (categoryId) {
      const [cat] = await db
        .select({ id: categories.id })
        .from(categories)
        .where(
          and(
            eq(categories.id, categoryId),
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

    // Idempotency check
    if (idempotencyKey) {
      const [existing] = await db
        .select({ id: transactions.id })
        .from(transactions)
        .where(
          and(
            eq(transactions.userId, req.user.id),
            eq(transactions.idempotencyKey, idempotencyKey)
          )
        )
        .limit(1);
      if (existing) {
        return sendError(res, 'Transaction with this idempotency key already exists', 'CONFLICT', 409);
      }
    }

    // Derive transactionDate from occurredAt if not provided
    const finalTransactionDate = transactionDate
      || (occurredAt ? occurredAt.slice(0, 10) : new Date().toISOString().slice(0, 10));

    const [newTransaction] = await db
      .insert(transactions)
      .values({
        userId: req.user.id,
        sourceId,
        categoryId: categoryId || null,
        amount,
        currency: currency || req.user.currency,
        type,
        status: 'confirmed',
        merchant: merchant || null,
        description: description || null,
        occurredAt: occurredAt ? new Date(occurredAt) : new Date(),
        transactionDate: finalTransactionDate,
        cardLast4: cardLast4 || null,
        bankReference: bankReference || null,
        idempotencyKey: idempotencyKey || null,
      })
      .returning({
        id: transactions.id,
        amount: transactions.amount,
        currency: transactions.currency,
        type: transactions.type,
        status: transactions.status,
        merchant: transactions.merchant,
        description: transactions.description,
        occurredAt: transactions.occurredAt,
        transactionDate: transactions.transactionDate,
        cardLast4: transactions.cardLast4,
        bankReference: transactions.bankReference,
        sourceId: transactions.sourceId,
        categoryId: transactions.categoryId,
        createdAt: transactions.createdAt,
      });

    return sendSuccess(res, { transaction: newTransaction }, 201);
  } catch (err) {
    next(err);
  }
});

/**
 * GET /api/transactions/:id
 */
router.get('/:id', async (req, res, next) => {
  try {
    const transactionId = parseInt(req.params.id, 10);
    if (Number.isNaN(transactionId)) {
      return sendError(res, 'Invalid transaction ID', 'VALIDATION_ERROR', 400);
    }

    const [row] = await db
      .select({
        id: transactions.id,
        amount: transactions.amount,
        currency: transactions.currency,
        type: transactions.type,
        status: transactions.status,
        merchant: transactions.merchant,
        description: transactions.description,
        occurredAt: transactions.occurredAt,
        transactionDate: transactions.transactionDate,
        cardLast4: transactions.cardLast4,
        bankReference: transactions.bankReference,
        receiptId: transactions.receiptId,
        createdAt: transactions.createdAt,
        updatedAt: transactions.updatedAt,
        sourceId: transactions.sourceId,
        sourceName: sources.name,
        categoryId: transactions.categoryId,
        categoryName: categories.name,
        categoryIcon: categories.icon,
        categoryColor: categories.color,
      })
      .from(transactions)
      .leftJoin(sources, eq(transactions.sourceId, sources.id))
      .leftJoin(categories, eq(transactions.categoryId, categories.id))
      .where(and(eq(transactions.id, transactionId), eq(transactions.userId, req.user.id)))
      .limit(1);

    if (!row) {
      return sendError(res, 'Transaction not found', 'NOT_FOUND', 404);
    }

    return sendSuccess(res, { transaction: row });
  } catch (err) {
    next(err);
  }
});

/**
 * PUT /api/transactions/:id
 */
router.put('/:id', validate(updateTransactionSchema), async (req, res, next) => {
  try {
    const transactionId = parseInt(req.params.id, 10);
    if (Number.isNaN(transactionId)) {
      return sendError(res, 'Invalid transaction ID', 'VALIDATION_ERROR', 400);
    }

    // Verify ownership
    const [existing] = await db
      .select({ id: transactions.id, status: transactions.status })
      .from(transactions)
      .where(and(eq(transactions.id, transactionId), eq(transactions.userId, req.user.id)))
      .limit(1);

    if (!existing) {
      return sendError(res, 'Transaction not found', 'NOT_FOUND', 404);
    }

    // Build update object from provided fields only
    const updateData = { ...req.body, updatedAt: new Date() };
    if (req.body.occurredAt) {
      updateData.occurredAt = new Date(req.body.occurredAt);
    }

    const [updated] = await db
      .update(transactions)
      .set(updateData)
      .where(eq(transactions.id, transactionId))
      .returning({
        id: transactions.id,
        amount: transactions.amount,
        currency: transactions.currency,
        type: transactions.type,
        status: transactions.status,
        merchant: transactions.merchant,
        description: transactions.description,
        occurredAt: transactions.occurredAt,
        transactionDate: transactions.transactionDate,
        cardLast4: transactions.cardLast4,
        bankReference: transactions.bankReference,
        sourceId: transactions.sourceId,
        categoryId: transactions.categoryId,
        updatedAt: transactions.updatedAt,
      });

    return sendSuccess(res, { transaction: updated });
  } catch (err) {
    next(err);
  }
});

/**
 * DELETE /api/transactions/:id
 */
router.delete('/:id', async (req, res, next) => {
  try {
    const transactionId = parseInt(req.params.id, 10);
    if (Number.isNaN(transactionId)) {
      return sendError(res, 'Invalid transaction ID', 'VALIDATION_ERROR', 400);
    }

    const [existing] = await db
      .select({ id: transactions.id })
      .from(transactions)
      .where(and(eq(transactions.id, transactionId), eq(transactions.userId, req.user.id)))
      .limit(1);

    if (!existing) {
      return sendError(res, 'Transaction not found', 'NOT_FOUND', 404);
    }

    await db.delete(transactions).where(eq(transactions.id, transactionId));

    return sendSuccess(res, { message: 'Transaction deleted successfully' });
  } catch (err) {
    next(err);
  }
});

/**
 * POST /api/transactions/:id/confirm
 * Transition a transaction from needs_review → confirmed
 */
router.post('/:id/confirm', async (req, res, next) => {
  try {
    const transactionId = parseInt(req.params.id, 10);
    if (Number.isNaN(transactionId)) {
      return sendError(res, 'Invalid transaction ID', 'VALIDATION_ERROR', 400);
    }

    const [existing] = await db
      .select({ id: transactions.id, status: transactions.status })
      .from(transactions)
      .where(and(eq(transactions.id, transactionId), eq(transactions.userId, req.user.id)))
      .limit(1);

    if (!existing) {
      return sendError(res, 'Transaction not found', 'NOT_FOUND', 404);
    }

    if (existing.status !== 'needs_review') {
      return sendError(
        res,
        `Transaction cannot be confirmed — current status is '${existing.status}'`,
        'INVALID_STATE_TRANSITION',
        400
      );
    }

    const [updated] = await db
      .update(transactions)
      .set({ status: 'confirmed', updatedAt: new Date() })
      .where(eq(transactions.id, transactionId))
      .returning({
        id: transactions.id,
        amount: transactions.amount,
        type: transactions.type,
        status: transactions.status,
        merchant: transactions.merchant,
        transactionDate: transactions.transactionDate,
        sourceId: transactions.sourceId,
        categoryId: transactions.categoryId,
      });

    return sendSuccess(res, { transaction: updated });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
