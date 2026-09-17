const { z } = require('zod');

const createBudgetSchema = z.object({
  amount: z.number({ required_error: 'Amount is required' }).positive('Amount must be greater than 0').max(999999999999.99, 'Amount is too large'),
  month: z.string({ required_error: 'Month is required' }).regex(/^\d{4}-\d{2}$/, 'Month must be in YYYY-MM format'),
  categoryId: z.number().int().positive().nullable().optional(),
});

const updateBudgetSchema = z.object({
  amount: z.number().positive().max(999999999999.99).optional(),
  month: z.string().regex(/^\d{4}-\d{2}$/).optional(),
  categoryId: z.number().int().positive().nullable().optional(),
});

const listBudgetsSchema = z.object({
  month: z.string().regex(/^\d{4}-\d{2}$/, 'Month must be in YYYY-MM format').optional(),
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().positive().max(100, 'Limit cannot exceed 100').default(20),
});

module.exports = {
  createBudgetSchema,
  updateBudgetSchema,
  listBudgetsSchema,
};
