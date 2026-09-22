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
| `GROQ_VISION_MODEL` | Groq model for image parsing | `llama-3.2-11b-vision-preview` |
| `GROQ_TEXT_MODEL` | Groq model for text/SMS parsing | `llama-3.3-70b-versatile` |
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
6. On success, transaction is auto-confirmed and saved

**Bank SMS flow:**
1. Raw SMS text pre-processed with regex (strips bank-specific boilerplate)
2. Cleaned text sent to **Groq Text** for structured extraction

**Scan statuses:** `queued` → `processing` → `success` / `needs_review` / `failed` / `duplicate`

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
| `budgets` | Overall and per-category monthly budget limits |

Key relationships: `transactions` → `categories`, `transactions` → `sources`, `transactions` → `receipts` (nullable, for AI-parsed entries), `budgets` → `categories` (nullable, for overall budgets). Money is stored as `numeric(14,2)`; all timestamps are `timestamptz`.

---

## Testing

```bash
cd backend
npm test   # Vitest + Supertest
```

Coverage: auth flows (register, login, refresh, password reset), transaction CRUD/filtering, dashboard summary/chart calculations, worker job processing (queue claiming, parsing, dedup).

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
