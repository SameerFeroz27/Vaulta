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
10. [UI Port — Approved Prototype](#10-ui-port--approved-prototype)

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
| `/` | `MainScaffold` | 4-tab bottom nav: Dashboard, Transactions, Loans, Settings |

**MainScaffold:** `BottomNavigationBar` with `IndexedStack` (preserves state across tabs). The Loans screen adds the app's only nested tabs — a top `TabBar` with *Loans* / *By person*; because the screen stays mounted, the selected sub-tab persists across bottom-nav switches.

### 2.2 State Management — Providers (`lib/providers/`)

All providers extend `ChangeNotifier`.

| Provider | Responsibility |
|----------|---------------|
| `AuthProvider` | Auth status (`authenticated` / `unauthenticated` / `unknown`), current user, login, register, logout, profile update (including exchange rates), forgot password (email OTP), reset password, change password, `refreshExchangeRates()` (auto-fetches live rates on session restore and currency change). Registers reset callbacks to clear dependent caches on logout. |
| `TransactionProvider` | Transaction list, pagination (infinite scroll), filters (type, source, search, sort, order), CRUD operations. Notifies `DashboardProvider` and `BudgetProvider` on changes. |
| `DashboardProvider` | Dashboard summary (income, expense, balance, count, top merchants), expense-by-category, expense-by-source, expense trend, budget status. Month navigation. |
| `CategoryProvider` | Category list (global defaults + user custom), create, update, delete. |
| `BudgetProvider` | Budget list with computed spending, create, update, delete. Month navigation. |
| `LoanProvider` | Loan list, pagination (infinite scroll), filters (direction, status, search, sort, order), the per-person summary plus `overdueCount` / `overduePeople`, loan CRUD, record/delete repayment. Derives `totalTheyOwe` / `totalIOwe` / `netPosition` from the summary for the dashboard. Notifies `TransactionProvider` on changes, since loan money movements land in the ledger. |
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
| `LoanService` | list (with filters), summary (people + overdue count), get (loan + payments), create, update, delete, addPayment, deletePayment |
| `DashboardService` | summary, expense-by-category, expense-by-source, expense-trend, budget-status |
| `ReceiptService` | scan (image upload), bank-message, list, get (poll), reprocess |

### 2.4 Models (`lib/models/`)

| Model | Key Fields |
|-------|------------|
| `User` | `id`, `email`, `name`, `currency`, `timezone`, `exchangeRates` (`Map<String, double>?` — rates relative to base currency, e.g. `{'USD': 280}` means 1 USD = 280 base units) |
| `Transaction` | `id`, `amount`, `currency`, `type` (expense/income), `typeConfidence` (AI's confidence in the direction; `null` when user-chosen), `typeSource` (`ai_auto`/`user_override`/`manual`), `status`, `merchant`, `description`, `occurredAt`, `transactionDate`, `source`, `category`, `receiptId`, `cardLast4`, `bankReference` |
| `TransactionFilters` | `type`, `sourceId`, `search`, `sortBy`, `order` |
| `Pagination` | `page`, `limit`, `total`, `totalPages` |
| `Category` | `id`, `name`, `icon`, `color`, `transactionType`, `isGlobal` |
| `Budget` | `id`, `amount`, `month`, `categoryId`, `category`, `spent`, `remaining`, `percentage`, `overBudget` |
| `BudgetStatus` | Overall + per-category budget status with spending |
| `Loan` | `id`, `counterparty`, `direction` (lent/borrowed), `principal`, `issueDate`, `dueDate`, `notes`, `paid`, `outstanding` (floors at 0), `surplus`, `state` (open/settled), `overdue`, `transactionId`. Derived fields are recomputed locally if the API omits them. |
| `LoanPayment` | `id`, `amount`, `paymentDate`, `transactionId`, `note` |
| `LoanSummaryPerson` | `person`, `theyOwe`, `iOwe`, `repaid`, `loanCount`, `net`, `state` |
| `LoanFilters` | `direction`, `state`, `search`, `sort`, `order` |
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
| `DashboardScreen` | Month selector (prev/next). Summary cards: Income, Expense, Balance (color-coded), transaction count. A **Loans section** below the tiles (owed to me / I owe, plus who is overdue when anything is late) that taps through to the Loans tab; it is shown even when there are no transactions yet. Expense-by-Category pie chart. Expense-by-Source pie chart. Expense Trend bar chart. Top Merchants list. Pull-to-refresh. Empty-state with "Add Transaction" CTA. |

#### Transactions (`screens/transactions/`)

| Screen | Description |
|--------|-------------|
| `TransactionListScreen` | Paginated list with infinite scroll, pull-to-refresh, empty state. A review banner ("N transactions need review") appears above the list when any are pending and jumps straight to the review queue, since those rows are excluded from dashboard totals and would otherwise be invisible. App bar: scan-receipt icon, filter icon. FAB to add. |
| `TransactionFormScreen` | Add/edit. Type toggle (expense/income), amount (currency-prefixed), **per-transaction currency dropdown** (all 9 currencies), live conversion hint ("≈ ₨{converted} {baseCurrency}") when currency differs from base, source dropdown (Card/Cash/Online), category dropdown (filtered by type), date picker, merchant, description. |
| `TransactionDetailScreen` | Amount with sign, status chip (Confirmed / Needs Review / Archived). Rows: type, decided-by (when AI-classified), category (icon+name), source, date, merchant, description, card last4, bank reference. For `needs_review` rows a review card offers one-tap **Confirm** or **Change to Income/Expense**. Edit & delete actions. |
| `TransactionFilterSheet` (widget) | Bottom sheet: type (all/expense/income), status (all/needs review/confirmed/archived), source, text search, sort (date/amount), order (asc/desc), "Clear All". Filters are built explicitly on Apply rather than via `copyWith`, which treats null as "keep the old value" and so could never clear a filter back to All. |

#### Receipts (`screens/receipts/`)

| Screen | Description |
|--------|-------------|
| `ReceiptScanScreen` | Three modes via segmented button: Cash Receipt (camera/gallery), Online Receipt (screenshot upload), Bank Message (paste SMS). A three-way **Auto / Expense / Income** toggle for image modes, defaulting to Auto so the AI decides the direction; an explicit choice overrides it. Dismissible instructions card. Polls receipt status every 2s until terminal state. Shows the parsed transaction plus the AI's confidence and the evidence it used. When the direction was held back, the result screen resolves it in place with one-tap **Confirm** / **Change to Income-Expense** rather than sending the user to another tab. "Try Again" reprocess on failure. |
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

#### Loans (`screens/loans/`)

| Screen | Description |
|--------|-------------|
| `LoanListScreen` | The Loans screen: a shell holding a top `TabBar` with **Loans** and **By person**. Owns the app bar, the FAB, the overdue banner (shown above both tabs — an overdue loan matters on either), and the filter sheet, whose icon appears only on the Loans tab since filtering narrows the list. Loads the provider on mount rather than from whichever tab builds first. |
| `LoanDetailScreen` | Outstanding amount as the hero, direction label, progress bar (`paid` of `principal`), issued/due dates with an overdue badge, notes, and a surplus line when money was paid beyond the amount ("counted as a gift, tip or refund"). Actions: **Record payment**, edit, remove. Repayment timeline below, each row deletable. |
| `LoanFormScreen` | Add/edit. Direction toggle (**I lent** / **I borrowed**) with an explanatory caption, person, amount, issue date, optional due date (with a clear button), notes, and — on create only — an "Also record this in my transactions" toggle. The person field carries a hint recommending a capitalised name with a space, e.g. "Sana Malik". |
| `RecordPaymentSheet` (widget) | Amount (pre-filled with the outstanding balance), payment date, note, and the record-in-transactions toggle. Generates an idempotency key once per sheet so a double tap cannot create two repayments. Warns live when the amount exceeds what is owed, and reports the resulting surplus after saving. |
| `LoanListView` (widget) | The **Loans** tab: segmented **All / Owed to me / I owe** direction filter, the active loan list with infinite scroll and pull-to-refresh. Empty state distinguishes "No loans yet" from "No loans match these filters" and only the filtered case offers "Clear filters". Navigation is left to the shell, so it takes `onAddLoan` / `onOpenLoan` callbacks. |
| `LoanPersonSummaryView` (widget) | The **By person** tab: `LoanSummaryTable` with pull-to-refresh and its own empty state ("No one to show yet"). Always shows everyone — the direction filter is a list concern. |

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
| `LoansCard` | `dashboard/` | Lending section directly under the tiles: "Owed to me" and "I owe", plus an **"Overdue: Ali, +1 more"** line shown only when something is actually late (never an empty bar). Converts PKR totals to the base currency when a rate exists; otherwise the ₨ symbol marks them as PKR. Taps through to the Loans tab. |
| `LoanCard` | `loans/` | Loan list item: counterparty, amount outstanding — or, for an overpaid loan, the surplus as the headline figure so nothing reads as unfinished — progress bar, due date, overdue/settled badge |
| `LoanListView` | `loans/` | Loans tab content: direction filter, list, empty states |
| `LoanPersonSummaryView` | `loans/` | By person tab content: the summary table, refresh, empty state |
| `LoanSummaryTable` | `loans/` | One stacked block per person — name and status, then *Owed to me* / *I owe* / *Net* as right-aligned label-value lines — plus a totals block when there is more than one person. Stacked rather than a column grid because four money columns at phone width forced larger amounts to scale down or truncate. Counts active loans only, so it agrees with the loan list — a person whose loans were all removed reads "No active loans". |
| `LoanFilterSheet` | `loans/` | Loan filters: person search, status, sort, order |
| `RecordPaymentSheet` | `loans/` | Record-repayment bottom sheet with idempotency key and surplus warning |
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

#### Loans (`/api/loans`)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/loans` | ✓ | Active loans with `paid`, `outstanding`, `state`, `overdue`. Query: `direction`, `state` (open/settled), `search`, `sort`, `order`, `page`, `limit`. Hidden loans excluded. |
| GET | `/loans/summary` | ✓ | Per-person table: `theyOwe`, `iOwe`, `repaid`, `net`, `state`, `loanCount`, plus `overdueCount` and `overduePeople` (one entry per person, for the dashboard). The owed figures count **active loans only**, so they agree with the list; `repaid` spans removed loans too, so deleting a loan never erases a repayment. |
| POST | `/loans` | ✓ | Create: `{ counterparty, direction, principal, issueDate, dueDate?, notes?, recordTransaction? }` |
| GET | `/loans/:id` | ✓ | Loan + repayment timeline. Active only. |
| PUT | `/loans/:id` | ✓ | Edit. A principal change keeps the linked disbursement transaction in step. |
| DELETE | `/loans/:id` | ✓ | Remove: deletes **only this loan's** transactions, keeps repayments, sets `deletedAt`. |
| POST | `/loans/:id/payments` | ✓ | Record repayment. Overpayment is accepted and returns `surplus` rather than a 400. Idempotency key → 409. |
| DELETE | `/loans/:id/payments/:paymentId` | ✓ | Remove a repayment and its transaction; the loan reopens if it drops below the principal. |

#### Receipts (`/api/receipts`)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/receipts/scan` | ✓ | Upload receipt image (multipart, field `receipt`). Body: `inputType` (image/virtual_receipt), optional `transactionType` (expense/income — omit to let the AI decide). SHA-256 dedup. Returns 202 with receipt ID. |
| POST | `/receipts/bank-message` | ✓ | Submit bank SMS: `{ message }`. Max 5000 chars. SHA-256 dedup. Returns 202. |
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
| `kind` | text | null for ordinary rows; loan_disbursement / loan_repayment |
| `loanId` | integer | FK → loans (set null), nullable — links loan money movement |
| `amount` | numeric(14,2) | |
| `currency` | char(3) | |
| `type` | text | expense / income |
| `typeConfidence` | numeric(3,2) | AI's confidence in `type`; `null` when the user chose the direction |
| `typeSource` | text | ai_auto / user_override / manual, nullable |
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

Seven composite indexes for user-scoped queries + idempotency, plus `(userId, loanId)`.

#### `loans`
| Column | Type | Constraints |
|--------|------|-------------|
| `id` | serial | PK |
| `userId` | integer | FK → users (cascade) |
| `counterparty` | text | the friend/relative's name (free text) |
| `direction` | text | lent (they owe me) / borrowed (I owe them) |
| `principal` | numeric(14,2) | |
| `issueDate` | date | |
| `dueDate` | date | nullable |
| `notes` | text | nullable |
| `deletedAt` | timestamptz | nullable — set when removed, hides it from the active list |
| `createdAt` | timestamptz | default now() |
| `updatedAt` | timestamptz | default now() |

No `status` and no `currency` column. State (open/settled) and balance are derived from
repayments, and loans are PKR-only.

#### `loan_payments`
| Column | Type | Constraints |
|--------|------|-------------|
| `id` | serial | PK |
| `loanId` | integer | FK → loans (cascade) |
| `userId` | integer | FK → users (cascade) |
| `amount` | numeric(14,2) | |
| `paymentDate` | date | |
| `transactionId` | integer | FK → transactions (set null), nullable |
| `idempotencyKey` | text | nullable |
| `note` | text | nullable |
| `createdAt` | timestamptz | default now() |

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
  └─ invalid → mark "needs_review" (no transaction is created)

Duplicate check (amount + date per user)
  ├─ duplicate → mark "duplicate"
  └─ unique → resolve direction (services/direction.js)
                ├─ explicit user override, or AI confidence ≥ threshold
                │    → create transaction (status: confirmed)
                └─ otherwise (low confidence, missing type, or hints contradicting
                   the AI) → create transaction (status: needs_review)

Receipt status → success (or needs_review / failed / duplicate)
```

### 6.2 Bank SMS Flow

```
User pastes bank SMS text
  │
  ▼
POST /api/receipts/bank-message { message }
  → SHA-256 hash of message text
  → Dedup check: (userId, fileHash)
  → Insert receipt (status: queued, inputType: bank_message, rawText: message)
  → return 202

Worker claims receipt
  │
  ▼
Regex pre-processing (services/bank-message.js)
  → extract hints: amount, card last-4, date, time, debit/credit
  → build structured prompt from the non-directional hints only; the guessed
    debit/credit is deliberately withheld so it can serve as an independent
    cross-check of the AI's answer
  │
  ▼
Groq Text API (structured extraction prompt)
  → structured JSON (amount, merchant, date, type, typeConfidence,
    directionEvidence, cardLast4, bankReference)
  │
  ▼
Zod validation → dedup → resolve direction
  → AI answer cross-checked against the keyword hint; a disagreement forces
    needs_review even at high AI confidence
  → create transaction (source: Card)
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
| `success` | Transaction created and filed as confirmed |
| `needs_review` | Two cases: the AI output failed validation (no transaction created — reprocess), or the parse succeeded but the direction is uncertain (a transaction exists, awaiting confirmation) |
| `failed` | All attempts exhausted (max 3) |
| `duplicate` | Same receipt/SMS already processed |

### 6.5 Transaction Statuses

| Status | Meaning |
|--------|---------|
| `confirmed` | Filed automatically by the AI at or above the confidence threshold, confirmed by the user, or entered manually |
| `needs_review` | Direction uncertain — kept with the AI's best guess but excluded from dashboard totals until the user confirms or flips it |
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

---

## 10. UI Port — Approved Prototype

The reference design is [`docs/prototype/m3-nav-prototype.html`](prototype/m3-nav-prototype.html) — a
self-contained clickable prototype (open it directly in a browser; no server or build step).
It is the source of truth for the changes below, and this section tracks their port into the
Flutter app. It also covers the **sign-in screen**, which is pre-auth and so replaces the tab
shell rather than becoming a fifth destination; three layouts (Plain / Hero / Card) were
offered there for review, and the **Plain** layout is the one adopted.

Motion timings come from the *Vaulta Tab & Tile Transitions Guide*; the table in 10.2 mirrors
them so this section stands alone.

### 10.1 Decisions

The prototype has toggle groups, but those exist so a reviewer could compare options. The app
adopts the reviewed state, not every variant:

| Prototype control | Adopted |
| --- | --- |
| Bottom nav | **Flat bar with a 3 px top indicator line** that glides between destinations |
| Overall look | **M3 reskin** — surface tiers, 20 px buttons, 28 px drag-handle sheets. The "current" look was a comparison only and is not adopted |
| Loans sub-tabs | **Secondary** — filled pills, not an underline. "Primary" was a comparison |
| Phone theme | Both light and dark |
| Motion | **Full** — every timing in 10.2, played unconditionally |
| Sign-in layout | **Plain** — no app bar, brand block above the form |

### 10.2 Motion spec

Every duration is a named constant in one place so tuning is a single edit.

| Element | Duration | Easing |
| --- | --- | --- |
| Tile → detail container | 320 ms | `cubic-bezier(0.2, 0, 0, 1)` |
| Detail content fade | 150 ms, 110 ms delay (rows/actions 170 ms) | standard |
| Back / collapse | 300 ms | emphasized |
| Tab slide (shared axis X) | 300 ms | emphasized |
| Nav indicator glide | 280 ms | same as the slide |
| Sheet in / out | 300 ms / 220 ms | emphasized |
| Scrim fade | 220 ms | standard |
| List stagger | 40 ms per item, max 6 | ease-out |

Rules:

- A tapped tile grows from its own rectangle and keeps its corner radius and colour through
  the first half of the grow, so the tap origin stays legible.
- Detail content does not animate on the same beat as its container: the header arrives at
  110 ms, the rows and actions at 170 ms.
- A tab switch slides the incoming screen from the side the tab order came from — later tab
  from the right, earlier from the left.
- An open detail is closed **before** a tab change; animating both reads as one muddled
  double movement.
- Quick decisions (such as *mark as reviewed*) stay bottom sheets, never full screens.
- Motion is played in full. Flutter shortens every default-behaviour `AnimationController`
  to 5% of its duration while `AccessibilityFeatures.disableAnimations` is set — one frame,
  which is what reads as an instant cut — so every controller the app owns is created with
  `AnimationBehavior.preserve` (`lib/widgets/motion/full_motion_route.dart`,
  `lib/widgets/navigation/app_bottom_nav.dart`, `tab_slide.dart`, `stagger.dart`, the auth
  shake and `showAppSheet`).

### 10.3 Changes to port — rationale

The list below is the reasoning behind each change and, through its checkboxes, the record of
what is done — kept here so the spec and the design reference stay together.

**Bottom navigation** (`lib/main.dart`, `lib/config/theme.dart`)

- [x] Tab 2's label becomes **Activity**; the screen keeps its own *Transactions* title.
- [x] Flat bar: plain surface, no tonal pill, 3 px primary line across the top edge of the
      selected destination. `NavigationBar` cannot glide an indicator, so this is a custom
      widget — `lib/widgets/navigation/app_bottom_nav.dart`.
- [x] The indicator glides between destinations in 280 ms instead of appearing per item.
- [x] Labels stay unclipped at narrow widths: the nav label style is pinned to 12 px, where
      the default 14 clipped the longer destinations.
- [x] Badges kept: pending-review on Activity, overdue on Loans.

**Motion** (`lib/main.dart`, new shared widgets, `pubspec.yaml`)

- [x] The tile → detail transform is the app's own `ContainerTransformRoute`
      (`lib/widgets/motion/full_motion_route.dart`) rather than the `animations` package's
      `OpenContainer`: its route can opt out of the reduce-motion scaling, and it does not
      allocate two `GlobalKey`s per tile. An enter-only slide drives tabs (an `IndexedStack`
      is kept for per-tab scroll state).
- [x] Tab slide, list stagger, tile → detail, sheet slide, per 10.2.

**Tiles that open a detail**

The prototype opens all 18 tiles, and each detail **mirrors the rows out of the tile that was
tapped**, so a detail can never disagree with the card it came from. The mechanism is ported
through a shared `OpenTile` / `OpenContainer` rather than a hand-authored screen per tile
(`lib/widgets/motion/open_tile.dart`, `lib/widgets/dashboard/tile_detail.dart`).

- [x] Income / Expense / Balance tiles → a breakdown of the figure.
- [x] Dashboard Loans card → its owed/owe rows plus a **See all loans** action that lands on
      the Loans tab.
- [x] Expenses by Category and Top Merchants → their own rows.
- [x] Each **By person** row → that person's owed / owe / net.
- [x] Loan cards and transaction rows → the same transform
      (`loan_detail_screen.dart`, `transaction_detail_screen.dart`). A transparent tile must
      morph with the nearest ancestor that paints a colour, or the grow starts invisible.

**Loans**

- [x] Remaining amount as the headline, labelled `left`, with the original total below
      (`of Rs 30,000`). — `widgets/loans/loan_card.dart`, `screens/loans/loan_detail_screen.dart`
- [x] By person already shows what is owed *now* and reconciles: `GET /api/loans/summary`
      computes `GREATEST(principal - paid, 0)`, counting active loans only, so it agrees with
      the list and with the dashboard card.
- [x] Consolidate the loan filters into one control. The prototype has a single `Filters` chip
      (Person / Direction / Status / Sort); the app now has one chip opening the sheet, with
      the old `SegmentedButton` and app-bar filter icon gone. — `widgets/loans/loan_list_view.dart`,
      `screens/loans/loan_list_screen.dart`, `widgets/loans/loan_filter_sheet.dart`
- [x] Record payment also sits on the loan card row (`LoanCard.onRecordPayment`), so a
      repayment no longer requires opening the detail first.

**Transactions**

- [x] Day headings: `Today` / `Yesterday` only when true, otherwise the weekday and date,
      compared as calendar days rather than elapsed hours. Grouped only when the list is
      date-sorted, since an amount sort interleaves the days. — `Formatters.dayLabel()`,
      `transaction_list_screen.dart`
- [x] Inline search at the top of the list, debounced into `TransactionFilters.search` via a
      new `TransactionProvider.setSearch()`, which is built explicitly because `copyWith`
      treats null as "keep the old value" and so could never clear the term.
- [x] The review banner's **Show** opens a bottom sheet carrying *Mark as reviewed*.
      — `widgets/transactions/review_sheet.dart`

**Dashboard**

- [x] Hairline card edge in both themes, so cards stop reading as washed out. — `cardTheme`
- [x] Theme roles instead of hardcoded greys, and the semantic colours are brightness-aware
      now (`AppTheme.incomeFor` / `expenseFor` / `warnFor`): light takes the deeper shade,
      where the bright tints measured 3.03:1 and 2.83:1 against card surfaces.
- [x] Currency correctness — see 10.4.

**Settings**

- [x] Log out is a danger-red row behind its own divider, with bottom padding that clears the
      nav bar. Today it was a red button ending flush against it.

**Theme**

- [x] Scrollbar follows the app theme, and `scrollBehavior` now enables scrollbars at all —
      Flutter only draws them by default on desktop, so the themed thumb would otherwise
      never appear on a phone.
- [x] Audit for colours that follow the **OS** brightness rather than the app's theme mode. No
      call site reads `MediaQuery.platformBrightnessOf`; every colour comes from
      `Theme.of(context)` or the brightness-aware `AppTheme` helpers.

**Sign-in** (`lib/screens/auth/`)

- [x] **Plain** layout on one shared `AuthLayout`: a brand block above the form, no app bar.
- [x] Failures reported inline — a per-field message plus a banner — rather than a snackbar
      over the form; the submit button keeps its own spinner and is marked busy for a reader.
- [x] **Keep me signed in**: ticked by default, so the session survives a restart. Unticked
      keeps the tokens in memory only — including across a token refresh, which must not
      quietly persist a session the user chose to keep for this run only.
- [x] Fits a standard phone height with no scrollbar and no empty tail: the brand opens the
      screen, the form sits in the middle and the privacy line closes it
      (`MainAxisAlignment.spaceBetween` over the full viewport). Every control keeps a 44 px
      touch target, and the privacy line takes a near-body colour so it reads as the trust
      message it is.

### 10.4 Currency correctness (the only money-affecting change)

`GET /api/dashboard/*` multiplies each amount by `COALESCE(u.exchange_rates->>currency, 1)`
(`src/routes/dashboard.js`), so all seven aggregates are already expressed in the user's base
currency. Two gaps remain:

- [x] When the base currency is not PKR and the rate map is empty, **do not** render a
      converted-looking total. The `COALESCE(..., 1)` fallback silently treats PKR amounts as
      base currency, so changing currency with the rates not yet fetched labels PKR figures
      with the new symbol. The dashboard waits for a non-empty map instead
      (`ratesReadyFor`, `lib/utils/currency.dart`).
- [x] Reload the dashboard as part of the currency change rather than waiting for a tab tap
      (`auth.updateProfile(currency: …)` → `dashboardProvider.loadDashboard()`), or the tiles
      show the old totals under the new symbol for one round-trip.
      — `screens/settings/settings_screen.dart`, `providers/dashboard_provider.dart`

### 10.5 Verification — detail

These are the checks that matter and why.

- [x] `flutter analyze` clean, full `flutter test` suite green.
- [x] `Formatters.dayLabel()` covered by `test/formatters_day_label_test.dart`: today,
      yesterday, a late-evening yesterday that must still read as a calendar day, an older
      date, and a future date that must never be claimed as today.
- [x] The currency decision covered by a unit test (an empty rate map must not render a
      total) — `test/currency_decision_test.dart`. The flat bar is covered by
      `test/app_bottom_nav_test.dart`: the indicator lands on the selected slot and every
      label fits at 360 dp.
- [x] Full motion covered by `test/full_motion_test.dart`: with
      `debugSemanticsDisableAnimations` on, a preserved controller keeps its duration while a
      plain one finishes at once, a `FullMotionPageRoute` is still travelling when a
      `MaterialPageRoute` has settled, and the container transform opens and collapses.
- [x] The sign-in layout covered by `test/login_layout_test.dart`: it fits 360 × 640 with
      nothing to scroll, and the checkbox, links and button all keep a 44 px target.
- [ ] Timings within ~40 ms of 10.2, measured on a **mid-range Android device** — an emulator
      hides the jank.
- [x] Prototype guards: extract the inline script and `node --check` it, and confirm the
      stylesheet's braces balance. A stray brace or a bad `else` in one file silently kills
      every listener on the page — that happened once already.

### 10.6 Not part of this port

Tracked separately, since the prototype does not cover them:

- `android:enableOnBackInvokedCallback="true"` is absent from `AndroidManifest.xml`.
- `dart run flutter_launcher_icons` has never been run (config and `assets/icon.png` exist).
- Edge-to-edge system bars and a native splash screen.
- `widgets/transactions/transaction_filter_sheet.dart` constructs a `TextEditingController`
  inside `build()` and never disposes it.
- The dashboard load issues a second `countByStatus` request that could be folded into the list
  response.
