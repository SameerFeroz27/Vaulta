# Vaulta — Product Vision

> **Note:** This document captures the *why* behind Vaulta — the problem, audience, design principles, and rationale.
> For technical details (features, setup, API reference, AI pipeline, roadmap), see the [README](../README.md).

---

## Briefing

**Vision:** Vaulta makes personal finance tracking effortless by turning the things you already do — snapping receipts, receiving bank SMS alerts — into a complete, organized financial picture. No manual data entry. No spreadsheets. Just clarity.

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

Vaulta intercepts money evidence at the source — before it disappears:

| Channel | How Vaulta Captures It |
|---|---|
| Physical receipts | Photograph → AI vision extracts merchant, amount, date, category |
| Online receipts | Screenshot → AI vision parses digital receipts (Daraz, Foodpanda, banking apps) |
| Bank SMS alerts | Paste text → AI parses amount, merchant, transaction type |
| Manual entry | Simple form for cash transactions with no paper trail |
| Analytics | Dashboard shows spending by category, trend over time, budget burn |
| Multi-currency | Per-transaction currency selection; live exchange rates auto-fetched; dashboard converts all totals to a base currency |

The system works even when AI fails — Tesseract OCR provides a fallback for receipt scanning when the Groq Vision API is unavailable or returns poor results.

---

## 3. Target Audience

**Primary user:** An individual in Pakistan (or similar market) who:
- Banks via SMS alerts rather than a full app integration.
- Mixes cash, card, and online payments across their day.
- Wants to understand their spending but won't maintain a manual log.
- Is comfortable enough with their phone to photograph a receipt.

**Default configuration:**
- Currency: PKR (Pakistani Rupee) — 8 others supported (USD, EUR, GBP, AED, INR, SAR, CAD, AUD) with live exchange rate conversion
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

## 5. Technical Rationale

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

## 6. Security Model

| Concern | Implementation |
|---|---|
| Password storage | bcrypt with 12 salt rounds |
| Password reset | 6-digit OTP emailed via SMTP; OTP hashed (SHA-256), 1-hour expiry, single-use |
| Session tokens | JWT access tokens (15 min TTL) + refresh tokens (stored hashed in DB, revocable); both carry a unique `jti` claim |
| Token rotation | Refresh token invalidated on logout; new pair issued on each refresh; reuse detection revokes all user tokens |
| Rate limiting | Applied per route — 30 req/15 min on auth, 5 req/hour on password reset |
| Data isolation | All queries filter by `user_id` — users cannot access each other's data |
| Duplicate prevention | SHA-256 `fileHash` on receipts and amount+date check on transactions prevents re-processing |

**Known gaps (to address before production):**
- No HTTPS — run behind nginx + certbot for any public deployment.
- `.env` secrets should be moved to a secrets manager in production.
