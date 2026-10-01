# AI-Determined Transaction Direction (Income vs Expense)

Status: **Phases 0–2 implemented.** From/To identity (Phase 3), correction metrics
(Phase 4) and automatic SMS ingestion (Phase 5) are deliberately deferred.

## The problem this fixed

The AI was already asked for a `type` and the worker already had
`userTransactionType || aiData.type || 'expense'` — but the AI's answer was unreachable:

| Layer | Was | Now |
| --- | --- | --- |
| `routes/receipts.js` | Coerced a missing type to `'expense'`, so it was never null | Stores `null` when the client sends no override |
| `receipt_scan_screen.dart` | Toggle defaulted to `'expense'` and was always sent | Three-way **Auto / Expense / Income**, defaults to Auto; Auto sends nothing |
| `worker.js` | `userTransactionType \|\| aiData.type \|\| 'expense'` | `services/direction.js#resolveDirection` |
| `validators/ai-output.schema.js` | `type` defaulted to `'expense'` when absent | Stays `undefined` so it can be routed to review |
| `confidence` | Asked for, parsed, never read | `typeConfidence` drives the auto-file/review gate |

Net effect of the old code: for image receipts the AI's `type` was dead code, and an
unreadable **income** receipt was silently filed as an **expense**.

## Locked decisions

- **Uncertain direction → one-tap review queue**, not silent auto-filing.
- **Scope: Phases 0–2.** From/To identity is deferred.
- **Direction only.** No auto-categorization — a separate feature with its own accuracy risk.

## What shipped

### Backend
- **`services/direction.js`** — `resolveDirection({ aiType, aiTypeConfidence, aiConfidence,
  hintsType, userOverride })` → `{ type, confidence, source, needsReview }`. Precedence:
  explicit override → AI judgement → keyword hint → `expense`. Anything less than confident
  is flagged. Threshold from `AI_TYPE_CONFIDENCE_THRESHOLD` (default `0.7`), read per call.
- **Prompts** ask for `typeConfidence` and `directionEvidence` (the phrase or receipt feature
  justifying the call) and instruct the model to **omit `type` when unsure**.
- **Worker** files `confirmed` or `needs_review`, mirrors the status onto the receipt,
  and persists `typeConfidence` / `typeSource`.
- **Migration `0004_careless_molecule_man.sql`** — adds `transactions.type_confidence` and
  `transactions.type_source` (both nullable, additive).
- **Dashboard** excludes `needs_review` from all seven aggregates via one shared
  `STATUS_EXCLUDED_FROM_TOTALS` fragment, so an unconfirmed guess cannot skew reported totals.
- **Bank SMS hardening** — added `sent`, `you have sent`, `transferred to/from`, `paid to`,
  `pos`, `atm`; replaced `includes()` substring matching (which fired on `unused`/`caused`)
  with word-boundary regexes; signed amounts (`Rs. -1,500`) are now parsed rather than missed,
  and `CR`/`DR` markers are honoured.
- **`routes/transactions.js`** records `typeSource` (`manual` on create, `user_override` when
  an update actually changes the direction, which also clears `typeConfidence`).

### Frontend
- Scan toggle is Auto/Expense/Income with a caption explaining the mode.
- Result card shows AI confidence and the evidence used, so auto-filing is explainable.
- A held-back receipt is resolved **on the scan result screen itself** — one-tap
  **Confirm** / **Change to Income-Expense** — rather than sending the user to another tab.
- `TransactionCard` gained a **Review** badge; previously review rows were indistinguishable.
- `TransactionDetailScreen` gained a review card with the same two actions (using the
  previously-dead `POST /transactions/:id/confirm`).
- `TransactionListScreen` shows a review banner with a live count that filters straight to
  the queue, so held-back rows cannot accumulate invisibly.
- `TransactionFilterSheet` gained a **status** filter (All / Needs Review / Confirmed / Archived).
- `TransactionProvider.confirmTransaction(id)` wraps the existing confirm service call, and
  `pendingReviewCount` is refreshed alongside the list (concurrently, and independently
  failure-tolerant so a count error can never break the list).

### Incidental bug fixed
`TransactionFilterSheet` applied filters through `TransactionFilters.copyWith`, which treats
`null` as "keep the existing value" — so choosing **All** for Type could never clear the
filter. The sheet now constructs the filters explicitly, and the empty state distinguishes
"no transactions yet" from "nothing matches your filters".

### Tests
- `src/tests/direction.test.js` — 19 cases covering override precedence, confidence gating,
  the missing-type path, hint disagreement and threshold configuration.
- `src/tests/fixtures/bank-sms.json` — 16 anonymised Pakistani bank SMS samples with expected
  directions, driven from `worker.test.js`. Includes a `caused`-contains-`used` regression case.
- `worker.test.js` now asserts an absent `type` stays absent, and that the keyword-guessed
  direction is **not** leaked into the AI prompt (otherwise the cross-check is meaningless).
- `dashboard.test.js` proves `needs_review` amounts are excluded from the summary, trend and
  budget spend, and counted again once confirmed.
- `transactions.test.js` covers direction provenance (`manual` / `user_override`, and that a
  client cannot spoof it) plus the review-queue count the UI banner reads.
- `receipts.test.js` is new: the receipts route had no tests, and the dedup query changed.

107 backend tests pass, `flutter analyze` is clean, and the Flutter widget test passes.

## Deferred, with reasons

- **From/To counterparty identity (Phase 3).** Direction for a P2P receipt needs to know which
  party the user is. There are no identity fields today (`users` has only `name`/`email`), and
  resolving it means sending the user's name, phone numbers and wallet handles to Groq — which
  sits awkwardly against the privacy stance in `docs/vision.md`. Needs a product decision.
- **Correction metrics / golden set (Phase 4).** `typeSource` now records corrections, so
  accuracy can be measured later without further schema work.
- **Automatic Android SMS ingestion (Phase 5).** Separate scope, Play Store policy implications.
- **Auto-categorization.** Not started; note that knowing the direction is a prerequisite,
  since categories are filtered by type.

## Tuning notes

- The `0.7` threshold is a starting guess, not a measured value. Expect visible review items
  until it is tuned against real usage; lower it to review less, raise it to misfile less.
- Receipts queued *before* this change keep `rawPayload.transactionType = 'expense'` and will
  still override the AI. Drain the queue or accept that those specific rows behave as before.
- `GROQ_TEXT_MODEL` and `GROQ_VISION_MODEL` are the most common cause of a whole job
  failing: a model that is not available for the account returns `404 model_not_found`
  and the receipt is marked `failed` after its retries. Both were verified against the
  live API: `openai/gpt-oss-120b` (text) and `qwen/qwen3.8-27b` (vision). Several earlier
  failures in this database came from retired names (`llama-3.3-70b-versatile`,
  `groq/compound`), so re-check `GET /v1/models` whenever a job fails this way.
