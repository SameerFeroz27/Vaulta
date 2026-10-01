const { z } = require('zod');

const DATE_REGEX = /^\d{4}-\d{2}-\d{2}$/;
const MAX_AMOUNT = 999999999999.99;

// ─── Loan Schemas ────────────────────────────────────────────────

const createLoanSchema = z.object({
  counterparty: z.string({ required_error: 'Person is required' }).trim().min(1, 'Person is required').max(100, 'Person cannot exceed 100 characters'),
  direction: z.enum(['lent', 'borrowed'], { required_error: 'Direction is required (lent or borrowed)' }),
  principal: z.number({ required_error: 'Amount is required' }).positive('Amount must be greater than 0').max(MAX_AMOUNT, 'Amount is too large'),
  issueDate: z.string({ required_error: 'Issue date is required' }).regex(DATE_REGEX, 'Issue date must be in YYYY-MM-DD format'),
  dueDate: z.string().regex(DATE_REGEX, 'Due date must be in YYYY-MM-DD format').optional(),
  notes: z.string().trim().max(500, 'Notes cannot exceed 500 characters').optional(),
  // Also record the money movement as a transaction, excluded from income/expense reports.
  recordTransaction: z.boolean().default(true),
}).refine((data) => !data.dueDate || data.dueDate >= data.issueDate, {
  message: 'Due date cannot be before the issue date',
  path: ['dueDate'],
});

const updateLoanSchema = z.object({
  counterparty: z.string().trim().min(1).max(100).optional(),
  direction: z.enum(['lent', 'borrowed']).optional(),
  principal: z.number().positive().max(MAX_AMOUNT).optional(),
  issueDate: z.string().regex(DATE_REGEX).optional(),
  dueDate: z.string().regex(DATE_REGEX).nullable().optional(),
  notes: z.string().trim().max(500).nullable().optional(),
});

// Query params for GET /api/loans (all arrive as strings from the URL)
const listLoansSchema = z.object({
  direction: z.enum(['lent', 'borrowed']).optional(),
  state: z.enum(['open', 'settled']).optional(),
  search: z.string().trim().max(100).optional(),
  sort: z.enum(['due_date', 'outstanding', 'created_at']).default('due_date'),
  order: z.enum(['asc', 'desc']).default('asc'),
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().positive().max(100, 'Limit cannot exceed 100').default(20),
});

// ─── Loan Payment Schemas ────────────────────────────────────────

const createLoanPaymentSchema = z.object({
  amount: z.number({ required_error: 'Amount is required' }).positive('Amount must be greater than 0').max(MAX_AMOUNT, 'Amount is too large'),
  paymentDate: z.string({ required_error: 'Payment date is required' }).regex(DATE_REGEX, 'Payment date must be in YYYY-MM-DD format'),
  note: z.string().trim().max(500, 'Note cannot exceed 500 characters').optional(),
  // Also record the money movement as a transaction, excluded from income/expense reports.
  recordTransaction: z.boolean().default(true),
  idempotencyKey: z.string().trim().max(100).optional(),
});

// Deliberately NO "amount must not exceed the outstanding balance" rule: repaying more
// than is owed settles the loan and reports the excess as a surplus (gift/tip/refund)
// rather than failing the request.

module.exports = {
  createLoanSchema,
  updateLoanSchema,
  listLoansSchema,
  createLoanPaymentSchema,
};
