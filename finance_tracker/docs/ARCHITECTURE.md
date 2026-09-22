# Vaulta — Architecture & Technical Reference

> Exhaustive technical reference for the Vaulta finance tracker.
> For a quick overview and setup, see the [README](../README.md).
> For product vision and design rationale, see [vision.md](vision.md).

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Frontend — Flutter App](#2-frontend--flutter-app)
3. [Backend — Express API](#3-backend--express-api)
4. [Database](#4-database)
5. [Authentication & Security](#5-authentication--security)
6. [AI Receipt Pipeline](#6-ai-receipt-pipeline)
7. [Configuration](#7-configuration)
8. [API Response Format](#8-api-response-format)
9. [Testing](#9-testing)

---

## 1. System Overview

Vaulta is a monorepo with two independent applications that communicate over REST/JSON:

```
┌─────────────────────────────────────────────────────┐
│                   Flutter App                        │
│  (Android / Web / Desktop)                          │
│                                                     │
│  Screens → Providers → Services → ApiClient        │
│                                      │              │
│                    flutter_secure_storage ◄────────┤ │
│                    (JWT tokens, settings)           │
└─────────────────────────────────────────────────────┘
                       │ HTTP / Bearer JWT
                       ▼
┌─────────────────────────────────────────────────────┐
│              Express API (port 5000)                │
│                                                     │
│  Routes → Middleware → Validators → DB             │
│    │                                                │
│    ├── /api/auth                                    │
│    ├── /api/transactions                            │
│    ├── /api/categories                              │
│    ├── /api/budgets                                 │
│    ├── /api/receipts                                │
│    └── /api/dashboard                               │
│                                                     │
│  Background Worker (forked child process)           │
│    polls receipts → Groq AI / Tesseract → DB       │
└─────────────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│              PostgreSQL (Drizzle ORM)               │
│  users · refresh_tokens · password_reset_tokens     │
│  sources · categories · receipts · transactions     │
│  budgets                                            │
└─────────────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│              External Services                      │
│  Groq Vision API (receipt images)                   │
│  Groq Text API (bank SMS, OCR structuring)          │
│  Tesseract.js OCR (fallback, local)                 │
│  SMTP / Nodemailer (password reset OTP emails)      │
│  open.er-api.com (live exchange rates)              │
└─────────────────────────────────────────────────────┘
```

**Communication:** The Flutter `ApiClient` sends `Bearer` JWT in the `Authorization` header, handles the `{ success, data }` / `{ success: false, error }` envelope, and auto-refreshes expired access tokens. File uploads use `multipart/form-data`.

---

## 2. Frontend — Flutter App

### 2.1 App Bootstrap & Routing (`lib/main.dart`)

**Initialization sequence:**
1. `WidgetsFlutterBinding.ensureInitialized()`
2. Create a single `ApiClient` instance — loads stored tokens and API URL override from `flutter_secure_storage`
3. Construct all providers and wire dependencies:
   - `ApiClient.onAuthFailed = authProvider.forceLogout` — redirect to login on refresh failure
   - `transactionProvider.setDependents(dashboardProvider, budgetProvider)` — dashboard & budgets auto-refresh when transactions change
   - `authProvider.registerResetCallback(...)` for every provider — cached data cleared on login/logout/user switch
4. Inject all providers via `MultiProvider` (mix of `Provider.value` for `ApiClient` and `ChangeNotifierProvider.value` for the rest)

**Routing (GoRouter):**
- `refreshListenable: authProvider` — router rebuilds when auth state changes
- Redirect guard: unauthenticated → `/login`; authenticated on auth routes → `/`
- Shows spinner while auth status is `unknown`

| Route | Screen | Description |
|-------|--------|-------------|
| `/login` | `LoginScreen` | Email + password |
| `/register` | `RegisterScreen` | Name + email + password |
| `/forgot-password` | `ForgotPasswordScreen` | Request reset token |
| `/reset-password` | `ResetPasswordScreen` | New password (receives token via `state.extra`) |
| `/` | `MainScaffold` | 3-tab bottom nav: Dashboard, Transactions, Settings |

**MainScaffold:** `BottomNavigationBar` with `IndexedStack` (preserves state across tabs).

### 2.2 State Management — Providers (`lib/providers/`)

All providers extend `ChangeNotifier`.

| Provider | Responsibility |
|----------|---------------|
| `AuthProvider` | Auth status (`authenticated` / `unauthenticated` / `unknown`), current user, login, register, logout, profile update (including exchange rates), forgot password (email OTP), reset password, change password, `refreshExchangeRates()` (auto-fetches live rates on session restore and currency change). Registers reset callbacks to clear dependent caches on logout. |
| `TransactionProvider` | Transaction list, pagination (infinite scroll), filters (type, source, search, sort, order), CRUD operations. Notifies `DashboardProvider` and `BudgetProvider` on changes. |
| `DashboardProvider` | Dashboard summary (income, expense, balance, count, top merchants), expense-by-category, expense-by-source, expense trend, budget status. Month navigation. |
| `CategoryProvider` | Category list (global defaults + user custom), create, update, delete. |
| `BudgetProvider` | Budget list with computed spending, create, update, delete. Month navigation. |
| `ReceiptProvider` | Receipt scan upload (image + bank message), poll status, receipt list (history), reprocess. |
| `ThemeProvider` | Theme mode (`light` / `dark` / `system`), persisted in secure storage. |

### 2.3 Services — API Layer (`lib/services/`)

**`ApiClient`** (`api_client.dart`) — the core HTTP client:
- Injects `Bearer` access token into every request
- Auto-refreshes on `401` with error code `TOKEN_EXPIRED` — calls `/auth/refresh`, rotates both tokens, retries the original request
- Unwraps the `{ success, data }` envelope; throws `ApiException` on `{ success: false, error }`
- Handles `multipart/form-data` uploads (receipt images)
- Dependencies (`http.Client`, `FlutterSecureStorage`) are injectable for testing
- `onAuthFailed` callback triggers `forceLogout` when refresh fails

**Domain services** (all use `ApiClient`):

| Service | Endpoints Called |
|---------|-----------------|
| `AuthService` | register, login, logout, refresh, me (GET/PUT with exchangeRates), change password, forgot/reset password (OTP) |
| `ExchangeRateService` | `fetchRates(baseCurrency)` — fetches live rates from `open.er-api.com/v6/latest/{base}`, inverts to "1 target = N base" format, filters to supported currencies |
| `TransactionService` | list (with filters), create, get, update, delete, confirm |
| `CategoryService` | list, create, update, delete |
| `BudgetService` | list, create, update, delete |
| `DashboardService` | summary, expense-by-category, expense-by-source, expense-trend, budget-status |
| `ReceiptService` | scan (image upload), bank-message, list, get (poll), reprocess |

### 2.4 Models (`lib/models/`)

| Model | Key Fields |
|-------|------------|
| `User` | `id`, `email`, `name`, `currency`, `timezone`, `exchangeRates` (`Map<String, double>?` — rates relative to base currency, e.g. `{'USD': 280}` means 1 USD = 280 base units) |
| `Transaction` | `id`, `amount`, `currency`, `type` (expense/income), `status`, `merchant`, `description`, `occurredAt`, `transactionDate`, `source`, `category`, `receiptId`, `cardLast4`, `bankReference` |
| `TransactionFilters` | `type`, `sourceId`, `search`, `sortBy`, `order` |
| `Pagination` | `page`, `limit`, `total`, `totalPages` |
| `Category` | `id`, `name`, `icon`, `color`, `transactionType`, `isGlobal` |
| `Budget` | `id`, `amount`, `month`, `categoryId`, `category`, `spent`, `remaining`, `percentage`, `overBudget` |
| `BudgetStatus` | Overall + per-category budget status with spending |
| `DashboardSummary` | `totalIncome`, `totalExpense`, `balance`, `transactionCount`, `topMerchants` |
| `TopMerchant` | `merchant`, `totalAmount`, `transactionCount` |
| `ExpenseBreakdown` | `categoryId`, `categoryName`, `icon`, `color`, `total`, `percentage` |
| `ExpenseTrend` | `month`, `totalExpense`, `totalIncome` |
| `Receipt` | `id`, `inputType`, `status`, `merchant`, `amount`, `createdAt`, `processedAt`, `errorMessage` |
| `ScanResult` | `receipt`, `transaction` |
| `ReceiptTransaction` | Parsed transaction from AI |
| `ReceiptDetail` | Full receipt detail with linked transaction |

### 2.5 Screens (`lib/screens/`)

#### Auth Screens (`screens/auth/`)

| Screen | Description |
|--------|-------------|
| `LoginScreen` | Email + password form with validation. "Forgot Password?" link, link to register. Scrollable keyboard-safe layout. |
| `RegisterScreen` | Full name + email + password. Password min 8 chars. Auto-logs in on success. Scrollable keyboard-safe layout. |
| `ForgotPasswordScreen` | Enter email → backend sends 6-digit OTP via email → navigates to reset screen. |
| `ResetPasswordScreen` | 6-digit code + new password + confirm. On success, navigates to login. |

#### Dashboard (`screens/dashboard/`)

| Screen | Description |
|--------|-------------|
| `DashboardScreen` | Month selector (prev/next). Summary cards: Income, Expense, Balance (color-coded), transaction count. Expense-by-Category pie chart. Expense-by-Source pie chart. Expense Trend bar chart. Top Merchants list. Pull-to-refresh. Empty-state with "Add Transaction" CTA. |

#### Transactions (`screens/transactions/`)

| Screen | Description |
|--------|-------------|
| `TransactionListScreen` | Paginated list with infinite scroll, pull-to-refresh, empty state. App bar: scan-receipt icon, filter icon. FAB to add. |
| `TransactionFormScreen` | Add/edit. Type toggle (expense/income), amount (currency-prefixed), **per-transaction currency dropdown** (all 9 currencies), live conversion hint ("≈ ₨{converted} {baseCurrency}") when currency differs from base, source dropdown (Card/Cash/Online), category dropdown (filtered by type), date picker, merchant, description. |
| `TransactionDetailScreen` | Amount with sign, status chip (Confirmed / Needs Review / Archived). Rows: type, category (icon+name), source, date, merchant, description, card last4, bank reference. Edit & delete actions. |
| `TransactionFilterSheet` (widget) | Bottom sheet: type (all/expense/income), source, text search, sort (date/amount), order (asc/desc), "Clear All". |

#### Receipts (`screens/receipts/`)

| Screen | Description |
|--------|-------------|
| `ReceiptScanScreen` | Three modes via segmented button: Cash Receipt (camera/gallery), Online Receipt (screenshot upload), Bank Message (paste SMS). Expense/Income toggle for image modes. Dismissible instructions card. Polls receipt status every 2s until terminal state. Shows parsed transaction on success. "Try Again" reprocess on failure. |
| `ReceiptListScreen` | Scan history. Input-type icon (Cash/Card/Online), merchant, date, amount, status badge. Pull-to-refresh. |

#### Categories (`screens/categories/`)

| Screen | Description |
|--------|-------------|
| `CategoryManagementScreen` | Lists Default Categories (global, read-only, badged "Default") and Your Categories (user-created, editable). |
| `CategoryFormScreen` | Name, transaction type (expense/income/both), emoji icon (24 presets + custom text), color (16 preset palette). Delete with confirmation. Conflict detection. |

#### Budgets (`screens/budgets/`)

| Screen | Description |
|--------|-------------|
| `BudgetListScreen` | Month selector. Overall Budget + per-category budgets with progress cards (amount, spent, remaining, percentage, over-budget warning). |
| `BudgetFormScreen` | Amount (currency-prefixed), month (prev/next navigator), category dropdown ("Overall Budget" or expense category). Delete with confirmation. Conflict detection. |

#### Settings (`screens/settings/`)

| Screen | Description |
|--------|-------------|
| `SettingsScreen` | Profile header (avatar initial, name, email). **Account**: Base Currency picker (9 currencies, changing currency clears & re-fetches exchange rates), Exchange Rates tile (auto-fetched from live API, view/refresh dialog), timezone (display only), Change Password dialog. **App**: manage categories, manage budgets, scan history. **Appearance**: Light/Dark/Auto toggle. **Network**: backend URL config dialog (custom API base URL, reset to default). **About**: version 1.0.0. **Logout** (with confirmation). |

### 2.6 Widgets (`lib/widgets/`)

| Widget | Location | Description |
|--------|----------|-------------|
| `ConfirmDialog` | `common/` | Confirmation dialog with title, message, confirm/cancel |
| `EmptyState` | `common/` | Empty list placeholder with icon, message, optional CTA |
| `ErrorState` | `common/` | Error display with message and retry |
| `LoadingIndicator` | `common/` | Centered spinner |
| `SummaryCard` | `dashboard/` | Dashboard summary card (label, value, color) |
| `ExpensePieChart` | `dashboard/` | Pie chart for category/source breakdown |
| `ExpenseBarChart` | `dashboard/` | Bar chart for expense trend |
| `BudgetProgressCard` | `dashboard/` | Budget progress with bar, spent, remaining |
| `TransactionCard` | `transactions/` | Transaction list item with amount, category, date |
| `TransactionFilterSheet` | `transactions/` | Filter bottom sheet |

### 2.7 Config & Utils

**`lib/config/constants.dart`:**
- API base URL (platform-aware):
  - Android: `http://192.168.9.172:5000/api` (LAN IP for real devices)
  - Web/desktop/iOS: `http://localhost:5000/api`
  - User override persisted in secure storage takes precedence
- Currencies: `PKR`, `USD`, `EUR`, `GBP`, `AED`, `INR`, `SAR`, `CAD`, `AUD`
- Default exchange rates to PKR: `{'USD': 280, 'EUR': 300, 'GBP': 350, 'AED': 76, 'INR': 3.3, 'SAR': 75, 'CAD': 200, 'AUD': 185}`
- Payment sources: Card (1), Cash (2), Online (3)
- Secure storage keys: `access_token`, `refresh_token`, `api_base_url`, `theme_mode`

**`lib/config/theme.dart`:**
- Material 3, seed color blue `#1976D2`
- Light & dark themes
- Semantic colors: expense red `#E53935`, income green `#43A047`
- White/light-gray surfaces; blue reserved for interactive elements

**`lib/utils/formatters.dart`:**
- `formatCurrency(amount, currency)` — currency symbol + formatted number
- `formatDate(date)` — full date
- `formatShortDate(date)` — abbreviated date
- `formatMonth(month)` — month label
- `currentMonth()` — current YYYY-MM string

### 2.8 Frontend Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `http` | ^1.2.0 | REST API calls |
| `http_parser` | ^4.1.0 | MIME type parsing for multipart |
| `provider` | ^6.1.2 | State management (ChangeNotifier) |
| `go_router` | ^14.2.0 | Declarative routing with auth redirects |
| `fl_chart` | ^0.69.0 | Dashboard pie/bar charts |
| `flutter_secure_storage` | ^9.2.2 | Secure JWT token & settings persistence |
| `intl` | ^0.19.0 | Currency/date formatting |
| `image_picker` | ^1.1.2 | Camera/gallery for receipt scanning |
| `cupertino_icons` | ^1.0.8 | iOS-style icons |
| `flutter_lints` | ^6.0.0 (dev) | Lint rules |
| `flutter_launcher_icons` | ^0.14.1 (dev) | App icon generation |

---

## 3. Backend — Express API

### 3.1 Boot Sequence (`src/index.js`)

The `boot()` function runs sequentially:

1. **Verify DB connection** — `pool.query('SELECT 1')`; exits if PostgreSQL unreachable
2. **Auto-migrate** — runs Drizzle migrations programmatically (`runMigrations()`), unless `AUTO_MIGRATE=false`
3. **Auto-seed** — idempotent seed of default sources + categories, unless `AUTO_SEED=false`
4. **Start Express server** on `PORT` (default 5000)
5. **Fork worker** — spawns `src/worker.js` as a child process (unless `ENABLE_WORKER=false`); auto-restarts on exit after 3s
6. **Token cleanup** — `setInterval` every 1 hour deletes expired/revoked refresh tokens
7. **Graceful shutdown** — on SIGTERM/SIGINT: clears timer, kills worker, closes HTTP server, ends DB pool
8. Global `uncaughtException` / `unhandledRejection` handlers

### 3.2 Express App (`src/app.js`)

| Middleware | Configuration |
|------------|---------------|
| `trust proxy` | 1 (correct `req.ip` behind reverse proxy) |
| CORS | Origins from `CORS_ORIGIN` env (comma-separated), defaults to `*` |
| `express.json` | 10mb limit |
| `express.urlencoded` | 10mb limit |
| `morgan` | `'dev'` logging |
| Static files | `/uploads` served from `./uploads` |
| Error handler | Mounted last (centralized) |

**Health check:** `GET /api/health` → `{ success: true, data: { status: 'healthy', timestamp } }`

**Route mounting:**

| Prefix | Router |
|--------|--------|
| `/api/auth` | `routes/auth.js` |
| `/api/categories` | `routes/categories.js` |
| `/api/transactions` | `routes/transactions.js` |
| `/api/receipts` | `routes/receipts.js` |
| `/api/dashboard` | `routes/dashboard.js` |
| `/api/budgets` | `routes/budgets.js` |

### 3.3 API Routes — Complete Reference

#### Auth (`/api/auth`)

| Method | Path | Auth | Rate Limit | Description |
|--------|------|------|------------|-------------|
| POST | `/auth/register` | — | authLimiter | Register: `{ name, email, password }` → `{ user, accessToken, refreshToken }` |
| POST | `/auth/login` | — | authLimiter | Login: `{ email, password }` → `{ user, accessToken, refreshToken }` |
| POST | `/auth/refresh` | — | authLimiter | Rotate: `{ refreshToken }` → new token pair. Detects reuse → revokes all user tokens. |
| POST | `/auth/logout` | — | authLimiter | Revoke: `{ refreshToken }` → revokes token server-side |
| GET | `/auth/me` | ✓ | — | Get current user profile |
| PUT | `/auth/me` | ✓ | — | Update profile: `{ name, currency, timezone, exchangeRates }`. Changing currency resets `exchangeRates` to null. Exchange rates validated as 3-letter code → number > 0. |
| PUT | `/auth/me/password` | ✓ | — | Change password: `{ currentPassword, newPassword }`. Rejects same password (`SAME_PASSWORD`). Does not revoke sessions. |
| POST | `/auth/forgot-password` | — | passwordResetLimiter | Send 6-digit OTP: `{ email }` → OTP hashed (SHA-256) and stored with 1-hour expiry, emailed via SMTP. Returns 404 if email not found. |
| POST | `/auth/reset-password` | — | passwordResetLimiter | Reset: `{ token, password }` → verifies 6-digit OTP, updates password, marks token used, revokes all refresh tokens. |

#### Transactions (`/api/transactions`)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/transactions` | ✓ | Paginated list. Query: `page`, `limit` (max 100), `month` (YYYY-MM), `source`, `category`, `type` (expense/income), `status`, `search`, `sort` (date/amount/created_at), `order` (asc/desc). Joins source + category. |
| POST | `/transactions` | ✓ | Create. Body: `{ amount, currency, type, sourceId, categoryId?, merchant?, description?, occurredAt, idempotencyKey? }`. Default status: `confirmed`. Validates source + category ownership. |
| GET | `/transactions/:id` | ✓ | Get single transaction with joined source + category |
| PUT | `/transactions/:id` | ✓ | Update transaction fields |
| DELETE | `/transactions/:id` | ✓ | Delete transaction |
| POST | `/transactions/:id/confirm` | ✓ | Transition `needs_review` → `confirmed` |

#### Categories (`/api/categories`)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/categories` | ✓ | List global defaults (`userId = NULL`) + user's custom categories |
| POST | `/categories` | ✓ | Create custom category: `{ name, icon, color, transactionType }`. Dedup by name per user. |
| PUT | `/categories/:id` | ✓ | Update own category (cannot edit globals) |
| DELETE | `/categories/:id` | ✓ | Delete own category. Transactions set to `categoryId = NULL`. |

#### Budgets (`/api/budgets`)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/budgets` | ✓ | List with computed spending. Query: `month`, `page`, `limit`. Returns `spent`, `remaining`, `percentage`, `overBudget` per budget. |
| POST | `/budgets` | ✓ | Create: `{ amount, month, categoryId? }`. No categoryId = overall budget. Unique per (user, category, month). |
| PUT | `/budgets/:id` | ✓ | Update: `{ amount?, month?, categoryId? }` |
| DELETE | `/budgets/:id` | ✓ | Delete budget |

#### Receipts (`/api/receipts`)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/receipts/scan` | ✓ | Upload receipt image (multipart, field `receipt`). Body: `inputType` (image/virtual_receipt), `transactionType` (expense/income). SHA-256 dedup. Returns 202 with receipt ID. |
| POST | `/receipts/bank-message` | ✓ | Submit bank SMS: `{ message, transactionType? }`. Max 5000 chars. SHA-256 dedup. Returns 202. |
| GET | `/receipts` | ✓ | List user's receipts (paginated). Includes input type, status, merchant, amount. |
| GET | `/receipts/:id` | ✓ | Poll receipt status + linked transaction. Used by frontend every 2s. |
| POST | `/receipts/:id/reprocess` | ✓ | Requeue a `failed` or `needs_review` receipt |

#### Dashboard (`/api/dashboard`)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/dashboard/summary` | ✓ | Query: `month` (YYYY-MM). Returns: `totalIncome`, `totalExpense`, `balance`, `transactionCount`, `topMerchants` (top 5). **All amounts converted to base currency via `users.exchange_rates`.** |
| GET | `/dashboard/expense-by-category` | ✓ | Query: `month`. Returns expense totals grouped by category with `%`, `icon`, `color` for pie chart. **Amounts currency-converted.** |
| GET | `/dashboard/expense-by-source` | ✓ | Query: `month`. Returns expense totals grouped by payment source. **Amounts currency-converted.** |
| GET | `/dashboard/expense-trend` | ✓ | Query: `months` (default 6, max 24). Returns monthly expense & income for last N months. **Amounts currency-converted.** |
| GET | `/dashboard/budget-status` | ✓ | Query: `month`. Returns budget vs. actual spent per category + overall. **Spent amounts currency-converted.** |

#### Health

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/health` | `{ success: true, data: { status: 'healthy', timestamp } }` |

### 3.4 Middleware (`src/middleware/`)

| Middleware | File | Description |
|------------|------|-------------|
| **Auth** | `auth.js` | Verifies JWT access token from `Authorization: Bearer`, loads user from DB (including `exchangeRates`), checks `status === 'active'`, attaches `req.user`. Returns `TOKEN_EXPIRED` code on expiry. |
| **Validate** | `validate.js` | Zod schema validation. Parses `req.body` (default) or specified source, replaces with validated data. Converts `ZodError` to 400 with field-level details. |
| **Rate Limit** | `rate-limit.js` | `authLimiter`: 30 req / 15 min / IP. `passwordResetLimiter`: 5 req / hour / IP. Standard headers, `trust proxy` enabled. |
| **Upload** | `upload.js` | Multer disk storage in `UPLOAD_DIR` with random 16-byte hex filenames. Max size from `MAX_FILE_SIZE_MB`. Allowed: jpeg, jpg, png, webp, gif, bmp. Field name: `receipt`. |
| **Error Handler** | `error-handler.js` | Centralized. Handles ZodError (400), Multer errors (FILE_TOO_LARGE), JSON parse errors (INVALID_JSON), and generic errors (500). |

### 3.5 Services (`src/services/`)

| Service | File | Description |
|---------|------|-------------|
| **AI** | `ai.js` | Groq SDK wrapper. `parseReceiptWithVision(imageBase64)` → vision model. `parseTextWithGroq(text)` → text model. Retry logic with 429 backoff. Strips `<think>` reasoning tags and markdown fences. JSON-format fallback. |
| **OCR** | `ocr.js` | Tesseract.js fallback. `runTesseractOcr(imagePath)` → raw text. `parseReceiptWithOcrFallback(imagePath)` → OCR text → Groq Text for structuring. |
| **Bank Message** | `bank-message.js` | Regex pre-extraction from bank SMS: amount, card last-4, date, time, debit/credit type. Builds structured AI prompt with hints. |
| **Duplicate** | `duplicate.js` | Dedup helpers: by file hash (receipts), by idempotency key (transactions), by amount + date per user (transactions). |
| **Email Config** | `config/email.js` | Nodemailer SMTP transporter (Gmail by default). Reads `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`. |
| **Email Util** | `utils/email.js` | `sendOtpEmail(toEmail, otp)` — sends a styled HTML email with the 6-digit password-reset OTP. Sender from `SMTP_FROM` or `SMTP_USER`. |

### 3.6 Background Worker (`src/worker.js`)

A polling worker forked as a child process by `index.js` (or run standalone via `npm run worker`):

1. **Poll** every 5s for `queued` receipts
2. **Claim** batches of 5 using `FOR UPDATE SKIP LOCKED` (concurrency-safe)
3. **Process** based on input type:
   - `image` / `virtual_receipt`: Groq Vision API → (fallback: Tesseract OCR → Groq Text)
   - `bank_message`: regex pre-processing → Groq Text API
4. **Validate** AI output via `ai-output.schema.js` (strips markdown fences, reasoning tags, extracts JSON)
5. **Create** auto-confirmed transaction linked to receipt. Source mapping: image → Cash, virtual_receipt → Online, bank_message → Card
6. **Dedup** by amount + date per user
7. **Retry** up to `maxAttempts` (3), then mark `failed`
8. **Stale lock recovery** every 60s — locks older than 10 min reset to `queued`
9. **Graceful shutdown** on SIGTERM/SIGINT

### 3.7 Validators (`src/validators/`)

| Schema File | Schemas |
|-------------|---------|
| `auth.schema.js` | register, login, refresh, forgotPassword (email), resetPassword (6-digit OTP + password min 8), changePassword (currentPassword + newPassword min 8) |
| `transaction.schema.js` | createTransaction, updateTransaction, listTransactionsQuery, createCategory, updateCategory |
| `budget.schema.js` | createBudget, updateBudget, listBudgetsQuery |
| `ai-output.schema.js` | AI response parsing + validation (strips markdown fences, reasoning tags, extracts JSON) |

### 3.8 Backend Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `express` | ^4.21.2 | Web framework |
| `pg` | ^8.13.3 | PostgreSQL driver |
| `drizzle-orm` | ^0.39.3 | Type-safe ORM |
| `bcryptjs` | ^2.4.3 | Password hashing (12 rounds) |
| `jsonwebtoken` | ^9.0.2 | JWT generation/verification |
| `zod` | ^3.24.2 | Schema validation |
| `multer` | ^1.4.5-lts.1 | File uploads |
| `groq-sdk` | ^0.15.0 | Groq AI (vision + text) |
| `tesseract.js` | ^5.1.1 | OCR fallback |
| `express-rate-limit` | ^7.5.0 | Rate limiting |
| `nodemailer` | ^10.0.10 | SMTP email for password reset OTP |
| `cors` | ^2.8.5 | Cross-origin resource sharing |
| `morgan` | ^1.10.0 | HTTP logging |
| `dotenv` | ^16.4.7 | Environment variables |
| `drizzle-kit` | ^0.30.4 (dev) | Migration generation |
| `vitest` | ^3.0.7 (dev) | Test runner |
| `supertest` | ^7.0.0 (dev) | HTTP assertion testing |

### 3.9 npm Scripts

| Script | Command | Purpose |
|--------|---------|---------|
| `start` | `node src/index.js` | Production server |
| `dev` | `node --watch src/index.js` | Dev with file watch |
| `worker` | `node src/worker.js` | Standalone worker |
| `worker:dev` | `node --watch src/worker.js` | Worker with watch |
| `db:generate` | `drizzle-kit generate` | Generate migrations |
| `db:migrate` | `drizzle-kit migrate` | Apply migrations |
| `db:push` | `drizzle-kit push` | Push schema directly |
| `db:studio` | `drizzle-kit studio` | Drizzle Studio GUI |
| `db:seed` | `node src/db/seed.js` | Seed default data |
| `setup` | `db:migrate && db:seed` | Migrate + seed |
| `test` | `vitest run` | Run tests |

---

## 4. Database

### 4.1 Schema — All Tables

#### `users`
| Column | Type | Constraints |
|--------|------|-------------|
| `id` | serial | PK |
| `email` | text | unique, not null |
| `passwordHash` | text | not null |
| `name` | text | not null |
| `currency` | char(3) | default 'PKR' |
| `timezone` | text | default 'Asia/Karachi' |
| `exchangeRates` | jsonb | nullable. Per-user rates: `{"USD": 280, "EUR": 300, ...}` meaning 1 unit of X = N base currency units. Null = no conversion. |
| `status` | text | default 'active' (active/inactive/deleted) |
| `createdAt` | timestamptz | default now() |
| `updatedAt` | timestamptz | default now() |

#### `refresh_tokens`
| Column | Type | Constraints |
|--------|------|-------------|
| `id` | serial | PK |
| `userId` | integer | FK → users (cascade), indexed |
| `tokenHash` | text | unique (SHA-256) |
| `expiresAt` | timestamptz | indexed |
| `revokedAt` | timestamptz | nullable |
| `ipAddress` | text | |
| `userAgent` | text | |
| `createdAt` | timestamptz | default now() |

#### `password_reset_tokens`
| Column | Type | Constraints |
|--------|------|-------------|
| `id` | serial | PK |
| `userId` | integer | FK → users (cascade), indexed |
| `tokenHash` | text | unique (SHA-256) |
| `expiresAt` | timestamptz | 1-hour expiry, indexed |
| `usedAt` | timestamptz | nullable |
| `ipAddress` | text | |
| `createdAt` | timestamptz | default now() |

#### `sources`
| Column | Type | Constraints |
|--------|------|-------------|
| `id` | serial | PK |
| `name` | text | unique |
| `createdAt` | timestamptz | default now() |

**Seed data:** Card (1), Cash (2), Online (3)

#### `categories`
| Column | Type | Constraints |
|--------|------|-------------|
| `id` | serial | PK |
| `userId` | integer | FK → users (cascade), NULL = global default, indexed |
| `name` | text | |
| `icon` | text | emoji or text |
| `color` | text | hex color |
| `transactionType` | text | expense / income / both |
| `createdAt` | timestamptz | default now() |
| `updatedAt` | timestamptz | default now() |

#### `receipts`
| Column | Type | Constraints |
|--------|------|-------------|
| `id` | serial | PK |
| `userId` | integer | FK → users (cascade), indexed |
| `transactionId` | integer | FK → transactions (set null), nullable |
| `inputType` | text | image / bank_message / sms / virtual_receipt |
| `filePath` | text | |
| `fileHash` | text | SHA-256, indexed with userId |
| `originalFileName` | text | |
| `mimeType` | text | |
| `fileSizeBytes` | bigint | |
| `rawText` | text | |
| `rawPayload` | jsonb | |
| `aiResponse` | jsonb | |
| `aiModel` | text | |
| `ocrProvider` | text | groq_vision / tesseract / none |
| `status` | text | queued / processing / success / needs_review / failed / duplicate, indexed |
| `errorMessage` | text | |
| `attempts` | integer | |
| `maxAttempts` | integer | default 3 |
| `lockedAt` | timestamptz | |
| `lockedBy` | text | |
| `createdAt` | timestamptz | default now() |
| `updatedAt` | timestamptz | default now() |
| `processedAt` | timestamptz | |

#### `transactions`
| Column | Type | Constraints |
|--------|------|-------------|
| `id` | serial | PK |
| `userId` | integer | FK → users (cascade) |
| `sourceId` | integer | FK → sources (restrict) |
| `categoryId` | integer | FK → categories (set null), nullable |
| `receiptId` | integer | FK → receipts (set null), nullable |
| `amount` | numeric(14,2) | |
| `currency` | char(3) | |
| `type` | text | expense / income |
| `status` | text | needs_review / confirmed / archived |
| `merchant` | text | nullable |
| `description` | text | nullable |
| `occurredAt` | timestamptz | |
| `transactionDate` | date | |
| `cardLast4` | char(4) | nullable |
| `bankReference` | text | nullable |
| `idempotencyKey` | text | nullable |
| `duplicateOfTransactionId` | integer | nullable |
| `createdAt` | timestamptz | default now() |
| `updatedAt` | timestamptz | default now() |

Seven composite indexes for user-scoped queries + idempotency.

#### `budgets`
| Column | Type | Constraints |
|--------|------|-------------|
| `id` | serial | PK |
| `userId` | integer | FK → users (cascade) |
| `categoryId` | integer | FK → categories (cascade), NULL = overall monthly |
| `amount` | numeric(14,2) | |
| `period` | text | monthly |
| `month` | char(7) | YYYY-MM |
| `createdAt` | timestamptz | default now() |
| `updatedAt` | timestamptz | default now() |

Unique index on `(userId, categoryId, month)`.

### 4.2 Relationships

```
users 1───∞ refresh_tokens
users 1───∞ password_reset_tokens
users 1───∞ transactions
users 1───∞ receipts
users 1───∞ categories (userId = NULL → global)
users 1───∞ budgets

sources 1───∞ transactions
categories 1───∞ transactions (set null on delete)
categories 1───∞ budgets (cascade on delete)
receipts 1───1 transactions (via transactionId, set null)
```

### 4.3 Migrations

| Migration | Description |
|-----------|-------------|
| `0000_numerous_stingray.sql` | Creates all base tables (users, refresh_tokens, sources, categories, receipts, transactions, budgets) with FKs and indexes |
| `0001_stormy_hardball.sql` | Adds unique index `idx_budgets_unique` on budgets(userId, categoryId, month) |
| `0002_old_quentin_quire.sql` | Adds `password_reset_tokens` table |
| `0003_hard_mimic.sql` | Adds `exchange_rates` jsonb column to `users` table |

### 4.4 Seed Data (`src/db/seed.js`)

Idempotent seed runs on boot (unless `AUTO_SEED=false`):
- **3 sources:** Card, Cash, Online
- **10 global categories:** (userId = NULL) with icons, colors, and transaction types

---

## 5. Authentication & Security

### 5.1 JWT Token Lifecycle

```
Register / Login
  → bcrypt hash password (12 rounds)
  → generate access token (JWT, 15 min TTL, JWT_ACCESS_SECRET, unique `jti` via crypto.randomUUID)
  → generate refresh token (JWT, 7d TTL, JWT_REFRESH_SECRET, unique `jti`)
  → store refresh token HASH (SHA-256) in refresh_tokens table
  → return { user, accessToken, refreshToken }

Authenticated Request
  → Client sends Authorization: Bearer <accessToken>
  → auth middleware verifies token, loads user, checks status === 'active'
  → if expired: returns 401 { code: 'TOKEN_EXPIRED' }
  → client ApiClient catches TOKEN_EXPIRED, calls /auth/refresh, retries

Token Refresh
  → POST /auth/refresh { refreshToken }
  → verify refresh token, look up hash in DB
  → if revoked or expired → 401 (triggers client forceLogout)
  → REUSE DETECTION: if token was already revoked → revoke ALL user tokens
  → revoke old refresh token, issue new pair
  → return { accessToken, refreshToken }

Logout
  → POST /auth/logout { refreshToken }
  → revoke refresh token (set revokedAt)
  → client clears secure storage
```

### 5.2 Password Reset Flow (Email OTP)

```
Forgot Password
  → POST /auth/forgot-password { email }
  → look up user by email (404 if not found)
  → generate 6-digit OTP via crypto.randomInt(100000, 1000000)
  → hash OTP (SHA-256), store in password_reset_tokens (1-hour expiry, IP tracked)
  → email OTP to user via Nodemailer (sendOtpEmail)
  → return success message

Reset Password
  → POST /auth/reset-password { token, password }
  → hash incoming OTP, match against unused, non-expired token
  → reject if new password equals current (SAME_PASSWORD)
  → bcrypt hash new password, update user
  → mark token used (usedAt)
  → revoke ALL refresh tokens for user
```

### 5.3 Change Password (Authenticated)

```
  → PUT /auth/me/password { currentPassword, newPassword }
  → verify currentPassword against stored hash
  → reject if newPassword equals current (SAME_PASSWORD)
  → bcrypt hash new password, update user
  → does NOT revoke existing sessions
```

### 5.4 Rate Limiting

| Limiter | Limit | Applied to |
|---------|-------|------------|
| `authLimiter` | 30 req / 15 min / IP | register, login, refresh, logout |
| `passwordResetLimiter` | 5 req / hour / IP | forgot-password, reset-password |

### 5.5 Data Isolation

All queries filter by `userId` from `req.user` — users cannot access another user's transactions, categories, budgets, or receipts.

### 5.6 Token Cleanup

A hourly interval (`setInterval`) deletes expired and revoked refresh tokens from the `refresh_tokens` table.

---

## 6. AI Receipt Pipeline

### 6.1 Image Receipt Flow

```
User uploads image (cash receipt or online screenshot)
  │
  ▼
POST /api/receipts/scan (multipart, field: receipt)
  → Multer saves to UPLOAD_DIR with random hex filename
  → SHA-256 file hash computed
  → Dedup check: (userId, fileHash) already exists?
     └─ yes → return existing receipt (status: duplicate)
  → Insert receipt row (status: queued, inputType: image/virtual_receipt)
  → return 202 { receipt }

Worker polls every 5s (FOR UPDATE SKIP LOCKED, batch of 5)
  │
  ▼
Claim receipt (status: queued → processing, set lockedAt)
  │
  ▼
Groq Vision API (image as base64)
  ├─ success → structured JSON (merchant, amount, date, category)
  └─ failure ──► Tesseract OCR (local)
                   ├─ success → raw text → Groq Text model → structured JSON
                   └─ failure → mark receipt "failed"

Structured JSON → Zod validation (ai-output.schema.js)
  ├─ valid → continue
  └─ invalid → mark "needs_review"

Duplicate check (amount + date per user)
  ├─ duplicate → mark "duplicate"
  └─ unique → create transaction (status: confirmed, linked to receipt)

Receipt status → success (or needs_review / failed / duplicate)
```

### 6.2 Bank SMS Flow

```
User pastes bank SMS text
  │
  ▼
POST /api/receipts/bank-message { message, transactionType? }
  → SHA-256 hash of message text
  → Dedup check: (userId, fileHash)
  → Insert receipt (status: queued, inputType: bank_message, rawText: message)
  → return 202

Worker claims receipt
  │
  ▼
Regex pre-processing (services/bank-message.js)
  → extract hints: amount, card last-4, date, time, debit/credit
  → build structured prompt with hints
  │
  ▼
Groq Text API (structured extraction prompt)
  → structured JSON (amount, merchant, date, type, cardLast4, bankReference)
  │
  ▼
Zod validation → dedup → create transaction (source: Card)
```

### 6.3 Source Mapping

| Input Type | Mapped Source |
|------------|---------------|
| `image` | Cash (2) |
| `virtual_receipt` | Online (3) |
| `bank_message` | Card (1) |

### 6.4 Receipt Statuses

| Status | Meaning |
|--------|---------|
| `queued` | Uploaded, waiting for worker |
| `processing` | Worker has claimed and is processing |
| `success` | Transaction auto-created and confirmed |
| `needs_review` | AI parsed but confidence low or validation partial — user reviews |
| `failed` | All attempts exhausted (max 3) |
| `duplicate` | Same receipt/SMS already processed |

### 6.5 Transaction Statuses

| Status | Meaning |
|--------|---------|
| `confirmed` | Auto-confirmed by AI or manually confirmed by user |
| `needs_review` | Awaiting user review |
| `archived` | Archived by user |

---

## 7. Configuration

### 7.1 Backend Environment Variables (`backend/.env`)

| Variable | Default | Description |
|----------|---------|-------------|
| `NODE_ENV` | `development` | Runtime environment |
| `PORT` | `5000` | Server port |
| `CORS_ORIGIN` | `*` | Comma-separated allowed origins |
| `DATABASE_URL` | — | PostgreSQL connection string (required) |
| `JWT_ACCESS_SECRET` | dev fallback | Access token signing secret (min 32 chars) |
| `JWT_REFRESH_SECRET` | dev fallback | Refresh token signing secret (min 32 chars) |
| `JWT_ACCESS_EXPIRES_IN` | `15m` | Access token expiry |
| `JWT_REFRESH_EXPIRES_IN` | `7d` | Refresh token expiry |
| `GROQ_API_KEY` | — | Groq API key (required for AI features) |
| `GROQ_VISION_MODEL` | `llama-3.2-11b-vision-preview` | Vision model for receipt images |
| `GROQ_TEXT_MODEL` | `llama-3.3-70b-versatile` | Text model for SMS / OCR structuring |
| `UPLOAD_DIR` | `./uploads` | Receipt image upload directory |
| `MAX_FILE_SIZE_MB` | `10` | Maximum upload file size |
| `ENABLE_GROQ_VISION` | `true` | Enable Groq vision for receipts |
| `ENABLE_TESSERACT_FALLBACK` | `true` | Enable Tesseract OCR fallback |
| `AUTO_MIGRATE` | `true` | Auto-run DB migrations on boot |
| `AUTO_SEED` | `true` | Auto-seed default data on boot |
| `ENABLE_WORKER` | `true` | Fork receipt-processing worker on boot |
| `SMTP_HOST` | `smtp.gmail.com` | SMTP server host for password reset emails |
| `SMTP_PORT` | `587` | SMTP server port |
| `SMTP_USER` | — | SMTP username (email account) |
| `SMTP_PASS` | — | SMTP password or app-specific password |
| `SMTP_FROM` | — | Sender email address (defaults to SMTP_USER) |

### 7.2 Frontend Constants (`lib/config/constants.dart`)

| Constant | Value |
|----------|-------|
| Android API URL | `http://192.168.9.172:5000/api` (LAN IP) |
| Web/Desktop API URL | `http://localhost:5000/api` |
| Currencies | PKR, USD, EUR, GBP, AED, INR, SAR, CAD, AUD |
| Sources | Card (1), Cash (2), Online (3) |
| Storage keys | `access_token`, `refresh_token`, `api_base_url`, `theme_mode` |
| Exchange rate API | `https://open.er-api.com/v6/latest/{baseCurrency}` (free, no key required) |

API URL is user-overridable in Settings and persisted in `flutter_secure_storage`.

---

## 8. API Response Format

### 8.1 Success Envelope

```json
{
  "success": true,
  "data": { ... }
}
```

### 8.2 Error Envelope

```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable message",
    "details": ["field-level errors"]
  }
}
```

### 8.3 Error Codes

| Code | HTTP Status | Meaning |
|------|-------------|---------|
| `VALIDATION_ERROR` | 400 | Zod validation failed |
| `INVALID_JSON` | 400 | Malformed JSON body |
| `FILE_TOO_LARGE` | 413 | Upload exceeds MAX_FILE_SIZE_MB |
| `UNAUTHORIZED` | 401 | Missing or invalid token |
| `TOKEN_EXPIRED` | 401 | Access token expired (triggers client refresh) |
| `INVALID_CREDENTIALS` | 401 | Wrong email/password |
| `FORBIDDEN` | 403 | Accessing another user's resource |
| `NOT_FOUND` | 404 | Resource doesn't exist |
| `CONFLICT` | 409 | Duplicate resource (e.g., category name exists) |
| `SAME_PASSWORD` | 400 | New password matches current password |
| `INVALID_TOKEN` | 400 | Password reset OTP is invalid, expired, or already used |
| `RATE_LIMITED` | 429 | Rate limit exceeded |
| `INTERNAL_ERROR` | 500 | Unexpected server error |

---

## 9. Testing

### 9.1 Backend Tests (Vitest + Supertest)

```bash
cd backend
npm test
```

| Test File | Coverage |
|-----------|----------|
| `auth.test.js` | Register, login, refresh, logout, profile, password reset, change password |
| `transactions.test.js` | CRUD, filtering, search, sorting, pagination, confirm |
| `dashboard.test.js` | Summary, expense-by-category, expense-by-source, expense-trend, budget-status |
| `worker.test.js` | Queue claiming, AI parsing, dedup, transaction creation |

### 9.2 Test Setup (`src/tests/setup.js`)

Helpers:
- `createTestUser()` — creates user directly in DB (bypasses rate limits)
- `getAuthTokens()` — generates auth tokens for a user
- `cleanup()` — deletes test users (cascade)
- `getFirstSourceId()` / `getFirstCategoryId()` — fetches seeded IDs

Configuration: 30s timeouts, globals enabled.
