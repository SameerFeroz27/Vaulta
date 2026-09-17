# Valuta — Product Vision

---

## Briefing

**Vision:** Valuta makes personal finance tracking effortless by turning the things you already do — snapping receipts, receiving bank SMS alerts — into a complete, organized financial picture. No manual data entry. No spreadsheets. Just clarity.

**Core value proposition:** Automate financial data capture through AI, so tracking money costs less effort than ignoring it.

---

## 1. The Problem

Manual finance tracking fails because it requires too much discipline at too many moments:

- You get a receipt — you lose it, ignore it, or forget to log it.
- Your bank sends an SMS — you read it and move on.
- You try a spreadsheet — it works for two weeks, then falls behind.
- Apps exist, but they still require you to type in every transaction.

The result: most people have a vague, not a clear, sense of where their money goes. Vague awareness doesn't change behavior. Clear data does.

This is especially true in cash-heavy, SMS-banking markets like Pakistan, where formal bank app integrations are limited and most transaction evidence exists only as a paper receipt or a text message.

---

## 2. The Solution

Valuta intercepts money evidence at the source — before it disappears:

| Channel | How Valuta Captures It |
|---|---|
| Physical receipts | Photograph → AI vision extracts merchant, amount, date, category |
| Bank SMS alerts | Paste text → AI parses amount, merchant, transaction type |
| Manual entry | Simple form for cash transactions with no paper trail |
| Analytics | Dashboard shows spending by category, trend over time, budget burn |

The system works even when AI fails — Tesseract OCR provides a fallback for receipt scanning when the Groq Vision API is unavailable or returns poor results.

---

## 3. Target Audience

**Primary user:** An individual in Pakistan (or similar market) who:
- Banks via SMS alerts rather than a full app integration.
- Mixes cash, card, and online payments across their day.
- Wants to understand their spending but won't maintain a manual log.
- Is comfortable enough with their phone to photograph a receipt.

**Default configuration:**
- Currency: PKR (Pakistani Rupee), USD(US Dollar), EUR(Euro)
- Locale: Asia/Karachi timezone
- Language: English

---

## 4. Core Principles

### Privacy-First
- All data stays on the user's own server (self-hosted backend).
- No third-party analytics or ad tracking.
- JWT tokens are short-lived and rotated. Passwords are bcrypt-hashed.

### Automation Over Discipline
- The system should do the work. A user who uploads a receipt and walks away should return to a categorized, logged transaction — no follow-up required.

### Simplicity
- Every screen should have one clear purpose.
- No feature should require a tutorial to understand.
- Defaults should be correct for the target user without configuration.

### Accuracy With Graceful Degradation
- AI is the primary path. OCR is the fallback. Manual override is always available.
- Duplicate detection (via hash comparison) prevents the same transaction from being logged twice regardless of source.

---

## 5. Feature Walkthrough

### Authentication
Users register with name, email, and password. Login returns an access token (short-lived) and a refresh token (stored server-side). The app silently refreshes sessions so users are never kicked out unexpectedly. Logout revokes the refresh token immediately.

### Dashboard
The home screen surfaces what matters most:
- **Net balance** for the current period
- **Total income vs. total expenses**
- **Spending by category** (visual breakdown)
- **Daily/weekly trend** chart

The period is selectable (this week, this month, custom range).

### Transactions
A filterable, searchable list of all transactions — manual, receipt-sourced, or SMS-sourced. Each transaction shows amount, category, date, payment method, and source. Users can edit or delete any entry. Creating a transaction manually takes under 30 seconds.

### Receipt Scanning
1. User photographs a receipt in-app.
2. Image uploads to the backend.
3. Worker picks it up asynchronously — calls Groq Vision API.
4. Extracted fields (merchant, amount, date, category guess) come back as a structured object.
5. Transaction is auto-created. User can review and edit if needed.

If Groq Vision fails, Tesseract OCR is called as a fallback. If both fail, the receipt is marked `failed` and the user is notified.

### Bank SMS Parsing
Users paste raw bank SMS text into the app. The backend sends it to Groq (text model) with a prompt that extracts transaction amount, type (debit/credit), merchant, and date. Result is pre-filled into a transaction form for confirmation. This turns an unstructured SMS into a logged, categorized record in seconds.

### Categories
Users get a set of default categories (Food, Transport, Shopping, etc.) and can create custom ones with an icon and color. Every transaction maps to a category, which powers the dashboard breakdown. Categories can be renamed or deleted (transactions are re-assigned or left uncategorized).

### Budgets
Users set a monthly or weekly spending limit per category. The budget screen shows:
- Budget amount
- Amount spent so far
- Remaining balance (with visual progress bar)
- Over-budget warning when the limit is exceeded

### Settings
- Update profile (name, email)
- Change password
- Configure network base URL (for switching between emulator and real device)
- View app version

---

## 6. Technical Vision

Every technology choice was made to minimize operational complexity for a solo developer or small team.

| Choice | Reason |
|---|---|
| **Flutter** | Single codebase for Android (primary) with future iOS/web path |
| **Node.js + Express** | Low boilerplate, fast iteration, large ecosystem for AI/OCR tooling |
| **PostgreSQL + Drizzle** | Relational integrity for financial data; Drizzle gives type-safe queries without heavy ORM overhead |
| **Groq AI** | Fast inference, supports vision + text models, cost-effective for a personal app |
| **Background worker (custom)** | Avoids the operational complexity of a job queue (Redis, Bull) for a low-volume use case |
| **Tesseract fallback** | Keeps the app functional offline or when the AI API is unavailable |

---

## 7. Security Model

| Concern | Implementation |
|---|---|
| Password storage | bcrypt with work factor ≥ 10 |
| Session tokens | JWT access tokens (~15 min TTL) + refresh tokens (stored in DB, revocable) |
| Token rotation | Refresh token invalidated on logout; new pair issued on each refresh |
| Rate limiting | Applied per route to prevent brute-force on auth endpoints |
| Data isolation | All queries filter by `user_id` — users cannot access each other's data |
| Duplicate prevention | SHA-based `dedup_hash` on transactions prevents re-processing the same receipt or SMS twice |

**Known gaps (to address before production):**
- No HTTPS — run behind nginx + certbot for any public deployment.
- `.env` secrets should be moved to a secrets manager in production.

---

## 8. AI Pipeline

```
Receipt Image Upload
        │
        ▼
  Groq Vision API ──► Success ──► Structured JSON (merchant, amount, date, category)
        │                                │
      Failure                            ▼
        │                     Zod validation → save to DB
        ▼
  Tesseract OCR ──► Raw text ──► Regex pre-processing ──► Best-effort extraction
        │
      Failure
        │
        ▼
  Mark receipt "failed" → notify user
```

```
Bank SMS Text Input
        │
        ▼
  Regex pre-processing (strip noise, identify currency patterns)
        │
        ▼
  Groq Text Model (structured extraction prompt)
        │
        ▼
  Zod schema validation → save to DB (or return parse error)
```

---

## 9. Future Roadmap

These are planned improvements, not yet implemented:

| Priority | Feature | Reason |
|---|---|---|
| High | Real device networking (non-hardcoded URL) | Current `10.0.2.2` only works on Android emulator |
| High | HTTPS support | Required for any production or real-device deployment |
| Medium | Recurring transactions | Subscriptions, rent, salaries — automate repetitive entries |
| Medium | CSV / PDF export | Users need their data in portable formats |
| Medium | Dark mode | Standard expectation in modern mobile apps |
| Low | Multi-currency support | Useful for users who travel or hold foreign accounts |
| Low | iOS support | Flutter supports it; just needs testing + App Store setup |
| Low | Push notifications for budget alerts | Proactive warning before limits are exceeded |
| Low | Google Drive / cloud backup | Avoid data loss if the backend server goes down |
