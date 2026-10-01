# Vaulta

**AI-powered personal finance tracker for cash-heavy, SMS-banking markets.**

Vaulta turns unstructured input — receipt photos, bank SMS, online receipt screenshots — into clean, categorized transactions automatically. Snap a receipt, forward a bank SMS, or add an entry manually; the AI pipeline parses it into your ledger.

---

## Key Features

- 🧾 **AI receipt scanning** — cash receipts, online receipt screenshots, and bank SMS parsed via Groq Vision with a Tesseract OCR fallback
- 📊 **Dashboard analytics** — income/expense/balance summary, category & source pie charts, expense trend bar chart, top merchants
- 🔄 **Transaction management** — full CRUD, filtering, search, sorting, pagination
- 🏷️ **Custom categories** — emoji + color, alongside seeded defaults
- 💰 **Monthly budgets** — overall and per-category, with progress tracking
- 🤝 **Loan tracking** — money lent to and borrowed from friends and relatives, with a per-person owed/repaid summary, repayment history, and dashboard totals
- 🔐 **JWT authentication** — silent token refresh, email-based password reset (OTP), change password
- 🌍 **Multi-currency** — 9 currencies with per-transaction selection, live exchange rates auto-fetched from open.er-api.com, dashboard totals converted to base currency
- 🎨 **Light / Dark / System theme**
- 📜 **Scan history** — with per-scan status tracking

---

## Tech Stack

**Frontend**
- Flutter
- Provider
- GoRouter
- fl_chart
- flutter_secure_storage
- image_picker
- intl
- http

**Backend**
- Node.js
- Express
- PostgreSQL
- Drizzle ORM
- JWT + bcrypt
- Zod
- Multer
- Groq SDK
- Tesseract.js
- express-rate-limit
- nodemailer
- Vitest + Supertest

---

## Project Structure

```
vaulta/
├── lib/                          # Flutter app source
│   ├── config/                   # API base URL & app-wide constants
│   ├── models/                   # Data models (Transaction, Category, Budget, etc.)
│   ├── providers/                # Provider state management
│   ├── screens/                  # Dashboard, Transactions, Budgets, Settings
│   ├── services/                 # API clients, auth, storage
│   └── widgets/                  # Reusable UI components
├── backend/                      # Express API
│   ├── src/routes/               # Auth, Transactions, Categories, Budgets, Dashboard, Receipts
│   ├── src/db/                   # Drizzle schema & migrations
│   ├── src/services/             # Groq/Tesseract pipeline, business logic
│   ├── src/middleware/           # Auth, validation, rate limiting
│   └── src/worker.js             # Async receipt-processing worker
├── docs/                         # Project documentation
└── pubspec.yaml
```

---

## Prerequisites

- Flutter SDK (Dart ^3.13.2)
- Node.js 18+
- PostgreSQL 14+
- A [Groq](https://console.groq.com) API key
- SMTP credentials (Gmail or similar) for password reset emails

---

## Getting Started

**Backend**
```bash
git clone https://github.com/SameerFeroz27/Vaulta.git
cd Vaulta/backend
cp .env.example .env
# fill in DATABASE_URL, GROQ_API_KEY, JWT secrets, and SMTP credentials

npm install
npm run setup   # migrations + seed
npm run dev      # worker auto-forks; run standalone with `npm run worker`
```

The API runs on `http://localhost:5000/api`. Health check: `GET /api/health`.

**Frontend**
```bash
# from project root
flutter pub get

# set API base URL in Settings, or edit lib/config/constants.dart
# (defaults to a LAN IP for Android — use 10.0.2.2 for the emulator)

flutter run
```

---

## Configuration

Full reference in `backend/.env.example`.

| Variable | Description | Default |
|---|---|---|
| `PORT` | Port the API server listens on | `5000` |
| `CORS_ORIGIN` | Comma-separated allowed origins | `*` |
| `DATABASE_URL` | PostgreSQL connection string | — |
| `JWT_ACCESS_SECRET` | Secret for signing access tokens (min 32 chars) | dev fallback |
| `JWT_REFRESH_SECRET` | Secret for signing refresh tokens (min 32 chars) | dev fallback |
| `JWT_ACCESS_EXPIRES_IN` | Access token expiry | `15m` |
| `JWT_REFRESH_EXPIRES_IN` | Refresh token expiry | `7d` |
| `GROQ_API_KEY` | API key for Groq Vision/Text | — |
| `GROQ_VISION_MODEL` | Groq model for image parsing | `qwen/qwen3.8-27b` |
| `GROQ_TEXT_MODEL` | Groq model for text/SMS parsing | `openai/gpt-oss-120b` |
| `AI_TYPE_CONFIDENCE_THRESHOLD` | Min AI confidence in income/expense before auto-filing; below it, held for review | `0.7` |
| `UPLOAD_DIR` | Receipt image upload directory | `./uploads` |
| `MAX_FILE_SIZE_MB` | Max receipt upload size | `10` |
| `ENABLE_GROQ_VISION` | Enable Groq vision for receipts | `true` |
| `ENABLE_TESSERACT_FALLBACK` | Enable Tesseract OCR fallback | `true` |
| `AUTO_MIGRATE` | Run migrations automatically on startup | `true` |
| `AUTO_SEED` | Seed default categories/sources on startup | `true` |
| `ENABLE_WORKER` | Fork the receipt-processing worker on boot | `true` |
| `SMTP_HOST` | SMTP server host for password reset emails | `smtp.gmail.com` |
| `SMTP_PORT` | SMTP server port | `587` |
| `SMTP_USER` | SMTP username (email account) | — |
| `SMTP_PASS` | SMTP password or app-specific password | — |
| `SMTP_FROM` | Sender email address (defaults to SMTP_USER) | — |

### Groq model availability

Model access varies by account and models get retired, so a configured model can stop
working without any code change. A receipt or SMS then fails with
`404 model_not_found` after exhausting its retries. Check what your key can actually
reach before editing the model vars:

```bash
curl https://api.groq.com/openai/v1/models -H "Authorization: Bearer $GROQ_API_KEY"
```

Use the returned IDs verbatim (including any `vendor/` prefix).

---

## API Overview

Response envelope: `{ success: true, data }` on success, `{ success: false, error: { code, message, details } }` on failure. All routes prefixed `/api`.

| Group | Method | Path | Description |
|---|---|---|---|
| Auth | POST | `/auth/register` | Create a new account; returns tokens |
| Auth | POST | `/auth/login` | Log in; returns access + refresh tokens |
| Auth | POST | `/auth/refresh` | Rotate refresh token (detects reuse) |
| Auth | POST | `/auth/logout` | Revoke refresh token |
| Auth | GET | `/auth/me` | Get current user profile |
| Auth | PUT | `/auth/me` | Update profile (name, currency, timezone) |
| Auth | PUT | `/auth/me/password` | Change password |
| Auth | POST | `/auth/forgot-password` | Send a 6-digit reset code to email |
| Auth | POST | `/auth/reset-password` | Reset password with the 6-digit code |
| Transactions | GET | `/transactions` | List (filter, search, sort, paginate) |
| Transactions | POST | `/transactions` | Create a transaction |
| Transactions | GET | `/transactions/:id` | Get a single transaction |
| Transactions | PUT | `/transactions/:id` | Update a transaction |
| Transactions | DELETE | `/transactions/:id` | Delete a transaction |
| Transactions | POST | `/transactions/:id/confirm` | Confirm a `needs_review` transaction |
| Categories | GET | `/categories` | List categories (seeded + custom) |
| Categories | POST | `/categories` | Create a custom category |
| Categories | PUT | `/categories/:id` | Update own category |
| Categories | DELETE | `/categories/:id` | Delete own category |
| Budgets | GET | `/budgets` | List budgets with computed spending |
| Budgets | POST | `/budgets` | Create a monthly budget |
| Budgets | PUT | `/budgets/:id` | Update a budget |
| Budgets | DELETE | `/budgets/:id` | Delete a budget |
| Loans | GET | `/loans` | List active loans with paid/outstanding/state/overdue |
| Loans | GET | `/loans/summary` | Per-person summary: they owe / I owe / repaid, plus who is overdue |
| Loans | POST | `/loans` | Create a loan (optionally records the money movement) |
| Loans | GET | `/loans/:id` | Loan detail with its repayment timeline |
| Loans | PUT | `/loans/:id` | Edit a loan; keeps a linked transaction in step |
| Loans | DELETE | `/loans/:id` | Remove a loan (hidden, own transactions deleted) |
| Loans | POST | `/loans/:id/payments` | Record a repayment; overpayment settles with a surplus |
| Loans | DELETE | `/loans/:id/payments/:paymentId` | Remove a repayment and its transaction |
| Dashboard | GET | `/dashboard/summary` | Income/expense/balance summary + top merchants |
| Dashboard | GET | `/dashboard/expense-by-category` | Expense breakdown by category |
| Dashboard | GET | `/dashboard/expense-by-source` | Expense breakdown by payment source |
| Dashboard | GET | `/dashboard/expense-trend` | Multi-month expense & income trend |
| Dashboard | GET | `/dashboard/budget-status` | Budget vs. actual per category |
| Receipts | POST | `/receipts/scan` | Upload a receipt image for AI parsing |
| Receipts | POST | `/receipts/bank-message` | Submit bank SMS text for AI parsing |
| Receipts | GET | `/receipts` | List user's receipts (paginated) |
| Receipts | GET | `/receipts/:id` | Poll scan status + linked transaction |
| Receipts | POST | `/receipts/:id/reprocess` | Requeue a failed/needs_review receipt |
| Health | GET | `/health` | Service health check |

---

## AI Receipt Pipeline

**Receipt/screenshot flow:**
1. User uploads an image (cash receipt or online receipt screenshot)
2. Worker polls the queue using `FOR UPDATE SKIP LOCKED` to safely claim jobs
3. Image sent to **Groq Vision**; on failure, falls back to **Tesseract OCR → Groq Text**
4. Extracted fields validated with **Zod**
5. Dedup check against existing transactions
6. Direction (income vs expense) resolved, then the transaction is saved

**Bank SMS flow:**
1. Raw SMS text pre-processed with regex into hints (amount, date, card last-4, direction)
2. Cleaned text sent to **Groq Text** for structured extraction
3. The keyword hint and the AI's answer are cross-checked; a disagreement forces review

**Deciding income vs expense**

The AI infers the direction from the input and returns `type`, `typeConfidence` and a
`directionEvidence` string quoting what it relied on. `services/direction.js` then:

- honours an explicit user override above everything else;
- auto-files the transaction as `confirmed` when confidence is at or above
  `AI_TYPE_CONFIDENCE_THRESHOLD` (default `0.7`);
- holds anything less certain — low confidence, a missing `type`, or a keyword hint that
  contradicts the AI — as `needs_review`.

A `needs_review` transaction keeps the AI's best guess but is **excluded from dashboard
totals** until the user confirms or flips it in one tap from the Transactions tab. An absent
`type` is never silently filed as an expense.

**Scan statuses:** `queued` → `processing` → `success` / `needs_review` / `failed` / `duplicate`

`needs_review` covers two cases: the parse failed (no transaction is created — retry via
reprocess), and the parse succeeded but the direction is uncertain (a transaction exists and
is waiting to be confirmed).

The worker retries up to 3 attempts before marking a receipt as `failed`. Stale locks (older than 10 minutes) are automatically recovered.

---

## Database Schema

8 core tables:

| Table | Purpose |
|---|---|
| `users` | Account credentials, profile (email, name, currency, timezone), and exchange rates |
| `refresh_tokens` | Hashed JWT refresh tokens with IP/user-agent tracking |
| `password_reset_tokens` | Single-use reset tokens (1-hour expiry) |
| `sources` | Seeded payment sources: Card, Cash, Online |
| `categories` | Default + user-created categories (emoji, color) |
| `receipts` | Uploaded scans and their processing status |
| `transactions` | Core ledger — linked to category, source, and optionally a receipt |
| `loans` | Money lent to / borrowed from friends and relatives (PKR only) |
| `loan_payments` | Repayments against a loan, optionally linked to a transaction |
| `budgets` | Overall and per-category monthly budget limits |

Key relationships: `transactions` → `categories`, `transactions` → `sources`, `transactions` → `receipts` (nullable, for AI-parsed entries), `budgets` → `categories` (nullable, for overall budgets), `loan_payments` → `loans`, `transactions` → `loans` (nullable, for loan money movement). Money is stored as `numeric(14,2)`; all timestamps are `timestamptz`.

### Loan tracking

Loans record money lent to or borrowed from friends and relatives. Two rules make the
numbers trustworthy:

- **A loan is not a transaction.** Lending converts cash into a receivable and borrowing
  creates a liability, so neither is income or expense. The cash movement is still written
  as a real transaction carrying a `kind` marker, and every reported total excludes rows
  where `kind` is set — so lending never inflates your spending.
- **The balance is derived, never stored**: `principal − SUM(payments)`, floored at zero.
  Open/settled follows from it. Repaying more than is owed settles the loan and reports the
  excess as a surplus (a gift, tip or refund) rather than failing.

Removing a loan hides it and deletes only the transactions it created. It also stops counting
toward what you owe or are owed, so the dashboard reflects the removal straight away — but its
repayments are kept on record. People are grouped by normalised name, so there is no people
table yet and two different people sharing a name would merge.

In the app this is the **Loans** screen, which has two tabs: **Loans** (the active list,
filterable to *owed to me* / *I owe*) and **By person** (each person's they-owe / I-owe / net
standing). They are separate tabs because the summary aggregates by person while the list is
per loan, and one screen carrying both makes you work out which block answers your question.
Each loan opens a detail screen with its repayment timeline, and a **Loans section on the
dashboard** shows owed-to-me and I-owe underneath the income/expense/balance tiles, with an
"Overdue: Ali, +1 more" line only when something is actually late. Loans are PKR-only; the
dashboard converts to your base currency when a PKR exchange rate is set.

---

## Testing

```bash
cd backend
npm test   # Vitest + Supertest
```

Coverage: auth flows (register, login, refresh, password reset), transaction CRUD/filtering, dashboard summary/chart calculations, worker job processing (queue claiming, parsing, dedup), loan CRUD/repayments/overpayment and the report-isolation guarantee that loan money movements never reach income or expense.

---

## Roadmap

- [ ] HTTPS + production deployment setup (nginx + certbot)
- [ ] CI/CD pipeline
- [ ] Docker support
- [ ] iOS support
- [ ] Recurring transactions (subscriptions, rent, salaries)
- [ ] CSV / PDF export
- [ ] Push notifications for budget alerts
- [ ] Cloud backup (Google Drive / similar)

---

## License

No license is currently specified for this project.
