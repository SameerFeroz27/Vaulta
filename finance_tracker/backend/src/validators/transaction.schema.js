const { z } = require('zod');

// ─── Transaction Schemas ─────────────────────────────────────────

const createTransactionSchema = z.object({
  sourceId: z.number({ required_error: 'Source ID is required' }).int().positive('Source ID must be a positive integer'),
  categoryId: z.number().int().positive().optional(),
  amount: z.number({ required_error: 'Amount is required' }).positive('Amount must be greater than 0').max(999999999999.99, 'Amount is too large'),
  currency: z.string().length(3, 'Currency must be a 3-letter ISO code').toUpperCase().optional(),
  type: z.enum(['expense', 'income'], { required_error: 'Type is required (expense or income)' }),
  merchant: z.string().trim().max(200, 'Merchant name cannot exceed 200 characters').optional(),
  description: z.string().trim().max(1000, 'Description cannot exceed 1000 characters').optional(),
  occurredAt: z.string().datetime().optional(),
  transactionDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Date must be in YYYY-MM-DD format').optional(),
  cardLast4: z.string().length(4, 'Card last 4 must be exactly 4 characters').optional(),
  bankReference: z.string().trim().max(100).optional(),
  idempotencyKey: z.string().trim().max(100).optional(),
});

const updateTransactionSchema = z.object({
  sourceId: z.number().int().positive().optional(),
  categoryId: z.number().int().positive().nullable().optional(),
  amount: z.number().positive().max(999999999999.99).optional(),
  currency: z.string().length(3).toUpperCase().optional(),
  type: z.enum(['expense', 'income']).optional(),
  status: z.enum(['needs_review', 'confirmed', 'archived']).optional(),
  merchant: z.string().trim().max(200).nullable().optional(),
  description: z.string().trim().max(1000).nullable().optional(),
  occurredAt: z.string().datetime().optional(),
  transactionDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  cardLast4: z.string().length(4).nullable().optional(),
  bankReference: z.string().trim().max(100).nullable().optional(),
});

// Query params for GET /api/transactions (all come as strings from URL)
const listTransactionsSchema = z.object({
  month: z.string().regex(/^\d{4}-\d{2}$/, 'Month must be in YYYY-MM format').optional(),
  source: z.coerce.number().int().positive().optional(),
  category: z.coerce.number().int().positive().optional(),
  type: z.enum(['expense', 'income']).optional(),
  status: z.enum(['needs_review', 'confirmed', 'archived']).optional(),
  search: z.string().trim().max(200).optional(),
  sort: z.enum(['date', 'amount', 'created_at']).default('date'),
  order: z.enum(['asc', 'desc']).default('desc'),
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().positive().max(100, 'Limit cannot exceed 100').default(20),
});

// ─── Category Schemas ────────────────────────────────────────────

const createCategorySchema = z.object({
  name: z.string({ required_error: 'Name is required' }).trim().min(1, 'Name is required').max(50, 'Name cannot exceed 50 characters'),
  icon: z.string().trim().max(10).default('📁'),
  color: z.string().regex(/^#[0-9A-Fa-f]{6}$/, 'Color must be a valid hex color like #FF5733').default('#BDC3C7'),
  transactionType: z.enum(['expense', 'income', 'both']).default('expense'),
});

const updateCategorySchema = z.object({
  name: z.string().trim().min(1).max(50).optional(),
  icon: z.string().trim().max(10).optional(),
  color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional(),
  transactionType: z.enum(['expense', 'income', 'both']).optional(),
});

module.exports = {
  createTransactionSchema,
  updateTransactionSchema,
  listTransactionsSchema,
  createCategorySchema,
  updateCategorySchema,
};
