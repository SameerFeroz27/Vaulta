const express = require('express');
const { db } = require('../config/db');
const { loans, loanPayments, transactions, sources } = require('../db/schema');
const { eq, and, isNull, sql } = require('drizzle-orm');
const authenticate = require('../middleware/auth');
const validate = require('../middleware/validate');
const {
  createLoanSchema,
  updateLoanSchema,
  listLoansSchema,
  createLoanPaymentSchema,
} = require('../validators/loan.schema');
const { sendSuccess, sendError } = require('../utils/response');
const {
  DIRECTION,
  KIND,
  round2,
  sumPaid,
  describeLoan,
  movementType,
  toDateString,
} = require('../services/loan');

const router = express.Router();

// All loan routes require authentication
router.use(authenticate);

// Loan money movements are cash in hand, so they use the Cash source. Cached after the
// first lookup since the sources table is fixed seed data.
let cashSourceId = null;

async function getCashSourceId() {
  if (cashSourceId) return cashSourceId;

  const [cash] = await db
    .select({ id: sources.id })
    .from(sources)
    .where(eq(sources.name, 'Cash'))
    .limit(1);

  const [fallback] = cash
    ? [cash]
    : await db.select({ id: sources.id }).from(sources).limit(1);

  cashSourceId = fallback?.id ?? null;
  return cashSourceId;
}

/**
 * Record a loan money movement as a transaction.
 *
 * It is a real cash movement and belongs in the ledger, but it is not income or
 * expense — the dashboard excludes any row carrying a `kind`.
 *
 * @param {object} options
 * @param {number} options.userId
 * @param {object} options.loan - row providing id, direction and counterparty
 * @param {string} options.kind - loan_disbursement | loan_repayment
 * @param {number} options.amount
 * @param {string} options.date - YYYY-MM-DD
 * @param {string} [options.description]
 * @param {string} [options.idempotencyKey]
 * @returns {Promise<number>} the new transaction id
 */
async function createLoanTransaction({
  userId,
  loan,
  kind,
  amount,
  date,
  description,
  idempotencyKey,
}) {
  const sourceId = await getCashSourceId();
  if (!sourceId) {
    throw new Error('No payment source available for loan transactions');
  }

  const [created] = await db
    .insert(transactions)
    .values({
      userId,
      sourceId,
      amount: round2(amount).toFixed(2),
      currency: 'PKR', // loans are PKR-only by design
      type: movementType(loan.direction, kind),
      status: 'confirmed',
      kind,
      loanId: loan.id,
      merchant: loan.counterparty,
      description: description || null,
      occurredAt: new Date(`${date}T00:00:00Z`),
      transactionDate: date,
      idempotencyKey: idempotencyKey || null,
    })
    .returning({ id: transactions.id });

  return created.id;
}

/** Total repaid against a loan. */
async function getPaidTotal(loanId) {
  const [row] = await db
    .select({ paid: sql`COALESCE(SUM(${loanPayments.amount}), 0)::numeric` })
    .from(loanPayments)
    .where(eq(loanPayments.loanId, loanId));

  return parseFloat(row?.paid ?? 0);
}

/**
 * Shape a loan row for the API: raw columns plus every derived money field.
 * @param {object} loan - raw loans row
 * @param {number} paid - total repaid
 * @param {number|null} [transactionId] - linked cash-movement transaction, when known
 */
function presentLoan(loan, paid, transactionId = undefined) {
  return {
    id: loan.id,
    counterparty: loan.counterparty,
    direction: loan.direction,
    principal: parseFloat(loan.principal),
    issueDate: toDateString(loan.issueDate),
    dueDate: toDateString(loan.dueDate),
    notes: loan.notes,
    ...describeLoan(loan, paid),
    ...(transactionId === undefined ? {} : { transactionId }),
    createdAt: loan.createdAt,
    updatedAt: loan.updatedAt,
  };
}

/** Load an active (not hidden) loan owned by the user, or null. */
async function findActiveLoan(loanId, userId) {
  const [loan] = await db
    .select()
    .from(loans)
    .where(and(eq(loans.id, loanId), eq(loans.userId, userId), isNull(loans.deletedAt)))
    .limit(1);

  return loan || null;
}

function parseId(value) {
  const id = parseInt(value, 10);
  return Number.isNaN(id) ? null : id;
}

// ─── GET /api/loans/summary ──────────────────────────────────────
/**
 * Per-person lending summary: what they owe me, what I owe them, and how much they
 * have repaid over time.
 *
 * What is owed counts ACTIVE loans only: removing a loan must take it out of what you
 * owe and are owed, since the dashboard reports these figures. `repaid` is the one field
 * that spans removed loans too, so deleting a loan never erases the fact that the person
 * repaid.
 *
 * People are grouped by a normalised name, so "Ali" and "ali " are one row. There is no
 * people table yet, so two different people sharing a name would merge.
 *
 * Also returns `overdueCount` and `overduePeople` — active loans past their due date —
 * which the dashboard card needs. Removed loans are excluded from those too: they are
 * gone from the user's view, so flagging them as overdue would be noise.
 */
router.get('/summary', async (req, res, next) => {
  try {
    const userId = req.user.id;

    const result = await db.execute(sql`
      WITH loan_totals AS (
        SELECT l.id,
               -- Person grouping key: lowercased, trimmed, with run-on whitespace
               -- collapsed, so "Ali Raza", "ali raza" and "Ali   Raza" are one person.
               -- POSIX [[:space:]] avoids backslash escaping inside the sql template.
               regexp_replace(lower(btrim(l.counterparty)), '[[:space:]]+', ' ', 'g') AS person_key,
               l.counterparty,
               l.direction,
               l.principal,
               l.deleted_at,
               l.created_at,
               COALESCE(SUM(p.amount), 0)::numeric AS paid
        FROM loans l
        LEFT JOIN loan_payments p ON p.loan_id = l.id
        WHERE l.user_id = ${userId}
        GROUP BY l.id
      )
      SELECT person_key,
             -- Names are stored exactly as the user typed them, so this shows the most
             -- recent spelling rather than imposing a house style on them.
             (array_agg(counterparty ORDER BY created_at DESC))[1] AS person,
             -- Only loans that still exist count as owed, so removing a loan takes it out
             -- of what you owe and are owed — which is what the dashboard reports.
             SUM(CASE WHEN deleted_at IS NULL AND direction = 'lent' THEN GREATEST(principal - paid, 0) ELSE 0 END)::numeric AS they_owe,
             SUM(CASE WHEN deleted_at IS NULL AND direction = 'borrowed' THEN GREATEST(principal - paid, 0) ELSE 0 END)::numeric AS i_owe,
             -- Repaid deliberately spans removed loans too, so deleting a loan never
             -- erases the fact that the person repaid.
             SUM(paid)::numeric AS repaid,
             COUNT(*) FILTER (WHERE deleted_at IS NULL)::int AS loan_count
      FROM loan_totals
      GROUP BY person_key
      ORDER BY person_key ASC
    `);

    const people = result.rows.map((row) => {
      const theyOwe = round2(parseFloat(row.they_owe));
      const iOwe = round2(parseFloat(row.i_owe));

      return {
        person: row.person,
        theyOwe,
        iOwe,
        repaid: round2(parseFloat(row.repaid)),
        loanCount: row.loan_count,
        net: round2(theyOwe - iOwe), // positive = they owe me more than I owe them
        state: theyOwe > 0 || iOwe > 0 ? 'open' : 'settled',
      };
    });

    // Listed on its own rather than alongside the per-person aggregate: anything
    // computed inside that GROUP BY would only see one person's loans, not the whole
    // set. Hidden loans are excluded — they are gone from the user's view, so
    // surfacing them as overdue would be noise.
    const overdueResult = await db.execute(sql`
      SELECT l.id, l.counterparty, l.due_date
      FROM loans l
      LEFT JOIN loan_payments p ON p.loan_id = l.id
      WHERE l.user_id = ${userId}
        AND l.deleted_at IS NULL
        AND l.due_date IS NOT NULL
        AND l.due_date < CURRENT_DATE
      GROUP BY l.id, l.counterparty, l.due_date
      HAVING COALESCE(SUM(p.amount), 0) < l.principal
      ORDER BY l.due_date ASC
    `);

    // One entry per person, grouped the same way the summary groups loans, so two
    // overdue loans from the same person name them once.
    const overduePeople = [];
    const seenPeople = new Set();
    for (const row of overdueResult.rows) {
      const key = row.counterparty.trim().toLowerCase().replace(/\s+/g, ' ');
      if (seenPeople.has(key)) continue;
      seenPeople.add(key);
      overduePeople.push(row.counterparty);
    }

    return sendSuccess(res, {
      people,
      overdueCount: overdueResult.rows.length,
      overduePeople,
    });
  } catch (err) {
    next(err);
  }
});

// ─── GET /api/loans ──────────────────────────────────────────────
/**
 * Active loans with their derived money fields.
 * Query: ?direction=&state=&search=&sort=&order=&page=&limit=
 */
router.get('/', async (req, res, next) => {
  try {
    const parsed = listLoansSchema.parse(req.query);
    const { direction, state: stateFilter, search, sort, order, page, limit } = parsed;
    const userId = req.user.id;
    const offset = (page - 1) * limit;

    // State and outstanding are derived, so filtering on them has to happen after the
    // repayment SUM — hence raw SQL rather than the query builder. Pagination stays in
    // SQL so the totals below can never disagree with the page of rows returned.
    const directionCondition = direction ? sql`AND l.direction = ${direction}` : sql``;
    const searchCondition = search
      ? sql`AND l.counterparty ILIKE ${'%' + search + '%'}`
      : sql``;

    const havingCondition =
      stateFilter === 'open'
        ? sql`HAVING COALESCE(SUM(p.amount), 0) < l.principal`
        : stateFilter === 'settled'
          ? sql`HAVING COALESCE(SUM(p.amount), 0) >= l.principal`
          : sql``;

    const sortDirection = order === 'asc' ? sql.raw('ASC') : sql.raw('DESC');
    // Loans with a due date come first, soonest first; undated ones fall to the end.
    const orderBy =
      sort === 'outstanding'
        ? sql`ORDER BY GREATEST(l.principal - COALESCE(SUM(p.amount), 0), 0) ${sortDirection}, l.id DESC`
        : sort === 'created_at'
          ? sql`ORDER BY l.created_at ${sortDirection}, l.id DESC`
          : sql`ORDER BY l.due_date ${sortDirection} NULLS LAST, l.id DESC`;

    const rows = await db.execute(sql`
      SELECT l.id, l.counterparty, l.direction, l.principal, l.issue_date, l.due_date,
             l.notes, l.created_at, l.updated_at,
             COALESCE(SUM(p.amount), 0)::numeric AS paid
      FROM loans l
      LEFT JOIN loan_payments p ON p.loan_id = l.id
      WHERE l.user_id = ${userId}
        AND l.deleted_at IS NULL
        ${directionCondition}
        ${searchCondition}
      GROUP BY l.id
      ${havingCondition}
      ${orderBy}
      LIMIT ${limit} OFFSET ${offset}
    `);

    const countResult = await db.execute(sql`
      SELECT COUNT(*)::int AS total
      FROM (
        SELECT l.id
        FROM loans l
        LEFT JOIN loan_payments p ON p.loan_id = l.id
        WHERE l.user_id = ${userId}
          AND l.deleted_at IS NULL
          ${directionCondition}
          ${searchCondition}
        GROUP BY l.id
        ${havingCondition}
      ) matched
    `);
    const total = countResult.rows[0]?.total ?? 0;

    const presented = rows.rows.map((row) =>
      presentLoan(
        {
          id: row.id,
          counterparty: row.counterparty,
          direction: row.direction,
          principal: row.principal,
          issueDate: row.issue_date,
          dueDate: row.due_date,
          notes: row.notes,
          createdAt: row.created_at,
          updatedAt: row.updated_at,
        },
        parseFloat(row.paid)
      )
    );

    return sendSuccess(res, {
      loans: presented,
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

// ─── POST /api/loans ─────────────────────────────────────────────
/**
 * Create a loan, optionally recording the money movement as a transaction.
 */
router.post('/', validate(createLoanSchema), async (req, res, next) => {
  try {
    const { counterparty, direction, principal, issueDate, dueDate, notes, recordTransaction } =
      req.body;

    const [loan] = await db
      .insert(loans)
      .values({
        userId: req.user.id,
        counterparty,
        direction,
        principal: round2(principal).toFixed(2),
        issueDate,
        dueDate: dueDate || null,
        notes: notes || null,
      })
      .returning();

    let transactionId = null;
    if (recordTransaction) {
      transactionId = await createLoanTransaction({
        userId: req.user.id,
        loan,
        kind: KIND.DISBURSEMENT,
        amount: principal,
        date: issueDate,
        description:
          direction === DIRECTION.LENT
            ? `Lent to ${counterparty}`
            : `Borrowed from ${counterparty}`,
      });
    }

    return sendSuccess(res, { loan: presentLoan(loan, 0, transactionId) }, 201);
  } catch (err) {
    next(err);
  }
});

// ─── GET /api/loans/:id ──────────────────────────────────────────
/**
 * A single loan with its repayment timeline.
 */
router.get('/:id', async (req, res, next) => {
  try {
    const loanId = parseId(req.params.id);
    if (loanId === null) {
      return sendError(res, 'Invalid loan ID', 'VALIDATION_ERROR', 400);
    }

    const loan = await findActiveLoan(loanId, req.user.id);
    if (!loan) {
      return sendError(res, 'Loan not found', 'NOT_FOUND', 404);
    }

    const payments = await db
      .select()
      .from(loanPayments)
      .where(eq(loanPayments.loanId, loanId))
      .orderBy(loanPayments.paymentDate, loanPayments.id);

    const paid = sumPaid(payments);

    const [disbursement] = await db
      .select({ id: transactions.id })
      .from(transactions)
      .where(and(eq(transactions.loanId, loanId), eq(transactions.kind, KIND.DISBURSEMENT)))
      .limit(1);

    return sendSuccess(res, {
      loan: presentLoan(loan, paid, disbursement?.id ?? null),
      payments: payments.map((payment) => ({
        id: payment.id,
        amount: parseFloat(payment.amount),
        paymentDate: toDateString(payment.paymentDate),
        transactionId: payment.transactionId,
        note: payment.note,
        createdAt: payment.createdAt,
      })),
    });
  } catch (err) {
    next(err);
  }
});

// ─── PUT /api/loans/:id ──────────────────────────────────────────
/**
 * Edit a loan. If the principal changes, the linked disbursement transaction is kept
 * in step so the ledger and the loan cannot disagree.
 */
router.put('/:id', validate(updateLoanSchema), async (req, res, next) => {
  try {
    const loanId = parseId(req.params.id);
    if (loanId === null) {
      return sendError(res, 'Invalid loan ID', 'VALIDATION_ERROR', 400);
    }

    const existing = await findActiveLoan(loanId, req.user.id);
    if (!existing) {
      return sendError(res, 'Loan not found', 'NOT_FOUND', 404);
    }

    const updateData = { ...req.body, updatedAt: new Date() };
    if (updateData.principal !== undefined) {
      updateData.principal = round2(updateData.principal).toFixed(2);
    }

    // Cross-check the dates against whichever values survive this update.
    const nextIssueDate = toDateString(updateData.issueDate ?? existing.issueDate);
    const nextDueDate = toDateString(
      updateData.dueDate === undefined ? existing.dueDate : updateData.dueDate
    );
    if (nextDueDate && nextDueDate < nextIssueDate) {
      return sendError(res, 'Due date cannot be before the issue date', 'VALIDATION_ERROR', 400);
    }

    const [updated] = await db
      .update(loans)
      .set(updateData)
      .where(eq(loans.id, loanId))
      .returning();

    // Keep the linked transactions in step so the ledger and the loan cannot disagree.
    if (updateData.principal !== undefined) {
      // Only the disbursement mirrors the principal; repayments are their own amounts.
      await db
        .update(transactions)
        .set({ amount: updateData.principal, updatedAt: new Date() })
        .where(and(eq(transactions.loanId, loanId), eq(transactions.kind, KIND.DISBURSEMENT)));
    }
    if (updateData.counterparty !== undefined) {
      // Every movement for this loan is labelled with the counterparty.
      await db
        .update(transactions)
        .set({ merchant: updateData.counterparty, updatedAt: new Date() })
        .where(
          and(eq(transactions.userId, req.user.id), eq(transactions.loanId, loanId))
        );
    }

    return sendSuccess(res, { loan: presentLoan(updated, await getPaidTotal(loanId)) });
  } catch (err) {
    next(err);
  }
});

// ─── DELETE /api/loans/:id ───────────────────────────────────────
/**
 * Remove a loan: it disappears from the active list and its own transactions are
 * deleted, but the loan and its repayments are kept in the background so the per-person
 * summary still shows that this person repaid.
 *
 * Only transactions this loan created are touched — `loan_id = :id AND kind IS NOT NULL`.
 * Nothing else in the ledger is affected.
 */
router.delete('/:id', async (req, res, next) => {
  try {
    const loanId = parseId(req.params.id);
    if (loanId === null) {
      return sendError(res, 'Invalid loan ID', 'VALIDATION_ERROR', 400);
    }

    const loan = await findActiveLoan(loanId, req.user.id);
    if (!loan) {
      return sendError(res, 'Loan not found', 'NOT_FOUND', 404);
    }

    const deletedTransactions = await db
      .delete(transactions)
      .where(
        and(
          eq(transactions.userId, req.user.id),
          eq(transactions.loanId, loanId),
          sql`${transactions.kind} IS NOT NULL`
        )
      )
      .returning({ id: transactions.id });

    // Repayments are deliberately kept; their transaction_id clears itself via the FK.
    await db
      .update(loans)
      .set({ deletedAt: new Date(), updatedAt: new Date() })
      .where(eq(loans.id, loanId));

    return sendSuccess(res, {
      message: 'Loan removed',
      deletedTransactionCount: deletedTransactions.length,
    });
  } catch (err) {
    next(err);
  }
});

// ─── POST /api/loans/:id/payments ────────────────────────────────
/**
 * Record a repayment, optionally recording the money movement as a transaction.
 *
 * Repaying MORE than is owed is accepted rather than rejected: the balance floors at
 * zero, the loan settles, and the excess comes back as `surplus` on the loan for the UI
 * to present as a gift, tip or refund.
 */
router.post('/:id/payments', validate(createLoanPaymentSchema), async (req, res, next) => {
  try {
    const loanId = parseId(req.params.id);
    if (loanId === null) {
      return sendError(res, 'Invalid loan ID', 'VALIDATION_ERROR', 400);
    }

    const loan = await findActiveLoan(loanId, req.user.id);
    if (!loan) {
      return sendError(res, 'Loan not found', 'NOT_FOUND', 404);
    }

    const { amount, paymentDate, note, recordTransaction, idempotencyKey } = req.body;

    if (idempotencyKey) {
      const [existing] = await db
        .select({ id: loanPayments.id })
        .from(loanPayments)
        .where(
          and(
            eq(loanPayments.userId, req.user.id),
            eq(loanPayments.idempotencyKey, idempotencyKey)
          )
        )
        .limit(1);

      if (existing) {
        return sendError(
          res,
          'Payment with this idempotency key already exists',
          'CONFLICT',
          409
        );
      }
    }

    const paidBefore = await getPaidTotal(loanId);
    const balanceBefore = describeLoan(loan, paidBefore);

    let transactionId = null;
    if (recordTransaction) {
      transactionId = await createLoanTransaction({
        userId: req.user.id,
        loan,
        kind: KIND.REPAYMENT,
        amount,
        date: paymentDate,
        description:
          loan.direction === DIRECTION.LENT
            ? `Repaid by ${loan.counterparty}`
            : `Repaid to ${loan.counterparty}`,
        idempotencyKey,
      });
    }

    const [payment] = await db
      .insert(loanPayments)
      .values({
        loanId,
        userId: req.user.id,
        amount: round2(amount).toFixed(2),
        paymentDate,
        transactionId,
        idempotencyKey: idempotencyKey || null,
        note: note || null,
      })
      .returning();

    const updatedLoan = presentLoan(loan, paidBefore + round2(amount));

    return sendSuccess(
      res,
      {
        payment: {
          id: payment.id,
          amount: parseFloat(payment.amount),
          paymentDate: toDateString(payment.paymentDate),
          transactionId: payment.transactionId,
          note: payment.note,
          createdAt: payment.createdAt,
        },
        loan: updatedLoan,
        // Convenience for the UI: how much of this payment went past the balance.
        settled: balanceBefore.outstanding <= round2(amount),
        surplusAdded: Math.min(round2(amount), Math.max(0, round2(amount) - balanceBefore.outstanding)),
      },
      201
    );
  } catch (err) {
    next(err);
  }
});

// ─── DELETE /api/loans/:id/payments/:paymentId ───────────────────
/**
 * Remove a repayment and the transaction it created. The loan is recomputed from the
 * remaining payments, so a settled loan reopens if this drops it below the principal.
 */
router.delete('/:id/payments/:paymentId', async (req, res, next) => {
  try {
    const loanId = parseId(req.params.id);
    const paymentId = parseId(req.params.paymentId);
    if (loanId === null || paymentId === null) {
      return sendError(res, 'Invalid id', 'VALIDATION_ERROR', 400);
    }

    const loan = await findActiveLoan(loanId, req.user.id);
    if (!loan) {
      return sendError(res, 'Loan not found', 'NOT_FOUND', 404);
    }

    const [payment] = await db
      .select()
      .from(loanPayments)
      .where(
        and(
          eq(loanPayments.id, paymentId),
          eq(loanPayments.loanId, loanId),
          eq(loanPayments.userId, req.user.id)
        )
      )
      .limit(1);

    if (!payment) {
      return sendError(res, 'Payment not found', 'NOT_FOUND', 404);
    }

    if (payment.transactionId) {
      await db.delete(transactions).where(eq(transactions.id, payment.transactionId));
    }

    await db.delete(loanPayments).where(eq(loanPayments.id, paymentId));

    return sendSuccess(res, {
      message: 'Payment removed',
      loan: presentLoan(loan, await getPaidTotal(loanId)),
    });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
