const {
  pgTable,
  serial,
  text,
  varchar,
  char,
  numeric,
  timestamp,
  date,
  integer,
  bigint,
  jsonb,
  uniqueIndex,
  index,
} = require('drizzle-orm/pg-core');
const { relations, sql } = require('drizzle-orm');

// 1. Users Table
const users = pgTable('users', {
  id: serial('id').primaryKey(),
  email: text('email').notNull().unique(),
  passwordHash: text('password_hash').notNull(),
  name: text('name').notNull(),
  currency: char('currency', { length: 3 }).notNull().default('PKR'),
  timezone: text('timezone').notNull().default('Asia/Karachi'),
  exchangeRates: jsonb('exchange_rates'), // { "USD": 280, "EUR": 300, ... } — 1 unit of X = N units of base currency
  status: text('status').notNull().default('active'), // active, inactive, deleted
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
});

// 2. Refresh Tokens Table (Hashed storage & rotation)
const refreshTokens = pgTable('refresh_tokens', {
  id: serial('id').primaryKey(),
  userId: integer('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  tokenHash: text('token_hash').notNull().unique(),
  expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
  revokedAt: timestamp('revoked_at', { withTimezone: true }),
  ipAddress: text('ip_address'),
  userAgent: text('user_agent'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
}, (table) => [
  index('idx_refresh_tokens_user_id').on(table.userId),
  index('idx_refresh_tokens_expires_at').on(table.expiresAt),
]);

// 2b. Password Reset Tokens Table (Hashed storage, 1-hour expiry, single-use)
const passwordResetTokens = pgTable('password_reset_tokens', {
  id: serial('id').primaryKey(),
  userId: integer('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  tokenHash: text('token_hash').notNull().unique(),
  expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
  usedAt: timestamp('used_at', { withTimezone: true }),
  ipAddress: text('ip_address'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
}, (table) => [
  index('idx_password_reset_tokens_user_id').on(table.userId),
  index('idx_password_reset_tokens_expires_at').on(table.expiresAt),
]);

// 3. Payment Sources Table (Fixed global seeds: Card, Cash, Online)
const sources = pgTable('sources', {
  id: serial('id').primaryKey(),
  name: text('name').notNull().unique(),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
});

// 4. Categories Table (Global default categories when userId is NULL, custom user categories when userId is set)
const categories = pgTable('categories', {
  id: serial('id').primaryKey(),
  userId: integer('user_id').references(() => users.id, { onDelete: 'cascade' }),
  name: text('name').notNull(),
  icon: text('icon').notNull().default('??'),
  color: text('color').notNull().default('#BDC3C7'),
  transactionType: text('transaction_type').notNull().default('expense'), // expense, income, both
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
}, (table) => [
  index('idx_categories_user_id').on(table.userId),
]);

// 5. Receipts / Jobs Table (Lightweight background processing queue & file store)
const receipts = pgTable('receipts', {
  id: serial('id').primaryKey(),
  userId: integer('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  transactionId: integer('transaction_id'), // Linked after transaction creation
  inputType: text('input_type').notNull(), // image, bank_message, sms, virtual_receipt
  filePath: text('file_path'),
  fileHash: text('file_hash'), // SHA-256 for duplicate receipt detection
  originalFileName: text('original_file_name'),
  mimeType: text('mime_type'),
  fileSizeBytes: bigint('file_size_bytes', { mode: 'number' }),
  rawText: text('raw_text'),
  rawPayload: jsonb('raw_payload'),
  aiResponse: jsonb('ai_response'),
  aiModel: text('ai_model'),
  ocrProvider: text('ocr_provider'), // groq_vision, tesseract, none
  status: text('status').notNull().default('queued'), // queued, processing, success, needs_review, failed, duplicate
  errorMessage: text('error_message'),
  attempts: integer('attempts').notNull().default(0),
  maxAttempts: integer('max_attempts').notNull().default(3),
  lockedAt: timestamp('locked_at', { withTimezone: true }),
  lockedBy: text('locked_by'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  processedAt: timestamp('processed_at', { withTimezone: true }),
}, (table) => [
  index('idx_receipts_user_id').on(table.userId),
  index('idx_receipts_status').on(table.status),
  index('idx_receipts_file_hash').on(table.userId, table.fileHash),
]);

// 6. Transactions Table
const transactions = pgTable('transactions', {
  id: serial('id').primaryKey(),
  userId: integer('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  sourceId: integer('source_id').notNull().references(() => sources.id, { onDelete: 'restrict' }),
  categoryId: integer('category_id').references(() => categories.id, { onDelete: 'set null' }),
  receiptId: integer('receipt_id').references(() => receipts.id, { onDelete: 'set null' }),
  amount: numeric('amount', { precision: 14, scale: 2 }).notNull(),
  currency: char('currency', { length: 3 }).notNull().default('PKR'),
  type: text('type').notNull().default('expense'), // expense, income
  status: text('status').notNull().default('confirmed'), // needs_review, confirmed, archived
  merchant: text('merchant'),
  description: text('description'),
  occurredAt: timestamp('occurred_at', { withTimezone: true }).notNull().defaultNow(),
  transactionDate: date('transaction_date').notNull(),
  cardLast4: char('card_last4', { length: 4 }),
  bankReference: text('bank_reference'),
  idempotencyKey: text('idempotency_key'),
  duplicateOfTransactionId: integer('duplicate_of_transaction_id'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
}, (table) => [
  index('idx_transactions_user_date').on(table.userId, table.transactionDate),
  index('idx_transactions_user_occurred').on(table.userId, table.occurredAt),
  index('idx_transactions_user_status').on(table.userId, table.status),
  index('idx_transactions_user_source').on(table.userId, table.sourceId),
  index('idx_transactions_user_category').on(table.userId, table.categoryId),
  index('idx_transactions_user_type').on(table.userId, table.type),
  index('idx_transactions_idempotency').on(table.userId, table.idempotencyKey),
]);

// 7. Budgets Table (Monthly overall or category-specific budgets)
const budgets = pgTable('budgets', {
  id: serial('id').primaryKey(),
  userId: integer('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  categoryId: integer('category_id').references(() => categories.id, { onDelete: 'cascade' }), // NULL = overall monthly budget
  amount: numeric('amount', { precision: 14, scale: 2 }).notNull(),
  period: text('period').notNull().default('monthly'), // monthly
  month: char('month', { length: 7 }).notNull(), // YYYY-MM
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
}, (table) => [
  uniqueIndex('idx_budgets_unique').on(table.userId, table.categoryId, table.month),
  index('idx_budgets_user_month').on(table.userId, table.month),
  index('idx_budgets_user_category_month').on(table.userId, table.categoryId, table.month),
]);

// Relationships
const usersRelations = relations(users, ({ many }) => ({
  refreshTokens: many(refreshTokens),
  passwordResetTokens: many(passwordResetTokens),
  transactions: many(transactions),
  receipts: many(receipts),
  categories: many(categories),
  budgets: many(budgets),
}));

const passwordResetTokensRelations = relations(passwordResetTokens, ({ one }) => ({
  user: one(users, { fields: [passwordResetTokens.userId], references: [users.id] }),
}));

const sourcesRelations = relations(sources, ({ many }) => ({
  transactions: many(transactions),
}));

const categoriesRelations = relations(categories, ({ one, many }) => ({
  user: one(users, { fields: [categories.userId], references: [users.id] }),
  transactions: many(transactions),
  budgets: many(budgets),
}));

const receiptsRelations = relations(receipts, ({ one }) => ({
  user: one(users, { fields: [receipts.userId], references: [users.id] }),
  transaction: one(transactions, { fields: [receipts.transactionId], references: [transactions.id] }),
}));

const transactionsRelations = relations(transactions, ({ one }) => ({
  user: one(users, { fields: [transactions.userId], references: [users.id] }),
  source: one(sources, { fields: [transactions.sourceId], references: [sources.id] }),
  category: one(categories, { fields: [transactions.categoryId], references: [categories.id] }),
  receipt: one(receipts, { fields: [transactions.receiptId], references: [receipts.id] }),
}));

const budgetsRelations = relations(budgets, ({ one }) => ({
  user: one(users, { fields: [budgets.userId], references: [users.id] }),
  category: one(categories, { fields: [budgets.categoryId], references: [categories.id] }),
}));

module.exports = {
  users,
  refreshTokens,
  passwordResetTokens,
  sources,
  categories,
  receipts,
  transactions,
  budgets,
  usersRelations,
  passwordResetTokensRelations,
  sourcesRelations,
  categoriesRelations,
  receiptsRelations,
  transactionsRelations,
  budgetsRelations,
};
