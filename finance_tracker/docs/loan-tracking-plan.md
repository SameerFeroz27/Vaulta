# Loan Tracking (Lending & Borrowing) — Plan

Status: **proposed, not started.** Scope: friends and relatives, informal lending —
the Urdu/`udhaar` pattern, not a lending business.

## 1. Verdict: add it to this app, do not build a new one

Reasons, in order of weight:

1. **The integration is the feature.** "I am owed 120k and I owe 80k, net +40k" only means
   something next to your income and spending. Two apps would give two half-truths.
2. **Almost everything is already built.** Auth, users, currency + exchange rates, sources,
   categories, budgets, transactions, receipts, dashboard analytics, Zod validators, the
   response envelope, a test suite. A new app rebuilds all of it and re-earns none of it.
3. **Cost.** Here it is one migration, two tables, a provider and four screens. A new app
   is weeks before the first useful screen.
4. **Same audience, same data.** Money lent to a relative is household finance, not a
   separate activity.

**When a new app *would* be right:** if the target is a lending *business* — interest or EMI
schedules, many borrowers, statements, penalties, KYC. That is a different product. If this
ever grows that way, the `loans` table below is still the right foundation to extract.

## 2. Your instinct is right, with one correction

A fourth screen plus dashboard surfacing is the correct shape. What is missing is the
decision in section 3 — get it wrong and your existing dashboard starts lying to you.

## 3. The decision that determines everything: a loan is not a transaction

Consider lending Ali 50,000:

- Record it as an **expense** → your dashboard shows 50,000 of spending that never happened.
  Budgets, category breakdowns and the trend chart are all wrong.
- Record **nothing** → your dashboard shows nothing while 50,000 left your account. Also wrong.

Lending converts cash into a **receivable**; borrowing creates a **liability**. Neither is
income or expense.

**The model:** a loan is its own entity, and each cash movement is a transaction *linked*
to it. So:

- `loans` — the obligation (who, how much, which way, when due).
- `loan_payments` — repayments, each optionally linked to a real transaction.
- `transactions.kind` — marks a transaction as loan-related so the dashboard can exclude it
  from income/expense while still counting it as cash movement.

Your dashboard already has exactly this pattern: `STATUS_EXCLUDED_FROM_TOTALS` in
`routes/dashboard.js` excludes `needs_review` from all seven aggregates. Extending that one
shared fragment is cheap, which is why this is affordable now and awkward to retrofit later.

Do this in Phase 1 (so data is captured correctly from day one), not later.

## 4. Data model

### `loans`
| Column | Type | Notes |
| --- | --- | --- |
| `id` | serial PK | |
| `user_id` | int FK → users | cascade |
| `counterparty` | text | the friend/relative's name |
| `direction` | text | `lent` (they owe me) or `borrowed` (I owe them) |
| `principal` | numeric(14,2) | original amount |
| `currency` | char(3) | matches transactions |
| `issue_date` | date | when the money moved |
| `due_date` | date, null | optional — informal loans often have none |
| `status` | text | `open`, `settled`, `written_off` |
| `interest_rate` | numeric, null | see the note in section 7 |
| `notes` | text, null | |
| `created_at` / `updated_at` | timestamptz | |

### `loan_payments`
| Column | Type | Notes |
| --- | --- | --- |
| `id` | serial PK | |
| `loan_id` | int FK → loans | cascade |
| `user_id` | int FK → users | cascade; keeps queries user-scoped |
| `amount` | numeric(14,2) | |
| `payment_date` | date | |
| `transaction_id` | int FK → transactions, null | the cash movement, when recorded |
| `idempotency_key` | text, null | reuse the existing transactions pattern |
| `note` | text, null | |
| `created_at` | timestamptz | |

**Outstanding balance is computed, never stored:** `principal − SUM(payments)`. Same formula
for both directions — `direction` only decides the label and sign. Computing avoids drift and
makes concurrent repayments safe. At personal scale this is a trivial `SUM`.

**Indexes:** `(user_id, status)`, `(user_id, due_date)` on loans; `(loan_id)` on payments.

## 5. Screens

**Tab 4 — Loans** (adds to `main.dart`'s `screens` list and `BottomNavigationBar.items`;
`type: fixed` already supports 4–5 tabs).

1. **Loan list** — segmented filter *All / Owed to me / I owe*. Each row: name, outstanding
   amount, progress (`paid of total`), due date with an overdue badge. Sorted overdue-first,
   then by due date. Empty state distinguishes "no loans" from "none match this filter".
2. **Loan detail** — outstanding amount as the hero, progress bar, direction and dates, a
   payment timeline, and actions: *Record payment*, *Edit*, *Write off*, share a reminder.
3. **Add / edit form** — person, direction, amount, currency, issue date, optional due date,
   notes, and a toggle *"also record this in my transactions"* (default on).

**Dashboard additions**

- A **Loans card**: owed to me / I owe / net position, tapping through to the Loans tab.
- An **overdue** indicator when any loan is past its due date.

## 6. Integrity rules — the specific failure modes to design out

"Flawless" is not achievable in a plan; what is achievable is naming the edge cases and
handling them. These are the ones this feature actually hits:

1. **Overpayment** — reject a repayment larger than the outstanding balance rather than
   letting the balance go negative. If advance payment is wanted, make it explicit.
2. **Auto-settle at zero**, and **un-settle when a repayment is deleted** — derive status from
   the balance so it can never contradict the numbers.
3. **Bad debt needs a terminal state.** `written_off` exists because some money is never
   coming back. Without it, one unpaid loan sits in "owed to me" forever and the total stops
   being trustworthy.
4. **Deleting a repayment** must restore the balance and decide the fate of the linked
   transaction (delete it too, or unlink). Pick one and say so in the UI.
5. **Currency.** A USD loan cannot be summed with PKR without conversion. Use the existing
   `users.exchange_rates` for the dashboard total, and display each loan in its own currency.
6. **Double-tap on "Record payment"** must not create two repayments — reuse the
   `idempotency_key` pattern already used by transactions.
7. **Loan transactions must stay out of budgets.** A repayment is settling a debt, not
   consumption; if it leaks into budget spend, budgets break.
8. **Dates are date-only** (`date`, not `timestamptz`) — a loan is due "on the 5th", with no
   time-of-day semantics.

## 7. Two domain notes specific to this market

- **Interest between individuals is religiously sensitive in Pakistan** (riba). Default
  `interest_rate` to 0 and keep it out of the basic UI. If it is ever added, make it opt-in
  and clearly labelled rather than a default field.
- **Chasing repayment happens over WhatsApp.** A "share reminder" action is the highest-value
  nicety here, but it is deliberately deferred — it needs no schema and can come later.

## 8. Phased plan

### Phase 1 — Data and core tracking
- [ ] Migration: `loans`, `loan_payments`, and `transactions.kind` + `transactions.loan_id`
- [ ] Zod validators (`loan.schema.js`, following `transaction.schema.js` style)
- [ ] Routes: `GET/POST /api/loans`, `GET/PUT/DELETE /api/loans/:id`,
      `POST/DELETE /api/loans/:id/payments`, `GET /api/loans/summary`
- [ ] Balance + status rules in one pure module (`services/loan-balance.js`) so they are
      unit-testable without a database
- [ ] `LoanProvider` + `LoanService` (mirroring `TransactionProvider` / `TransactionService`)
- [ ] Screens: loan list, loan detail, add/edit form; wire the 4th tab in `main.dart`

### Phase 2 — Ledger linkage
- [ ] Recording a disbursement or repayment optionally creates a transaction with the right
      `kind` and `loan_id`
- [ ] Extend `STATUS_EXCLUDED_FROM_TOTALS` so loan transactions stay out of income/expense
      while remaining visible as cash movements
- [ ] Confirm budgets ignore loan transactions

### Phase 3 — Dashboard surfacing
- [ ] Loans card (owed to me / I owe / net), converted via `exchange_rates`
- [ ] Overdue indicator
- [ ] Tap-through to the Loans tab

### Phase 4 — Deferred, but designed for
- [ ] Share-a-reminder message
- [ ] A `people`/contacts table (dedupe names, attach phone numbers)
- [ ] Interest, if ever needed
- [ ] Attachments (a photo of a handwritten IOU)
- [ ] Per-person history and analytics

## 9. Verification

The test suite is the reason this can be built safely. Add:

- Unit tests for the balance rules: partial repayments, exact settle, overpayment rejection,
  write-off, un-settle after deleting a repayment.
- API tests for the CRUD and payment routes.
- A dashboard test asserting loan transactions do **not** move `totalIncome`/`totalExpense` —
  mirroring the existing `needs_review` exclusion test, which is the same failure mode.

## 10. What I would not do

- Do not model a loan as an expense or income category. This is the one mistake that silently
  corrupts every existing report.
- Do not store a mutable `balance` column alongside the payments. Two sources of truth drift.
- Do not add interest to the basic UI.
- Do not build a separate app for friends-and-relatives lending.
