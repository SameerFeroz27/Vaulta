# Finance Tracker Backend (v3) — Actionable Task List

## Phase 1: Project Setup & Database
- [ ] Initialize `backend/package.json` with dependencies (`express`, `pg`, `drizzle-orm`, `drizzle-kit`, `dotenv`, `zod`, `bcryptjs`, `jsonwebtoken`, `multer`, `groq-sdk`, `tesseract.js`, `cors`, `morgan`)
- [ ] Create `backend/.env.example` and `backend/.env` with configuration templates
- [ ] Setup `drizzle.config.js` and database connection pool in `src/config/db.js`
- [ ] Define PostgreSQL schema in `src/db/schema.js`:
  - [ ] `users` (citext email, password_hash, timezone, currency, status)
  - [ ] `refresh_tokens` (hashed tokens, user_id, expiry, revocation)
  - [ ] `sources` (Card, Cash, Online)
  - [ ] `categories` (global defaults + user custom categories)
  - [ ] `transactions` (status: needs_review/confirmed/archived, idempotency_key, duplicate_of_transaction_id)
  - [ ] `receipts` (job statuses: queued/processing/success/needs_review/failed/duplicate, file_hash, ai_response)
  - [ ] `budgets` (monthly overall & per-category budgets)
- [ ] Write seed script `src/db/seed.js` for sources and default categories
- [ ] Configure `app.js` and `index.js` with centralized JSON parsing, CORS, and error handlers

## Phase 2: Authentication System
- [ ] Create password hashing (`src/utils/password.js`) and JWT helpers (`src/utils/jwt.js`)
- [ ] Build Zod validators (`src/validators/auth.schema.js`)
- [ ] Implement Auth Repository & Controller:
  - [ ] `POST /api/auth/register`
  - [ ] `POST /api/auth/login`
  - [ ] `POST /api/auth/refresh` (with token rotation & revocation)
  - [ ] `POST /api/auth/logout`
  - [ ] `GET /api/auth/me`
- [ ] Build `src/middleware/auth.js` and rate-limiting middleware

## Phase 3: Categories & Transaction CRUD
- [ ] Build category endpoints:
  - [ ] `GET /api/categories` (global + user-specific)
  - [ ] `POST`, `PUT`, `DELETE /api/categories/:id`
- [ ] Build transaction Zod validation schemas (`src/validators/transaction.schema.js`)
- [ ] Implement Transaction endpoints:
  - [ ] `POST /api/transactions` (manual entry, default status: `confirmed`)
  - [ ] `GET /api/transactions` (pagination, filters: `month`, `source`, `category`, `type`, `status`, search)
  - [ ] `GET /api/transactions/:id`
  - [ ] `PUT /api/transactions/:id`
  - [ ] `DELETE /api/transactions/:id`
  - [ ] `POST /api/transactions/:id/confirm` (transition `needs_review` -> `confirmed`)

## Phase 4: Async Receipt & Bank Message Bot Pipeline
- [ ] Setup file upload middleware (`src/middleware/upload.js`) with Multer & validation
- [ ] Implement receipt ingestion routes:
  - [ ] `POST /api/receipts/scan` (save image, create `queued` receipt, return `receiptId` immediately)
  - [ ] `POST /api/receipts/bank-message` (save raw text, create `queued` receipt, return `receiptId`)
  - [ ] `GET /api/receipts/:id` (polling status endpoint)
  - [ ] `GET /api/receipts`
  - [ ] `POST /api/receipts/:id/reprocess`
- [ ] Build AI & OCR services:
  - [ ] Groq Vision extraction (`src/services/ai.js`)
  - [ ] Tesseract.js fallback OCR + Groq Text (`src/services/ocr.js`)
  - [ ] Zod schema validator for AI output (`src/validators/ai-output.schema.js`)
- [ ] Build Deduplication & Idempotency engine (`src/services/duplicate.js`)
- [ ] Implement Background Worker (`src/worker.js`):
  - [ ] DB polling loop with `FOR UPDATE SKIP LOCKED`
  - [ ] OCR/Vision parsing → validation → deduplication → transaction creation
  - [ ] Mark status: `success`, `needs_review`, `failed`, or `duplicate`

## Phase 5: Dashboard Analytics
- [ ] Implement aggregated dashboard endpoints:
  - [ ] `GET /api/dashboard/summary?month=YYYY-MM` (Income, Expense, Balance, Transaction Count)
  - [ ] `GET /api/dashboard/expense-by-category?month=YYYY-MM` (Pie chart data with colors & icons)
  - [ ] `GET /api/dashboard/expense-by-source?month=YYYY-MM` (Pie chart data for Card/Cash/Online)
  - [ ] `GET /api/dashboard/expense-trend?months=6` (Bar chart historical comparison)
  - [ ] `GET /api/dashboard/budget-status?month=YYYY-MM` (Budget progress)

## Phase 6: Monthly Budgets
- [ ] Build budget schemas (`src/validators/budget.schema.js`)
- [ ] Implement Budget routes:
  - [ ] `POST /api/budgets` (overall or category-specific)
  - [ ] `GET /api/budgets` (with computed spent and remaining amounts)
  - [ ] `PUT /api/budgets/:id`
  - [ ] `DELETE /api/budgets/:id`

## Phase 7: Testing, Error Handling & Polish
- [ ] Setup Vitest + Supertest suite
- [ ] Write integration tests for Auth (register, login, refresh rotation)
- [ ] Write tests for Transaction CRUD, filters, and dashboard aggregations
- [ ] Write worker mock tests (Groq parsing, Tesseract fallback, duplicate detection)
- [ ] Finalize logging (`morgan`) and central error handling middleware
